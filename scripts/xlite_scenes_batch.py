#!/usr/bin/env python3
"""xlite SCENE / background art (the gap the sprite batch didn't cover): a
homescreen/title illustration, an in-battle backdrop, a mission-hub background,
and a generic menu backdrop. These are full pixel-art ILLUSTRATIONS (not 48px
sprites) — rendered wide, kept opaque (no alpha key), and lightly pixelized to
match the game's aesthetic. Two outputs per scene:
  - <key>__raw.png  : the full 1344x768 render (crisp)
  - <key>.png       : 672x384, 32-color quantized (pixel-art, drop-in background)
Run in the ComfyUI venv, GPU required (maintenance window).
"""
import os, torch
from diffusers import StableDiffusionXLPipeline
from PIL import Image

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/scenes"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

# Slightly softer LoRA than the sprite batch (1.0 vs 1.2) so scenes keep depth and
# don't over-blockify; still clearly pixel art to match the roster.
STYLE = "pixel art, vibrant saturated colors, high contrast, detailed scene, arcade game background"
NEG = ("blurry, jpeg artifacts, photo, realistic, 3d render, text, words, letters, "
       "watermark, logo, signature, ui, hud, health bar, characters in foreground, "
       "close-up face, frame, border")

# (key, subject) — wide establishing backdrops, empty foreground so game UI/units
# read on top of them.
SCENES = [
  ("bg_title",  "epic sci-fi title screen, alien warships descending over a futuristic human city skyline at dusk, dramatic glowing sky, wide cinematic establishing shot, empty foreground"),
  ("bg_battle", "distant alien battlefield horizon, ruined sci-fi structures under a glowing alien sky, atmospheric moody backdrop, wide, empty flat foreground"),
  ("bg_hub",    "interior of a sci-fi military command center and barracks, glowing wall screens and equipment lockers, warm ambient lighting, empty room, wide shot"),
  ("bg_menu",   "dark sci-fi brushed-metal panel wall with subtle glowing blue circuitry lines, minimal clean seamless backdrop, evenly lit"),
]

def gen(pipe, prompt, seed):
    g = torch.Generator("cuda").manual_seed(seed)
    return pipe(prompt=f"{STYLE}, {prompt}", negative_prompt=NEG,
                num_inference_steps=34, guidance_scale=7.0,
                height=768, width=1344, generator=g).images[0]

def post(img, w=672, h=384, colors=32):
    small = img.resize((w, h), Image.LANCZOS)
    return small.quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")

def main():
    print("loading SDXL + LoRA (scenes)...", flush=True)
    t2i = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    t2i.load_lora_weights(LORA); t2i.fuse_lora(lora_scale=1.0)
    t2i.set_progress_bar_config(disable=True)
    n = 0
    for key, subj in SCENES:
        img = gen(t2i, subj, seed=abs(hash(key)) % 100000)
        img.save(f"{OUT}/{key}__raw.png")
        post(img).save(f"{OUT}/{key}.png")
        n += 1
        print(f"[{n}] {key}", flush=True)
    print(f"DONE {n} scenes -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
