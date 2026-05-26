param(
    [ValidateSet("Auto", "TaskOnStart", "TaskOnLogon", "StartupFolder")]
    [string]$Mode = "Auto",
    [switch]$Uninstall = $false,
    [switch]$ShowStatus = $false
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pythonExe = Join-Path $repoRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $pythonExe)) {
    $pythonExe = "C:\Users\markh\AppData\Local\Programs\Python\Python311\python.exe"
}

$recoveryScript = Join-Path $repoRoot "scripts\recover_after_crash.py"
if (-not (Test-Path $recoveryScript)) {
    throw "Recovery script not found: $recoveryScript"
}

$taskName = "ShrikeAILabRecovery"
$startupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$cmdPath = Join-Path $startupDir "ShrikeAILabRecovery.cmd"
$taskCmd = ('"{0}" "{1}"' -f $pythonExe, $recoveryScript)
$logsDir = Join-Path $repoRoot "training\logs\startup"
$startupRunLog = Join-Path $logsDir "startup-recover-last.log"
$startupExitLog = Join-Path $logsDir "startup-recover-last-exit.txt"

function Invoke-Schtasks {
    param([string[]]$Arguments)

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath "schtasks.exe" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        $stdout = if (Test-Path $stdoutFile) { Get-Content -Path $stdoutFile -Raw } else { "" }
        $stderr = if (Test-Path $stderrFile) { Get-Content -Path $stderrFile -Raw } else { "" }
    } finally {
        Remove-Item -Path $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $stderrFile -Force -ErrorAction SilentlyContinue
    }

    return @{
        ExitCode = $proc.ExitCode
        Output = (($stdout + [Environment]::NewLine + $stderr).Trim())
    }
}

function Remove-RecoveryArtifacts {
    $delete = Invoke-Schtasks -Arguments @("/Delete", "/TN", $taskName, "/F")
    if ($delete.ExitCode -ne 0 -and $delete.Output -notmatch "cannot find") {
        Write-Warning ($delete.Output.Trim())
    }
    if (Test-Path $cmdPath) {
        Remove-Item -Path $cmdPath -Force -ErrorAction SilentlyContinue
    }
}

function Install-StartupFolder {
    New-Item -ItemType Directory -Force -Path $startupDir | Out-Null
    New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

    $cmdContent = @"
@echo off
set PYTHONUNBUFFERED=1
"$pythonExe" "$recoveryScript" --skip-open-webui > "$startupRunLog" 2>&1
echo EXIT_CODE=%ERRORLEVEL% > "$startupExitLog"
"@

    Set-Content -Path $cmdPath -Value $cmdContent -Encoding ascii
    Write-Output "Startup folder launcher written: $cmdPath"
    return $true
}

function Install-TaskOnLogon {
    $taskResult = Invoke-Schtasks -Arguments @("/Create", "/TN", $taskName, "/SC", "ONLOGON", "/DELAY", "0000:30", "/TR", $taskCmd, "/RL", "LIMITED", "/F")
    if ($taskResult.ExitCode -eq 0) {
        Write-Output "Scheduled task registered (ONLOGON): $taskName"
        return $true
    }

    Write-Warning "Failed to register ONLOGON task"
    Write-Output $taskResult.Output
    return $false
}

function Install-TaskOnStart {
    # Requires elevated privileges. Runs pre-login, so recovery can happen without user unlock.
    $taskResult = Invoke-Schtasks -Arguments @("/Create", "/TN", $taskName, "/SC", "ONSTART", "/RU", "SYSTEM", "/TR", $taskCmd, "/RL", "HIGHEST", "/F")
    if ($taskResult.ExitCode -eq 0) {
        Write-Output "Scheduled task registered (ONSTART as SYSTEM): $taskName"
        return $true
    }

    Write-Warning "Failed to register ONSTART task (likely needs admin privileges)"
    Write-Output $taskResult.Output
    return $false
}

function Show-Status {
    Write-Output "=== Shrike AI Lab Recovery Startup Status ==="
    Write-Output "Python: $pythonExe"
    Write-Output "Script: $recoveryScript"
    Write-Output ""
    Write-Output "Scheduled task:"
    $query = Invoke-Schtasks -Arguments @("/Query", "/TN", $taskName, "/V", "/FO", "LIST")
    if ($query.ExitCode -eq 0) {
        Write-Output $query.Output
    } else {
        Write-Output "  (not installed)"
    }
    Write-Output ""
    Write-Output "Startup folder launcher: $(if (Test-Path $cmdPath) { "installed" } else { "not installed" })"
    if (Test-Path $cmdPath) {
        Write-Output "  Path: $cmdPath"
    }
}

if ($ShowStatus) {
    Show-Status
    exit 0
}

if ($Uninstall) {
    Remove-RecoveryArtifacts
    Write-Output "Removed scheduled task and startup launcher (if present)."
    exit 0
}

Remove-RecoveryArtifacts

switch ($Mode) {
    "TaskOnStart" {
        if (-not (Install-TaskOnStart)) { exit 1 }
    }
    "TaskOnLogon" {
        if (-not (Install-TaskOnLogon)) { exit 1 }
    }
    "StartupFolder" {
        if (-not (Install-StartupFolder)) { exit 1 }
    }
    "Auto" {
        if (Install-TaskOnStart) {
            break
        }
        if (Install-TaskOnLogon) {
            break
        }
        if (-not (Install-StartupFolder)) {
            exit 1
        }
    }
}

Show-Status
