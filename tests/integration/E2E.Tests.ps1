<#
    End-to-end integration tests for opencode-wsl.
    Requires: Windows with WSL enabled.
    Runs: build-base.ps1 -> new-project.ps1 -> verify instance -> cleanup.

    These tests create real WSL instances and should only run in CI or
    controlled environments. They are slow (10-15 minutes for the full suite).
#>

Describe 'opencode-wsl end-to-end' -Tag 'Integration' {
    BeforeAll {
        $ProjectRoot = Join-Path $PSScriptRoot '../..' | Resolve-Path
        $TestProject = "oc-test-$(Get-Random -Maximum 9999)"
        $TestBaseDir = "C:\wsl\test-base-$TestProject"
        $TestInstanceDir = "C:\wsl\$TestProject"
        $TestInstanceName = "ubuntu-$TestProject"
        $BaseImage = Join-Path $TestBaseDir 'opencode-base.tar.gz'

        # Pre-seed Ubuntu rootfs from CI cache to avoid re-downloading ~600MB
        if ($env:ROOTFS_CACHE -and (Test-Path $env:ROOTFS_CACHE)) {
            New-Item -ItemType Directory -Force -Path $TestBaseDir | Out-Null
            Copy-Item $env:ROOTFS_CACHE (Join-Path $TestBaseDir 'ubuntu-24.04.tar.gz')
        }
    }

    AfterAll {
        # Persist rootfs to cache path so actions/cache can save it for next run
        $rootfs = Join-Path $TestBaseDir 'ubuntu-24.04.tar.gz'
        if ($env:ROOTFS_CACHE -and (Test-Path $rootfs) -and -not (Test-Path $env:ROOTFS_CACHE)) {
            $cacheDir = Split-Path $env:ROOTFS_CACHE
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
            Copy-Item $rootfs $env:ROOTFS_CACHE
        }

        # Cleanup: unregister test instance and builder, plus leftovers from failed runs
        $allInstances = wsl --list --quiet 2>$null |
            ForEach-Object { $_ -replace "`0", "" } |
            Where-Object { $_.Trim() -match '^(ubuntu-oc-test-|opencode-wsl-builder$)' }
        foreach ($inst in $allInstances) {
            $name = $inst.Trim()
            if ($name) { wsl --unregister $name 2>$null }
        }
        if (Test-Path $TestBaseDir) { Remove-Item -Recurse -Force $TestBaseDir }
        if (Test-Path $TestInstanceDir) { Remove-Item -Recurse -Force $TestInstanceDir }

        # Remove OS artifacts left by wsl --import (current run + stale leftovers)
        $dvcBase = Join-Path $env:LOCALAPPDATA 'Temp\WSLDVCPlugin'
        $startMenuBase = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

        foreach ($artifactBase in @($dvcBase, $startMenuBase)) {
            if (-not (Test-Path $artifactBase)) { continue }
            Get-ChildItem $artifactBase -Directory |
                Where-Object { $_.Name -match '^(ubuntu-oc-test-|opencode-wsl-builder$)' } |
                ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
        }
    }

    It 'build-base.ps1 produces a base image tarball' {
        & "$ProjectRoot/build-base.ps1" -BaseImage $BaseImage
        $LASTEXITCODE | Should -Be 0
        $BaseImage | Should -Exist
        $rootfs = Join-Path $TestBaseDir 'ubuntu-24.04.tar.gz'
        (Get-Item $BaseImage).Length | Should -BeGreaterThan (Get-Item $rootfs).Length
    }

    It 'build-base.ps1 cleans up builder artifacts' {
        # Builder WSL instance should be unregistered by build-base.ps1's finally block
        $builders = wsl --list --quiet 2>$null |
            ForEach-Object { $_ -replace "`0", "" } |
            Where-Object { $_.Trim() -eq 'opencode-wsl-builder' }
        $builders | Should -BeNullOrEmpty

        # OS artifacts created by wsl --import should be removed
        $dvcDir = Join-Path $env:LOCALAPPDATA 'Temp\WSLDVCPlugin\opencode-wsl-builder'
        $dvcDir | Should -Not -Exist

        $startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\opencode-wsl-builder'
        $startMenuDir | Should -Not -Exist
    }

    It 'new-project.ps1 creates a WSL instance' {
        & "$ProjectRoot/new-project.ps1" -ProjectName $TestProject -BaseImage $BaseImage
        $LASTEXITCODE | Should -Be 0

        $instances = wsl --list --quiet 2>$null |
            ForEach-Object { $_ -replace "`0", "" } |
            Where-Object { $_.Trim() -eq $TestInstanceName }
        $instances | Should -Not -BeNullOrEmpty
    }

    It 'instance has git installed' {
        $ErrorActionPreference = 'Continue'
        $version = wsl -d $TestInstanceName -- git --version 2>&1
        $LASTEXITCODE | Should -Be 0
        $version | Should -Match 'git version'
    }

    It 'instance has GitHub CLI installed' {
        $ErrorActionPreference = 'Continue'
        $result = wsl -d $TestInstanceName -- bash -c "which gh" 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'instance has Podman installed' {
        $ErrorActionPreference = 'Continue'
        $version = wsl -d $TestInstanceName -- podman --version 2>&1
        $LASTEXITCODE | Should -Be 0
        $version | Should -Match 'podman version'
    }

    It 'instance has opencode installed' {
        $ErrorActionPreference = 'Continue'
        $result = wsl -d $TestInstanceName -- bash -lc 'command -v opencode >/dev/null && opencode --version' 2>&1
        $LASTEXITCODE | Should -Be 0
        "$result".Trim() | Should -Match '^\d+\.\d+\.\d+'
    }

    It 'instance has docker symlink via podman-docker' {
        $ErrorActionPreference = 'Continue'
        $result = wsl -d $TestInstanceName -- which docker 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'instance has opencode config at correct path' {
        $ErrorActionPreference = 'Continue'
        $result = wsl -d $TestInstanceName -- cat /root/.config/opencode/opencode.json 2>&1
        $LASTEXITCODE | Should -Be 0
        $config = $result | ConvertFrom-Json
        $config.snapshot | Should -Be $false
        $config.share | Should -Be 'disabled'
        $config.experimental.openTelemetry | Should -Be $false
    }

    It 'instance has BROWSER env var set in .bashrc' {
        $ErrorActionPreference = 'Continue'
        $browser = wsl -d $TestInstanceName -- sed -n "s/^export BROWSER=//p" /root/.bashrc 2>&1
        "$browser" | Should -Match 'msedge'
    }

    It 'instance has COLORTERM env var set in .bashrc' {
        $ErrorActionPreference = 'Continue'
        $colorterm = wsl -d $TestInstanceName -- sed -n "s/^export COLORTERM=//p" /root/.bashrc 2>&1
        "$colorterm" | Should -Be 'truecolor'
    }

    It 'instance resolves opencode via /usr/local/bin' {
        $ErrorActionPreference = 'Continue'
        $pathValue = wsl -d $TestInstanceName -- bash -lc 'command -v opencode' 2>&1
        $LASTEXITCODE | Should -Be 0
        "$pathValue".Trim() | Should -Be '/usr/local/bin/opencode'
    }

    It 'instance can be unregistered cleanly' {
        wsl --unregister $TestInstanceName
        $LASTEXITCODE | Should -Be 0

        $instances = wsl --list --quiet 2>$null |
            ForEach-Object { $_ -replace "`0", "" } |
            Where-Object { $_.Trim() -eq $TestInstanceName }
        $instances | Should -BeNullOrEmpty
    }
}
