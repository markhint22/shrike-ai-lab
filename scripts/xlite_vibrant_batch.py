#!/usr/bin/env python3
"""Full xlite asset batch in the chosen VIBRANT style at 48px. Generates:
  - a player + enemy UNIT ROSTER (idle poses)
  - POSE variants (walk/attack/hit/death) for the two primary units via img2img,
    seeded from their idle so the character stays consistent frame-to-frame
  - TERRAIN tiles
  - UI / TECH icons
Raw 1024 renders land in out/vibrant/ ; the PIL post-processor snaps them to 48px.
Run in the ComfyUI venv, GPU required (maintenance window).
"""
import os, torch
from diffusers import StableDiffusionXLPipeline, StableDiffusionXLImg2ImgPipeline

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/vibrant"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

STYLE = "pixel art, vibrant saturated colors, high contrast, arcade, bold clean shapes"
BGC   = "solid flat neutral gray background"
NEG   = ("blurry, jpeg artifacts, gradient, soft shading, photo, 3d render, text, "
         "watermark, multiple objects, cropped, frame, border")

# roster: (key, subject prompt) — idle sprites
UNITS = [
  ("player_trooper", "a sci-fi tactical soldier trooper standing at attention, front view"),
  ("player_heavy",   "a bulky heavy-armor soldier with a big gun, front view"),
  ("player_sniper",  "a lean scout sniper soldier with a long rifle, front view"),
  ("player_medic",   "a soldier medic with a red cross and med-pack, front view"),
  ("enemy_grunt",    "a small green alien grunt creature with big red eyes, front view"),
  ("enemy_brute",    "a hulking muscular alien brute monster, front view"),
  ("enemy_flyer",    "a winged flying alien creature with a barbed tail, front view"),
  ("enemy_drone",    "a floating robotic alien drone with a single eye, front view"),
]
# pose set for the two primaries, done via img2img off the idle
POSES = [("walk","mid-stride walking pose, one leg forward"),
         ("attack","aggressive attacking lunge pose, weapon raised"),
         ("hit","recoiling flinching hurt pose"),
         ("death","falling defeated collapsing pose")]
PRIMARIES = ["player_trooper", "enemy_grunt"]

TILES = [
  ("tile_floor_metal","seamless top-down metal grid floor tile"),
  ("tile_floor_tech","seamless top-down glowing tech circuit floor tile"),
  ("tile_wall","seamless top-down sci-fi metal wall tile"),
  ("tile_cover_crate","a single sci-fi supply crate for cover, top-down"),
  ("tile_hazard","seamless top-down glowing toxic hazard floor tile"),
  ("tile_rubble","seamless top-down cracked rubble debris floor tile"),
]
ICONS = [
  ("icon_chip","a research microchip tech icon"),
  ("icon_weapon","a laser rifle weapon upgrade icon"),
  ("icon_armor","a shield armor upgrade icon"),
  ("icon_medkit","a red medkit health icon"),
  ("icon_ammo","an ammo clip icon"),
  ("icon_move","a blue movement arrow icon"),
]

def gen(pipe, prompt, seed, steps=30):
    g = torch.Generator("cuda").manual_seed(seed)
    return pipe(prompt=f"{STYLE}, {prompt}, {BGC}, centered single sprite",
                negative_prompt=NEG, num_inference_steps=steps, guidance_scale=7.5,
                height=1024, width=1024, generator=g).images[0]

def main():
    print("loading SDXL + LoRA (txt2img + img2img)...", flush=True)
    t2i = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    t2i.load_lora_weights(LORA); t2i.fuse_lora(lora_scale=1.2)
    t2i.set_progress_bar_config(disable=True)
    i2i = StableDiffusionXLImg2ImgPipeline(**t2i.components)
    i2i.set_progress_bar_config(disable=True)
    idles, n = {}, 0
    for key, subj in UNITS + TILES + ICONS:
        img = gen(t2i, subj, seed=hash(key) % 100000)
        img.save(f"{OUT}/{key}__idle.png"); idles[key] = (img, subj); n += 1
        print(f"[{n}] {key}", flush=True)
    # pose frames via img2img off the idle (keeps the character consistent)
    for key in PRIMARIES:
        base, subj = idles[key]
        for pkey, pose in POSES:
            g = torch.Generator("cuda").manual_seed(hash(key+pkey) % 100000)
            out = i2i(prompt=f"{STYLE}, {subj}, {pose}, {BGC}, centered single sprite",
                      negative_prompt=NEG, image=base, strength=0.55,
                      num_inference_steps=30, guidance_scale=7.5, generator=g).images[0]
            out.save(f"{OUT}/{key}__{pkey}.png"); n += 1
            print(f"[{n}] {key} {pkey} (img2img)", flush=True)
    print(f"DONE {n} renders -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
