#!/usr/bin/env python3
"""A/B/C model comparison, candidate: Z-Image-Turbo (Tongyi-MAI/Alibaba, 6B,
Apache 2.0, ungated). Run in the dedicated .venv (diffusers installed from
git source - Z-Image support isn't in a pip release yet as of 2026-09).
"""
import os, sys, torch
from diffusers import ZImagePipeline

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_eval_prompts import PROMPTS  # noqa: E402

MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/z-image-turbo"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/model_eval/z_image_turbo"


def main():
    os.makedirs(OUT, exist_ok=True)
    print("loading Z-Image-Turbo...", flush=True)
    pipe = ZImagePipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16, low_cpu_mem_usage=False)
    pipe.to("cuda")
    for p in PROMPTS:
        g = torch.Generator("cuda").manual_seed(42)
        img = pipe(
            prompt=p["text"],
            height=1024,
            width=1024,
            num_inference_steps=9,
            guidance_scale=0.0,
            generator=g,
        ).images[0]
        img.save(f"{OUT}/{p['key']}.png")
        print(f"wrote {p['key']}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
