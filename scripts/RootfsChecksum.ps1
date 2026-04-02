function Get-RemoteText([string]$Uri) {
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -ErrorAction Stop
    if ($response.Content -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($response.Content)
    }
    return [string]$response.Content
}

function Get-PublishedSha256([string]$ChecksumUri, [string]$FileName) {
    $checksums = Get-RemoteText $ChecksumUri
    $matchedLine = ($checksums -split "`n" |
        Where-Object { $_ -match [regex]::Escape($FileName) } |
        Select-Object -First 1)
    if (-not $matchedLine) {
        throw "Could not find checksum for '$FileName' in $ChecksumUri"
    }

    $expectedHash = $matchedLine.Trim() -replace '\s+.*', ''
    return $expectedHash.ToLower()
}
