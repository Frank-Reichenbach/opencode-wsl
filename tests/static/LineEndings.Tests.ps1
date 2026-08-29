BeforeDiscovery {
    $repoRoot = Join-Path $PSScriptRoot '../..' | Resolve-Path
    $trackedFiles = & git -C $repoRoot.Path ls-files --eol |
        ForEach-Object {
            if ($_ -match '^(?<index>\S+)\s+(?<working>\S+)\s+(?<attributes>.+?)\t(?<path>.+)$') {
                [pscustomobject]@{
                    Index      = $matches.index
                    Working    = $matches.working
                    Attributes = $matches.attributes
                    Path       = $matches.path
                }
            }
        }

    $LfFiles = $trackedFiles |
        Where-Object { $_.Attributes -match '\beol=lf\b' } |
        ForEach-Object {
            @{
                Name       = $_.Path
                Working    = $_.Working
                Attributes = $_.Attributes
            }
        }

    $CrlfFiles = $trackedFiles |
        Where-Object { $_.Attributes -match '\beol=crlf\b' } |
        ForEach-Object {
            @{
                Name       = $_.Path
                Working    = $_.Working
                Attributes = $_.Attributes
            }
        }
}

Describe 'Tracked line endings' {
    It '<Name> checks out with LF when attributes require LF' -ForEach $LfFiles {
        if ($Working -ne 'w/lf') {
            Write-Host "  Attributes: $Attributes"
            Write-Host "  Working tree EOL: $Working"
        }

        $Working | Should -Be 'w/lf'
    }

    It '<Name> checks out with CRLF when attributes require CRLF' -ForEach $CrlfFiles {
        if ($Working -ne 'w/crlf') {
            Write-Host "  Attributes: $Attributes"
            Write-Host "  Working tree EOL: $Working"
        }

        $Working | Should -Be 'w/crlf'
    }
}
