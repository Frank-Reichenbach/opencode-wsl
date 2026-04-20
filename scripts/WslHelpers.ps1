function Get-WslCommandOutput {
    param(
        [string[]]$Arguments
    )

    $output = & wsl @Arguments 2>&1 | Out-String
    return ($output -replace "`0", '')
}

function Get-WslDistroName {
    (Get-WslCommandOutput -Arguments @('--list', '--quiet')) -split "\r?\n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
}

function Assert-SafeWindowsDirectory([string]$DirectoryPath) {
    $resolvedDirectory = [System.IO.Path]::GetFullPath($DirectoryPath)
    $sysRoot = if ($env:SystemRoot) { $env:SystemRoot.TrimEnd('\') + '\' } else { $null }

    if ($resolvedDirectory -match '^[A-Za-z]:\\?$' -or ($sysRoot -and ($resolvedDirectory.TrimEnd('\') + '\').StartsWith($sysRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to use '$resolvedDirectory' -- path is a drive root or system directory."
    }

    return $resolvedDirectory
}
