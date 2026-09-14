#!/usr/bin/env python3
"""ovn_filesize_retag.py — bump a doable [T1]/[T2] item's tier to [T3] when its target file is
large, so it naturally routes into the higher-tier staged/architect pipeline (run_overnight.sh's
and ovn_stage_runner.sh's item-pickers both already select purely on the [T345] tag text via
grep — no other signal is consulted).

Why: iptv_apps's discover.py (1066 lines) had 6 separately-queued "small T3" sub-items ALL fail
via the basic scout+implement flow, each looking individually trivial but landing in a large,
easy-to-break file. Real-data cut of state/outcomes.jsonl (2026-09-14) shows the SAME shape
elsewhere: large/complex files are hard to edit safely regardless of how small a step's own text
claims to be, but the staged pipeline (decompose -> per-step aider+gate -> independent verify) is
measurably better at exactly this (58-79% land rate vs the basic flow) BECAUSE it re-verifies
after every single step instead of trusting one big diff. A [T1]/[T2] tag on a large-file item
denies it that safety net purely because of how the item was worded, not its real risk.

.gd (Godot) files are deliberately EXCLUDED here even though the underlying idea would apply
equally: ovn_stage_runner.sh's own item-picker hard-excludes `.gd` regardless of tier (measured
0% in an old benchmark predating this pipeline's recent improvements) - retagging a godot item to
T3 would not route it into staging at all, it would just relabel it uselessly. Re-enabling godot
in the staged picker is a separate, larger decision (see the 2026-09-14 fleet capability review).

Usage: ovn_filesize_retag.py <OVERNIGHT_PROGRESS.md path> <repo root dir> [line-threshold] [max-retags]
Prints RETAGGED=<n> for the caller to detect.
"""
import re
import sys
import os

LINE_RE = re.compile(r"^- \[ \] \[(T[12])\]")
PARKED_RE = re.compile(r"AUTO-SKIP|HUMAN-ONLY|BLOCKED|retired-")
PATH_TOKEN_RE = re.compile(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}")


def main():
    prog_path = sys.argv[1]
    repo_root = sys.argv[2]
    threshold = int(sys.argv[3]) if len(sys.argv) > 3 else 500
    max_retags = int(sys.argv[4]) if len(sys.argv) > 4 else 5

    with open(prog_path, encoding="utf-8") as f:
        lines = f.read().split("\n")

    retagged = 0
    for i, line in enumerate(lines):
        if retagged >= max_retags:
            break
        if not line.startswith("- [ ] "):
            continue
        if PARKED_RE.search(line):
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        if ".gd" in line:
            continue  # staged picker hard-excludes godot regardless of tier — see module docstring

        target = None
        for tok in PATH_TOKEN_RE.findall(line):
            if tok.endswith(".md"):
                continue
            candidate = os.path.join(repo_root, tok)
            if os.path.isfile(candidate):
                target = candidate
                break
        if target is None:
            continue

        try:
            with open(target, encoding="utf-8", errors="ignore") as tf:
                nlines = sum(1 for _ in tf)
        except OSError:
            continue

        if nlines <= threshold:
            continue

        tier = m.group(1)
        new_line = line.replace(f"[{tier}]", "[T3]", 1) + f"  <!-- retagged {tier}->T3: target file is {nlines} lines, routes to staged pipeline -->"
        lines[i] = new_line
        retagged += 1

    if retagged:
        with open(prog_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))

    print(f"RETAGGED={retagged}")


if __name__ == "__main__":
    main()
