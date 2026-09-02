#!/usr/bin/env python3
"""Generate sprites FROM the reference briefs (art pipeline Step 0 — see
docs/art/REFERENCE_RESEARCH_STEP.md). Every prompt is composed from
scripts/art_reference_briefs.json; nothing is hand-written here. This is the
mechanism that makes "look up what it looks like, THEN generate" enforceable.

Usage:
  gen_from_brief.py                      # all live unit sprites
  gen_from_brief.py enemy_grunt__dead    # one dead sprite
  gen_from_brief.py --dead-all           # a dead sprite for every unit
  gen_from_brief.py enemy_grunt player_medic   # specific live keys

A '<key>__dead' target composes the base unit's subject + family corpse brief
into a distinct, flattened, ichor-pooled corpse — the fix for "the dead alien
looks like a live green blob tipped over".
"""
import os, sys, json, torch
from diffusers import StableDiffusionXLPipeline

HERE = os.path.dirname(os.path.abspath(__file__))
BRIEFS = json.load(open(os.path.join(HERE, "art_reference_briefs.json")))
C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

def out_dir(dead):
    d = "/run/media/mhintermeister/secondary_drive1/comfy/out/" + ("units_dead" if dead else "units_brief")
    os.makedirs(d, exist_ok=True)
    return d

def build_prompt(key):
    """Return (out_name, prompt, negative). key may be '<unit>' or '<unit>__dead'."""
    dead = key.endswith("__dead")
    unit_key = key[:-6] if dead else key
    u = BRIEFS["units"][unit_key]
    style = BRIEFS["style"]
    base_neg = BRIEFS["base_negatives"]
    if dead:
        fam = BRIEFS["corpse_by_family"][u["family"]]
        feats = ", ".join(fam["key_features"])
        prompt = f"{style}, a dead {u['subject']}, {feats}, {BRIEFS['framing_dead']}"
        neg = f"{base_neg}, {fam['negatives']}"
        name = f"{unit_key}__dead.png"
    else:
        feats = ", ".join(u.get("key_features", []))
        prompt = f"{style}, {u['subject']}, {feats}, {BRIEFS['framing_live']}"
        neg = f"{base_neg}, {BRIEFS['live_negatives']}"
        name = f"{unit_key}__idle.png"
    return name, prompt, neg

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    if "--dead-all" in flags:
        keys = [f"{k}__dead" for k in BRIEFS["units"].keys()]
    elif args:
        keys = args
    else:
        keys = list(BRIEFS["units"].keys())  # all live idles

    print(f"loading SDXL + LoRA for {len(keys)} target(s)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.15)
    pipe.set_progress_bar_config(disable=True)
    for i, key in enumerate(keys):
        name, prompt, neg = build_prompt(key)
        dead = key.endswith("__dead")
        g = torch.Generator("cuda").manual_seed(7000 + i)
        img = pipe(prompt=prompt, negative_prompt=neg, num_inference_steps=40,
                   guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
        img.save(os.path.join(out_dir(dead), name))
        print(f"[{i+1}/{len(keys)}] {name}\n     {prompt[:120]}...", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
