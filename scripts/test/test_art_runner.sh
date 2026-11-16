#!/usr/bin/env bash
# Regression: art_runner.py (art/animation queue runner). Everything GPU/network is stubbed: torch + diffusers are fake
# modules injected into sys.modules, curl is a stub first on PATH, HOME is a temp dir. PIL is real (pixelize/alpha is
# exercised for real).  The harness prints "OK label" / "FAIL label" lines which this wrapper counts.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT=""; for c in "$HERE/../../art_runner.py" "$HERE/../art_runner.py" "$HERE/art_runner.py"; do [ -f "$c" ] && { SUT="$c"; break; }; done
[ -n "$SUT" ] || { echo "art_runner.py not found"; exit 2; }
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
python3 -c 'import PIL' 2>/dev/null || { echo "PIL missing - cannot test"; exit 2; }
safe_set_sandbox_home "$T" || exit 1; mkdir -p "$HOME/overnight-queue" "$T/bin"
export PYTHONDONTWRITEBYTECODE=1   # run the REAL file in place (coverage attribution); never write __pycache__ into the tree
# curl stub: records args, succeeds (or fails when CURL_FAIL=1)
cat > "$T/bin/curl" <<'C'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"; [ "${CURL_FAIL:-0}" = 1 ] && exit 22; exit 0
C
chmod +x "$T/bin/curl"; export CURL_LOG="$T/curl.log"; : > "$CURL_LOG"

# ---- CLI: no queue file / empty queue -> graceful exit 0 (nothing imported from torch) ----
out="$(PATH="$T/bin:$PATH" python3 "$SUT" 2>&1)"; rc=$?
ok "CLI, no queue file -> rc 0 + 'queue empty'" "$([ $rc = 0 ] && echo "$out" | grep -q 'art queue empty' && echo 1 || echo 0)"
printf '# header only\n- [x] (staged for review) [unit] old — done already\n' > "$HOME/overnight-queue/art_queue.md"
out="$(PATH="$T/bin:$PATH" python3 "$SUT" 2>&1)"; rc=$?
ok "CLI, only done items -> rc 0 + 'queue empty'" "$([ $rc = 0 ] && echo "$out" | grep -q 'art queue empty' && echo 1 || echo 0)"
ok "CLI empty run sends no ntfy" "$([ ! -s "$CURL_LOG" ] && echo 1 || echo 0)"

# ---- in-process harness ----
cat > "$T/harness.py" <<'PY'
import os, sys, types, io, contextlib, importlib
sys.path.insert(0, os.environ["SUTDIR"])
import art_runner as A
from PIL import Image
res = []
def chk(label, cond): res.append(("OK " if cond else "FAIL ") + label)

T = os.environ["TREE"]
A.QUEUE = os.path.join(T, "q.md")
A.STAGE = os.path.join(T, "stage")
A.POSES = os.path.join(T, "poses")

# -- parse_queue --
chk("parse_queue: missing file -> []", A.parse_queue() == [])
open(A.QUEUE, "w", encoding="utf-8").write("""# Art queue
<!-- a multi-line comment
- [ ] [unit] hidden — must not be parsed | seed:1
-->
<!-- single-line comment -->
- [ ] [unit] raider-a — rusty raider with shotgun | seed:4242
- [ ] [SPRITE] crate-1 - a hyphen-separated crate
- [x] (staged for review) [unit] done-one — already generated
- [ ]   [tile]   floor_b   —   cracked asphalt tile   |  seed:7
not a task line
- [ ] [icon] bad key! — has a bang so the key regexp must reject it
- [ ] [unit] raider-a — rusty raider with shotgun | seed:4242
""")
ts = A.parse_queue()
keys = [t["key"] for t in ts]
chk("parse_queue: multi-line comment skipped, [x] and junk ignored", keys == ["raider-a", "crate-1", "floor_b", "raider-a"])
chk("parse_queue: explicit seed parsed as int", ts[0]["seed"] == 4242 and ts[2]["seed"] == 7)
chk("parse_queue: prompt stripped of '| seed:' suffix", ts[0]["prompt"] == "rusty raider with shotgun" and ts[2]["prompt"] == "cracked asphalt tile")
chk("parse_queue: type lowercased, ASCII hyphen separator accepted", ts[1]["type"] == "sprite" and ts[1]["prompt"] == "a hyphen-separated crate")
chk("parse_queue: missing seed -> default in 1000..90999", 1000 <= ts[1]["seed"] < 91000)
chk("parse_queue: line_no/raw recorded", ts[0]["raw"].startswith("- [ ] [unit] raider-a") and A.parse_queue()[0]["line_no"] == ts[0]["line_no"])

# -- alert --
import subprocess
real_run = subprocess.run
A.TOPIC = "topic_xyz"
_saved_srv = os.environ.pop("NTFY_SERVER", None)   # 2026-11-02 (N5): the suite guard sets NTFY_SERVER to a closed port; the DEFAULT under test is the relay, never ntfy.sh
A.alert("Title A", "body text")
log = open(os.environ["CURL_LOG"]).read()
chk("alert: posts to the relay (default http://127.0.0.1:8099, never ntfy.sh) with title/tags/body", "http://127.0.0.1:8099/topic_xyz" in log and "ntfy.sh" not in log and "Title: Title A" in log and "Tags: art" in log and "body text" in log)
os.environ["NTFY_SERVER"] = "http://stub.test:1"; open(os.environ["CURL_LOG"], "w").close()
A.alert("Title B", "body b")
chk("alert: an explicit NTFY_SERVER is used as given", "http://stub.test:1/topic_xyz" in open(os.environ["CURL_LOG"]).read())
if _saved_srv is None: os.environ.pop("NTFY_SERVER", None)
else: os.environ["NTFY_SERVER"] = _saved_srv
def boom(*a, **k): raise OSError("no curl")
subprocess.run = boom
try:
    A.alert("t", "m"); chk("alert: swallows exec errors", True)
except Exception:
    chk("alert: swallows exec errors", False)
subprocess.run = real_run

# -- pixelize_and_alpha --
img = Image.new("RGB", (1024, 1024), (128, 128, 128))
for x in range(384, 640):
    for y in range(384, 640):
        img.putpixel((x, y), (200, 30, 30))
out = A.pixelize_and_alpha(img)
chk("pixelize: 64x64 RGBA", out.size == (64, 64) and out.mode == "RGBA")
chk("pixelize: corners (gray bg) become transparent", all(out.getpixel(p)[3] == 0 for p in [(0, 0), (63, 0), (0, 63), (63, 63)]))
chk("pixelize: subject stays opaque", out.getpixel((32, 32)) == (200, 30, 30, 255))
near = Image.new("RGB", (1024, 1024), (100, 100, 100))
for x in range(512, 1024):
    for y in range(1024):
        near.putpixel((x, y), (120, 110, 100))   # within the 28 threshold of the corner average -> also background
o2 = A.pixelize_and_alpha(near)
chk("pixelize: near-background colours thresholded out too", o2.getpixel((40, 32))[3] == 0)
chk("pixelize: accepts non-RGB input (L mode)", A.pixelize_and_alpha(Image.new("L", (256, 256), 90)).size == (64, 64))

# -- nearest_resize: the box's Pillow 12.1.1 raises SystemError on resize(NEAREST) (2026-11-15) --
def ref_nearest(im, w, h):
    iw, ih = im.size
    o = Image.new(im.mode, (w, h))
    for y in range(h):
        for x in range(w):
            o.putpixel((x, y), im.getpixel((min(iw - 1, ((2 * x + 1) * iw) // (2 * w)), min(ih - 1, ((2 * y + 1) * ih) // (2 * h)))))
    return o
def same(a, b): return a.size == b.size and a.mode == b.mode and list(a.getdata()) == list(b.getdata())
img4 = Image.new("RGB", (4, 4))
for i in range(16): img4.putpixel((i % 4, i // 4), (i * 15, 255 - i * 7, i))
_real_resize = Image.Image.resize
def _broken_resize(self, size, resample=None, *a, **k):
    if resample in (0, Image.Resampling.NEAREST): raise SystemError("<method 'resize' of 'ImagingCore' objects> returned NULL without setting an exception")
    return _real_resize(self, size, resample, *a, **k) if resample is not None else _real_resize(self, size, *a, **k)
Image.Image.resize = _broken_resize
try:
    try:
        img4.resize((8, 8), Image.NEAREST); chk("simulated stack raises SystemError on resize(NEAREST)", False)
    except SystemError:
        chk("simulated stack raises SystemError on resize(NEAREST)", True)
    for (w, h) in [(8, 8), (16, 16), (12, 12), (2, 2), (1, 1), (4, 4), (8, 16)]:
        chk(f"nearest_resize 4x4 -> {w}x{h} (broken stack): exact pixel equality with pure-python nearest", same(A.nearest_resize(img4, (w, h)), ref_nearest(img4, w, h)))
    big = Image.new("RGB", (64, 64))
    for i in range(64 * 64): big.putpixel((i % 64, i // 64), ((i * 7) % 256, (i * 13) % 256, (i * 3) % 256))
    chk("nearest_resize 64 -> 256 (broken stack) exact", same(A.nearest_resize(big, (256, 256)), ref_nearest(big, 256, 256)))
    chk("nearest_resize downscale 64 -> 16 (broken stack) exact", same(A.nearest_resize(big, (16, 16)), ref_nearest(big, 16, 16)))
    _odd = list(A.nearest_resize(big, (10, 10)).getdata()); _ref = list(ref_nearest(big, 10, 10).getdata())
    chk("nearest_resize odd ratio 64 -> 10 (broken stack): >=60% pixels equal (only exact-tie rows/cols may differ)", sum(1 for a, b in zip(_odd, _ref) if a == b) >= 60)
    lm = Image.new("L", (4, 4)); lm.putdata(list(range(16)))
    chk("nearest_resize L-mode (broken stack) exact", same(A.nearest_resize(lm, (8, 8)), ref_nearest(lm, 8, 8)))
    # second link broken too -> pure-python last resort
    _real_tf = Image.Image.transform
    def _broken_tf(self, *a, **k): raise SystemError("tf broken")
    Image.Image.transform = _broken_tf
    chk("nearest_resize: transform also broken -> pure-python fallback exact", same(A.nearest_resize(img4, (8, 8)), ref_nearest(img4, 8, 8)) and same(A.nearest_resize(img4, (3, 3)), ref_nearest(img4, 3, 3)))
    Image.Image.transform = _real_tf
    os.environ["OVN_ART_NEAREST_FALLBACK"] = "off"
    try:
        A.nearest_resize(img4, (8, 8)); chk("nearest_resize: OVN_ART_NEAREST_FALLBACK=off re-raises", False)
    except SystemError:
        chk("nearest_resize: OVN_ART_NEAREST_FALLBACK=off re-raises", True)
    del os.environ["OVN_ART_NEAREST_FALLBACK"]
    gimg = Image.new("RGB", (1024, 1024), (128, 128, 128))
    chk("pixelize_and_alpha works on the broken-NEAREST stack", A.pixelize_and_alpha(gimg).size == (64, 64))
finally:
    Image.Image.resize = _real_resize
chk("nearest_resize: healthy stack matches pure-python too", same(A.nearest_resize(img4, (8, 8)), ref_nearest(img4, 8, 8)))
import re as _re
_src = open(os.path.join(os.environ["SUTDIR"], "art_runner.py"), encoding="utf-8").read()
chk("art_runner.py: no bare resize(..., Image.NEAREST) call left", not _re.search(r"\.resize\([^)]*NEAREST", _src.split("def nearest_resize")[0] + _src.split("def pixelize_and_alpha")[1]))

# -- mark_done --
open(A.QUEUE, "w", encoding="utf-8").write("- [ ] [unit] a — one\n- [ ] [unit] b — two\n- [ ] [unit] a — one\nkeep me\n")
A.mark_done([{"raw": "- [ ] [unit] a — one"}, {"raw": "- [ ] [unit] not-there — x"}], A.STAGE)
got = open(A.QUEUE, encoding="utf-8").read().splitlines()
chk("mark_done: first matching line flipped to staged", got[0] == "- [x] (staged for review) [unit] a — one")
chk("mark_done: other/duplicate/unrelated lines untouched", got[1] == "- [ ] [unit] b — two" and got[2] == "- [ ] [unit] a — one" and got[3] == "keep me")
chk("mark_done: unknown raw line is a no-op (no crash)", len(got) == 4)

# -- main(): stub torch + diffusers, real PIL --
os.makedirs(A.POSES, exist_ok=True)
for p in A.UNIT_ORDER:
    Image.new("RGB", (64, 64), (0, 0, 0)).save(os.path.join(A.POSES, p + ".png"))
calls = {"pipe": [], "ip": [], "lora": 0, "fuse": None, "adapter": 0}
class Gen:
    def __init__(self, dev): self.dev = dev
    def manual_seed(self, s): self.seed = s; return self
torch = types.ModuleType("torch"); torch.float16 = "fp16"; torch.Generator = Gen
class R:
    def __init__(self): self.images = [Image.new("RGB", (1024, 1024), (128, 128, 128))]
class Pipe:
    def to(self, d): self.dev = d; return self
    def load_lora_weights(self, p): calls["lora"] += 1; calls["lora_path"] = p
    def fuse_lora(self, lora_scale): calls["fuse"] = lora_scale
    def load_ip_adapter(self, *a, **k): calls["adapter"] += 1
    def set_progress_bar_config(self, **k): pass
    def set_ip_adapter_scale(self, s): calls["ip"].append(s)
    def __call__(self, **kw):
        calls["pipe"].append(kw)
        if "explode-me" in kw["prompt"]: raise RuntimeError("CUDA out of memory")
        return R()
class CN:
    @staticmethod
    def from_pretrained(name, torch_dtype=None): return ("cn", name)
class SP:
    @staticmethod
    def from_single_file(ckpt, controlnet=None, torch_dtype=None): calls["ckpt"] = ckpt; return Pipe()
dif = types.ModuleType("diffusers"); dif.StableDiffusionXLControlNetPipeline = SP; dif.ControlNetModel = CN
sys.modules["torch"] = torch; sys.modules["diffusers"] = dif

open(A.QUEUE, "w", encoding="utf-8").write(
    "- [ ] [unit] hero — armoured scavenger | seed:11\n"
    "- [ ] [sprite] barrel — rusty barrel | seed:22\n"
    "- [ ] [unit] bad — explode-me mutant | seed:33\n")
alerts = []
A.alert = lambda t, m: alerts.append((t, m))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = A.main()
outp = buf.getvalue()
chk("main: returns 0", rc == 0)
chk("main: lists the 3 queued tasks", "art queue: 3 task(s): hero[unit], barrel[sprite], bad[unit]" in outp)
hero = sorted(os.listdir(os.path.join(A.STAGE, "hero")))
chk("main: unit task writes all 6 pose frames", hero == sorted(f"hero__{p}.png" for p in A.UNIT_ORDER))
chk("main: sprite task writes exactly 1 (idle) frame", os.listdir(os.path.join(A.STAGE, "barrel")) == ["barrel__idle.png"])
chk("main: failing task is reported FAILED and does not abort the batch", "FAILED bad: CUDA out of memory" in outp)
q = open(A.QUEUE, encoding="utf-8").read().splitlines()
chk("main: successful tasks marked staged in queue", q[0].startswith("- [x] (staged for review) [unit] hero") and q[1].startswith("- [x] (staged for review) [sprite] barrel"))
chk("main: failed task stays pending for retry", q[2].startswith("- [ ] [unit] bad"))
chk("main: ntfy summary sent once with frame/unit counts", len(alerts) == 1 and alerts[0][0] == "Art batch staged for review" and alerts[0][1].startswith("7 frames, 2 unit(s)"))
chk("main: DONE line reports frames + tasks", "DONE 7 frames for 2 task(s)" in outp)
frame = Image.open(os.path.join(A.STAGE, "hero", "hero__idle.png"))
chk("main: saved frames are 64x64 transparent-background PNGs", frame.size == (64, 64) and frame.convert("RGBA").getpixel((0, 0))[3] == 0)
chk("main: model setup performed once (lora+fuse 1.1, ip-adapter)", calls["lora"] == 1 and calls["fuse"] == 1.1 and calls["adapter"] == 1 and calls["ckpt"] == A.CKPT)
chk("main: first frame of each task uses ip scale 0.0", calls["ip"][0] == 0.0)
chk("main: per-pose ip scales applied (walk .55, attack .5, hit .4, death .2)", [0.55, 0.55, 0.5, 0.4, 0.2] == calls["ip"][1:6])
idle = calls["pipe"][0]
chk("main: idle prompt carries STYLE+desc+pose hint+bg; seed used", A.STYLE in idle["prompt"] and "armoured scavenger" in idle["prompt"] and A.POSE_HINT["idle"] in idle["prompt"] and A.BGC in idle["prompt"] and idle["generator"].seed == 11)
chk("main: negative prompt + 1024 px + 36 steps", idle["negative_prompt"] == A.NEG and idle["height"] == 1024 and idle["width"] == 1024 and idle["num_inference_steps"] == 36)
chk("main: later poses use conditioning 0.9 and idle frame as ip-adapter image", calls["pipe"][1]["controlnet_conditioning_scale"] == 0.9 and idle["controlnet_conditioning_scale"] == 0.85)

# main(): all tasks fail -> nothing marked, but summary still sent with 0 counts
open(A.QUEUE, "w", encoding="utf-8").write("- [ ] [unit] bad2 — explode-me again | seed:5\n")
alerts.clear()
with contextlib.redirect_stdout(io.StringIO()):
    rc = A.main()
chk("main: all-fail batch leaves queue untouched (no mark_done)", open(A.QUEUE, encoding="utf-8").read().startswith("- [ ] [unit] bad2"))
chk("main: all-fail batch still alerts with 0 frames", len(alerts) == 1 and alerts[0][1].startswith("0 frames, 0 unit(s)"))
print("\n".join(res))
PY
export TREE="$T" SUTDIR="$(dirname "$SUT")"
PATH="$T/bin:$PATH" python3 "$T/harness.py" > "$T/h.out" 2> "$T/h.err"; hrc=$?
while IFS= read -r ln; do case "$ln" in "OK "*) ok "${ln#OK }" 1;; "FAIL "*) ok "${ln#FAIL }" 0;; esac; done < "$T/h.out"
ok "harness ran to completion (rc 0, no traceback)" "$([ $hrc = 0 ] && ! grep -q Traceback "$T/h.err" && echo 1 || echo 0)"
[ $hrc = 0 ] || sed 's/^/    | /' "$T/h.err" | tail -15
echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
