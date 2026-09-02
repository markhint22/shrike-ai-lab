# Art Pipeline — Step 0: Reference Research (MANDATORY, runs BEFORE any generation)

**Why this exists**: sprites kept "not making sense" (a dead alien that read as a
green blob, poses that didn't parse) because we jumped straight to an SDXL prompt
without first pinning down *what the thing actually looks like*. A one-line prompt
like "a green mutant alien grunt" leaves every silhouette/pose/telltale detail to
the model's imagination — so it invents a shape that doesn't convey the concept.

**The rule**: for every art subject, do a reference-research pass FIRST, distill it
into a short **reference brief** of concrete visual features, and build the SDXL
prompt FROM that brief. No brief → no generation.

## The step (what "look up images first" means concretely)

1. **Research the subject** — web-search the thing plus its medium and view:
   e.g. `dead alien corpse top-down pixel art sprite`, `wasteland raider sprite
   sheet idle`. Note how real sprite sheets depict it: silhouette, palette,
   the 2-3 *telltale* details that make it read (a sniper's long barrel, a
   medic's red cross), and — critically — how a **state** is conveyed (a "dead"
   sprite is a distinct sprawled/flattened pose with an ichor pool, NOT a live
   idle rotated on its side).
2. **Write the brief** — add/adjust an entry in `scripts/art_reference_briefs.json`
   (see schema below). `key_features` are the concrete must-haves pulled from the
   references; `negatives` are the failure modes to ban.
3. **Generate from the brief** — `gen_from_brief.py <key>...` builds the prompt as
   `STYLE + key_features + subject + framing`, negatives as `BASE_NEG + negatives`.
   Never hand-write a prompt that bypasses the brief.
4. **Pixelize + review** — `pixelize3.py`, composite on magenta, eyeball the
   isolation, then wire into the game and get sign-off (gated art process).

## Brief schema (`scripts/art_reference_briefs.json`)

```json
{
  "<art_key>": {
    "subject": "one plain-language sentence naming the thing",
    "view": "the framing (full body centered / top-down 3/4 / iso tile)",
    "references": ["short notes on what real sprite sheets do (from the research)"],
    "key_features": ["concrete visual must-have", "..."],
    "negatives": ["failure mode to ban", "..."]
  }
}
```

## States need their OWN brief + sprite

Top-down enemy sheets ship Idle / Attack / **Dead** / Hit as *distinct* art. A
corpse is a first-class sprite: sprawled/splayed limbs, lying flat, a fluid pool
(green ichor for a mutant, oil for a robot), desaturated + darker than the live
unit. `unit.gd` uses a real `dead` frame when present and only falls back to the
old rotate-the-idle hack when a unit has no dead sprite yet.

## Sources consulted for the current briefs

- Top-down enemy asset packs commonly ship Idle/Attack/**Dead**/Hit states —
  https://www.gamedevmarket.net/asset/pixel-art-rpg-top-down-enemies
- "Top down dead things" / undead top-down tilesets show corpses as flattened,
  splayed, ichor-pooled shapes — https://opengameart.org/content/topdown-assets
- Aliens: Dark Descent (top-down real-time tactics) for alien read at small scale
  — https://en.wikipedia.org/wiki/Aliens:_Dark_Descent
