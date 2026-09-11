#!/usr/bin/env python3
"""A/B/C/D model comparison, candidate: FLUX.1-schnell (Black Forest Labs,
12B, Apache 2.0). Same shared prompt set as the other candidates
(model_eval_prompts.py). CPU-offloaded from the start (unlike the LLaDA
false-start, this is a standard, mature diffusers pipeline, not brand-new
custom code, so offloading is expected to just work) - the 12B transformer +
T5-XXL text encoder combined exceed 24GB loaded all at once in bf16.
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from model_eval_prompts import PROMPTS  # noqa: E402

MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/flux1-schnell"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/model_eval/flux_schnell"


def main():
    import torch
    from diffusers import FluxPipeline

    os.makedirs(OUT, exist_ok=True)
    print("loading FLUX.1-schnell (CPU-offloaded)...", flush=True)
    pipe = FluxPipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16)
    pipe.enable_model_cpu_offload()
    for p in PROMPTS:
        g = torch.Generator("cpu").manual_seed(42)
        img = pipe(
            prompt=p["text"],
            height=1024,
            width=1024,
            num_inference_steps=4,
            guidance_scale=0.0,
            max_sequence_length=256,
            generator=g,
        ).images[0]
        img.save(f"{OUT}/{p['key']}.png")
        print(f"wrote {p['key']}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
