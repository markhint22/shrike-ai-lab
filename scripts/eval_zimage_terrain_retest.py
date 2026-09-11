#!/usr/bin/env python3
"""Quick follow-up test: Z-Image-Turbo's sprite/object results were excellent
but terrain/texture prompts drifted to a realistic/photographic style instead
of pixel art. Testing whether stronger style-anchoring in the prompt fixes it
before concluding terrain needs a different model."""
import os, torch
from diffusers import ZImagePipeline

MODEL = "/run/media/mhintermeister/secondary_drive1/comfy/models_eval/z-image-turbo"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/model_eval/z_image_turbo_retest"

PROMPTS = [
    ("wall_v2_stronger_anchor", "16-bit pixel art sprite, blocky pixelated retro game texture, "
     "gray cracked concrete wall, exposed rebar, wasteland ruin, NOT photorealistic, flat shading, hard pixel edges"),
    ("wall_v3_no_seamless_word", "pixel art, blocky retro game texture, gray cracked concrete wall with exposed rebar, wasteland ruin"),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    print("loading Z-Image-Turbo...", flush=True)
    pipe = ZImagePipeline.from_pretrained(MODEL, torch_dtype=torch.bfloat16, low_cpu_mem_usage=False)
    pipe.to("cuda")
    for key, text in PROMPTS:
        g = torch.Generator("cuda").manual_seed(42)
        img = pipe(prompt=text, height=1024, width=1024, num_inference_steps=9,
                   guidance_scale=0.0, generator=g).images[0]
        img.save(f"{OUT}/{key}.png")
        print(f"wrote {key}", flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
