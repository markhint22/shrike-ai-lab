# Art / animation queue

Add tasks with `art.sh add <type> <key> "<prompt>" [seed]`, then generate with `art.sh run`
(it grabs the GPU, pauses the 27B, and the auto-swap restarts it when done). Output is
staged to `repos/xlite/assets/staging/art-review/<key>/` for review — NOT applied to the
game automatically (art is gated: review, then apply).

**Line format:** `- [ ] [type] key — <full-body wasteland prompt> | seed:NNNN`
- **type** `unit` = 6-pose animation (idle/walk/walk2/attack/hit/death, character-locked via IP-Adapter)
- **type** `sprite`/`icon`/`tile` = single frame
- **prompt** follows the art canon: post-apocalyptic wasteland, worn/scavenged/rusted, vibrant accents, bold readable silhouette, humanoid-bodied units.

**Format examples** (illustrative only — copy into an `art.sh add`, don't leave here as `- [ ]`):
> `art.sh add sprite boss_warlord "a towering scrap-armored wasteland warlord boss with a huge cleaver, full body, front view" 9100`

## Queue
