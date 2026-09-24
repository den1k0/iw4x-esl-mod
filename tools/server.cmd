@echo off
REM ===========================================================================
REM  ESL-MOD - dedicated server control
REM
REM      tools\server.cmd start
REM      tools\server.cmd stop
REM      tools\server.cmd restart
REM      tools\server.cmd status
REM
REM  Extra arguments are passed straight to tools\server.ps1, e.g.
REM      tools\server.cmd start -Map mp_terminal
REM      tools\server.cmd start -Port 28961
REM
REM  For double-click use, server-start.cmd and server-stop.cmd are the same
REM  thing with the -Action already filled in.
REM ===========================================================================
setlocal
if "%~1"=="" (
    echo Usage: server.cmd ^<start^|stop^|restart^|status^> [extra options]
    echo   e.g.  server.cmd start -Map mp_terminal
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Action %*
if errorlevel 1 (
    echo.
    echo Command FAILED - see the messages above.
    pause
    exit /b 1
)
endlocal
