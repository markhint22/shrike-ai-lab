#!/usr/bin/env bash
# Wave-3c coverage tests for art/*.py (art_qa_gate, art_pipeline_run, gen_from_brief, pixelize3).
# The REAL files are imported by path / executed in place. Needs numpy+PIL: uses $OVN_ART_PY, else a venv on the box that has
# both (system python3 has no numpy); SKIPs (exit 0) if none. torch/diffusers are stubbed via sys.modules (no GPU, no model);
# every hardcoded /run/media/... output path is redirected into a temp dir (os.makedirs patched) - nothing outside mktemp is touched.
# subprocess.run is faked in art_pipeline_run, so no generator is ever launched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"; ART="$Q/art"
[ -f "$ART/art_qa_gate.py" ] || { echo "  SKIP: art dir not found"; exit 0; }
REAL_HOME="$HOME"
export PYTHONDONTWRITEBYTECODE=1
PYX=""
for c in "${OVN_ART_PY:-}" "$REAL_HOME/aider-venv/bin/python" "$REAL_HOME"/overnight-queue/repos/*/backend/.venv/bin/python "$REAL_HOME/shrike-ai-lab-training/.venv/bin/python" python3; do
  [ -n "$c" ] || continue
  if "$c" -c 'import numpy, PIL.Image' 2>/dev/null; then PYX="$c"; break; fi
done
[ -n "$PYX" ] || { echo "  SKIP: no python with numpy+PIL"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# a venv python does not see coverage.py; expose JUST the coverage package so the runner's sitecustomize can trace it
mkdir -p "$T/covlink"; CP="$(python3 -c 'import coverage,os;print(os.path.dirname(coverage.__file__))' 2>/dev/null)"
[ -n "$CP" ] && ln -s "$CP" "$T/covlink/coverage"
export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$T/covlink"
export HOME="$T/home"; mkdir -p "$HOME"
pass=0; fail=0
run_driver(){  # $1 = name, stdin = driver source
  cat > "$T/$1.py"
  local out rc; out="$(ART_DIR="$ART" WORK="$T/w_$1" "$PYX" "$T/$1.py" 2>&1)"; rc=$?
  printf '%s\n' "$out" | grep -v '^PASS ' | grep -v '^PASSES=' | sed 's/^/    /'
  local n f; n="$(printf '%s\n' "$out" | grep -c '^PASS ')"; f="$(printf '%s\n' "$out" | grep -c '^FAIL ')"
  pass=$((pass+n)); fail=$((fail+f))
  if [ $rc -ne 0 ] && [ "$f" = 0 ]; then fail=$((fail+1)); echo "  FAIL $1: driver crashed rc=$rc"; fi
  echo "  $1: $n checks passed, $f failed (rc=$rc)"
}
COMMON='
import os, sys, importlib.util, json
ART = os.environ["ART_DIR"]; WORK = os.environ["WORK"]; os.makedirs(WORK, exist_ok=True)
def chk(name, cond, extra=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + str(extra)))
def load(name, argv=None):
    if argv is not None: sys.argv = argv
    spec = importlib.util.spec_from_file_location(name, os.path.join(ART, name + ".py"))
    m = importlib.util.module_from_spec(spec); sys.modules[name + "_uut"] = m; spec.loader.exec_module(m); return m
'

# ------------------------------------------------------------------ art_qa_gate
run_driver qa <<PY
$COMMON
import numpy as np
from PIL import Image
sys.path.insert(0, ART)
G = load("art_qa_gate")
def blank(w=96, h=96): return np.zeros((h, w, 4), dtype=np.uint8)
def blob(arr, y0, y1, x0, x1, rgb=(200, 40, 40), a=255):
    arr[y0:y1, x0:x1, :3] = rgb; arr[y0:y1, x0:x1, 3] = a; return arr
good = blob(blank(), 30, 70, 30, 70)
r = G.inspect(good, "idle"); chk("clean idle sprite passes", r["ok"] and r["reasons"] == [], r)
chk("coverage rounded", isinstance(r["coverage"], float))
solid = blob(blank(), 0, 96, 0, 96)
r = G.inspect(solid, "idle"); txt = " ".join(r["reasons"])
chk("solid card -> no_alpha", "no_alpha" in txt, r); chk("solid card -> bg_residue (idle)", "bg_residue(4 opaque corners)" in txt, r)
chk("solid card -> edge_frame", "edge_frame" in txt, r); chk("solid card -> coverage_high", "coverage_high" in txt, r)
r = G.inspect(solid, "dead"); chk("bg_residue only for idle/object", "bg_residue" not in " ".join(r["reasons"]), r)
empty = blank()
r = G.inspect(empty, "idle"); chk("empty -> coverage_low", any(x.startswith("coverage_low") for x in r["reasons"]) and not r["ok"], r)
r = G.inspect(empty, "dead"); chk("empty dead -> 'empty'", "empty" in r["reasons"], r)
r = G.inspect(empty, "tile"); chk("role tile skips pose/halo checks", r["reasons"] == [x for x in r["reasons"] if x.startswith("coverage_low")], r)
halo = blob(blank(), 20, 60, 30, 70)
halo[80:96, 10:90, :3] = (128, 128, 128); halo[80:96, 10:90, 3] = 100
r = G.inspect(halo, "idle"); chk("low-sat semi-opaque fringe at feet -> feet_halo", any(x.startswith("feet_halo") for x in r["reasons"]), r)
r = G.inspect(halo, "dead"); chk("feet_halo only for idle/object", not any(x.startswith("feet_halo") for x in r["reasons"]), r)
tall = blob(blank(), 10, 80, 40, 56)
r = G.inspect(tall, "dead"); chk("standing corpse -> standing_pose", any(x.startswith("standing_pose") for x in r["reasons"]), r)
r = G.inspect(tall, "downed"); chk("standing downed -> standing_pose", any(x.startswith("standing_pose") for x in r["reasons"]), r)
lying = blob(blank(), 40, 60, 10, 86)
r = G.inspect(lying, "dead"); chk("lying corpse passes", r["ok"], r)
r = G.inspect(tall, "idle"); chk("tall idle is fine (pose rule only dead/downed)", not any(x.startswith("standing") for x in r["reasons"]), r)
# load() + main() through the real CLI on a dir of PNGs
d = os.path.join(WORK, "sprites"); os.makedirs(d, exist_ok=True)
Image.fromarray(good, "RGBA").save(os.path.join(d, "a_good.png"))
Image.fromarray(solid, "RGBA").save(os.path.join(d, "b_bad.png"))
Image.fromarray(good, "RGBA").save(os.path.join(d, "c_preview.png"))
arr = G.load(os.path.join(d, "a_good.png")); chk("load() returns RGBA array", arr.shape == (96, 96, 4))
import subprocess
def cli(*a):
    return subprocess.run([sys.executable, os.path.join(ART, "art_qa_gate.py"), *a], capture_output=True, text=True)
p = cli(d); res = json.loads(p.stdout)
chk("CLI rc 0 always", p.returncode == 0); chk("CLI lists 2 files (previews skipped)", [x["file"] for x in res] == ["a_good.png", "b_bad.png"], res)
chk("CLI stderr summary default role idle", "[qa idle] 1/2 pass" in p.stderr and "FAIL b_bad.png" in p.stderr, p.stderr)
p = cli(d, "--role", "dead"); chk("CLI --role dead", "[qa dead]" in p.stderr, p.stderr)
e = os.path.join(WORK, "emptydir"); os.makedirs(e, exist_ok=True)
p = cli(e); chk("CLI empty dir -> [] and 0/0", json.loads(p.stdout) == [] and "0/0 pass" in p.stderr, p.stdout + p.stderr)
PY

# ------------------------------------------------------------- art_pipeline_run
run_driver pipe <<PY
$COMMON
import numpy as np, io, contextlib
from PIL import Image
P = load("art_pipeline_run", ["art_pipeline_run.py"])
chk("BRIEFS loaded", "units" in P.BRIEFS and len(P.BRIEFS["units"]) > 5)
# real qa_failures() on a temp sprite dir
sd = os.path.join(WORK, "spr"); os.makedirs(sd, exist_ok=True)
good = np.zeros((64, 64, 4), dtype=np.uint8); good[15:50, 15:50] = (200, 40, 40, 255)
bad = np.zeros((64, 64, 4), dtype=np.uint8); bad[5:60, 25:39] = (200, 40, 40, 255)   # standing for role dead
Image.fromarray(good, "RGBA").save(os.path.join(sd, "unit_a@64.png"))
Image.fromarray(bad, "RGBA").save(os.path.join(sd, "unit_b@64.png"))
Image.fromarray(good, "RGBA").save(os.path.join(sd, "unit_c@48.png"))   # ignored: not @64
f = P.qa_failures(sd, "idle"); chk("idle: both @64 sprites pass", f == [], f)
f = P.qa_failures(sd, "dead"); chk("dead: the standing one fails", [n for n, _ in f] == ["unit_b"] and f[0][1], f)
# main(): fake subprocess + scripted qa_failures, OUTBASE redirected
calls = []
class R: returncode = 0
def fake_run(cmd, env=None, check=None, **kw):
    calls.append((os.path.basename(cmd[1]), cmd[2:], (env or {}).get("SEED_OFFSET"), check)); return R()
P.subprocess.run = fake_run
P.OUTBASE = os.path.join(WORK, "out")
def run_main(argv, script):
    calls.clear(); seq = iter(script)
    P.qa_failures = lambda d, role: next(seq)
    sys.argv = argv; buf = io.StringIO()
    with contextlib.redirect_stdout(buf): P.main()
    return buf.getvalue()
n_units = len(P.BRIEFS["units"])
out = run_main(["x", "--role", "dead"], [[]])
chk("all-pass first pass: ALL PASS + DONE", "ALL PASS" in out and "PIPELINE DONE" in out and "still failing" not in out, out)
chk("one generate + one pixelize call", [c[0] for c in calls] == ["gen_from_brief.py", "pixelize3.py"], calls)
chk("generate gets every unit key with role suffix", len(calls[0][1]) == n_units and all(k.endswith("__dead") for k in calls[0][1]), calls[0])
chk("pixelize gets raw dir under OUTBASE", calls[1][1] == [P.OUTBASE + "/units_dead"], calls[1])
chk("SEED_OFFSET=0 pass one, check=False", calls[0][2] == "0" and calls[0][3] is False, calls[0])
out = run_main(["x", "--role", "idle", "--passes", "3"], [[("unit_a", ["r1"]), ("unit_b", ["r2", "r3"])], [("unit_b", ["r2"])], []])
chk("re-rolls only failures on pass 2", calls[2][1] == ["unit_a", "unit_b"] and calls[4][1] == ["unit_b"], calls)
chk("seed offset advances per pass", [c[2] for c in calls if c[0] == "gen_from_brief.py"] == ["0", "1", "2"], calls)
chk("FAIL detail lines with joined reasons", "FAIL unit_b: r2; r3" in out and "2 fail after pass 1" in out, out)
chk("recovers on pass 3 -> ALL PASS", "ALL PASS" in out and "still failing" not in out, out)
out = run_main(["x", "--role", "downed", "--passes", "2"], [[("u1", ["x"])], [("u1", ["x"]), ("u2", ["y"])]])
chk("still failing after N passes is flagged", "[QA downed] 2 still failing after 2 passes (flagged): u1, u2" in out, out)
chk("pass count honoured (2 passes -> 2 generates)", len([c for c in calls if c[0] == "gen_from_brief.py"]) == 2, calls)
# the __main__ guard, via runpy, with --passes 0 so no generator subprocess can ever start
import runpy, subprocess as _sp
_real = _sp.run
_sp.run = lambda *a, **k: (_ for _ in ()).throw(AssertionError("subprocess must not run"))
sys.argv = ["art_pipeline_run.py", "--role", "object", "--passes", "0"]
buf = io.StringIO()
with contextlib.redirect_stdout(buf): runpy.run_path(os.path.join(ART, "art_pipeline_run.py"), run_name="__main__")
_sp.run = _real
chk("__main__ with zero passes just prints DONE", "object PIPELINE DONE" in buf.getvalue(), buf.getvalue())
PY

# -------------------------------------------------------------- gen_from_brief
run_driver gen <<PY
$COMMON
import types, contextlib, io
REC = {"gen": [], "saved": [], "calls": []}
class Img:
    def __init__(self, tag): self.tag = tag
    def save(self, path): REC["saved"].append(path)
class Out:
    def __init__(self, tag): self.images = [Img(tag)]
class Gen:
    def __init__(self, dev): self.dev = dev; self.seed = None
    def manual_seed(self, s): self.seed = s; REC["gen"].append((self.dev, s)); return self
class Pipe:
    def __init__(self): pass
    def to(self, dev): REC["calls"].append(("to", dev)); return self
    def load_lora_weights(self, p): REC["calls"].append(("lora", os.path.basename(p)))
    def fuse_lora(self, lora_scale=None): REC["calls"].append(("fuse", lora_scale))
    def set_progress_bar_config(self, **kw): REC["calls"].append(("bar", kw))
    def __call__(self, **kw): REC["calls"].append(("call", kw["height"], kw["num_inference_steps"])); return Out(kw["prompt"])
    @classmethod
    def from_single_file(cls, path, torch_dtype=None): REC["calls"].append(("ckpt", os.path.basename(path), torch_dtype)); return cls()
torch = types.ModuleType("torch"); torch.float16 = "fp16"; torch.Generator = Gen
diff = types.ModuleType("diffusers"); diff.StableDiffusionXLPipeline = Pipe
sys.modules["torch"] = torch; sys.modules["diffusers"] = diff
# redirect every hardcoded /run/media path into WORK
_real_makedirs = os.makedirs
MADE = []
def safe_makedirs(p, *a, **k):
    if str(p).startswith("/run/media"):
        MADE.append(str(p)); p = os.path.join(WORK, "redirected", str(p).lstrip("/"))
    return _real_makedirs(p, *a, **k)
os.makedirs = safe_makedirs
g = load("gen_from_brief")
B = g.BRIEFS
chk("paths are the hardcoded comfy ones (module untouched)", g.CKPT.endswith("sd_xl_base_1.0.safetensors") and g.LORA.endswith("pixel-art-xl.safetensors"))
# build_prompt across every family x suffix
seen = set()
for unit, u in B["units"].items():
    for suf in ("__dead", "__downed"):
        name, prompt, neg = g.build_prompt(unit + suf)
        seen.add((u["family"], suf))
        chk("%s%s name" % (unit, suf), name == "%s__%s.png" % (unit, suf[2:]), name)
        chk("%s%s prompt front-loads pixel art + side view" % (unit, suf), prompt.startswith("pixel art,") and "side view" in prompt, prompt)
        chk("%s%s negatives include standing/upright" % (unit, suf), "standing, upright" in neg and B["base_negatives"] in neg, neg)
    name, prompt, neg = g.build_prompt(unit)
    chk(unit + " live idle name/prompt/neg", name == unit + "__idle.png" and "full body centered" in prompt and B["live_negatives"] in neg, (name, prompt))
chk("all 3 families x dead/downed exercised", len(seen) == 6, seen)
_, p, _ = g.build_prompt("enemy_grunt__dead"); chk("DEAD_STRONG subject override used", "green mutant alien" in p, p)
_, p, _ = g.build_prompt("enemy_drone__dead"); chk("robot corpse uses oil pool + wrecked robot", "oil pool and debris" in p and "wrecked robot" in p, p)
_, p, _ = g.build_prompt("enemy_drone__downed"); chk("robot downed uses sparks", "sparks and loose wires" in p, p)
_, p, _ = g.build_prompt("player_medic__downed"); chk("human downed uses blood smear", "small blood smear" in p, p)
chk("_strip_article: a/an/the/none", [g._strip_article(x) for x in ("A big cat", "an owl", "The end", "plain")] == ["big cat", "owl", "end", "plain"])
# out_dir suffix routing
chk("out_dir dead", g.out_dir("x__dead").endswith("/units_dead"))
chk("out_dir downed", g.out_dir("x__downed").endswith("/units_downed"))
chk("out_dir live", g.out_dir("x").endswith("/units_brief"))
chk("makedirs was redirected (3 calls)", len(MADE) == 3 and os.path.isdir(os.path.join(WORK, "redirected")), MADE)
# main() in every mode
def run_main(argv, env=None):
    REC["gen"].clear(); REC["saved"].clear(); REC["calls"].clear()
    sys.argv = ["gen_from_brief.py"] + argv
    old = os.environ.get("SEED_OFFSET")
    if env is not None: os.environ["SEED_OFFSET"] = env
    else: os.environ.pop("SEED_OFFSET", None)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): g.main()
    if old is not None: os.environ["SEED_OFFSET"] = old
    return buf.getvalue()
n = len(B["units"])
out = run_main([])
chk("default: all live idles", len(REC["saved"]) == n and all(s.endswith("__idle.png") for s in REC["saved"]), REC["saved"][:2])
chk("model setup sequence (ckpt, to cuda, lora, fuse 1.15, bar off)", [c[0] for c in REC["calls"][:5]] == ["ckpt", "to", "lora", "fuse", "bar"] and ("fuse", 1.15) in REC["calls"] and ("to", "cuda") in REC["calls"], REC["calls"][:5])
chk("seeds 7000+i with offset 0", [s for _, s in REC["gen"]] == [7000 + i for i in range(n)], REC["gen"][:3])
chk("progress lines + DONE", "[1/%d]" % n in out and out.rstrip().endswith("DONE") and ("loading SDXL + LoRA for %d target(s)" % n) in out, out[:200])
chk("1024 px, 40 steps", ("call", 1024, 40) in REC["calls"])
out = run_main(["--dead-all"]); chk("--dead-all", len(REC["saved"]) == n and all("__dead.png" in s for s in REC["saved"]))
out = run_main(["--downed-all"]); chk("--downed-all", len(REC["saved"]) == n and all("__downed.png" in s for s in REC["saved"]))
chk("dead/downed saved under their own dirs", REC["saved"][0].split("/")[-2] == "units_downed", REC["saved"][0])
out = run_main(["enemy_grunt__dead", "player_medic"], env="2")
chk("explicit keys used", [os.path.basename(s) for s in REC["saved"]] == ["enemy_grunt__dead.png", "player_medic__idle.png"], REC["saved"])
chk("SEED_OFFSET=2 -> 7000+i+202", [s for _, s in REC["gen"]] == [7202, 7203], REC["gen"])
import runpy
REC["saved"].clear()
sys.argv = ["gen_from_brief.py", "enemy_grunt"]
buf = io.StringIO()
with contextlib.redirect_stdout(buf): runpy.run_path(os.path.join(ART, "gen_from_brief.py"), run_name="__main__")
chk("__main__ guard runs main() (stubbed torch)", len(REC["saved"]) == 1 and "DONE" in buf.getvalue(), buf.getvalue())
PY

# ------------------------------------------------------------------- pixelize3
run_driver pix <<PY
$COMMON
import numpy as np, contextlib, io
from PIL import Image, ImageDraw
src = os.path.join(WORK, "raw"); os.makedirs(src, exist_ok=True)
def gray_bg(w=128, h=128, c=(120, 125, 130)):
    return Image.new("RGB", (w, h), c)
# sprite: red body, an enclosed bg-coloured pocket, low-sat gray "shadow" at the feet
sp = gray_bg(); d = ImageDraw.Draw(sp)
d.rectangle((40, 20, 90, 100), fill=(200, 40, 40))
d.rectangle((60, 40, 70, 50), fill=(120, 125, 130))          # enclosed pocket
d.rectangle((40, 95, 90, 100), fill=(150, 150, 150))         # shadow-ish gray in bottom band
sp.save(os.path.join(src, "unit_sprite.png"))
gray_bg().save(os.path.join(src, "blank_bg.png"))            # everything is background -> empty sprite
busy = gray_bg(); bd = ImageDraw.Draw(busy)
for (x, y), c in zip(((0, 0), (112, 0), (0, 112), (112, 112)), ((250, 0, 0), (0, 250, 0), (0, 0, 250), (250, 250, 250))): bd.rectangle((x, y, x + 15, y + 15), fill=c)
busy.save(os.path.join(src, "busy.png"))   # differently coloured corners -> spread > 45 -> tile
Image.fromarray(np.zeros((128, 128, 3), dtype=np.uint8) + 100, "RGB").save(os.path.join(src, "floor_tile.png"))   # name says tile
X = load("pixelize3", ["pixelize3.py", src])
chk("DST derived + created at import", X.DST == src + "_sprites3" and os.path.isdir(X.DST))
# helpers directly
im = Image.open(os.path.join(src, "unit_sprite.png")).convert("RGBA")
bg, spread = X.corner_stats(im); chk("corner_stats: uniform corners -> bg gray, spread 0", bg == (120, 125, 130) and spread == 0, (bg, spread))
bg2, spread2 = X.corner_stats(Image.open(os.path.join(src, "busy.png")).convert("RGBA")); chk("busy corners -> large spread", spread2 > 45, spread2)
k = X.key_bg(im, bg); a = np.array(k)[:, :, 3]
chk("key_bg removes bg-colour pixels, keeps the body", a[5, 5] == 0 and a[60, 50] == 255, (a[5, 5], a[60, 50]))
fk = np.array(X.floodkey(im)); chk("floodkey: bg transparent, body opaque", fk[2, 2, 3] == 0 and fk[60, 50, 3] == 255, (fk[2, 2, 3], fk[60, 50, 3]))
chk("floodkey: enclosed pocket keyed out", fk[45, 65, 3] == 0, fk[45, 65])
chk("floodkey: gray shadow at feet stripped", fk[97, 60, 3] == 0, fk[97, 60])
allbg = X.floodkey(Image.open(os.path.join(src, "blank_bg.png")).convert("RGBA"))
chk("floodkey on pure background -> fully transparent", np.array(allbg)[:, :, 3].max() == 0)
# floodfill exception path is swallowed
_orig = X.ImageDraw.floodfill
def boom(*a, **kw): raise ValueError("boom")
X.ImageDraw.floodfill = boom
try:
    r = X.floodkey(im); chk("floodkey tolerates floodfill errors", r.size == im.size)
finally:
    X.ImageDraw.floodfill = _orig
ac = X.autocrop_square(X.floodkey(im)); chk("autocrop_square -> square around content", ac.size[0] == ac.size[1] and ac.size[0] < 128, ac.size)
emp = X.autocrop_square(Image.new("RGBA", (40, 20), (0, 0, 0, 0))); chk("autocrop of empty image pads to square without crop", emp.size == (40, 40), emp.size)
q = X.quant(ac, 32, keep_alpha=True); chk("quant keeps alpha, target grid", q.size == (32, 32) and q.mode == "RGBA" and np.array(q)[:, :, 3].min() == 0)
q = X.quant(ac, 16, keep_alpha=False); chk("quant without alpha is opaque", np.array(q)[:, :, 3].min() == 255)
q = X.quant(Image.new("RGB", (40, 40), (10, 200, 10)), 8, keep_alpha=True); chk("quant of non-RGBA input gets a solid alpha", np.array(q)[:, :, 3].min() == 255)
# main(): classify sprite vs tile, emit @64/@48/@32 + previews
buf = io.StringIO()
with contextlib.redirect_stdout(buf): X.main()
out = buf.getvalue()
chk("main lists 4 raw files", "4 raw ->" in out and out.rstrip().endswith("DONE"), out)
chk("sprite classified as sprite", "unit_sprite" in out and "sprite" in [l.split()[-1] for l in out.splitlines() if "unit_sprite" in l], out)
chk("busy + 'tile'-named files classified TILE", all(l.rstrip().endswith("TILE") for l in out.splitlines() if "busy" in l or "floor_tile" in l), out)
for name in ("unit_sprite", "busy", "floor_tile", "blank_bg"):
    for g in (64, 48, 32):
        chk("outputs for %s@%d" % (name, g), os.path.exists(os.path.join(X.DST, "%s@%d.png" % (name, g))) and os.path.exists(os.path.join(X.DST, "%s@%d_preview.png" % (name, g))))
chk("preview is 4x nearest", Image.open(os.path.join(X.DST, "unit_sprite@32_preview.png")).size == (128, 128))
chk("tile output stays fully opaque", np.array(Image.open(os.path.join(X.DST, "busy@64.png")).convert("RGBA"))[:, :, 3].min() == 255)
chk("sprite output has transparency", np.array(Image.open(os.path.join(X.DST, "unit_sprite@64.png")).convert("RGBA"))[:, :, 3].min() == 0)
import runpy
src2 = os.path.join(WORK, "raw2"); os.makedirs(src2, exist_ok=True); gray_bg(32, 32).save(os.path.join(src2, "one.png"))
sys.argv = ["pixelize3.py", src2]
buf = io.StringIO()
with contextlib.redirect_stdout(buf): runpy.run_path(os.path.join(ART, "pixelize3.py"), run_name="__main__")
chk("__main__ guard runs main()", "1 raw ->" in buf.getvalue() and os.path.exists(os.path.join(src2 + "_sprites3", "one@32.png")), buf.getvalue())
# default SRC when argv has no path is the hardcoded comfy dir: verify the expression only (do NOT import with it: it would mkdir there)
import re
srcline = open(os.path.join(ART, "pixelize3.py")).read()
chk("default SRC is the style_tests dir (unexecuted, by design)", "style_tests" in srcline)
PY

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
