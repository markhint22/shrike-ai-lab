#!/usr/bin/env python3
"""ovn_swift_retag.py — tag any doable item whose target file is .swift as AUTO-SKIP.

Why: unlike Python (pytest), web (vitest/npm build), Android (gradlew test), and Godot (gdparse +
GUT, all runnable headless on Linux), Swift/iOS/tvOS code needs Xcode + the Apple SDKs to compile
at all — there is no Linux toolchain that can build a SwiftUI/UIKit target. Confirmed empirically:
grepping every verify/gate function in run_overnight.sh, branch_hygiene.sh, and
ovn_stage_runner.sh for "swift"/"xcodebuild" turns up nothing — a Swift-only change gets a green
gate purely because the OTHER parts of the repo (backend/web) are unaffected and pass, not because
anything checked the Swift code. Confirmed live: 8 "staged step" commits (2026-09-14/15) refactored
TVHistoryView.swift/TVGuideView.swift with zero automated verification, and were only checked when
a human opened Xcode. The code happened to compile, but that was luck, not a gate.

This mirrors the fully-excluded Godot GUT-test-file case in ovn_stage_runner.sh's own item-picker
and the size-based-retag mechanics of ovn_filesize_retag.py: pure text relocation, no LLM,
hold-safe. Unlike the Godot case, there is no future in which a Linux fleet CAN verify Swift, so
this is a permanent routing decision, not a capability-measurement pending re-test.

Usage: ovn_swift_retag.py <OVERNIGHT_PROGRESS.md path> [max-retags]
Prints RETAGGED=<n> for the caller to detect.
"""
import re
import sys

PARKED_RE = re.compile(r"AUTO-SKIP|HUMAN-ONLY|BLOCKED|retired-")
SWIFT_RE = re.compile(r"\.swift\b")


def main():
    prog_path = sys.argv[1]
    max_retags = int(sys.argv[2]) if len(sys.argv) > 2 else 10

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
        if not SWIFT_RE.search(line):
            continue
        lines[i] = line.replace(
            "- [ ] ",
            "- [ ] [AUTO-SKIP swift(no-fleet-verify) — no Xcode/Apple SDK on the Linux fleet, "
            "cannot build-check this; route to Claude or a human with a Mac] ",
            1,
        )
        retagged += 1

    if retagged:
        with open(prog_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))

    print(f"RETAGGED={retagged}")


if __name__ == "__main__":
    main()
