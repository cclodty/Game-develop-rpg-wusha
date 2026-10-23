param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8071,
    [switch]$NoBrowser
)

# Windows PowerShell 5.1 and built-in .NET only; nothing is installed.
$ErrorActionPreference = 'Stop'
$webRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\build\web'))
$url = "http://127.0.0.1:$Port/"

function Send-Response {
    param($Stream, [int]$Status, [string]$Reason, [string]$ContentType,
          [byte[]]$Body, [bool]$HeadOnly = $false)
    $header = "HTTP/1.1 $Status $Reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`nCache-Control: no-cache`r`nX-Content-Type-Options: nosniff`r`n`r`n"
    $bytes = [Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($bytes, 0, $bytes.Length)
    if (-not $HeadOnly -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
}

function Send-ErrorResponse {
    param($Stream, [int]$Status, [string]$Reason, [bool]$HeadOnly = $false)
    Send-Response $Stream $Status $Reason 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes("$Reason`n")) $HeadOnly
}

function Serve-Client {
    param($Client)
    $stream = $Client.GetStream()
    $stream.ReadTimeout = 3000
    $stream.WriteTimeout = 15000
    $headOnly = $false
    $file = $null
    try {
        # Limit request headers and wait only briefly for an incomplete request.
        $headerBytes = New-Object 'System.Collections.Generic.List[byte]'
        $complete = $false
        while ($headerBytes.Count -lt 16384) {
            $nextByte = $stream.ReadByte()
            if ($nextByte -lt 0) { return }
            $headerBytes.Add([byte]$nextByte)
            $count = $headerBytes.Count
            if ($count -ge 4 -and $headerBytes[$count - 4] -eq 13 -and
                $headerBytes[$count - 3] -eq 10 -and $headerBytes[$count - 2] -eq 13 -and
                $headerBytes[$count - 1] -eq 10) {
                $complete = $true
                break
            }
        }
        if (-not $complete) { Send-ErrorResponse $stream 431 'Request Header Fields Too Large'; return }
        $requestLine = ([Text.Encoding]::ASCII.GetString($headerBytes.ToArray()) -split "`r`n", 2)[0]
        if ($requestLine -notmatch '^([A-Z]+) ([^ ]+) HTTP/1\.[01]$') {
            Send-ErrorResponse $stream 400 'Bad Request'; return
        }
        $method = $Matches[1]
        $target = $Matches[2]
        $headOnly = $method -eq 'HEAD'
        if ($method -ne 'GET' -and -not $headOnly) {
            Send-ErrorResponse $stream 405 'Method Not Allowed'; return
        }
        $pathPart = ($target -split '\?', 2)[0]
        $decoded = [Uri]::UnescapeDataString($pathPart)
        # Reject Windows drive/UNC paths and traversal before resolving the file.
        $segments = $decoded -split '/'
        if (-not $decoded.StartsWith('/') -or $decoded -match '[\\:\x00-\x1f<>"|?*]' -or
            @($segments | Where-Object { $_.EndsWith('.') -or $_.EndsWith(' ') }).Count -gt 0) {
            Send-ErrorResponse $stream 400 'Bad Request' $headOnly; return
        }
        $relative = $decoded.TrimStart('/')
        if ($relative -eq '') { $relative = 'index.html' }
        $path = [IO.Path]::GetFullPath((Join-Path $webRoot $relative))
        $rootPrefix = $webRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Send-ErrorResponse $stream 400 'Bad Request' $headOnly; return
        }
        if (-not [IO.File]::Exists($path)) {
            Send-ErrorResponse $stream 404 'Not Found' $headOnly; return
        }
        $contentType = switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
            '.html' { 'text/html; charset=utf-8' }
            '.js'   { 'application/javascript; charset=utf-8' }
            '.wasm' { 'application/wasm' }
            '.css'  { 'text/css; charset=utf-8' }
            '.png'  { 'image/png' }
            '.svg'  { 'image/svg+xml' }
            '.json' { 'application/json; charset=utf-8' }
            '.txt'  { 'text/plain; charset=utf-8' }
            default { 'application/octet-stream' }
        }
        $file = [IO.File]::OpenRead($path)
        $header = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($file.Length)`r`nConnection: close`r`nCache-Control: no-cache`r`nX-Content-Type-Options: nosniff`r`n`r`n"
        $bytes = [Text.Encoding]::ASCII.GetBytes($header)
        $stream.Write($bytes, 0, $bytes.Length)
        if (-not $headOnly) { $file.CopyTo($stream) }
    }
    catch {
        # Closing a tab or a timed-out request must not stop the game server.
    }
    finally {
        if ($null -ne $file) { $file.Dispose() }
        $Client.Close()
    }
}

$missingBuild = $false
foreach ($requiredFile in @('index.html', 'index.js', 'index.wasm', 'index.pck')) {
    if (-not [IO.File]::Exists((Join-Path $webRoot $requiredFile))) { $missingBuild = $true }
}
if ($missingBuild) {
    Write-Host 'Game files are missing. Extract the ENTIRE downloaded ZIP first.' -ForegroundColor Yellow
    Write-Host 'Keep Play-Windows.cmd, tools, and build together in the extracted folder.'
    exit 1
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
}
catch {
    Write-Host "Cannot start the game at $url" -ForegroundColor Yellow
    Write-Host 'Another program may already be using this port.'
    Write-Host 'If a game launcher window is already open, use it or close it and try again.'
    Write-Host 'The port is kept unchanged so your existing browser save stays available.'
    exit 1
}

Write-Host ''
Write-Host 'JIANGHU WEIYUAN CARDS - The game is ready.' -ForegroundColor Green
Write-Host "Open: $url"
Write-Host 'Keep this window open while playing. Close it to stop the game server.'
Write-Host 'Use the same browser and this address next time to continue your save.'
Write-Host ''
if (-not $NoBrowser) {
    try { Start-Process $url }
    catch { Write-Host 'Please open the address above in your browser.' }
}

$waiting = New-Object 'System.Collections.Generic.List[object]'
try {
    while ($true) {
        while ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            $waiting.Add(@{ Client = $client; Accepted = [DateTime]::UtcNow })
        }
        for ($index = $waiting.Count - 1; $index -ge 0; $index--) {
            $entry = $waiting[$index]
            # Browsers may open idle connections in advance. Do not block on them.
            try {
                if ($entry.Client.GetStream().DataAvailable) {
                    Serve-Client $entry.Client
                    $waiting.RemoveAt($index)
                }
                elseif (([DateTime]::UtcNow - $entry.Accepted).TotalSeconds -ge 5) {
                    $entry.Client.Close()
                    $waiting.RemoveAt($index)
                }
            }
            catch {
                # A browser can reset even an unused speculative connection.
                $entry.Client.Close()
                $waiting.RemoveAt($index)
            }
        }
        Start-Sleep -Milliseconds 15
    }
}
finally {
    foreach ($entry in $waiting) { $entry.Client.Close() }
    $listener.Stop()
}
