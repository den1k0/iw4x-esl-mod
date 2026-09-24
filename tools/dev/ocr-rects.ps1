# =============================================================================
#  ocr-rects.ps1 - OCR a screenshot and print every word with its pixel rect.
#
#  ocr.ps1 answers "what does the screen say"; this answers "where does it say
#  it".  That is what a menu layout question needs: the game draws in a 640x480
#  space scaled to the window, so a word's pixel rect is comparable with the
#  rects the menu declares, and the distance between two known items gives the
#  scale factor between the two.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\ocr-rects.ps1 -Path error4.png
#      ... -Filter "dmg|head|Primary"     only words matching this regex
# =============================================================================

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Language = 'en-US',
    [string]$Filter   = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    throw "image not found: $Path"
}

$full = (Resolve-Path -LiteralPath $Path).Path

Add-Type -AssemblyName System.Runtime.WindowsRuntime

# the WinRT types have to be loaded before they can be named
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

# await a WinRT IAsyncOperation<T> from PowerShell
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($WinRtTask, $ResultType) {
    $asTask   = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask  = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

$file    = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($full)) ([Windows.Storage.StorageFile])
$stream  = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap  = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()

if ($null -eq $engine) {
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new($Language))
}

if ($null -eq $engine) {
    $available = ([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag }) -join ', '
    throw "no OCR engine for the user profile; available: $available"
}

$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

Write-Output ('image : ' + $full + '  (' + $decoder.PixelWidth + ' x ' + $decoder.PixelHeight + ')')
Write-Output ''

foreach ($line in $result.Lines) {
    foreach ($word in $line.Words) {
        if ($Filter -ne '' -and $word.Text -notmatch $Filter) { continue }

        $r = $word.BoundingRect

        Write-Output ('{0,-26} x={1,-6} y={2,-6} w={3,-6} h={4}' -f `
            $word.Text, [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)
    }
}
