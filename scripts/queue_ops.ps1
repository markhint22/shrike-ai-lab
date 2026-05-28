param(
    [ValidateSet("status", "jobs", "tail", "tailrun", "tailrunf", "failures", "pids", "cleanup", "help")]
    [string]$Action = "status",
    [int]$TailLines = 80,
    [switch]$Follow,
    [int]$Recent = 20
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$queueDir = Join-Path $repoRoot "runtime\queue"
$jobsFile = Join-Path $repoRoot "training\queue\nightly_jobs.json"
$pidFile = Join-Path $queueDir "training-queue.pid"
$lockFiles = @(
    (Join-Path $queueDir "training-queue.lock")
)

function Get-LatestQueueLog {
    if (-not (Test-Path $queueDir)) {
        return $null
    }
    return Get-ChildItem -Path $queueDir -File -Filter "queue-launch-*.log" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-PidState([string]$filePath) {
    if (-not (Test-Path $filePath)) {
        return [pscustomobject]@{
            File = $filePath
            Exists = $false
            Pid = $null
            Alive = $false
            ProcessName = $null
            StartTime = $null
        }
    }

    $pidValue = (Get-Content $filePath -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $pidValue) {
        return [pscustomobject]@{
            File = $filePath
            Exists = $true
            Pid = $null
            Alive = $false
            ProcessName = $null
            StartTime = $null
        }
    }

    $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        File = $filePath
        Exists = $true
        Pid = [int]$pidValue
        Alive = [bool]$proc
        ProcessName = if ($proc) { $proc.ProcessName } else { $null }
        StartTime = if ($proc) { $proc.StartTime } else { $null }
    }
}

function Show-Status {
    Write-Host "=== Queue Status ==="
    Write-Host "Time: $(Get-Date -Format o)"
    Write-Host ""

    $pidState = Get-PidState $pidFile
    $lockStates = @($lockFiles | ForEach-Object { Get-PidState $_ })

    Write-Host "[PID and lock files]"
    @($pidState) + $lockStates |
        Select-Object @{Name = "File"; Expression = { Split-Path $_.File -Leaf } }, Exists, Pid, Alive, ProcessName, StartTime |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "[Running Python queue/train processes]"
    $running = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match "python|py" -and
            $_.CommandLine -match "train_queue\.py|scripts\\train\.py|start_nightly_queue\.py"
        } |
        Select-Object ProcessId, Name, CommandLine

    if (-not $running) {
        Write-Host "none"
    }
    else {
        $running | Format-Table -Wrap
    }

    Write-Host ""
    Write-Host "[Latest queue log]"
    $latest = Get-LatestQueueLog
    if (-not $latest) {
        Write-Host "No queue-launch log found in $queueDir"
        return
    }

    Write-Host "File: $($latest.FullName)"
    $tail = Get-Content $latest.FullName -Tail 300

    $lastCycle = $tail | Select-String "^=== Queue Cycle" | Select-Object -Last 1
    $lastJob = $tail | Select-String "^\[[0-9]+/[0-9]+\]" | Select-Object -Last 1
    $lastStop = $tail | Select-String "Queue completed|Reached max runtime window|Stopping queue" | Select-Object -Last 1

    if ($lastCycle) { Write-Host "Cycle: $($lastCycle.Line)" }
    if ($lastJob) { Write-Host "Latest job line: $($lastJob.Line)" }
    if ($lastStop) { Write-Host "Latest stop/completion line: $($lastStop.Line)" }
}

function Show-Jobs {
    if (-not (Test-Path $jobsFile)) {
        Write-Error "Jobs file not found: $jobsFile"
    }

    $payload = Get-Content $jobsFile -Raw | ConvertFrom-Json
    $jobs = @($payload.jobs)

    Write-Host "=== Nightly Queue Jobs ==="
    Write-Host "File: $jobsFile"
    Write-Host "Total jobs: $($jobs.Count)"
    Write-Host ""

    $i = 0
    $jobs | ForEach-Object {
        $i++
        [pscustomobject]@{
            Index = $i
            Kind = if ($_.kind) { $_.kind } else { 'llm_train' }
            Project = $_.project
            Task = $_.task
            Team = $_.team
            Version = $_.version
            CandidateModel = $_.ab_gate_candidate_model
        }
    } | Format-Table -AutoSize
}

function Show-Tail {
    $latest = Get-LatestQueueLog
    if (-not $latest) {
        Write-Error "No queue-launch log found in $queueDir"
    }

    Write-Host "=== Queue Log Tail ==="
    Write-Host "File: $($latest.FullName)"
    Write-Host ""

    if ($Follow) {
        Get-Content $latest.FullName -Tail $TailLines -Wait
    }
    else {
        Get-Content $latest.FullName -Tail $TailLines
    }
}

function Show-RunTail([bool]$followRun) {
    $runsDir = Join-Path $repoRoot "training\logs\runs"
    if (-not (Test-Path $runsDir)) {
        Write-Error "Runs log directory not found: $runsDir"
    }

    $latestRun = Get-ChildItem -Path $runsDir -File -Filter "*.log" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestRun) {
        Write-Error "No run logs found in $runsDir"
    }

    Write-Host "=== Latest Run Log Tail ==="
    Write-Host "File: $($latestRun.FullName)"
    Write-Host ""

    if (-not $followRun) {
        Get-Content $latestRun.FullName -Tail $TailLines
        return
    }

    Write-Host "Auto-follow mode: will switch to the next run log when a new job starts."
    Write-Host "Press Ctrl+C to stop."
    Write-Host ""

    $currentFile = $null
    $lineCursor = 0

    while ($true) {
        $latestRun = Get-ChildItem -Path $runsDir -File -Filter "*.log" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if (-not $latestRun) {
            Start-Sleep -Milliseconds 800
            continue
        }

        if ($latestRun.FullName -ne $currentFile) {
            $currentFile = $latestRun.FullName
            $allLines = @(Get-Content $currentFile -ErrorAction SilentlyContinue)
            $lineCursor = [Math]::Max(0, $allLines.Count - $TailLines)

            Write-Host ""
            Write-Host (">>> Switched to: " + $currentFile)
            Write-Host ""

            if ($allLines.Count -gt 0 -and $lineCursor -lt $allLines.Count) {
                $allLines[$lineCursor..($allLines.Count - 1)] | ForEach-Object { Write-Output $_ }
                $lineCursor = $allLines.Count
            }
        }

        $allLines = @(Get-Content $currentFile -ErrorAction SilentlyContinue)
        if ($allLines.Count -gt $lineCursor) {
            $allLines[$lineCursor..($allLines.Count - 1)] | ForEach-Object { Write-Output $_ }
            $lineCursor = $allLines.Count
        }

        Start-Sleep -Milliseconds 800
    }
}

function Show-Failures {
    $latest = Get-LatestQueueLog
    if (-not $latest) {
        Write-Error "No queue-launch log found in $queueDir"
    }

    $patterns = @(
        "Job failed",
        "ab-gate failed",
        "Stopping queue due to",
        "Queue completed with failures"
    )

    Write-Host "=== Recent Failures ==="
    Write-Host "File: $($latest.FullName)"
    Write-Host ""

    $matches = Get-Content $latest.FullName |
        Select-String -Pattern ($patterns -join "|") |
        Select-Object -Last $Recent

    if (-not $matches) {
        Write-Host "No matching failure lines found in latest queue log."
    }
    else {
        $matches | ForEach-Object { $_.Line }
    }
}

function Show-Pids {
    Write-Host "=== Queue PIDs ==="
    @($pidFile) + $lockFiles |
        ForEach-Object { Get-PidState $_ } |
        Select-Object @{Name = "File"; Expression = { Split-Path $_.File -Leaf } }, Pid, Alive, ProcessName, StartTime |
        Format-Table -AutoSize
}

function Cleanup-Stale {
    Write-Host "=== Cleanup Stale Queue Artifacts ==="
    $targets = @($pidFile) + $lockFiles
    $removed = New-Object System.Collections.Generic.List[string]
    $kept = New-Object System.Collections.Generic.List[string]

    foreach ($target in $targets) {
        if (-not (Test-Path $target)) {
            continue
        }

        $state = Get-PidState $target
        if (-not $state.Alive) {
            Remove-Item $target -Force
            [void]$removed.Add((Split-Path $target -Leaf))
        }
        else {
            [void]$kept.Add((Split-Path $target -Leaf))
        }
    }

    if ($removed.Count -eq 0) {
        Write-Host "No stale PID/lock files removed."
    }
    else {
        Write-Host "Removed: $($removed -join ', ')"
    }

    if ($kept.Count -gt 0) {
        Write-Host "Kept active: $($kept -join ', ')"
    }
}

function Show-HelpText {
    Write-Host "queue_ops.ps1 actions:"
    Write-Host "  status    - summary of PID/locks, running process, latest cycle/job lines"
    Write-Host "  jobs      - print all jobs from training/queue/nightly_jobs.json"
    Write-Host "  tail      - tail latest queue-launch log (use -Follow to stream)"
    Write-Host "  tailrun   - tail latest per-job run log (usually most live output)"
    Write-Host "  tailrunf  - follow latest per-job run log live"
    Write-Host "  failures  - show recent failure-related lines from latest log"
    Write-Host "  pids      - show PID and lock file process states"
    Write-Host "  cleanup   - remove stale queue PID/lock files only"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/queue_ops.ps1 -Action status"
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/queue_ops.ps1 -Action tail -TailLines 120 -Follow"
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/queue_ops.ps1 -Action tailrunf -TailLines 120"
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/queue_ops.ps1 -Action failures -Recent 30"
}

switch ($Action) {
    "status" { Show-Status }
    "jobs" { Show-Jobs }
    "tail" { Show-Tail }
    "tailrun" { Show-RunTail $false }
    "tailrunf" { Show-RunTail $true }
    "failures" { Show-Failures }
    "pids" { Show-Pids }
    "cleanup" { Cleanup-Stale }
    default { Show-HelpText }
}
