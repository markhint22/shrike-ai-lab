#!/usr/bin/env python3
"""Generate the ruined-wasteland-city building/prop/road batch FROM the
reference brief (art pipeline Step 0 — see docs/art/CITY_PROPS_BRIEF.md and
scripts/city_reference_briefs.json). Every prompt is composed from that JSON;
nothing is hand-written here (same discipline as gen_from_brief.py).

Locked to match the EXISTING terrain assets exactly (verified by opening
crate.png/floor_metal.png, not just reading old prompts):
  - upright pieces (walls/vehicles/props): crate.png's iso pseudo-3D box
    angle, floodkey-isolated off a solid magenta background.
  - tile pieces (roads/sidewalks/door decals): floor_metal.png's flat
    top-down 2:1 diamond, full-frame opaque, filename carries 'tile_' so
    pixelize3.py classifies it correctly regardless of corner busyness.
Same base LoRA recipe as the ORIGINAL terrain batch (xlite_vibrant_batch.py)
that produced the assets already in the game, for maximum consistency.

Usage:
  gen_city_props.py                  # every module x variant, SEEDS_PER_VARIANT each
  gen_city_props.py wall_run_a        # just one module's variants
  SEEDS_PER_VARIANT=2 gen_city_props.py   # override seed count (default 3)
"""
import os, sys, json, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
BRIEF = json.load(open(os.path.join(HERE, "city_reference_briefs.json")))
C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/city_props"


def _seed_for(name: str) -> int:
    # Stable across runs (hash of the full name, which already bakes in
    # module/variant/seed-index, e.g. "wall_run_a__v0__s1") so re-running
    # this script reproduces the same images rather than re-rolling them.
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % 90000


def build_items(module_keys=None):
    """Return a list of (name, prompt, negative, render_style) tuples, one per
    (module, variant, seed). No GPU/torch needed - kept separate so this is
    importable/testable on its own (matches gen_from_brief.py's convention).

    Prompt formula is deliberately SHORT (~20-25 words): CLIP truncates at 77
    tokens, and the full brief's style/palette/view sentences (see
    CITY_PROPS_BRIEF.md) blow well past that if restated in every prompt -
    verified locally (build_items() is importable without a GPU specifically
    so this can be checked before ever touching the server). The palette/
    style are carried by the same fused pixel-art LoRA every existing terrain
    asset already uses, not by restating them in text. The one thing that
    MUST survive truncation is the background cue (magenta for upright
    pieces - the exact failure mode this avoids is a baked-in background
    that ruins the floodkey isolation), so it goes second, right after
    "pixel art" - never trailing.
    """
    base_neg = BRIEF["base_negatives"]
    seeds_per_variant = int(os.environ.get("SEEDS_PER_VARIANT", "3"))
    items = []
    for mod in BRIEF["modules"]:
        if module_keys and mod["key"] not in module_keys:
            continue
        upright = mod["render_style"] == "upright"
        neg = base_neg + (", " + BRIEF["upright_negatives"] if upright else "")
        for v_idx, variant in enumerate(mod["variants"]):
            if upright:
                # "single isolated object" front-loaded, right after the background
                # cue - the 2026-09-10 first-pass fix: without an explicit positive
                # single-object/bounded cue, SDXL rendered "wall"/"fence" subjects as
                # an infinite full-bleed material (no background left to key) and
                # round objects (drum, barricade) as a repeated tiled pattern. A ban
                # in the negatives alone (base_negatives already had "multiple
                # objects") was not enough - needed the positive framing too.
                # SECOND fix (still 2026-09-10): "magenta background" itself was
                # the next problem - even once bounded, several subjects painted
                # the MAGENTA onto their own material (pink rocks) while the actual
                # backdrop came out a plain gray. Switched to "gray background",
                # matching gen_from_brief.py's already-proven character-sprite
                # precedent ("flat gray background") - pixelize3.py's floodkey
                # auto-detects whatever color is actually in the corners, it never
                # required magenta specifically, so there's no isolation downside.
                prompt = f"pixel art, gray background, single isolated object, {mod['subject']}, {variant}, iso angle"
            else:
                prompt = f"pixel art, top-down floor tile, {mod['subject']}, {variant}"
            for seed_idx in range(seeds_per_variant):
                name = f"{mod['key']}__v{v_idx}__s{seed_idx}"
                items.append((name, prompt, neg, mod["render_style"]))
    return items


def main():
    module_keys = set(a for a in sys.argv[1:] if not a.startswith("--")) or None
    items = build_items(module_keys)
    os.makedirs(OUT, exist_ok=True)
    print(f"{len(items)} renders planned -> {OUT}", flush=True)

    import torch  # lazy - keeps build_items() importable/testable without the ML stack
    from diffusers import StableDiffusionXLPipeline
    print("loading SDXL + pixel-art LoRA...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA)
    pipe.fuse_lora(lora_scale=1.2)  # same recipe as the terrain assets already in the game
    pipe.set_progress_bar_config(disable=True)

    for i, (name, prompt, neg, _render_style) in enumerate(items):
        g = torch.Generator("cuda").manual_seed(_seed_for(name))
        img = pipe(prompt=prompt, negative_prompt=neg, num_inference_steps=32,
                   guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
        img.save(os.path.join(OUT, f"{name}.png"))
        print(f"[{i+1}/{len(items)}] {name}\n     {prompt[:120]}...", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
