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
(used to locate backlog/<repo>.md, roadmap/<repo>.md and state/task_stats.log).

Usage (cont'd, 2026-09-20):
  ovn_feature_groups.py --in-progress [--max-total N]
      every real (feat-tagged) group across all repos that is NOT yet done, with its
      human-readable title when it can be resolved from roadmap/<repo>.md - for the
      digest's proactive "features in progress" section. Never includes file-kind
      approximate groups (see this module's header for why those aren't trustworthy
      enough to surface as a "feature").
  ovn_feature_groups.py --ready-count <hours>
      prints a single integer: how many real feat-kind groups both (a) hit 100% (done)
      and (b) had landed activity in the trailing <hours> - for the digest's one-line
      "N feature(s) ready to test" summary. Deliberately NOT deduped against
      ovn_feature_watch.sh's own notified-log (that log exists to make the distinct
      celebratory push a one-time event; this is a routine summary line that's fine to
      keep mentioning a still-untested feature every digest).
"""
import glob
import json
import os
import re
import sys
import time

QUEUE_DIR = os.environ.get("OVN_QUEUE_DIR", os.path.expanduser("~/overnight-queue"))
REPOS_DIR = os.environ.get("OVN_REPOS_DIR", os.path.join(QUEUE_DIR, "repos"))
BACKLOG_DIR = os.environ.get("OVN_BACKLOG_DIR", os.path.join(QUEUE_DIR, "backlog"))
ROADMAP_DIR = os.environ.get("OVN_ROADMAP_DIR", os.path.join(QUEUE_DIR, "roadmap"))
TASK_STATS = os.environ.get("OVN_TASK_STATS", os.path.join(QUEUE_DIR, "state", "task_stats.log"))

ITEM_RE = re.compile(r'^-\s*\[( |x|X)\]\s*(.*)$')
FEAT_RE = re.compile(r'\[feat:([A-Za-z0-9_-]+)\]')
FILE_RE = re.compile(r'`([^`]+)`')

# 2026-09-20: a [feat:ID] tag on its own (e.g. "xlite-20260920-appool-fill-percentage-for-an-
# ap-bar-ui-") is not human-readable. ovn_planner.sh mints it as
# "<repo>-<decompose-date:YYYYMMDD>-<slug of the FULL remaining roadmap line text, cut to 40
# chars>" (see ovn_planner.sh's own "feature tracking" comment) - note the slug is derived
# from the ENTIRE "<title> — <why> {tags}" text, not just the title, so re-deriving it here
# has to slugify the same full text a roadmap line would produce, not just its title, or the
# cut-to-40 boundary won't line up and nothing will match.
FEAT_ID_RE = re.compile(r'^(?P<repo>.+?)-(?P<date>\d{8})-(?P<slug>.+)$')
FEAT_LINE_RE = re.compile(r'^-\s*\[[ xX]\]\s*\[P\d+\]\s*\[[a-z-]+\]\s*(.*)$')


def _slugify(text, cut=40):
    """Mirror ovn_planner.sh's `tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g;
    s/^-+//; s/-+$//' | cut -c1-40` exactly, so a feat_id's slug can be re-derived from
    roadmap text and matched byte-for-byte."""
    s = re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')
    return s[:cut]


def feature_title(repo, feat_id):
    """Best-effort human-readable title for a [feat:ID] tag: re-derive the slug
    ovn_planner.sh minted the id from and match it against every roadmap/<repo>.md
    feature line's own re-slugified text. Returns None (never fabricates a title) if
    the id doesn't parse, the roadmap file is missing, or no line's slug matches (e.g.
    the roadmap line was since edited or removed) - callers should fall back to the
    raw feat_id or a file-only display, not invent a name."""
    m = FEAT_ID_RE.match(feat_id or "")
    if not m or m.group("repo") != repo:
        return None
    target_slug = m.group("slug")
    rm = os.path.join(ROADMAP_DIR, f"{repo}.md")
    if not os.path.exists(rm):
        return None
    for line in open(rm, encoding="utf-8", errors="replace"):
        lm = FEAT_LINE_RE.match(line.rstrip("\n"))
        if not lm:
            continue
        feat_text = lm.group(1)
        if _slugify(feat_text) == target_slug:
            # human title = the part before the " — why" separator (the same
            # "<feature> — <why>" convention ovn_planner.sh's own decompose prompt
            # uses) - falls back to the first 90 chars if no separator is present.
            title = feat_text.split(" — ", 1)[0].strip()
            return title[:90] if title else None
    return None

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


# 2026-09-20: ovn_planner.sh's own decompose prompt template is `[T<1-5>] <real/path.ext> —
# <change> VERIFY: <command>. (cat:...)` - the target path is NOT backtick-wrapped (only
# inline code snippets and the VERIFY command are), unlike the older hand-authored
# OVERNIGHT_PROGRESS.md house style FILE_RE above was written for ("every item names an EXACT
# file" in backticks). Confirmed live on a real planner-decomposed xlite item: FILE_RE's first
# backtick match landed on an inline code snippet ("`static func percent_full(...)`"), got
# correctly rejected by _looks_like_path (it has parens/spaces), and the item's real target
# file was never recorded in `files` at all - every [feat:] group ovn_planner.sh produces
# would silently never resolve to any file, breaking feat_lookup_for_file's (and this
# function's own file-kind grouping's) ability to attribute a landed file back to it. Fall
# back to the bare leading token right after the item's own [tag] when no valid backtick path
# was found.
LEADING_PATH_RE = re.compile(r'^\[[^\]]*\]\s*(\S+)')


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
        if item_file is None:
            lm = LEADING_PATH_RE.match(rest)
            if lm and _looks_like_path(lm.group(1)):
                item_file = lm.group(1)
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


def feat_lookup_for_file(repo, fpath, min_total=2):
    """-> (feat_id, title_or_None, pct) for the real feat-tagged group (if any) that
    contains this landed file in repo_groups(repo), else None. Used by
    ovn_landed_detail.py to attribute a per-item digest line to its parent feature.
    File-kind approximate groups are intentionally never matched here — this is an
    attribution, and an approx same-file group is explicitly not a trustworthy enough
    signal for that (see this module's header)."""
    for r in repo_groups(repo, min_total):
        if r["kind"] != "feat":
            continue
        if fpath in r["_files"]:
            return r["key"], feature_title(repo, r["key"]), r["pct"]
    return None


def _landed_files_by_repo(hours):
    """-> {repo: {file, ...}} of every file with a 'pass' row in state/task_stats.log
    within the trailing <hours>. Shared by cmd_digest and cmd_ready_count so both use
    the exact same window-membership logic."""
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
    return landed_by_repo


def all_repo_names():
    """Every repo the fleet has a checkout for (mirrors ovn_feature_watch.sh's own
    iteration), sorted for deterministic output."""
    if not os.path.isdir(REPOS_DIR):
        return []
    return sorted(
        os.path.basename(p.rstrip("/"))
        for p in glob.glob(os.path.join(REPOS_DIR, "*"))
        if os.path.isdir(p)
    )


def cmd_digest(hours, max_total):
    landed_by_repo = _landed_files_by_repo(hours)

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


def cmd_in_progress(max_total):
    """Every real (feat-kind), not-yet-done group across ALL repos, human title when
    resolvable - regardless of whether it had activity in any particular window (a
    feature can sit "in progress" for days between fleet touches and this is meant to
    stay visible the whole time). File-kind approximate groups are never included -
    see this module's header for why those aren't a trustworthy enough signal."""
    lines = []
    total = 0
    for repo in all_repo_names():
        if total >= max_total:
            break
        for r in repo_groups(repo, min_total=2):
            if r["kind"] != "feat" or r["done"]:
                continue
            if total >= max_total:
                break
            title = feature_title(repo, r["key"])
            label = f'"{title}"' if title else r["key"]
            lines.append(f"  {repo} {label} — {r['checked']}/{r['total']} items ({r['pct']}%)")
            total += 1
    if not lines:
        return
    print("🔧 Features in progress:")
    print("\n".join(lines))


def cmd_ready_count(hours):
    """Prints a single integer: real feat-kind groups that are both done (100% +
    nothing left queued in the backlog) and had a landed item in the trailing <hours>
    - for the digest's one-line "N feature(s) ready to test" summary."""
    landed_by_repo = _landed_files_by_repo(hours)
    n = 0
    for repo, landed_files in landed_by_repo.items():
        for r in repo_groups(repo, min_total=2):
            if r["kind"] == "feat" and r["done"] and (r["_files"] & landed_files):
                n += 1
    print(n)


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
    if "--in-progress" in argv:
        max_total = 6
        if "--max-total" in argv:
            j = argv.index("--max-total"); max_total = int(argv[j + 1])
        cmd_in_progress(max_total)
        return
    if "--ready-count" in argv:
        i = argv.index("--ready-count")
        hours = float(argv[i + 1]) if i + 1 < len(argv) and not argv[i + 1].startswith("--") else 3.0
        cmd_ready_count(hours)
        return
    pos = [a for a in argv if not a.startswith("--")]
    if not pos:
        print("usage: ovn_feature_groups.py <repo> [--min-total N] [--json]  |  "
              "ovn_feature_groups.py --digest <hours> [--max-total N]  |  "
              "ovn_feature_groups.py --in-progress [--max-total N]  |  "
              "ovn_feature_groups.py --ready-count <hours>", file=sys.stderr)
        sys.exit(2)
    repo = pos[0]
    min_total = 2
    if "--min-total" in argv:
        i = argv.index("--min-total"); min_total = int(argv[i + 1])
    cmd_repo(repo, min_total, "--json" in argv)


if __name__ == "__main__":
    main()
