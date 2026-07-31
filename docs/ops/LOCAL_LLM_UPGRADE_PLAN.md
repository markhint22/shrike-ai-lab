# Local LLM Upgrade Plan — Tailscale, Overnight Runner, Local Training

Status doc for three related in-progress efforts, written 2026-07-31 while offline
(no GPU server access). Everything in "What's done" was built and tested as far
as possible without the server; everything in "TODO" needs the home LAN and/or
the GPU server and picks up from here.

Read this top to bottom the first time you're back — the sections are ordered
roughly in the sequence you'd actually do them.

---

## 1. Tailscale (blocks remote/car access to the GPU server)

**Why**: `192.168.68.145` is LAN-only. Whenever you're off the home WiFi
(car, on the road), nothing that talks to the GPU server works — this is
what's blocking a lot of the rest of this doc from being tested right now.

**Status, re-verified 2026-07-31**: corrected from a stale earlier note —
Tailscale is **not installed on the Mac** (`which tailscale` → not found, no
`/Applications/Tailscale.app`). Don't trust the old "already installed" note
without re-checking.

### TODO
- [ ] On the Mac: `brew install --cask tailscale-app`, then approve the
      system extension in **System Settings → Privacy & Security**, then log
      in via the browser flow it opens. All three steps need you physically
      clicking through them — not automatable.
- [ ] Confirm with `tailscale status`.
- [ ] While physically on the home network: SSH into the GPU server
      (`make gpu-ssh`) and do the same install + login there.
- [ ] Once both sides show up in `tailscale status`, switch from the LAN IP to
      the new Tailscale IP (`100.x.x.x`) in:
  - `shrike-ai-lab/.env` (`GPU_SERVER_HOST`, `LITELLM_BASE_URL`, `LLAMA_SERVER_URL`)
  - `~/.continue/config.yaml` (`apiBase` fields)
  - Cline's provider base URL
  - `agents/overnight/run_overnight.sh` picks up `.env` automatically, no separate edit needed there.

---

## 2. Overnight local-LLM task queue (built last session, merged with training this session)

Lives at `shrike-ai-lab/agents/overnight/` — full details in its own README.
Quick recap: one merged queue (`tasks.json`), two task types:
- `aider_fix` (the original coding-task runner — `aider`, not Continue CLI,
  see the README for why): fixes something in a repo, one task per pushed
  branch, never merged to main/develop.
- `train_job` (new this session — see §4): runs a fine-tuning job on the GPU
  server. **Automatically stops the inference container first and always
  restarts it after**, even on failure — training needs the GPU almost
  entirely to itself, it can't share with inference.

New: `make overnight-pause` / `make overnight-resume` — stops the queue from
starting further tasks (e.g. while you're actively chatting with the local
model). An in-progress task still finishes; there's no safe way to interrupt
a live aider edit or a mid-training job. In practice this matters most for
`train_job` tasks (hard GPU conflict) — `aider_fix` tasks just add more
inference load, similar to an extra chat session, low-impact enough you may
not need to pause for those specifically.

### TODO
- [ ] Run, once, requires interactive sudo (couldn't be scripted):
      `sudo pmset repeat wakeorpoweron MTWRFSU 23:45:00`
      — without this the Mac won't wake up to run the launchd job at all.
- [ ] First live test: `make overnight-run-now`, then check
      `make overnight-report` and the logs under `agents/overnight/logs/`.
- [ ] Review/edit `agents/overnight/tasks.json` — the 3 seeded `aider_fix`
      tasks are a starting point, not verified-correct fixes. The 4th task
      (`specpilot-selector-optimization-smoke`, `type: train_job`) is a
      template, disabled by default — flip `enabled` to `true` once you've
      deployed the training pipeline (§4) and are ready for a real run.

---

## 3. Verify the local model setup itself

From the "existing artifacts" research earlier: your current model is
already close to the community-consensus best pick for a 24GB card, so the
highest-value cheap check is confirming what you already have actually works,
not chasing a different model.

### TODO
- [ ] `curl http://192.168.68.145:4000/v1/models` (or `make gpu-status`) —
      confirm whether `qwen-dflash-27B` (registered in `~/.continue/config.yaml`
      but flagged as unconfirmed in `.claude/skills/gpu-server/SKILL.md`) is
      actually live. 27B, not 35B, was the specific size called out as best
      for a 24GB card.
- [ ] If you want to look at **Laguna XS 2.1** (Poolside) as a coding-focused
      alternative, check Poolside's own page directly first — the source that
      surfaced it was a listicle-style site, not verified firsthand.

---

## 4. Training your own model — what changed this session

You already have a training pipeline (`scripts/train.py`, per-project
`training/<project>/finetune.py`, a job-queue runner). It was built assuming
**Windows** (the GPU box used to be Windows); the box is now Linux. Ported
what's actually needed for training; deliberately did **not** touch two large
unrelated subsystems — see "Explicitly out of scope" below.

### Done this session (tested as far as possible without the server)

- **`scripts/train_queue.py`, `scripts/start_nightly_queue.py`**: replaced the
  Windows-only `tasklist`/PowerShell `Win32_Process` process-checks with a
  portable `os.kill(pid, 0)` check (same technique `log_layout.py` already
  used elsewhere in this repo) and `pgrep -f` for scanning running queue
  processes. Also added real POSIX process detachment (`start_new_session=True`)
  so the queue survives an SSH disconnect, matching what `DETACHED_PROCESS`
  already did for Windows.
- **`scripts/queue_ops.py`** (new): a straight port of `queue_ops.ps1`'s 8
  subcommands (`status`, `jobs`, `tail`, `tailrun`, `tailrunf`, `failures`,
  `pids`, `cleanup`) to plain Python — no PowerShell dependency. `Makefile`'s
  `queue-*` targets now call this.
- **`scripts/gpu_server_deploy_training.sh`** (new) + `make train-remote-*`
  targets: rsyncs `scripts/` + `training/` (minus logs/cache/models) to a
  **dedicated** `~/shrike-ai-lab-training` directory on the GPU server —
  deliberately *not* the docker-compose directory, since that's already
  diverged from this repo and training must never risk clobbering it.
  - `make train-remote-deploy` — sync code to the server
  - `make train-remote-setup` — create a venv there, `pip install -r requirements.txt`, then `pip install unsloth` separately (matches the note already in `requirements.txt`)
  - `make train-remote-run P=<project> T=<task> [E=hf|unsloth] [V=<version>]` — run one job
  - `make train-remote-queue` — start the nightly job queue there, detached
  - `make train-remote-status` — check queue status there
  - Fixed `scripts/gpu_server_ssh.sh` to add `-o ConnectTimeout=10` — discovered
    by testing that without it, any of these commands would hang for 1-2
    minutes (not fail fast) when run off the home LAN. All the new targets
    were verified to fail in ~10s when tested from the road just now.
- **Confirmed `--engine unsloth` already exists** in `scripts/train.py` (line
  ~313 onward) — it wasn't missing, just never runnable since nothing here
  ever had CUDA before. Read through it; looks complete (`FastLanguageModel`
  load → LoRA via `get_peft_model` → `SFTTrainer`), not broken.
- Ran `python scripts/train.py --preflight` locally: confirms both engines
  correctly report missing deps on the Mac (expected — no CUDA here), and
  that all 18 project/task data files are present.

### TODO once home / on the GPU server
- [ ] `make train-remote-deploy`
- [ ] `make train-remote-setup` (installs unsloth + deps — needs CUDA, only
      works on the server)
- [x] **GPU memory conflict — decided**: the server's GPU is already
      near-maxed (~22.6GB / 24GB) by the inference model
      (`qwen-dflash-35B-A3B` holding a Q4 main + Q8 draft model
      simultaneously), so inference and training can't run at once. You chose
      auto stop/restart (not manual, not idle-detection) — implemented via
      `scripts/gpu_server_stop_inference.sh` + `scripts/gpu_server_restart.sh`,
      wired into the overnight queue's `train_job` task type (§2). Chat/aider
      is unavailable only for the duration of an actual training task, and
      always comes back automatically, even if training itself fails.
- [ ] `make train-remote-run P=specpilot T=selector_optimization E=unsloth` as
      a first real smoke test (small existing sample data, ~13 examples) —
      or just flip `enabled: true` on the seeded `train_job` task in
      `agents/overnight/tasks.json` and let the queue do it overnight.

### Open decisions (deliberately not changed without you)
- **Base models in `scripts/train.py` `PROJECT_CONFIGS`** are
  `codellama/CodeLlama-7b-hf` and `mistralai/Mistral-7B-Instruct-v0.2` — picked
  for the old RTX 2080/2080 Ti hardware. Now that the server has a 24GB RTX
  3090, worth considering something more current (e.g. a Qwen2.5/3-Coder 7B
  variant) — but this changes prompt formatting expectations downstream, so
  it's a real decision, not a drop-in swap. Flagging, not changing.
- **Real training data**: everything under `training/*/data/*.jsonl` is
  10-15 example rows — seed/format samples, not enough for a meaningful
  fine-tune. Collecting real training data (from your actual repos/PR
  history/etc.) is a distinct, larger task on its own, out of scope for this
  session.

### Explicitly out of scope (found, deliberately not touched)
Two other Windows-era subsystems exist in `scripts/` and weren't ported —
don't assume they're ready:
- **Startup/crash-recovery cluster** (`register_windows_startup.ps1`,
  `register-startup.ps1`, `startup-recovery.ps1`, `startup-launcher.bat`,
  `crash-diagnostics.ps1`, `recover_after_crash.py`): this auto-recovers
  Ollama/LiteLLM/the training queue on a Windows logon/crash. It's superseded
  by Docker's own `unless-stopped` restart policy on the Linux box — the real
  recovery playbook for this box now lives in
  `.claude/skills/gpu-server/SKILL.md`. Treat as dead code unless you
  specifically want to resurrect Windows-style auto-recovery for some reason.
- **Agent-team promotion pipeline** (`start_agent_team_bootstrap.py`,
  `training_intervention_board.py`, `evaluate_agent_teams.py`,
  `decide_agent_team_promotion.py`, `resume_agent_team_rollout.py`,
  `auto_apply_agent_team_promotions.py`, `review_ab_gates.py`,
  `eval_learning_trend.py`, `learning_snapshot.py`, the `ops-*.ps1` scripts):
  a separate, much larger initiative (A/B-gated autonomous agent-team
  rollout, per `docs/AGENT_TEAM_IMPLEMENTATION_PLAN.md`) that's unrelated to
  "fine-tune a coding model on my own repo." Left entirely alone — a much
  bigger project if you ever want to pick it up, not something folded into
  this pass.

---

## Suggested order when you're back

1. Tailscale (§1) — unblocks everything else remotely in the future.
2. `sudo pmset ...` (§2) + `make overnight-run-now` — cheapest to verify, already fully built.
3. `curl :4000/v1/models` (§3) — free, 10-second check.
4. `make train-remote-deploy` → `train-remote-setup` → decide the GPU-sharing
   question → `train-remote-run` smoke test (§4).
