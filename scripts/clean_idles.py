#!/usr/bin/env python3
"""Clean, background-REMOVABLE idle sprites — the missing input for procedural_anim.
Root cause of the bad poses/backgrounds: long wasteland prompts made SDXL paint a
SCENE behind the character (and CLIP's 77-token limit clipped the 'flat background'
instruction), so the sprite couldn't be isolated. Fix: SHORT prompt + a flat MAGENTA
background (unlike any wasteland tone, so it keys out cleanly) + negatives that ban
scenery/ground/shadow. Character stays wasteland-flavored but concise.
"""
import os, torch
from diffusers import StableDiffusionXLPipeline

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/idles"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

STYLE = "pixel art, high contrast, bold clean shapes, full color"
BG = "full body, centered, plain solid flat gray background"   # neutral => no color bleed; short => not CLIP-clipped
NEG = ("background scenery, landscape, wall, room, floor, ground, shadow, purple tint, "
       "monochrome, blurry, jpeg artifacts, text, watermark, multiple, cropped, border, frame")

UNITS = [
  ("player_trooper", "a wasteland soldier in patched armor holding a rifle"),
  ("player_heavy",   "a heavy wasteland soldier in bulky armor with a big machine gun"),
  ("player_sniper",  "a wasteland sniper in a hood holding a long rifle"),
  ("player_medic",   "a wasteland medic in armor with a red cross holding a pistol"),
  ("enemy_grunt",    "a green mutant alien grunt with claws and red eyes"),
  ("enemy_brute",    "a huge mutant brute monster with big clawed arms"),
  ("enemy_flyer",    "a winged mutant flying creature with claws"),
  ("enemy_drone",    "a rusty flying robot drone with one glowing eye"),
]

def main():
    print("loading SDXL + LoRA (clean idles)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.15)
    pipe.set_progress_bar_config(disable=True)
    for i, (key, desc) in enumerate(UNITS):
        g = torch.Generator("cuda").manual_seed(1000 + i)
        img = pipe(prompt=f"{STYLE}, {desc}, {BG}", negative_prompt=NEG,
                   num_inference_steps=40, guidance_scale=7.5,
                   height=1024, width=1024, generator=g).images[0]
        img.save(f"{OUT}/{key}__idle.png")
        print(f"[{i+1}] {key}", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
