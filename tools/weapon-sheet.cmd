@echo off
REM ===========================================================================
REM  ESL-MOD - write the weapon stat sheet (docs\weapon-stats.html)
REM
REM      weapon-sheet.cmd
REM      weapon-sheet.cmd -Health 100
REM
REM  Read out of build\payload\weapons\mp, the tweaked payload the mod packs, so
REM  run tools\build.cmd (or tools\install.cmd) first - a build regenerates that
REM  folder from the rebalance plus src\weapons\extra and applies
REM  src\weapons\weapon-tweaks.txt to it.
REM
REM  The page prints the payload's newest file time, so a stale sheet is visible.
REM ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0weapon-sheet.ps1" %*
endlocal
