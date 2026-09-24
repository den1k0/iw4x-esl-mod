@echo off
REM ===========================================================================
REM  ESL-MOD - build wrapper (double-click friendly)
REM ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
if errorlevel 1 (
    echo.
    echo Build FAILED.
    pause
    exit /b 1
)
echo.
pause
endlocal
