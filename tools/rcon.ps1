# =============================================================================
#  ESL-MOD - send a command to the running server (IW4x rcon)
#
#  The dedicated server has no console window, so rcon is how it is driven.
#  IW4x speaks its own little protocol on the game port:
#
#      FF FF FF FF + "rcon <password> <command>" + NUL     -> UDP <host>:<port>
#      response: FF FF FF FF + "print \"<output>\""
#
#  The password is read from the installed server config unless -Password is
#  given, so the common case is just:
#
#      tools\rcon.cmd sv_hostname
#      tools\rcon.cmd fast_restart        (ends the match, same map again)
#      tools\rcon.cmd map_rotate          (ends the match, next map)
#      tools\rcon.cmd map mp_terminal     (ends the match, jump to a map)
#      tools\rcon.cmd kick <name>
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\rcon.ps1 <command...>
#      ... -Server 192.168.31.148 -Port 28960 -Password secret -Timeout 4
#
#  NOTE: the parameter is -Server, not -Host: $Host is a read-only automatic
#  variable in PowerShell and cannot be used as a parameter name.
# =============================================================================

[CmdletBinding()]
param(
    # the whole command as one string, e.g. "map mp_terminal" - tools\rcon.cmd
    # passes "%*" through so spaces survive
    [string] $Command  = '',

    [string] $Server   = '127.0.0.1',
    [string] $Iw4xPath = 'D:\Games\iw4x',
    [int]    $Port     = 28960,
    [int]    $Timeout  = 4,
    [string] $Password = ''
)

$ErrorActionPreference = 'Stop'

$Command = $Command.Trim()

if (-not $Command) {
    throw 'usage: tools\rcon.ps1 -Command "<command>"   e.g. tools\rcon.ps1 -Command map_rotate'
}

# --- password ---------------------------------------------------------------
if (-not $Password) {
    $cfg = Join-Path $Iw4xPath 'mods\ESL-MOD\configs\ESL-MOD_server.cfg'
    if (Test-Path -LiteralPath $cfg) {
        foreach ($line in (Get-Content -LiteralPath $cfg -Encoding UTF8)) {
            if ($line -match '^\s*set\s+rcon_password\s+"?([^"\s]+)"?') {
                $Password = $Matches[1]
                break
            }
        }
    }
}

if (-not $Password) {
    throw "no rcon password found - set one in $Iw4xPath\mods\ESL-MOD\configs\ESL-MOD_server.cfg, or pass -Password"
}

# --- send --------------------------------------------------------------------
$text    = 'rcon ' + $Password + ' ' + $Command
$payload = [System.Text.Encoding]::GetEncoding(28591).GetBytes(
                ([char]255 + [char]255 + [char]255 + [char]255 + $text + [char]0))

$udp = New-Object System.Net.Sockets.UdpClient
$udp.Client.ReceiveTimeout = $Timeout * 1000

try {
    $udp.Connect($Server, $Port)
    [void]$udp.Send($payload, $payload.Length)

    $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $reply = $udp.Receive([ref]$ep)
} catch {
    # IW4x only answers when the command produces output, so silence is not proof
    # of failure - "sv_hostname" answers, "fast_restart" typically does not.
    Write-Output ('no reply from ' + $Server + ':' + $Port)
    Write-Output '  the command may still have run - IW4x replies only when there is output.'
    Write-Output '  to prove the connection works, try:  tools\rcon.cmd sv_hostname'
    exit 1
} finally {
    $udp.Close()
}

# --- print -------------------------------------------------------------------
$raw = [System.Text.Encoding]::GetEncoding(28591).GetString($reply)
$raw = $raw -replace '^[\xFF]{4}', ''      # strip the FF FF FF FF header

if ($raw -match '^\s*print\s+"?(.*)$') { $raw = $Matches[1] }

Write-Output ($raw.TrimEnd([char]0, '"', "`r", "`n", ' '))
