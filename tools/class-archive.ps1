# =============================================================================
#  ESL-MOD - save the class archive to a file, so classes survive a restart
#
#  The mod keeps every player's ESL class in server dvars - esl_class_<id>_<type>
#  and esl_type_<id> - and that is what makes a class survive a *map change*.
#  Server dvars die with the process, so they do not survive a restart, and every
#  player then rebuilds their class from the type defaults.
#
#  This reads them back out of the running server (IW4x rcon "dvarlist") and writes
#  them into configs\ESL-MOD_classes.cfg, which the server execs at boot - so the
#  classes are back before the first level of the next run loads.
#
#  Run it while the server is up:  tools\server.cmd restart does exactly that.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\class-archive.ps1
#      ... -Server 192.168.31.148 -Port 28960
#      ... -Prune                             rewrite the file even when there is
#                                             nothing to save (drops what is in it)
#
#  NOTE: the id in the name is the player's guid (see esl_archiveId() in _esl.gsc),
#  so a line here reads "esl_class_bbdb7963f59fc1ec_sniper"; a player who has
#  neither a guid nor an xuid falls back to their name, filtered down to the
#  characters a dvar name may contain.
# =============================================================================

[CmdletBinding()]
param(
    [string] $Iw4xPath = 'D:\Games\iw4x',
    [string] $Server   = '127.0.0.1',
    [int]    $Port     = 28960,

    # Write the file even when the server has no archive dvar at all.  The default
    # is deliberately the other way round - a server that is not up yet answers
    # nothing, and that must not cost anybody their saved class.  This is how the
    # file is emptied on purpose: after the archive id changed, say, or with
    # esl_keep_classes 0.
    [switch] $Prune
)

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$rcon    = Join-Path $PSScriptRoot 'rcon.ps1'
$modCfg  = Join-Path $Iw4xPath 'mods\ESL-MOD\configs'
$outRepo = Join-Path $root 'config\ESL-MOD_classes.cfg'
$outMod  = Join-Path $modCfg 'ESL-MOD_classes.cfg'

if (-not (Test-Path -LiteralPath $rcon)) {
    throw "rcon helper not found: $rcon"
}

# --- read the archive out of the live server ---------------------------------
# ONE query, not one per family: IW4x answers a single command per packet and
# only when it produces output, and two back-to-back requests leave the second
# one unanswered often enough to matter.  "dvarlist esl_" lists every dvar the
# mod owns, and the two archive families are picked out of that.
# The reply comes back as one string with embedded newlines, so it has to be
# split before it can be matched line by line.
$reply = @(& $rcon -Command 'dvarlist esl_' -Server $Server -Port $Port -Iw4xPath $Iw4xPath 2>$null)

$lines = @()
foreach ($chunk in $reply) {
    $lines += [string]$chunk -split "`r?`n"
}

$classes = @()
$types   = @()

foreach ($line in $lines) {
    # a dvarlist line is:      <name> "<value>"
    $m = [regex]::Match($line, '^\s*([A-Za-z0-9_]+)\s+"(.*)"\s*$')

    if (-not $m.Success) { continue }

    $name  = $m.Groups[1].Value
    $value = $m.Groups[2].Value

    # An empty value carries nothing (reading one back is a no-op), so it is not
    # saved - and that is also how a stale dvar is retired:
    #     rcon set esl_class_b_sniper ""
    # An archive id written by an older build would otherwise be saved here and
    # loaded again at every boot, for ever.
    if ($value -eq '') { continue }

    if     ($name -match '^esl_class_[A-Za-z0-9]+_[A-Za-z0-9]+$') {
        $classes += [pscustomobject]@{ Name = $name; Value = $value }
    }
    elseif ($name -match '^esl_type_[A-Za-z0-9]+$') {
        $types   += [pscustomobject]@{ Name = $name; Value = $value }
    }
}

if ($classes.Count -eq 0 -and $types.Count -eq 0 -and -not $Prune) {
    # writing an empty file here would throw away the classes saved by an earlier
    # run - a server that is simply not up yet must not cost anybody their class
    Write-Output ('class-archive: nothing to save - ' + $lines.Count + ' dvar line(s) seen, no esl_class_/esl_type_ among them')
    Write-Output '               (is the server up, and has anybody committed a class yet?)'
    Write-Output '               file left alone'
    return
}

# --- write it ----------------------------------------------------------------
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('// =============================================================================')
[void]$sb.AppendLine('//  ESL-MOD -- saved ESL classes (generated - do not edit by hand)')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('//  Written by tools\class-archive.ps1 on ' + $stamp + '.')
[void]$sb.AppendLine('//')
[void]$sb.AppendLine('//  The mod keeps a class in server dvars - esl_class_<id>_<type> and')
[void]$sb.AppendLine('//  esl_type_<id> - and those outlive a map change but not a restart.  These')
[void]$sb.AppendLine('//  are the same dvars, read back out of the running server and exec''d at boot')
[void]$sb.AppendLine('//  so the classes are there again after a restart.  Delete this file to start')
[void]$sb.AppendLine('//  everybody from the type defaults.')
[void]$sb.AppendLine('// =============================================================================')
[void]$sb.AppendLine('')

foreach ($dvar in (@($classes) + @($types) | Sort-Object Name)) {
    [void]$sb.AppendLine('set ' + $dvar.Name + ' "' + $dvar.Value + '"')
}

Set-Content -LiteralPath $outRepo -Value $sb.ToString() -Encoding ASCII

if (-not (Test-Path -LiteralPath $modCfg)) {
    New-Item -ItemType Directory -Force -Path $modCfg | Out-Null
}

Copy-Item -LiteralPath $outRepo -Destination $outMod -Force

Write-Output ('class-archive: ' + $classes.Count + ' class dvar(s), ' + $types.Count + ' type dvar(s)')
Write-Output ('               ' + $outMod)
