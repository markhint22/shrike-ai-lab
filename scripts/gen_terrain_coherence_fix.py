#!/usr/bin/env python3
"""Two rounds of user feedback on the first terrain-theme pass, same root
cause both times: pieces meant to sit next to each other were independently
generated, so their patterns/brick-layouts/coloring don't actually align at
the boundary - "patchy" floor tiles, and building wall pieces that "look
like individual pieces... not together like one building."

Fix, applied to both floors AND walls: img2img at LOW strength (0.2) off a
SHARED base image per material, instead of independent fresh generations.
Low strength keeps the overall composition/pattern nearly frozen (same
grate/brick layout) and only perturbs surface detail - so any two variants
placed edge-to-edge read as continuations of the same material, not two
different materials stitched together.

Floors: wasteland floor_metal v2/v3 (off the shipped floor_metal.png),
city sidewalk v2/v3 (off sidewalk v1), city road v2/v3 (off road v1).
Walls: NEW - every non-window wall shape (straight_ns/ew, corner, end_cap,
isolated) collapses to a small pool of 3 mutually-consistent variants (the
existing straight_ns piece as v1, plus 2 img2img siblings) PER theme,
instead of 5 independently-generated shapes that never matched each other.
CoverObject picks from this pool the same way it already does for CRATE
props. WINDOW stays its own distinct (but already tonally close) piece -
it's supposed to look different, it has a hole in it.
"""
import os, hashlib, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_flux_final import process_tile, process_sprite  # noqa: E402

MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/flux1-schnell"
FLUX_FINAL_RAW = "/run/media/mhintermeister/secondary_drive1/comfy/out/flux_final/raw"
THEME_RAW = "/run/media/mhintermeister/secondary_drive1/comfy/out/theme_terrain/raw"
GAME_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/theme_terrain/game_ready"
STRENGTH = 0.2
STEPS = 8

# (base raw image to img2img FROM, output key, prompt, post-process kind)
JOBS = [
    (f"{FLUX_FINAL_RAW}/tile_floor_metal.png", "floor_wasteland_floor_metal_v2",
     "16-bit pixel art, blocky pixelated retro game texture, seamless top-down rusted riveted metal grate floor, extra grime and stains, wasteland ruin, NOT photorealistic, flat shading, hard pixel edges", "tile"),
    (f"{FLUX_FINAL_RAW}/tile_floor_metal.png", "floor_wasteland_floor_metal_v3",
     "16-bit pixel art, blocky pixelated retro game texture, seamless top-down rusted riveted metal grate floor, extra dark rust spots, wasteland ruin, NOT photorealistic, flat shading, hard pixel edges", "tile"),
    (f"{THEME_RAW}/floor_city_sidewalk_v1.png", "floor_city_sidewalk_v2",
     "16-bit pixel art, blocky pixelated retro game texture, seamless top-down light tan cracked concrete sidewalk texture, a bit more weeds and stains, wasteland ruin, NOT photorealistic, flat shading, hard pixel edges", "tile"),
    (f"{THEME_RAW}/floor_city_sidewalk_v1.png", "floor_city_sidewalk_v3",
     "16-bit pixel art, blocky pixelated retro game texture, seamless top-down light tan cracked concrete sidewalk texture, extra dark stains, wasteland ruin, NOT photorealistic, flat shading, hard pixel edges", "tile"),
    (f"{THEME_RAW}/floor_city_road_v1.png", "floor_city_road_v2",
     "16-bit pixel art, blocky pixelated retro game texture, seamless top-down dark asphalt road texture, faded lane markings, wasteland ruin, NOT photorealistic, flat shading, hard pixel edges", "tile"),
    (f"{THEME_RAW}/floor_city_road_v1.png", "floor_city_road_v3",
     "16-bit pixel art, blocky pixelated retro game texture, seamless top-down dark asphalt road texture, extra potholes and rubble, wasteland ruin, NOT photorealistic, flat shading, hard pixel edges", "tile"),
    (f"{THEME_RAW}/wall_wasteland_straight_ns.png", "wall_wasteland_pool_v2",
     "pixel art, a single straight building wall segment, standing upright, scavenged gray scrap metal patchwork wall, riveted plates, extra rust and dents, wasteland ruin, flat gray background", "sprite"),
    (f"{THEME_RAW}/wall_wasteland_straight_ns.png", "wall_wasteland_pool_v3",
     "pixel art, a single straight building wall segment, standing upright, scavenged gray scrap metal patchwork wall, riveted plates, extra scorch marks, wasteland ruin, flat gray background", "sprite"),
    (f"{THEME_RAW}/wall_city_straight_ns.png", "wall_city_pool_v2",
     "pixel art, a single straight building wall segment, standing upright, crumbling red-brown brick building wall, extra cracks and missing bricks, wasteland ruin, flat gray background", "sprite"),
    (f"{THEME_RAW}/wall_city_straight_ns.png", "wall_city_pool_v3",
     "pixel art, a single straight building wall segment, standing upright, crumbling red-brown brick building wall, extra soot stains, wasteland ruin, flat gray background", "sprite"),
]


def _seed_for(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % 90000


def main():
    import torch
    from diffusers import FluxImg2ImgPipeline
    from PIL import Image

    print("loading FLUX.1-schnell img2img (CPU-offloaded)...", flush=True)
    pipe = FluxImg2ImgPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe.enable_model_cpu_offload()

    for i, (base_path, out_key, prompt, kind) in enumerate(JOBS):
        init_image = Image.open(base_path).convert("RGB").resize((1024, 1024))
        g = torch.Generator("cpu").manual_seed(_seed_for(out_key))
        img = pipe(prompt=prompt, image=init_image, strength=STRENGTH,
                   num_inference_steps=STEPS, guidance_scale=0.0,
                   max_sequence_length=256, generator=g).images[0]
        raw_out = f"{THEME_RAW}/{out_key}.png"
        img.save(raw_out)
        out_path = f"{GAME_OUT}/{out_key}.png"
        if kind == "tile":
            process_tile(raw_out, out_path)
        else:
            process_sprite(raw_out, out_path)
        print(f"[{i + 1}/{len(JOBS)}] {out_key}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
