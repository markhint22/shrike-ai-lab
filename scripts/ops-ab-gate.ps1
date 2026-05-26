param(
    [Parameter(Mandatory = $true)] [string]$Project,
    [Parameter(Mandatory = $true)] [string]$Task,
    [Parameter(Mandatory = $true)] [string]$BaselineModel,
    [Parameter(Mandatory = $true)] [string]$CandidateModel,
    [string]$TestData = "",
    [int]$Limit = 20
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pythonExe = Join-Path $repoRoot ".venv\Scripts\python.exe"
$abGatesDir = Join-Path $repoRoot "training\logs\ab-gates"
New-Item -ItemType Directory -Path $abGatesDir -Force | Out-Null
$outFile = Join-Path $abGatesDir ("ab-gate-{0}-{1}.json" -f $Project, $Task)

if (-not (Test-Path $pythonExe)) {
    Write-Error "Python venv not found at $pythonExe"
}

$argsList = @(
    (Join-Path $repoRoot "scripts\ab_eval_gate.py"),
    "--project", $Project,
    "--task", $Task,
    "--baseline-model", $BaselineModel,
    "--candidate-model", $CandidateModel,
    "--limit", $Limit,
    "--json-out", $outFile
)

if ($TestData -ne "") {
    $argsList += @("--test-data", $TestData)
}

& $pythonExe @argsList

Write-Host ""
Write-Host "Saved A/B report: $outFile"
