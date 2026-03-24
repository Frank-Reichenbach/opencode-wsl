# new-project.ps1
#
# Creates a new isolated WSL project instance from the pre-baked base image.
# Run build-base.ps1 first if you haven't already.
#
# Usage: .\new-project.ps1 my-project-name

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,

    [string]$BaseImage   = "C:\wsl\base\opencode-base.tar.gz",
    [string]$ProjectsDir = "C:\wsl\projects"
)

$ErrorActionPreference = "Stop"
$InstanceName = "proj-$ProjectName"
$InstanceDir  = Join-Path $ProjectsDir $InstanceName

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if (-not (Test-Path $BaseImage)) {
    Write-Error @"
Base image not found at: $BaseImage

Run .\build-base.ps1 first to build the base image.
"@
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
Write-Host "Creating project instance '$InstanceName'..."
New-Item -ItemType Directory -Force -Path $InstanceDir | Out-Null
wsl --import $InstanceName $InstanceDir $BaseImage

Write-Host ""
Write-Host "Done! '$InstanceName' is ready."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open the instance:"
Write-Host "       wsl -d $InstanceName"
Write-Host ""
Write-Host "  2. On first use, log in to your AI provider (Claude / OpenAI):"
Write-Host "       opencode auth login"
Write-Host "     This opens your Windows browser. Complete the OAuth flow once per instance."
Write-Host ""
Write-Host "  3. Start opencode:"
Write-Host "       opencode"
Write-Host ""
Write-Host "  Or connect via VS Code:"
Write-Host "     Ctrl+Shift+P → 'Remote-WSL: Connect to WSL using Distro...' → $InstanceName"
