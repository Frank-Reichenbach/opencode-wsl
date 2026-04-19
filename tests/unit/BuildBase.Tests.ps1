Describe 'build-base.ps1' {
    Context 'ConvertTo-WslPath function' {
        BeforeAll {
            # Extract ConvertTo-WslPath from build-base.ps1 via AST
            $scriptPath = Join-Path $PSScriptRoot '../../build-base.ps1' | Resolve-Path
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath.Path, [ref]$null, [ref]$null
            )
            $funcAst = $ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $args[0].Name -eq 'ConvertTo-WslPath'
            }, $true) | Select-Object -First 1

            if (-not $funcAst) { throw 'ConvertTo-WslPath function not found in build-base.ps1' }
            . ([scriptblock]::Create($funcAst.Extent.Text))
        }

        It 'converts C:\foo\bar to /mnt/c/foo/bar' {
            ConvertTo-WslPath 'C:\foo\bar' | Should -Be '/mnt/c/foo/bar'
        }

        It 'converts D:\Users\test to /mnt/d/Users/test' {
            ConvertTo-WslPath 'D:\Users\test' | Should -Be '/mnt/d/Users/test'
        }

        It 'handles paths with spaces' {
            ConvertTo-WslPath 'C:\Program Files\app' | Should -Be '/mnt/c/Program Files/app'
        }

        It 'lowercases the drive letter' {
            ConvertTo-WslPath 'E:\data' | Should -Be '/mnt/e/data'
        }
    }

    Context 'RootfsChecksum helper' {
        BeforeAll {
            $scriptPath = Join-Path $PSScriptRoot '../../scripts/RootfsChecksum.ps1' | Resolve-Path
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath.Path, [ref]$null, [ref]$null
            )
            $funcAst = $ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $args[0].Name -eq 'Get-PublishedSha256'
            }, $true) | Select-Object -First 1

            if (-not $funcAst) { throw 'Get-PublishedSha256 function not found in scripts/RootfsChecksum.ps1' }
            . ([scriptblock]::Create($funcAst.Extent.Text))
        }

        It 'extracts the checksum for a matching file' {
            function Get-RemoteText([string]$Uri) {
                @'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other-file.tar.gz
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz
'@
            }

            Get-PublishedSha256 'https://example.invalid/SHA256SUMS' 'ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz' |
                Should -Be 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        }

        It 'throws a friendly error when the file is missing from SHA256SUMS' {
            function Get-RemoteText([string]$Uri) {
                @'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other-file.tar.gz
'@
            }

            { Get-PublishedSha256 'https://example.invalid/SHA256SUMS' 'ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz' } |
                Should -Throw "Could not find checksum for 'ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz' in https://example.invalid/SHA256SUMS"
        }
    }

    Context 'builder configuration' {
        BeforeAll {
            $scriptPath = Join-Path $PSScriptRoot '../../build-base.ps1' | Resolve-Path
            $scriptText = Get-Content $scriptPath -Raw
        }

        It 'uses a fixed repo-specific builder name' {
            $scriptText | Should -Match '\$BuilderName\s*=\s*"opencode-wsl-builder"'
        }

        It 'loads the shared rootfs checksum helper' {
            $scriptText | Should -Match 'scripts/RootfsChecksum\.ps1'
        }
    }

    Context 'path validation' {
        BeforeAll {
            $scriptPath = Join-Path $PSScriptRoot '../../build-base.ps1' | Resolve-Path
        }

        It 'rejects a drive root as base directory' {
            $ErrorActionPreference = 'Continue'
            $output = & powershell -NoProfile -NonInteractive -Command "& '$($scriptPath.Path)' -BaseImage 'C:\opencode-base.tar.gz'" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            "$output" | Should -Match 'drive\s+root\s+or\s+system\s+directory'
        }

        It 'rejects a system directory as base directory' {
            $ErrorActionPreference = 'Continue'
            $sysDir = $env:SystemRoot
            $output = & powershell -NoProfile -NonInteractive -Command "& '$($scriptPath.Path)' -BaseImage '$sysDir\opencode-base.tar.gz'" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            "$output" | Should -Match 'drive\s+root\s+or\s+system\s+directory'
        }
    }
}
