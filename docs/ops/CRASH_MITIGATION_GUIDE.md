# Shrike AI Lab - Crash Mitigation & Troubleshooting Guide

## 🚨 What's Happening: Why the Computer Crashes During Training

### Root Causes (May 23, 2026 Findings)

Your computer has **critical resource constraints** that cause overnight training crashes:

| Issue | Status | Impact |
|-------|--------|--------|
| **RAM Exhaustion** | 🔴 CRITICAL | 40 MB available out of 48 GB (system nearly OOM) |
| **GPU Underpowered** | 🟡 HIGH | RTX 2060 4GB VRAM too small for 7B models |
| **Disk Nearly Full** | 🔴 CRITICAL | C: drive 33 GB free (training logs fill it up) |
| **Background Apps** | 🟡 HIGH | VS Code + utilities consuming 2-3 GB |
| **No Crash Recovery** | 🔴 CRITICAL | Services don't auto-restart after crash |

### Why Crashes Happen

1. **Memory Pressure** → Training starts → Models load into RAM → RAM exhausted → Windows kills process
2. **Disk Full** → Training logs accumulate → C: drive fills → Cannot write logs → Crash
3. **No Recovery** → Services die → Manual restart needed → Workload lost

---

## ✅ Solutions Implemented

### 1. **Auto-Crash Recovery System**
Your services now auto-start on Windows logon:
- Ollama (local LLM engine)
- LiteLLM proxy (API gateway)
- Training queue (agent fine-tuning)

**Files:**
- `scripts/startup-recovery.ps1` - Main recovery logic
- `scripts/startup-launcher.bat` - Windows launcher
- `scripts/register-startup.ps1` - Installation script

### 2. **Crash Diagnostics**
Automatic crash analysis before training:
- RAM/disk/GPU health checks
- Process cleanup (kills duplicate services)
- Event log analysis
- Recommendations

**File:** `scripts/crash-diagnostics.ps1`

### 3. **Memory Monitoring**
Continuous RAM monitoring during training:
- Warns at 80% RAM
- Aborts at 90% RAM (prevents hard crash)
- Logs top RAM consumers
- Graceful shutdown instead of OOM crash

**File:** `scripts/train-with-monitoring.ps1`

---

## 🔧 Installation & Activation

### Step 1: Install Auto-Startup (Run Once)

```powershell
cd d:\LocalProjects\shrike-ai-lab
.\scripts\register-startup.ps1
```

**What it does:**
- Creates shortcut in Windows Startup folder
- Services auto-start on next logon
- No user action needed after reboot

**Output:**
```
✅ Installation Complete
Services will now auto-start on next Windows logon:
  • Ollama (local LLM engine)
  • LiteLLM proxy (OpenAI-compatible API on :4000)
  • Training queue (nightly agent training)
```

### Step 2: Check Installation Status

```powershell
.\scripts\register-startup.ps1 -ShowStatus
```

**Output:**
```
=== Shrike AI Lab Startup Status ===
✅ Startup shortcut installed
   Path: C:\Users\markh\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Shrike-AI-Lab-Recovery.lnk
   Working Dir: d:\LocalProjects\shrike-ai-lab
✅ Launcher script exists
✅ Recovery script exists
✅ Diagnostics script exists
```

### Step 3: Verify on Next Reboot

After rebooting:
1. Check `d:\LocalProjects\shrike-ai-lab\training\logs\startup-launcher-*.log`
2. Verify Ollama is responding:
   ```powershell
   (Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing).StatusCode
   # Should return: 200
   ```
3. Verify LiteLLM is responding:
   ```powershell
   (Invoke-WebRequest -Uri "http://localhost:4000/health" -Headers @{Authorization="Bearer sk-shrike-local"} -UseBasicParsing).StatusCode
   # Should return: 200
   ```

---

## 🎯 Immediate Actions to Reduce Crash Risk

### High Priority (Do Today)

#### 1. Clean Up Disk (Critical)
```powershell
# Delete old training logs
Get-ChildItem d:\LocalProjects\shrike-ai-lab\training\logs -Filter *.log | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
    Remove-Item

# Run Windows Disk Cleanup
cleanmgr

# Target: Get C: drive to >50 GB free
```

#### 2. Free Up RAM (Critical)
```powershell
# Close VS Code completely (not just minimize)
# Close Snagit, StreamDeck, OneDrive (non-essential during training)

# Check RAM after closing
$os = Get-CimInstance Win32_OperatingSystem
$freeRamGB = [math]::Round($os.FreePhysicalMemory / 1GB, 2)
Write-Host "Free RAM: $freeRamGB GB"

# Target: >8 GB free before training
```

#### 3. Disable Windows Search (Significant)
```powershell
# Stop Windows Search indexing (frees 1-2 GB RAM)
Stop-Service -Name WSearch -Force

# Disable on startup
Set-Service -Name WSearch -StartupType Disabled

# Verify
Get-Service -Name WSearch | Select-Object Name, Status, StartType
```

### Medium Priority (This Week)

#### 4. Limit Ollama Memory
Edit or create `d:\LocalProjects\shrike-ai-lab\.env.local`:
```env
# Limit Ollama to 2 GB max RAM (leave headroom)
OLLAMA_MAX_MEMORY=2000
```

#### 5. Use Smaller Models
Modify `training/queue/nightly_jobs.json` to use Phi-3 instead of CodeLlama 7B:
```json
{
  "model": "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
  "epochs": 1,
  "batch_size": 1
}
```

#### 6. Monitor Training Logs
During training, watch for memory warnings:
```powershell
# Real-time tail of latest training log
Get-ChildItem d:\LocalProjects\shrike-ai-lab\training\logs -Filter *.log | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 | 
    Get-Content -Tail 50 -Wait
```

---

## 🚀 Running Training Safely

### Recommended Workflow

#### Before Training Session
```powershell
cd d:\LocalProjects\shrike-ai-lab

# 1. Run crash diagnostics
.\scripts\crash-diagnostics.ps1

# 2. Check if system is healthy
# Should see: "RAM usage <80%", "Disk >30% free", no critical errors

# 3. Clean up stuck processes
Get-Process python | Where-Object { $_.CommandLine -match 'litellm' } | Stop-Process -Force
```

#### Start Training (Monitored)
```powershell
# Option A: Automatic startup (on Windows logon)
# - Just reboot, services auto-start
# - Check logs in training/logs/startup-launcher-*.log

# Option B: Manual start with monitoring
.\scripts\train-with-monitoring.ps1 -MemoryAbortPercent 85

# Option C: Old method (no monitoring - NOT RECOMMENDED)
.\scripts\startup-recovery.ps1
```

#### Monitor During Training
```powershell
# Watch for warnings
Get-ChildItem training\logs -Filter training-monitor-*.log | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 | 
    Get-Content -Tail 20 -Wait

# Stop if you see: "CRITICAL: RAM XXX% > abort threshold"
# This prevents hard crash
```

---

## 🔍 Troubleshooting

### Problem: Services Don't Auto-Start on Reboot

```powershell
# Check if shortcut is installed
Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Shrike-AI-Lab-Recovery.lnk"

# If not, reinstall
.\scripts\register-startup.ps1

# Check startup logs
Get-ChildItem training\logs -Filter startup-launcher-*.log | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 | 
    Get-Content -Tail 50
```

### Problem: Training Queue Aborts at 90% RAM

**This is intentional** - prevents hard crash. To fix:

1. **Clean disk** (see "Immediate Actions" above)
2. **Free RAM** (close unnecessary apps)
3. **Use smaller models** (Phi-3 instead of 7B)
4. **Increase swap file** (temporary workaround):
   ```powershell
   # Settings > System > Advanced > Performance > Virtual Memory
   # Set to 4 GB on D: drive (larger, faster drive)
   ```

### Problem: Ollama or LiteLLM Won't Start

```powershell
# Check if ports are in use
netstat -ano | Select-String ":11434"  # Ollama
netstat -ano | Select-String ":4000"   # LiteLLM

# Kill stuck process if needed
Get-Process -Id XXXX | Stop-Process -Force

# Restart manually
.\scripts\startup-recovery.ps1
```

### Problem: Training Queue Fails with "No Space Left"

```powershell
# Disk is full
Get-Volume | Select-Object DriveLetter, SizeRemaining, Size

# Clean up
Remove-Item d:\LocalProjects\shrike-ai-lab\training\logs\*.log -Force
Remove-Item d:\LocalProjects\shrike-ai-lab\models\* -Force
cleanmgr
```

---

## 📊 Monitoring Checklist

Before each training session, verify:

- [ ] RAM available >8 GB (`Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory`)
- [ ] C: drive free >50 GB
- [ ] D: drive free >100 GB
- [ ] LiteLLM responds to health check
- [ ] Ollama models are loaded (`ollama list`)
- [ ] No stuck Python processes (`Get-Process python | measure`)
- [ ] Log folder is not full (`Get-ChildItem training\logs | Measure-Object -Property Length -Sum`)

---

## 🔄 How to Update/Disable Auto-Start

### Disable Auto-Start (Temporary)

```powershell
# Remove startup shortcut
.\scripts\register-startup.ps1 -Uninstall
```

### Re-Enable Auto-Start

```powershell
# Reinstall startup shortcut
.\scripts\register-startup.ps1
```

### View Startup Logs

```powershell
# Latest startup attempt
Get-ChildItem training\logs -Filter startup-* | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 3 Name, LastWriteTime
```

---

## 📝 Log File Locations

| Purpose | Location | Retention |
|---------|----------|-----------|
| **Crash Diagnostics** | `training/logs/diagnostic-*.log` | Last 7 days |
| **Startup Recovery** | `training/logs/startup-recovery-*.log` | Last 7 days |
| **Startup Launcher** | `training/logs/startup-launcher-*.log` | Last 7 days |
| **Training Monitor** | `training/logs/training-monitor-*.log` | Last 7 days |
| **Training Output** | `training/logs/[project]-[task]-*.log` | Last 7 days |
| **LiteLLM** | `training/logs/litellm-startup.log` | Latest only |

---

## ⚡ Performance Tuning

### For Low-VRAM GPU (RTX 2060)

```env
# .env.local
OLLAMA_MAX_MEMORY=2000       # Limit to 2 GB
OLLAMA_NUM_PARALLEL=1        # Run 1 model at a time
OLLAMA_NUM_GPU=1             # Use only 1 GPU
```

### For Training with Limited RAM

```json
{
  "epochs": 1,
  "batch_size": 1,           # Smaller batch = less RAM
  "learning_rate": 0.0002,
  "lora_r": 8                # Lower LoRA rank = less memory
}
```

### Verify After Changes

```powershell
# Test that everything still works
.\scripts\startup-recovery.ps1
.\scripts\crash-diagnostics.ps1
```

---

## 🎓 Understanding the Crash

**What happens during a crash:**

1. Training starts → Ollama loads models into RAM
2. Training consumes CPU/GPU → RAM fills up
3. Windows memory pressure hits limit → Kills random processes
4. Training dies abruptly → No logs written → Crash appears random

**With auto-recovery:**

1. Training starts → Monitoring watches RAM
2. RAM reaches 80% → Warning logged
3. RAM reaches 90% → Queue gracefully stops → No hard crash
4. On reboot → Services auto-start → Training resumes

---

## 📞 Support

If crashes continue after following this guide:

1. **Collect diagnostics:**
   ```powershell
   .\scripts\crash-diagnostics.ps1 -Verbose > crash-report.txt
   ```

2. **Check Event Logs:**
   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} | 
       Select-Object TimeCreated, Id, Message | 
       Out-File crash-events.txt
   ```

3. **Check disk space:**
   ```powershell
   Get-Volume | Select-Object DriveLetter, SizeRemaining, Size | 
       Out-File disk-report.txt
   ```

4. **Review these logs together:**
   - `training/logs/startup-*.log`
   - `training/logs/diagnostic-*.log`
   - `crash-report.txt`
   - `crash-events.txt`

---

**Last Updated:** May 23, 2026  
**Version:** 1.0 - Initial crash mitigation suite
