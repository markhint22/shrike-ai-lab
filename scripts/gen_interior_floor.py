#!/usr/bin/env python3
"""One new tile: interior floor for city-theme buildings. Live playtest:
"you can't have roads go through a building. tiles inside buildings need to
be like floors not outside tiles" - xlite's GridRenderer had no concept of
"inside a building" at all; every floor cell (even ones fully enclosed by
WALL cells) drew the same exterior street/sidewalk material. Paired with a
new flood-fill interior-detector on the game side, this is the texture that
detector routes enclosed cells to instead of street material.
"""
import os, sys, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_flux_final import process_tile  # noqa: E402

MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/flux1-schnell"
RAW_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/theme_terrain/raw"
GAME_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/theme_terrain/game_ready"

PROMPT = ("16-bit pixel art, blocky pixelated retro game texture, seamless top-down worn wooden "
          "plank interior floor, indoor building floor, wasteland ruin, NOT photorealistic, "
          "flat shading, hard pixel edges")


def _seed_for(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % 90000


def main():
    import torch
    from diffusers import FluxPipeline

    print("loading FLUX.1-schnell (CPU-offloaded)...", flush=True)
    pipe = FluxPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe.enable_model_cpu_offload()

    name = "floor_city_interior"
    g = torch.Generator("cpu").manual_seed(_seed_for(name))
    img = pipe(prompt=PROMPT, height=1024, width=1024, num_inference_steps=4,
                guidance_scale=0.0, max_sequence_length=256, generator=g).images[0]
    raw_path = f"{RAW_OUT}/{name}.png"
    img.save(raw_path)
    process_tile(raw_path, f"{GAME_OUT}/{name}.png")
    print("DONE", name, flush=True)


if __name__ == "__main__":
    main()
