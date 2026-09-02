#!/usr/bin/env python3
"""Transform the square top-down terrain tiles into 64x32 ISOMETRIC diamond tiles
that fit xlite's iso grid (TILE_WIDTH=64, TILE_HEIGHT=32). Rotate 45 deg (so the
square becomes a diamond) then squash vertically to the 2:1 iso ratio. Pure PIL."""
import os, glob, sys
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/run/media/mhintermeister/secondary_drive1/comfy/out/vibrant_sprites3"
DST = "/run/media/mhintermeister/secondary_drive1/comfy/out/iso_tiles"
os.makedirs(DST, exist_ok=True)
# map generated tile name -> game terrain name
NAMES = {"tile_floor_metal":"floor_metal","tile_floor_tech":"floor_tech","tile_wall":"wall",
         "tile_cover_crate":"crate","tile_hazard":"hazard","tile_rubble":"rubble"}
TW, TH = 64, 32

def to_iso(path):
    im = Image.open(path).convert("RGBA")
    # size so that after a 45deg rotate the diagonal ~= TW
    s = round(TW / (2 ** 0.5))              # ~45
    im = im.resize((s, s), Image.LANCZOS)
    rot = im.rotate(45, expand=True, resample=Image.BICUBIC)   # diamond in a square bbox
    iso = rot.resize((TW, TH), Image.LANCZOS)                  # squash to 2:1
    # 8x preview to eyeball
    return iso, iso.resize((TW*6, TH*6), Image.NEAREST)

def main():
    n = 0
    for src, game in NAMES.items():
        matches = glob.glob(f"{SRC}/{src}__*@48.png") or glob.glob(f"{SRC}/{game}.png")
        if not matches:
            print("MISSING", src); continue
        iso, prev = to_iso(matches[0])
        iso.save(f"{DST}/{game}.png"); prev.save(f"{DST}/{game}_preview.png"); n += 1
        print("iso", game)
    print(f"DONE {n} -> {DST}")

if __name__ == "__main__":
    main()
