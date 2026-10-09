#!/usr/bin/env python3
"""ovn_fold_migration_items.py - keep a model-column item and its "create the migration" sibling ONE unit (2026-10-02, harness Y1).

MEASURED (iptv_apps 'Add last_event_ms column', 2026-10-02): the planner split one schema change into a T1 item "app/models/subscription.py - add
last_event_ms" and a T2 item "alembic/versions/0011_...py - create migration", same [feat:...] tag. Neither can be green alone: the model-only
commit fails tests/test_migration_drift.py, and the migration-only item has a guessed file name / revision and forks the chain. The alembic
autogen hook (scripts/ovn_alembic_autogen.sh) now generates the migration deterministically in the SAME step that edits the model, so the model
item is self-sufficient and the separate migration item is redundant AND harmful (the 27B hand-writes a second migration -> MULTIPLE HEADS).

Rule (pure text edit, no LLM, idempotent): when the repo is on the autogen allowlist (OVN_ALEMBIC_AUTOGEN_REPOS, same default as the hook) and
has tests/test_migration_drift.py, an UNCHECKED migration item (names alembic/versions/*.py) that shares its [feat:...] tag with an UNCHECKED
model item (names a models/ or models.py path) is retired in place as "- [x] (retired-folded-migration) ...". It is only folded while the model
sibling is still open: once the model item has landed, a still-open migration item is genuine work (the hook did not produce one) and is kept.
A migration item whose text carries data/drop/alter/rename/backfill work (DATA_WORK_RE) is never folded: the hook is structural-only and
refuses that work, so retiring it would silently drop it. Items without a feat tag, with a different tag, or in a repo off the allowlist are never touched.

usage: ovn_fold_migration_items.py <OVERNIGHT_PROGRESS.md> <repo_root> [repo_name]      prints "folded N"
"""
import glob
import os
import re
import sys

DEFAULT_ALLOW = "test-automation-agent iptv_apps"
FEAT_RE = re.compile(r"\[feat:([^\]]+)\]")
MIG_RE = re.compile(r"alembic/versions/[A-Za-z0-9_./-]*\.py")
MODEL_RE = re.compile(r"(^|[/\s`(])(models?/[A-Za-z0-9_./-]*\.py|[A-Za-z0-9_./-]*/models?\.py|models?\.py)")
# Work the structural-only autogen hook cannot produce (it refuses drop/alter; "credit never covers data work"). A migration item that
# mentions any of it is genuine work, so it is NEVER folded (kept open even while the model sibling is open).
DATA_WORK_RE = re.compile(
    r"back-?fill|data[- ](migration|work|fix|copy)|\b(update|insert|delete|drop|alter|rename|truncate|populate|convert|transform)s?\b"
    r"|\bmigrate (the )?(existing|old)|existing (rows|records|data)|\bchange[sd]? (the )?(column )?type|\bset not null",
    re.I)
SKIP_RE = re.compile(r"AUTO-SKIP|HUMAN-ONLY|\[CLAUDE\]|(?-i:BLOCKED)|\(retired-", re.I)


def _featkey(line):
    m = FEAT_RE.search(line)
    if not m:
        return None
    # same date-stamp strip as ovn_item_hash: regenerations of one feature differ only by the embedded date
    return re.sub(r"-[0-9]{6,8}-", "-", m.group(1))


def _eligible(root, name):
    allow = os.environ.get("OVN_ALEMBIC_AUTOGEN_REPOS", DEFAULT_ALLOW).split()
    if os.environ.get("OVN_ALEMBIC_AUTOGEN_DISABLE") or os.environ.get("OVN_FOLD_MIGRATION") == "off":
        return False
    if name not in allow:
        return False
    return bool(glob.glob(os.path.join(root, "**", "tests", "test_migration_drift.py"), recursive=True))


def fold(prog, root, name):
    if not os.path.isfile(prog) or not _eligible(root, name):
        return 0
    lines = open(prog, encoding="utf-8").read().split("\n")
    open_models = set()
    for ln in lines:
        if ln.startswith("- [ ] ") and not SKIP_RE.search(ln) and MODEL_RE.search(ln) and not MIG_RE.search(ln):
            k = _featkey(ln)
            if k:
                open_models.add(k)
    n = 0
    for i, ln in enumerate(lines):
        if not ln.startswith("- [ ] ") or SKIP_RE.search(ln) or not MIG_RE.search(ln):
            continue
        k = _featkey(ln)
        if k and k in open_models and not DATA_WORK_RE.search(ln):
            lines[i] = "- [x] (retired-folded-migration: the alembic autogen hook creates it with the model item) " + ln[len("- [ ] "):]
            n += 1
    if n:
        open(prog, "w", encoding="utf-8").write("\n".join(lines))
    return n


if __name__ == "__main__":
    prog, root = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else os.path.basename(os.path.abspath(root))
    print("folded %d" % fold(prog, root, name))
