# Image-Model A/B/C Evaluation (2026-09-11)

User asked to research newer specialist image-gen models (specifically
mentioned LLaDA-Image), download a few, and A/B test against the current
production pipeline (SDXL 1.0 + pixel-art-xl LoRA) on the SAME prompts.

## Candidates tested

- **SDXL 1.0 + pixel-art-xl LoRA** (baseline) — current production recipe.
- **Z-Image-Turbo** (Tongyi-MAI/Alibaba, 6B, Apache 2.0, ungated) — 9 steps.
- **LLaDA-Image-Turbo** (inclusionAI, 6B DiT + full VLM text encoder, Apache
  2.0) — the model specifically asked about. 4 steps.
- **FLUX.1-schnell** — considered, dropped: the official diffusers-format
  repo is gated (requires an HF account + click-through license we don't
  have credentials for); the only ungated mirrors are single merged
  checkpoints without the separate text-encoder/VAE components a full
  diffusers pipeline needs. Not worth assembling from scattered sources
  given Z-Image was already available ungated with comparable standing.

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
