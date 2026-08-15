# Overnight Local-LLM Task Queue

Runs a merged queue of two kinds of work against the local GPU server while
you're asleep:
- **`aider_fix`** (default): an agentic coding task — `aider` fixes something
  in a repo, one task per pushed branch (never merged to main/develop).
- **`train_job`**: a model fine-tuning job on the GPU server. Since training
  needs the GPU almost entirely to itself (inference already holds
  ~22.6GB/24GB VRAM), the runner **automatically stops the inference
  container before training and always restarts it after** — even if
  training fails — so chat/aider access is never left down overnight.

## Files

- `tasks.json` — the task queue. Common fields: `id`, `type` (`aider_fix` or
  `train_job`, defaults to `aider_fix`), `enabled` (defaults to `true`).
  `aider_fix` also needs `repo` (absolute path) + `prompt`. `train_job` also
  needs `project` + `task` (matching `scripts/train.py`'s `PROJECT_CONFIGS`),
  optional `engine` (defaults `unsloth`) and `version`. Edit this before bed
  to add/remove/adjust/enable tasks.
- `run_overnight.sh` — the runner. Waits for the GPU server to be reachable,
  then runs each enabled task by type, in order.
- `smoke_test.sh` — checks tooling + (if reachable) the GPU server/model,
  without running any real tasks.
- `state/` — per-night "already ran" markers, plus the `PAUSED` flag (see below).
- `logs/<date>/<id>.log` — full output per task (aider output, or the
  stop-inference/train/restart-inference sequence for `train_job`).
- `reports/<date>.md` — one-line-per-task summary for morning review.

## Pausing the queue

If you want to actively chat with the local model and don't want the queue
competing for it:

```bash
make overnight-pause    # queue won't start any FURTHER tasks tonight (or on future nights, until resumed)
make overnight-resume   # clear the pause
```

A task already in progress still finishes — pause only stops the next one
from starting (there's no safe way to interrupt a live `aider` edit or a
mid-training job). In practice this mostly matters for `train_job` tasks,
since those take inference down entirely; `aider_fix` tasks just add more
requests to the same running inference server (like an extra chat session) —
low-impact enough that you may not need to pause for those.

## Usage

```bash
make overnight-install   # installs aider (pipx), loads the launchd job
make overnight-run-now   # manually trigger a run now, bypassing the "already ran" marker
make overnight-status    # show whether the launchd job is loaded, pause state, + last marker
make overnight-report    # print the latest reports/<date>.md
make overnight-pause     # stop the queue from starting further tasks
make overnight-resume    # clear the pause
```

Or directly:

```bash
./agents/overnight/smoke_test.sh
./agents/overnight/run_overnight.sh          # normal run
./agents/overnight/run_overnight.sh --force  # rerun even if already run tonight
```

## How it's scheduled

- `~/Library/LaunchAgents/com.shrikelabs.overnight-agent.plist` fires
  `run_overnight.sh` (wrapped in `caffeinate -i`) at 23:50 daily.
- Since the Mac normally sleeps overnight, a `pmset` wake schedule is needed
  too (launchd alone won't fire on a sleeping Mac). This has to be set up by
  hand once (requires interactive `sudo`):
  ```bash
  sudo pmset repeat wakeorpoweron MTWRFSU 23:45:00
  ```
- The script itself then polls the GPU server for up to 30 minutes in case
  the Mac is slow to reconnect to the home WiFi after waking.

## Notes / known limitations

- Model name defaults to `qwen-dflash-35B-A3B` (whatever's currently loaded
  on the GPU server per the `gpu-server` skill). Override by setting
  `OVERNIGHT_MODEL=<name>` in the repo's `.env` if the loaded model changes.
- Tasks run **sequentially** — only one GPU, one loaded model.
- `train_job` tasks need the training pipeline already deployed to the GPU
  server (`make train-remote-deploy` and `make train-remote-setup` — see
  `docs/ops/LOCAL_LLM_UPGRADE_PLAN.md`), and wrap the job with
  `scripts/gpu_server_stop_inference.sh` and `scripts/gpu_server_restart.sh`.
  If stopping inference itself fails, the training run is skipped entirely
  (logged, not attempted) rather than risking an OOM crash; restarting
  inference afterward is attempted unconditionally regardless of how the job went.
- A task that errors or produces no diff is logged and skipped; there's no
  automatic retry (the known llama.cpp malformed-tool-call-JSON bug is
  deterministic at temp 0, so retrying identically just fails the same way —
  aider avoids this class of bug by not using native tool-calling, but keep
  task prompts scoped to focused fixes rather than large builds regardless).
- This never touches `main`/`develop` — only creates/pushes `overnight/*`
  branches for you to review and merge yourself.
