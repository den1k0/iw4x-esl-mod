@echo off
REM ===========================================================================
REM  ESL-MOD - send a command to the running server (rcon)
REM
REM      rcon.cmd sv_hostname
REM      rcon.cmd fast_restart        end the match, restart the same map
REM      rcon.cmd map_rotate          end the match, load the next map
REM      rcon.cmd map mp_terminal     end the match, jump to a map
REM      rcon.cmd kick <player>
REM
REM  The rcon password is taken from mods\ESL-MOD\configs\ESL-MOD_server.cfg.
REM  Options (server, port, password) go to tools\rcon.ps1, e.g.
REM      rcon.cmd -Server 192.168.31.148 map_rotate
REM ===========================================================================
setlocal
if "%~1"=="" (
    echo Usage: rcon.cmd ^<command^> [args]
    echo   e.g.  rcon.cmd map_rotate
    echo         rcon.cmd sv_hostname
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rcon.ps1" -Command "%*"
endlocal
