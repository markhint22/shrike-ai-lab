---
name: gpu-server
description: Operate the Shrike AI Lab GPU server (192.168.68.145) that serves local LLMs for Continue.dev - status checks, restarts, logs, and known failure modes. Use when a local model in Continue is erroring, slow, or unreachable, or when doing infra work on the GPU box itself.
---

# Shrike AI Lab GPU Server

Connection details live in `shrike-ai-lab/.env` (gitignored). Summary:

- Host `192.168.68.145`, hostname `markhint-server1`, SSH user `mhintermeister`, key-based auth already set up (no password).
- LiteLLM proxy: `http://192.168.68.145:4000` (key `sk-shrike-local`) — this is what Continue's `apiBase` points at.
- Direct llama.cpp server: `http://192.168.68.145:8081` (bypasses litellm, useful for isolating whether a bug is in litellm or the model server).
- Real `docker-compose.yml` lives ON the server at `/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab` — **not** in this repo's local copy, which has diverged (older, Ollama-only). Always edit the one on the server.
- GPU: single RTX 3090, 24GB VRAM. Currently near-maxed (~22.6GB) by `qwen-dflash-35B-A3B` holding both a Q4_K_M main model and Q8_0 draft model in VRAM simultaneously for self-speculative decoding — very little headroom left for raising `--ctx-size` further without freeing something else first.

## Quick commands

Run from the `shrike-ai-lab` repo root (scripts source `.env` automatically):

```bash
make gpu-status              # SSH reachability, GPU usage, container status, API health
make gpu-test                # send a real completion to qwen-dflash-35B-A3B and print the response
make gpu-test M=qwen-coder-30b-local   # test a different model
make gpu-logs                # tail shrike-llama-dflash-35b logs (default)
make gpu-logs C=shrike-litellm         # tail a different container
make gpu-restart              # restart shrike-llama-dflash-35b and wait for healthy
make gpu-restart C=shrike-litellm      # restart a different container
make gpu-ssh                  # interactive shell on the box
make gpu-ssh C="docker ps -a"         # one-off remote command (positional, not C=)
```

Underlying scripts are in `scripts/gpu_server_*.sh` if you need something the Makefile targets don't cover — they're plain bash, safe to read/extend.

## Known failure modes (already hit and fixed once each — check these first)

1. **Whole stack down after a host reboot, containers show "Exited ... N days ago"**: the model/compose files live on a secondary NVMe drive (`/dev/nvme0n1p1`, UUID `6dc56e73-e062-4168-bb50-260a62e3f2da`) that historically had **no fstab entry** and needed a manual/desktop mount. Fixed by adding `UUID=6dc56e73-e062-4168-bb50-260a62e3f2da /run/media/mhintermeister/secondary_drive1 ext4 defaults,nofail 0 2` to `/etc/fstab` (backed up first as `/etc/fstab.bak.<date>`). If this regresses, check `mount | grep secondary_drive1` — if empty, `sudo mount -a` should bring it back without needing the manual `sudo mount /dev/nvme0n1p1 ...` workaround.

2. **`llama-dflash-35b` crash-loops citing a missing `--chat-template-file`**: this points at `/models/deepflash/fixed_template.jinja`, a patched copy of the model's embedded chat template (see below) — it lives on the secondary drive, so this is usually downstream of failure mode #1 (drive not mounted → file "missing" → llama-server exits → docker restarts it → loop). Fix the mount first, then `make gpu-restart`.

3. **Container can't see the GPU (`nvidia-smi` inside container → "Failed to initialize NVML: Unknown Error"), model runs on CPU at ~5 tok/s instead of GPU at ~180 tok/s**: boot-order race — Docker started ~16s after the kernel, before the NVIDIA driver stack was ready, and `unless-stopped` containers grabbed a broken GPU handle before the driver caught up. Fix: `docker restart <container>` once the system's been up a bit (don't need to restart the whole Docker daemon). Diagnose with `docker exec <container> nvidia-smi` — if that fails but host-level `nvidia-smi` works, this is the cause.

4. **Model silently much slower than expected, "b10088" build but no CUDA/offload logs, GPU memory near-idle even while a request is running**: the image `ghcr.io/ggml-org/llama.cpp:server` (no suffix) is the **CPU-only** build. Need `ghcr.io/ggml-org/llama.cpp:server-cuda` instead. Check `docker inspect <container> --format '{{.Config.Image}}'`.

5. **Continue error: `context_window_fallback` / "Available Model Group Fallbacks=None"**: `contextLength` in `~/.continue/config.yaml` doesn't match the model's real `max_input_tokens` (check via `curl http://192.168.68.145:4000/v1/models` — the real ceiling shows up per-model there). Fix by lowering `contextLength` to match reality, not by adding a fallback model (there usually isn't a second model loaded to fall back to anyway).

6. **litellm 500: `Failed to parse tool call arguments as JSON... missing closing quote`, on a large file-write tool call**: open upstream `llama.cpp` bug ([ggml-org/llama.cpp#22948](https://github.com/ggml-org/llama.cpp/issues/22948)) — Qwen3.6-dflash occasionally emits malformed JSON for large tool-call string arguments, and llama-server has no graceful recovery. No config fix. Mitigate by asking the model to write large files in smaller pieces, or start a fresh chat rather than retrying the identical oversized request (temperature 0 means retries reproduce the exact same failure).

7. **litellm 400: `Unable to generate parser for this template... Jinja Exception: No user query found in messages` / `System message must be at the beginning`**: the model's *embedded* chat template has hard `raise_exception()` self-checks that llama.cpp's automatic tool-parser-generation probe trips over. Already patched: pulled the template via `curl http://192.168.68.145:8081/props`, stripped just those two `raise_exception` calls (left the legitimate input-validation ones alone), saved as `/models/deepflash/fixed_template.jinja` on the secondary drive, and pointed the container at it via `--chat-template-file` in `docker-compose.yml`. If a similar error recurs on a *different* model added later, same fix applies: fetch `/props`, find the offending `raise_exception`, patch it out, point `--chat-template-file` at the patched copy.

8. **This model "thinks" a lot and burns its token budget before producing real output** (Qwen3-family reasoning behavior, shows up as `reasoning_content` and can cause timeouts in clients with no per-request override, e.g. Cline): fixed **server-side** in `configs/litellm_config.yaml` on the box itself — both the `qwen-dflash-35B-A3B` and `qwen-dflash-27B` `litellm_params` entries have:
   ```yaml
   chat_template_kwargs:
     enable_thinking: false
   ```
   litellm passes unrecognized `litellm_params` keys straight through to the backend as default request params, so this applies to **every client** (Cline, Continue, raw curl) automatically — no client-side config needed. Verified: a plain request with zero extra params now returns in <1s with `reasoning_content: null`, versus burning the full token budget on invisible reasoning before this fix. Continue's `config.yaml` also has this same override client-side (`requestOptions.extraBodyProperties`) from before this server-side fix existed — redundant now but harmless. If adding a new model that has the same thinking-mode behavior, prefer adding it here (server-side) over per-client config, since not every client (e.g. Cline) supports custom body parameters at all.

## Continue.dev config notes

- Continue's own IDE extension (checked v2.0.0 and the 2.1.0 pre-release directly in the installed extension code, not just docs) has **no global "auto-accept all tool calls" toggle** — that's CLI-only (`cn --auto`, `~/.continue/permissions.yaml`), unrelated to the VS Code/JetBrains extension. To stop being prompted on every terminal command: in the Continue chat panel, click the wrench icon in the small toolbar directly above the message input (tooltip: "Configure tools") → find the tool (e.g. `run_terminal_command`) → change its dropdown from "Ask First" to "Automatic". This is per-tool, per-workspace UI state, not something scriptable from here.
- `~/.continue/config.yaml` model names must exactly match what's registered on the litellm proxy — check `curl http://192.168.68.145:4000/v1/models` before assuming a model config entry actually resolves to something real. Some configured model names (e.g. `qwen-dflash-27B`, `qwen-dflash-9B`) may not currently be registered even though they're in Continue's config.
