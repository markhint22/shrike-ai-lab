"""Shared prompt set for the image-model A/B/C comparison (2026-09-11) - same
underlying content across every candidate model so the comparison is fair.
Each model gets its OWN recommended sampler settings (steps/guidance) since
forcing one model's settings on another would be a broken, not fair, test.
Covers both SPRITE (character) and TERRAIN (material/tile) generation, per
the user's ask, matching subjects already proven-good in the existing
xlite pipeline (city_reference_briefs.json / art_reference_briefs.json) so
results are directly comparable to what's already shipped.
"""

PROMPTS = [
    {"key": "sprite_trooper",
     "text": "pixel art, a wasteland soldier in patched scrap armor holding a battle rifle, full body, standing, centered, flat gray background"},
    {"key": "sprite_mutant",
     "text": "pixel art, a hunched green wasteland mutant with clawed hands and red eyes, full body, centered, flat gray background"},
    {"key": "terrain_wall_concrete",
     "text": "pixel art, gray cracked concrete wall texture, exposed rebar, wasteland ruin, seamless tileable texture"},
    {"key": "terrain_car_wreck",
     "text": "pixel art, a single wrecked sedan car, cover object, gray background"},
    {"key": "terrain_road",
     "text": "pixel art, dark asphalt road texture, black-gray cracked pavement, wasteland ruin, seamless tileable texture"},
]
