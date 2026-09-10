#!/usr/bin/env python3
"""Prepend a 🚨 EMERGENCY item to a repo's OVERNIGHT_PROGRESS.md, idempotently.

Used by deploy_watch.sh (Mac-side) when a Railway prod deploy FAILS: the failing
repo gets a high-priority fix item at the TOP of its queue so the scout picks it
next cycle. Kept as a standalone, side-effect-light script so the server-side
regression suite can test it without any Railway/network access.

Usage:  ovn_enqueue_emergency.py <progress_file> <service> <item_text>

Exit 0 = item added, OR an OPEN emergency item for this service already exists
         (no-op — so the every-N-min cron can't stack duplicates).
Exit 2 = bad arguments.

The item is inserted just after a leading H1 (if present) inside a dedicated
'## 🚨 Emergency' section. Dedup: if any OPEN ('- [ ]') line already contains the
EMERGENCY marker AND the service name, nothing is written.
"""
import sys

MARKER = "🚨 EMERGENCY DEPLOY FIX"
SECTION = "## 🚨 Emergency (auto-added by deploy_watch — do this first)"


def enqueue(text: str, service: str, item: str) -> tuple[str | None, bool]:
    """Return (new_text_or_None, added). new_text is None when it was a no-op."""
    lines = text.splitlines()
    for l in lines:
        if l.startswith("- [ ]") and MARKER in l and service in l:
            return None, False  # already an open emergency item for this service
    insert_at = 1 if (lines and lines[0].startswith("# ")) else 0
    block = ["", SECTION, item.rstrip(), ""]
    lines[insert_at:insert_at] = block
    return "\n".join(lines).rstrip("\n") + "\n", True


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: ovn_enqueue_emergency.py <file> <service> <item>", file=sys.stderr)
        return 2
    path, service, item = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        text = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        text = ""
    new_text, added = enqueue(text, service, item)
    if added:
        open(path, "w", encoding="utf-8").write(new_text)
        print(f"enqueued emergency item for {service}")
    else:
        print(f"emergency item for {service} already present — no-op")
    return 0


if __name__ == "__main__":
    sys.exit(main())
