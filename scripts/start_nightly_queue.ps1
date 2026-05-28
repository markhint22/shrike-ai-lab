param(
    [string]$PythonExe = "C:/Users/markh/AppData/Local/Programs/Python/Python311/python.exe",
    [string]$JobsFile = "training/queue/nightly_jobs.json",
    [double]$MaxHours = 18,
    [int]$RetryCount = 1,
    [double]$RetryLrMultiplier = 0.5
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$args = @(
    "scripts/start_nightly_queue.py",
    "--python", $PythonExe,
    "--jobs-file", $JobsFile,
    "--max-hours", "$MaxHours",
    "--retry-count", "$RetryCount",
    "--retry-lr-multiplier", "$RetryLrMultiplier"
)

& $PythonExe @args
exit $LASTEXITCODE