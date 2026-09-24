# =============================================================================
#  ESL-MOD dedicated server control
#
#      tools\server.cmd start      (or: tools\server-start.cmd)
#      tools\server.cmd stop       (or: tools\server-stop.cmd)
#      tools\server.cmd status
#      tools\server.cmd restart
#
#  Reads config\ESL-MOD_server.cfg (installed as
#  mods\ESL-MOD\configs\ESL-MOD_server.cfg) - edit that file to change the
#  hostname, port, slots, rcon password or the map rotation.
#
#  IMPORTANT: this script only ever touches the DEDICATED server process.  Your
#  game client is also "iw4x.exe", so a plain "stop every iw4x" would kill the
#  game you are playing in.  The dedicated server is identified by the
#  -dedicated switch on its command line, and nothing else is touched.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\server.ps1 start
#      ... -Action stop        (or restart / status)
#      ... -Iw4xPath "C:\Games\iw4x" -Port 28960 -Map mp_terminal
# =============================================================================

[CmdletBinding()]
param(
    [ValidateSet('start', 'stop', 'restart', 'status')]
    [string] $Action = 'status',

    [string] $Iw4xPath = 'D:\Games\iw4x',
    [int]    $Port     = 28960,

    # start on one specific map instead of the first entry of the rotation
    [string] $Map      = '',

    # start: do not wait for the map to come up before reporting
    [switch] $NoWait
)

$ErrorActionPreference = 'Stop'

$exe       = Join-Path $Iw4xPath 'iw4x.exe'
$modDir    = Join-Path $Iw4xPath 'mods\ESL-MOD'
$consoleLog = Join-Path $modDir 'console_mp.log'
$gameLog    = Join-Path $modDir 'logs\games_mp.log'

# reads the classes back out of the running server - see Save-ClassArchive
$classArchive = Join-Path $PSScriptRoot 'class-archive.ps1'

# The dedicated server, and only the dedicated server: the client is iw4x.exe
# too, but without -dedicated on its command line.
function Get-DedicatedServer {
    @(Get-CimInstance Win32_Process -Filter "Name = 'iw4x.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match '(\s|^)-dedicated(\s|$)' })
}

# Who holds UDP $Port, and is it us?  A bare "the port is in use" is useless on a PC
# that runs the game client as well: the client is iw4x.exe too, it takes 28960 by
# default, and only one of the two processes can bind it.
function Get-PortOwner {
    $endpoints = @(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)

    if ($endpoints.Count -eq 0) { return $null }

    $ownerPid = $endpoints[0].OwningProcess
    $proc     = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
    $name     = if ($proc) { $proc.ProcessName } else { 'unknown' }
    $command  = ''

    if ($name -eq 'iw4x') {
        $info = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $ownerPid) -ErrorAction SilentlyContinue
        if ($info -and $info.CommandLine) { $command = $info.CommandLine }
    }

    return [pscustomobject]@{
        Pid         = $ownerPid
        Name        = $name
        Command     = $command
        IsDedicated = ($command -match '(\s|^)-dedicated(\s|$)')
    }
}

function Describe-PortOwner($owner) {
    if ($null -eq $owner) { return 'nothing' }

    if ($owner.Name -eq 'iw4x') {
        if ($owner.IsDedicated) { return ('a dedicated server (pid ' + $owner.Pid + ')') }
        return ('the game client (pid ' + $owner.Pid + ')')
    }

    return ($owner.Name + ' (pid ' + $owner.Pid + ')')
}

function Get-LastLoadedMap {
    if (-not (Test-Path -LiteralPath $consoleLog)) { return '' }
    try {
        $hits = Get-Content -LiteralPath $consoleLog -ErrorAction Stop |
                Select-String -Pattern 'Server: (mp_\S+)'
        if ($hits) { return $hits[-1].Matches[0].Groups[1].Value }
    } catch { }
    return ''
}

function Show-Status {
    $procs = Get-DedicatedServer
    $owner = Get-PortOwner

    if ($procs.Count -eq 0) {
        Write-Output 'ESL-MOD server: NOT running'
        if ($owner) { Write-Output ('  (UDP ' + $Port + ' is held by ' + (Describe-PortOwner $owner) + ')') }
        return
    }

    # The endpoint's owner is the only way to tell "we are listening" from "somebody
    # else is listening and our server is deaf" - both look like an open port.
    $ownerIsUs = $false
    foreach ($p in $procs) {
        if ($owner -and $owner.Pid -eq $p.ProcessId) { $ownerIsUs = $true }
    }

    foreach ($p in $procs) {
        $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Pid     = $p.ProcessId
            Started = $p.CreationDate
            MemMB   = if ($proc) { [math]::Round($proc.WorkingSet64 / 1MB) } else { 0 }
            Map     = Get-LastLoadedMap
            Port    = if ($ownerIsUs)      { "listening on UDP $Port" }
                      elseif ($owner)      { 'NOT listening - UDP ' + $Port + ' is held by ' + (Describe-PortOwner $owner) }
                      else                 { "NOT listening on UDP $Port" }
        } | Format-List
    }

    if (Test-Path -LiteralPath $gameLog) {
        Write-Output 'Last game sessions (mods\ESL-MOD\logs\games_mp.log):'
        (Get-Content -LiteralPath $gameLog -Tail 6) | ForEach-Object { Write-Output ('  ' + $_) }
    }
}

# The class a player committed lives in server dvars (esl_class_<id>_<type>), which
# are what carries it across a map change but die with the process.  So on the way
# out, while the server can still be asked, they are read back into
# configs\ESL-MOD_classes.cfg - which the server exec's at boot - and the class is
# there again after the restart.
function Save-ClassArchive {
    if (-not (Test-Path -LiteralPath $classArchive)) { return }

    Write-Output 'ESL-MOD server: saving the ESL class archive'

    # a separate process on purpose: the rcon helper exits non-zero when the
    # server does not answer, and that must not take the stop down with it
    # (arguments are positional: -Iw4xPath, -Server, -Port)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $classArchive $Iw4xPath '127.0.0.1' $Port
}

function Start-Server {
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "iw4x.exe not found: $exe (pass -Iw4xPath <folder>)"
    }

    if ((Get-DedicatedServer).Count -gt 0) {
        Write-Output 'ESL-MOD server: already running'
        Show-Status
        return
    }

    $owner = Get-PortOwner

    if ($owner) {
        Write-Warning ('UDP ' + $Port + ' is already in use by ' + (Describe-PortOwner $owner) + ' - the server will fail to bind.')

        if ($owner.Name -eq 'iw4x' -and -not $owner.IsDedicated) {
            Write-Output '  The game client and the dedicated server both take UDP 28960 by default, and two'
            Write-Output '  programs cannot share one UDP port. Either close the game first, or give the'
            Write-Output '  client a port of its own: start it with   +set net_port 28961'
        }
        elseif ($owner.IsDedicated) {
            Write-Output '  That is another dedicated server - stop it first:'
            Write-Output ('    Stop-Process -Id ' + $owner.Pid + '     (or tools\server.cmd stop)')
        }
    }

    # -dedicated is the launcher SWITCH: with only "+set dedicated 2" the engine
    # starts the client UI instead, loads a map and drops back to the menu.
    $argList = @(
        '-dedicated',
        '+set', 'net_port', "$Port",
        '+set', 'fs_game', 'mods/ESL-MOD',
        '+exec', 'configs/ESL-MOD_server.cfg'
    )

    if ($Map) {
        $argList += @('+map', $Map)
    } else {
        $argList += '+map_rotate'
    }

    $p = Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory $Iw4xPath -PassThru
    Write-Output ('ESL-MOD server: starting (pid ' + $p.Id + ')')

    if ($NoWait) { return }

    Start-Sleep -Seconds 15
    $p.Refresh()

    if ($p.HasExited) {
        Write-Output ('ESL-MOD server: FAILED to stay up (exit code ' + $p.ExitCode + ')')
        if (Test-Path -LiteralPath $consoleLog) {
            Write-Output 'Last lines of console_mp.log:'
            (Get-Content -LiteralPath $consoleLog -Tail 15) | ForEach-Object { Write-Output ('  ' + $_) }
        }
        return
    }

    Show-Status
    Write-Output ''
    Write-Output ('Join with: connect 127.0.0.1:' + $Port + '   (or this PC''s LAN IP from another machine)')
}

function Stop-Server {
    $procs = Get-DedicatedServer

    if ($procs.Count -eq 0) {
        Write-Output 'ESL-MOD server: not running'
        return
    }

    # while it is still up: the dvars that hold the classes go away with it
    Save-ClassArchive

    foreach ($p in $procs) {
        Write-Output ('ESL-MOD server: stopping pid ' + $p.ProcessId)
        Stop-Process -Id $p.ProcessId -Force
    }

    Start-Sleep -Seconds 2
    Write-Output 'ESL-MOD server: stopped'
}

switch ($Action) {
    'start'   { Start-Server }
    'stop'    { Stop-Server }
    'restart' { Stop-Server; Start-Sleep -Seconds 2; Start-Server }
    'status'  { Show-Status }
}
