# new-project.ps1
#
# Creates a new isolated WSL project instance from the pre-baked base image.
# Run build-base.ps1 first if you haven't already.
#
# Usage: .\new-project.ps1 my-project-name
#        .\new-project.ps1 -ProjectName my-api -ProjectDir C:\elsewhere
#        .\new-project.ps1              (will prompt for name)

param(
    [string]$ProjectName = "",
    [string]$ProjectDir  = "C:\wsl",
    [string]$BaseImage   = "C:\wsl\base\opencode-base.tar.gz"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WslHelper = Join-Path $ScriptDir 'scripts/WslHelpers.ps1'
. $WslHelper

# -- Input validation ---------------------------------------------------------
if ($PSBoundParameters.ContainsKey('ProjectName') -and -not $ProjectName) {
    throw "Project name cannot be empty."
}

if (-not $ProjectName) {
    try {
        $ProjectName = Read-Host "Project name"
    } catch {
        throw "Project name is required. Pass -ProjectName when running non-interactively."
    }
}

if (-not $ProjectName) {
    throw "Project name is required."
}

if ($ProjectName -notmatch '^[a-zA-Z0-9][-a-zA-Z0-9]*$') {
    throw "Invalid project name '$ProjectName'. Use only letters, numbers, and hyphens. Must start with a letter or number."
}

Assert-SafeWindowsDirectory -DirectoryPath $ProjectDir > $null

# Normalize trailing backslash so paths are clean
$ProjectDir = $ProjectDir.TrimEnd('\')

$InstanceName = "ubuntu-$ProjectName"
$InstanceDir  = "$ProjectDir\$ProjectName"

# -- Pre-flight checks --------------------------------------------------------
if (-not (Test-Path -LiteralPath $BaseImage)) {
    throw @"
Base image not found at: $BaseImage

Run .\build-base.ps1 first to build the base image.
"@
}

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    throw "WSL is not installed. Install it with: wsl --install"
}

$existing = Get-WslDistroName | Where-Object { $_ -eq $InstanceName }

if ($existing) {
    throw @"
WSL instance '$InstanceName' already exists. Choose a different name or unregister it first:
  wsl --unregister $InstanceName
"@
}

# -- Create project instance --------------------------------------------------
$createdDir = $false
if (Test-Path -LiteralPath $InstanceDir) {
    throw "Directory '$InstanceDir' already exists. Remove it first or choose a different name."
} else {
    New-Item -ItemType Directory -Force -Path $InstanceDir | Out-Null
    $createdDir = $true
}

Write-Host "Creating '$InstanceName' at $InstanceDir ..."
wsl --import $InstanceName $InstanceDir $BaseImage --version 2 > $null
$importExitCode = $LASTEXITCODE
if ($importExitCode -ne 0) {
    $existing = Get-WslDistroName | Where-Object { $_ -eq $InstanceName }
    if ($existing) {
        wsl --unregister $InstanceName > $null 2>$null
        if (Get-WslDistroName | Where-Object { $_ -eq $InstanceName }) {
            Write-Warning "Failed to unregister leftover WSL instance '$InstanceName'."
        }
    }

    if ($createdDir -and (Test-Path -LiteralPath $InstanceDir)) {
        Remove-Item -Recurse -Force -LiteralPath $InstanceDir -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $InstanceDir) {
            Write-Warning "Failed to remove leftover project directory '$InstanceDir'."
        }
    }

    if ($env:LOCALAPPDATA) {
        $dvcDir = Join-Path $env:LOCALAPPDATA "Temp\WSLDVCPlugin\$InstanceName"
        if (Test-Path -LiteralPath $dvcDir) {
            Remove-Item -Recurse -Force -LiteralPath $dvcDir -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $dvcDir) {
                Write-Warning "Failed to remove leftover WSL DVC artifact '$dvcDir'."
            }
        }
    }

    if ($env:APPDATA) {
        $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$InstanceName"
        if (Test-Path -LiteralPath $startMenuDir) {
            Remove-Item -Recurse -Force -LiteralPath $startMenuDir -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $startMenuDir) {
                Write-Warning "Failed to remove leftover Start Menu artifact '$startMenuDir'."
            }
        }
    }

    throw "wsl --import failed with exit code $importExitCode"
}

Write-Host ""
Write-Host "Done! '$InstanceName' is ready."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open the instance:"
Write-Host "       wsl -d $InstanceName"
Write-Host ""
Write-Host "  2. On first use, authenticate with your AI provider:"
Write-Host "       opencode auth login"
Write-Host "     Follow the prompts to complete login (once per instance)."
Write-Host ""
Write-Host "  3. Start opencode:"
Write-Host "       opencode"
Write-Host ""
Write-Host "  Or connect via VS Code:"
Write-Host "     Ctrl+Shift+P -> 'Remote-WSL: Connect to WSL using Distro...' -> $InstanceName"
