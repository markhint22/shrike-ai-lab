#!/usr/bin/env python3
"""xlite OPTIONS batch — multiple variants per asset so the user can pick keepers.
Wasteland theme (post-apocalyptic + advanced-but-ruined tech). Covers:
  - UNIT/ENEMY idles: the core roster + NEW archetypes, N seed options each.
  - TERRAIN: distinct floors + hazard (neon toxic) as seamless TILES; cover objects
    as bg-removed SPRITES, HALF cover = short, FULL cover = tall.
  - ICONS: bold single-symbol HUD icons incl. a NEW hazard warning icon.
Raw 1024 -> pixelize3 (64/48/32). Filenames w/ "tile" stay opaque tiles; everything
else is alpha-keyed as a sprite. Run in the ComfyUI venv (GPU window).
"""
import os, torch
from diffusers import StableDiffusionXLPipeline

C = "/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI"
OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/options"
os.makedirs(OUT, exist_ok=True)
CKPT = f"{C}/models/checkpoints/sd_xl_base_1.0.safetensors"
LORA = f"{C}/models/loras/pixel-art-xl.safetensors"

OPTIONS = 2  # seed variants per asset

STYLE = ("pixel art, high-contrast arcade style, post-apocalyptic wasteland, worn "
         "rusted scavenged look, vibrant accent colors, bold clean readable shapes, "
         "brightly lit, clearly visible")
BGC = "solid flat neutral gray background, centered single object"
NEG = ("blurry, jpeg artifacts, gradient, soft shading, photo, 3d render, text, "
       "watermark, multiple objects, extra limbs, deformed, cropped, frame, border, "
       "dark, underexposed, murky")

# --- units / enemies (idle look options) -----------------------------------
UNITS = [
  # core roster — alt looks to compare against the animated set
  ("player_trooper", "a post-apocalyptic wasteland soldier in patched scavenged armor holding a makeshift assault rifle, front view"),
  ("player_heavy",   "a hulking wasteland heavy trooper in bulky scrap-metal armor with a huge salvaged machine gun, front view"),
  ("player_sniper",  "a lean wasteland scout sniper in a ragged hooded cloak with a long scoped rifle, front view"),
  ("player_medic",   "a wasteland field medic in patched armor with a red cross med-pack and a pistol, front view"),
  # NEW player archetypes
  ("player_engineer","a wasteland engineer in a tool harness with a wrench and a deployable scrap turret backpack, front view"),
  ("player_pyro",    "a wasteland pyro trooper in a gas mask with a salvaged flamethrower and fuel tanks, front view"),
  ("player_ranger",  "a wasteland melee ranger in light scrap armor gripping a machete, front view"),
  # core enemies
  ("enemy_grunt",    "a mutated pale green wasteland alien grunt with big red eyes and sharp claws, front view"),
  ("enemy_brute",    "a huge mutated wasteland brute monster with thick clawed arms and an armored hide, front view"),
  ("enemy_flyer",    "a winged mutant wasteland creature with membrane wings and clawed arms, front view"),
  ("enemy_drone",    "a rusty salvaged hovering war drone with a single glowing red eye and metal arms, front view"),
  # NEW / distinct enemy archetypes (currently reuse grunt/brute art in game)
  ("enemy_elite",    "an elite mutant alien warrior with chitin plate armor and glowing veins, front view"),
  ("enemy_raider",   "a human wasteland raider bandit in spiked scrap armor with a machete and a pistol, front view"),
  ("enemy_shotgunner","a wasteland raider in riot armor aiming a sawn-off shotgun, front view"),
  ("enemy_shield",   "a heavy wasteland raider hauling a huge welded scrap riot shield, front view"),
  ("enemy_minigunner","a hulking wasteland raider hefting a salvaged minigun with ammo belts, front view"),
  ("enemy_boss",     "a towering mutated wasteland warlord boss, massive and heavily armored with glowing eyes, front view"),
]

# --- terrain ---------------------------------------------------------------
# floors + hazard are seamless TILES (name contains "tile" -> opaque, no alpha)
TILES = [
  ("tile_floor_concrete", "seamless top-down cracked concrete wasteland floor, worn"),
  ("tile_floor_metal",    "seamless top-down rusted riveted metal grate floor"),
  ("tile_floor_asphalt",  "seamless top-down cracked asphalt road with weeds poking through"),
  ("tile_hazard_toxic",   "seamless top-down glowing neon green toxic radioactive sludge pool, bright acid green, obvious danger"),
  ("tile_rubble",         "seamless top-down scattered concrete rubble and debris flat on the ground"),
]
# cover objects are bg-removed SPRITES (no "tile" in the name). HALF = short, FULL = tall.
COVER = [
  ("cover_sandbags",  "a short low stack of worn military sandbags for cover, low and wide"),   # half
  ("cover_barrels",   "two short rusty oil drum barrels for cover, low"),                        # half
  ("cover_crate",     "a single worn wooden supply crate, a slatted wooden box with metal corners, low"),  # half
  ("cover_lowwall",   "a short broken concrete half-wall barrier for cover, low"),               # half
  ("cover_wall",      "a tall cracked reinforced concrete wall barrier, full height, tall"),      # full
  ("cover_container", "a tall rusty shipping cargo container, full height, tall"),                # full
  ("cover_wreck",     "a tall burned-out wrecked car for cover, full height, tall"),              # full
]

# --- icons (bold, single-symbol, readable small) ---------------------------
ICONS = [
  ("icon_move",      "a single bold blue directional arrow symbol, flat icon"),
  ("icon_shoot",     "a single bold crosshair target reticle symbol, flat icon"),
  ("icon_grenade",   "a single bold round grenade with a pin symbol, flat icon"),
  ("icon_net",       "a single bold capture net symbol, flat icon"),
  ("icon_overwatch", "a single bold watching eye symbol, flat icon"),
  ("icon_medkit",    "a single bold red cross medkit symbol, flat icon"),
  ("icon_hazard",    "a single bold yellow and black striped hazard warning triangle with a skull, flat icon, danger"),
  ("icon_research",  "a single bold green microchip symbol, flat icon"),
  ("icon_armor",     "a single bold metal shield symbol, flat icon"),
]

def gen(pipe, prompt, seed, steps=40):
    g = torch.Generator("cuda").manual_seed(seed)
    return pipe(prompt=f"{STYLE}, {prompt}, {BGC}",
                negative_prompt=NEG, num_inference_steps=steps, guidance_scale=7.5,
                height=1024, width=1024, generator=g).images[0]

def main():
    print("loading SDXL + LoRA (options)...", flush=True)
    pipe = StableDiffusionXLPipeline.from_single_file(CKPT, torch_dtype=torch.float16).to("cuda")
    pipe.load_lora_weights(LORA); pipe.fuse_lora(lora_scale=1.15)
    pipe.set_progress_bar_config(disable=True)
    n = 0
    for group in (UNITS, COVER, ICONS, TILES):
        for key, subj in group:
            for opt in range(1, OPTIONS + 1):
                seed = (abs(hash(key)) + opt * 7919) % 100000
                gen(pipe, subj, seed).save(f"{OUT}/{key}__opt{opt}.png")
                n += 1
                print(f"[{n}] {key} opt{opt}", flush=True)
    print(f"DONE {n} option renders -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
