param(
    [string]$PythonExe = "C:/Users/markh/AppData/Local/Programs/Python/Python311/python.exe",
    [string]$JobsFile = "training/queue/nightly_jobs.json",
    [double]$MaxHours = 18,
    [int]$RetryCount = 1,
    [double]$RetryLrMultiplier = 0.5
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$logsDir = Join-Path $repoRoot "training/logs"
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$launcherLog = Join-Path $logsDir "queue-launch-$timestamp.log"
$pidFile = Join-Path $logsDir "nightly-queue.pid"

$args = @(
    "scripts/train_queue.py",
    "--jobs-file", $JobsFile,
    "--continue-on-error",
    "--retry-count", "$RetryCount",
    "--retry-lr-multiplier", "$RetryLrMultiplier",
    "--repeat",
    "--stamp-version",
    "--max-hours", "$MaxHours"
)

$stdoutLog = $launcherLog
$stderrLog = Join-Path $logsDir "queue-launch-$timestamp.err.log"

$process = Start-Process `
    -FilePath $PythonExe `
    -ArgumentList $args `
    -WorkingDirectory $repoRoot `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -PassThru

Set-Content -Path $pidFile -Value $process.Id -Encoding ascii

Write-Output "Started nightly queue"
Write-Output "PID: $($process.Id)"
Write-Output "Launcher log: $launcherLog"
Write-Output "PID file: $pidFile"