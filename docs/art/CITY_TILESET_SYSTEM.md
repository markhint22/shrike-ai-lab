# Art Pipeline — Reusable City Tileset System (v2)

Supersedes the first city-props pass (`CITY_PROPS_BRIEF.md`) for one specific
category: **walls**. That pass proved individual pieces can look good but
found (via an actual composited mockup, not just eyeballing pieces alone)
that independently-generated "single object" wall chunks don't connect into
a continuous wall — each piece has no knowledge of its neighbor, so gaps show
between segments no matter how good each one looks alone.

## The fix: real seamless tiling, not more single-object chunks

Validated 2026-09-10 via `seamless_tile_test.py`: patching every `Conv2d` in
the SDXL UNet + VAE to `padding_mode='circular'` before generating (the
standard diffusion-model trick for wallpaper/texture generation) makes the
denoiser treat the canvas as toroidal — the decoded image tiles seamlessly
with itself in both X and Y. Verified by self-tiling the raw output 3x3 and
looking for seams: concrete, brick, and rusted metal all came back with NO
visible seam. This is the real fix, not a prompt-wording trick — any two
64px-wide crops taken from the SAME seamless source image will connect
perfectly when placed side by side, because the source already wraps.

**This is the reusable "do it over and over" system the user asked for**: one
seamless generation per material yields effectively unlimited wall-run
segments (slice a 1024x1024 tile into sixteen 64-wide columns), and adding a
new building material later is just adding one entry to `MATERIALS` in
`gen_city_tileset.py` and re-running — no new technique needed.

## Piece taxonomy (what tiles vs what doesn't)

- **Seamless-tiled** (wraps with itself, sliced into N segments): wall runs,
  road, sidewalk. These repeat many times along a run and MUST connect to
  their neighbor — this is exactly what seamless tiling is for.
- **Bounded single objects** (the "chunk on a gray background" recipe from
  the first pass, which DOES work once isolated from the tiling problem):
  corners, end-caps, window inserts, doors, and every standalone prop (cars,
  drums, sandbags, debris, containers, etc.). These each appear once per
  junction/opening/prop placement — they don't need to self-tile, they only
  need to visually match the wall material they're placed against.

## Materials (each gets a full matching set: wall tile + corner + end-cap + window)

concrete, brick, rusted_metal, scrap_metal, sandbag — chosen to match
`reference-xlite-art-direction`'s wasteland palette and the "pick cover type
on purpose" guidance in `docs/LEVEL_DESIGN_GUIDELINES.md` (xlite repo).

## Also fixed in this pass

- **Road vs sidewalk had near-zero contrast** in the first batch (both read
  as similar gray-brown cracked textures — an intersection mockup was
  illegible). Road is now dark asphalt-black with optional lane markings;
  sidewalk is lighter warm tan/beige concrete — a real value/hue difference,
  not just a different crack pattern.
- **Road/sidewalk aspect ratio bug**: first pass generated these as full
  64x64 squares (SDXL's native square canvas) with no correction, when the
  game's actual floor tiles are 64x32 (2:1). Now cropped from the (also
  seamless, tiles-in-both-directions) source at the correct 2:1 window
  instead of squishing a square 50% after the fact.
- **`oil_drum` still rendered as a tiled cluster of several drums** even
  after the first "single isolated object" fix. Strengthened further:
  explicit "exactly one (1)", much more aggressive multi-object negatives,
  and the object framed larger within the canvas (less empty space appears
  to invite the model to fill it with more copies).
- **`chainlink_fence` drifted into an unrelated rod/torch shape.** Rewritten
  with an explicit structural description (a rectangular metal frame holding
  a mesh net) instead of a vague "torn wire-mesh chunk."

## Files

- `scripts/city_reference_briefs_v2.json` — the brief (materials, colors,
  prompts) this pipeline builds every prompt from.
- `scripts/gen_city_tileset.py` — the generator. `make_seamless(pipe, cell)`
  is copy of the validated prototype technique; `slice_wall_segments()` cuts
  a seamless tile into N game-ready 64x64 pieces.
- `scripts/art_city_tileset_window.sh` — trap-safe GPU window, same
  pause-queue/free-GPU/restore-on-EXIT pattern as `art_city_window.sh`.
