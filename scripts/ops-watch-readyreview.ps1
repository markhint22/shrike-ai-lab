param(
    [int]$Hours = 24,
    [int]$MinSuccessRuns = 2,
    [double]$MaxFailRate = 0.50,
    [int]$IntervalSec = 120,
    [switch]$QuietBoard,
    [switch]$UseModalDialog
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$notifyScript = Join-Path $repoRoot "scripts\ops-notify-readyreview.ps1"

if (-not (Test-Path $notifyScript)) {
    Write-Error "Notifier script not found: $notifyScript"
}

if ($QuietBoard -and $UseModalDialog) {
    & $notifyScript -Watch -Hours $Hours -MinSuccessRuns $MinSuccessRuns -MaxFailRate $MaxFailRate -IntervalSec $IntervalSec -QuietBoard -UseModalDialog
} elseif ($QuietBoard) {
    & $notifyScript -Watch -Hours $Hours -MinSuccessRuns $MinSuccessRuns -MaxFailRate $MaxFailRate -IntervalSec $IntervalSec -QuietBoard
} elseif ($UseModalDialog) {
    & $notifyScript -Watch -Hours $Hours -MinSuccessRuns $MinSuccessRuns -MaxFailRate $MaxFailRate -IntervalSec $IntervalSec -UseModalDialog
} else {
    & $notifyScript -Watch -Hours $Hours -MinSuccessRuns $MinSuccessRuns -MaxFailRate $MaxFailRate -IntervalSec $IntervalSec
}
