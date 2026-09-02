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
import os, sys, json
# NOTE: torch/diffusers are imported lazily inside main() so build_prompt() and the
# briefs are importable (and unit-testable) without a GPU / the heavy ML stack.

HERE = os.path.dirname(os.path.abspath(__file__))
BRIEFS = json.load(open(os.path.join(HERE, "art_reference_briefs.json")))
C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

def out_dir(key):
    sub = "units_dead" if key.endswith("__dead") else "units_downed" if key.endswith("__downed") else "units_brief"
    d = "/run/media/mhintermeister/secondary_drive1/comfy/out/" + sub
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
# Tight 2-4 word identity per unit for POSE prompts (dead/downed). Using the full
# brief subject blows past CLIP's 77-token window (test_pose_prompts_stay_short_for_clip)
# AND its "hunched/clawed/warrior/hulking" words cue an upright standing figure.
_POSE_SUBJ = {
    "player_trooper": "wasteland soldier",
    "player_heavy": "armored heavy soldier",
    "player_sniper": "hooded sniper",
    "player_medic": "medic with red cross",
    "enemy_grunt": "green mutant alien",
    "enemy_brute": "huge green mutant",
    "enemy_flyer": "winged mutant",
    "enemy_drone": "quadrotor drone",
    "enemy_elite": "chitin-armored alien",
    "enemy_raider": "spiked scrap raider",
    "enemy_shotgunner": "riot-armor raider",
    "enemy_shield": "shield raider",
    "enemy_minigunner": "minigun raider",
    "enemy_boss": "armored mutant warlord",
}

def build_prompt(key):
    """Return (out_name, prompt, negative). key may be '<unit>', '<unit>__dead' or
    '<unit>__downed'. Prompts front-loaded + short for CLIP's 77-token window. DEATH
    CANON: dead AND downed lie ON THEIR SIDE, crumpled (side view), NOT standing and
    NOT a tidy top-down laid-out body."""
    style = BRIEFS["style"]
    base_neg = BRIEFS["base_negatives"]
    for suffix, famkey, name_suf in (("__dead", "corpse_by_family", "dead"),
                                     ("__downed", "downed_by_family", "downed")):
        if key.endswith(suffix):
            unit_key = key[:-len(suffix)]
            u = BRIEFS["units"][unit_key]
            fam = BRIEFS[famkey][u["family"]]
            kind = _DEAD_KIND[u["family"]]
            core = _POSE_SUBJ.get(unit_key, _strip_article(u["subject"]))
            pool = _DEAD_POOL[u["family"]]
            # Kept SHORT + front-loaded: CLIP truncates at 77 tokens, so the critical
            # corpse cues lead and the whole prompt stays well under the limit.
            if name_suf == "dead":
                prompt = (f"pixel art, dead {kind} lying on its side, crumpled, "
                          f"limbs at odd angles, mouth open, {pool}, {core}, gray background")
            else:
                small = "sparks and loose wires" if u["family"] == "robot" else "small blood smear"
                prompt = (f"pixel art, wounded {kind} down on its side, collapsed clutching a wound, "
                          f"{small}, {core}, gray background")
            neg = (f"{base_neg}, {fam['negatives']}, standing, upright, front view, walking")
            return f"{unit_key}__{name_suf}.png", prompt, neg
    # live idle: subject + the 2 most identifying features + short framing (stay <77).
    u = BRIEFS["units"][key]
    feats = ", ".join(u.get("key_features", [])[:2])
    prompt = f"pixel art, {_strip_article(u['subject'])}, {feats}, full body centered, flat gray background, no shadow"
    neg = f"{base_neg}, {BRIEFS['live_negatives']}"
    return f"{key}__idle.png", prompt, neg

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    if "--dead-all" in flags:
        keys = [f"{k}__dead" for k in BRIEFS["units"].keys()]
    elif "--downed-all" in flags:
        keys = [f"{k}__downed" for k in BRIEFS["units"].keys()]
    elif args:
        keys = args
    else:
        keys = list(BRIEFS["units"].keys())  # all live idles

    import torch  # lazy — keeps build_prompt() importable without the ML stack
    from diffusers import StableDiffusionXLPipeline
    print(f"loading SDXL + LoRA for {len(keys)} target(s)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.15)
    pipe.set_progress_bar_config(disable=True)
    # SEED_OFFSET lets the QA loop re-roll a failed key with a fresh seed each pass.
    seed_off = int(os.environ.get("SEED_OFFSET", "0"))
    for i, key in enumerate(keys):
        name, prompt, neg = build_prompt(key)
        g = torch.Generator("cuda").manual_seed(7000 + i + seed_off * 101)
        img = pipe(prompt=prompt, negative_prompt=neg, num_inference_steps=40,
                   guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
        img.save(os.path.join(out_dir(key), name))
        print(f"[{i+1}/{len(keys)}] {name}\n     {prompt[:120]}...", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
