#!/usr/bin/env python3
"""Overnight-queue throughput + pass-rate, sliced by classification axis.

Reads state/task_stats.log rows: <epoch>\t<repo>\t<outcome>\t{lang.type.cx.verif}\t<file>
outcome in {pass, fail, revert, error, noop, skip}.

Leads with THROUGHPUT (landed / no-op / failed / errored) — what a human actually
cares about — then flags only the cells worth attention: what's producing, what's
just spinning (all no-op = exhausted or unverifiable), and any real failures.

Usage: ovn_stats.py [hours=24] [--ntfy]
"""
import os, re, sys, time
from collections import defaultdict

P = os.path.expanduser("~/overnight-queue/state/task_stats.log")
args = [a for a in sys.argv[1:] if not a.startswith('--')]
ntfy = '--ntfy' in sys.argv
hours = float(args[0]) if args else 24.0
cutoff = time.time() - hours * 3600

rows = []
if os.path.exists(P):
    for ln in open(P):
        p = ln.rstrip("\n").split("\t")
        if len(p) < 5:
            continue
        ts, repo, oc, tag, f = p[:5]
        try:
            ts = float(ts)
        except ValueError:
            continue
        if ts < cutoff:
            continue
        m = re.match(r'\{([^.·]*)[.·]([^.·]*)[.·]([^.·]*)[.·]([^}]*)\}', tag)
        if not m:
            continue
        lang, typ, cx, verif = m.groups()
        rows.append({'ts': ts, 'oc': oc, 'lang': lang, 'type': typ, 'cx': cx, 'verif': verif})

if not rows:
    print("no queue activity recorded in the last %gh yet" % hours)
    sys.exit(0)

def c(sub):
    """-> (landed, failed, noop, errored). 'skip' (an exhausted repo skipped
    before the model ran) is deliberately NOT counted as a no-op — it's idle,
    not wasted work — and is surfaced separately as an 'Idle' line."""
    landed = sum(1 for r in sub if r['oc'] == 'pass')
    failed = sum(1 for r in sub if r['oc'] in ('fail', 'revert'))
    noop = sum(1 for r in sub if r['oc'].startswith('noop'))
    err = sum(1 for r in sub if r['oc'] == 'error')
    return landed, failed, noop, err


# Human-readable label + one-line meaning for each no-op cause, so the digest
# tells you WHICH problem to fix: exhausted (refill/features), or a real bug.
NOOP_CAUSES = [
    ('noop:flail',   'flailed',  'too hard for the 27B — route to Claude or simplify the item'),
    ('noop:done',    'done',     'already satisfied in code — mis-targeted item, retarget or credit it'),
    ('noop:blocked', 'blocked',  'model wants a human decision — the item is under-specified'),
    ('noop:gate',    'gate-rev', 'model changed code but a safety gate reverted it'),
]

def noop_breakdown(sub):
    """-> {cause_key: count} over the no-op rows (legacy bare 'noop' -> flail)."""
    d = {}
    for r in sub:
        oc = r['oc']
        if not oc.startswith('noop'):
            continue
        key = oc if oc in (c[0] for c in NOOP_CAUSES) else 'noop:flail'
        d[key] = d.get(key, 0) + 1
    return d


def runway():
    """Per active repo: (repo, open_doable, days_str, burn24h). Runway = open items
    / recent daily burn (substantive commits in the last 24h on the working branch)."""
    import glob, subprocess
    rdir = os.environ.get("OVN_REPOS_DIR")
    if not rdir or not os.path.isdir(rdir):
        return []
    active = set(os.environ.get("OVN_ACTIVE_REPOS", "").split())
    out = []
    for prog in sorted(glob.glob(os.path.join(rdir, "*", "OVERNIGHT_PROGRESS.md"))):
        repo = os.path.basename(os.path.dirname(prog))
        if active and repo not in active:
            continue
        try:
            txt = open(prog, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        doable = sum(1 for l in txt.splitlines()
                     if l.lstrip().startswith("- [ ]")
                     and not re.search(r"HUMAN-ONLY|human/|AUTO-SKIP|BLOCKED ITEM|retired-", l))
        rd = os.path.dirname(prog)
        try:
            log = subprocess.run(["git","-C",rd,"log","--since=24 hours ago","--pretty=%s"],
                                 capture_output=True, text=True, timeout=15).stdout
            burn = sum(1 for l in log.splitlines()
                       if re.match(r"(feat|fix|test|perf|refactor)", l)
                       and not re.search(r"auto-credit|auto-skip|reconcile|rebalance", l))
        except Exception:
            burn = 0
        if doable == 0:
            days = "0d"
        elif burn == 0:
            days = "stalled?"
        else:
            d = doable / burn
            days = ("~%.0fd" % d) if d >= 1 else "<1d"
        out.append((repo, doable, days, burn))
    return out

L, F, N, E = c(rows)
total = len(rows)

def group(axis):
    g = defaultdict(list)
    for r in rows:
        g[r[axis]].append(r)
    return g

def producing(axis, top=4):
    out = [(k, c(v)[0]) for k, v in group(axis).items()]
    out = [(k, l) for k, l in out if l > 0]
    out.sort(key=lambda x: -x[1])
    return out[:top]

def spinning(axis, minnoop=5):
    """cells that ONLY ever no-op (0 landed, 0 failed) = exhausted / already-done / unverifiable."""
    out = []
    for k, v in group(axis).items():
        l, f, n, e = c(v)
        if l == 0 and f == 0 and n >= minnoop:
            out.append((k, n))
    out.sort(key=lambda x: -x[1])
    return out

def failing(axis):
    out = []
    for k, v in group(axis).items():
        l, f, n, e = c(v)
        if f > 0:
            out.append((k, 100 * l // (l + f)))
    out.sort(key=lambda x: x[1])
    return out

if ntfy:
    lines = ["Overnight · %gh · %d cycles" % (hours, total)]
    head = "✅ %d landed   ➖ %d no-op   ❌ %d failed" % (L, N, F)
    if E:
        # recency: how long since the last error? a stale spike shouldn't look ongoing.
        last_err_ts = max((r.get('ts', 0) for r in rows if r['oc'] == 'error'), default=0)
        mins = int((time.time() - last_err_ts) / 60) if last_err_ts else 0
        if mins >= 25:
            head += "   ⚠ %d errored (RESOLVED — last %dm ago)" % (E, mins)
        else:
            head += "   ⚠ %d errored (ONGOING — last %dm ago)" % (E, mins)
    lines.append(head)
    # always show the most-recent 30 min so current health is unambiguous
    r30 = [r for r in rows if r.get('ts', 0) >= time.time() - 1800]
    if r30:
        l3, f3, n3, e3 = c(r30)
        lines.append("last 30m: ✅ %d  ➖ %d  ❌ %d  ⚠ %d" % (l3, n3, f3, e3))
    # Break the no-op bucket down BY CAUSE so you can tell "needs refill" from a
    # real bug at a glance. flail/done are the ones worth acting on.
    nb = noop_breakdown(rows)
    if nb:
        bits = ["%s %d" % (lbl, nb[key]) for key, lbl, _ in NOOP_CAUSES if nb.get(key)]
        lines.append("No-op causes: " + " · ".join(bits))
        # point at the single biggest actionable cause
        top_key = max(nb, key=nb.get)
        meaning = next((m for k, _l, m in NOOP_CAUSES if k == top_key), "")
        if meaning and nb[top_key] >= 3:
            lines.append("→ mostly %s: %s" % (dict((k, l) for k, l, _ in NOOP_CAUSES).get(top_key, top_key), meaning))
    # 2026-09-09: the per-tier line that used to live here is now ovn_tier_stats.py's
    # job — it reads outcomes.jsonl (tier is explicit there, not inferred via the 'cx'
    # classification tag) and adds no-op/timeout/token detail this couldn't show.
    # digest_notify.sh calls both scripts; keeping both tier lines would just be two
    # slightly-different numbers next to each other, which is the opposite of clean.
    prod = producing('lang')
    if prod:
        lines.append("Producing: " + " · ".join("%s %d" % (k, v) for k, v in prod))
    spun = spinning('type') or spinning('lang')
    if spun:
        unv = sum(1 for r in rows if r['verif'] == 'unverifiable')
        tail = (" +%d unverifiable" % unv) if unv else ""
        lines.append("Idle (nothing to do): " + ", ".join(k for k, _ in spun[:5]) + tail)
    fails = failing('cx') + failing('lang')
    if fails:
        lines.append("⚠ Weak: " + " · ".join("%s %d%%" % (k, r) for k, r in fails[:4]))
    # 2026-09-09: "Exhausted repos" used to live here (idle_repos(): a same-instant doable-count
    # snapshot). Removed in favor of ovn_planning_stats.py's "Stuck dry" line in the digest, which
    # checks the SAME underlying condition (no doable work) but more precisely - it requires BOTH
    # the planner (no [ready] roadmap feature) AND refill (backlog also empty) to agree within the
    # window, so it only flags repos that genuinely can't self-heal, not one that just looks empty
    # at the exact instant this script runs. Keeping both would show the same repos twice.
    rw = runway()
    if rw:
        lines.append("Runway: " + " · ".join("%s %d %s" % (r, n, d) for r, n, d, b in rw))
    print("\n".join(lines))
else:
    print("Overnight throughput, last %gh — %d cycles" % (hours, total))
    line = "  ✅ %d landed   ➖ %d no-op   ❌ %d failed" % (L, N, F)
    if E:
        line += "   ⚠ %d errored" % E
    print(line)
    if L + F:
        print("  pass-rate (of attempts that changed code): %d%%" % (100 * L // (L + F)))
    print()
    for name, axis in [("COMPLEXITY", "cx"), ("LANGUAGE", "lang"), ("TYPE", "type"), ("VERIFIABILITY", "verif")]:
        print("BY %s:" % name)
        for k, v in sorted(group(axis).items(), key=lambda kv: -c(kv[1])[0]):
            l, f, n, e = c(v)
            rate = ("%d%%" % (100 * l // (l + f))) if (l + f) else "  — "
            print("  %-14s %5s   landed %-3d failed %-2d no-op %-3d%s" % (
                k, rate, l, f, n, ("  err %d" % e) if e else ""))
        print()
