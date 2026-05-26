param(
    [int]$Hours = 24,
    [int]$MinSuccessRuns = 2,
    [double]$MaxFailRate = 0.50
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pythonExe = Join-Path $repoRoot ".venv\Scripts\python.exe"
$jsonOut = Join-Path $repoRoot "training\logs\intervention-board.json"

if (-not (Test-Path $pythonExe)) {
    Write-Error "Python venv not found at $pythonExe"
}

Write-Host "=== Intervention Results ==="
Write-Host "Time: $(Get-Date -Format o)"
Write-Host ""

& $pythonExe (Join-Path $repoRoot "scripts\training_intervention_board.py") `
    --hours $Hours `
    --min-success-runs $MinSuccessRuns `
    --max-fail-rate $MaxFailRate `
    --json-out $jsonOut

Write-Host ""
Write-Host "[Ready for review now]"
$report = Get-Content $jsonOut -Raw | ConvertFrom-Json
$ready = @($report.rows | Where-Object { $_.recommendation -eq "READY_REVIEW" })
if ($ready.Count -eq 0) {
    Write-Host "- none"
} else {
    foreach ($row in $ready) {
        Write-Host ("- {0}/{1}" -f $row.project, $row.task)
    }
}
