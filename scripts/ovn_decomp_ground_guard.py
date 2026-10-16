#!/usr/bin/env python3
"""scripts/ovn_decomp_ground_guard.py - drop planner-decomposed backlog steps that contradict the repo.

The planner's 27B decomposes a roadmap feature WITHOUT reading the repo (it only sees a path list), so it
keeps producing steps that tell the implementer to build something that already exists:
  * "Implement `assert_public_url(...)`" when url_safety.py already defines it (would rewrite working code)
  * "Create tests/test_url_safety.py" when that test file already exists (would clobber a passing suite)
  * test paths in a directory the repo's runner never collects (xlite res://test/ instead of res://tests/,
    iptv tests placed under app/)
Each of those was seen live on 2026-10-05. This guard checks the three facts deterministically.

Usage: printf '%s\n' "$items" | ovn_decomp_ground_guard.py <repo_dir>
Reads item lines on stdin, writes the kept lines to stdout (original order), one "dropped:" line per removed
step to stderr. Fail-safe: if filtering would leave fewer than MIN_KEEP items, or anything goes wrong, the
ORIGINAL lines are printed unchanged (a planner must never lose a decomposition to its own guard).
Exit 0 always.
"""
import os
import re
import sys

MIN_KEEP = 2
ITEM_RE = re.compile(r"^- \[ \] \[T[1-5]\] (?P<path>\S+) — (?P<body>.*)$")
CREATE_VERB_RE = re.compile(r"^(Create|Write|Implement|Define)\b", re.I)
SYMBOL_RE = re.compile(r"`([A-Za-z_][A-Za-z0-9_]*)\s*\(")
DEF_TMPL = r"(?:def|func|fun|function|static func)\s+%s\s*\("
TEST_NAME_RE = re.compile(r"(^|/)(test_[^/]+\.(py|gd)|[^/]+\.(test|spec)\.(ts|tsx|js))$")


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def _bad_test_location(repo_name, rel):
    """True when a test file is placed where the repo's runner never collects it."""
    if not TEST_NAME_RE.search(rel):
        return None
    if repo_name == "xlite" and (rel.startswith("test/") or rel.startswith("res://test/")):
        return "xlite collects res://tests/ only, not test/"
    if repo_name == "iptv_apps" and re.search(r"(^|/)app/.+/test_[^/]+\.py$", rel):
        return "iptv_apps collects iptv-backend/tests/ only (pytest testpaths), not next to app modules"
    return None


def judge(line, repo_dir):
    """Return a drop reason for one item line, or None to keep it."""
    m = ITEM_RE.match(line.strip())
    if not m:
        return None
    rel, body = m.group("path"), m.group("body")
    repo_name = os.path.basename(os.path.normpath(repo_dir))
    loc = _bad_test_location(repo_name, rel)
    if loc:
        return loc
    full = os.path.join(repo_dir, rel)
    if not CREATE_VERB_RE.match(body):
        return None
    if os.path.isfile(full) and TEST_NAME_RE.search(rel) and re.match(r"^(Create|Write)\b", body, re.I):
        return "test file already exists (a 'Create' step would overwrite it)"
    text = _read(full)
    if text is None:
        return None
    for sym in SYMBOL_RE.findall(body):
        if re.search(DEF_TMPL % re.escape(sym), text):
            return "`%s` is already defined in %s (Implement/Create/Define would rewrite it)" % (sym, rel)
    return None


def main(argv):
    repo_dir = argv[1] if len(argv) > 1 else "."
    lines = sys.stdin.read().split("\n")
    out, dropped = [], []
    try:
        for l in lines:
            reason = judge(l, repo_dir) if l.strip() else None
            if reason:
                dropped.append((l, reason))
            else:
                out.append(l)
    except Exception as e:  # never lose a decomposition to a guard bug
        sys.stderr.write("ground-guard error, passing items through: %s\n" % e)
        sys.stdout.write("\n".join(lines))
        return 0
    kept_items = [l for l in out if ITEM_RE.match(l.strip())]
    if dropped and len(kept_items) < MIN_KEEP:
        sys.stderr.write("ground-guard would leave %d item(s) - passing all %d through unchanged for review\n"
                         % (len(kept_items), len(kept_items) + len(dropped)))
        sys.stdout.write("\n".join(lines))
        return 0
    for l, why in dropped:
        sys.stderr.write("ground-guard dropped step: %s | %s\n" % (why, l.strip()[:110]))
    sys.stdout.write("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
