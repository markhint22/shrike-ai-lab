#!/usr/bin/env python3
"""A/B/C model comparison, baseline: the CURRENT production pipeline (SDXL
1.0 + pixel-art-xl LoRA, fused lora_scale=1.2 - identical recipe to every
existing xlite terrain/sprite asset). Same prompt set as the new candidates
(model_eval_prompts.py) for a fair comparison, run in the existing ComfyUI
venv (unmodified - this is the pipeline being defended/challenged, must not
touch its environment).
"""
import os, sys, torch
from diffusers import StableDiffusionXLPipeline

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_eval_prompts import PROMPTS  # noqa: E402

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/model_eval/sdxl_baseline"


def main():
    os.makedirs(OUT, exist_ok=True)
    print("loading SDXL + pixel-art LoRA (the current production baseline)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA)
    pipe.fuse_lora(lora_scale=1.2)
    pipe.set_progress_bar_config(disable=True)
    neg = "blurry, jpeg artifacts, text, watermark, 3d render, photo, multiple objects, cropped, frame, border"
    for p in PROMPTS:
        g = torch.Generator("cuda").manual_seed(42)
        img = pipe(prompt=p["text"], negative_prompt=neg, num_inference_steps=32,
                   guidance_scale=7.5, height=1024, width=1024, generator=g).images[0]
        img.save(f"{OUT}/{p['key']}.png")
        print(f"wrote {p['key']}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
