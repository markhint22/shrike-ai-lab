# DFlash Single Active Model Workflow

This runbook defines the one-model-at-a-time setup for local DFlash serving.

## Why this mode

- Keeps memory usage predictable.
- Avoids running multiple heavyweight model servers concurrently.
- Matches Continue usage where one selected model should handle each chat request.

## Current active model target

- Model name exposed to clients: `qwen-dflash-35B-A3B`
- API endpoint clients use: `http://<host-ip>:4000/v1/chat/completions`
- Auth header: `Authorization: Bearer sk-shrike-local`

## How requests route

1. Continue on a remote machine sends a chat request to LiteLLM.
2. LiteLLM routes `qwen-dflash-35B-A3B` to llama.cpp speculative server.
3. llama.cpp serves with target+draft pair (DFlash).

Only the model you select is used for that chat call.

## Commands

### Activate 35B DFlash

```bash
make active-35b
```

This will:

- Ensure required GGUF files are present (resumable downloads).
- Start `llama-dflash-35b` and `litellm` services.
- Perform a local validation call through LiteLLM.

### Check progress/status

```bash
make active-35b-status
```

This reports:

- Target GGUF download progress.
- Draft GGUF download progress.
- Service states and health checks.

## Readiness test

Run after `make active-35b-status` shows both files ready and DFlash health ready:

```bash
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-shrike-local" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-dflash-35B-A3B",
    "messages": [{"role":"user","content":"Reply with exactly DFLASH_35B_READY"}],
    "temperature": 0
  }' | jq -r '.choices[0].message.content // .error.message'
```

Expected output:

- `DFLASH_35B_READY`

## LAN test from another machine

```bash
curl -s http://192.168.68.145:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-shrike-local" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-dflash-35B-A3B",
    "messages": [{"role":"user","content":"Reply with exactly LAN_OK"}],
    "temperature": 0
  }' | jq -r '.choices[0].message.content // .error.message'
```

## Notes

- Draft-only DFlash GGUF files are not standalone models.
- They require speculative runtime support (llama.cpp/SGLang) plus a target model.
- If DFlash service is not ready, keep using `make active-35b-status` until downloads complete.
