#!/usr/bin/env python3
"""Build a self-contained style-pick gallery for xlite sprites. Embeds the game-ready
48px sprites (rendered crisp) + the raw SDXL source art as base64 data URIs so the
page needs no external hosts. Dark pixel-editor aesthetic. Writes gallery.html."""
import base64, io, os
from PIL import Image

SP = "/run/media/mhintermeister/secondary_drive1/comfy/out/style_tests_sprites3"
RAW = "/run/media/mhintermeister/secondary_drive1/comfy/out/style_tests"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/gallery.html"

SUBJECTS = [("unit_soldier","Soldier","player unit"),
            ("unit_alien","Alien","enemy unit"),
            ("tile_floor","Floor","terrain tile"),
            ("icon_tech","Tech icon","UI / research")]
STYLES = [("A_clean16","Clean","bold outlines, 16-bit, crisp readable shapes"),
          ("B_gritty","Gritty","muted desaturated palette, dark sci-fi, dithered"),
          ("C_vibrant","Vibrant","saturated high-contrast arcade colors"),
          ("D_minimal","Minimal","tight 8-color flat palette, simple retro forms")]

def b64(path, resize=None):
    im = Image.open(path).convert("RGBA")
    if resize: im = im.resize(resize, Image.LANCZOS)
    buf = io.BytesIO(); im.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

def sprite_uri(subj, style):
    return b64(f"{SP}/{subj}__{style}@48.png")
def raw_uri(subj, style):
    return b64(f"{RAW}/{subj}__{style}.png", resize=(300,300))

# ---- build style columns (each style shows all 4 subjects) ----
cols = []
for skey, sname, sdesc in STYLES:
    cells = "".join(
        f'<figure class="sprite"><div class="frame"><img src="{sprite_uri(subj,skey)}" alt="{dname} {sname}"></div>'
        f'<figcaption>{dname}<span>{role}</span></figcaption></figure>'
        for subj,dname,role in SUBJECTS)
    cols.append(
        f'<section class="style" id="{skey}"><header><span class="tag">Style {skey[0]}</span>'
        f'<h2>{sname}</h2><p>{sdesc}</p></header><div class="stack">{cells}</div></section>')
columns = "\n".join(cols)

# ---- source-art strip: the soldier rendered in all 4 styles, full SDXL quality ----
raws = "".join(
    f'<figure><img src="{raw_uri("unit_soldier",skey)}" alt="raw {sname}"><figcaption>{sname}</figcaption></figure>'
    for skey,sname,_ in STYLES)

html = f"""<title>xlite — pick a sprite style</title>
<style>
:root{{--bg:#12141a;--panel:#1a1e27;--panel2:#20252f;--ink:#d3d7e0;--mut:#868da0;
--grn:#7bd88f;--amb:#e6b45c;--line:#2b313d;}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);
font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace;line-height:1.5;
-webkit-font-smoothing:antialiased}}
.wrap{{max-width:1160px;margin:0 auto;padding:40px 24px 80px}}
header.top{{border-bottom:1px solid var(--line);padding-bottom:24px;margin-bottom:32px}}
.eyebrow{{color:var(--grn);letter-spacing:.18em;text-transform:uppercase;font-size:12px;margin:0 0 10px}}
h1{{font-size:30px;margin:0 0 12px;letter-spacing:-.01em;text-wrap:balance}}
.lede{{color:var(--mut);max-width:64ch;margin:0;font-size:14px}}
.lede b{{color:var(--ink);font-weight:600}}
.grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-top:8px}}
.style{{background:var(--panel);border:1px solid var(--line);border-radius:8px;overflow:hidden}}
.style header{{padding:16px 16px 14px;border-bottom:1px solid var(--line);background:var(--panel2)}}
.tag{{font-size:11px;color:var(--amb);letter-spacing:.14em;text-transform:uppercase}}
.style h2{{margin:6px 0 6px;font-size:18px}}
.style p{{margin:0;font-size:12px;color:var(--mut);min-height:48px}}
.stack{{display:flex;flex-direction:column;gap:2px;padding:12px}}
.sprite{{margin:0;display:flex;flex-direction:column;align-items:center;gap:6px;
padding:12px 8px;border-radius:6px}}
.sprite:hover{{background:var(--panel2)}}
.frame{{width:132px;height:132px;display:flex;align-items:center;justify-content:center;
border-radius:6px;
background-color:#0d0f14;
background-image:linear-gradient(45deg,#171a21 25%,transparent 25%),linear-gradient(-45deg,#171a21 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#171a21 75%),linear-gradient(-45deg,transparent 75%,#171a21 75%);
background-size:16px 16px;background-position:0 0,0 8px,8px -8px,-8px 0}}
.frame img{{width:120px;height:120px;object-fit:contain;image-rendering:pixelated}}
figcaption{{font-size:12px;color:var(--ink);text-align:center}}
figcaption span{{display:block;font-size:10px;color:var(--mut)}}
.src{{margin-top:44px;border-top:1px solid var(--line);padding-top:28px}}
.src h3{{font-size:15px;margin:0 0 4px}}
.src .note{{color:var(--mut);font-size:12px;margin:0 0 18px;max-width:66ch}}
.srcrow{{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}}
.srcrow figure{{margin:0;background:var(--panel);border:1px solid var(--line);border-radius:8px;overflow:hidden}}
.srcrow img{{width:100%;display:block;image-rendering:auto}}
.srcrow figcaption{{padding:8px;font-size:12px}}
.how{{margin-top:40px;background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--grn);
border-radius:6px;padding:18px 20px;font-size:13px;color:var(--mut)}}
.how b{{color:var(--ink)}}
.how code{{background:var(--panel2);padding:1px 6px;border-radius:4px;color:var(--amb);font-size:12px}}
@media(max-width:900px){{.grid,.srcrow{{grid-template-columns:repeat(2,1fr)}}}}
@media(max-width:560px){{.grid,.srcrow{{grid-template-columns:1fr}}}}
</style>
<div class="wrap">
<header class="top">
<p class="eyebrow">xlite &middot; sprite direction</p>
<h1>Pick a pixel-art style</h1>
<p class="lede">Four looks, each rendered across your real asset types &mdash; <b>player unit, enemy, terrain tile, UI icon</b> &mdash; so you can judge consistency, not one lucky sprite. These are <b>style tests</b> at 48&times;48 (your placeholders were 16&times;16; SDXL pixel-art lands cleanest around 48). Tell me a column letter and I'll batch-generate units + walk/attack/hit/death frames, terrain, and icons in that direction.</p>
</header>
<div class="grid">
{columns}
</div>
<div class="src">
<h3>Source art &mdash; the soldier at full render quality</h3>
<p class="note">The generator outputs detailed 1024px pixel-art; the sprites above are these downsized to a true 48px grid + 16-color palette with a transparent background. Same underlying quality carries to every asset.</p>
<div class="srcrow">{raws}</div>
</div>
<div class="how">
<b>How this was made &mdash; $0, fully local.</b> ComfyUI stack (SDXL + Pixel Art XL LoRA) on the RTX&nbsp;3090, generated in a ~4&nbsp;min window while the coding queue paused, then auto-snapped to a game palette with a PIL post-processor. Pick a style with <code>A</code>/<code>B</code>/<code>C</code>/<code>D</code> and the full batch runs the same way.</div>
</div>
"""
open(OUT,"w").write(html)
print("wrote", OUT, os.path.getsize(OUT), "bytes")
