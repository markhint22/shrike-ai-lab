# Shrike AI Lab - Auto-Recovery & Startup Script
# Designed to run on Windows logon
# This script safely recovers Ollama + LiteLLM + training queue after crashes

param(
    [switch]$SkipDiagnostics = $false,
    [switch]$SkipTraining = $false,
    [int]$MemoryThresholdPercent = 80  # Abort if RAM usage exceeds this %
)

$projectRoot = "d:\LocalProjects\shrike-ai-lab"
$startupLogDir = "$projectRoot\training\logs\startup"
$servicesLogDir = "$projectRoot\training\logs\services"
$queueLogDir = "$projectRoot\training\logs\queue"
$recoveryLog = "$startupLogDir\startup-recovery-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

New-Item -ItemType Directory -Path $startupLogDir -Force | Out-Null
New-Item -ItemType Directory -Path $servicesLogDir -Force | Out-Null
New-Item -ItemType Directory -Path $queueLogDir -Force | Out-Null

function Log {
    param([string]$msg, [string]$level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] [$level] $msg"
    Write-Host $line
    Add-Content -Path $recoveryLog -Value $line
}

function Cleanup-StuckProcesses {
    Log "Cleaning up stuck processes..." "INFO"
    
    # Kill all LiteLLM processes (we'll restart fresh)
    $litellmProcs = Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'litellm|proxy_cli' }
    foreach ($proc in $litellmProcs) {
        Log "Stopping LiteLLM PID $($proc.Id)..."
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Log "Killed LiteLLM PID $($proc.Id)" "CLEAN"
        } catch {
            Log "Failed to kill LiteLLM PID $($proc.Id): $_" "WARN"
        }
    }
    
    # Kill all training processes
    $trainProcs = Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'train_queue|train\.py' }
    foreach ($proc in $trainProcs) {
        Log "Stopping training PID $($proc.Id)..."
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Log "Killed training PID $($proc.Id)" "CLEAN"
        } catch {
            Log "Failed to kill training PID $($proc.Id): $_" "WARN"
        }
    }
    
    # Give system time to release ports
    Start-Sleep -Seconds 2
    
    # Wait for port 4000 to be free
    $maxWait = 10
    $waited = 0
    while ((Get-NetTCPConnection -LocalPort 4000 -State Listen -ErrorAction SilentlyContinue) -and $waited -lt $maxWait) {
        Log "Waiting for port 4000 to be free... ($waited/$maxWait)"
        Start-Sleep -Seconds 1
        $waited++
    }
}

function Start-LiteLLM {
    param([string]$ConfigPath = "configs/litellm_config.yaml")
    
    Log "Starting LiteLLM proxy on port 4000..." "INFO"
    
    # Ensure config exists
    $configFull = Join-Path $projectRoot $ConfigPath
    if (-not (Test-Path $configFull)) {
        Log "Config not found at $configFull" "ERROR"
        return $false
    }
    
    # Start LiteLLM in background
    $env:LITELLM_MASTER_KEY = "sk-shrike-local"
    
    $logFile = "$servicesLogDir\litellm-startup.log"
    $pythonPath = "C:\Users\markh\AppData\Local\Programs\Python\Python311\python.exe"
    
    try {
        $process = Start-Process `
            -FilePath $pythonPath `
            -ArgumentList "-m", "litellm.proxy.proxy_cli", "--config", $ConfigPath, "--host", "0.0.0.0", "--port", "4000" `
            -WorkingDirectory $projectRoot `
            -NoNewWindow `
            -PassThru `
            -ErrorAction Stop
        
        Log "Started LiteLLM PID $($process.Id)" "SUCCESS"
        
        # Wait for proxy to be ready
        $maxRetries = 30
        $retry = 0
        while ($retry -lt $maxRetries) {
            try {
                $response = Invoke-WebRequest `
                    -Uri "http://localhost:4000/health" `
                    -Headers @{ Authorization = "Bearer sk-shrike-local" } `
                    -UseBasicParsing `
                    -TimeoutSec 5 `
                    -ErrorAction Stop
                
                if ($response.StatusCode -eq 200) {
                    Log "LiteLLM is ready (HTTP 200)" "SUCCESS"
                    return $true
                }
            } catch {}
            
            Start-Sleep -Seconds 1
            $retry++
        }
        
        Log "LiteLLM did not respond after 30 seconds" "ERROR"
        return $false
        
    } catch {
        Log "Failed to start LiteLLM: $_" "ERROR"
        return $false
    }
}

function Start-TrainingQueue {
    param(
        [string]$JobsFile = "training/queue/nightly_jobs.json",
        [int]$MaxHours = 18
    )
    
    Log "Starting training queue..." "INFO"
    
    $jobsFull = Join-Path $projectRoot $JobsFile
    if (-not (Test-Path $jobsFull)) {
        Log "Jobs file not found at $jobsFull" "ERROR"
        return $false
    }
    
    $pythonPath = "C:\Users\markh\AppData\Local\Programs\Python\Python311\python.exe"
    $queueScript = "scripts\train_queue.py"
    
    try {
        $process = Start-Process `
            -FilePath $pythonPath `
            -ArgumentList $queueScript, "--jobs-file", $JobsFile, "--continue-on-error", "--repeat", "--stamp-version", "--max-hours", "$MaxHours" `
            -WorkingDirectory $projectRoot `
            -NoNewWindow `
            -PassThru `
            -ErrorAction Stop
        
        Log "Started training queue PID $($process.Id)" "SUCCESS"
        
        # Save PID for monitoring
        Set-Content -Path "$queueLogDir\nightly-queue.pid" -Value $process.Id -Encoding ASCII
        
        return $true
        
    } catch {
        Log "Failed to start training queue: $_" "ERROR"
        return $false
    }
}

function Check-SystemHealth {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRam = [math]::Round($os.TotalPhysicalMemory / 1GB, 2)
    $freeRam = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedPercent = [math]::Round(100 * (($totalRam * 1024 - $freeRam) / ($totalRam * 1024)), 1)
    
    Log "System Health: $usedPercent% RAM used (Free: $freeRam MB / $totalRam GB)"
    
    if ($usedPercent -gt $MemoryThresholdPercent) {
        Log "ABORT: RAM usage $usedPercent% exceeds threshold $MemoryThresholdPercent%" "ERROR"
        Log "Close applications and try again" "ERROR"
        return $false
    }
    
    return $true
}

# ===== MAIN FLOW =====
Log "========================================" "INFO"
Log "Shrike AI Lab - Startup Recovery Script" "INFO"
Log "========================================" "INFO"

Set-Location $projectRoot

# Run diagnostics first
if (-not $SkipDiagnostics) {
    Log "Running crash diagnostics..." "INFO"
    & "$projectRoot\scripts\crash-diagnostics.ps1" -AutoClean
}

# Check system health
if (-not (Check-SystemHealth)) {
    Log "System health check failed - aborting startup" "ERROR"
    exit 1
}

# Clean stuck processes
Cleanup-StuckProcesses

# Start LiteLLM
if (-not (Start-LiteLLM)) {
    Log "Failed to start LiteLLM - aborting" "ERROR"
    exit 1
}

# Start training queue (if not skipped)
if (-not $SkipTraining) {
    if (Start-TrainingQueue) {
        Log "All services started successfully" "SUCCESS"
    } else {
        Log "Training queue failed to start (but LiteLLM is running)" "WARN"
    }
}

Log "Startup complete. Check training logs for progress." "INFO"
Log "Log file: $recoveryLog" "INFO"

exit 0
