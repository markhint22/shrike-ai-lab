#!/usr/bin/env python3
"""ovn_feature_groups.py — group backlog/queue items into "features" for progress
tracking (% complete) and completion detection.

INVESTIGATION (2026-09-20): a real feature-grouping structure already exists, one layer
up from the live queue: roadmap/<repo>.md lists features as
`- [ ] [P<1-4>] [<status>] <feature> — <why> {cat:...; size:...; multifile:...; research:...}`
with status needs-research -> ready -> decomposed -> done (see roadmap/README.md). When a
feature is [ready], ovn_planner.sh (cron, hourly) decomposes it into 6-10 tiered backlog
items appended under a `# --- 27B-decomposed from roadmap [date]: <feature> ---` comment in
backlog/<repo>.md, and flips the roadmap line to [decomposed].

The gap: that link was thrown away the moment an item left backlog/<repo>.md. queue_refill.py
(the "dumb pull" that feeds OVERNIGHT_PROGRESS.md) copies each `- [ ] [T#] ...` line VERBATIM,
with nothing on it identifying which feature spawned it — so before this file there was no way
to answer "how much of feature X is done" for ANY already-decomposed feature, old or new; the
grouping information existed for a few hours in backlog/<repo>.md and then vanished.

FIX: ovn_planner.sh now appends a durable `[feat:<repo>-<date>-<slug>]` tag to every item it
decomposes, which survives checkbox toggling (run_overnight.sh's sed only ever rewrites the
"- [ ] " prefix) and archival to OVERNIGHT_DONE.md (archive_done.py moves lines verbatim). This
script groups by that tag when present — a REAL, precise feature group (kind="feat").

For everything decomposed BEFORE this change (the large majority of current backlog history)
there is no such tag and never will be retroactively. As a best-effort APPROXIMATION only —
explicitly NOT real feature-boundary detection; several unrelated one-off polish items landing
in the same file is not the same thing as one product feature — this script also groups by
TARGET FILE (kind="file"): every item already names an exact file per OVERNIGHT_PROGRESS.md's
own house rule ("Every item names an EXACT file"), extracted from the first backtick-quoted
path on the line. File-kind groups are always labeled "approx" wherever they're surfaced and
are NEVER used to fire a completion notification (see ovn_feature_watch.sh) — only a real
feat-tagged group is a trustworthy enough signal for "this feature is done, go test it."

Usage:
  ovn_feature_groups.py <repo> [--min-total N] [--json]
      per-repo group listing (used by the completion watcher).
  ovn_feature_groups.py --digest <hours> [--max-total N]
      cross-references state/task_stats.log's landed rows in the trailing <hours> against
      every active repo's groups and prints only the ones that had activity in the window —
      for the ntfy digests. Prints nothing if no multi-item group was active.

Env: OVN_REPOS_DIR overrides ~/overnight-queue/repos; OVN_QUEUE_DIR overrides ~/overnight-queue
(used to locate backlog/<repo>.md and state/task_stats.log).
"""
import json
import os
import re
import sys
import time

QUEUE_DIR = os.environ.get("OVN_QUEUE_DIR", os.path.expanduser("~/overnight-queue"))
REPOS_DIR = os.environ.get("OVN_REPOS_DIR", os.path.join(QUEUE_DIR, "repos"))
BACKLOG_DIR = os.environ.get("OVN_BACKLOG_DIR", os.path.join(QUEUE_DIR, "backlog"))
TASK_STATS = os.environ.get("OVN_TASK_STATS", os.path.join(QUEUE_DIR, "state", "task_stats.log"))

ITEM_RE = re.compile(r'^-\s*\[( |x|X)\]\s*(.*)$')
FEAT_RE = re.compile(r'\[feat:([A-Za-z0-9_-]+)\]')
FILE_RE = re.compile(r'`([^`]+)`')

# extensions actually used across the fleet's repos (see ovn_planner.sh's own "category" list +
# EXT_LANG in ovn_classify.py). Real target-file backticks always end in one of these; a bare
# `\.[A-Za-z0-9]{1,8}$` check (the first cut of this heuristic) was catching code-snippet
# backticks that merely END in something extension-shaped — e.g. `return 1.5 if is_flanking
# else 1.0` (ext "0"), `OS.execute` (ext "execute") — as if they were files. Confirmed live on
# xlite: ~15 of ~49 "file" groups from a real production scan were exactly this false-positive
# shape, not a real shared target file at all.
KNOWN_EXTS = {
    'py', 'ts', 'tsx', 'js', 'jsx', 'vue', 'gd', 'tres', 'tscn', 'kt', 'kts', 'swift', 'dart',
    'md', 'json', 'yaml', 'yml', 'sh', 'sql', 'html', 'css', 'gradle', 'xml', 'plist', 'toml',
}


def _looks_like_path(s):
    if not s or re.search(r'[\s"\'(){}=<>]', s):
        return False
    if '/' in s:
        return True
    m = re.search(r'\.([A-Za-z0-9]{1,8})$', s)
    return bool(m) and m.group(1).lower() in KNOWN_EXTS


def parse_file(path, groups):
    """Fold every - [ ]/- [x] item line in `path` into `groups`: {(kind,key): {total,checked,files}}."""
    if not os.path.exists(path):
        return
    for line in open(path, encoding="utf-8", errors="replace"):
        m = ITEM_RE.match(line.strip())
        if not m:
            continue
        checked = m.group(1).lower() == "x"
        rest = m.group(2)
        fm = FEAT_RE.search(rest)
        pm = FILE_RE.search(rest)
        item_file = pm.group(1) if (pm and _looks_like_path(pm.group(1))) else None
        if fm:
            key = ("feat", fm.group(1))
        elif item_file:
            key = ("file", item_file)
        else:
            continue
        g = groups.setdefault(key, {"total": 0, "checked": 0, "files": set()})
        g["total"] += 1
        if checked:
            g["checked"] += 1
        if item_file:
            g["files"].add(item_file)


def backlog_remaining(repo, feat_id):
    """How many [feat:feat_id] items are still sitting unpulled in backlog/<repo>.md — a
    feat group can't be "done" while the planner still has more of it queued to hand out."""
    bl = os.path.join(BACKLOG_DIR, f"{repo}.md")
    if not os.path.exists(bl):
        return 0
    tag = f"[feat:{feat_id}]"
    n = 0
    for line in open(bl, encoding="utf-8", errors="replace"):
        if line.startswith("- [ ]") and tag in line:
            n += 1
    return n


def repo_groups(repo, min_total=2):
    groups = {}
    parse_file(os.path.join(REPOS_DIR, repo, "OVERNIGHT_PROGRESS.md"), groups)
    parse_file(os.path.join(REPOS_DIR, repo, "OVERNIGHT_DONE.md"), groups)
    out = []
    for (kind, key), g in groups.items():
        if g["total"] < min_total:
            continue
        rem = backlog_remaining(repo, key) if kind == "feat" else 0
        pct = round(100 * g["checked"] / g["total"])
        out.append({
            "repo": repo, "kind": kind, "key": key,
            "checked": g["checked"], "total": g["total"],
            "backlog_remaining": rem, "pct": pct,
            "done": (kind == "feat" and g["checked"] == g["total"] and rem == 0),
            "_files": g["files"],
        })
    out.sort(key=lambda r: (-r["pct"], -r["total"]))
    return out


def _fmt_line(r):
    label = r["key"] if r["kind"] == "feat" else os.path.basename(r["key"])
    approx = "" if r["kind"] == "feat" else " (approx: same-file grouping, not a real feature)"
    return f"{r['repo']} {label}: {r['checked']}/{r['total']} ({r['pct']}%){approx}"


def cmd_repo(repo, min_total, as_json):
    groups = repo_groups(repo, min_total)
    if as_json:
        print(json.dumps([{k: v for k, v in r.items() if k != "_files"} for r in groups]))
    else:
        for r in groups:
            print(_fmt_line(r))


def cmd_digest(hours, max_total):
    cutoff = time.time() - hours * 3600
    landed_by_repo = {}
    if os.path.exists(TASK_STATS):
        for ln in open(TASK_STATS, encoding="utf-8", errors="replace"):
            p = ln.rstrip("\n").split("\t")
            if len(p) < 5:
                continue
            ts_raw, repo, oc, _tag, fpath = p[:5]
            if oc != "pass":
                continue
            try:
                ts = float(ts_raw)
            except ValueError:
                continue
            if ts < cutoff:
                continue
            landed_by_repo.setdefault(repo, set()).add(fpath)

    lines = []
    total = 0
    for repo in sorted(landed_by_repo):
        if total >= max_total:
            break
        landed_files = landed_by_repo[repo]

        def _touched(r):
            if r["kind"] == "file":
                return r["key"] in landed_files
            return bool(r["_files"] & landed_files)

        cands = [r for r in repo_groups(repo, min_total=2) if _touched(r)]
        for r in cands:
            if total >= max_total:
                break
            lines.append("  " + _fmt_line(r))
            total += 1
    if not lines:
        return
    print("🧩 Feature progress (active this window):")
    print("\n".join(lines))


def main():
    argv = sys.argv[1:]
    if "--digest" in argv:
        i = argv.index("--digest")
        hours = float(argv[i + 1]) if i + 1 < len(argv) and not argv[i + 1].startswith("--") else 3.0
        max_total = 6
        if "--max-total" in argv:
            j = argv.index("--max-total"); max_total = int(argv[j + 1])
        cmd_digest(hours, max_total)
        return
    pos = [a for a in argv if not a.startswith("--")]
    if not pos:
        print("usage: ovn_feature_groups.py <repo> [--min-total N] [--json]  |  ovn_feature_groups.py --digest <hours> [--max-total N]", file=sys.stderr)
        sys.exit(2)
    repo = pos[0]
    min_total = 2
    if "--min-total" in argv:
        i = argv.index("--min-total"); min_total = int(argv[i + 1])
    cmd_repo(repo, min_total, "--json" in argv)


if __name__ == "__main__":
    main()
