@echo off
REM ===========================================================================
REM  ESL-MOD - start the dedicated server (double-click friendly)
REM
REM  Extra arguments are passed straight to tools\server.ps1, e.g.
REM      server-start.cmd -Map mp_terminal
REM      server-start.cmd -Port 28961
REM ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Action start %*
if errorlevel 1 (
    echo.
    echo The server did NOT start - see the messages above.
    pause
    exit /b 1
)
echo.
pause
endlocal
