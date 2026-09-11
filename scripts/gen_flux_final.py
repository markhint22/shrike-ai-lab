#!/usr/bin/env python3
"""THE 128px production generator for xlite's LIVE game assets, switching
from Z-Image-Turbo to FLUX.1-schnell after empirical A/B/C/D testing showed
FLUX wins decisively once judged at the game's actual 128px sprite/tile
resolution (doubled from 64px/64x32 - see docs/art/MODEL_EVAL_2026-09-11.md's
64px-vs-128px finding for the full comparison).

This targets EXACTLY xlite's current live asset set - a resolution/model
upgrade, not a re-imagining. Same subjects/prompts as the currently-shipped
wasteland-themed art: art_reference_briefs.json for the 14 units (unchanged,
already proven with FLUX earlier this session), prompts curated from the
most recent wasteland-era batch (xlite_options_batch.py) for crate/terrain,
per the standing "keep the art style/theme consistent" instruction.

Two distinct post-process pipelines, matching how each asset actually renders
in-game (see xlite's grid_renderer.gd / cover_object.gd / unit.gd):
  - SPRITE items (14 units + crate): floodkey+autocrop+quant, matching
    pixelize3.py's sprite branch - CoverObject/Unit draw these as upright
    objects with alpha, scaled by a factor in the scene (any square size
    works after crop/pad).
  - TILE items (floor_metal/floor_tech/rubble/hazard): quant to a small
    square, then rotate 45deg + squash to the game's 2:1 iso footprint
    (128x64, doubled from the old 64x32) - matches iso_tiles.py's proven
    technique. grid_renderer.gd draws these via draw_texture() at NATIVE
    resolution (no scale factor) - getting this exact pixel size right is a
    hard correctness requirement, not cosmetic polish.

Usage:
  gen_flux_final.py            # everything (19 items)
  gen_flux_final.py sprites    # 14 units + crate only
  gen_flux_final.py tiles      # 4 iso floor/hazard/rubble tiles only
"""
import os, sys, json, hashlib
from PIL import Image, ImageEnhance, ImageDraw
# numpy/torch/diffusers imported lazily so item lists stay importable/testable
# without the ML stack (matches gen_zimage_final.py's convention).

HERE = os.path.dirname(os.path.abspath(__file__))
UNITS_BRIEF = json.load(open(os.path.join(HERE, "art_reference_briefs.json")))
MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/flux1-schnell"
RAW_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/flux_final/raw"
GAME_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/flux_final/game_ready"
PALETTE = 20
GRID = 128         # doubled from pixelize3.py's old 64 - the new sprite/crate pixel scale
TILE_W, TILE_H = 128, 64  # doubled from IsoGrid's old 64x32, must match iso_grid.gd exactly

# Curated from xlite_options_batch.py (the freshest wasteland-era batch, prompt
# style matching art_reference_briefs.json's units) with floor_tech backfilled
# from the earlier xlite_vibrant_batch.py (no wasteland-era update exists for
# it) - same subjects as what's currently shipped, not a redesign.
TILE_PROMPTS = [
    ("floor_metal", "seamless top-down rusted riveted metal grate floor, wasteland ruin"),
    ("floor_tech", "seamless top-down glowing tech circuit floor tile, wasteland ruin, advanced salvaged technology"),
    ("rubble", "seamless top-down scattered concrete rubble and debris flat on the ground, wasteland ruin"),
    ("hazard", "seamless top-down toxic radioactive sludge pool floor, wasteland ruin, danger"),
]
CRATE_KEY = "crate"
CRATE_PROMPT = "a single worn wooden supply crate, a slatted wooden box with metal corners, low, cover object"


def _seed_for(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % 90000


def _strip_article(s):
    for a in ("a ", "an ", "the "):
        if s.lower().startswith(a):
            return s[len(a):]
    return s


def sprite_items():
    items = []
    for key, u in UNITS_BRIEF["units"].items():
        feats = ", ".join(u.get("key_features", [])[:2])
        prompt = f"pixel art, {_strip_article(u['subject'])}, {feats}, full body centered, flat gray background"
        items.append((f"sprite_{key}", prompt))
    items.append((f"sprite_{CRATE_KEY}", f"pixel art, {CRATE_PROMPT}, flat gray background"))
    return items


def tile_items():
    return [(f"tile_{key}", f"16-bit pixel art, blocky pixelated retro game texture, {prompt}, "
                             f"NOT photorealistic, flat shading, hard pixel edges")
            for key, prompt in TILE_PROMPTS]


# ---- post-processing (mirrors pixelize3.py's sprite branch + iso_tiles.py's rotate-squash) ----

def floodkey(im, tol=70, pocket_tol=30):
    import numpy as np
    rgb = im.convert("RGB")
    W, H = rgb.size
    orig = np.array(rgb).astype(int)
    corners = orig[[0, 0, H - 1, H - 1], [0, W - 1, 0, W - 1]]
    bg = corners.mean(axis=0)
    SENT = (255, 0, 255)
    for corner in ((0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)):
        try:
            ImageDraw.floodfill(rgb, corner, SENT, thresh=tol)
        except Exception:
            pass
    arr = np.array(rgb)
    connected = (arr[:, :, 0] == 255) & (arr[:, :, 1] == 0) & (arr[:, :, 2] == 255)
    pockets = np.abs(orig - bg).sum(axis=2) < pocket_tol
    out = np.array(im.convert("RGBA"))
    out[connected | pockets] = (0, 0, 0, 0)
    ys, xs = np.where(out[:, :, 3] > 8)
    if len(ys):
        top, bot = int(ys.min()), int(ys.max())
        band_y = top + int((bot - top) * 0.85)
        rgb2 = out[:, :, :3].astype(int)
        sat = rgb2.max(axis=2) - rgb2.min(axis=2)
        val = rgb2.max(axis=2)
        yy = np.arange(out.shape[0])[:, None]
        shadow = (sat < 26) & (val > 45) & (val < 200) & (yy >= band_y) & (out[:, :, 3] > 8)
        out[shadow] = (0, 0, 0, 0)
    return Image.fromarray(out, "RGBA")


def autocrop_square(im):
    bb = im.split()[-1].getbbox()
    if bb:
        x0, y0, x1, y1 = bb
        pad = max(4, (x1 - x0) // 20)
        im = im.crop((max(0, x0 - pad), max(0, y0 - pad), min(im.size[0], x1 + pad), min(im.size[1], y1 + pad)))
    w, h = im.size
    s = max(w, h)
    c = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c.paste(im, ((s - w) // 2, (s - h) // 2))
    return c


def quant_sprite(im, grid):
    small = im.resize((grid, grid), Image.LANCZOS)
    rgb = small.convert("RGB")
    rgb = ImageEnhance.Brightness(rgb).enhance(1.14)
    rgb = ImageEnhance.Color(rgb).enhance(1.08)
    rgb = rgb.quantize(colors=PALETTE, method=Image.MEDIANCUT).convert("RGBA")
    rgb.putalpha(small.split()[-1] if small.mode == "RGBA" else Image.new("L", (grid, grid), 255))
    return rgb


def process_sprite(raw_path, out_path, grid=GRID):
    im = Image.open(raw_path).convert("RGBA")
    base = autocrop_square(floodkey(im))
    sp = quant_sprite(base, grid)
    sp.save(out_path)
    sp.resize((grid * 3, grid * 3), Image.NEAREST).save(out_path.replace(".png", "_preview.png"))


def process_tile(raw_path, out_path, tw=TILE_W, th=TILE_H):
    """Square seamless-ish texture -> quantize -> rotate 45deg -> squash to
    the game's 2:1 iso footprint. Matches iso_tiles.py's proven technique,
    just parameterized for the new (doubled) tile size."""
    im = Image.open(raw_path).convert("RGBA")
    s = round(tw / (2 ** 0.5))  # pre-rotation square size so the diagonal ~= tw
    small = im.resize((s, s), Image.LANCZOS)
    rgb = small.convert("RGB")
    rgb = ImageEnhance.Brightness(rgb).enhance(1.1)
    rgb = ImageEnhance.Color(rgb).enhance(1.08)
    rgb = rgb.quantize(colors=PALETTE, method=Image.MEDIANCUT).convert("RGBA")
    rot = rgb.rotate(45, expand=True, resample=Image.BICUBIC)
    iso = rot.resize((tw, th), Image.LANCZOS)
    iso.save(out_path)
    iso.resize((tw * 4, th * 4), Image.NEAREST).save(out_path.replace(".png", "_preview.png"))


def main():
    targets = set(a for a in sys.argv[1:] if not a.startswith("--")) or {"sprites", "tiles"}
    items = []
    if "sprites" in targets:
        items += sprite_items()
    if "tiles" in targets:
        items += tile_items()

    os.makedirs(RAW_OUT, exist_ok=True)
    os.makedirs(GAME_OUT, exist_ok=True)
    print(f"{len(items)} items planned -> {RAW_OUT}", flush=True)

    import torch
    from diffusers import FluxPipeline
    print("loading FLUX.1-schnell (CPU-offloaded)...", flush=True)
    pipe = FluxPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe.enable_model_cpu_offload()

    for i, (name, prompt) in enumerate(items):
        g = torch.Generator("cpu").manual_seed(_seed_for(name))
        img = pipe(prompt=prompt, height=1024, width=1024, num_inference_steps=4,
                    guidance_scale=0.0, max_sequence_length=256, generator=g).images[0]
        raw_path = f"{RAW_OUT}/{name}.png"
        img.save(raw_path)
        out_path = f"{GAME_OUT}/{name}.png"
        if name.startswith("tile_"):
            process_tile(raw_path, out_path)
        else:
            process_sprite(raw_path, out_path)
        print(f"[{i + 1}/{len(items)}] {name}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
