BeforeDiscovery {
    $Scripts = @(
        @{ Name = 'build-base.ps1';  Path = Join-Path $PSScriptRoot '../../build-base.ps1' }
        @{ Name = 'new-project.ps1'; Path = Join-Path $PSScriptRoot '../../new-project.ps1' }
    )
}

Describe 'PSScriptAnalyzer' {
    It '<Name> has valid PowerShell syntax' -ForEach $Scripts {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $Path).Path,
            [ref]$null,
            [ref]$errors
        )
        $errors | Should -BeNullOrEmpty
    }

    It '<Name> passes PSScriptAnalyzer' -ForEach $Scripts {
        $results = Invoke-ScriptAnalyzer -Path (Resolve-Path $Path).Path -ExcludeRule 'PSAvoidUsingWriteHost','PSUseBOMForUnicodeEncodedFile'
        $results | ForEach-Object { Write-Host "  $($_.RuleName): $($_.Message) (line $($_.Line))" }
        $results | Should -BeNullOrEmpty
    }
}
