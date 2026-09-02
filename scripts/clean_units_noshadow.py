#!/usr/bin/env python3
"""Regenerate unit idles with STRONG anti-shadow negatives — the previous batch baked a
cast shadow under the feet (opaque, can't be keyed out), which read as 'background at
the feet'. Same clean flat-gray-bg + short-prompt recipe; just ban the ground shadow.
"""
import os, torch
from diffusers import StableDiffusionXLPipeline

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/units_ns"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

STYLE = "pixel art, high contrast, bold clean shapes, full color"
BG = "full body, centered, floating on a plain solid flat gray background, no ground"
# hammer the shadow/ground so nothing bakes under the feet
NEG = ("cast shadow, drop shadow, ground shadow, shadow under feet, shadow, floor, ground, "
       "base, platform, standing surface, reflection, background scenery, wall, room, "
       "purple tint, monochrome, blurry, jpeg artifacts, text, watermark, multiple, cropped, border")

UNITS = [
  ("player_trooper", "a wasteland soldier in patched armor holding a rifle"),
  ("player_heavy",   "a heavy wasteland soldier in bulky armor with a big machine gun"),
  ("player_sniper",  "a wasteland sniper in a hood holding a long rifle"),
  ("player_medic",   "a wasteland medic in armor with a red cross holding a pistol"),
  ("enemy_grunt",    "a green mutant alien grunt with claws and red eyes"),
  ("enemy_brute",    "a huge mutant brute monster with big clawed arms"),
  ("enemy_flyer",    "a winged mutant flying creature with claws"),
  ("enemy_drone",    "a rusty flying robot drone with one glowing eye"),
  ("enemy_elite",    "an elite mutant alien warrior with chitin armor"),
  ("enemy_raider",   "a human wasteland raider in spiked scrap armor with a machete"),
  ("enemy_shotgunner","a wasteland raider in riot armor with a sawn-off shotgun"),
  ("enemy_shield",   "a heavy wasteland raider with a huge scrap riot shield"),
  ("enemy_minigunner","a hulking wasteland raider with a big minigun"),
  ("enemy_boss",     "a towering mutant wasteland warlord, heavily armored, glowing eyes"),
]

def main():
    print("loading SDXL + LoRA (units no-shadow)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.15)
    pipe.set_progress_bar_config(disable=True)
    for i, (key, subj) in enumerate(UNITS):
        g = torch.Generator("cuda").manual_seed(4000 + i)
        img = pipe(prompt=f"{STYLE}, {subj}, {BG}", negative_prompt=NEG,
                   num_inference_steps=40, guidance_scale=7.5, height=1024, width=1024,
                   generator=g).images[0]
        img.save(f"{OUT}/{key}__idle.png")
        print(f"[{i+1}] {key}", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
