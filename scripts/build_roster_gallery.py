#!/usr/bin/env python3
"""Complete xlite roster gallery: all 8 units + their animation frames. Self-contained."""
import base64, io, os, glob
from PIL import Image
ANI = "/run/media/mhintermeister/secondary_drive1/comfy/out/anims_sprites3"
VIB = "/run/media/mhintermeister/secondary_drive1/comfy/out/vibrant_sprites3"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/gallery_roster.html"

def find(key):
    for base in (ANI, VIB):
        for pat in (f"{base}/{key}@48.png", f"{base}/{key}__*@48.png"):
            m = glob.glob(pat)
            if m: return m[0]
    return None

def uri(key):
    p = find(key)
    if not p: return None
    im = Image.open(p).convert("RGBA"); b = io.BytesIO(); im.save(b, "PNG")
    return "data:image/png;base64," + base64.b64encode(b.getvalue()).decode()

POSES = ["idle", "walk", "attack", "hit", "death"]
PLAYERS = [("player_trooper","Assault"),("player_heavy","Heavy"),("player_sniper","Sniper"),("player_medic","Medic")]
ENEMIES_ANIM = [("enemy_grunt","Grunt"),("enemy_brute","Brute")]
ENEMIES_IDLE = [("enemy_flyer","Flyer"),("enemy_drone","Drone")]

def film(prefix):
    cells = ""
    for p in POSES:
        u = uri(f"{prefix}__{p}")
        if not u: continue
        cells += f'<figure class="cell"><div class="frame"><img src="{u}"></div><figcaption>{p}</figcaption></figure>'
    return cells

def idlecard(key, name, tag):
    u = uri(f"{key}__idle") or uri(f"tile_{key}")
    return (f'<figure class="cell big"><div class="frame"><img src="{u}"></div>'
            f'<figcaption>{name}<span>{tag}</span></figcaption></figure>')

sections = ""
for key, name in PLAYERS:
    sections += f'<section><h2>{name} <span>player</span></h2><div class="film">{film(key)}</div></section>'
for key, name in ENEMIES_ANIM:
    sections += f'<section><h2>{name} <span>enemy</span></h2><div class="film">{film(key)}</div></section>'
idles = "".join(idlecard(k, n, "idle + hover") for k, n in ENEMIES_IDLE)
sections += f'<section><h2>Flyer &amp; Drone <span>enemy &middot; hover + procedural FX</span></h2><div class="film">{idles}</div></section>'

html = f"""<title>xlite — complete roster</title>
<style>
:root{{--bg:#12141a;--panel:#1a1e27;--panel2:#20252f;--ink:#d3d7e0;--mut:#868da0;--grn:#7bd88f;--amb:#e6b45c;--line:#2b313d}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace;line-height:1.5}}
.wrap{{max-width:1000px;margin:0 auto;padding:40px 24px 80px}}
header.top{{border-bottom:1px solid var(--line);padding-bottom:22px;margin-bottom:8px}}
.eyebrow{{color:var(--grn);letter-spacing:.18em;text-transform:uppercase;font-size:12px;margin:0 0 10px}}
h1{{font-size:29px;margin:0 0 12px}}
.lede{{color:var(--mut);max-width:66ch;margin:0;font-size:14px}} .lede b{{color:var(--ink)}}
section{{margin-top:30px}}
h2{{font-size:16px;margin:0 0 12px}} h2 span{{color:var(--mut);font-size:12px;text-transform:uppercase;letter-spacing:.1em}}
.film{{display:flex;gap:10px;flex-wrap:wrap;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px}}
.cell{{margin:0;display:flex;flex-direction:column;align-items:center;gap:7px}}
.frame{{width:108px;height:108px;display:flex;align-items:center;justify-content:center;border-radius:6px;
background-color:#0d0f14;
background-image:linear-gradient(45deg,#171a21 25%,transparent 25%),linear-gradient(-45deg,#171a21 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#171a21 75%),linear-gradient(-45deg,transparent 75%,#171a21 75%);
background-size:14px 14px;background-position:0 0,0 7px,7px -7px,-7px 0}}
.frame img{{width:96px;height:96px;object-fit:contain;image-rendering:pixelated}}
.big .frame{{width:128px;height:128px}} .big .frame img{{width:116px;height:116px}}
figcaption{{font-size:12px;color:var(--amb);text-transform:uppercase;letter-spacing:.08em;text-align:center}}
figcaption span{{display:block;color:var(--mut);font-size:10px;letter-spacing:0}}
.note{{margin-top:36px;background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--grn);border-radius:6px;padding:16px 20px;font-size:13px;color:var(--mut)}}
.note b{{color:var(--ink)}}
@media(max-width:560px){{.frame{{width:88px;height:88px}}.frame img{{width:78px;height:78px}}}}
</style>
<div class="wrap">
<header class="top">
<p class="eyebrow">xlite &middot; complete roster &middot; $0 local</p>
<h1>Every unit, animated</h1>
<p class="lede">Four <b>player classes</b> and four <b>enemy archetypes</b>. The six humanoids have full idle/walk/attack/hit/death frames (ControlNet + IP-Adapter, character-consistent); the two floating enemies hover and use procedural flash/fade reactions. All 48px, generated locally on the 3090. Merged to <b>main</b>, 305 tests passing.</p>
</header>
{sections}
<div class="note"><b>Complete.</b> All 8 units have images + animations; iso floor + crate cover on the battlefield; the 6 UI icons are homed (research in the tech tree; move/weapon/ammo/medkit in the battle HUD; armor shown on armored units). Remaining is genuine game design (a real inventory screen, class-based stats via a roster refactor, isometric-native cover for wall/hazard tiles).</div>
</div>
"""
open(OUT, "w").write(html)
print("wrote", OUT, os.path.getsize(OUT))
