#!/usr/bin/env python3
"""Generate xlite pixel-art STYLE TESTS: a few looks for the user to choose from,
before mass-generating. Uses the ComfyUI-downloaded SDXL base + Pixel Art XL LoRA via
diffusers (simpler to script headless than a ComfyUI API graph). Each subject is
rendered in several distinct style directions on a flat chroma background; the
companion post-processor snaps them to true 16x16 / 32x32 with a limited palette + alpha.

Run inside the ComfyUI venv (has torch). GPU required -> maintenance window only.
"""
import os, itertools, torch
from diffusers import StableDiffusionXLPipeline

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/style_tests"
os.makedirs(OUT, exist_ok=True)

CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

# Chroma background keeps the subject isolatable for clean alpha in post.
BG = "solid flat chroma green background"
NEG = ("blurry, jpeg artifacts, gradient, soft shading, antialiased, photo, 3d render, "
       "text, watermark, multiple objects, cropped")

# Subjects that map to the game's real needs (units, terrain, UI/tech icon).
SUBJECTS = {
    "unit_soldier": "a single sci-fi tactical soldier trooper standing, front view, game character sprite",
    "unit_alien":   "a single hostile alien creature enemy, front view, game character sprite",
    "tile_floor":   "a seamless top-down metal floor terrain tile, tactical grid",
    "icon_tech":    "a single research tech-tree icon of a microchip, game UI icon",
}

# Distinct STYLE directions to choose between.
STYLES = {
    "A_clean16":   "pixel art, 16-bit, clean bold outlines, limited palette, crisp",
    "B_gritty":    "pixel art, muted desaturated palette, dark sci-fi, dithering, gritty",
    "C_vibrant":   "pixel art, vibrant saturated colors, high contrast, arcade, no outline",
    "D_minimal":   "pixel art, minimal 8-color palette, flat, simple shapes, retro 8-bit",
}

def main():
    print("loading SDXL + Pixel Art XL LoRA ...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA)
    pipe.fuse_lora(lora_scale=1.2)
    pipe.set_progress_bar_config(disable=True)
    g = torch.Generator("cuda").manual_seed(7)
    n = 0
    for (skey, subj), (stkey, style) in itertools.product(SUBJECTS.items(), STYLES.items()):
        prompt = f"{style}, {subj}, {BG}, centered, single sprite"
        img = pipe(prompt=prompt, negative_prompt=NEG, num_inference_steps=28,
                   guidance_scale=7.0, height=1024, width=1024, generator=g).images[0]
        fn = f"{OUT}/{skey}__{stkey}.png"
        img.save(fn); n += 1
        print(f"[{n}] {fn}", flush=True)
    print(f"DONE {n} style tests -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
