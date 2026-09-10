#!/usr/bin/env python3
"""Art/animation queue runner for the Shrike GPU box.

Reads ~/overnight-queue/art_queue.md (the persistent art queue), generates each
queued task with the PROVEN pipeline (SDXL + ControlNet-OpenPose + IP-Adapter +
pixel-art LoRA — same as the vetted /tmp/generate_anims_controlnet.py), pixelizes
to 64px, hardens alpha, and writes to a REVIEW STAGING dir (never straight into the
game — art is gated: a human reviews, then applies). Marks each item done in the
queue and ntfy-pings a summary.

GPU coordination: this runner GRABS the GPU. The caller (art.sh run) stops the 27B
llama container first to free VRAM; when this finishes and the GPU frees, the
existing gpu_autoswap.sh watcher restarts the 27B automatically. So art and the
code fleet take turns with no manual step.

Queue line format (one task per line in art_queue.md):
  - [ ] [unit]   <key> — <full-body wasteland prompt> | seed:NNNN
  - [ ] [sprite] <key> — <prompt> | seed:NNNN      (single frame, no anim)
Types: unit = 6-pose animation (idle/walk/walk2/attack/hit/death); sprite/icon/tile = single frame.
"""
import os, re, sys, subprocess, datetime

HOME = os.path.expanduser("~")
QUEUE = f"{HOME}/overnight-queue/art_queue.md"
C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
POSES = "/run/media/mhintermeister/secondary_drive1/comfy/out/poses"
STAGE = f"{HOME}/overnight-queue/repos/xlite/assets/staging/art-review"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"
TOPIC = os.environ.get("NTFY_TOPIC", "shrike_ovn_311380987a")

STYLE = ("pixel art, high-contrast arcade style, post-apocalyptic wasteland, worn "
         "scavenged battle-scarred gear, rust and grit with vibrant accent colors, "
         "bold clean readable silhouette, brightly lit, clearly visible")
BGC = "solid flat neutral gray background"
NEG = ("blurry, jpeg artifacts, gradient, soft shading, photo, 3d render, text, watermark, "
       "multiple people, extra limbs, deformed, cropped, frame, border, dark, underexposed, murky")
POSE_HINT = {"idle": "standing ready holding a weapon",
             "walk": "walking forward, mid-stride, legs wide apart",
             "walk2": "walking forward, opposite stride, legs wide apart",
             "attack": "attacking, weapon raised and firing forward, aggressive combat action",
             "hit": "struck and violently recoiling backward, staggering, flinching in pain, off balance",
             "death": "dead, lying flat on the ground, collapsed injured corpse, defeated, motionless"}
UNIT_ORDER = ["idle", "walk", "walk2", "attack", "hit", "death"]
IP_SCALE = {"walk": 0.55, "walk2": 0.55, "attack": 0.5, "hit": 0.4, "death": 0.2}

LINE = re.compile(r"^- \[ \]\s*\[(?P<type>\w+)\]\s*(?P<key>[\w\-]+)\s*[—-]\s*(?P<prompt>.+?)(?:\s*\|\s*seed:(?P<seed>\d+))?\s*$")


def parse_queue():
    if not os.path.exists(QUEUE):
        return []
    tasks = []
    in_comment = False
    for i, ln in enumerate(open(QUEUE, encoding="utf-8").read().splitlines()):
        if "<!--" in ln:
            in_comment = True
        if in_comment:
            if "-->" in ln:
                in_comment = False
            continue
        m = LINE.match(ln)
        if m:
            d = m.groupdict()
            tasks.append({"line_no": i, "raw": ln, "type": d["type"].lower(),
                          "key": d["key"], "prompt": d["prompt"].strip(),
                          "seed": int(d["seed"]) if d["seed"] else (abs(hash(d["key"])) % 90000 + 1000)})
    return tasks


def alert(title, msg):
    try:
        subprocess.run(["curl", "-fsS", "--max-time", "8", "-H", f"Title: {title}",
                        "-H", "Tags: art", "-d", msg, f"https://ntfy.sh/{TOPIC}"],
                       capture_output=True, timeout=10)
    except Exception:
        pass


def pixelize_and_alpha(img):
    """1024 -> 64px nearest, then make the flat gray background transparent."""
    from PIL import Image
    small = img.convert("RGB").resize((64, 64), Image.NEAREST)
    rgba = small.convert("RGBA")
    px = rgba.load()
    # sample the 4 corners to learn the background gray, then threshold it out
    corners = [px[0, 0], px[63, 0], px[0, 63], px[63, 63]]
    br = sum(c[0] for c in corners) // 4
    bg = sum(c[1] for c in corners) // 4
    bb = sum(c[2] for c in corners) // 4
    for y in range(64):
        for x in range(64):
            r, g, b, _ = px[x, y]
            if abs(r - br) < 28 and abs(g - bg) < 28 and abs(b - bb) < 28:
                px[x, y] = (r, g, b, 0)
    return rgba


def mark_done(tasks_done, outdir):
    lines = open(QUEUE, encoding="utf-8").read().splitlines(keepends=True)
    for t in tasks_done:
        raw = t["raw"]
        stamp = datetime.datetime.now().strftime("%Y-%m-%d") if False else "generated"  # no Date.now in scripts elsewhere; fine here
        for i, ln in enumerate(lines):
            if ln.rstrip("\n") == raw:
                lines[i] = ln.replace("- [ ]", "- [x] (staged for review)", 1)
                break
    open(QUEUE, "w", encoding="utf-8").write("".join(lines))


def main():
    tasks = parse_queue()
    if not tasks:
        print("art queue empty — nothing to generate")
        return 0
    print(f"art queue: {len(tasks)} task(s): " + ", ".join(f"{t['key']}[{t['type']}]" for t in tasks), flush=True)

    import torch
    from PIL import Image
    from diffusers import StableDiffusionXLControlNetPipeline, ControlNetModel
    print("loading ControlNet-OpenPose + SDXL + LoRA + IP-Adapter ...", flush=True)
    cn = ControlNetModel.from_pretrained("xinsir/controlnet-openpose-sdxl-1.0", torch_dtype=torch.float16)
    pipe = StableDiffusionXLControlNetPipeline.from_single_file(CKPT, controlnet=cn, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.1)
    pipe.load_ip_adapter("h94/IP-Adapter", subfolder="sdxl_models", weight_name="ip-adapter_sdxl.bin")
    pipe.set_progress_bar_config(disable=True)
    skels = {p: Image.open(f"{POSES}/{p}.png").convert("RGB") for p in UNIT_ORDER}

    done, frames = [], 0
    for t in tasks:
        outdir = f"{STAGE}/{t['key']}"
        os.makedirs(outdir, exist_ok=True)
        desc, seed = t["prompt"], t["seed"]
        poses = UNIT_ORDER if t["type"] == "unit" else ["idle"]
        try:
            pipe.set_ip_adapter_scale(0.0)
            g = torch.Generator("cuda").manual_seed(seed)
            idle = pipe(prompt=f"{STYLE}, {desc}, {POSE_HINT['idle']}, {BGC}, centered single sprite",
                        negative_prompt=NEG, image=skels["idle"], ip_adapter_image=skels["idle"],
                        controlnet_conditioning_scale=0.85, num_inference_steps=36, guidance_scale=7.5,
                        height=1024, width=1024, generator=g).images[0]
            pixelize_and_alpha(idle).save(f"{outdir}/{t['key']}__idle.png"); frames += 1
            print(f"  {t['key']} idle", flush=True)
            for p in poses[1:]:
                pipe.set_ip_adapter_scale(IP_SCALE[p])
                g = torch.Generator("cuda").manual_seed(seed)
                img = pipe(prompt=f"{STYLE}, {desc}, {POSE_HINT[p]}, {BGC}, centered single sprite",
                           negative_prompt=NEG, image=skels[p], ip_adapter_image=idle,
                           controlnet_conditioning_scale=0.9, num_inference_steps=36, guidance_scale=7.5,
                           height=1024, width=1024, generator=g).images[0]
                pixelize_and_alpha(img).save(f"{outdir}/{t['key']}__{p}.png"); frames += 1
                print(f"  {t['key']} {p}", flush=True)
            done.append(t)
        except Exception as e:
            print(f"  FAILED {t['key']}: {e}", flush=True)

    if done:
        mark_done(done, STAGE)
    print(f"DONE {frames} frames for {len(done)} task(s) -> {STAGE}", flush=True)
    alert("Art batch staged for review",
          f"{frames} frames, {len(done)} unit(s) at assets/staging/art-review/. Review, then apply. "
          f"27B will auto-restore now the GPU is freeing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
