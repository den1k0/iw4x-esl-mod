# =============================================================================
#  Self-test for tools\dev\lint_gsc_locals.ps1
#
#  A lint that reports nothing is indistinguishable from a lint that is broken,
#  so this reintroduces the exact bug it exists for - the side-arm response
#  reading attachOk, a local of esl_pushAvailability() - in a throwaway copy of
#  the source and asserts that it is reported.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev\lint_selftest.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$root   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$src    = Join-Path $root 'src\maps\mp\gametypes\_esl.gsc'
$lint   = Join-Path $PSScriptRoot 'lint_gsc_locals.ps1'
$tmp    = Join-Path $root 'build\linttest.gsc'

$good = Get-Content -LiteralPath $src -Raw

# rename the assignment, not the read: the injected file must *read* a name the
# function never assigns, which is what the compiler rejects.  (Renaming the
# read instead would work too, but then the report names a name that does not
# appear anywhere else, which is harder to read in the output.)
$bug = $good -replace 'attachOk = esl_attachmentAllowed',
                      'attachZZ = esl_attachmentAllowed'

# the mutator is a no-op only if the line it targets changed - fail loudly
if ($bug -eq $good) {
    throw 'self-test could not inject the bug: the target line was not found'
}

Set-Content -LiteralPath $tmp -Value $bug -Encoding ASCII -NoNewline

$output = & powershell -NoProfile -ExecutionPolicy Bypass -File $lint -File $tmp 2>&1
$code   = $LASTEXITCODE

Remove-Item -LiteralPath $tmp -Force

if ($code -eq 0) {
    Write-Output 'selftest: FAILED - the injected unassigned local was not reported'
    $output | ForEach-Object { Write-Output ('    ' + $_) }
    exit 1
}

$reported = @($output | Where-Object { $_ -match 'attachOk' })

if ($reported.Count -eq 0) {
    Write-Output 'selftest: FAILED - the lint failed, but not on attachOk'
    $output | ForEach-Object { Write-Output ('    ' + $_) }
    exit 1
}

Write-Output 'selftest: ok - the injected unassigned local is reported'

# and the real file must stay clean
& powershell -NoProfile -ExecutionPolicy Bypass -File $lint

exit $LASTEXITCODE
