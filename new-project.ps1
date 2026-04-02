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

# ── Input validation ──────────────────────────────────────────────────────────
if (-not $ProjectName) {
    $ProjectName = Read-Host "Project name"
}

if (-not $ProjectName) {
    Write-Error "Project name is required."
    exit 1
}

if ($ProjectName -notmatch '^[a-zA-Z0-9][-a-zA-Z0-9]*$') {
    Write-Error "Invalid project name '$ProjectName'. Use only letters, numbers, and hyphens. Must start with a letter or number."
    exit 1
}

# Guard against dangerous project directory (resolve before TrimEnd so C:\ is caught)
$resolvedProjectDir = [System.IO.Path]::GetFullPath($ProjectDir)
$sysRoot = if ($env:SystemRoot) { $env:SystemRoot.TrimEnd('\') + '\' } else { $null }
if ($resolvedProjectDir -match '^[A-Za-z]:\\?$' -or ($sysRoot -and ($resolvedProjectDir.TrimEnd('\') + '\').StartsWith($sysRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
    Write-Error "Refusing to use '$resolvedProjectDir' — path is a drive root or system directory."
    exit 1
}

# Normalize trailing backslash so paths are clean
$ProjectDir = $ProjectDir.TrimEnd('\')

$InstanceName = "ubuntu-$ProjectName"
$InstanceDir  = "$ProjectDir\$ProjectName"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if (-not (Test-Path $BaseImage)) {
    Write-Error @"
Base image not found at: $BaseImage

Run .\build-base.ps1 first to build the base image.
"@
    exit 1
}

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "WSL is not installed. Install it with: wsl --install"
    exit 1
}

$existing = wsl --list --quiet 2>$null `
  | ForEach-Object { $_ -replace "`0", "" } `
  | Where-Object   { $_.Trim() -eq $InstanceName }

if ($existing) {
    Write-Error "WSL instance '$InstanceName' already exists. Choose a different name or unregister it first:"
    Write-Error "  wsl --unregister $InstanceName"
    exit 1
}

# ── Create project instance ───────────────────────────────────────────────────
$createdDir = $false
if (Test-Path $InstanceDir) {
    if ((Get-ChildItem $InstanceDir -Force | Measure-Object).Count -gt 0) {
        Write-Error "Directory '$InstanceDir' already exists and is not empty. Remove it first or choose a different name."
        exit 1
    }
} else {
    New-Item -ItemType Directory -Force -Path $InstanceDir | Out-Null
    $createdDir = $true
}

Write-Host "Creating '$InstanceName' at $InstanceDir ..."
wsl --import $InstanceName $InstanceDir $BaseImage --version 2
if ($LASTEXITCODE -ne 0) {
    # Roll back only if we created the directory
    if ($createdDir -and (Test-Path $InstanceDir)) { Remove-Item -Recurse -Force $InstanceDir }
    Write-Error "wsl --import failed with exit code $LASTEXITCODE"
    exit 1
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
Write-Host "     Ctrl+Shift+P → 'Remote-WSL: Connect to WSL using Distro...' → $InstanceName"
