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

## spec-draft-n-max tuning (tested 2026-08-15, reverted)

`--spec-draft-n-max` is configurable via `DFLASH_SPEC_DRAFT_N_MAX` (default 4,
set in `docker-compose.yml`/`switch-active-model.sh`). Tested raising it to 8
on qwen-dflash-27B to see if the already-high draft acceptance rate (measured
0.63-0.81 at n_max=4) meant a higher cap would improve throughput:

- Benchmark 1 (structured code + tests, easily-predictable content): 7.51
  tok/s at n_max=8, up from ~5.16 tok/s baseline at n_max=4 (+45%).
- Benchmark 2 (mixed prose + code, less predictable): ~4.3 tok/s at n_max=8 -
  *worse* than the n_max=4 baseline.

Conclusion: throughput is highly content-dependent (draft acceptance varies a
lot with how predictable the generated text is), so a higher n_max is not a
reliable win - it can help or hurt depending on the task. Reverted to the
default of 4 rather than leave an unproven change on shared infra. If
revisiting this, benchmark against the actual overnight-queue workload
specifically (code diffs, not generic prompts) with enough samples to average
out content-dependent variance, not a couple of one-off requests.
