@echo off
setlocal

set ACTION=%1
if "%ACTION%"=="" set ACTION=status

set REPO_ROOT=%~dp0..
set PS_SCRIPT=%~dp0queue_ops.ps1

if /I "%ACTION%"=="tailf" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action tail -TailLines 120 -Follow
    exit /b %ERRORLEVEL%
)

if /I "%ACTION%"=="tailrunf" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action tailrunf -TailLines 120
    exit /b %ERRORLEVEL%
)

if /I "%ACTION%"=="tail" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action tail -TailLines 120
    exit /b %ERRORLEVEL%
)

if /I "%ACTION%"=="tailrun" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action tailrun -TailLines 120
    exit /b %ERRORLEVEL%
)

if /I "%ACTION%"=="status" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action status
    exit /b %ERRORLEVEL%
)

if /I "%ACTION%"=="jobs" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action jobs
    exit /b %ERRORLEVEL%
)

if /I "%ACTION%"=="failures" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action failures -Recent 30
    exit /b %ERRORLEVEL%
)

if /I "%ACTION%"=="pids" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action pids
    exit /b %ERRORLEVEL%
)

if /I "%ACTION%"=="cleanup" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action cleanup
    exit /b %ERRORLEVEL%
)

echo Unknown action: %ACTION%
echo.
echo Usage:
echo   scripts\queue.cmd status
echo   scripts\queue.cmd jobs
echo   scripts\queue.cmd tail
echo   scripts\queue.cmd tailf
echo   scripts\queue.cmd tailrun
echo   scripts\queue.cmd tailrunf
echo   scripts\queue.cmd failures
echo   scripts\queue.cmd pids
echo   scripts\queue.cmd cleanup
exit /b 1
