@echo off
REM ===========================================================================
REM  ESL-MOD - package the mod for players (double-click friendly)
REM
REM  Writes build\ESL-MOD.zip containing mods\ESL-MOD\... so a player can extract
REM  it into their IW4x folder and join the server.  This is the reliable route:
REM  IW4x's own mod download needs an HTTP file server, see docs\SERVER.md.
REM
REM  Extra arguments go to tools\pack-mod.ps1, e.g.
REM      pack-mod.cmd -OutFile "D:\share\ESL-MOD.zip"
REM ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack-mod.ps1" %*
if errorlevel 1 (
    echo.
    echo Packaging FAILED - see the messages above.
    pause
    exit /b 1
)
echo.
pause
endlocal
