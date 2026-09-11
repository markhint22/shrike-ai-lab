# Art Pipeline — Reference Brief: Ruined Wasteland City Props

Step 0 (per `REFERENCE_RESEARCH_STEP.md`) for the new modular-building +
city-street asset batch requested 2026-09-10, feeding xlite's new
`WallTiling`/`CoverObject.RenderKind` system (walls pick a sprite by
neighbor shape: straight run / corner / end-cap / window / door) and the
long-standing "buildings you can walk into and fire out the windows" +
road/sidewalk wishlist in `reference-xlite-art-direction` memory.

## Sources consulted (2026-09-10)

- itch.io "War-Torn Destroyed City" / "Post-Apocalyptic Zombie City" pixel
  tilesets — ruined high-rises, shattered windows, broken doors, cracked
  roads, broken streetlights, abandoned vehicles, barricades, graffiti walls.
  https://comshadow.itch.io/wartorn-destroyed-city-pixel-art-tileset
  https://comshadow.itch.io/post-apocalyptic-zombie-city-tileset
- OpenGameArt "1700+ Isometric Doorways" + Screaming Brain Studios iso town
  pack — confirms the modular-kit convention: a small base kit (wall run,
  corner, doorway) reused via material/damage swaps to build many distinct
  structures, rather than one-off hand-drawn buildings.
  https://opengameart.org/content/1700-isometric-doorways
  https://screamingbrainstudios.itch.io/iso-town-pack
- Sunstrike Studios "Isometric City Builder Art" — modular kits (base
  footprint + material swap + damage/prop overlay) is how iso city tilesets
  scale to many buildings from few base pieces. Applied here as: few module
  SHAPES (wall run A/B, corner, end-cap, window, door) × several MATERIAL/
  damage variants each = "many options" without a combinatorial prompt mess.
  https://sunstrikestudios.com/en/blog/isometric-city-builder-art/

## Locked style (must match existing assets exactly — verified visually, not just by name)

- **Palette/style tag** (unchanged from `xlite_vibrant_batch.py` / the
  picked "Vibrant" option): `pixel art, vibrant saturated colors, high
  contrast, arcade, bold clean shapes`.
- **Wasteland palette** (`reference-xlite-art-direction`): rust red, ash
  gray, toxic-green warning accents, warning amber, steel blue, bone white.
  NOT clean sci-fi — everything damaged/worn/rusted (`feedback-xlite-art-
  generation-mistakes` theme correction: this is a wasteland, not aliens).
- **Lighting**: consistent top-down-ish light source, dark grounded hard
  shadow — same as every existing terrain asset.
- **Two distinct render styles, verified against the actual existing PNGs**
  (checked pixel dimensions + opened the images, not just descriptions):
  - **Upright cover objects** (`crate.png`, 64x64 RGBA, floodkey-isolated):
    an isometric pseudo-3D BOX angle — front-left corner faces the camera,
    a little of the top face visible, NOT a flat front elevation and NOT a
    top-down blueprint. Every wall/corner/window/vehicle/prop piece in this
    batch must match this exact camera angle.
  - **Flat floor tiles** (`floor_metal.png`/`rubble.png`/`hazard.png`, all
    64x32 RGBA, full-frame opaque, no isolation): a flat top-down 2:1
    isometric diamond, matching `IsoGrid.TILE_WIDTH=64`/`TILE_HEIGHT=32`
    exactly. Roads/sidewalks/door-threshold decals use this style, not the
    upright box angle.
- **Canvas**: generate at 1024x1024 native (SDXL's working resolution) same
  as every existing asset; `pixelize3.py` downscales to the established
  64/48/32 sizes — do not pre-resize.
- **Background convention** (avoids the baked-background failure mode in
  `feedback-xlite-art-generation-mistakes`): upright objects render on a
  SOLID FLAT MAGENTA background (unlike any wasteland tone, keys cleanly);
  flat floor tiles render full-frame with no distinct background at all
  (the whole frame IS the tile, matching `floor_metal.png`'s own approach).
- **Prompt length**: SDXL/CLIP truncates at ~77 tokens — keep every prompt
  SHORT with the identity/material cue FRONT-LOADED, not trailing.

## Module shapes (upright, floodkey-isolated — CoverObject.RenderKind)

Each gets its own base subject + several material/damage **variants**
(the "many options" axis) so a designer can mix materials across one
building or keep one material consistent per building.

| key | subject (front-loaded) | why this shape |
|---|---|---|
| `wall_run_a` | a straight ruined building wall segment, weathered and cracked | one edge orientation of a rectangle's perimeter |
| `wall_run_b` | a straight ruined building wall segment, weathered and cracked, alternate angle | the other edge orientation |
| `wall_corner` | a corner section of a ruined building wall, two sides meeting | `WallTiling.WallShape.CORNER` |
| `wall_end_cap` | a short ruined wall stub ending abruptly, rubble at the broken end | `WallTiling.WallShape.END_CAP` |
| `wall_window` | a ruined building wall segment with a window opening built into it | `WallTiling.is_window` — half-cover, shoot/see-over |

**Wall material/damage variants** (apply to all 5 shapes above):
concrete (cracked, rebar showing), rusted corrugated metal sheeting, old
brick (crumbling, exposed), scrap-metal patchwork (scavenged wasteland
repair look), sandbag-reinforced concrete.

## Standalone cover props (upright, floodkey-isolated)

| key | subject | variants |
|---|---|---|
| `car_wreck` | a wrecked burnt-out sedan car, cover object | rusted-out, burnt husk, overturned, bullet-riddled |
| `van_wreck` | a wrecked box van, tall cover object | rusted, burnt-out |
| `oil_drum` | a rusty oil drum, low cover object | plain rusted, dented, leaking toxic sludge |
| `sandbag_wall` | a stacked sandbag wall, low cover object | plain, torn/leaking sand, reinforced with scrap |
| `concrete_barrier` | a concrete traffic barrier, low cover object | plain cracked, graffiti-tagged |
| `dumpster` | a rusted metal dumpster, low cover object | closed lid, overturned |
| `chainlink_fence` | a torn chain-link fence section, low cover object | plain torn, with warning signage |
| `shipping_container` | a rusted shipping container, tall cover object | plain rusted, riddled with bullet holes |
| `road_barricade` | a makeshift wasteland road barricade of scrap and barrels | plain, with warning sign |
| `debris_pile` | a tall pile of rubble and scrap debris, cover object | concrete chunks, twisted rebar and scrap |

## Flat floor/decal tiles (opaque, full-frame, "tile" in filename — pixelize3.py classifies by name)

| key | subject | variants |
|---|---|---|
| `tile_road` | a seamless top-down cracked asphalt road tile | plain cracked, faded lane-line markings, pothole-heavy, rubble-strewn |
| `tile_road_corner` | a seamless top-down cracked asphalt road corner-turn tile | plain, faded markings |
| `tile_sidewalk` | a seamless top-down cracked concrete sidewalk tile | plain cracked, weed-overgrown, scorched/stained, manhole cover |
| `tile_curb` | a seamless top-down road-to-sidewalk curb edge tile | plain |
| `tile_rubble2` | a seamless top-down rubble debris floor tile, alternate | concrete-chunk debris, twisted-rebar debris |
| `tile_door` | a top-down ruined building doorway threshold set into a wall gap | rusted metal door ajar, boarded-up door, broken door off its hinges, corrugated shutter half-open |

## Negatives (all pieces)

Base: `blurry, jpeg artifacts, gradient, soft shading, photo, 3d render,
text, watermark, multiple objects, cropped, frame, border, clean, shiny,
pristine, sci-fi, alien`.
Upright-only (avoids the baked-background failure mode): add `scenery,
landscape, sky, ground plane, floor, multiple buildings, full scene`.
