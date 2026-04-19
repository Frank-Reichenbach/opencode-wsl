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
. $ChecksumHelper

# -- Derived paths -------------------------------------------------------------
$BaseDir      = Split-Path -Parent $BaseImage
$BuilderName  = "opencode-wsl-builder"

# -- Pre-flight checks ---------------------------------------------------------

# Guard against dangerous base directory
$resolvedBase = [System.IO.Path]::GetFullPath($BaseDir)
$sysRoot = if ($env:SystemRoot) { $env:SystemRoot.TrimEnd('\') + '\' } else { $null }
if ($resolvedBase -match '^[A-Za-z]:\\?$' -or ($sysRoot -and ($resolvedBase.TrimEnd('\') + '\').StartsWith($sysRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
    Write-Error "Refusing to use '$resolvedBase' -- path is a drive root or system directory."
    exit 1
}

$BuilderDir = Join-Path $env:TEMP $BuilderName

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "WSL is not installed. Install it with: wsl --install"
    exit 1
}

$UbuntuUrl  = "https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz"
$UbuntuTar  = Join-Path $BaseDir "ubuntu-24.04.tar.gz"
$ChecksumUrl = ($UbuntuUrl -replace '/[^/]+$', '/SHA256SUMS')
$SourceFile  = ($UbuntuUrl -replace '.+/', '')

# -- Convert Windows path to WSL /mnt/... path --------------------------------
function ConvertTo-WslPath([string]$winPath) {
    $drive = $winPath[0].ToString().ToLower()
    $rest  = $winPath.Substring(2) -replace "\\", "/"
    return "/mnt/$drive$rest"
}

$WslScriptDir = ConvertTo-WslPath $ScriptDir

# -- Prepare directories ------------------------------------------------------
Write-Host "Creating directories..."
New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null

# -- Clean up any leftover exact builder instance from interrupted runs -------
$existingBuilder = wsl --list --quiet 2>$null |
    ForEach-Object { $_ -replace "`0", "" } |
    Where-Object { $_.Trim() -eq $BuilderName }
if ($existingBuilder) {
    Write-Host "Removing leftover builder instance '$BuilderName'..."
    wsl --unregister $BuilderName > $null 2>$null
}
if (Test-Path $BuilderDir) {
    Remove-Item -Recurse -Force $BuilderDir
}
New-Item -ItemType Directory -Force -Path $BuilderDir | Out-Null

# -- Resolve and verify Ubuntu rootfs -----------------------------------------
Write-Host "Resolving published SHA256 checksum..."
try {
    $ExpectedHash = Get-PublishedSha256 -ChecksumUri $ChecksumUrl -FileName $SourceFile
} catch {
    if ($_.Exception.Message -like "Could not find checksum*") {
        throw
    }

    $message = "Could not resolve Canonical's published SHA256 checksum from '$ChecksumUrl'."
    if (Test-Path $UbuntuTar) {
        $message += " A cached rootfs exists at '$UbuntuTar', but the build will not reuse it without revalidating it against Canonical's published checksum."
    }
    $message += " Check your network connection and try again."
    throw "$message Inner error: $($_.Exception.Message)"
}
$ShouldDownload = $true

if (Test-Path $UbuntuTar) {
    Write-Host "Verifying cached Ubuntu rootfs: $UbuntuTar"
    $cachedHash = (Get-FileHash -Algorithm SHA256 $UbuntuTar).Hash.ToLower()
    if ($cachedHash -eq $ExpectedHash) {
        Write-Host "  Cached rootfs SHA256 verified: $cachedHash"
        $ShouldDownload = $false
    } else {
        Write-Warning "Cached rootfs checksum mismatch. Re-downloading current Canonical rootfs."
        Remove-Item -Force $UbuntuTar
    }
}

if ($ShouldDownload) {
    Write-Host "Downloading Ubuntu 24.04 WSL rootfs from Canonical..."
    Write-Host "  Source: $UbuntuUrl"
    $tempTar = "$UbuntuTar.download"
    try {
        Invoke-WebRequest -Uri $UbuntuUrl -OutFile $tempTar -UseBasicParsing

        Write-Host "  Verifying SHA256 checksum..."
        $actualHash = (Get-FileHash -Algorithm SHA256 $tempTar).Hash.ToLower()
        if ($actualHash -ne $ExpectedHash) {
            throw "SHA256 mismatch: expected $ExpectedHash, got $actualHash. Download may be corrupted."
        }
        Write-Host "  SHA256 verified: $actualHash"

        Move-Item -Force $tempTar $UbuntuTar
        Write-Host "  Saved to: $UbuntuTar"
    } catch {
        if (Test-Path $tempTar) { Remove-Item $tempTar }
        throw
    }
}

# -- Build base image (with cleanup on failure) -------------------------------
try {
    # -- Import builder instance ----------------------------------------------
    Write-Host "Importing builder instance '$BuilderName'..."
    wsl --import $BuilderName $BuilderDir $UbuntuTar --version 2 > $null
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
    if (Test-Path $BaseImage) { Remove-Item $BaseImage }
    wsl --export $BuilderName $BaseImage > $null
    if ($LASTEXITCODE -ne 0) { throw "wsl --export failed with exit code $LASTEXITCODE" }
    Write-Host "  Saved to: $BaseImage"
}
finally {
    # -- Clean up builder (runs even on failure) -------------------------------
    Write-Host "Cleaning up builder instance..."
    $existing = wsl --list --quiet 2>$null | ForEach-Object { $_ -replace "`0", "" } | Where-Object { $_.Trim() -eq $BuilderName }
    if ($existing) {
        wsl --unregister $BuilderName > $null 2>$null
    }
    if (Test-Path $BuilderDir) {
        Remove-Item -Recurse -Force $BuilderDir
    }

    # Remove OS artifacts left by wsl --import
    $dvcDir = Join-Path $env:LOCALAPPDATA "Temp\WSLDVCPlugin\$BuilderName"
    if (Test-Path $dvcDir) { Remove-Item -Recurse -Force $dvcDir }

    $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$BuilderName"
    if (Test-Path $startMenuDir) { Remove-Item -Recurse -Force $startMenuDir }
}

Write-Host ""
Write-Host "Done! Base image ready at: $BaseImage"
Write-Host "Run .\new-project.ps1 <project-name> to create a new project instance."
