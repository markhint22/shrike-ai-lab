# Shrike AI Lab - Training Queue with Memory Monitoring
# Wrapper around train_queue.py that monitors RAM and gracefully aborts if threshold exceeded

param(
    [string]$JobsFile = "training/queue/nightly_jobs.json",
    [int]$MaxHours = 18,
    [int]$MemoryAbortPercent = 90,    # Abort if RAM exceeds this %
    [int]$MemoryWarningPercent = 80   # Warn if RAM exceeds this %
)

$projectRoot = "d:\LocalProjects\shrike-ai-lab"
$logDir = "$projectRoot\training\logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$monitorLog = "$logDir\training-monitor-$timestamp.log"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Log {
    param([string]$msg, [string]$level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$level] $msg"
    Write-Host $line
    Add-Content -Path $monitorLog -Value $line
}

function Get-MemoryPercent {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRam = $os.TotalPhysicalMemory
    $freeRam = $os.FreePhysicalMemory
    return [math]::Round(100 * (($totalRam - $freeRam) / $totalRam), 1)
}

function Get-TopRamConsumers {
    Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 ProcessName, @{N="RAM_MB"; E={[math]::Round($_.WorkingSet / 1MB, 2)}}
}

Log "========================================" "INFO"
Log "Training Queue with Memory Monitoring" "INFO"
Log "========================================" "INFO"
Log "Jobs file: $JobsFile" "INFO"
Log "Max runtime: $MaxHours hours" "INFO"
Log "Memory warning threshold: $MemoryWarningPercent%" "INFO"
Log "Memory abort threshold: $MemoryAbortPercent%" "INFO"
Log "Monitor log: $monitorLog" "INFO"

Set-Location $projectRoot

# Start training queue in background
Log "Starting training queue..." "INFO"
$pythonPath = "C:\Users\markh\AppData\Local\Programs\Python\Python311\python.exe"

$process = Start-Process `
    -FilePath $pythonPath `
    -ArgumentList "scripts/train_queue.py", "--jobs-file", $JobsFile, "--continue-on-error", "--repeat", "--stamp-version", "--max-hours", "$MaxHours" `
    -WorkingDirectory $projectRoot `
    -PassThru `
    -ErrorAction Stop

$trainPid = $process.Id
Log "Training queue started (PID $trainPid)" "SUCCESS"

# Save PID
Set-Content -Path "$logDir\training-monitor.pid" -Value $trainPid -Encoding ASCII

# Monitor loop
$startTime = Get-Date
$endTime = $startTime.AddHours($MaxHours)
$checkInterval = 30  # Check every 30 seconds
$lastWarning = $null
$memoryHistory = @()

while ($true) {
    # Check if training process is still alive
    $trainProcess = Get-Process -Id $trainPid -ErrorAction SilentlyContinue
    if (-not $trainProcess) {
        Log "Training queue process ended (PID $trainPid)" "INFO"
        break
    }
    
    # Check memory usage
    $memPercent = Get-MemoryPercent
    $memoryHistory += $memPercent
    
    # Keep only last 10 readings for average
    if ($memoryHistory.Count -gt 10) {
        $memoryHistory = $memoryHistory[-10..-1]
    }
    $avgMemPercent = [math]::Round(($memoryHistory | Measure-Object -Average).Average, 1)
    
    # Log current status
    if ($memPercent -gt $MemoryAbortPercent) {
        Log "CRITICAL: RAM $memPercent% > abort threshold $MemoryAbortPercent%" "ERROR"
        Log "Top RAM consumers:" "ERROR"
        Get-TopRamConsumers | ForEach-Object {
            Log "  $($_.ProcessName): $($_.RAM_MB) MB" "ERROR"
        }
        Log "Terminating training queue to prevent crash..." "ERROR"
        
        try {
            Stop-Process -Id $trainPid -Force
            Log "Training queue terminated (PID $trainPid)" "ERROR"
        } catch {
            Log "Failed to terminate process: $_" "ERROR"
        }
        
        exit 1
    }
    
    if ($memPercent -gt $MemoryWarningPercent) {
        if (-not $lastWarning -or ((Get-Date) - $lastWarning).TotalMinutes -gt 5) {
            Log "WARNING: RAM $memPercent% > warning threshold $MemoryWarningPercent% (avg: $avgMemPercent%)" "WARN"
            Log "Top RAM consumers:" "WARN"
            Get-TopRamConsumers | ForEach-Object {
                Log "  $($_.ProcessName): $($_.RAM_MB) MB" "WARN"
            }
            $lastWarning = Get-Date
        }
    } else {
        Log "Memory: $memPercent% (avg: $avgMemPercent%)" "DEBUG"
    }
    
    # Check if max runtime exceeded
    if ((Get-Date) -gt $endTime) {
        Log "Max runtime ($MaxHours hours) reached, stopping queue..." "INFO"
        try {
            Stop-Process -Id $trainPid -Force
        } catch {}
        break
    }
    
    # Wait before next check
    Start-Sleep -Seconds $checkInterval
}

Log "Monitoring complete. Check training logs for details." "INFO"
exit 0
