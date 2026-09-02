#!/usr/bin/env python3
"""Pose generation v2 — POSE-FORCED + character-locked (2026-09-02 rework).

img2img-from-idle locked the character but kept the standing pose (validated). So:
  * ControlNet-OpenPose (a lying / attack skeleton) FORCES the pose, and
  * IP-Adapter (the unit's REAL idle as the image reference) locks the CHARACTER.
This is the only combo that changes the pose AND keeps colours/proportions.

Skeletons (out/poses, from pose_skeletons.py): dead + downed use the horizontal
`death` lying skeleton; attack uses `attack` (human/robot firing) or `attack_melee`
(mutant lunge). Prompts come from the reference briefs (build_prompt). Output is a
gray-bg render → pixelize3 + art_qa_gate downstream.

Usage: gen_pose_controlnet.py <unit>__attack <unit>__downed <unit>__dead ...
"""
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
BRIEFS = json.load(open(os.path.join(HERE, "art_reference_briefs.json")))
sys.path.insert(0, HERE)
from gen_from_brief import build_prompt, CKPT, LORA

OUTBASE = "/run/media/mhintermeister/secondary_drive1/comfy/out"
POSES = f"{OUTBASE}/poses"
IDLE_DIRS = [f"{OUTBASE}/units_norm", f"{OUTBASE}/units_ns"]  # normalized idles first
# skeleton per (pose, family) — dead/downed lie down; attack differs melee vs ranged
def skeleton_for(pose, family):
    if pose == "dead":
        return "death"          # flat, lifeless
    if pose == "downed":
        return "downed"         # propped/collapsed, wounded-but-alive
    return "attack_melee" if family == "mutant" else "attack"
# IP-Adapter scale: lower where the skeleton is very unlike the idle (lying) so the
# pose wins; higher for attack (closer to idle) to hold the character.
IP_SCALE = {"dead": 0.45, "downed": 0.45, "attack": 0.6}

def out_dir(pose):
    d = f"{OUTBASE}/units_{pose}"; os.makedirs(d, exist_ok=True); return d

def find_idle(unit_key):
    for d in IDLE_DIRS:
        p = os.path.join(d, f"{unit_key}__idle.png")
        if os.path.exists(p):
            return p
    return None

def main():
    from PIL import Image
    import torch
    from diffusers import StableDiffusionXLControlNetPipeline, ControlNetModel

    keys = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not keys:
        keys = [f"{u}__{p}" for u in BRIEFS["units"] for p in ("attack", "downed", "dead")]

    print("loading ControlNet-OpenPose + SDXL + LoRA + IP-Adapter ...", flush=True)
    cn = ControlNetModel.from_pretrained("xinsir/controlnet-openpose-sdxl-1.0", torch_dtype=torch.float16)
    pipe = StableDiffusionXLControlNetPipeline.from_single_file(CKPT, controlnet=cn, torch_dtype=torch.float16).to("cuda")
    # pixel-art-xl LoRA + (if trained) our style LoRA, so poses render in the SAME
    # learned wasteland look as everything else (the fix for 'poses lower quality /
    # inconsistent artwork'). Trigger token 'xlwaste' prepended to each prompt.
    pipe.load_lora_weights(LORA, adapter_name="pixel")
    STYLE = f"{OUTBASE}/lora"
    use_style = os.path.exists(f"{STYLE}/pytorch_lora_weights.safetensors")
    if use_style:
        pipe.load_lora_weights(STYLE, adapter_name="xlwaste")
        pipe.set_adapters(["pixel", "xlwaste"], adapter_weights=[0.7, 1.0])
        print("  style LoRA loaded (xlwaste)", flush=True)
    else:
        pipe.set_adapters(["pixel"], adapter_weights=[1.0])
    pipe.load_ip_adapter("h94/IP-Adapter", subfolder="sdxl_models", weight_name="ip-adapter_sdxl.bin")
    pipe.set_progress_bar_config(disable=True)
    skels = {}
    seed_off = int(os.environ.get("SEED_OFFSET", "0"))

    for i, key in enumerate(keys):
        unit_key, pose = key.rsplit("__", 1)
        idle_p = find_idle(unit_key)
        if idle_p is None:
            print(f"[skip] {key}: no idle reference", flush=True); continue
        fam = BRIEFS["units"][unit_key]["family"]
        sk = skeleton_for(pose, fam)
        if sk not in skels:
            skels[sk] = Image.open(f"{POSES}/{sk}.png").convert("RGB")
        idle = Image.open(idle_p).convert("RGB")
        _, prompt, neg = build_prompt(key)
        if use_style:
            prompt = "xlwaste, " + prompt
        pipe.set_ip_adapter_scale(IP_SCALE.get(pose, 0.5))
        g = torch.Generator("cuda").manual_seed(11000 + i + seed_off * 137)
        img = pipe(prompt=prompt, negative_prompt=neg, image=skels[sk], ip_adapter_image=idle,
                   controlnet_conditioning_scale=0.9, num_inference_steps=40, guidance_scale=7.5,
                   height=1024, width=1024, generator=g).images[0]
        img.save(os.path.join(out_dir(pose), f"{unit_key}__{pose}.png"))
        print(f"[{i+1}/{len(keys)}] {key}  (skeleton={sk}, ip={IP_SCALE.get(pose,0.5)})", flush=True)
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
