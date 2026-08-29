Describe 'WslHelpers.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../scripts/WslHelpers.ps1' | Resolve-Path
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath.Path, [ref]$null, [ref]$null
        )
        $funcAsts = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $args[0].Name -in @('Get-WslCommandOutput', 'Get-WslDistroName', 'Get-WslVersion', 'Assert-WslMinimumVersion', 'Assert-SafeWindowsDirectory')
        }, $true)

        foreach ($name in 'Get-WslCommandOutput', 'Get-WslDistroName', 'Get-WslVersion', 'Assert-WslMinimumVersion', 'Assert-SafeWindowsDirectory') {
            $funcAst = $funcAsts | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            if (-not $funcAst) { throw "$name function not found in scripts/WslHelpers.ps1" }
            . ([scriptblock]::Create($funcAst.Extent.Text))
        }
    }

    It 'strips embedded NUL characters from WSL output' {
        function wsl {
            @"
u`0b`0u`0n`0t`0u`0
"@
        }

        $output = Get-WslCommandOutput -Arguments @('--list', '--quiet')
        $output | Should -Match 'ubuntu'
        $output | Should -Not -Match "`0"
    }

    It 'returns trimmed distro names and skips blank lines' {
        function Get-WslCommandOutput {
            param([string[]]$Arguments)

            return @('', ' ubuntu', '', ('Debian' + ' '), '') -join "`n"
        }

        $distros = Get-WslDistroName
        $distros.Count | Should -Be 2
        $distros[0] | Should -Be 'ubuntu'
        $distros[1] | Should -Be 'Debian'
    }

    It 'parses the installed WSL version' {
        function Get-WslCommandOutput {
            param([string[]]$Arguments)

            return @'
WSL version: 2.4.10.0
Kernel version: 6.6.87.2-1
'@
        }

        Get-WslVersion | Should -Be ([version]'2.4.10.0')
    }

    It 'accepts WSL 2.4.10 and newer' {
        function Get-WslVersion {
            return [version]'2.4.10.0'
        }

        { Assert-WslMinimumVersion } | Should -Not -Throw
    }

    It 'rejects WSL versions older than 2.4.10' {
        function Get-WslVersion {
            return [version]'2.4.9.0'
        }

        { Assert-WslMinimumVersion } |
            Should -Throw '*requires WSL 2.4.10 or later*'
    }

    It 'rejects an undetectable WSL version' {
        function Get-WslVersion {
            return $null
        }

        { Assert-WslMinimumVersion } |
            Should -Throw '*Could not determine the WSL version*'
    }

    It 'rejects a drive root as an unsafe directory' {
        { Assert-SafeWindowsDirectory 'C:\' } |
            Should -Throw '*drive root or system directory*'
    }

    It 'rejects the Windows system directory as unsafe' {
        { Assert-SafeWindowsDirectory $env:SystemRoot } |
            Should -Throw '*drive root or system directory*'
    }
}
