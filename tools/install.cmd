@echo off
REM ===========================================================================
REM  ESL-MOD - install wrapper (double-click friendly)
REM
REM  Override the IW4x location by passing it as the first argument:
REM      install.cmd "C:\Games\iw4x"
REM ===========================================================================
setlocal

set "IW4X=%~1"
if "%IW4X%"=="" set "IW4X=D:\Games\iw4x"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Iw4xPath "%IW4X%"
if errorlevel 1 (
    echo.
    echo Install FAILED.
    pause
    exit /b 1
)
echo.
pause
endlocal
