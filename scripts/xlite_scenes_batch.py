#!/usr/bin/env python3
"""xlite SCENE / background art — WASTELAND theme (post-apocalyptic + ruined advanced
tech, everything damaged/worn). Multiple OPTIONS per screen so the user can pick.
Full pixel-art illustrations kept opaque; wide 1344x768 render + 672x384 pixelized.
Outputs per option:  <key>__optN__raw.png (crisp 1344x768) and <key>__optN.png (pixel).
Run in the ComfyUI venv, GPU required.
"""
import os, torch
from diffusers import StableDiffusionXLPipeline
from PIL import Image

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/scenes"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

OPTIONS = 3  # variants per background

STYLE = ("pixel art, high-contrast arcade game background, post-apocalyptic wasteland, "
         "ruined damaged worn, rusted wrecked technology, vibrant but gritty")
NEG = ("blurry, jpeg artifacts, photo, realistic, 3d render, text, words, letters, "
       "watermark, logo, signature, ui, hud, health bar, characters in foreground, "
       "close-up face, frame, border, clean, pristine, new")

SCENES = [
  ("bg_title",  "epic post-apocalyptic ruined city skyline at dusk, collapsed skyscrapers and wrecked alien warships, toxic hazy sky, scattered fires, wide cinematic establishing shot, empty foreground"),
  ("bg_battle", "ruined wasteland battlefield horizon, wrecked vehicles and collapsed rusted structures, toxic green haze and distant fires, gritty, wide, empty flat foreground"),
  ("bg_hub",    "interior of a scavenged wasteland survivor bunker base, patched walls and salvaged flickering tech screens, rusted lockers and crates, warm ambient light, empty room, wide shot"),
  ("bg_menu",   "dark rusted scavenged metal panel wall with cracked concrete and dim flickering salvaged circuitry, worn seamless backdrop, evenly lit"),
]

def gen(pipe, prompt, seed):
    g = torch.Generator("cuda").manual_seed(seed)
    return pipe(prompt=f"{STYLE}, {prompt}", negative_prompt=NEG,
                num_inference_steps=36, guidance_scale=7.0,
                height=768, width=1344, generator=g).images[0]

def post(img, w=672, h=384, colors=32):
    return img.resize((w, h), Image.LANCZOS).quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")

def main():
    print("loading SDXL + LoRA (scenes)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.0)
    pipe.set_progress_bar_config(disable=True)
    n = 0
    for key, subj in SCENES:
        for opt in range(1, OPTIONS + 1):
            seed = (abs(hash(key)) + opt * 7919) % 100000
            img = gen(pipe, subj, seed)
            img.save(f"{OUT}/{key}__opt{opt}__raw.png")
            post(img).save(f"{OUT}/{key}__opt{opt}.png")
            n += 1
            print(f"[{n}] {key} opt{opt}", flush=True)
    print(f"DONE {n} scene renders -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
