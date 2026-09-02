#!/usr/bin/env python3
"""CONSISTENCY-first pose generation (art pipeline, 2026-09-02 rework).

The #1 problem: generating each pose from an independent text prompt produced a
DIFFERENT character every time (colors/proportions/style drift). Fix: derive
attack / downed / dead FROM each unit's own canonical idle via SDXL **img2img** —
the idle's pixels are the starting point, so identity carries across poses; the
text prompt + a tuned denoise strength only push the POSE.

Strength is per-pose: attack keeps most of the idle (small change); downed/dead
change more (to lie the body down) but still anchor to the idle's palette + build.

Idle source = the 1024 gray-bg idle render (out/units_ns or out/units_brief). Output
is a gray-bg render per pose; the normal pixelize3 + art_qa_gate stages key + gate it.

Usage:
  gen_pose_from_idle.py <unit>__attack <unit>__downed ...   # specific
  gen_pose_from_idle.py --unit player_trooper               # all 3 poses for a unit
"""
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
BRIEFS = json.load(open(os.path.join(HERE, "art_reference_briefs.json")))
sys.path.insert(0, HERE)
from gen_from_brief import build_prompt, CKPT, LORA  # reuse the brief-driven prompts

OUTBASE = "/run/media/mhintermeister/secondary_drive1/comfy/out"
IDLE_DIRS = [f"{OUTBASE}/units_ns", f"{OUTBASE}/units_brief"]  # 1024 gray-bg idles
# img2img denoise per pose: lower = closer to the idle (more consistent, less pose change)
STRENGTH = {"attack": 0.52, "downed": 0.66, "dead": 0.70}

def out_dir(pose):
    d = f"{OUTBASE}/units_{pose}"
    os.makedirs(d, exist_ok=True)
    return d

def find_idle(unit_key):
    for d in IDLE_DIRS:
        p = os.path.join(d, f"{unit_key}__idle.png")
        if os.path.exists(p):
            return p
    return None

def main():
    from PIL import Image
    import torch
    from diffusers import StableDiffusionXLImg2ImgPipeline

    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--unit" in sys.argv:
        u = sys.argv[sys.argv.index("--unit") + 1]
        keys = [f"{u}__attack", f"{u}__downed", f"{u}__dead"]
    else:
        keys = args
    if not keys:
        keys = [f"{u}__{p}" for u in BRIEFS["units"] for p in ("attack", "downed", "dead")]

    print(f"img2img pose-from-idle for {len(keys)} target(s)...", flush=True)
    pipe = StableDiffusionXLImg2ImgPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.15)
    pipe.set_progress_bar_config(disable=True)
    seed_off = int(os.environ.get("SEED_OFFSET", "0"))

    for i, key in enumerate(keys):
        unit_key, pose = key.rsplit("__", 1)
        idle_p = find_idle(unit_key)
        if idle_p is None:
            print(f"[skip] {key}: no idle base found in {IDLE_DIRS}", flush=True)
            continue
        init = Image.open(idle_p).convert("RGB").resize((1024, 1024), Image.LANCZOS)
        name, prompt, neg = build_prompt(key)
        g = torch.Generator("cuda").manual_seed(9000 + i + seed_off * 131)
        img = pipe(prompt=prompt, image=init, strength=STRENGTH.get(pose, 0.6),
                   negative_prompt=neg, num_inference_steps=44, guidance_scale=7.0,
                   generator=g).images[0]
        img.save(os.path.join(out_dir(pose), name))
        print(f"[{i+1}/{len(keys)}] {name}  (str={STRENGTH.get(pose,0.6)}, base={os.path.basename(idle_p)})", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
