@echo off
REM ===========================================================================
REM  ESL-MOD - router port forwarding helper
REM
REM      forward-port.cmd             show the current mapping
REM      forward-port.cmd -Add        create the UDP 28960 forward on the router
REM      forward-port.cmd -Remove     remove it
REM
REM  Uses UPnP on the router. If the router has UPnP switched off, the script
REM  says so and docs\SERVER.md explains how to forward the port by hand.
REM ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0forward-port.ps1" %*
if errorlevel 1 (
    echo.
    pause
    exit /b 1
)
echo.
pause
endlocal
