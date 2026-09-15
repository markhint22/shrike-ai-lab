#!/usr/bin/env python3
"""Deep-dive test: can FLUX.1-schnell's img2img mode produce distinct,
CONSISTENT walk/attack/hit pose frames off an existing idle sprite? This is
the alternative to xlite's current pure-engine-motion approach (slide/bob/
flash/tip-over, no baked pose frames at all - see unit.gd's _FRAMES comment).

img2img denoises FROM the existing idle image instead of generating fresh
from text, which is the standard technique for keeping a character's
identity (colors/gear/proportions) stable across pose variants - text-only
generation has no persistent identity between calls. `strength` controls the
trade-off directly: low strength = stays close to the source (safe but
barely changes pose), high strength = more freedom to actually strike a new
pose (but drifts further from the original character). Testing multiple
strengths across 2 units to see where (if anywhere) a usable middle ground
is, and multiple seeds per setting to see the run-to-run variance instead of
judging off a single lucky/unlucky draw.
"""
import os, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/flux1-schnell"
SRC_DIR = "/run/media/mhintermeister/secondary_drive1/comfy/out/flux_final/raw"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/flux_img2img_poses"

UNITS = ["sprite_player_trooper", "sprite_enemy_grunt"]
POSES = [
    ("walk", "mid-stride walking pose, one leg forward, dynamic action pose"),
    ("attack", "aggressive attacking lunge pose, weapon raised and thrust forward"),
    ("hit", "recoiling flinching hurt pose, staggering backward"),
]
STRENGTHS = [0.35, 0.55, 0.75]
SEEDS = [1, 2]


def _seed_for(name, seed):
    return int(hashlib.sha1(f"{name}_{seed}".encode()).hexdigest(), 16) % 90000


def main():
    import torch
    from diffusers import FluxImg2ImgPipeline
    from PIL import Image

    os.makedirs(OUT, exist_ok=True)
    print("loading FLUX.1-schnell img2img (CPU-offloaded)...", flush=True)
    pipe = FluxImg2ImgPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe.enable_model_cpu_offload()

    n = 0
    total = len(UNITS) * len(POSES) * len(STRENGTHS) * len(SEEDS)
    for unit in UNITS:
        src_path = f"{SRC_DIR}/{unit}.png"
        init_image = Image.open(src_path).convert("RGB").resize((1024, 1024))
        for pose_key, pose_prompt in POSES:
            for strength in STRENGTHS:
                for seed in SEEDS:
                    name = f"{unit}__{pose_key}__s{strength}__seed{seed}"
                    g = torch.Generator("cpu").manual_seed(_seed_for(name, seed))
                    # num_inference_steps=8 (not schnell's usual 4) so that
                    # steps*strength clears diffusers' >=1 effective-step floor
                    # even at the lowest strength tested (0.35 * 8 = 2.8).
                    img = pipe(
                        prompt=f"pixel art, {pose_prompt}, full body, flat gray background",
                        image=init_image,
                        strength=strength,
                        num_inference_steps=8,
                        guidance_scale=0.0,
                        max_sequence_length=256,
                        generator=g,
                    ).images[0]
                    img.save(f"{OUT}/{name}.png")
                    n += 1
                    print(f"[{n}/{total}] {name}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
