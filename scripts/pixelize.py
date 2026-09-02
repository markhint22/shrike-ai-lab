#!/usr/bin/env python3
"""Post-process raw SDXL pixel-art-style renders into true game sprites:
  1. chroma-key the flat green background -> transparent alpha
  2. autocrop to the subject, pad square
  3. nearest-neighbor downscale to the target grid (default 32, also emits 16)
  4. quantize to a limited palette (median cut)
Emits <name>@32.png and <name>@16.png next to an index. Pure PIL (in the venv).
"""
import os, sys, glob
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/run/media/mhintermeister/secondary_drive1/comfy/out/style_tests"
DST = SRC + "_sprites"
os.makedirs(DST, exist_ok=True)
GREEN = (0, 177, 64)        # approx chroma green; tolerance below
TOL = 90
PALETTE = 16

def chroma_alpha(im):
    im = im.convert("RGBA"); px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if abs(r-GREEN[0]) < TOL and g > 110 and abs(b-GREEN[2]) < TOL and g > r+30 and g > b+20:
                px[x, y] = (0, 0, 0, 0)
    return im

def autocrop(im):
    bbox = im.split()[-1].getbbox()
    return im.crop(bbox) if bbox else im

def square(im):
    w, h = im.size; s = max(w, h)
    c = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c.paste(im, ((s-w)//2, (s-h)//2)); return c

def pixelize(im, grid):
    small = im.resize((grid, grid), Image.NEAREST)
    # quantize RGB (keep alpha separate)
    rgb = small.convert("RGB").quantize(colors=PALETTE, method=Image.MEDIANCUT).convert("RGB")
    out = rgb.convert("RGBA")
    a = small.split()[-1]
    out.putalpha(a)
    return out

def main():
    files = sorted(glob.glob(f"{SRC}/*.png"))
    print(f"{len(files)} raw renders -> {DST}", flush=True)
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        im = autocrop(square(chroma_alpha(Image.open(f))))
        for grid in (32, 16):
            sp = pixelize(im, grid)
            up = sp.resize((grid*8, grid*8), Image.NEAREST)   # 8x preview for eyeballing
            sp.save(f"{DST}/{name}@{grid}.png")
            up.save(f"{DST}/{name}@{grid}_preview.png")
        print(f"  {name}", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
