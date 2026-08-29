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

function Get-WslVersion {
    $versionText = Get-WslCommandOutput -Arguments @('--version')
    $match = [regex]::Match($versionText, '(?im)^\s*WSL version:\s*(?<version>\d+(?:\.\d+){1,3})\s*$')

    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups['version'].Value
}

function Assert-WslMinimumVersion([version]$MinimumVersion = [version]'2.4.10') {
    $installedVersion = Get-WslVersion
    $requiredVersionText = $MinimumVersion.ToString()

    if (-not $installedVersion) {
        throw "Could not determine the WSL version. Ubuntu 26.04's .wsl image requires WSL $requiredVersionText or later. Run 'wsl --update' and try again."
    }

    if ($installedVersion -lt $MinimumVersion) {
        throw "WSL $installedVersion is too old. Ubuntu 26.04's .wsl image requires WSL $requiredVersionText or later. Run 'wsl --update' and try again."
    }
}

function Assert-SafeWindowsDirectory([string]$DirectoryPath) {
    $resolvedDirectory = [System.IO.Path]::GetFullPath($DirectoryPath)
    $sysRoot = if ($env:SystemRoot) { $env:SystemRoot.TrimEnd('\') + '\' } else { $null }

    if ($resolvedDirectory -match '^[A-Za-z]:\\?$' -or ($sysRoot -and ($resolvedDirectory.TrimEnd('\') + '\').StartsWith($sysRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to use '$resolvedDirectory' -- path is a drive root or system directory."
    }

    return $resolvedDirectory
}
