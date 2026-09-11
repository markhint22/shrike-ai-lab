#!/usr/bin/env python3
"""Real fix for "if it's a piece of wall it should take up the whole tile so
it touches the wall next to it" - CoverObject draws one flat rectangular
sprite per WALL cell; adjacent cells only look like a continuous wall if
each sprite's OPAQUE CONTENT spans the full tile width edge-to-edge. The
first wall art was prompted/floodkeyed like a standalone object (a "ruined
chunk" with an organic, tapered silhouette and a rubble pile at the base),
so autocrop_square cropped tight to that irregular shape - narrower than the
tile - leaving visible gaps (background showing through) between neighbors,
both at the sides and along the base.

This is a well-known tile-art principle (same one governing autotile sets in
general - see redblobgames.com/articles/autotile): a modular tile's
SILHOUETTE must be a clean shape that tiles cleanly (here: a full-width
rectangle); damage/wear belongs in the TEXTURE (cracks, missing bricks,
stains), never the outer shape. A first attempt to just reprompt for this
was not trusted blindly - process_wall_panel() below is a deterministic
safety net: it floodkeys only the SKY above the wall (vertical extent from
real content), then forces full canvas WIDTH regardless of what the
generation actually drew, and as a last-resort guarantee, clamp-extends the
leftmost/rightmost opaque columns outward to eliminate any residual edge gap
- so the output is guaranteed edge-to-edge even if the generation itself
isn't perfect.
"""
import os, hashlib
import numpy as np
from PIL import Image, ImageEnhance, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/flux1-schnell"
RAW_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/theme_terrain/raw"
GAME_OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/theme_terrain/game_ready"
GRID = 128
PALETTE = 20

PROMPTS = {
    "wall_wasteland_straight_ns": (
        "pixel art, a rectangular exterior wall panel filling the entire frame edge to edge, "
        "extending all the way to the left and right borders, straight flat vertical sides, "
        "scavenged gray scrap metal patchwork wall, riveted plates, rust and dents, wasteland ruin, "
        "flat gray background above the wall only"
    ),
    "wall_city_straight_ns": (
        "pixel art, a rectangular exterior wall panel filling the entire frame edge to edge, "
        "extending all the way to the left and right borders, straight flat vertical sides, "
        "crumbling red-brown brick building wall, wasteland ruin, "
        "flat gray background above the wall only"
    ),
}


def _seed_for(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % 90000


def floodkey_sky_only(im, tol=70):
    """Same corner-flood-fill technique as gen_flux_final.floodkey, but does
    NOT also key 'flat-bg pockets' between limbs (that pass is for character
    sprites with gaps between arms/legs; a wall panel has no such gaps, and
    running it risked eating into flat-colored wall texture)."""
    rgb = im.convert("RGB")
    W, H = rgb.size
    SENT = (255, 0, 255)
    for corner in ((0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)):
        try:
            ImageDraw.floodfill(rgb, corner, SENT, thresh=tol)
        except Exception:
            pass
    arr = np.array(rgb)
    connected = (arr[:, :, 0] == 255) & (arr[:, :, 1] == 0) & (arr[:, :, 2] == 255)
    out = np.array(im.convert("RGBA"))
    out[connected] = (0, 0, 0, 0)
    return Image.fromarray(out, "RGBA")


def process_wall_panel(raw_path, out_path):
    im = Image.open(raw_path).convert("RGBA")
    keyed = floodkey_sky_only(im)
    arr = np.array(keyed)
    alpha = arr[:, :, 3]
    W, H = keyed.size

    # Vertical extent from real content (ignore width - always keep full W).
    rows_with_content = np.where(alpha.max(axis=1) > 8)[0]
    if len(rows_with_content) == 0:
        top, bot = 0, H - 1
    else:
        top, bot = int(rows_with_content.min()), int(rows_with_content.max())
    pad = max(4, (bot - top) // 20)
    top = max(0, top - pad)
    bot = min(H - 1, bot + pad)

    band = arr[top:bot + 1, :, :].copy()

    # Safety net: clamp-extend the leftmost/rightmost columns that actually
    # have opaque content outward to the canvas edges, so the panel is
    # GUARANTEED full-width even if the generation left a sliver of
    # background at the very edges.
    band_alpha = band[:, :, 3]
    cols_with_content = np.where(band_alpha.max(axis=0) > 8)[0]
    if len(cols_with_content) > 0:
        left_col, right_col = int(cols_with_content.min()), int(cols_with_content.max())
        if left_col > 0:
            band[:, :left_col, :] = band[:, left_col:left_col + 1, :]
        if right_col < W - 1:
            band[:, right_col + 1:, :] = band[:, right_col:right_col + 1, :]
    band[:, :, 3] = 255  # the whole width is now the wall's opaque body

    full_width = Image.fromarray(band, "RGBA")
    # Pad to square (height typically < width after the vertical-only crop)
    w, h = full_width.size
    s = max(w, h)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    canvas.paste(full_width, (0, s - h))  # bottom-anchored, matching a wall standing on the ground
    small = canvas.resize((GRID, GRID), Image.LANCZOS)
    rgb = small.convert("RGB")
    rgb = ImageEnhance.Brightness(rgb).enhance(1.1)
    rgb = ImageEnhance.Color(rgb).enhance(1.08)
    rgb = rgb.quantize(colors=PALETTE, method=Image.MEDIANCUT).convert("RGBA")
    rgb.putalpha(small.split()[-1])
    rgb.save(out_path)
    rgb.resize((GRID * 3, GRID * 3), Image.NEAREST).save(out_path.replace(".png", "_preview.png"))


# img2img siblings off each fresh full-width base - same low-strength
# "wear variant, not a different generation" technique as the earlier
# coherence fix, now layered on TOP of a base that's actually full-width.
POOL_VARIANT_PROMPTS = {
    "wasteland": [
        ("wall_wasteland_pool_v2", "pixel art, a rectangular exterior wall panel filling the entire frame edge to edge, scavenged gray scrap metal patchwork wall, extra rust and dents, wasteland ruin, flat gray background above only"),
        ("wall_wasteland_pool_v3", "pixel art, a rectangular exterior wall panel filling the entire frame edge to edge, scavenged gray scrap metal patchwork wall, extra scorch marks, wasteland ruin, flat gray background above only"),
    ],
    "city": [
        ("wall_city_pool_v2", "pixel art, a rectangular exterior wall panel filling the entire frame edge to edge, crumbling red-brown brick building wall, extra cracks and missing bricks, wasteland ruin, flat gray background above only"),
        ("wall_city_pool_v3", "pixel art, a rectangular exterior wall panel filling the entire frame edge to edge, crumbling red-brown brick building wall, extra soot stains, wasteland ruin, flat gray background above only"),
    ],
}
WINDOW_PROMPTS = {
    "wasteland": ("wall_wasteland_window", "pixel art, a rectangular exterior wall panel filling the entire frame edge to edge, scavenged gray scrap metal patchwork wall, with a square window hole cut through the middle, wasteland ruin, flat gray background above only"),
    "city": ("wall_city_window", "pixel art, a rectangular exterior wall panel filling the entire frame edge to edge, crumbling red-brown brick building wall, with a square window hole cut through the middle, wasteland ruin, flat gray background above only"),
}
STRENGTH = 0.25
STEPS = 8


def main():
    import torch
    from diffusers import FluxPipeline, FluxImg2ImgPipeline

    print("loading FLUX.1-schnell (CPU-offloaded)...", flush=True)
    pipe = FluxPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe.enable_model_cpu_offload()

    base_raw = {}
    for name, prompt in PROMPTS.items():
        g = torch.Generator("cpu").manual_seed(_seed_for(name + "_fullwidth"))
        img = pipe(prompt=prompt, height=1024, width=1024, num_inference_steps=4,
                    guidance_scale=0.0, max_sequence_length=256, generator=g).images[0]
        raw_path = f"{RAW_OUT}/{name}.png"
        img.save(raw_path)
        base_raw[name] = raw_path
        process_wall_panel(raw_path, f"{GAME_OUT}/{name}.png")
        print("DONE base", name, flush=True)

    del pipe
    import gc
    gc.collect()
    torch.cuda.empty_cache() if torch.cuda.is_available() else None

    print("loading FLUX.1-schnell img2img (CPU-offloaded)...", flush=True)
    pipe2 = FluxImg2ImgPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe2.enable_model_cpu_offload()

    for theme, base_name in (("wasteland", "wall_wasteland_straight_ns"), ("city", "wall_city_straight_ns")):
        init_image = Image.open(base_raw[base_name]).convert("RGB").resize((1024, 1024))
        for name, prompt in POOL_VARIANT_PROMPTS[theme]:
            g = torch.Generator("cpu").manual_seed(_seed_for(name + "_fullwidth"))
            img = pipe2(prompt=prompt, image=init_image, strength=STRENGTH, num_inference_steps=STEPS,
                        guidance_scale=0.0, max_sequence_length=256, generator=g).images[0]
            raw_path = f"{RAW_OUT}/{name}.png"
            img.save(raw_path)
            process_wall_panel(raw_path, f"{GAME_OUT}/{name}.png")
            print("DONE variant", name, flush=True)
        win_name, win_prompt = WINDOW_PROMPTS[theme]
        g = torch.Generator("cpu").manual_seed(_seed_for(win_name + "_fullwidth"))
        img = pipe2(prompt=win_prompt, image=init_image, strength=0.45, num_inference_steps=STEPS,
                    guidance_scale=0.0, max_sequence_length=256, generator=g).images[0]
        raw_path = f"{RAW_OUT}/{win_name}.png"
        img.save(raw_path)
        process_wall_panel(raw_path, f"{GAME_OUT}/{win_name}.png")
        print("DONE window", win_name, flush=True)

    print("ALL_DONE", flush=True)


if __name__ == "__main__":
    main()
