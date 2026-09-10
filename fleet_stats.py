#!/usr/bin/env python3
"""fleet_stats.py — compute a fleet-wide snapshot and write state/fleet_stats.json.

CLAUDE_QUEUE.md §19: "a live, always-on version of the fleet snapshot dashboard
(first built as an Artifact 2026-09-06), plus the deeper metrics the snapshot
can't yet measure." This is the generator; fleet_dashboard.html renders its
output. Run from anywhere (resolves paths relative to this script); intended
to be cron'd every 15-30 min on the GPU server, e.g.:
    */15 * * * * cd ~/overnight-queue && python3 fleet_stats.py >> logs/fleet_stats.log 2>&1

Per-repo: {done, doable, landed_1d, landed_7d, runway_days, unpromoted,
pass_rate_7d, by_category}. Fleet-level: {llama_requests_today, tokens_today,
context_overflow_today}.

Data sources (no new instrumentation needed - all of this already exists):
  - repos/<repo>/OVERNIGHT_PROGRESS.md   -> done / doable counts
  - state/task_stats.log                 -> per-item outcome + classification
                                             tag, written by cycle_notify.sh
                                             every cycle (pass/revert/error/
                                             noop/skip - a real "did this
                                             land" signal, independent of the
                                             emit_alert stdout-pollution bug
                                             fixed 2026-09-07 in
                                             run_overnight.sh's outcomes.jsonl
                                             path)
  - git (origin/main..origin/develop)    -> unpromoted commit count
  - docker logs shrike-litellm           -> request count (proxy access log)
  - docker logs <llama container>        -> token counts + context-overflow
                                             count (llama.cpp's own per-slot
                                             "total time = ... / N tokens" and
                                             "truncated = " log lines)

Nothing here is fatal: a missing/unreachable data source degrades that one
field to null rather than crashing the whole snapshot (a partial dashboard
beats no dashboard).
"""
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_DIR = os.path.join(SCRIPT_DIR, "state")
REPOS_DIR = os.path.join(SCRIPT_DIR, "repos")
TASKS_FILE = os.path.join(SCRIPT_DIR, "tasks.json")
TASK_STATS_LOG = os.path.join(STATE_DIR, "task_stats.log")
OUT_FILE = os.path.join(STATE_DIR, "fleet_stats.json")

# task_stats.log's repo column doesn't match the repos/<dir> name for these two
# (hyphenated in the log, underscored/different on disk).
REPO_LOG_NAME = {
    "iptv_apps": "iptv-apps",
}

LLAMA_CONTAINER = os.environ.get("LLAMA_CONTAINER", "shrike-llama-dflash-35b")
LITELLM_CONTAINER = os.environ.get("LITELLM_CONTAINER", "shrike-litellm")


def sh(cmd, cwd=None, timeout=30):
    """Run a shell command, return stdout (empty string on any failure)."""
    try:
        r = subprocess.run(
            cmd, shell=True, cwd=cwd, capture_output=True, text=True,
            timeout=timeout, errors="replace",
        )
        return r.stdout
    except Exception:
        return ""


def enabled_repos():
    """[(task_id, repo_dirname), ...] for every enabled=true task in tasks.json,
    deduped by repo (a repo can have multiple tasks; one row is enough)."""
    try:
        with open(TASKS_FILE, encoding="utf-8") as f:
            tasks = json.load(f)
    except Exception:
        return []
    seen = set()
    out = []
    for t in tasks:
        if t.get("enabled", True) is False:
            continue
        repo_path = t.get("repo", "")
        dirname = os.path.basename(repo_path.rstrip("/"))
        if not dirname or dirname in seen:
            continue
        seen.add(dirname)
        out.append((t.get("id", dirname), dirname))
    return out


def queue_counts(repo_dir):
    """(done, doable) from OVERNIGHT_PROGRESS.md, matching the fleet-wide
    convention used throughout the coverage-sweep sessions: an item is
    "doable" only if it's unchecked AND not HUMAN-ONLY/AUTO-SKIP/BLOCKED/
    already-retired."""
    path = os.path.join(repo_dir, "OVERNIGHT_PROGRESS.md")
    done = doable = 0
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("- [x]"):
                    done += 1
                elif line.startswith("- [ ]"):
                    low = line.lower()
                    if not any(
                        m in low
                        for m in ("human-only", "human/", "auto-skip", "blocked item", "retired-")
                    ):
                        doable += 1
    except OSError:
        return None, None
    return done, doable


def git_unpromoted(repo_dir):
    """Commits on origin/develop not yet on origin/main (work landed but not
    promoted to prod). Fetches quietly first so the count reflects current
    remote state, not a possibly-stale local clone."""
    sh("git fetch -q origin main develop 2>/dev/null", cwd=repo_dir, timeout=60)
    out = sh(
        "git rev-list --count origin/main..origin/develop 2>/dev/null",
        cwd=repo_dir,
    ).strip()
    try:
        return int(out)
    except ValueError:
        return None


TAG_RE = re.compile(r"\{([^.·]*)[.·]([^.·]*)[.·]([^.·]*)[.·]([^}]*)\}")


def load_task_stats(cutoff_1d, cutoff_7d):
    """repo -> {'1d': [...], '7d': [...]} of {oc, lang, typ, cx, verif} rows,
    read once and sliced per-repo by every caller (task_stats.log is ~1MB and
    grows daily; one pass beats one file-read per repo)."""
    by_repo_7d = defaultdict(list)
    by_repo_1d = defaultdict(list)
    try:
        with open(TASK_STATS_LOG, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 5:
                    continue
                ts_s, repo, oc, tag, _file = parts[:5]
                try:
                    ts = float(ts_s)
                except ValueError:
                    continue
                if ts < cutoff_7d:
                    continue
                m = TAG_RE.match(tag)
                row = {
                    "oc": oc,
                    "lang": m.group(1) if m else "?",
                    "typ": m.group(2) if m else "?",
                }
                by_repo_7d[repo].append(row)
                if ts >= cutoff_1d:
                    by_repo_1d[repo].append(row)
    except OSError:
        pass
    return by_repo_7d, by_repo_1d


def pass_rate(rows):
    """% of PROCEED attempts (pass or revert - the model tried and either
    landed or got reverted by a gate) that actually landed. noop/skip/error
    are excluded from the denominator - they're not "the model tried and
    failed", they're "there was nothing to try" or an infra hiccup."""
    landed = sum(1 for r in rows if r["oc"] == "pass")
    reverted = sum(1 for r in rows if r["oc"] == "revert")
    attempted = landed + reverted
    if attempted == 0:
        return None
    return round(100.0 * landed / attempted, 1)


def by_category(rows):
    """{category: {landed, attempted, pass_rate}} - confirms/updates which
    item categories (vue/py/godot/typescript/...) the fleet's model actually
    succeeds at, per §19's 'what the LLM succeeds/fails at' goal."""
    cats = defaultdict(lambda: {"landed": 0, "attempted": 0})
    for r in rows:
        if r["oc"] not in ("pass", "revert"):
            continue
        c = cats[r["lang"]]
        c["attempted"] += 1
        if r["oc"] == "pass":
            c["landed"] += 1
    return {
        k: {**v, "pass_rate": round(100.0 * v["landed"] / v["attempted"], 1) if v["attempted"] else None}
        for k, v in sorted(cats.items())
    }


def llama_token_stats(since="24h"):
    """(tokens_total, context_overflow_count) from llama.cpp's own per-slot
    timing lines in the container's docker logs. Returns (None, None) if the
    container isn't reachable (e.g. this ran from a machine without docker
    access) rather than raising."""
    log = sh(f"docker logs {LLAMA_CONTAINER} --since {since} 2>&1", timeout=30)
    if not log:
        return None, None
    tokens = 0
    for m in re.finditer(r"total time\s*=\s*[\d.]+\s*ms\s*/\s*(\d+)\s*tokens", log):
        tokens += int(m.group(1))
    overflow = len(re.findall(r"truncated\s*=\s*([1-9]\d*)", log))
    return tokens, overflow


def litellm_request_count(since="24h"):
    log = sh(f"docker logs {LITELLM_CONTAINER} --since {since} 2>&1", timeout=30)
    if not log:
        return None
    return len(re.findall(r'"POST /v1/chat/completions', log))


def main():
    now = time.time()
    cutoff_1d = now - 86400
    cutoff_7d = now - 7 * 86400

    stats_7d, stats_1d = load_task_stats(cutoff_1d, cutoff_7d)

    repos_out = {}
    for task_id, dirname in enabled_repos():
        repo_dir = os.path.join(REPOS_DIR, dirname)
        if not os.path.isdir(repo_dir):
            continue
        log_name = REPO_LOG_NAME.get(dirname, dirname)
        rows_7d = stats_7d.get(log_name, [])
        rows_1d = stats_1d.get(log_name, [])
        done, doable = queue_counts(repo_dir)
        landed_7d = sum(1 for r in rows_7d if r["oc"] == "pass")
        landed_1d = sum(1 for r in rows_1d if r["oc"] == "pass")
        runway_days = round(doable / (landed_7d / 7.0), 1) if doable is not None and landed_7d > 0 else None
        repos_out[dirname] = {
            "task_id": task_id,
            "done": done,
            "doable": doable,
            "landed_1d": landed_1d,
            "landed_7d": landed_7d,
            "runway_days": runway_days,
            "unpromoted": git_unpromoted(repo_dir),
            "pass_rate_7d": pass_rate(rows_7d),
            "by_category_7d": by_category(rows_7d),
        }

    tokens_today, overflow_today = llama_token_stats("24h")

    out = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "repos": repos_out,
        "fleet": {
            "llama_requests_today": litellm_request_count("24h"),
            "tokens_today": tokens_today,
            "context_overflow_today": overflow_today,
        },
    }

    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = OUT_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    os.replace(tmp, OUT_FILE)  # atomic - a concurrent reader never sees a partial write
    print(f"wrote {OUT_FILE} ({len(repos_out)} repos)")


if __name__ == "__main__":
    sys.exit(main() or 0)
