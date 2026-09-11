#!/usr/bin/env python3
"""PROTOTYPE ONLY - validates the seamless-tiling technique (circular-padding
conv layers, the standard SD trick for wrap-around textures) before building
the full wall-tileset pipeline around it. Generates a handful of test tiles
for different materials and saves both the raw tile and a 3x3 self-tiled
composite so tiling quality can be checked visually before committing GPU
time to the full system."""
import os, torch
from diffusers import StableDiffusionXLPipeline
from PIL import Image

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/seamless_test"
os.makedirs(OUT, exist_ok=True)

def make_seamless(pipe, on=True):
    """Patch every Conv2d in the UNet+VAE to wrap (circular) instead of zero-pad.
    This makes the denoising process treat the canvas as toroidal, so the
    decoded image tiles seamlessly with itself when repeated - the standard
    technique for generating wallpaper/texture tiles with diffusion models."""
    targets = [pipe.vae, pipe.unet]
    mode = "circular" if on else "zeros"
    for target in targets:
        for module in target.modules():
            if isinstance(module, torch.nn.Conv2d):
                module.padding_mode = mode

MATERIALS = [
    ("concrete", "gray cracked concrete wall texture, exposed rebar, wasteland ruin"),
    ("brick", "red-brown crumbling old brick wall texture, wasteland ruin"),
    ("metal", "rusted brown corrugated metal sheeting texture, wasteland ruin"),
]

def main():
    print("loading SDXL + LoRA...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.2)
    pipe.set_progress_bar_config(disable=True)

    make_seamless(pipe, True)
    for key, prompt in MATERIALS:
        full = f"pixel art, {prompt}, seamless tileable texture, flat lighting"
        neg = "blurry, jpeg artifacts, text, watermark, 3d render, photo, object, character, seam, border, frame"
        g = torch.Generator("cuda").manual_seed(4242)
        img = pipe(prompt=full, negative_prompt=neg, num_inference_steps=32,
                   guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
        img.save(f"{OUT}/{key}_tile.png")
        # 3x3 self-tile composite to SEE whether seams vanish before trusting this.
        w, h = img.size
        composite = Image.new("RGB", (w * 3, h * 3))
        for tx in range(3):
            for ty in range(3):
                composite.paste(img, (tx * w, ty * h))
        composite.resize((w, h)).save(f"{OUT}/{key}_tile_3x3_check.png")
        print(f"wrote {key}", flush=True)
    make_seamless(pipe, False)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
