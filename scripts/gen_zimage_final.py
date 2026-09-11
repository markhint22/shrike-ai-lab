#!/usr/bin/env python3
"""THE deliverable generator (2026-09-11): full sprite roster + terrain/prop
set through Z-Image-Turbo (the A/B/C winner - see docs/art/MODEL_EVAL.md),
reusing the EXISTING, already-researched brief files rather than redefining
subjects from scratch:
  - art_reference_briefs.json (units) -> every player/enemy sprite.
  - city_reference_briefs_v2.json (materials/fixed_props) -> wall materials
    + standalone cover props.
Two validated prompt formulas from the A/B/C eval, NOT the same formula for
both: sprites use the plain "pixel art, subject, features" phrasing that
already worked great; terrain/materials need the STRONGER style-anchor
("16-bit pixel art... NOT photorealistic, hard pixel edges") or Z-Image
drifts into a realistic/photographic style - confirmed by direct comparison,
not assumed.

Usage:
  gen_zimage_final.py sprites            # all 14 units
  gen_zimage_final.py terrain            # 5 wall materials + props + floors
  gen_zimage_final.py                    # everything
"""
import os, sys, json, hashlib
# torch/diffusers imported lazily inside main() so sprite_items()/terrain_items()
# stay importable/testable without the ML stack (matches gen_city_props.py's convention).

HERE = os.path.dirname(os.path.abspath(__file__))
UNITS_BRIEF = json.load(open(os.path.join(HERE, "art_reference_briefs.json")))
CITY_BRIEF = json.load(open(os.path.join(HERE, "city_reference_briefs_v2.json")))
MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/z-image-turbo"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/zimage_final"


def _seed_for(name):
    return int(hashlib.sha1(name.encode()).hexdigest(), 16) % 90000


def _strip_article(s):
    for a in ("a ", "an ", "the "):
        if s.lower().startswith(a):
            return s[len(a):]
    return s


def sprite_items():
    items = []
    for key, u in UNITS_BRIEF["units"].items():
        feats = ", ".join(u.get("key_features", [])[:2])
        prompt = f"pixel art, {_strip_article(u['subject'])}, {feats}, full body centered, flat gray background"
        items.append((f"sprite_{key}", prompt))
    return items


def terrain_items():
    items = []
    for mat in CITY_BRIEF["materials"]:
        prompt = (f"16-bit pixel art, blocky pixelated retro game texture, {mat['wall_prompt']}, "
                  f"NOT photorealistic, flat shading, hard pixel edges")
        items.append((f"wall_{mat['key']}", prompt))
    for tile in CITY_BRIEF["floor_tiles"]:
        variant = tile["variants"][0]
        prompt = (f"16-bit pixel art, blocky pixelated retro game texture, {tile['seamless_prompt']}, {variant}, "
                  f"NOT photorealistic, flat shading, hard pixel edges")
        items.append((f"floor_{tile['key']}", prompt))
    for prop in CITY_BRIEF.get("fixed_props", []):
        prompt = f"{prop['subject']}, {prop['variants'][0]}"
        items.append((f"prop_{prop['key']}", prompt))
    # A few extra standalone props from the earlier v1 brief that tested well
    # (car_wreck, dumpster, shipping_container) - same "single object" recipe.
    extra_props = [
        ("prop_car_wreck", "pixel art, a single wrecked sedan car, cover object, gray background"),
        ("prop_van_wreck", "pixel art, a single wrecked box van, tall cover object, gray background"),
        ("prop_dumpster", "pixel art, a single rusted metal dumpster, low cover object, gray background"),
        ("prop_shipping_container", "pixel art, a single rusted shipping container, tall cover object, gray background"),
        ("prop_concrete_barrier", "pixel art, a single gray concrete traffic barrier, low cover object, gray background"),
    ]
    items.extend(extra_props)
    return items


def main():
    targets = set(a for a in sys.argv[1:] if not a.startswith("--")) or {"sprites", "terrain"}
    items = []
    if "sprites" in targets:
        items += sprite_items()
    if "terrain" in targets:
        items += terrain_items()

    os.makedirs(OUT, exist_ok=True)
    print(f"{len(items)} items planned -> {OUT}", flush=True)

    import torch
    from diffusers import ZImagePipeline
    print("loading Z-Image-Turbo...", flush=True)
    pipe = ZImagePipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16, low_cpu_mem_usage=False)
    pipe.to("cuda")

    for i, (name, prompt) in enumerate(items):
        g = torch.Generator("cuda").manual_seed(_seed_for(name))
        img = pipe(prompt=prompt, height=1024, width=1024, num_inference_steps=9,
                   guidance_scale=0.0, generator=g).images[0]
        img.save(f"{OUT}/{name}.png")
        print(f"[{i+1}/{len(items)}] {name}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
