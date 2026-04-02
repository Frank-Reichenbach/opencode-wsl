<#
    End-to-end integration tests for opencode-wsl.
    Requires: Windows with WSL enabled.
    Runs: build-base.ps1 → new-project.ps1 → verify instance → cleanup.

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

        # Cleanup: unregister any test instances and remove directories
        $instances = wsl --list --quiet 2>$null |
            ForEach-Object { $_ -replace "`0", "" } |
            Where-Object { $_.Trim() -eq $TestInstanceName }
        foreach ($inst in $instances) {
            $name = $inst.Trim()
            if ($name) { wsl --unregister $name 2>$null }
        }
        if (Test-Path $TestBaseDir) { Remove-Item -Recurse -Force $TestBaseDir }
        if (Test-Path $TestInstanceDir) { Remove-Item -Recurse -Force $TestInstanceDir }
    }

    It 'build-base.ps1 produces a base image tarball' {
        & "$ProjectRoot/build-base.ps1" -BaseImage $BaseImage
        $LASTEXITCODE | Should -Be 0
        $BaseImage | Should -Exist
        (Get-Item $BaseImage).Length | Should -BeGreaterThan 100MB
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
        $version = wsl -d $TestInstanceName -- git --version 2>&1
        $LASTEXITCODE | Should -Be 0
        $version | Should -Match 'git version'
    }

    It 'instance has GitHub CLI installed' {
        $result = wsl -d $TestInstanceName -- bash -c "which gh" 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'instance has Podman installed' {
        $version = wsl -d $TestInstanceName -- podman --version 2>&1
        $LASTEXITCODE | Should -Be 0
        $version | Should -Match 'podman version'
    }

    It 'instance has opencode installed' {
        $result = wsl -d $TestInstanceName -- bash -lc 'command -v opencode >/dev/null && opencode --version' 2>&1
        $LASTEXITCODE | Should -Be 0
        "$result".Trim() | Should -Match '^\d+\.\d+\.\d+'
    }

    It 'instance has docker symlink via podman-docker' {
        $result = wsl -d $TestInstanceName -- which docker 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'instance has opencode config at correct path' {
        $result = wsl -d $TestInstanceName -- cat /root/.config/opencode/opencode.json 2>&1
        $LASTEXITCODE | Should -Be 0
        $config = $result | ConvertFrom-Json
        $config.snapshot | Should -Be $false
        $config.share | Should -Be 'disabled'
        $config.experimental.openTelemetry | Should -Be $false
    }

    It 'instance has BROWSER env var set in .bashrc' {
        $browser = wsl -d $TestInstanceName -- sed -n "s/^export BROWSER=//p" /root/.bashrc 2>&1
        "$browser" | Should -Match 'msedge'
    }

    It 'instance has COLORTERM env var set in .bashrc' {
        $colorterm = wsl -d $TestInstanceName -- sed -n "s/^export COLORTERM=//p" /root/.bashrc 2>&1
        "$colorterm" | Should -Be 'truecolor'
    }

    It 'instance resolves opencode via /usr/local/bin' {
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
