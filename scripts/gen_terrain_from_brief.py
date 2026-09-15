#!/usr/bin/env python3
"""Generate xlite RUINED-CITY terrain/object art FROM art_terrain_briefs.json
(art pipeline Step 0 - see docs/art/REFERENCE_RESEARCH_STEP.md). Every prompt
is composed from that brief file; nothing is hand-written here. Generates
MULTIPLE seed variants per key ("many options for each", user 2026-09-10) so
a human can pick a favorite per piece rather than getting one forced result.

Same checkpoint/LoRA/steps/resolution as every other xlite asset (gen_from_brief.py)
so this shares the SAME rendering recipe, not a separate style - consistency is
enforced by routing every prompt through the SAME shared style/framing/negative
strings in the brief (see its "_consistency_note").

Usage:
  gen_terrain_from_brief.py                    # every object + tile key, N_VARIANTS each
  gen_terrain_from_brief.py wall_concrete_straight door_wood_boarded   # specific keys
  gen_terrain_from_brief.py --variants 8        # override variant count
  gen_terrain_from_brief.py --objects-only
  gen_terrain_from_brief.py --tiles-only
"""
import os, sys, json
# NOTE: torch/diffusers imported lazily inside main() so build_prompt() and the
# briefs stay importable (and unit-testable) without a GPU / the heavy ML stack.

HERE = os.path.dirname(os.path.abspath(__file__))
BRIEFS = json.load(open(os.path.join(HERE, "art_terrain_briefs.json")))
C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/terrain"

DEFAULT_VARIANTS = 6

def _strip_article(s):
    for a in ("a ", "an ", "the "):
        if s.lower().startswith(a):
            return s[len(a):]
    return s

def build_prompt(key):
    """Return (kind, out_name_prefix, prompt, negative). kind is 'objects' or
    'tiles' - determines which shared framing/negatives apply AND whether the
    output filename carries a 'tile' marker (pixelize3.py classifies purely by
    that substring: busy/full-frame texture vs standalone keyed sprite)."""
    style = BRIEFS["style"]
    base_neg = BRIEFS["base_negatives"]
    if key in BRIEFS["objects"]:
        kind = "objects"
        entry = BRIEFS["objects"][key]
        framing = BRIEFS["framing_object"]
        neg_extra = BRIEFS["object_negatives"]
        name_prefix = key  # no "tile" substring -> pixelize3 treats as a keyed sprite
    elif key in BRIEFS["tiles"]:
        kind = "tiles"
        entry = BRIEFS["tiles"][key]
        framing = BRIEFS["framing_tile"]
        neg_extra = BRIEFS["tile_negatives"]
        name_prefix = f"{key}__tile"  # MUST contain "tile" -> pixelize3 keeps full frame
    else:
        raise KeyError(f"'{key}' is not in art_terrain_briefs.json objects or tiles")
    feats = ", ".join(entry.get("key_features", [])[:3])
    # Front-loaded + short for CLIP's 77-token window: style + subject + features
    # lead, framing/negatives trail - matches gen_from_brief.py's own discipline.
    prompt = f"{style}, {_strip_article(entry['subject'])}, {feats}, {framing}"
    neg = f"{base_neg}, {neg_extra}, {entry.get('negatives', '')}"
    return kind, name_prefix, prompt, neg

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    variants = DEFAULT_VARIANTS
    if "--variants" in sys.argv:
        variants = int(sys.argv[sys.argv.index("--variants") + 1])
    all_keys = list(BRIEFS["objects"].keys()) + list(BRIEFS["tiles"].keys())
    if args:
        keys = args
    elif "--objects-only" in flags:
        keys = list(BRIEFS["objects"].keys())
    elif "--tiles-only" in flags:
        keys = list(BRIEFS["tiles"].keys())
    else:
        keys = all_keys

    os.makedirs(OUT, exist_ok=True)
    import torch  # lazy - keeps build_prompt() importable without the ML stack
    from diffusers import StableDiffusionXLPipeline
    print(f"loading SDXL + LoRA for {len(keys)} key(s) x {variants} variant(s)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA)
    pipe.fuse_lora(lora_scale=1.15)
    pipe.set_progress_bar_config(disable=True)

    n = 0
    total = len(keys) * variants
    for key in keys:
        kind, name_prefix, prompt, neg = build_prompt(key)
        for v in range(variants):
            n += 1
            g = torch.Generator("cuda").manual_seed(9000 + hash(key) % 5000 + v * 101)
            img = pipe(prompt=prompt, negative_prompt=neg, num_inference_steps=40,
                       guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
            out_name = f"{name_prefix}__v{v+1}.png"
            img.save(os.path.join(OUT, out_name))
            print(f"[{n}/{total}] ({kind}) {out_name}\n     {prompt[:120]}...", flush=True)
    print(f"DONE {n} renders -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
