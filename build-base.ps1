# build-base.ps1
#
# Builds the pre-baked WSL base image with all tools installed.
# Run this once. After it completes, use new-project.ps1 to create project instances.
#
# Usage: .\build-base.ps1
#        .\build-base.ps1 -BaseDir D:\wsl\base

param(
    [string]$BaseDir    = "C:\wsl\base",
    [string]$BuilderDir = "C:\wsl\builder",
    [string]$BuilderName = "oc-builder"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$UbuntuUrl  = "https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz"
$UbuntuTar  = Join-Path $BaseDir "ubuntu-24.04.tar.gz"
$OutputTar  = Join-Path $BaseDir "opencode-base.tar.gz"

# ── Convert Windows path to WSL /mnt/... path ──────────────────────────────────
function To-WslPath([string]$winPath) {
    $drive = $winPath[0].ToString().ToLower()
    $rest  = $winPath.Substring(2) -replace "\\", "/"
    return "/mnt/$drive$rest"
}

$WslScriptDir = To-WslPath $ScriptDir

# ── Prepare directories ────────────────────────────────────────────────────────
Write-Host "Creating directories..."
New-Item -ItemType Directory -Force -Path $BaseDir    | Out-Null
New-Item -ItemType Directory -Force -Path $BuilderDir | Out-Null

# ── Download Ubuntu rootfs if not already present ─────────────────────────────
if (-not (Test-Path $UbuntuTar)) {
    Write-Host "Downloading Ubuntu 24.04 WSL rootfs from Canonical..."
    Write-Host "  Source: $UbuntuUrl"
    Invoke-WebRequest -Uri $UbuntuUrl -OutFile $UbuntuTar
    Write-Host "  Saved to: $UbuntuTar"
} else {
    Write-Host "Using existing Ubuntu rootfs: $UbuntuTar"
}

# ── Clean up any leftover builder instance ────────────────────────────────────
$existing = wsl --list --quiet 2>$null | ForEach-Object { $_ -replace "`0", "" } | Where-Object { $_.Trim() -eq $BuilderName }
if ($existing) {
    Write-Host "Removing leftover builder instance '$BuilderName'..."
    wsl --unregister $BuilderName
}
if (Test-Path $BuilderDir) {
    Remove-Item -Recurse -Force $BuilderDir
    New-Item -ItemType Directory -Force -Path $BuilderDir | Out-Null
}

# ── Import builder instance ───────────────────────────────────────────────────
Write-Host "Importing builder instance '$BuilderName'..."
wsl --import $BuilderName $BuilderDir $UbuntuTar

# ── Copy bootstrap files into the instance ────────────────────────────────────
Write-Host "Copying bootstrap files..."
wsl -d $BuilderName -- bash -c "
  cp '$WslScriptDir/bootstrap/install.sh' /tmp/install.sh &&
  cp '$WslScriptDir/config/opencode.json' /tmp/opencode.json &&
  chmod +x /tmp/install.sh
"

# ── Run bootstrap ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Running bootstrap (takes several minutes)..."
Write-Host "──────────────────────────────────────────────"
wsl -d $BuilderName -- bash /tmp/install.sh
Write-Host "──────────────────────────────────────────────"

# ── Export base image ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Exporting base image..."
if (Test-Path $OutputTar) { Remove-Item $OutputTar }
wsl --export $BuilderName $OutputTar
Write-Host "  Saved to: $OutputTar"

# ── Clean up builder ──────────────────────────────────────────────────────────
Write-Host "Cleaning up builder instance..."
wsl --unregister $BuilderName
Remove-Item -Recurse -Force $BuilderDir

Write-Host ""
Write-Host "Done! Base image ready at: $OutputTar"
Write-Host "Run .\new-project.ps1 <project-name> to create a new project instance."
