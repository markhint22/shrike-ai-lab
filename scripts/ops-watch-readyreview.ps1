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

$argsList = @(
    "-Watch",
    "-Hours", $Hours,
    "-MinSuccessRuns", $MinSuccessRuns,
    "-MaxFailRate", $MaxFailRate,
    "-IntervalSec", $IntervalSec
)

if ($QuietBoard) { $argsList += "-QuietBoard" }
if ($UseModalDialog) { $argsList += "-UseModalDialog" }

& $notifyScript @argsList
