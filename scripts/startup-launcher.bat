@echo off
REM Shrike AI Lab - Windows Startup Launcher
REM Place in: C:\Users\markh\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
REM This batch file runs on Windows logon and auto-recovers the LLM training stack

setlocal enabledelayedexpansion

cd /d "d:\LocalProjects\shrike-ai-lab" || (
    echo ERROR: Cannot change to project directory
    pause
    exit /b 1
)

REM Set Python environment
set PYTHONUNBUFFERED=1
set LITELLM_MASTER_KEY=sk-shrike-local

REM Get timestamp for log
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)
set TIMESTAMP=%mydate%-%mytime%

REM Log file
set LOGFILE=training\logs\startup\startup-launcher-%TIMESTAMP%.log

echo. > "%LOGFILE%"
echo ================================== >> "%LOGFILE%"
echo Shrike AI Lab - Startup Launcher >> "%LOGFILE%"
echo Time: %date% %time% >> "%LOGFILE%"
echo ================================== >> "%LOGFILE%"

REM Run PowerShell recovery script
echo. >> "%LOGFILE%"
echo [*] Running startup recovery script... >> "%LOGFILE%"
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\startup-recovery.ps1" >> "%LOGFILE%" 2>&1

if %ERRORLEVEL% neq 0 (
    echo [!] Startup failed with exit code %ERRORLEVEL% >> "%LOGFILE%"
) else (
    echo [+] Startup completed successfully >> "%LOGFILE%"
)

echo. >> "%LOGFILE%"
echo Log saved to: %LOGFILE% >> "%LOGFILE%"

REM Exit silently (no console window)
exit /b %ERRORLEVEL%
