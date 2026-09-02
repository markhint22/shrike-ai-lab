#!/usr/bin/env python3
"""Pixelize v2 — robust. SDXL rendered a solid (often gray/blue) background, not the
chroma green we asked for, so v1's green key failed. v2 AUTO-DETECTS the background
color from the image corners, and auto-classifies each render:
  * SPRITE (uniform-ish background, e.g. soldier/alien/icon): key out the bg color by
    distance -> alpha, autocrop tight, pad square, nearest-downscale, quantize palette.
  * TILE (busy/non-uniform corners, e.g. floor): no keying, no crop -> downscale the
    full frame so it stays seamless.
Emits <name>@16/@32 (+ 8x previews). CPU/PIL only.
"""
import os, sys, glob
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/run/media/mhintermeister/secondary_drive1/comfy/out/style_tests"
DST = SRC + "_sprites2"
os.makedirs(DST, exist_ok=True)
PALETTE = 16

def corner_stats(im):
    w, h = im.size; k = max(4, w//16)
    pts = []
    for cx, cy in ((0,0),(w-k,0),(0,h-k),(w-k,h-k)):
        c = im.crop((cx, cy, cx+k, cy+k)).resize((1,1)).getpixel((0,0))
        pts.append(c[:3])
    # bg = average corner; spread = max channel range across corners
    bg = tuple(sum(p[i] for p in pts)//4 for i in range(3))
    spread = max(max(p[i] for p in pts) - min(p[i] for p in pts) for i in range(3))
    return bg, spread

def key_bg(im, bg, tol=60):
    im = im.convert("RGBA"); px = im.load(); w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if abs(r-bg[0])+abs(g-bg[1])+abs(b-bg[2]) < tol*3:
                px[x, y] = (0, 0, 0, 0)
    return im

def autocrop_square(im):
    bb = im.split()[-1].getbbox()
    if bb:
        # pad the crop a hair so limbs aren't flush to the edge
        x0,y0,x1,y1 = bb; pad = max(4,(x1-x0)//20)
        im = im.crop((max(0,x0-pad),max(0,y0-pad),min(im.size[0],x1+pad),min(im.size[1],y1+pad)))
    w,h = im.size; s=max(w,h)
    c = Image.new("RGBA",(s,s),(0,0,0,0)); c.paste(im,((s-w)//2,(s-h)//2)); return c

def quant(im, grid, keep_alpha=True):
    small = im.resize((grid, grid), Image.NEAREST)
    rgb = small.convert("RGB").quantize(colors=PALETTE, method=Image.MEDIANCUT).convert("RGBA")
    if keep_alpha:
        rgb.putalpha(small.split()[-1] if small.mode=="RGBA" else Image.new("L",(grid,grid),255))
    return rgb

def main():
    files = sorted(glob.glob(f"{SRC}/*.png"))
    print(f"{len(files)} raw -> {DST}", flush=True)
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        im = Image.open(f).convert("RGBA")
        bg, spread = corner_stats(im)
        is_tile = ("tile" in name) or (spread > 45)   # busy corners => texture/tile
        if is_tile:
            base = im  # keep full frame, opaque
        else:
            base = autocrop_square(key_bg(im, bg))
        for grid in (32, 16):
            sp = quant(base, grid, keep_alpha=not is_tile)
            sp.save(f"{DST}/{name}@{grid}.png")
            sp.resize((grid*8, grid*8), Image.NEAREST).save(f"{DST}/{name}@{grid}_preview.png")
        print(f"  {name}  bg={bg} spread={spread} {'TILE' if is_tile else 'sprite'}", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
