# =============================================================================
#  ESL-MOD - publish the mod over HTTP so IW4x can download it automatically
#
#  IW4x's mod download is HTTP based and driven by two server dvars:
#
#      sv_wwwDownload 1
#      sv_wwwBaseUrl  "http://<host-or-ip>:<port>"
#
#  The client asks the game server for the mod list, then fetches the files from
#  that base url (HTTP only - the client refuses HTTPS).  This script lays out
#  the web root and, with -Serve, starts a small static web server on it.
#
#      tools\publish-mod.cmd                     -> stage the files, print the dvars
#      tools\publish-mod.cmd -Serve              -> stage + start the web server
#      tools\publish-mod.cmd -Serve -Port 8080   -> same, different port
#
#  The web root gets the mod under several path shapes, because which one the
#  client asks for is not documented: the access log (-Serve writes one) shows
#  the real requests the first time a client tries.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\publish-mod.ps1 -Serve
# =============================================================================

[CmdletBinding()]
param(
    [int]    $Port     = 8080,
    [string] $Iw4xPath = 'D:\Games\iw4x',
    [string] $BaseUrl  = '',          # printed config value; defaults to the LAN ip
    [switch] $Serve
)

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$modSrc  = Join-Path $Iw4xPath 'mods\ESL-MOD'
$webRoot = Join-Path $root 'build\webserve'
$logFile = Join-Path $root 'build\webserve-access.log'

if (-not (Test-Path -LiteralPath (Join-Path $modSrc 'z_eslmod.iwd'))) {
    throw "Mod not found at $modSrc - run tools\install.ps1 first"
}

# --- stage the web root -------------------------------------------------------
if (Test-Path -LiteralPath $webRoot) {
    Remove-Item -LiteralPath $webRoot -Recurse -Force
}

$shapes = @(
    'mods\ESL-MOD',      # mods/ESL-MOD/<file>
    'mods',              # mods/<file>
    ''                   # <file>
)

foreach ($shape in $shapes) {
    $dir = if ($shape) { Join-Path $webRoot $shape } else { $webRoot }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    Copy-Item -LiteralPath (Join-Path $modSrc 'z_eslmod.iwd') -Destination $dir -Force

    $cfgSrc = Join-Path $modSrc 'configs'
    if (Test-Path -LiteralPath $cfgSrc) {
        Copy-Item -LiteralPath $cfgSrc -Destination (Join-Path $dir 'configs') -Recurse -Force
    }
}

# copy just the iwd under the bare name too, for good measure
Copy-Item -LiteralPath (Join-Path $modSrc 'z_eslmod.iwd') -Destination (Join-Path $webRoot 'mods\ESL-MOD.iwd') -Force

# --- what to put on the server ------------------------------------------------
if (-not $BaseUrl) {
    $ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4Address -and $_.IPv4DefaultGateway } |
           Select-Object -First 1).IPv4Address.IPAddress
    $BaseUrl = 'http://' + $ip + ':' + $Port
}

Write-Output ''
Write-Output 'Web root staged:'
Get-ChildItem -LiteralPath $webRoot -Recurse -File | ForEach-Object {
    Write-Output ('  ' + $_.FullName.Substring($webRoot.Length + 1) + '  (' + $_.Length + ' bytes)')
}

Write-Output ''
Write-Output 'Put this in mods\ESL-MOD\configs\ESL-MOD_server.cfg:'
Write-Output ('    set sv_wwwDownload 1')
Write-Output ('    set sv_wwwBaseUrl  "' + $BaseUrl + '"')
Write-Output ''
Write-Output 'Players outside the LAN need that TCP port forwarded on the router too'
Write-Output ('    TCP ' + $Port + ' -> this PC:' + $Port)
Write-Output ''

if (-not $Serve) {
    Write-Output 'Serve it with the -Serve switch, or run the server yourself:'
    Write-Output ('    powershell -File tools\dev\httpd.ps1 -Port ' + $Port + ' -Root "' + $webRoot + '"')
    exit 0
}

# --- start the web server -----------------------------------------------------
# tools\dev\httpd.ps1 is a dependency-free TcpListener server: it needs no admin
# rights (unlike HttpListener) and it logs every request, which is how the
# expected url layout for the client gets discovered.
$httpd = Join-Path $PSScriptRoot 'dev\httpd.ps1'
if (-not (Test-Path -LiteralPath $httpd)) { throw "missing: $httpd" }

if (Test-Path -LiteralPath $logFile) { Remove-Item -LiteralPath $logFile -Force }

$args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $httpd,
          '-Port', "$Port", '-Root', $webRoot, '-Log', $logFile)

$proc = Start-Process -FilePath 'powershell' -ArgumentList $args -PassThru -WindowStyle Hidden

Start-Sleep -Seconds 3

if ($proc.HasExited) {
    Write-Output ('web server exited immediately - see ' + $logFile)
    Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ('  ' + $_) }
    exit 1
}

Write-Output ('web server : pid ' + $proc.Id + ' on port ' + $Port)
Write-Output ('web root   : ' + $webRoot)
Write-Output ('access log : ' + $logFile)
Write-Output ''
Write-Output 'Test it:'
Write-Output ('    http://127.0.0.1:' + $Port + '/mods/z_eslmod.iwd')
Write-Output ''
Write-Output 'Stop it with:  Stop-Process -Id ' + $proc.Id
