Describe 'WslHelpers.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../scripts/WslHelpers.ps1' | Resolve-Path
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptPath.Path, [ref]$null, [ref]$null
        )
        $funcAsts = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $args[0].Name -in @('Get-WslCommandOutput', 'Get-WslDistroName', 'Assert-SafeWindowsDirectory')
        }, $true)

        foreach ($name in 'Get-WslCommandOutput', 'Get-WslDistroName', 'Assert-SafeWindowsDirectory') {
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

    It 'rejects a drive root as an unsafe directory' {
        { Assert-SafeWindowsDirectory 'C:\' } |
            Should -Throw '*drive root or system directory*'
    }

    It 'rejects the Windows system directory as unsafe' {
        { Assert-SafeWindowsDirectory $env:SystemRoot } |
            Should -Throw '*drive root or system directory*'
    }
}
