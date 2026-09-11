# Image-Model A/B/C Evaluation (2026-09-11)

User asked to research newer specialist image-gen models (specifically
mentioned LLaDA-Image), download a few, and A/B test against the current
production pipeline (SDXL 1.0 + pixel-art-xl LoRA) on the SAME prompts.

## Candidates tested

- **SDXL 1.0 + pixel-art-xl LoRA** (baseline) — current production recipe.
- **Z-Image-Turbo** (Tongyi-MAI/Alibaba, 6B, Apache 2.0, ungated) — 9 steps.
- **LLaDA-Image-Turbo** (inclusionAI, 6B DiT + full VLM text encoder, Apache
  2.0) — the model specifically asked about. 4 steps.
- **FLUX.1-schnell** (Black Forest Labs, 12B, Apache 2.0) — initially
  dropped for the reason below, then re-tested after the user supplied a
  personal HF token and clicked through the model's license gate. See
  "FLUX.1-schnell: re-tested" below for the full result.

## Result: Z-Image-Turbo wins, now the production model

Same prompt set (2 character sprites, 3 terrain/object pieces), same seed,
each model's own recommended steps/guidance (forcing one model's settings on
another isn't a fair test):

- **Sprites**: Z-Image produced a single, clean, correctly-proportioned
  character on the first try. SDXL+LoRA produced a multi-pose "sprite sheet"
  grid for the identical prompt — needs the tighter, more specific framing
  already used in the real `art_reference_briefs.json` prompts to avoid that,
  which Z-Image didn't need.
- **Objects** (wrecked car): Z-Image nailed the isometric 3/4 box angle this
  session spent real effort chasing for the city-props batch — better
  results, less prompt engineering.
- **Terrain/textures**: first attempt, Z-Image drifted into a realistic/
  photographic style despite "pixel art" in the prompt (no pixel-art LoRA
  exists for it yet, unlike SDXL). Fixed with a stronger style-anchor:
  `"16-bit pixel art, blocky pixelated retro game texture, ..., NOT
  photorealistic, flat shading, hard pixel edges"` — confirmed clean on
  re-test, this formula is now baked into `gen_zimage_final.py`.
- **Speed**: 9 steps vs 32 — faster per image on top of the quality win.

## LLaDA-Image-Turbo: not adopted, real compatibility bugs (documented, not dismissed)

Given 3 genuine attempts since it's the model the user asked about by name:

1. `from_pretrained(..., device="cuda")` — **CUDA OOM** before generation
   started. Its text encoder is a full diffusion-language-model (LLaDA2.0-Mini
   backbone), not a small CLIP-style encoder — the combined pipeline exceeds
   24GB loaded all at once, even before the 6B image transformer loads.
2. Added `pipe.enable_model_cpu_offload()` (the pipeline already declares
   `model_cpu_offload_seq`, just wasn't being used) — loading succeeded, but
   crashed: `ValueError: Cannot generate a cpu tensor from a generator of
   type cuda` (the offloaded pipeline expects a CPU generator).
3. Switched to a CPU generator — crashed differently: `RuntimeError:
   Expected all tensors to be on the same device, but found at least two
   devices, cuda:0 and cpu!`, inside the scheduler's own `step()` math.

Three attempts, three distinct device-placement bugs. This reads as the
custom pipeline code (released 2026-09-04, one week before this eval) not
yet hardened against CPU offloading, not a quick fix. Worth revisiting once
the repo matures, or on hardware with enough VRAM (~32-40GB+, unconfirmed)
to skip offloading entirely.

## FLUX.1-schnell: re-tested, doesn't change the verdict

Originally skipped because the official diffusers-format repo is gated
(requires an HF account + license click-through) and the only ungated
mirrors are single merged checkpoints missing the separate text-encoder/VAE
components a full diffusers pipeline needs. The user supplied a personal HF
token and, after a 403 `GatedRepoError` (valid token, but the account hadn't
yet clicked "Agree and access repository" on the model page — a real human
step, not something fixable from the server side), accepted the license and
the download proceeded.

Ran the identical 5-prompt set at FLUX's own recommended settings (4 steps,
guidance 0.0, CPU-offloaded — the 12B transformer + T5-XXL text encoder
together exceed the 24GB card in bf16, `enable_model_cpu_offload()` plus a
CPU-device generator, both required together or you get a device-mismatch
error).

**Result: best raw 1024px quality of any candidate tested, but that doesn't
matter here.** FLUX's sprites and terrain were visibly richer/more detailed
than Z-Image's on identical prompts. But downscaled through the same
`pixelize3.py` pipeline to the game's actual 64x64 sprite resolution, that
extra detail turns into mush — fine features that read cleanly at 1024px
collapse into noise once resized down. Z-Image's simpler, bolder shapes stay
legible at 64px. This was only caught by checking the `@64_preview.png`
output specifically, not the raw generation — judging by the final target
resolution, not the generator's native resolution, is the right way to
evaluate any of these models for pixel-art sprite work.

Two smaller gaps: the wrecked-car prompt (verbatim identical to the one
Z-Image rendered in the needed isometric 3/4 box angle) came out in a flat
side profile instead — likely fixable with more angle-prompting, but Z-Image
didn't need any. And FLUX's cleaner/more uniform texture corners have lower
corner-color variance than Z-Image's, which tripped `pixelize3.py`'s
tile-vs-sprite classifier (`spread > 45` heuristic) into floodkey-treating
wall/road textures as sprites instead of leaving them opaque as tiles — a
fixable classifier/filename issue, not a model-quality problem, but one more
integration cost Z-Image doesn't impose.

**Verdict unchanged at 64px: Z-Image-Turbo stays the production model** —
Not because FLUX is worse in absolute terms — it's a stronger raw image
model — but because the game ships sprites at 64px and that's the
resolution that actually matters.

## Follow-up (same day): the resolution itself changed, and so did the winner

The user asked directly: if xlite's sprite/tile resolution were doubled to
make room for FLUX's extra detail, would FLUX become the right call? Rather
than guess, ran the actual FLUX output through the real `pixelize3.py`
pipeline at 64/96/128px side by side with Z-Image. Z-Image still wins at
64px, but **at 128px FLUX clearly wins** — the extra detail finally has room
to resolve instead of turning to mush.

That's a bigger decision than swapping models: xlite's `IsoGrid.TILE_WIDTH/
HEIGHT` (64x32) is load-bearing everywhere (camera zoom bounds, cover-object
anchoring, health-bar/damage-text offsets, hazard/door decals, ~15 unit test
assertions). User signed off on the full undertaking - doubled the tile
footprint to 128x64, rescaled every dependent constant, regenerated all 19
live game assets with FLUX.1-schnell at the new resolution, verified via the
full GUT suite (2177 tests, green) plus an in-engine screenshot. Shipped to
`xlite` (`claude/feature`, commit `0194431`).

Two real integration wrinkles found and handled, not glossed over:

- **FLUX's transformer backbone (FluxTransformer2DModel) has zero Conv2d
  layers** - the standard "patch every Conv2d to circular padding" seamless-
  tiling trick (works because SDXL/Z-Image's UNet backbones ARE built from
  Conv2d) has no unet to patch. Patching only the VAE's 62 Conv2d layers
  (decode-only, single pass) turned out to be enough anyway - confirmed via
  a 3x3 self-tile test, only a barely-visible hairline at the seam, not a
  real one. Worth knowing this isn't guaranteed to generalize to every
  transformer-based image model, but it worked here.
- `pixelize3.py`'s tile-vs-sprite classifier (`spread > 45`, corner-color
  variance) mis-fires on FLUX's cleaner/more-uniform texture corners for
  standalone terrain tests - not hit in the final production run since
  xlite's 4 iso tiles go through a dedicated rotate+squash pipeline
  (`gen_flux_final.py`), not `pixelize3.py`'s sprite/tile auto-classification,
  but worth flagging if `pixelize3.py` is pointed at FLUX terrain again.

See `docs/art/CITY_TILESET_SYSTEM.md` and the (separate, not-yet-shipped)
"Modular Ruined-City Terrain" plan for the walls/chunks/corners system this
did NOT touch - that's a different, larger piece generated a different way,
out of scope for this pass.

## Files (this follow-up)

- `scripts/eval_flux_schnell.py`, `scripts/flux_eval_window.sh` - the initial
  A/B/C/D candidate eval (64px verdict).
- `scripts/gen_flux_final.py` - **the new production generator** for xlite's
  live asset set at 128px (14 unit sprites + cover crate via floodkey/
  autocrop/quant, matching `pixelize3.py`'s sprite branch; 4 iso floor/hazard/
  rubble tiles via quantize + rotate-45 + squash to 128x64, matching
  `iso_tiles.py`'s technique). Run via a trap-safe GPU window, same
  pause-queue/free-GPU/restore-on-EXIT pattern as every other art window
  this session.

## Files

- `scripts/model_eval_prompts.py` — the shared fair-comparison prompt set.
- `scripts/eval_sdxl_baseline.py`, `eval_zimage.py`, `eval_llada_image.py` —
  one script per candidate, each using that model's own recommended settings.
- `scripts/eval_zimage_terrain_retest.py` — the terrain-style-drift fix test.
- `scripts/model_eval_window.sh` — trap-safe GPU window running all of the
  above in one pass (same pause-queue/free-GPU/restore-on-EXIT pattern as
  the art-generation windows).
- `scripts/gen_zimage_final.py` + `zimage_final_window.sh` — **the new
  production generator**: reuses the existing, already-researched brief
  files (`art_reference_briefs.json` for units, `city_reference_briefs_v2.json`
  for materials/props) with Z-Image-Turbo and the validated terrain formula.
  This is what to run for future sprite/terrain batches going forward.

## Setup notes (for reproducing/extending)

Isolated venvs per model (avoid touching the working ComfyUI venv):
`models_eval/.venv` (Z-Image — needs `diffusers` installed from git source,
not yet in a pip release as of 2026-09) and `models_eval/.venv-llada`
(LLaDA — pinned `torch==2.8.0`, `diffusers==0.39.0`, `transformers==4.57.6`
per its own `requirements.txt`, incompatible with Z-Image's newer stack).
Weights under `models_eval/{z-image-turbo,llada-image-turbo}/` (~77GB
combined) and the LLaDA inference code under `models_eval/LLaDA-Image-repo/`
(cloned from `github.com/inclusionAI/LLaDA-Image` — its pipeline isn't a
plain `trust_remote_code` HF pipeline, it needs this repo's `src/` on
`PYTHONPATH`).
