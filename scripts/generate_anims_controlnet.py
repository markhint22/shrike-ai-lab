#!/usr/bin/env python3
"""Generate DISTINCT, character-CONSISTENT animation frames (the RIGHT way to do
poses — the img2img path in xlite_vibrant_batch.py makes every frame look like idle).
  - ControlNet-OpenPose forces genuinely different poses (idle/walk/walk2/attack/hit/death).
  - IP-Adapter locks the CHARACTER so it's the same unit in every pose.
Wasteland theme (see reference-xlite-art-direction memory): worn, scavenged, rusted.
Humanoid-bodied units only. Raw 1024 -> pixelize3 to 64px.
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

STYLE = ("pixel art, high-contrast arcade style, post-apocalyptic wasteland, worn "
         "scavenged battle-scarred gear, rust and grit with vibrant accent colors, "
         "bold clean readable silhouette, brightly lit, clearly visible")
BGC   = "solid flat neutral gray background"
NEG   = ("blurry, jpeg artifacts, gradient, soft shading, photo, 3d render, text, watermark, "
         "multiple people, extra limbs, deformed, cropped, frame, border, dark, underexposed, murky")

# Same character in every frame; weapon/claws named so ATTACK actually shows them.
UNITS = {
  "player_trooper":("a post-apocalyptic wasteland soldier in patched scavenged armor holding a makeshift assault rifle, full body, front view", 4242),
  "player_heavy":  ("a hulking wasteland heavy trooper in bulky scrap-metal armor holding a huge salvaged machine gun, full body, front view", 5555),
  "player_sniper": ("a lean wasteland scout sniper in a ragged hooded cloak holding a long scoped rifle, full body, front view", 6666),
  "player_medic":  ("a wasteland field medic in patched armor with a red cross and med-pack holding a pistol, full body, front view", 7777),
  "enemy_grunt":   ("a mutated pale green wasteland alien grunt with big red eyes and sharp claws, full body, front view", 1337),
  "enemy_brute":   ("a huge mutated wasteland brute monster with thick clawed arms and armored hide, full body, front view", 9001),
  "enemy_flyer":   ("a winged mutant wasteland creature with membrane wings and clawed arms, full body, front view", 2468),
  "enemy_drone":   ("a rusty salvaged hovering war drone with a single glowing red eye and metal arms, full body, front view", 3579),
}
POSE_HINT = {"idle":"standing ready holding a weapon",
             "walk":"walking forward, mid-stride, legs wide apart",
             "walk2":"walking forward, opposite stride, legs wide apart",
             "attack":"attacking, weapon raised and firing forward, aggressive combat action",
             "hit":"struck and violently recoiling backward, staggering, flinching in pain, off balance",
             "death":"dead, lying flat on the ground, collapsed injured corpse, defeated, motionless"}
ORDER = ["idle","walk","walk2","attack","hit","death"]
IP_SCALE = {"walk":0.55,"walk2":0.55,"attack":0.5,"hit":0.4,"death":0.2}

def main():
    print("loading ControlNet-OpenPose + SDXL + LoRA + IP-Adapter ...", flush=True)
    cn = ControlNetModel.from_pretrained("xinsir/controlnet-openpose-sdxl-1.0", torch_dtype=torch.float16)
    pipe = StableDiffusionXLControlNetPipeline.from_single_file(CKPT, controlnet=cn, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.1)
    pipe.load_ip_adapter("h94/IP-Adapter", subfolder="sdxl_models", weight_name="ip-adapter_sdxl.bin")
    pipe.set_progress_bar_config(disable=True)
    skels = {p: Image.open(f"{POSES}/{p}.png").convert("RGB") for p in ORDER}
    n = 0
    for ukey,(desc,seed) in UNITS.items():
        pipe.set_ip_adapter_scale(0.0)
        g = torch.Generator("cuda").manual_seed(seed)
        idle = pipe(prompt=f"{STYLE}, {desc}, {POSE_HINT['idle']}, {BGC}, centered single sprite",
                    negative_prompt=NEG, image=skels["idle"], ip_adapter_image=skels["idle"],
                    controlnet_conditioning_scale=0.85, num_inference_steps=36, guidance_scale=7.5,
                    height=1024, width=1024, generator=g).images[0]
        idle.save(f"{OUT}/{ukey}__idle.png"); n += 1; print(f"[{n}] {ukey} idle", flush=True)
        for p in ["walk","walk2","attack","hit","death"]:
            pipe.set_ip_adapter_scale(IP_SCALE[p])
            g = torch.Generator("cuda").manual_seed(seed)
            img = pipe(prompt=f"{STYLE}, {desc}, {POSE_HINT[p]}, {BGC}, centered single sprite",
                       negative_prompt=NEG, image=skels[p], ip_adapter_image=idle,
                       controlnet_conditioning_scale=0.9, num_inference_steps=36, guidance_scale=7.5,
                       height=1024, width=1024, generator=g).images[0]
            img.save(f"{OUT}/{ukey}__{p}.png"); n += 1; print(f"[{n}] {ukey} {p} (ip-locked)", flush=True)
    print(f"DONE {n} frames -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
