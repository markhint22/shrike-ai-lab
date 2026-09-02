#!/usr/bin/env python3
"""Art pipeline — automated QA gate (stage 4). The user's recurring complaint is
background creeping into sprites (ground at the feet, halo around the unit) and
death poses that don't make sense. This programmatically INSPECTS each isolated
sprite and returns pass/fail + reasons so the pipeline can auto-reject → regenerate
before anything reaches the game or the review gallery.

Checks (per role):
  * has_alpha        : the image must actually be transparent (not a solid card).
  * bg_residue       : corners/edges must be transparent — opaque corners = a baked
                       background survived keying.
  * feet_halo        : a ring of low-saturation semi-opaque fringe at the base = the
                       'ground at the feet' artifact.
  * coverage         : opaque fraction in a sane band (too low = gen failed / empty;
                       too high = the whole background is still there).
  * pose_aspect      : for DEAD/DOWNED, the body must be LYING (wider than tall) — a
                       tall bbox means it rendered standing (the recurring bug).

Usage: art_qa_gate.py <dir> --role dead|downed|idle|object|tile  [--json]
Exit 0 always; prints a JSON list of {file, ok, reasons} (and a summary to stderr).
"""
import sys, os, glob, json
import numpy as np
from PIL import Image

def load(path):
    return np.array(Image.open(path).convert("RGBA"))

def _count_large_blobs(opaque, min_frac=0.10):
    """4-connected components on a downsized alpha mask; count blobs whose area is
    >= min_frac of the total opaque area. >=2 means the sprite rendered MORE THAN ONE
    figure (the 'downed = 2 people' bug) or a big stray secondary mass (a mystery pile
    beside the body). Pure-numpy BFS on a 32x-ish grid so it's cheap + dependency-free."""
    from collections import deque
    small = opaque[::2, ::2]
    H, W = small.shape
    total = int(small.sum())
    if total == 0:
        return 0
    seen = np.zeros_like(small, dtype=bool)
    big = 0
    for y in range(H):
        for x in range(W):
            if small[y, x] and not seen[y, x]:
                q = deque([(y, x)]); seen[y, x] = True; sz = 0
                while q:
                    cy, cx = q.popleft(); sz += 1
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W and small[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True; q.append((ny, nx))
                if sz >= min_frac * total:
                    big += 1
    return big

def inspect(arr, role):
    H, W = arr.shape[:2]
    a = arr[:, :, 3]
    reasons = []
    opaque = a > 40
    frac = opaque.mean()

    # has_alpha: some meaningful transparency must exist
    if (a > 8).mean() > 0.98:
        reasons.append("no_alpha(solid card — background not removed)")

    # bg_residue: corners must be clear
    k = max(3, W // 12)
    corners = [a[:k, :k], a[:k, -k:], a[-k:, :k], a[-k:, -k:]]
    opaque_corners = sum(1 for c in corners if (c > 40).mean() > 0.25)
    if opaque_corners >= 1 and role in ("idle", "object"):
        reasons.append(f"bg_residue({opaque_corners} opaque corners)")
    # edge frame (dead sprites sometimes bake a dark 'slab' border)
    edge = np.concatenate([a[0, :], a[-1, :], a[:, 0], a[:, -1]])
    if (edge > 40).mean() > 0.35:
        reasons.append("edge_frame(opaque border ring — baked slab/frame)")

    # coverage band
    lo, hi = (0.05, 0.75)
    if frac < lo:
        reasons.append(f"coverage_low({frac:.2f} — gen failed/empty)")
    if frac > hi:
        reasons.append(f"coverage_high({frac:.2f} — background likely intact)")

    # feet_halo: bottom 18% — low-saturation semi-opaque fringe around the mass
    if role in ("idle", "object"):
        band = arr[int(H * 0.82):, :, :]
        ba = band[:, :, 3]
        rgb = band[:, :, :3].astype(int)
        sat = rgb.max(2) - rgb.min(2)
        fringe = (ba > 20) & (ba < 210) & (sat < 30)
        if ba.size and fringe.mean() > 0.06:
            reasons.append(f"feet_halo(low-sat fringe {fringe.mean():.2f} at base)")

    # single subject: character sprites must be ONE figure, not two + no stray pile
    if role in ("idle", "downed", "dead", "attack"):
        blobs = _count_large_blobs(opaque)
        if blobs >= 2:
            reasons.append(f"multiple_figures({blobs} large masses — 2 people / stray pile)")

    # pose_aspect: a corpse/downed must be LYING (bbox wider than tall)
    if role in ("dead", "downed"):
        ys, xs = np.where(opaque)
        if len(ys):
            bw = xs.max() - xs.min() + 1
            bh = ys.max() - ys.min() + 1
            if bh > bw * 1.05:
                reasons.append(f"standing_pose(bbox {bw}x{bh}, taller than wide — must lie down)")
        else:
            reasons.append("empty")

    return {"ok": len(reasons) == 0, "reasons": reasons, "coverage": round(float(frac), 3)}

def main():
    d = sys.argv[1]
    role = "idle"
    if "--role" in sys.argv:
        role = sys.argv[sys.argv.index("--role") + 1]
    files = sorted(glob.glob(os.path.join(d, "*.png")))
    out = []
    for f in files:
        if f.endswith("_preview.png"):
            continue
        res = inspect(load(f), role)
        res["file"] = os.path.basename(f)
        out.append(res)
    npass = sum(1 for r in out if r["ok"])
    print(json.dumps(out, indent=2))
    print(f"[qa {role}] {npass}/{len(out)} pass", file=sys.stderr)
    for r in out:
        if not r["ok"]:
            print(f"  FAIL {r['file']}: {'; '.join(r['reasons'])}", file=sys.stderr)

if __name__ == "__main__":
    main()
