@echo off
REM ===========================================================================
REM  ESL-MOD - stop the dedicated server (double-click friendly)
REM
REM  Only the dedicated server process is stopped: your game client is also
REM  iw4x.exe, but it is not started with -dedicated, so it is left alone.
REM ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Action stop
if errorlevel 1 (
    echo.
    echo Something went wrong - see the messages above.
    pause
    exit /b 1
)
echo.
pause
endlocal
