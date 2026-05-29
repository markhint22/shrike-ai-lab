# Cline Local Models Setup (Shrike AI Lab)

This repo is already set up for local model routing through LiteLLM.

## Recommended Provider (Cline)

Use `LiteLLM` provider in Cline.

- Base URL: `http://localhost:4000`
- API Key: `sk-shrike-local`
- Suggested model IDs:
  - `mistral-local` (better quality for most coding tasks)
  - `phi3-local` (faster for simple tasks)
  - `specpilot-local` (project-specific fallback alias)

You can also use Cline's OpenAI-compatible provider with the same endpoint and key.

## Quick Configure Steps (VS Code Cline UI)

1. Open Cline settings/provider selector.
2. Choose provider: `LiteLLM` (or `OpenAI Compatible`).
3. Set base URL to `http://localhost:4000`.
4. Set API key to `sk-shrike-local`.
5. Set Plan/Act models to `mistral-local` (or `phi3-local` for speed).
6. Save and run a short prompt test.

## Validate Before First Use

Run:

```powershell
Set-Location "d:/LocalProjects/shrike-ai-lab"
d:/LocalProjects/shrike-ai-lab/.venv/Scripts/python.exe scripts/verify_cline_local_setup.py
```

Expected result:

- Ollama check passes
- LiteLLM auth/health passes
- Model list includes local aliases
- Completion smoke test passes for `mistral-local` and `phi3-local`

## Notes About Training Interference

- Running Cline local inference while training can contend for CPU/GPU/RAM.
- For best stability, use lightweight model (`phi3-local`) during active training windows.
- Avoid restarting LiteLLM/Ollama while queue jobs are running.

## Optional Direct Ollama Route

If you want to bypass LiteLLM:

- Provider: `Ollama`
- Base URL: `http://localhost:11434`
- Model example: `mistral:7b-instruct` or `phi3:mini`

LiteLLM is still preferred in this repo because aliases are standardized across scripts and agents.
