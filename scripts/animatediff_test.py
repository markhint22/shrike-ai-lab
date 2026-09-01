#!/usr/bin/env python3
"""SPIKE: can AnimateDiff (SDXL + motion adapter) produce CLEAN pixel-art character
motion (a walk cycle) where the whole-sprite-transform / redraw approaches failed?
Temporal layers keep the character consistent across frames within a clip. Generates a
short walk clip of a wasteland soldier on a plain background (for later isolation) + a
gif to eyeball. Experimental — judge the output before trusting it.
"""
import os, torch
from diffusers import AnimateDiffSDXLPipeline, MotionAdapter, StableDiffusionXLPipeline, DDIMScheduler
from diffusers.utils import export_to_gif

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/animatediff"
os.makedirs(OUT, exist_ok=True)

def build():
    print("downloading/loading SDXL motion adapter...", flush=True)
    adapter = MotionAdapter.from_pretrained("guoyww/animatediff-motion-adapter-sdxl-beta",
                                            torch_dtype=torch.float32)
    sdxl = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float32)
    sched = DDIMScheduler.from_config(sdxl.scheduler.config, beta_schedule="linear",
                                      timestep_spacing="linspace", steps_offset=1, clip_sample=False)
    pipe = AnimateDiffSDXLPipeline(
        vae=sdxl.vae, text_encoder=sdxl.text_encoder, text_encoder_2=sdxl.text_encoder_2,
        tokenizer=sdxl.tokenizer, tokenizer_2=sdxl.tokenizer_2, unet=sdxl.unet,
        motion_adapter=adapter, scheduler=sched)
    # Spike v3: NO LoRA, full GPU (24GB free in the window). Just testing whether
    # AnimateDiff produces COHERENT motion at all before worrying about pixel style —
    # keep dtype fp16 end-to-end (the offload path caused 'expected Half but found Float').
    pipe = pipe.to("cuda")
    pipe.set_progress_bar_config(disable=True)
    return pipe

def run(pipe, key, prompt, seed):
    res = pipe(prompt=f"pixel art, high contrast, {prompt}, plain solid gray background",
               negative_prompt="blurry, deformed, extra limbs, morphing, background scenery, text, watermark",
               num_frames=6, num_inference_steps=25, guidance_scale=7.5,
               height=768, width=768,
               generator=torch.Generator("cuda").manual_seed(seed)).frames[0]
    for i, f in enumerate(res):
        f.save(f"{OUT}/{key}_{i:02d}.png")
    export_to_gif(res, f"{OUT}/{key}.gif")
    print(f"{key}: {len(res)} frames + gif", flush=True)

def main():
    pipe = build()
    run(pipe, "walk", "a wasteland soldier in patched armor walking forward, full body", 42)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
