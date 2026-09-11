#!/usr/bin/env python3
"""Per-mission terrain THEME art (2026-09-11 follow-up to the FLUX 128px
bump): several coherent floor-tile variants per theme instead of the old
"checker two unrelated materials together" look, a second full CITY theme
(streets/sidewalks, brick buildings, burn barrels/car+bus wrecks), and real
per-shape wall art (STRAIGHT_NS/EW, CORNER, END_CAP, ISOLATED, WINDOW) for
both themes - wall_tiling.gd/CoverObject.RenderKind already classify every
obstacle cell into these shapes, this just supplies the art that classification
plan explicitly deferred ("Modular Ruined-City Terrain").

Reuses gen_flux_final.py's two proven post-process pipelines unchanged:
  - process_sprite: floodkey+autocrop+quant -> upright CoverObject art
    (walls, cover props).
  - process_tile: quantize+rotate45+squash -> the game's 128x64 iso floor
    footprint (must match IsoGrid.TILE_WIDTH/HEIGHT exactly).

Usage:
  gen_theme_terrain.py             # everything (23 items)
  gen_theme_terrain.py floors      # 8 floor variants (2 wasteland + 6 city)
  gen_theme_terrain.py walls       # 12 wall shapes (6 wasteland + 6 city)
  gen_theme_terrain.py props       # 3 city cover props
"""
import os, sys, json, hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_flux_final import process_sprite, process_tile  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BRIEF = json.load(open(os.path.join(HERE, "theme_terrain_briefs.json")))
MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/flux1-schnell"
RAW_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/theme_terrain/raw"
GAME_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/theme_terrain/game_ready"

STYLE_ANCHOR = "16-bit pixel art, blocky pixelated retro game texture, {}, NOT photorealistic, flat shading, hard pixel edges"


def _seed_for(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % 90000


def floor_items():
    items = []
    for theme_key, theme in BRIEF["themes"].items():
        for v in theme["floor_variants"]:
            items.append((f"floor_{theme_key}_{v['key']}", STYLE_ANCHOR.format(v["prompt"]), "tile"))
    return items


def wall_items():
    items = []
    for theme_key, theme in BRIEF["themes"].items():
        material = theme["wall_material"]
        for shape in BRIEF["wall_shapes"]:
            key = f"wall_{theme_key}_{shape['key']}"
            prompt = f"pixel art, {shape['subject']}, {material}, flat gray background"
            items.append((key, prompt, "sprite"))
    return items


def prop_items():
    items = []
    for theme_key, theme in BRIEF["themes"].items():
        for prop in theme.get("cover_props", []):
            key = f"prop_{theme_key}_{prop['key']}"
            prompt = f"pixel art, {prop['prompt']}, flat gray background"
            items.append((key, prompt, "sprite"))
    return items


def main():
    targets = set(a for a in sys.argv[1:] if not a.startswith("--")) or {"floors", "walls", "props"}
    items = []
    if "floors" in targets:
        items += floor_items()
    if "walls" in targets:
        items += wall_items()
    if "props" in targets:
        items += prop_items()

    os.makedirs(RAW_OUT, exist_ok=True)
    os.makedirs(GAME_OUT, exist_ok=True)
    print(f"{len(items)} items planned -> {RAW_OUT}", flush=True)

    import torch
    from diffusers import FluxPipeline
    print("loading FLUX.1-schnell (CPU-offloaded)...", flush=True)
    pipe = FluxPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe.enable_model_cpu_offload()

    for i, (name, prompt, kind) in enumerate(items):
        g = torch.Generator("cpu").manual_seed(_seed_for(name))
        img = pipe(prompt=prompt, height=1024, width=1024, num_inference_steps=4,
                    guidance_scale=0.0, max_sequence_length=256, generator=g).images[0]
        raw_path = f"{RAW_OUT}/{name}.png"
        img.save(raw_path)
        out_path = f"{GAME_OUT}/{name}.png"
        if kind == "tile":
            process_tile(raw_path, out_path)
        else:
            process_sprite(raw_path, out_path)
        print(f"[{i + 1}/{len(items)}] {name}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
