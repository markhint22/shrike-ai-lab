# Shrike AI Lab - Startup Registration Script
# Install auto-recovery to Windows logon

param(
    [switch]$Uninstall = $false,
    [switch]$ShowStatus = $false
)

$projectRoot = "d:\LocalProjects\shrike-ai-lab"
$launcherBat = "$projectRoot\scripts\startup-launcher.bat"
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$shortcutPath = "$startupFolder\Shrike-AI-Lab-Recovery.lnk"

function Log {
    param([string]$msg)
    Write-Host $msg
}

if ($ShowStatus) {
    Log "=== Shrike AI Lab Startup Status ==="
    
    if (Test-Path $shortcutPath) {
        Log "✅ Startup shortcut installed"
        $shortcut = New-Object -ComObject WScript.Shell
        $link = $shortcut.CreateShortcut($shortcutPath)
        Log "   Path: $($link.TargetPath)"
        Log "   Working Dir: $($link.WorkingDirectory)"
    } else {
        Log "❌ Startup shortcut NOT installed"
    }
    
    Log ""
    Log "Launcher script: $(if (Test-Path $launcherBat) { '✅ Exists' } else { '❌ Missing' })"
    Log "Recovery script: $(if (Test-Path "$projectRoot\scripts\startup-recovery.ps1") { '✅ Exists' } else { '❌ Missing' })"
    Log "Diagnostics script: $(if (Test-Path "$projectRoot\scripts\crash-diagnostics.ps1") { '✅ Exists' } else { '❌ Missing' })"
    
    exit 0
}

if ($Uninstall) {
    Log "Uninstalling startup launcher..."
    
    if (Test-Path $shortcutPath) {
        try {
            Remove-Item -Path $shortcutPath -Force -ErrorAction Stop
            Log "✅ Removed startup shortcut"
        } catch {
            Log "❌ Failed to remove shortcut: $_"
            exit 1
        }
    } else {
        Log "ℹ️  Shortcut not found (already uninstalled)"
    }
    
    exit 0
}

# Installation mode (default)
Log "=== Installing Shrike AI Lab Auto-Recovery ==="

# Verify launcher script exists
if (-not (Test-Path $launcherBat)) {
    Log "❌ ERROR: Launcher script not found at $launcherBat"
    exit 1
}

Log "✅ Launcher script found"

# Create startup folder if it doesn't exist
if (-not (Test-Path $startupFolder)) {
    Log "Creating startup folder..."
    try {
        New-Item -ItemType Directory -Path $startupFolder -Force | Out-Null
        Log "✅ Startup folder created"
    } catch {
        Log "❌ Failed to create startup folder: $_"
        exit 1
    }
}

# Remove old shortcut if it exists
if (Test-Path $shortcutPath) {
    Log "Removing old startup shortcut..."
    try {
        Remove-Item -Path $shortcutPath -Force
    } catch {}
}

# Create Windows shortcut
Log "Creating startup shortcut..."

try {
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    
    # Point to batch launcher
    $shortcut.TargetPath = $launcherBat
    $shortcut.WorkingDirectory = $projectRoot
    $shortcut.WindowStyle = 7  # Minimized
    $shortcut.Description = "Shrike AI Lab - Auto-Recovery for Ollama, LiteLLM, and Training Queue"
    
    $shortcut.Save()
    
    Log "✅ Created shortcut: $shortcutPath"
    
} catch {
    Log "❌ Failed to create shortcut: $_"
    exit 1
}

# Verify it was created
if (Test-Path $shortcutPath) {
    Log "✅ Shortcut verified"
    Log ""
    Log "=== Installation Complete ==="
    Log "Services will now auto-start on next Windows logon:"
    Log "  • Ollama (local LLM engine)"
    Log "  • LiteLLM proxy (OpenAI-compatible API on :4000)"
    Log "  • Training queue (nightly agent training)"
    Log ""
    Log "Startup logs location:"
    Log "  d:\LocalProjects\shrike-ai-lab\training\logs\startup\startup-*.log"
    Log ""
    Log "To disable auto-start, run:"
    Log "  .\scripts\register-startup.ps1 -Uninstall"
    Log ""
    Log "To check status, run:"
    Log "  .\scripts\register-startup.ps1 -ShowStatus"
    
    exit 0
} else {
    Log "❌ Failed to verify shortcut creation"
    exit 1
}
