# =============================================================================
#  ESL-MOD development helper - tiny static web server
#
#  Serves a folder over HTTP and logs every request (method, path, status,
#  bytes) to the console and to a log file.  Written with a raw TcpListener on
#  purpose: System.Net.HttpListener needs a url ACL (admin) to listen on
#  anything but localhost, TcpListener needs nothing.
#
#  Built for one job: find out which paths IW4x's mod downloader actually asks
#  for.  Start it, point sv_wwwBaseUrl at it, watch the log.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\httpd.ps1
#      ... -Port 8080 -Root "D:\Games\projects\esl-mod\build\webserve"
# =============================================================================

[CmdletBinding()]
param(
    [int]    $Port = 8080,
    [string] $Root = '',
    [string] $Log  = ''
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $Root) { $Root = Join-Path $repoRoot 'build\webserve' }
if (-not (Test-Path -LiteralPath $Root)) { throw "web root not found: $Root (run tools\publish-mod.ps1)" }
$Root = (Resolve-Path -LiteralPath $Root).Path

if (-not $Log) { $Log = Join-Path $repoRoot 'build\webserve-access.log' }

function Write-Log([string] $line) {
    $text = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $line
    Write-Output $text
    try { Add-Content -LiteralPath $Log -Value $text -ErrorAction Stop } catch { }
}

function Get-ContentType([string] $path) {
    switch ([System.IO.Path]::GetExtension($path).ToLowerInvariant()) {
        '.iwd'  { 'application/octet-stream' }
        '.cfg'  { 'text/plain; charset=utf-8' }
        '.json' { 'application/json' }
        '.txt'  { 'text/plain; charset=utf-8' }
        '.html' { 'text/html; charset=utf-8' }
        default { 'application/octet-stream' }
    }
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
$listener.Start()

Write-Log ('listening on 0.0.0.0:' + $Port + '  root=' + $Root)
Write-Log ('log file: ' + $Log)

while ($true) {
    $client = $listener.AcceptTcpClient()

    try {
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)

        $requestLine = $reader.ReadLine()
        if (-not $requestLine) { $client.Close(); continue }

        $parts  = $requestLine.Split(' ')
        $method = $parts[0]
        $target = if ($parts.Count -gt 1) { $parts[1] } else { '/' }

        # drain the headers
        while ($true) {
            $header = $reader.ReadLine()
            if ($null -eq $header -or $header -eq '') { break }
        }

        $path = [System.Uri]::UnescapeDataString(($target -split '\?')[0])
        $rel  = $path.TrimStart('/')
        if ($rel -eq '') { $rel = '.' }

        $full = Join-Path $Root $rel

        $status = '404 Not Found'
        $ctype  = 'text/plain; charset=utf-8'
        $body   = [System.Text.Encoding]::UTF8.GetBytes('not found')

        if (Test-Path -LiteralPath $full -PathType Container) {
            $names = @(Get-ChildItem -LiteralPath $full | ForEach-Object { $_.Name })
            $body  = [System.Text.Encoding]::UTF8.GetBytes(($names -join "`r`n"))
            $status = '200 OK'
            $ctype  = 'text/plain; charset=utf-8'
        } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
            # guard against escaping the root through the mapped path
            $resolved = (Resolve-Path -LiteralPath $full).Path
            if ($resolved.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
                $body   = [System.IO.File]::ReadAllBytes($resolved)
                $status = '200 OK'
                $ctype  = Get-ContentType $resolved
            } else {
                $status = '403 Forbidden'
                $body   = [System.Text.Encoding]::UTF8.GetBytes('forbidden')
            }
        }

        $head = 'HTTP/1.1 ' + $status + "`r`n" +
                'Content-Type: ' + $ctype + "`r`n" +
                'Content-Length: ' + $body.Length + "`r`n" +
                'Connection: close' + "`r`n`r`n"

        $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
        $stream.Write($headBytes, 0, $headBytes.Length)

        if ($method -ne 'HEAD' -and $body.Length -gt 0) {
            $stream.Write($body, 0, $body.Length)
        }

        $stream.Flush()
        Write-Log ($method + ' ' + $target + ' -> ' + $status + ' (' + $body.Length + ' bytes)')
    } catch {
        Write-Log ('request failed: ' + $_.Exception.Message)
    } finally {
        try { $client.Close() } catch { }
    }
}
