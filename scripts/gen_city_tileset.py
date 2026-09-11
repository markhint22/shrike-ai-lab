#!/usr/bin/env python3
"""The reusable ruined-city TILESET generator (v2) - see
docs/art/CITY_TILESET_SYSTEM.md for the full rationale. Two fundamentally
different techniques, applied to the right piece type:

  - WALLS + FLOOR TILES (road/sidewalk): generated with circular-padding
    conv layers (make_seamless) so the raw output tiles with ITSELF when
    repeated. Sliced into a grid of game-sized chunks that connect to their
    natural (wrapping) neighbor - see slice_grid()'s docstring for the
    critical usage rule (use chunks in their original sequence/position;
    shuffling them breaks the seam).
  - CORNERS / END-CAPS / WINDOWS / standalone PROPS: the "single bounded
    object on a gray background" recipe from the first city-props pass,
    which worked fine once separated from the (unrelated) tiling problem.
    These get floodkey-isolated by pixelize3.py afterward, same as before.

Usage:
  gen_city_tileset.py walls            # seamless wall tiles, all materials
  gen_city_tileset.py floors           # seamless road/sidewalk tiles
  gen_city_tileset.py chunks           # corner/end-cap/window bounded objects
  gen_city_tileset.py props            # fixed oil_drum/chainlink_fence
  gen_city_tileset.py                  # everything
"""
import os, sys, json, hashlib
from PIL import Image, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
BRIEF = json.load(open(os.path.join(HERE, "city_reference_briefs_v2.json")))
C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"
OUT_TILES = "/run/media/mhintermeister/secondary_drive1/comfy/out/city_tileset_v2/tiles"
OUT_CHUNKS = "/run/media/mhintermeister/secondary_drive1/comfy/out/city_tileset_v2/chunks"
PALETTE = 20


def _seed_for(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % 90000


def make_seamless(pipe, on):
    """Patch every Conv2d in the UNet+VAE to wrap (circular) instead of
    zero-pad, so the decoded image tiles with itself in both X and Y -
    validated 2026-09-10 via seamless_tile_test.py (3x3 self-tile, no visible
    seam on concrete/brick/rusted-metal). Toggle back off before generating
    any bounded single-object piece - circular padding on those would make
    SDXL want to fill the whole frame again (the original failure mode)."""
    mode = "circular" if on else "zeros"
    for target in (pipe.vae, pipe.unet):
        for module in target.modules():
            if isinstance(module, __import__("torch").nn.Conv2d):
                module.padding_mode = mode


def slice_grid(tile_img, cell_w, cell_h):
    """Slice a seamless tile into a grid of cell_w x cell_h chunks. CRITICAL
    usage rule: chunks connect seamlessly to their NATURAL neighbor in this
    grid (including wrapping from the last column/row back to the first,
    since the source was generated to tile with itself) - place them in a
    building/street in this same relative order. Do NOT shuffle chunks from
    different rows/materials next to each other; only sequence within one
    material's own grid, in order, wrapping as needed."""
    w, h = tile_img.size
    cols, rows = w // cell_w, h // cell_h
    return [[tile_img.crop((c * cell_w, r * cell_h, (c + 1) * cell_w, (r + 1) * cell_h))
             for c in range(cols)] for r in range(rows)]


def quant(im, w, h):
    small = im.convert("RGB").resize((w, h), Image.LANCZOS)
    small = ImageEnhance.Brightness(small).enhance(1.1)
    small = ImageEnhance.Color(small).enhance(1.08)
    return small.quantize(colors=PALETTE, method=Image.MEDIANCUT).convert("RGB")


def _pipe():
    import torch
    from diffusers import StableDiffusionXLPipeline
    print("loading SDXL + LoRA...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA)
    pipe.fuse_lora(lora_scale=1.2)
    pipe.set_progress_bar_config(disable=True)
    return pipe, torch


def gen_walls(pipe, torch):
    os.makedirs(OUT_TILES, exist_ok=True)
    make_seamless(pipe, True)
    neg = "blurry, jpeg artifacts, text, watermark, 3d render, photo, object, character, seam, border, frame"
    for mat in BRIEF["materials"]:
        key = mat["key"]
        prompt = f"pixel art, {mat['wall_prompt']}, seamless tileable texture, flat lighting"
        g = torch.Generator("cuda").manual_seed(_seed_for(f"wall_{key}"))
        img = pipe(prompt=prompt, negative_prompt=neg, num_inference_steps=32,
                   guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
        grid = slice_grid(img, 64, 64)
        row = grid[len(grid) // 2]  # one horizontal sequence, 16 connected segments
        for i, chunk in enumerate(row):
            quant(chunk, 64, 64).save(f"{OUT_TILES}/wall_{key}_seg{i:02d}.png")
        print(f"wall material done: {key} (16 segments)", flush=True)
    make_seamless(pipe, False)


def gen_floors(pipe, torch):
    os.makedirs(OUT_TILES, exist_ok=True)
    make_seamless(pipe, True)
    neg = "blurry, jpeg artifacts, text, watermark, 3d render, photo, object, character, seam, border, frame"
    for tile in BRIEF["floor_tiles"]:
        key = tile["key"]
        for v_idx, variant in enumerate(tile["variants"]):
            prompt = f"pixel art, {tile['seamless_prompt']}, {variant}, seamless tileable texture, flat lighting"
            g = torch.Generator("cuda").manual_seed(_seed_for(f"{key}_v{v_idx}"))
            img = pipe(prompt=prompt, negative_prompt=neg, num_inference_steps=32,
                       guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
            grid = slice_grid(img, 64, 32)  # game's real 2:1 floor-tile footprint
            for r in range(min(4, len(grid))):
                for c in range(min(4, len(grid[0]))):
                    quant(grid[r][c], 64, 32).save(f"{OUT_TILES}/{key}_v{v_idx}_r{r}c{c}.png")
        print(f"floor tile done: {key}", flush=True)
    make_seamless(pipe, False)


def _chunk_prompt(subject, material_words):
    prefix = BRIEF["chunk_common"]["prefix"]
    suffix = BRIEF["chunk_common"]["suffix"]
    return f"{prefix}, {subject}, {material_words}, {suffix}"


def gen_chunks(pipe, torch):
    os.makedirs(OUT_CHUNKS, exist_ok=True)
    base_neg = BRIEF["chunk_common"]["negatives"]
    for mat in BRIEF["materials"]:
        for shape in BRIEF["chunk_shapes"]:
            name_base = f"{shape['key']}_{mat['key']}"
            prompt = _chunk_prompt(shape["subject"], mat["chunk_material"])
            for seed_idx in range(2):
                name = f"{name_base}__s{seed_idx}"
                g = torch.Generator("cuda").manual_seed(_seed_for(name))
                img = pipe(prompt=prompt, negative_prompt=base_neg, num_inference_steps=32,
                           guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
                img.save(f"{OUT_CHUNKS}/{name}.png")
            print(f"chunk done: {name_base}", flush=True)


def gen_props(pipe, torch):
    os.makedirs(OUT_CHUNKS, exist_ok=True)
    for prop in BRIEF["fixed_props"]:
        key = prop["key"]
        neg = BRIEF["chunk_common"]["negatives"] + ", " + prop["extra_negatives"]
        for v_idx, variant in enumerate(prop["variants"]):
            prompt = f"{prop['subject']}, {variant}"
            for seed_idx in range(3):
                name = f"{key}__v{v_idx}__s{seed_idx}"
                g = torch.Generator("cuda").manual_seed(_seed_for(name))
                img = pipe(prompt=prompt, negative_prompt=neg, num_inference_steps=32,
                           guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
                img.save(f"{OUT_CHUNKS}/{name}.png")
        print(f"prop done: {key}", flush=True)


def main():
    targets = set(a for a in sys.argv[1:] if not a.startswith("--")) or {"walls", "floors", "chunks", "props"}
    pipe, torch = _pipe()
    if "walls" in targets:
        gen_walls(pipe, torch)
    if "floors" in targets:
        gen_floors(pipe, torch)
    if "chunks" in targets:
        gen_chunks(pipe, torch)
    if "props" in targets:
        gen_props(pipe, torch)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
