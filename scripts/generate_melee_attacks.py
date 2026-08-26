#!/usr/bin/env python3
"""Re-roll ONLY the attack frame for the melee aliens (grunt/brute/flyer/drone):
a lunging claw/punch strike with the melee skeleton + a 'no weapon, claws/fists'
prompt (the shared firing skeleton wrongly gave them guns). Same seeds/IP-Adapter
as the main run so the character stays consistent. Outputs to out/melee/."""
import os, torch
from PIL import Image
from diffusers import StableDiffusionXLControlNetPipeline, ControlNetModel

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
POSES = "/run/media/mhintermeister/secondary_drive1/comfy/out/poses"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/melee"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

STYLE = ("pixel art, vibrant saturated colors, high contrast, arcade, bold clean shapes, "
         "brightly lit, well lit")
BGC = "solid flat neutral gray background"
NEG = ("gun, rifle, pistol, firearm, weapon, holding a gun, blurry, jpeg artifacts, gradient, "
       "soft shading, photo, 3d render, text, watermark, multiple people, extra limbs, deformed, "
       "cropped, frame, border, dark, murky")
MELEE_HINT = "lunging forward in a melee attack, striking and slashing with sharp claws and fists, bare-handed, no gun"

UNITS = {
  "enemy_grunt": ("a small pale green alien grunt with big red eyes and sharp claws", 1337),
  "enemy_brute": ("a hulking muscular alien brute monster with thick clawed arms and fists", 9001),
  "enemy_flyer": ("a winged humanoid alien warrior with membrane wings and clawed arms", 2468),
  "enemy_drone": ("a hovering humanoid robotic drone with a single glowing eye and sharp metal claws", 3579),
}

def main():
    print("loading ControlNet + SDXL + LoRA + IP-Adapter ...", flush=True)
    cn = ControlNetModel.from_pretrained("xinsir/controlnet-openpose-sdxl-1.0", torch_dtype=torch.float16)
    pipe = StableDiffusionXLControlNetPipeline.from_single_file(CKPT, controlnet=cn, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.1)
    pipe.load_ip_adapter("h94/IP-Adapter", subfolder="sdxl_models", weight_name="ip-adapter_sdxl.bin")
    pipe.set_progress_bar_config(disable=True)
    idle_skel = Image.open(f"{POSES}/idle.png").convert("RGB")
    melee_skel = Image.open(f"{POSES}/attack_melee.png").convert("RGB")
    n = 0
    for ukey, (desc, seed) in UNITS.items():
        # canonical idle (IP reference), ControlNet only
        pipe.set_ip_adapter_scale(0.0)
        g = torch.Generator("cuda").manual_seed(seed)
        idle = pipe(prompt=f"{STYLE}, {desc}, standing ready, {BGC}, centered single sprite",
                    negative_prompt=NEG, image=idle_skel, ip_adapter_image=idle_skel,
                    controlnet_conditioning_scale=0.85, num_inference_steps=32, guidance_scale=7.5,
                    height=1024, width=1024, generator=g).images[0]
        # melee attack: pose from the melee skeleton, character locked to the idle
        pipe.set_ip_adapter_scale(0.5)
        g = torch.Generator("cuda").manual_seed(seed)
        atk = pipe(prompt=f"{STYLE}, {desc}, {MELEE_HINT}, {BGC}, centered single sprite",
                   negative_prompt=NEG, image=melee_skel, ip_adapter_image=idle,
                   controlnet_conditioning_scale=0.9, num_inference_steps=32, guidance_scale=7.5,
                   height=1024, width=1024, generator=g).images[0]
        atk.save(f"{OUT}/{ukey}__attack.png"); n += 1
        print(f"[{n}] {ukey} melee attack", flush=True)
    print(f"DONE {n} -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
