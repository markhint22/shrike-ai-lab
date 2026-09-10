#!/usr/bin/env python3
"""Art pipeline orchestrator (stages 2-4 with the auto-reject loop). For a given
role (dead / downed / idle / object), it: generates from the reference briefs ->
pixelizes (isolate) -> runs the QA gate -> RE-ROLLS only the sprites that fail,
with a fresh seed, up to N passes. Nothing that fails QA is kept. This is the
'design with no background + send back for edits if wrong' loop the user asked for.

Runs on the server (venv has torch/PIL/numpy). Usage:
  art_pipeline_run.py --role dead   [--passes 3]
"""
import os, sys, glob, subprocess
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_qa_gate, json
BRIEFS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "art_reference_briefs.json")))

PY = sys.executable
HERE = os.path.dirname(os.path.abspath(__file__))
OUTBASE = "/run/media/mhintermeister/secondary_drive1/comfy/out"

def qa_failures(sprite_dir, role):
    fails = []
    for f in sorted(glob.glob(f"{sprite_dir}/*@64.png")):
        res = art_qa_gate.inspect(np.array(Image.open(f).convert("RGBA")), role)
        if not res["ok"]:
            fails.append((os.path.basename(f).split("@")[0], res["reasons"]))
    return fails

def main():
    role = sys.argv[sys.argv.index("--role") + 1]
    passes = int(sys.argv[sys.argv.index("--passes") + 1]) if "--passes" in sys.argv else 3
    raw = f"{OUTBASE}/units_{role}"
    spr = f"{raw}_sprites3"
    keys = [f"{u}__{role}" for u in BRIEFS["units"].keys()]
    last_fails = []
    for p in range(passes):
        print(f"=== {role} PASS {p+1}/{passes}: generating {len(keys)} ===", flush=True)
        env = dict(os.environ, SEED_OFFSET=str(p))
        subprocess.run([PY, f"{HERE}/gen_from_brief.py", *keys], env=env, check=False)
        subprocess.run([PY, f"{HERE}/pixelize3.py", raw], check=False)
        last_fails = qa_failures(spr, role)
        print(f"[QA {role}] {len(last_fails)} fail after pass {p+1}", flush=True)
        for fn, rs in last_fails:
            print(f"   FAIL {fn}: {'; '.join(rs)}", flush=True)
        if not last_fails:
            print(f"[QA {role}] ALL PASS", flush=True)
            break
        keys = [fn for fn, _ in last_fails]  # re-roll only the failures next pass
    if last_fails:
        print(f"[QA {role}] {len(last_fails)} still failing after {passes} passes (flagged): "
              + ", ".join(fn for fn, _ in last_fails), flush=True)
    print(f"=== {role} PIPELINE DONE ===", flush=True)

if __name__ == "__main__":
    main()
