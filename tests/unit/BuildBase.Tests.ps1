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

        It 'does not match similarly named files' {
            function Get-RemoteText([string]$Uri) {
                @'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz.zsync
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
            $wslHelperPath = Join-Path $PSScriptRoot '../../scripts/WslHelpers.ps1' | Resolve-Path
            $ScriptText = Get-Content $scriptPath -Raw
            . $wslHelperPath.Path
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptPath.Path, [ref]$null, [ref]$null
            )
            $funcAsts = $ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $args[0].Name -in @('Get-WslExportFormat', 'Assert-WslExportFormatSupport', 'Get-WslExportFormatProbeText', 'Test-WslExportFormatSupport', 'Move-WslExportIntoPlace', 'Export-WslDistroImage')
            }, $true)

            foreach ($name in 'Get-WslExportFormat', 'Assert-WslExportFormatSupport', 'Get-WslExportFormatProbeText', 'Test-WslExportFormatSupport', 'Move-WslExportIntoPlace', 'Export-WslDistroImage') {
                $funcAst = $funcAsts | Where-Object { $_.Name -eq $name } | Select-Object -First 1
                if (-not $funcAst) { throw "$name function not found in build-base.ps1" }
                . ([scriptblock]::Create($funcAst.Extent.Text))
            }
        }

        It 'uses a fixed repo-specific builder name' {
            $ScriptText | Should -Match '\$BuilderName\s*=\s*"opencode-wsl-builder"'
        }

        It 'loads the shared rootfs checksum helper' {
            $ScriptText | Should -Match 'scripts/RootfsChecksum\.ps1'
        }

        It 'loads the shared WSL helper' {
            $ScriptText | Should -Match 'scripts/WslHelpers\.ps1'
        }

        It 'checks export-format support before long-running setup begins' {
            $ScriptText.IndexOf('$BaseImageExportFormat = Assert-WslExportFormatSupport -ImagePath $BaseImage') |
                Should -BeLessThan $ScriptText.IndexOf('Write-Host "Creating directories..."')
        }

        It 'uses tar.gz export format for .tar.gz base images' {
            Get-WslExportFormat 'C:\wsl\base\opencode-base.tar.gz' | Should -Be 'tar.gz'
        }

        It 'leaves the format unset for plain tar exports' {
            Get-WslExportFormat 'C:\wsl\base\opencode-base.tar' | Should -BeNullOrEmpty
        }

        It 'detects when WSL export format support is available' {
            Mock Test-Path { $false }
            Mock Remove-Item {}

            function Get-WslExportFormatProbeText([string]$probePath) {
                @'
There is no distribution with the supplied name.

Error code: Wsl/Service/WSL_E_DISTRO_NOT_FOUND
'@
            }

            Test-WslExportFormatSupport | Should -BeTrue
        }

        It 'detects when WSL export format support is unavailable' {
            Mock Test-Path { $false }
            Mock Remove-Item {}

            function Get-WslExportFormatProbeText([string]$probePath) {
                @'
Invalid command line argument: --format

Error code: Wsl/E_INVALIDARG
'@
            }

            Test-WslExportFormatSupport | Should -BeFalse
        }

        It 'falls back to help text when probe output is inconclusive' {
            Mock Test-Path { $false }
            Mock Remove-Item {}

            function Get-WslExportFormatProbeText([string]$probePath) {
                return 'unexpected probe output'
            }

            function Get-WslCommandOutput {
                param([string[]]$Arguments)

                return @'
Usage: wsl.exe [Argument]
    --format <Format>
'@
            }

            Test-WslExportFormatSupport | Should -BeTrue
        }

        It 'returns the export format when support is available' {
            function Test-WslExportFormatSupport {
                return $true
            }

            Assert-WslExportFormatSupport 'C:\wsl\base\opencode-base.tar.gz' | Should -Be 'tar.gz'
        }

        It 'replaces an existing export in place' {
            $imagePath = Join-Path $TestDrive 'opencode-base.tar.gz'
            $temporaryPath = $imagePath + '.exporting'

            [System.IO.File]::WriteAllText($imagePath, 'old image')
            [System.IO.File]::WriteAllText($temporaryPath, 'new image')

            Move-WslExportIntoPlace -TemporaryPath $temporaryPath -ImagePath $imagePath

            [System.IO.File]::ReadAllText($imagePath) | Should -Be 'new image'
            Test-Path -LiteralPath $temporaryPath | Should -BeFalse
        }

        It 'moves a new export into place when no previous image exists' {
            $imagePath = Join-Path $TestDrive 'opencode-base.tar'
            $temporaryPath = $imagePath + '.exporting'

            [System.IO.File]::WriteAllText($temporaryPath, 'fresh image')

            Move-WslExportIntoPlace -TemporaryPath $temporaryPath -ImagePath $imagePath

            [System.IO.File]::ReadAllText($imagePath) | Should -Be 'fresh image'
            Test-Path -LiteralPath $temporaryPath | Should -BeFalse
        }

        It 'fails before touching the existing image when tar.gz export support is unavailable' {
            function Get-WslExportFormat([string]$imagePath) {
                return 'tar.gz'
            }

            function Test-WslExportFormatSupport {
                return $false
            }

            $script:wslCalled = $false
            function wsl {
                $script:wslCalled = $true
                $global:LASTEXITCODE = 0
            }

            Mock Test-Path { $false }
            Mock Remove-Item {}

            {
                Export-WslDistroImage -DistroName 'opencode-wsl-builder' -ImagePath 'C:\wsl\base\opencode-base.tar.gz'
            } | Should -Throw "This WSL version does not support 'wsl --export --format'. Update WSL and try again, or use a .tar base image path."

            $script:wslCalled | Should -BeFalse
            Assert-MockCalled Remove-Item -Times 0
        }

        It 'stages exports through a temporary file before replacing the destination' {
            function Get-WslExportFormat([string]$imagePath) {
                return 'tar.gz'
            }

            function Test-WslExportFormatSupport {
                return $true
            }

            $script:wslCalls = @()
            function wsl {
                $script:wslCalls += ,@($args)
                $global:LASTEXITCODE = 0
            }

            $script:placedImage = $null
            function Move-WslExportIntoPlace([string]$temporaryPath, [string]$imagePath) {
                $script:placedImage = @($temporaryPath, $imagePath)
            }

            Mock Test-Path { $false }
            Mock Remove-Item {}

            Export-WslDistroImage -DistroName 'opencode-wsl-builder' -ImagePath 'C:\wsl\base\opencode-base.tar.gz' -ExportFormat 'tar.gz'

            $script:wslCalls.Count | Should -Be 1
            $script:wslCalls[0][0] | Should -Be '--export'
            $script:wslCalls[0][1] | Should -Be 'opencode-wsl-builder'
            $script:wslCalls[0][2] | Should -Be 'C:\wsl\base\opencode-base.tar.gz.exporting'
            $script:wslCalls[0][3] | Should -Be '--format'
            $script:wslCalls[0][4] | Should -Be 'tar.gz'
            $script:placedImage[0] | Should -Be 'C:\wsl\base\opencode-base.tar.gz.exporting'
            $script:placedImage[1] | Should -Be 'C:\wsl\base\opencode-base.tar.gz'
            Assert-MockCalled Remove-Item -Times 0
        }

        It 'cleans up the temporary export when wsl --export fails' {
            function Get-WslExportFormat([string]$imagePath) {
                return $null
            }

            function wsl {
                $global:LASTEXITCODE = 7
            }

            $script:placedImage = $false
            function Move-WslExportIntoPlace {
                $script:placedImage = $true
            }

            $temporaryPath = 'C:\wsl\base\opencode-base.tar.exporting'
            $script:testPathCalls = 0
            Mock Test-Path {
                param([string]$Path, [string]$LiteralPath)

                $effectivePath = if ($PSBoundParameters.ContainsKey('LiteralPath')) { $LiteralPath } else { $Path }

                if ($effectivePath -ne $temporaryPath) {
                    return $false
                }

                $script:testPathCalls += 1
                return $script:testPathCalls -gt 1
            }

            $script:removedPaths = @()
            Mock Remove-Item {
                param([string]$Path, [string]$LiteralPath)

                if ($PSBoundParameters.ContainsKey('LiteralPath')) {
                    $script:removedPaths += $LiteralPath
                } else {
                    $script:removedPaths += $Path
                }
            }

            {
                Export-WslDistroImage -DistroName 'opencode-wsl-builder' -ImagePath 'C:\wsl\base\opencode-base.tar' -ExportFormat $null
            } | Should -Throw 'wsl --export failed with exit code 7'

            $script:placedImage | Should -BeFalse
            $script:removedPaths | Should -Contain $temporaryPath
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
