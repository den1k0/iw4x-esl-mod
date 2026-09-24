# =============================================================================
#  ESL-MOD development helper - "why is my server not in the browser?"
#
#  Answers the question with data instead of guesswork:
#
#    1. which IPv4 addresses this machine has  (the router's port forwards must
#       point at one of them - DHCP moving the machine is the classic failure:
#       the forwards then point at an address nothing answers on, the master
#       cannot query the server back, and the server disappears from the list)
#    2. the public IP the router presents
#    3. whether the game server and its embedded web server are alive
#       (/info and /list on the game port)
#    4. whether the server appears in the list the IW4x client last fetched -
#       the same data the in-game browser shows, read from
#       <game>\players\server_cache.json
#
#  It does not query the master itself: the master protocol is IW4x's own, and
#  the client's cache is the exact thing the user is looking at.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\check-master-list.ps1
#      ... -Match "ESL-MOD" -Cache "D:\Games\iw4x\players\server_cache.json"
# =============================================================================

[CmdletBinding()]
param(
    [string] $Match = 'ESL-MOD',
    [string] $Cache = 'D:\Games\iw4x\players\server_cache.json',
    [string] $Info  = 'http://127.0.0.1:28960/info',
    [string] $List  = 'http://127.0.0.1:28960/list'
)

$ErrorActionPreference = 'Continue'

# -----------------------------------------------------------------------------
#  1. this machine's addresses
# -----------------------------------------------------------------------------
Write-Output '== this machine =='

$localIps = @()

try {
    $localIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })

    foreach ($ip in $localIps) {
        Write-Output ('  ' + $ip.IPAddress + '/' + $ip.PrefixLength +
                      '  ' + $ip.InterfaceAlias + '  (' + $ip.PrefixOrigin + ')')
    }
}
catch {
    Write-Output ('  could not read the addresses: ' + $_.Exception.Message)
}

Write-Output '  ^ the router must forward UDP 28960 (game) and TCP 28960 (mod download)'
Write-Output '    to one of the addresses above. A different address = not listed, no joins.'

$publicIp = ''

try {
    $publicIp = (Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 15).Content.Trim()
    Write-Output ('  public IP: ' + $publicIp)
}
catch {
    Write-Output ('  public IP: unknown (' + $_.Exception.Message + ')')
}

# -----------------------------------------------------------------------------
#  2. is the server itself alive?
# -----------------------------------------------------------------------------
Write-Output ''
Write-Output '== server =='

$hostname = ''

try {
    $raw = (Invoke-WebRequest -Uri $Info -UseBasicParsing -TimeoutSec 10).Content
    $json = $raw | ConvertFrom-Json

    $hostname = $json.status.sv_hostname
    Write-Output ('  /info ok    : ' + $hostname)
    Write-Output ('  map         : ' + $json.status.mapname +
                  '   gametype: ' + $json.status.g_gametype +
                  '   players: ' + @($json.players).Count + '/' + $json.status.sv_maxclients)
    Write-Output ('  gamedir     : ' + $json.status.fs_game + '   checksum: ' + $json.status.checksum +
                  '   level: ' + $json.status.sv_securityLevel)
}
catch {
    Write-Output ('  /info FAILED: ' + $_.Exception.Message)
    Write-Output '  ^ the game is not running (tools\server-start.cmd) - nothing else here matters.'
}

try {
    $mods = ((Invoke-WebRequest -Uri $List -UseBasicParsing -TimeoutSec 10).Content) | ConvertFrom-Json

    foreach ($m in $mods) {
        Write-Output ('  /list ok    : ' + $m.name + '  ' + $m.size + ' bytes  sha256 ' + $m.hash.Substring(0, 16) + '...')
    }

    if (@($mods).Count -eq 0) { Write-Output '  /list ok    : (no mod files offered)' }
}
catch {
    Write-Output ('  /list FAILED: ' + $_.Exception.Message + '  (mod download would not work)')
}

# -----------------------------------------------------------------------------
#  3. what the client's browser shows
# -----------------------------------------------------------------------------
Write-Output ''
Write-Output '== master list (as cached by the IW4x client) =='

if (-not (Test-Path -LiteralPath $Cache)) {
    Write-Output ('  no cache at ' + $Cache)
    Write-Output '  start the game and open the server browser once, then run this again.'
    exit 0
}

$age = [math]::Round(((Get-Date) - (Get-Item -LiteralPath $Cache).LastWriteTime).TotalMinutes, 1)

try {
    $servers = @((Get-Content -LiteralPath $Cache -Raw | ConvertFrom-Json).servers)
}
catch {
    Write-Output ('  could not parse the cache: ' + $_.Exception.Message)
    exit 1
}

Write-Output ('  cache       : ' + $Cache)
Write-Output ('  age         : ' + $age + ' minutes, ' + $servers.Count + ' servers')

$byName = @($servers | Where-Object { $_.hostname -and $_.hostname -like ('*' + $Match + '*') })
$byIp   = @()

if ($publicIp) {
    $byIp = @($servers | Where-Object { $_.address -and $_.address.StartsWith($publicIp + ':') })
}

if ($byName.Count -eq 0 -and $byIp.Count -eq 0) {
    Write-Output '  RESULT      : not listed'
    Write-Output ''
    Write-Output '  The master server verifies a server by querying it from the internet before'
    Write-Output '  listing it. Not listed therefore means "not reachable on UDP 28960":'
    Write-Output '    * the forwards point at another address than this machine has (see above)'
    Write-Output '    * or the rule is missing/wrong, or UPnP left a stale mapping behind'
    Write-Output '    * or the server is not running (see the /info result above)'
    Write-Output '  Until that is fixed, connect around the router:'
    Write-Output '    connect 127.0.0.1:28960        (same machine)'
    if ($localIps.Count -gt 0) {
        Write-Output ('    connect ' + $localIps[0].IPAddress + ':28960     (another machine on the LAN)')
    }
}
else {
    Write-Output '  RESULT      : LISTED'
    foreach ($s in ($byName + $byIp | Sort-Object address -Unique)) {
        Write-Output ('    ' + $s.address + '  ' + $s.hostname)
        Write-Output ('      map ' + $s.mapname + '  ' + $s.clients + '/' + $s.maxClients +
                      '  gametype ' + $s.gametype + '  mod "' + $s.mod + '"')
    }
    Write-Output '  If the browser still does not show it, refresh the list in game (the cache above is what it read).'
}
