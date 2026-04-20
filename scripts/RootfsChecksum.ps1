function Get-RemoteText([string]$Uri) {
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -ErrorAction Stop
    if ($response.Content -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($response.Content)
    }
    return [string]$response.Content
}

function Get-PublishedSha256([string]$ChecksumUri, [string]$FileName) {
    $checksums = Get-RemoteText $ChecksumUri
    $sha256Pattern = '[0-9A-Fa-f]{64}'
    $filePattern = [regex]::Escape($FileName)
    $matchedLine = ($checksums -split "\r?\n" |
        Where-Object { $_ -match "^$sha256Pattern\s+\*?$filePattern$" } |
        Select-Object -First 1)
    if (-not $matchedLine) {
        throw "Could not find checksum for '$FileName' in $ChecksumUri"
    }

    return ([regex]::Match($matchedLine, "^$sha256Pattern").Value).ToLower()
}
