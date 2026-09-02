#!/usr/bin/env python3
"""Normalize the idle base set so EVERY unit's idle is the same scale, centering and
background. Everything (IP-Adapter reference, img2img init, LoRA training data) derives
from the idle, so an inconsistent idle (e.g. the grunt rendered small on a lighter bg)
poisons every downstream pose. This autocrops each idle to the character, rescales it
to a uniform character height, and centers it on ONE fixed gray canvas.

in:  out/units_ns/<key>__idle.png   (raw 1024 gray-bg SDXL renders)
out: out/units_norm/<key>__idle.png (uniform 1024, character ~78% tall, same gray)
"""
import os, glob, sys
import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/run/media/mhintermeister/secondary_drive1/comfy/out/units_ns"
DST = sys.argv[2] if len(sys.argv) > 2 else "/run/media/mhintermeister/secondary_drive1/comfy/out/units_norm"
os.makedirs(DST, exist_ok=True)
CANVAS = 1024
TARGET_H = int(CANVAS * 0.78)   # character height as a fraction of the canvas
BG = (128, 128, 128)            # the ONE gray every idle sits on

def char_bbox(im):
    """Bbox of the character = pixels that differ from the (corner-sampled) background."""
    a = np.asarray(im.convert("RGB")).astype(int)
    k = max(8, im.width // 16)
    corners = np.concatenate([a[:k, :k], a[:k, -k:], a[-k:, :k], a[-k:, -k:]]).reshape(-1, 3)
    bg = np.median(corners, axis=0)
    diff = np.abs(a - bg).sum(2)
    mask = diff > 40
    ys, xs = np.where(mask)
    if len(ys) < 50:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1

def main():
    files = sorted(glob.glob(f"{SRC}/*__idle.png"))
    print(f"{len(files)} idles -> {DST}", flush=True)
    for f in files:
        im = Image.open(f).convert("RGB")
        bb = char_bbox(im)
        canvas = Image.new("RGB", (CANVAS, CANVAS), BG)
        if bb is None:
            canvas.paste(im.resize((CANVAS, CANVAS)), (0, 0))
        else:
            crop = im.crop(bb)
            scale = TARGET_H / crop.height
            nw, nh = max(1, int(crop.width * scale)), TARGET_H
            crop = crop.resize((nw, nh), Image.LANCZOS)
            # paste centered horizontally, feet near the bottom (grounded)
            x = (CANVAS - nw) // 2
            y = CANVAS - nh - int(CANVAS * 0.08)
            canvas.paste(crop, (x, max(0, y)))
        name = os.path.basename(f)
        canvas.save(f"{DST}/{name}")
        print(f"  {name}  bbox={bb}", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
