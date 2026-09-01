#!/usr/bin/env python3
"""AnimateDiff SD1.5 spike — the MATURE, reliable AnimateDiff (the SDXL beta adapter
was incompatible with our single-file stack: fp16 dtype error, fp32 OOM). SD1.5 runs
in fp16 at 512, 16 frames, low VRAM. Purely to answer 'does AnimateDiff give coherent
character motion?' — judge the gif before trusting it. No pixel LoRA yet (motion first).
"""
import os, torch
from diffusers import AnimateDiffPipeline, MotionAdapter, DDIMScheduler
from diffusers.utils import export_to_gif

OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/animatediff"
os.makedirs(OUT, exist_ok=True)
BASE = "stable-diffusion-v1-5/stable-diffusion-v1-5"          # community re-host, no token
ADAPTER = "guoyww/animatediff-motion-adapter-v1-5-2"

def main():
    print("downloading/loading SD1.5 + motion adapter...", flush=True)
    adapter = MotionAdapter.from_pretrained(ADAPTER, torch_dtype=torch.float16)
    pipe = AnimateDiffPipeline.from_pretrained(BASE, motion_adapter=adapter, torch_dtype=torch.float16)
    pipe.scheduler = DDIMScheduler.from_config(pipe.scheduler.config, beta_schedule="linear",
                                               clip_sample=False, timestep_spacing="linspace", steps_offset=1)
    pipe.to("cuda")
    pipe.set_progress_bar_config(disable=True)
    res = pipe(prompt="pixel art, a wasteland soldier in patched armor walking, full body, side view, plain gray background",
               negative_prompt="blurry, deformed, extra limbs, melting, morphing, background scenery, text, watermark",
               num_frames=16, num_inference_steps=25, guidance_scale=7.5, height=512, width=512,
               generator=torch.Generator("cuda").manual_seed(42)).frames[0]
    for i, f in enumerate(res):
        f.save(f"{OUT}/walk_{i:02d}.png")
    export_to_gif(res, f"{OUT}/walk.gif")
    print(f"walk: {len(res)} frames + gif", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
