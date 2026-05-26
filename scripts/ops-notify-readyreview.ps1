param(
    [int]$Hours = 24,
    [int]$MinSuccessRuns = 2,
    [double]$MaxFailRate = 0.50,
    [switch]$Watch,
    [int]$IntervalSec = 120,
    [switch]$QuietBoard,
    [switch]$UseModalDialog
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pythonExe = Join-Path $repoRoot ".venv\Scripts\python.exe"
$boardScript = Join-Path $repoRoot "scripts\training_intervention_board.py"
$jsonOut = Join-Path $repoRoot "training\logs\intervention-board.json"

if (-not (Test-Path $pythonExe)) {
    Write-Error "Python venv not found at $pythonExe"
}

function Invoke-Board {
    $args = @(
        $boardScript,
        "--hours", $Hours,
        "--min-success-runs", $MinSuccessRuns,
        "--max-fail-rate", $MaxFailRate,
        "--json-out", $jsonOut
    )

    if ($QuietBoard) {
        & $pythonExe @args | Out-Null
    } else {
        & $pythonExe @args
    }
}

function Get-ReadyQueue {
    if (-not (Test-Path $jsonOut)) {
        return @()
    }
    $report = Get-Content $jsonOut -Raw | ConvertFrom-Json
    $ready = @($report.rows | Where-Object { $_.recommendation -eq "READY_REVIEW" })
    return @($ready | ForEach-Object { "{0}/{1}" -f $_.project, $_.task })
}

function Send-ReadyNotification {
    param(
        [string[]]$Items
    )

    $title = "Shrike AI Lab: READY_REVIEW"
    $body = "Human intervention needed for:`n" + ($Items -join "`n")

    # Preferred path: Windows toast via BurntToast if installed.
    $hasBurntToast = @(Get-Module -ListAvailable -Name BurntToast).Count -gt 0
    if ($hasBurntToast) {
        Import-Module BurntToast -ErrorAction SilentlyContinue | Out-Null
        if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
            New-BurntToastNotification -Text $title, $body | Out-Null
            return
        }
    }

    # Non-blocking fallback: console + audible beep.
    [console]::beep(1000, 400)
    Write-Host "[NOTIFY] $title"
    Write-Host $body

    # Optional blocking dialog for users who explicitly request it.
    if ($UseModalDialog) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($body, $title, "OK", "Information") | Out-Null
    }
}

Write-Host "=== READY_REVIEW Notifier ==="
Write-Host "Time: $(Get-Date -Format o)"
Write-Host "Repo: $repoRoot"
Write-Host ""

if (-not $Watch) {
    Invoke-Board
    $ready = Get-ReadyQueue

    Write-Host ""
    Write-Host "[Ready queue]"
    if ($ready.Count -eq 0) {
        Write-Host "- none"
        exit 0
    }

    foreach ($item in $ready) {
        Write-Host "- $item"
    }

    Send-ReadyNotification -Items $ready
    exit 0
}

Write-Host "Watch mode enabled (interval: ${IntervalSec}s). Press Ctrl+C to stop."
$lastSignature = ""

while ($true) {
    Invoke-Board
    $ready = Get-ReadyQueue
    $signature = (($ready | Sort-Object) -join ";")

    if ($ready.Count -gt 0) {
        Write-Host "[$(Get-Date -Format T)] READY_REVIEW: $($ready -join ', ')"
        if ($signature -ne $lastSignature) {
            Send-ReadyNotification -Items $ready
            $lastSignature = $signature
        }
    } else {
        Write-Host "[$(Get-Date -Format T)] READY_REVIEW: none"
        $lastSignature = ""
    }

    Start-Sleep -Seconds $IntervalSec
}
