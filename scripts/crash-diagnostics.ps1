# Shrike AI Lab - Crash Diagnostics & Recovery
# Runs before training to identify and mitigate crash risks

param(
    [switch]$Verbose = $false,
    [switch]$AutoClean = $false
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = "d:\LocalProjects\shrike-ai-lab\training\logs\diagnostics"
$diagLog = "$logDir\diagnostic-$timestamp.log"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Log {
    param([string]$msg)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $diagLog -Value $line
}

Log "=== CRASH DIAGNOSTIC REPORT ==="
Log "System: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)"
Log "Uptime: $(New-TimeSpan -Start (Get-CimInstance Win32_OperatingSystem).LastBootUpTime -End (Get-Date) | ForEach-Object { "$($_.Days)d $($_.Hours)h $($_.Minutes)m" })"

# ===== RAM ANALYSIS =====
Log "`n=== MEMORY ANALYSIS ==="
$os = Get-CimInstance Win32_OperatingSystem
$totalRam = [math]::Round($os.TotalPhysicalMemory / 1GB, 2)
$freeRam = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$usedRamPercent = [math]::Round(100 * (($totalRam * 1024 - $freeRam) / ($totalRam * 1024)), 1)

Log "Total RAM: $totalRam GB"
Log "Available RAM: $freeRam MB ($usedRamPercent% used)"

if ($usedRamPercent -gt 85) {
    Log "⚠️  ALERT: RAM usage >85% - CRASH RISK HIGH"
    Log "Top RAM consumers:"
    Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 10 ProcessName, @{N="RAM_MB"; E={[math]::Round($_.WorkingSet / 1MB, 2)}} | ForEach-Object {
        Log "  $($_.ProcessName): $($_.RAM_MB) MB"
    }
}

# ===== DISK ANALYSIS =====
Log "`n=== DISK ANALYSIS ==="
$drives = Get-Volume | Where-Object { $_.DriveType -eq "Fixed" }
$criticalDisks = @()
foreach ($drive in $drives) {
    $percentFree = if ($drive.Size -gt 0) { [math]::Round(100 * $drive.SizeRemaining / $drive.Size, 1) } else { 0 }
    $sizeGB = [math]::Round($drive.SizeRemaining / 1GB, 2)
    Log "$($drive.DriveLetter): $sizeGB GB free ($percentFree% free)"
    
    if ($percentFree -lt 10) {
        $criticalDisks += $drive.DriveLetter
        Log "  ⚠️  CRITICAL: <10% free - DELETE OLD LOGS/MODELS"
    } elseif ($percentFree -lt 20) {
        Log "  ⚠️  LOW: <20% free"
    }
}

# ===== GPU ANALYSIS =====
Log "`n=== GPU ANALYSIS ==="
$gpu = Get-CimInstance Win32_VideoController
Log "GPU: $($gpu.Name)"
Log "VRAM: $([math]::Round($gpu.AdapterRAM / 1GB, 2)) GB"

if ($gpu.AdapterRAM -lt 4GB) {
    Log "⚠️  ALERT: <4GB VRAM - 7B models may cause OOM"
}

# ===== PROCESS CLEANUP =====
Log "`n=== PROCESS ANALYSIS ==="

# Find stuck/duplicate LiteLLM or training processes
$litellmProcs = Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'litellm|proxy_cli' }
$trainingProcs = Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'train_queue|train\.py' }

if ($litellmProcs.Count -gt 1) {
    Log "⚠️  ALERT: $($litellmProcs.Count) LiteLLM processes found (should be 1)"
    Log "Stuck LiteLLM processes (will be killed on --AutoClean):"
    $litellmProcs | ForEach-Object { Log "  PID $($_.Id): $($_.CommandLine.Substring(0, [math]::Min(80, $_.CommandLine.Length)))" }
}

if ($trainingProcs.Count -gt 1) {
    Log "⚠️  ALERT: $($trainingProcs.Count) training processes found (should be 1)"
}

# Check for zombie/stuck Code processes (common culprit)
$codeProcs = Get-Process -Name Code -ErrorAction SilentlyContinue | Measure-Object -Property WorkingSet -Sum
if ($codeProcs.Count -gt 2) {
    $codeRam = [math]::Round($codeProcs.Sum / 1GB, 2)
    Log "⚠️  VS Code using $codeRam GB across $($codeProcs.Count) processes - consider closing"
}

# ===== EVENT LOG ANALYSIS (last 24h) =====
Log "`n=== SYSTEM ERRORS (last 24h) ==="
try {
    $events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue | Select-Object -First 10
    if ($events.Count -gt 0) {
        Log "Found critical errors:"
        $events | ForEach-Object {
            Log "  [$($_.TimeCreated.ToString('HH:mm'))] ID $($_.Id): $($_.Message.Substring(0, [math]::Min(100, $_.Message.Length)))"
        }
    } else {
        Log "No critical errors found"
    }
} catch {
    Log "Could not read Event Logs (permission issue)"
}

# ===== RECOMMENDATIONS =====
Log "`n=== RECOMMENDATIONS ==="
$recommendations = @()

if ($usedRamPercent -gt 85) {
    $recommendations += "1. Close unnecessary applications (VS Code, Snagit, etc.)"
    $recommendations += "2. Disable Windows Search: 'powercfg /h off' and disable SearchIndexer"
    $recommendations += "3. Disable OneDrive sync during training"
    $recommendations += "4. Limit Ollama to 2GB max RAM (OLLAMA_MEMORY_LIMIT=2000)"
}

if ($criticalDisks.Count -gt 0) {
    $recommendations += "5. Clean up disk on drive(s): $($criticalDisks -join ', ')"
    $recommendations += "   - Delete old run logs: 'Get-ChildItem training/logs/runs -Filter *.log | Remove-Item'"
    $recommendations += "   - Run: 'cleanmgr' (Disk Cleanup utility)"
}

if ($gpu.AdapterRAM -lt 4GB) {
    $recommendations += "6. Switch to smaller models (Phi-3 instead of CodeLlama 7B)"
}

if ($recommendations.Count -gt 0) {
    $recommendations | ForEach-Object { Log "   $_" }
}

Log "`n=== DIAGNOSTIC COMPLETE ==="
Log "Report saved to: $diagLog"
Log "Next run: training queue will monitor memory during execution"

# Auto-cleanup if requested
if ($AutoClean) {
    Log "`n=== AUTO-CLEANUP MODE ==="
    
    # Kill duplicate LiteLLM processes
    if ($litellmProcs.Count -gt 1) {
        Log "Killing $($litellmProcs.Count - 1) duplicate LiteLLM processes..."
        $litellmProcs | Select-Object -Skip 1 | ForEach-Object {
            try {
                Stop-Process -Id $_.Id -Force
                Log "  Killed PID $($_.Id)"
            } catch {
                Log "  Failed to kill PID $($_.Id): $_"
            }
        }
    }
    
    # Kill training processes if stuck
    if ($trainingProcs.Count -gt 0) {
        Log "Stopping training processes for cleanup..."
        $trainingProcs | ForEach-Object {
            try {
                Stop-Process -Id $_.Id -Force
                Log "  Killed training PID $($_.Id)"
            } catch {}
        }
    }
}

exit 0
