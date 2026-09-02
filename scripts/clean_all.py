#!/usr/bin/env python3
"""ALL xlite static artwork, generated CLEAN (short prompts + flat gray background so
nothing bakes a scene behind sprites; pixelize3 floodkey isolates them). Wasteland
theme. Full unit roster + cover objects + HUD icons as bg-removed SPRITES; floors +
hazard as opaque TILES. Run in the ComfyUI venv, GPU window.
"""
import os, torch
from diffusers import StableDiffusionXLPipeline

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/allart"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

STYLE = "pixel art, high contrast, bold clean shapes, full color"
SPRITE_BG = "full body, centered, plain solid flat gray background"     # sprites -> isolated
OBJ_BG = "single object, centered, plain solid flat gray background"
TILE_BG = "seamless top-down tile texture, fills the frame"            # tiles -> opaque
NEG_SPRITE = ("background scenery, landscape, wall, room, floor, ground, shadow, purple tint, "
              "monochrome, blurry, jpeg artifacts, text, watermark, multiple, cropped, border, frame")
NEG_TILE = "character, person, creature, object, text, watermark, border, frame, blurry"

# name -> prompt. Names WITHOUT "tile" become alpha sprites; WITH "tile" stay opaque.
UNITS = [
  ("player_trooper", "a wasteland soldier in patched armor holding a rifle"),
  ("player_heavy",   "a heavy wasteland soldier in bulky armor with a big machine gun"),
  ("player_sniper",  "a wasteland sniper in a hood holding a long rifle"),
  ("player_medic",   "a wasteland medic in armor with a red cross holding a pistol"),
  ("player_engineer","a wasteland engineer with a tool harness and a wrench"),
  ("player_pyro",    "a wasteland soldier in a gas mask holding a flamethrower"),
  ("player_ranger",  "a wasteland ranger in light armor holding a machete"),
  ("enemy_grunt",    "a green mutant alien grunt with claws and red eyes"),
  ("enemy_brute",    "a huge mutant brute monster with big clawed arms"),
  ("enemy_flyer",    "a winged mutant flying creature with claws"),
  ("enemy_drone",    "a rusty flying robot drone with one glowing eye"),
  ("enemy_elite",    "an elite mutant alien warrior with chitin armor"),
  ("enemy_raider",   "a human wasteland raider in spiked scrap armor with a machete"),
  ("enemy_shotgunner","a wasteland raider in riot armor with a sawn-off shotgun"),
  ("enemy_shield",   "a heavy wasteland raider with a huge scrap riot shield"),
  ("enemy_minigunner","a hulking wasteland raider with a big minigun"),
  ("enemy_boss",     "a towering mutant wasteland warlord, heavily armored, glowing eyes"),
]
COVER = [
  ("cover_sandbags",  "a short low stack of military sandbags"),
  ("cover_barrels",   "two short rusty oil drum barrels"),
  ("cover_crate",     "a worn wooden supply crate, a slatted wooden box"),
  ("cover_lowwall",   "a short broken concrete half-wall barrier"),
  ("cover_wall",      "a tall cracked concrete wall barrier, full height"),
  ("cover_container", "a tall rusty shipping cargo container, full height"),
  ("cover_wreck",     "a tall burned-out wrecked car"),
]
ICONS = [
  ("icon_move",      "a bold blue directional arrow symbol"),
  ("icon_shoot",     "a bold crosshair target reticle symbol"),
  ("icon_grenade",   "a bold round grenade with a pin symbol"),
  ("icon_capture",   "a bold capture net symbol"),
  ("icon_overwatch", "a bold watching eye symbol"),
  ("icon_medkit",    "a bold red cross medkit symbol"),
  ("icon_hazard",    "a bold yellow and black hazard triangle with a skull"),
  ("icon_research",  "a bold green microchip symbol"),
  ("icon_armor",     "a bold metal shield symbol"),
]
TILES = [
  ("tile_floor_concrete", "cracked concrete wasteland floor"),
  ("tile_floor_metal",    "rusted riveted metal grate floor"),
  ("tile_floor_asphalt",  "cracked asphalt road with weeds"),
  ("tile_hazard_toxic",   "glowing neon green toxic radioactive sludge, bright acid green"),
  ("tile_rubble",         "scattered concrete rubble and debris"),
]

def gen(pipe, prompt, bg, neg, seed):
    g = torch.Generator("cuda").manual_seed(seed)
    return pipe(prompt=f"{STYLE}, {prompt}, {bg}", negative_prompt=neg,
                num_inference_steps=40, guidance_scale=7.5, height=1024, width=1024,
                generator=g).images[0]

def main():
    print("loading SDXL + LoRA (all art)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.15)
    pipe.set_progress_bar_config(disable=True)
    n = 0
    for key, subj in UNITS:
        gen(pipe, subj, SPRITE_BG, NEG_SPRITE, 2000 + n).save(f"{OUT}/{key}__idle.png"); n += 1; print(f"[{n}] {key}", flush=True)
    for key, subj in COVER + ICONS:
        gen(pipe, subj, OBJ_BG, NEG_SPRITE, 2000 + n).save(f"{OUT}/{key}.png"); n += 1; print(f"[{n}] {key}", flush=True)
    for key, subj in TILES:
        gen(pipe, subj, TILE_BG, NEG_TILE, 2000 + n).save(f"{OUT}/{key}.png"); n += 1; print(f"[{n}] {key}", flush=True)
    print(f"DONE {n} -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
