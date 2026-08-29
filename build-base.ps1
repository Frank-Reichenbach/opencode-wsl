# build-base.ps1
#
# Builds the pre-baked WSL base image with all tools installed.
# Run this once. After it completes, use new-project.ps1 to create project instances.
#
# Usage: .\build-base.ps1
#        .\build-base.ps1 -BaseImage C:\elsewhere\opencode-base.tar.gz

param(
    [string]$BaseImage = "C:\wsl\base\opencode-base.tar.gz"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ChecksumHelper = Join-Path $ScriptDir 'scripts/RootfsChecksum.ps1'
$WslHelper = Join-Path $ScriptDir 'scripts/WslHelpers.ps1'
. $ChecksumHelper
. $WslHelper

# -- Derived paths -------------------------------------------------------------
$BaseDir      = Split-Path -Parent $BaseImage
$BuilderName  = "opencode-wsl-builder"

# -- Pre-flight checks ---------------------------------------------------------

Assert-SafeWindowsDirectory -DirectoryPath $BaseDir > $null

$BuilderDir = Join-Path $env:TEMP $BuilderName

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    throw "WSL is not installed. Install it with: wsl --install"
}

# Canonical distributes Ubuntu 26.04 in WSL's new .wsl image format.
# That format requires WSL 2.4.10 or later.
Assert-WslMinimumVersion

$UbuntuUrl  = "https://releases.ubuntu.com/26.04/ubuntu-26.04-wsl-amd64.wsl"
$UbuntuImage = Join-Path $BaseDir "ubuntu-26.04.wsl"
$ChecksumUrl = "https://releases.ubuntu.com/26.04/SHA256SUMS"
$SourceFile  = ($UbuntuUrl -replace '.+/', '')

# -- Convert Windows path to WSL /mnt/... path --------------------------------
function ConvertTo-WslPath([string]$winPath) {
    $drive = $winPath[0].ToString().ToLower()
    $rest  = $winPath.Substring(2) -replace "\\", "/"
    return "/mnt/$drive$rest"
}

function Get-WslExportFormat([string]$imagePath) {
    $normalizedPath = $imagePath.ToLowerInvariant()

    # Only .tar.gz opts into gzip export; supported image paths are .tar.gz and .tar.
    if ($normalizedPath.EndsWith('.tar.gz')) {
        return 'tar.gz'
    }

    return $null
}

function Assert-WslExportFormatSupport([string]$imagePath) {
    $exportFormat = Get-WslExportFormat $imagePath
    if ($exportFormat -and -not (Test-WslExportFormatSupport)) {
        throw "This WSL version does not support 'wsl --export --format'. Update WSL and try again, or use a .tar base image path."
    }

    return $exportFormat
}

function Get-WslExportFormatProbeText([string]$probePath) {
    return Get-WslCommandOutput -Arguments @('--export', '__opencode_wsl_format_probe__', $probePath, '--format', 'tar.gz')
}

function Test-WslExportFormatSupport {
    $probePath = Join-Path $env:TEMP 'opencode-wsl-format-probe.tar.gz'

    if (Test-Path -LiteralPath $probePath) {
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
    }

    try {
        $probeText = Get-WslExportFormatProbeText $probePath
    }
    finally {
        if (Test-Path -LiteralPath $probePath) {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($probeText -match '\bWSL_E_DISTRO_NOT_FOUND\b') {
        return $true
    }

    if ($probeText -match '\bE_INVALIDARG\b' -or $probeText -match '(?i)command line argument:\s*--format') {
        return $false
    }

    $helpText = Get-WslCommandOutput -Arguments @('--help')
    return $helpText -match '(?i)--format\b'
}

# Wrapper keeps the final move mockable in unit tests.
function Move-WslExportIntoPlace([string]$temporaryPath, [string]$imagePath) {
    Move-Item -LiteralPath $temporaryPath -Destination $imagePath -Force
}

function Export-WslDistroImage([string]$distroName, [string]$imagePath, [AllowNull()][string]$exportFormat) {
    if (-not $PSBoundParameters.ContainsKey('ExportFormat')) {
        $exportFormat = Assert-WslExportFormatSupport -ImagePath $imagePath
    }

    $temporaryImagePath = $imagePath + '.exporting'
    if (Test-Path -LiteralPath $temporaryImagePath) {
        Remove-Item -LiteralPath $temporaryImagePath -Force
    }

    try {
        if ($exportFormat) {
            wsl --export $distroName $temporaryImagePath --format $exportFormat > $null
        } else {
            wsl --export $distroName $temporaryImagePath > $null
        }

        if ($LASTEXITCODE -ne 0) { throw "wsl --export failed with exit code $LASTEXITCODE" }

        Move-WslExportIntoPlace -TemporaryPath $temporaryImagePath -ImagePath $imagePath
    }
    catch {
        if (Test-Path -LiteralPath $temporaryImagePath) {
            Remove-Item -LiteralPath $temporaryImagePath -Force -ErrorAction SilentlyContinue
        }

        throw
    }
}

$WslScriptDir = ConvertTo-WslPath $ScriptDir
$BaseImageExportFormat = Assert-WslExportFormatSupport -ImagePath $BaseImage

# -- Prepare directories ------------------------------------------------------
Write-Host "Creating directories..."
New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null

# -- Clean up any leftover exact builder instance from interrupted runs -------
$existingBuilder = Get-WslDistroName | Where-Object { $_ -eq $BuilderName }
if ($existingBuilder) {
    Write-Host "Removing leftover builder instance '$BuilderName'..."
    wsl --unregister $BuilderName > $null 2>$null
}
if (Test-Path -LiteralPath $BuilderDir) {
    Remove-Item -Recurse -Force -LiteralPath $BuilderDir
}
New-Item -ItemType Directory -Force -Path $BuilderDir | Out-Null

# -- Resolve and verify Ubuntu WSL image --------------------------------------
Write-Host "Resolving published SHA256 checksum..."
try {
    $ExpectedHash = Get-PublishedSha256 -ChecksumUri $ChecksumUrl -FileName $SourceFile
} catch {
    if ($_.Exception.Message -like "Could not find checksum*") {
        throw
    }

    $message = "Could not resolve Canonical's published SHA256 checksum from '$ChecksumUrl'."
    if (Test-Path -LiteralPath $UbuntuImage) {
        $message += " A cached WSL image exists at '$UbuntuImage', but the build will not reuse it without revalidating it against Canonical's published checksum."
    }
    $message += " Check your network connection and try again."
    throw "$message Inner error: $($_.Exception.Message)"
}
$ShouldDownload = $true

if (Test-Path -LiteralPath $UbuntuImage) {
    Write-Host "Verifying cached Ubuntu WSL image: $UbuntuImage"
    $cachedHash = (Get-FileHash -Algorithm SHA256 $UbuntuImage).Hash.ToLower()
    if ($cachedHash -eq $ExpectedHash) {
        Write-Host "  Cached WSL image SHA256 verified: $cachedHash"
        $ShouldDownload = $false
    } else {
        Write-Warning "Cached WSL image checksum mismatch. Re-downloading Canonical's Ubuntu 26.04 LTS WSL image."
        Remove-Item -Force -LiteralPath $UbuntuImage
    }
}

if ($ShouldDownload) {
    Write-Host "Downloading Ubuntu 26.04 LTS WSL image from Canonical..."
    Write-Host "  Source: $UbuntuUrl"
    $tempImage = "$UbuntuImage.download"
    try {
        Invoke-WebRequest -Uri $UbuntuUrl -OutFile $tempImage -UseBasicParsing

        Write-Host "  Verifying SHA256 checksum..."
        $actualHash = (Get-FileHash -Algorithm SHA256 $tempImage).Hash.ToLower()
        if ($actualHash -ne $ExpectedHash) {
            throw "SHA256 mismatch: expected $ExpectedHash, got $actualHash. Download may be corrupted."
        }
        Write-Host "  SHA256 verified: $actualHash"

        Move-Item -Force $tempImage $UbuntuImage
        Write-Host "  Saved to: $UbuntuImage"
    } catch {
        if (Test-Path -LiteralPath $tempImage) { Remove-Item -LiteralPath $tempImage }
        throw
    }
}

# -- Build base image (with cleanup on failure) -------------------------------
try {
    # -- Import builder instance ----------------------------------------------
    Write-Host "Importing builder instance '$BuilderName'..."
    wsl --import $BuilderName $BuilderDir $UbuntuImage --version 2 > $null
    if ($LASTEXITCODE -ne 0) { throw "wsl --import failed with exit code $LASTEXITCODE" }

    # -- Copy bootstrap files into the instance --------------------------------
    Write-Host "Copying bootstrap files..."
    # Escape single quotes for safe embedding in bash single-quoted strings
    $SafeWslDir = $WslScriptDir -replace "'", "'\\''"
    wsl -d $BuilderName -- bash -c "cp '$SafeWslDir/bootstrap/install.sh' /tmp/install.sh && cp '$SafeWslDir/config/opencode.json' /tmp/opencode.json && chmod +x /tmp/install.sh"
    if ($LASTEXITCODE -ne 0) { throw "Failed to copy bootstrap files" }

    # -- Run bootstrap ---------------------------------------------------------
    Write-Host ""
    Write-Host "Running bootstrap (takes several minutes)..."
    Write-Host "----------------------------------------------"
    wsl -d $BuilderName -- bash /tmp/install.sh
    if ($LASTEXITCODE -ne 0) { throw "Bootstrap script failed with exit code $LASTEXITCODE" }
    Write-Host "----------------------------------------------"

    # -- Export base image -----------------------------------------------------
    Write-Host ""
    Write-Host "Exporting base image..."
    Export-WslDistroImage -DistroName $BuilderName -ImagePath $BaseImage -ExportFormat $BaseImageExportFormat
    Write-Host "  Saved to: $BaseImage"
}
finally {
    # -- Clean up builder (runs even on failure) -------------------------------
    Write-Host "Cleaning up builder instance..."
    $existing = Get-WslDistroName | Where-Object { $_ -eq $BuilderName }
    if ($existing) {
        wsl --unregister $BuilderName > $null 2>$null
    }
    if (Test-Path -LiteralPath $BuilderDir) {
        Remove-Item -Recurse -Force -LiteralPath $BuilderDir
    }

    # Remove OS artifacts left by wsl --import
    $dvcDir = Join-Path $env:LOCALAPPDATA "Temp\WSLDVCPlugin\$BuilderName"
    if (Test-Path -LiteralPath $dvcDir) { Remove-Item -Recurse -Force -LiteralPath $dvcDir }

    $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$BuilderName"
    if (Test-Path -LiteralPath $startMenuDir) { Remove-Item -Recurse -Force -LiteralPath $startMenuDir }
}

Write-Host ""
Write-Host "Done! Base image ready at: $BaseImage"
Write-Host "Run .\new-project.ps1 <project-name> to create a new project instance."
