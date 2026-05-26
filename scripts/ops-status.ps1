param(
    [switch]$IncludeTrainingSummaries = $true
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pythonExe = Join-Path $repoRoot ".venv\Scripts\python.exe"
$interventionsDir = Join-Path $repoRoot "training\logs\interventions"
New-Item -ItemType Directory -Path $interventionsDir -Force | Out-Null

if (-not (Test-Path $pythonExe)) {
    Write-Error "Python venv not found at $pythonExe"
}

Write-Host "=== Shrike AI Lab Status ==="
Write-Host "Time: $(Get-Date -Format o)"
Write-Host "Repo: $repoRoot"
Write-Host ""

# Ports and service health
Write-Host "[Health checks]"
try {
    $ollama = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 5
    Write-Host "Ollama: OK (11434)"
} catch {
    Write-Host "Ollama: DOWN (11434)"
}

try {
    $headers = @{ Authorization = "Bearer sk-shrike-local" }
    $null = Invoke-RestMethod -Uri "http://localhost:4000/health" -Headers $headers -Method Get -TimeoutSec 5
    Write-Host "LiteLLM: OK (4000)"
} catch {
    Write-Host "LiteLLM: DOWN (4000)"
}

Write-Host ""
Write-Host "[Active training processes]"
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match 'train_queue.py|scripts\\train.py' } |
    Select-Object ProcessId, Name, CreationDate, CommandLine |
    Format-Table -AutoSize

if ($IncludeTrainingSummaries) {
    Write-Host ""
    Write-Host "[Learning snapshot]"
    & $pythonExe (Join-Path $repoRoot "scripts\learning_snapshot.py")

    Write-Host ""
    Write-Host "[Learning trend]"
    & $pythonExe (Join-Path $repoRoot "scripts\eval_learning_trend.py")

    Write-Host ""
    Write-Host "[Intervention board]"
    & $pythonExe (Join-Path $repoRoot "scripts\training_intervention_board.py") --json-out (Join-Path $interventionsDir "intervention-board.json")
}
