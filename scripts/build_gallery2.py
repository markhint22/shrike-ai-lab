#!/usr/bin/env python3
"""Asset-sheet gallery for the produced VIBRANT batch. Self-contained (base64)."""
import base64, io, os
from PIL import Image
SP = "/run/media/mhintermeister/secondary_drive1/comfy/out/vibrant_sprites3"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/gallery2.html"

def uri(key):
    p = f"{SP}/{key}@48.png"
    if not os.path.exists(p): return None
    im = Image.open(p).convert("RGBA")
    buf = io.BytesIO(); im.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

def sprite(key, label, sub="", big=False):
    u = uri(key)
    if not u: return ""
    cls = "cell big" if big else "cell"
    s = f'<span>{sub}</span>' if sub else ''
    return f'<figure class="{cls}"><div class="frame"><img src="{u}" alt="{label}"></div><figcaption>{label}{s}</figcaption></figure>'

def tilecell(key, label):
    u = uri(key)
    if not u: return ""
    return (f'<figure class="cell"><div class="tileframe" style="background-image:url({u})"></div>'
            f'<figcaption>{label}<span>2&times;2 tiled</span></figcaption></figure>')

PLAYER_FILM = [("player_trooper__idle","idle"),("player_trooper__walk","walk"),
               ("player_trooper__attack","attack"),("player_trooper__hit","hit"),("player_trooper__death","death")]
ENEMY_FILM  = [("enemy_grunt__idle","idle"),("enemy_grunt__walk","walk"),
               ("enemy_grunt__attack","attack"),("enemy_grunt__hit","hit"),("enemy_grunt__death","death")]
PLAYERS = [("player_trooper__idle","Trooper"),("player_heavy__idle","Heavy"),
           ("player_sniper__idle","Sniper"),("player_medic__idle","Medic")]
ENEMIES = [("enemy_grunt__idle","Grunt"),("enemy_brute__idle","Brute"),
           ("enemy_flyer__idle","Flyer"),("enemy_drone__idle","Drone")]
TILES = [("tile_floor_metal__idle","Metal floor"),("tile_floor_tech__idle","Tech floor"),
         ("tile_wall__idle","Wall"),("tile_cover_crate__idle","Crate"),
         ("tile_hazard__idle","Hazard"),("tile_rubble__idle","Rubble")]
ICONS = [("icon_chip__idle","Research"),("icon_weapon__idle","Weapon"),("icon_armor__idle","Armor"),
         ("icon_medkit__idle","Medkit"),("icon_ammo__idle","Ammo"),("icon_move__idle","Move")]

def row(items, fn=lambda k,l: sprite(k,l)):
    return "".join(fn(k,l) for k,l in items)

html = f"""<title>xlite — Vibrant sprite set</title>
<style>
:root{{--bg:#12141a;--panel:#1a1e27;--panel2:#20252f;--ink:#d3d7e0;--mut:#868da0;
--grn:#7bd88f;--amb:#e6b45c;--line:#2b313d}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);
font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace;line-height:1.5}}
.wrap{{max-width:1100px;margin:0 auto;padding:40px 24px 80px}}
header.top{{border-bottom:1px solid var(--line);padding-bottom:22px;margin-bottom:10px}}
.eyebrow{{color:var(--grn);letter-spacing:.18em;text-transform:uppercase;font-size:12px;margin:0 0 10px}}
h1{{font-size:30px;margin:0 0 12px;text-wrap:balance}}
.lede{{color:var(--mut);max-width:66ch;margin:0;font-size:14px}}
.lede b{{color:var(--ink)}}
section{{margin-top:38px}}
h2{{font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--amb);
margin:0 0 4px;border-bottom:1px solid var(--line);padding-bottom:8px}}
.sub{{color:var(--mut);font-size:12px;margin:0 0 16px}}
.row{{display:flex;flex-wrap:wrap;gap:14px}}
.film{{display:flex;gap:8px;align-items:flex-end;background:var(--panel);border:1px solid var(--line);
border-radius:8px;padding:14px 16px;overflow-x:auto}}
.cell{{margin:0;display:flex;flex-direction:column;align-items:center;gap:7px}}
.frame{{width:104px;height:104px;display:flex;align-items:center;justify-content:center;border-radius:6px;
background-color:#0d0f14;
background-image:linear-gradient(45deg,#171a21 25%,transparent 25%),linear-gradient(-45deg,#171a21 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#171a21 75%),linear-gradient(-45deg,transparent 75%,#171a21 75%);
background-size:14px 14px;background-position:0 0,0 7px,7px -7px,-7px 0}}
.frame img{{width:92px;height:92px;object-fit:contain;image-rendering:pixelated}}
.film .frame{{width:84px;height:84px}} .film .frame img{{width:74px;height:74px}}
.tileframe{{width:104px;height:104px;border-radius:6px;image-rendering:pixelated;
background-size:52px 52px;background-repeat:repeat;border:1px solid var(--line)}}
figcaption{{font-size:12px;text-align:center}}
figcaption span{{display:block;font-size:10px;color:var(--mut)}}
.note{{margin-top:44px;background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--grn);
border-radius:6px;padding:16px 20px;font-size:13px;color:var(--mut)}}
.note b{{color:var(--ink)}} .note code{{background:var(--panel2);color:var(--amb);padding:1px 6px;border-radius:4px}}
@media(max-width:560px){{.frame{{width:88px;height:88px}}.frame img{{width:78px;height:78px}}}}
</style>
<div class="wrap">
<header class="top">
<p class="eyebrow">xlite &middot; vibrant set &middot; 48px &middot; $0 local</p>
<h1>Vibrant sprite set</h1>
<p class="lede">28 game-ready sprites in the chosen <b>Vibrant</b> direction: an 8-unit roster, animation-pose frames for the two primaries, six terrain tiles, and six UI icons. All 48&times;48 with a transparent background and a 16-color palette. Generated locally on the 3090 in one ~4&nbsp;min window.</p>
</header>

<section>
<h2>Player &mdash; Trooper animation frames</h2>
<p class="sub">img2img off the idle keeps the character consistent frame-to-frame (not yet pixel-perfect walk-cycle frames &mdash; that needs ControlNet).</p>
<div class="film">{row(PLAYER_FILM)}</div>
</section>

<section>
<h2>Enemy &mdash; Grunt animation frames</h2>
<div class="film">{row(ENEMY_FILM)}</div>
</section>

<section>
<h2>Player roster</h2>
<div class="row">{row(PLAYERS)}</div>
</section>

<section>
<h2>Enemy roster</h2>
<div class="row">{row(ENEMIES)}</div>
</section>

<section>
<h2>Terrain tiles</h2>
<p class="sub">shown 2&times;2 tiled to check seams.</p>
<div class="row">{row(TILES, tilecell)}</div>
</section>

<section>
<h2>UI &amp; tech icons</h2>
<div class="row">{row(ICONS)}</div>
</section>

<div class="note"><b>Next steps.</b> Say the word and I'll wire these into <code>assets/sprites/</code> in the xlite repo (Godot-ready, on a feature branch). For production-clean <b>walk cycles</b>, the follow-up is ControlNet pose-conditioning &mdash; consistent character across exact poses. Any unit/tile/icon you want re-rolled or added, just name it.</div>
</div>
"""
open(OUT,"w").write(html)
print("wrote", OUT, os.path.getsize(OUT))
