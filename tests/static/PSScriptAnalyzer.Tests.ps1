BeforeDiscovery {
    $repoRoot = Join-Path $PSScriptRoot '../..' | Resolve-Path
    $Scripts = & git -C $repoRoot.Path ls-files '*.ps1' |
        Where-Object { $_ -notmatch '^tests/' } |
        ForEach-Object {
            @{
                Name = $_
                Path = Join-Path $repoRoot.Path $_
            }
        }
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

BeforeDiscovery {
    $repoRoot = Join-Path $PSScriptRoot '../..' | Resolve-Path
    $AllScripts = & git -C $repoRoot.Path ls-files '*.ps1' |
        ForEach-Object {
            @{
                Name = $_
                Path = Join-Path $repoRoot.Path $_
            }
        }
}

Describe 'ASCII-only scripts' {
    It '<Name> contains only ASCII characters' -ForEach $AllScripts {
        $content = Get-Content (Resolve-Path $Path).Path -Raw
        $nonAscii = [regex]::Matches($content, '[^\x00-\x7F]')
        if ($nonAscii.Count -gt 0) {
            $samples = ($nonAscii | Select-Object -First 5 | ForEach-Object {
                "U+$("{0:X4}" -f [int][char]$_.Value) '$($_.Value)'"
            }) -join ', '
            Write-Host "  Found $($nonAscii.Count) non-ASCII character(s): $samples"
        }
        $nonAscii.Count | Should -Be 0
    }
}
