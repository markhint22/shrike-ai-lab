# Character Art Pipeline — READY (prep verified 2026-09-02, not yet run)

Generates the **DEAD** (side-lying corpse canon, redo) and **DOWNED** (wounded/
incapacitated on-side, new) sprite states for all 14 xlite units, QA-gated with
auto-reject + re-roll. Pure txt2img **SDXL + pixel-art-xl LoRA** (NO ControlNet /
OpenPose / IP-Adapter / pose skeletons — those belong to the anim flows).

## One-command start (run when the GPU can be given to art)
```bash
nohup bash ~/overnight-queue/art/art_character_window.sh \
  >> ~/overnight-queue/reports/art-characters.out 2>&1 &
```
Foreground equivalent: `bash ~/overnight-queue/art/art_character_window.sh`
(it self-logs to `reports/art-characters.out`). Durable, self-contained copy;
the original `/tmp/art_character_window.sh` still works too.

> This is a GPU WINDOW: it deliberately stops the 27B fleet (and the coder-next
> trial container) for its whole duration. Only start it when you are OK with
> chat/aider being down for ~30–60 min.

## What it does (stages)
1. `touch state/art_window.hold`, `queue.sh pause`, wait for `state/run.lock` to
   clear, then `docker stop shrike-llama-dflash-35b shrike-llama-coder-next` to
   free VRAM; waits until GPU < 2500 MiB.
2. `art_pipeline_run.py --role dead --passes 3`, then `--role downed --passes 3`
   (each hard-capped at `timeout 2400` = 40 min). Per pass:
   `gen_from_brief.py` (SDXL 1024, 40 steps) → `pixelize3.py` (CPU: bg-key,
   autocrop, @64/@48/@32 + 8x previews) → `art_qa_gate.py` inspects each sprite
   and RE-ROLLS only the failures next pass (fresh seed). Nothing failing QA is kept.
3. On EXIT (success, failure, or timeout) a trap removes `art_window.hold` +
   `queue.sh resume`; the 1-min `gpu_autoswap.sh` cron then auto-restores the 27B.

QA auto-rejects: solid card (no alpha), opaque-corner/edge bg residue, coverage
out of 0.05–0.75 band, feet halo, and — for dead/downed — a **standing** bbox
(taller than wide) instead of lying down.

## Prerequisites checklist (all verified 2026-09-02, static only)
- [x] venv python: `.../comfy/ComfyUI/.venv/bin/python`
- [x] SDXL base: `.../comfy/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors` (6.5G)
- [x] LoRA: `.../comfy/ComfyUI/models/loras/pixel-art-xl.safetensors` (163M)
- [x] `art_reference_briefs.json` (14 units; has corpse_by_family + downed_by_family)
- [x] all 5 scripts `py_compile` / `bash -n` clean
- [x] `gpu_autoswap.sh` respects `state/art_window.hold` (won't restart 27B mid-run)
- [ ] **VERIFY AT RUN TIME** (needs GPU, not checked in prep): SDXL/LoRA actually
      load in the venv; a gen produces a non-empty 1024 image; QA pass rates.

## Expected runtime
~30–60 min typical; hard ceiling ~80 min (2 roles × 40-min `timeout`). 14 units ×
up to 3 passes each; pixelize/QA are fast CPU steps.

## GPU coordination with the fleet
Single 3090 — art and the 27B fleet cannot coexist. The window holds the GPU via
`state/art_window.hold`; `gpu_autoswap.sh` (cron, 1 min) sees the hold and exits
without restarting the 27B, so no mid-run OOM. When the window exits, the hold is
removed and the watcher restores the 27B within ~1 min. If art dies uncleanly and
the hold is left behind, the fleet stays down — `rm ~/overnight-queue/state/art_window.hold`
and the watcher restores it.

## Review results afterward
- Log: `~/overnight-queue/reports/art-characters.out` (per-pass QA pass/fail; any
  unit "still failing after 3 passes" is flagged by name).
- Sprites: `.../comfy/out/units_dead_sprites3/*__dead@64.png` and
  `.../comfy/out/units_downed_sprites3/*__downed@64.png` (+ `*_preview.png` at 8x
  for eyeballing). Raw 1024s in `.../comfy/out/units_dead` and `units_downed`.
- Prior work + the interrupted 2026-09-02 partial were backed up to
  `.../comfy/out/_backup_precharacter_<ts>/` (14 dead raws, 84 dead sprites, 6
  partial downed raws) before this prep.

## Durable locations
- Runnable: `~/overnight-queue/art/` (self-contained; `/tmp/*` copies still work).
- Version-controlled mirror (Mac clone, WIP/untracked, not committed):
  `/Users/mhintermeister/LocalProjects/shared/scripts/overnight-queue/art/`.
