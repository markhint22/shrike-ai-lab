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

def _strip_article(s):
    for a in ("a ", "an ", "the "):
        if s.lower().startswith(a):
            return s[len(a):]
    return s

# CLIP only reads the first 77 tokens, so the SEMANTICALLY CRITICAL words must come
# FIRST and the whole prompt must stay short — otherwise the corpse cues get
# truncated and the model just draws a live unit (the exact bug we're fixing). Each
# family gives a TIGHT front-loaded corpse phrase (pool = the strongest 'dead' cue).
_DEAD_POOL = {"mutant": "green ichor pool", "robot": "oil pool and debris", "human": "dark blood pool"}
_DEAD_KIND = {"mutant": "mutant", "robot": "wrecked robot", "human": "body"}
# Stripped 2-3 word subjects for DEAD_STRONG re-rolls — the full briefs' "hunched",
# "clawed", "warrior", "hulking" words cue an upright standing figure.
_DEAD_STRONG_SUBJ = {
    "enemy_grunt": "green mutant alien",
    "enemy_boss": "big armored mutant",
    "enemy_brute": "huge green mutant",
    "player_heavy": "armored soldier",
    "enemy_shotgunner": "armored raider",
}

def build_prompt(key):
    """Return (out_name, prompt, negative). key may be '<unit>' or '<unit>__dead'.
    Prompts are front-loaded + short to survive CLIP's 77-token window."""
    dead = key.endswith("__dead")
    unit_key = key[:-6] if dead else key
    u = BRIEFS["units"][unit_key]
    style = BRIEFS["style"]
    base_neg = BRIEFS["base_negatives"]
    subj = _strip_article(u["subject"])
    if dead:
        fam = BRIEFS["corpse_by_family"][u["family"]]
        if os.environ.get("DEAD_STRONG"):
            # Re-roll mode for subjects whose 'armored warrior' prior kept drawing
            # them STANDING. Use an aggressive overhead-corpse framing + a stripped
            # 2-3 word subject (drop 'hunched/clawed/warrior' words that cue upright)
            # + hard anti-standing negatives.
            core = _DEAD_STRONG_SUBJ.get(unit_key, subj)
            prompt = (f"pixel art, dead {_DEAD_KIND[u['family']]} corpse sprawled flat on its back, "
                      f"aerial top-down view seen from directly overhead, limbs splayed wide, "
                      f"{_DEAD_POOL[u['family']]}, lifeless motionless, {core}, desaturated, flat gray background")
            neg = (f"{base_neg}, {fam['negatives']}, standing, upright, vertical, front view, "
                   f"facing viewer, portrait, walking, sitting, kneeling, alive, action pose")
        else:
            # critical corpse cues FIRST, then a trimmed subject, then minimal framing.
            prompt = (f"pixel art, dead {_DEAD_KIND[u['family']]} corpse lying flat on the ground, "
                      f"limbs splayed, {_DEAD_POOL[u['family']]}, top-down view, "
                      f"a dead {subj}, desaturated, flat gray background")
            neg = f"{base_neg}, {fam['negatives']}"
        name = f"{unit_key}__dead.png"
    else:
        # subject + the 2 most identifying features + short framing (stay under 77).
        feats = ", ".join(u.get("key_features", [])[:2])
        prompt = f"pixel art, {subj}, {feats}, full body centered, flat gray background, no shadow"
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
