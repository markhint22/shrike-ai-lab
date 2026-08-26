#!/usr/bin/env python3
"""Composite the iso floor tiles in xlite's exact grid layout (screen = ((x-y)*32,
(x+y)*16), metal/tech checker) to preview tessellation WITHOUT running Godot
(headless can't render). Approximates the battlefield floor."""
from PIL import Image
ISO = "/run/media/mhintermeister/secondary_drive1/comfy/out/iso_tiles"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/iso_mockup.png"
TW, TH = 64, 32
N = 8  # grid NxN
metal = Image.open(f"{ISO}/floor_metal.png").convert("RGBA")
tech = Image.open(f"{ISO}/floor_tech.png").convert("RGBA")
# canvas big enough for the diamond spread
W = (2 * N) * (TW // 2) + TW
H = (2 * N) * (TH // 2) + TH
cx = W // 2
canvas = Image.new("RGBA", (W, H), (18, 20, 26, 255))
# draw back-to-front (painter's order by x+y)
cells = sorted([(x, y) for x in range(N) for y in range(N)], key=lambda c: c[0] + c[1])
for x, y in cells:
    sx = cx + (x - y) * (TW // 2) - TW // 2
    sy = 20 + (x + y) * (TH // 2)
    tile = tech if (x + y) % 2 == 0 else metal
    canvas.alpha_composite(tile, (sx, sy))
canvas.save(OUT)
canvas.resize((W * 2, H * 2), Image.NEAREST).save(OUT.replace(".png", "_2x.png"))
print("wrote", OUT, canvas.size)
