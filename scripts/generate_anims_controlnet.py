#!/usr/bin/env python3
"""Generate DISTINCT, character-consistent animation frames with ControlNet-OpenPose:
same character prompt + fixed seed (keeps the character identical) while a per-frame
pose skeleton forces genuinely different poses (idle/walk/attack/hit/death). This fixes
the img2img 'all frames look the same' problem. Humanoid units only (trooper, grunt).
"""
import os, torch
from PIL import Image
from diffusers import StableDiffusionXLControlNetPipeline, ControlNetModel

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
POSES = "/run/media/mhintermeister/secondary_drive1/comfy/out/poses"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/anims"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

STYLE = "pixel art, vibrant saturated colors, high contrast, arcade, bold clean shapes"
BGC   = "solid flat neutral gray background"
NEG   = ("blurry, jpeg artifacts, gradient, soft shading, photo, 3d render, text, watermark, "
         "multiple people, extra limbs, deformed, cropped, frame, border")

# same detailed description drives character consistency; fixed seed per unit
UNITS = {
  "player_trooper": ("a single sci-fi tactical soldier trooper in white and red armor "
                     "with a helmet, full body, front view", 4242),
  "enemy_grunt":    ("a single small pale green alien grunt creature with big red eyes "
                     "and thin limbs, full body, front view", 1337),
}
POSE_HINT = {"idle":"standing idle","walk":"walking mid-stride","attack":"lunging attack, weapon thrust forward",
             "hit":"recoiling, hit and flinching backward","death":"collapsed on the ground, defeated"}
ORDER = ["idle","walk","attack","hit","death"]

def main():
    print("loading ControlNet-OpenPose + SDXL + LoRA ...", flush=True)
    cn = ControlNetModel.from_pretrained("xinsir/controlnet-openpose-sdxl-1.0", torch_dtype=torch.float16)
    pipe = StableDiffusionXLControlNetPipeline.from_single_file(CKPT, controlnet=cn, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.1)
    pipe.set_progress_bar_config(disable=True)
    skels = {p: Image.open(f"{POSES}/{p}.png").convert("RGB") for p in ORDER}
    n = 0
    for ukey,(desc,seed) in UNITS.items():
        for p in ORDER:
            g = torch.Generator("cuda").manual_seed(seed)
            img = pipe(prompt=f"{STYLE}, {desc}, {POSE_HINT[p]}, {BGC}, centered single sprite",
                       negative_prompt=NEG, image=skels[p], controlnet_conditioning_scale=0.85,
                       num_inference_steps=32, guidance_scale=7.5, height=1024, width=1024,
                       generator=g).images[0]
            img.save(f"{OUT}/{ukey}__{p}.png"); n += 1
            print(f"[{n}] {ukey} {p}", flush=True)
    print(f"DONE {n} frames -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
