#!/usr/bin/env python3
"""Procedural pixel-art animation from ONE idle sprite. Every frame is the SAME source
pixels transformed, so the character (weapon/clothes/colors/proportions) is IDENTICAL
across frames by construction; the motion is authored to read as the action. This is
the corrected pose approach (AI-redrawing each pose drifts + doesn't read).

Per bg-removed idle (RGBA), on a consistent padded canvas:
  idle | walk1..4 (contact/passing cycle, alternating legs + body bob)
  attack1..3 (wind-up / impact+flash / recovery) | hit1..2 (recoil+flash) | death
Usage: procedural_anim.py <dir_of_*__idle@64.png> [out_dir]   (CPU/PIL only)
"""
import os, sys, glob
from PIL import Image, ImageDraw

SRC = sys.argv[1]
DST = sys.argv[2] if len(sys.argv) > 2 else SRC + "_anim"
os.makedirs(DST, exist_ok=True)
PAD = 22

def framed(sp):
    w, h = sp.size
    c = Image.new("RGBA", (w + 2*PAD, h + 2*PAD), (0,0,0,0))
    c.paste(sp, (PAD, PAD), sp)
    return c, w, h

def put(canvas, im, dx, dy):
    c = canvas.copy()
    c.paste(im, (dx, dy), im)
    return c

def shift(im, dx, dy):
    c = Image.new("RGBA", im.size, (0,0,0,0))
    c.paste(im, (dx, dy), im)
    return c

def lean(im, dx_top):
    # shear: top row shifts by dx_top px, bottom row 0 (feet planted)
    W, H = im.size
    return im.transform((W, H), Image.AFFINE, (1, -dx_top/H, dx_top, 0, 1, 0), resample=Image.NEAREST)

def leg_lean(im, s):
    # Continuous tapered shear: the BOTTOM slides by `s` px, the top stays fixed, so
    # the legs/lower body sway like a stride WITHOUT ever cutting the sprite apart
    # (splitting the sprite into leg halves tore AI sprites — this never does).
    W, H = im.size
    return im.transform((W, H), Image.AFFINE, (1, -s/H, 0, 0, 1, 0), resample=Image.NEAREST)

def whiten(im, amt):
    r, g, b, a = im.split()
    w = Image.new("L", im.size, 255)
    return Image.merge("RGBA", (Image.blend(r, w, amt), Image.blend(g, w, amt), Image.blend(b, w, amt), a))

def flash(im, cx, cy, r=7):
    c = im.copy(); d = ImageDraw.Draw(c)
    for dx, dy in [(-r-4,0),(r+4,0),(0,-r-4),(0,r+4),(-r,-r),(r,r),(-r,r),(r,-r)]:
        d.line([cx, cy, cx+dx, cy+dy], fill=(255,225,110,220), width=2)
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(255,240,160,235))
    d.ellipse([cx-r//2, cy-r//2, cx+r//2, cy+r//2], fill=(255,255,235,255))
    return c

def save(im, name):
    im.save(f"{DST}/{name}.png")
    im.resize((im.width*4, im.height*4), Image.NEAREST).save(f"{DST}/{name}_x4.png")

def animate(path):
    unit = os.path.basename(path).split("@")[0].replace("__idle", "")
    sp = Image.open(path).convert("RGBA")
    base, w, h = framed(sp)
    W, H = base.size
    fx, fy = PAD + int(w*0.84), PAD + int(h*0.46)   # weapon-side flash anchor

    save(base, f"{unit}__idle")
    # walk: legs sway one way (contact, planted) / body up (passing) / sway other way / up
    save(leg_lean(base,  6),               f"{unit}__walk1")
    save(shift(base, 0, -3),               f"{unit}__walk2")
    save(leg_lean(base, -6),               f"{unit}__walk3")
    save(shift(base, 0, -3),               f"{unit}__walk4")
    # attack: wind-up (lean back) / impact (lunge fwd + muzzle flash) / recovery
    save(lean(base, -4),                            f"{unit}__attack1")
    save(flash(lean(shift(base, 3, -1), 7), fx, fy), f"{unit}__attack2")
    save(lean(base, 3),                             f"{unit}__attack3")
    # hit: recoil (knocked back + tilt + white flash) / settle
    save(whiten(lean(shift(base, -5, 0), -6), 0.55), f"{unit}__hit1")
    save(shift(base, -2, 0),                         f"{unit}__hit2")
    # death: tipped onto the ground
    dead = base.rotate(78, resample=Image.NEAREST, expand=False, center=(W//2, int(H*0.74)))
    save(shift(dead, 0, int(h*0.12)), f"{unit}__death")
    print("animated", unit, flush=True)

def main():
    files = sorted(glob.glob(f"{SRC}/*__idle@64.png"))
    print(f"{len(files)} idles -> {DST}", flush=True)
    for f in files:
        animate(f)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
