# =============================================================================
#  ESL-MOD development helper - turn an mp3 into the wav the game loads
#
#  The engine's short sounds are 16 bit PCM wav files; the only .mp3 files in the
#  game data are long, streamed ambience tracks.  A menu sound has to be a wav,
#  so this converts one with the Windows media pipeline (Media Foundation, through
#  the WinRT transcoder - no ffmpeg or other tooling needed).
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\mp3-to-wav.ps1 `
#          -In voting_short.mp3 -Out src\sound\esl\voting_short.wav
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $In,
    [Parameter(Mandatory = $true)] [string] $Out
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not [System.IO.Path]::IsPathRooted($In))  { $In  = Join-Path $root $In }
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path $root $Out }

if (-not (Test-Path -LiteralPath $In)) {
    throw "Input not found: $In"
}

$outDir  = Split-Path -Parent $Out
$outName = Split-Path -Leaf $Out

if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime

[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]             | Out-Null
[Windows.Storage.StorageFolder, Windows.Storage, ContentType = WindowsRuntime]           | Out-Null
[Windows.Storage.CreationCollisionOption, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType = WindowsRuntime]                       | Out-Null
[Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType = WindowsRuntime]          | Out-Null
[Windows.Media.MediaProperties.AudioEncodingQuality, Windows.Media.MediaProperties, ContentType = WindowsRuntime]          | Out-Null

# WinRT async has no PowerShell syntax: its AsTask bridge marshals IAsyncOperation<T>
# but not IAsyncAction (which TranscodeAsync returns), and neither IAsyncInfo.Status
# nor GetResults is reachable through the COM object.  The file operations below are
# therefore awaited with the standard AsTask bridge, and the transcode itself - the
# one IAsyncAction - is waited out by watching the output file settle.
$asTaskForOperation = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Wait-Operation($operation, [Type] $resultType) {
    $task = $asTaskForOperation.MakeGenericMethod($resultType).Invoke($null, @($operation))
    $task.Wait(-1) | Out-Null
    return $task.Result
}

$source = Wait-Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($In)) ([Windows.Storage.StorageFile])
$folder = Wait-Operation ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($outDir)) ([Windows.Storage.StorageFolder])
$target = Wait-Operation ($folder.CreateFileAsync($outName, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
# 44.1 kHz 16 bit stereo.  Mono would be half the size, but the WAV profile the
# Windows transcoder builds cannot be narrowed - setting ChannelCount on it makes
# PrepareFileTranscodeAsync() refuse the job outright.
$profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateWav([Windows.Media.MediaProperties.AudioEncodingQuality]::High)

$transcoder = New-Object Windows.Media.Transcoding.MediaTranscoder

$prepared = Wait-Operation ($transcoder.PrepareFileTranscodeAsync($source, $target, $profile)) ([Windows.Media.Transcoding.PrepareTranscodeResult])

if (-not $prepared.CanTranscode) {
    throw ('Windows cannot transcode ' + $In + ': ' + $prepared.FailureReason)
}

# The target StorageFile is left in place: the transcoder was handed that exact
# file, and deleting it underneath (the obvious way to start from a clean slate)
# makes the write land on a file that no longer exists.  ReplaceExisting already
# empties it, and the wait below ignores the empty file until the encoder fills it.
#
# The IAsyncAction has to stay referenced as well: PowerShell releases the COM
# wrapper as soon as the expression value is gone, and the cancelling release takes
# the transcode with it.
$transcodeAction = $prepared.TranscodeAsync()

$deadline = (Get-Date).AddSeconds(60)
$last     = -1

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200

    if (-not (Test-Path -LiteralPath $Out)) { continue }

    $size = (Get-Item -LiteralPath $Out).Length

    # two equal, non-empty readings: the encoder has finished writing
    if ($size -gt 0 -and $size -eq $last) { break }

    $last = $size
}

if (-not (Test-Path -LiteralPath $Out) -or (Get-Item -LiteralPath $Out).Length -eq 0) {
    throw ('the transcode wrote nothing to ' + $Out + ' - the file has to be a readable mp3')
}

$written = Get-Item -LiteralPath $Out

Write-Output ('converted : ' + $In)
Write-Output ('          -> ' + $written.FullName + '  (' + $written.Length + ' bytes)')
