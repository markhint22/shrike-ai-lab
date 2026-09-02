#!/usr/bin/env python3
"""Reliable DEATH frames: ControlNet won't render a prone body, so make death by
TOPPLING the idle sprite - rotate 90 degrees (fallen on its side) + darken +
desaturate. Always reads as 'dead', for every unit (humanoid or not)."""
import glob, os
from PIL import Image, ImageEnhance
S = "/run/media/mhintermeister/secondary_drive1/comfy/out/anims_sprites3"
n = 0
for f in sorted(glob.glob(f"{S}/*__idle@48.png")):
    unit = os.path.basename(f).replace("__idle@48.png", "")
    im = Image.open(f).convert("RGBA")
    d = im.rotate(-90, expand=False, resample=Image.NEAREST)  # topple onto its side
    d = ImageEnhance.Brightness(d).enhance(0.55)              # dim (dead)
    d = ImageEnhance.Color(d).enhance(0.65)                   # desaturate
    d.save(f"{S}/{unit}__death@48.png")
    d.resize((48*4, 48*4), Image.NEAREST).save(f"{S}/{unit}__death@48_preview.png")
    n += 1; print("toppled", unit)
print(f"DONE {n}")
