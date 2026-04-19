Describe 'new-project.ps1' {
    BeforeAll {
        $Script = Join-Path $PSScriptRoot '../../new-project.ps1' | Resolve-Path
    }

    Context 'input validation' {
        It 'rejects names with spaces' {
            $ErrorActionPreference = 'Continue'
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName 'my project'" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            "$output" | Should -Match 'Invalid project name'
        }

        It 'rejects names with special characters' {
            $ErrorActionPreference = 'Continue'
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName 'my@project!'" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            "$output" | Should -Match 'Invalid project name'
        }

        It 'rejects empty name when passed explicitly' {
            $ErrorActionPreference = 'Continue'
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName ''" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
        }

        It 'accepts valid hyphenated names' {
            $ErrorActionPreference = 'Continue'
            # This will fail at the "base image not found" step, not at name validation
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName 'my-api' -BaseImage '/nonexistent'" 2>&1
            "$output" | Should -Match 'Base image not found'
        }

        It 'accepts valid alphanumeric names' {
            $ErrorActionPreference = 'Continue'
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName 'myapi2' -BaseImage '/nonexistent'" 2>&1
            "$output" | Should -Match 'Base image not found'
        }
    }

    Context 'pre-flight checks' {
        It 'errors when base image is missing' {
            $ErrorActionPreference = 'Continue'
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName 'test' -BaseImage '/nonexistent/path.tar.gz'" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            "$output" | Should -Match 'Base image not found'
        }
    }

    Context 'ProjectDir validation' {
        It 'rejects a drive root as project directory' {
            $ErrorActionPreference = 'Continue'
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName 'test' -ProjectDir 'C:\' -BaseImage '/nonexistent'" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            "$output" | Should -Match 'drive\s+root\s+or\s+system\s+directory'
        }

        It 'rejects a system directory as project directory' {
            $ErrorActionPreference = 'Continue'
            $sysDir = $env:SystemRoot
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName 'test' -ProjectDir '$sysDir' -BaseImage '/nonexistent'" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            "$output" | Should -Match 'drive\s+root\s+or\s+system\s+directory'
        }

        It 'accepts a normal project directory (fails at base image check, not path check)' {
            $ErrorActionPreference = 'Continue'
            $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName 'test' -ProjectDir 'C:\wsl' -BaseImage '/nonexistent'" 2>&1
            "$output" | Should -Match 'Base image not found'
        }

        It 'treats hidden files as making the target directory non-empty' {
            $ErrorActionPreference = 'Continue'
            $tempRoot = Join-Path $env:TEMP "oc-np-test-$(Get-Random -Maximum 999999)"
            $projectName = "test$(Get-Random -Maximum 999999)"
            $instanceDir = Join-Path $tempRoot $projectName
            $baseImage = Join-Path $tempRoot 'dummy-base.tar.gz'

            try {
                New-Item -ItemType Directory -Force -Path $instanceDir | Out-Null
                New-Item -ItemType File -Force -Path $baseImage | Out-Null

                $hiddenFile = Join-Path $instanceDir '.hidden'
                New-Item -ItemType File -Force -Path $hiddenFile | Out-Null
                (Get-Item $hiddenFile).Attributes = 'Hidden'

                $output = & powershell -NoProfile -NonInteractive -Command "& '$Script' -ProjectName '$projectName' -ProjectDir '$tempRoot' -BaseImage '$baseImage'" 2>&1
                $LASTEXITCODE | Should -Not -Be 0
                "$output" | Should -Match 'already exists and is not empty'
            }
            finally {
                if (Test-Path $tempRoot) {
                    Remove-Item -Recurse -Force $tempRoot
                }
            }
        }
    }
}
