#!/usr/bin/env python3
"""A/B/C model comparison, candidate: LLaDA-Image-Turbo (inclusionAI, 6B,
Apache 2.0). Run in the dedicated .venv-llada (torch==2.8.0, diffusers==0.39.0,
transformers==4.57.6, per the model's own pinned requirements.txt - do NOT run
this in the shared ComfyUI venv, version conflicts).
"""
import os, sys, torch

REPO = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/LLaDA-Image-repo"
MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/llada-image-turbo"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/model_eval/llada_image_turbo"
sys.path.insert(0, REPO)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import LLaDAImagePipeline  # noqa: E402
from model_eval_prompts import PROMPTS  # noqa: E402


def main():
    os.makedirs(OUT, exist_ok=True)
    print("loading LLaDA-Image-Turbo (CPU-offloaded - the full pipeline, "
          "including its VLM text encoder, doesn't fit in 24GB loaded all at "
          "once on this card)...", flush=True)
    pipe = LLaDAImagePipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16, device="cpu")
    pipe.enable_model_cpu_offload()
    for p in PROMPTS:
        # CPU-offloaded pipeline expects a CPU generator (it internally moves
        # components to GPU per-step, but the pipeline's own reported device
        # stays CPU) - a cuda generator here raises a device-mismatch ValueError.
        g = torch.Generator(device="cpu").manual_seed(42)
        img = pipe(
            prompt=p["text"],
            generation_mode="text",
            height=1024,
            width=1024,
            num_inference_steps=4,
            guidance_scale=1.0,
            generator=g,
        ).images[0]
        img.save(f"{OUT}/{p['key']}.png")
        print(f"wrote {p['key']}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
