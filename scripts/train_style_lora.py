#!/usr/bin/env python3
"""Train a small SDXL **style LoRA** on the normalized idle set so every future
generation (idle AND poses) renders in ONE consistent wasteland pixel-art look —
the fix for "the poses are lower quality / different background / inconsistent
artwork than the idle". Self-contained: loads our single-file SDXL, caches VAE
latents + text embeds for the 14 idles (so only the UNet is on-GPU during training),
adds a peft LoRA to the UNet attention, trains, and saves a diffusers-loadable LoRA.

Trigger token = 'xlwaste'. Output: out/lora/pytorch_lora_weights.safetensors, load
with pipe.load_lora_weights(out/lora).
"""
import os, glob, json, random
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from diffusers import StableDiffusionXLPipeline, DDPMScheduler
from peft import LoraConfig
from peft.utils import get_peft_model_state_dict

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
HERE = os.path.dirname(os.path.abspath(__file__))
BRIEFS = json.load(open(os.path.join(HERE, "art_reference_briefs.json")))
DATA = "/run/media/mhintermeister/secondary_drive1/comfy/out/units_norm"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/lora"
os.makedirs(OUT, exist_ok=True)
TRIGGER = "xlwaste"
RES, STEPS, LR, RANK = 768, 1400, 1e-4, 16

def caption(ukey):
    subj = BRIEFS["units"][ukey]["subject"]
    return f"{TRIGGER}, pixel art, {subj}, flat gray background"

def encode_prompt(prompt, toks, tes, device):
    embs, pooled = [], None
    for tok, te in zip(toks, tes):
        ids = tok(prompt, padding="max_length", max_length=tok.model_max_length,
                  truncation=True, return_tensors="pt").input_ids.to(device)
        out = te(ids, output_hidden_states=True)
        pooled = out[0]                       # te2's text_embeds is the SDXL pooled embed
        embs.append(out.hidden_states[-2])    # penultimate hidden state
    return torch.cat(embs, dim=-1), pooled

def main():
    device = "cuda"; dtype = torch.float16
    print("loading SDXL components from single-file...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=dtype)
    vae, unet = pipe.vae, pipe.unet
    noise_sched = DDPMScheduler.from_config(pipe.scheduler.config)

    # --- cache latents + text embeds (VAE fp32 for stable encode) ---
    vae.to(device, dtype=torch.float32)
    pipe.text_encoder.to(device); pipe.text_encoder_2.to(device)
    toks = [pipe.tokenizer, pipe.tokenizer_2]; tes = [pipe.text_encoder, pipe.text_encoder_2]
    samples = []
    for f in sorted(glob.glob(f"{DATA}/*__idle.png")):
        ukey = os.path.basename(f).replace("__idle.png", "")
        im = Image.open(f).convert("RGB").resize((RES, RES), Image.LANCZOS)
        px = (torch.from_numpy(np.array(im)).float() / 127.5 - 1.0).permute(2, 0, 1)[None].to(device, torch.float32)
        with torch.no_grad():
            lat = vae.encode(px).latent_dist.sample() * vae.config.scaling_factor
            pe, pooled = encode_prompt(caption(ukey), toks, tes, device)
        samples.append((lat.to(dtype).cpu(), pe.to(dtype).cpu(), pooled.to(dtype).cpu()))
        print(f"  cached {ukey}", flush=True)
    vae.to("cpu"); pipe.text_encoder.to("cpu"); pipe.text_encoder_2.to("cpu")
    del vae; torch.cuda.empty_cache()

    # --- LoRA on the UNet, train UNet only ---
    unet.to(device)
    unet.add_adapter(LoraConfig(r=RANK, lora_alpha=RANK, init_lora_weights="gaussian",
                                target_modules=["to_k", "to_q", "to_v", "to_out.0"]))
    unet.train(); unet.enable_gradient_checkpointing()
    params = [p for p in unet.parameters() if p.requires_grad]
    for p in params:
        p.data = p.data.float()               # keep LoRA params in fp32
    opt = torch.optim.AdamW(params, lr=LR)
    add_time = torch.tensor([[RES, RES, 0, 0, RES, RES]], device=device, dtype=dtype)
    print(f"training {sum(p.numel() for p in params)} LoRA params, {STEPS} steps...", flush=True)

    for step in range(STEPS):
        lat, pe, pooled = random.choice(samples)
        lat, pe, pooled = lat.to(device), pe.to(device), pooled.to(device)
        noise = torch.randn_like(lat)
        t = torch.randint(0, noise_sched.config.num_train_timesteps, (1,), device=device).long()
        noisy = noise_sched.add_noise(lat, noise, t)
        with torch.autocast("cuda", dtype=dtype):
            pred = unet(noisy, t, encoder_hidden_states=pe,
                        added_cond_kwargs={"text_embeds": pooled, "time_ids": add_time}).sample
        loss = F.mse_loss(pred.float(), noise.float())
        opt.zero_grad(); loss.backward(); opt.step()
        if step % 100 == 0 or step == STEPS - 1:
            print(f"  step {step}/{STEPS} loss {loss.item():.4f}", flush=True)

    sd = get_peft_model_state_dict(unet)
    StableDiffusionXLPipeline.save_lora_weights(OUT, unet_lora_layers=sd, safe_serialization=True)
    print(f"DONE — saved LoRA to {OUT}", flush=True)

if __name__ == "__main__":
    main()
