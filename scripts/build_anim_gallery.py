#!/usr/bin/env python3
"""Gallery of the FIXED ControlNet animation frames — distinct poses, consistent
character. Self-contained base64."""
import base64, io, os
from PIL import Image
SP = "/run/media/mhintermeister/secondary_drive1/comfy/out/anims_sprites3"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/gallery_anim.html"

def uri(key):
    p = f"{SP}/{key}@48.png"
    if not os.path.exists(p): return None
    im = Image.open(p).convert("RGBA"); buf = io.BytesIO(); im.save(buf,"PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

POSES = ["idle","walk","attack","hit","death"]
UNITS = [("player_trooper","Trooper","player"),("enemy_grunt","Grunt","enemy")]

def film(ukey):
    cells = "".join(
        f'<figure class="cell"><div class="frame"><img src="{uri(ukey+"__"+p)}" alt="{p}"></div>'
        f'<figcaption>{p}</figcaption></figure>' for p in POSES)
    return cells

rows = "".join(
    f'<section><h2>{name} <span>({side})</span></h2><div class="film">{film(k)}</div></section>'
    for k,name,side in UNITS)

html = f"""<title>xlite — fixed animation frames</title>
<style>
:root{{--bg:#12141a;--panel:#1a1e27;--panel2:#20252f;--ink:#d3d7e0;--mut:#868da0;--grn:#7bd88f;--amb:#e6b45c;--line:#2b313d}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace;line-height:1.5}}
.wrap{{max-width:960px;margin:0 auto;padding:40px 24px 80px}}
header.top{{border-bottom:1px solid var(--line);padding-bottom:22px;margin-bottom:8px}}
.eyebrow{{color:var(--grn);letter-spacing:.18em;text-transform:uppercase;font-size:12px;margin:0 0 10px}}
h1{{font-size:28px;margin:0 0 12px;text-wrap:balance}}
.lede{{color:var(--mut);max-width:64ch;margin:0;font-size:14px}} .lede b{{color:var(--ink)}}
section{{margin-top:34px}}
h2{{font-size:16px;margin:0 0 14px}} h2 span{{color:var(--mut);font-size:13px}}
.film{{display:flex;gap:12px;flex-wrap:wrap;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px}}
.cell{{margin:0;display:flex;flex-direction:column;align-items:center;gap:8px}}
.frame{{width:132px;height:132px;display:flex;align-items:center;justify-content:center;border-radius:6px;
background-color:#0d0f14;
background-image:linear-gradient(45deg,#171a21 25%,transparent 25%),linear-gradient(-45deg,#171a21 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#171a21 75%),linear-gradient(-45deg,transparent 75%,#171a21 75%);
background-size:16px 16px;background-position:0 0,0 8px,8px -8px,-8px 0}}
.frame img{{width:120px;height:120px;object-fit:contain;image-rendering:pixelated}}
figcaption{{font-size:12px;color:var(--amb);text-transform:uppercase;letter-spacing:.1em}}
.note{{margin-top:38px;background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--grn);border-radius:6px;padding:16px 20px;font-size:13px;color:var(--mut)}}
.note b{{color:var(--ink)}} .note code{{background:var(--panel2);color:var(--amb);padding:1px 6px;border-radius:4px}}
@media(max-width:560px){{.frame{{width:100px;height:100px}}.frame img{{width:88px;height:88px}}}}
</style>
<div class="wrap">
<header class="top">
<p class="eyebrow">xlite &middot; animation fix</p>
<h1>Distinct pose frames</h1>
<p class="lede">The earlier frames all looked alike because img2img preserved the pose. These are regenerated with <b>ControlNet-OpenPose</b>: a distinct skeleton drives each frame while a fixed seed keeps the character identical. Now <b>idle / walk / attack / hit / death</b> read as different actions &mdash; same trooper, same grunt.</p>
</header>
{rows}
<div class="note"><b>Wired &amp; tested in-engine.</b> On branch <code>feature/vibrant-sprites</code>: <code>unit.gd</code> renders an <code>AnimatedSprite2D</code> per archetype, <code>take_damage()</code> auto-plays hit/death, and all <b>301 GUT tests pass</b>. Frames are single-pose states (play on action), not smooth multi-frame cycles &mdash; a true walk-cycle tween is the next optional step.</div>
</div>
"""
open(OUT,"w").write(html); print("wrote", OUT, os.path.getsize(OUT))
