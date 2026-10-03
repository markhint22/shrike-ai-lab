#!/usr/bin/env python3
"""Overnight-queue throughput + pass-rate, sliced by classification axis.

Reads state/task_stats.log rows: <epoch>\t<repo>\t<outcome>\t{lang.type.cx.verif}\t<file>
outcome in {pass, fail, revert, error, noop, skip}.

Leads with THROUGHPUT (landed / no-op / failed / errored) — what a human actually
cares about — then flags only the cells worth attention: what's producing, what's
just spinning (all no-op = exhausted or unverifiable), and any real failures.

Usage: ovn_stats.py [hours=24] [--ntfy] [--since T] [--real] [--gpu-alert]
  --since T    split the window at T (epoch | ISO | 'YYYY-MM-DD[ HH:MM]', UTC) and print the REAL
               pass rate pre vs post (scripts/ovn_real_passrate.py: phantom `landed`-without-commit
               rows excluded, suspected pre-existing-red reverts separated, honest-headline flag)
  --real       print only the REAL pass-rate section and exit
  --gpu-alert  evaluate the 24h GPU busy percentage and write the (6h-deduped) alerts.log line;
               used by ovn_gpu_util_check.sh after each sample
"""
import os, re, sys, time
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ovn_outcome_buckets import bucket, oc_bad_breakdown, oc_benign_breakdown, oc_pass_rate  # canonical GOOD/BAD/BENIGN split

STATE_DIR = os.environ.get("OVN_STATE_DIR") or os.path.expanduser("~/overnight-queue/state")
P = os.path.join(STATE_DIR, "task_stats.log")
# --since takes a value, so pull it out of argv BEFORE the positional-hours parse below.
_argv, _since_raw, _i = [], None, 1
while _i < len(sys.argv):
    _a = sys.argv[_i]
    if _a == '--since' and _i + 1 < len(sys.argv):
        _since_raw = sys.argv[_i + 1]; _i += 2; continue
    if _a.startswith('--since='):
        _since_raw = _a.split('=', 1)[1]
    else:
        _argv.append(_a)
    _i += 1
args = [a for a in _argv if not a.startswith('--')]
ntfy = '--ntfy' in _argv
real_only = '--real' in _argv
gpu_alert_mode = '--gpu-alert' in _argv
noop_headline = '--noop-headline' in sys.argv
hours = float(args[0]) if args else 24.0
cutoff = time.time() - hours * 3600

# --- GPU utilization (2026-10-03): ovn_gpu_util_check.sh appends "<epoch> <util%>" to state/gpu_util.log.
# The diagnosis measured 17 of 23 overnight samples under 5% (xlite VERIFY hangs idling the GPU) and nothing
# reported it. A sample counts as busy at >= GPU_BUSY_MIN percent.
GPU_BUSY_MIN = float(os.environ.get("OVN_GPU_BUSY_MIN", "5"))
GPU_ALERT_BELOW = float(os.environ.get("OVN_GPU_ALERT_BELOW", "40"))
GPU_MIN_SAMPLES = int(os.environ.get("OVN_GPU_MIN_SAMPLES", "12"))
GPU_ALERT_DEDUP_S = 6 * 3600

def gpu_busy(window_h=24.0, now=None):
    """-> (busy_pct or None, n_samples) over the last window_h hours of state/gpu_util.log."""
    now = now if now is not None else time.time()
    n = busy = 0
    try:
        for ln in open(os.path.join(STATE_DIR, "gpu_util.log"), errors="replace"):
            p = ln.split()
            if len(p) < 2:
                continue
            try:
                t, u = float(p[0]), float(p[1])
            except ValueError:
                continue
            if t < now - window_h * 3600:
                continue
            n += 1
            busy += 1 if u >= GPU_BUSY_MIN else 0
    except OSError:
        return None, 0
    return (round(100.0 * busy / n, 1) if n else None), n

def _any_lane_enabled():
    import json
    if os.path.exists(os.path.join(STATE_DIR, "PAUSED")):
        return False   # deliberately paused (e.g. GPU testing): low util is expected
    tf = os.environ.get("OVN_TASKS_FILE") or os.path.join(os.path.dirname(STATE_DIR.rstrip("/")) or ".", "tasks.json")
    try:
        tasks = json.load(open(tf))
    except Exception:
        return False   # cannot tell -> do not alert (infra uncertainty never alarms)
    return any(isinstance(t, dict) and t.get("enabled") is not False for t in tasks)

def gpu_alert(now=None):
    """Write ONE alerts.log line (deduped GPU_ALERT_DEDUP_S) when 24h busy percentage is below
    GPU_ALERT_BELOW while any lane is enabled and there are >= GPU_MIN_SAMPLES samples.
    Returns the line or None."""
    now = now if now is not None else time.time()
    pct, n = gpu_busy(24.0, now)
    if pct is None or n < GPU_MIN_SAMPLES or pct >= GPU_ALERT_BELOW or not _any_lane_enabled():
        return None
    stamp = os.path.join(STATE_DIR, ".gpu_util_alerted")
    try:
        if now - float(open(stamp).read().strip() or "0") < GPU_ALERT_DEDUP_S:
            return None
    except (OSError, ValueError):
        pass
    line = ("[%s] warn | gpu-util | GPU busy only %g%% over the last 24h (%d samples, busy = >=%g%% util) "
            "while a lane is enabled - cycles are spending their time outside model generation"
            % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), pct, n, GPU_BUSY_MIN))
    try:
        with open(os.path.join(STATE_DIR, "alerts.log"), "a") as f:
            f.write(line + "\n")
        with open(stamp, "w") as f:
            f.write(str(now))
    except OSError:
        return None
    return line

def _real_section():
    """REAL pass-rate (lines, result) - fail-safe: any error -> empty, never breaks the digest."""
    try:
        import ovn_real_passrate as rp
        lines_, res_ = rp.build(STATE_DIR, hours, rp.parse_since(_since_raw))
        w_ = res_["window"]
        if w_["good"] + w_["bad"] == 0:
            return [], {"flags": []}      # no outcomes.jsonl data in the window: print nothing
        return lines_, res_
    except Exception:
        return [], {"flags": []}

if gpu_alert_mode:
    print(gpu_alert() or "")
    sys.exit(0)
if real_only:
    print("\n".join(_real_section()[0]) or "no real pass-rate data")
    sys.exit(0)

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
        rows.append({'ts': ts, 'oc': oc, 'lang': lang, 'type': typ, 'cx': cx, 'verif': verif,
                     'repo': repo, 'file': f})

# 2026-09-30: runway() is defined BEFORE the no-rows early exit below. scripts/ovn_fleet_health.sh imports this module and calls runway();
# the old order made `import ovn_stats` sys.exit(0) whenever task_stats.log had no rows in the window, so the fleet-health check reported
# "clean run" exactly when the fleet was stalled - the case it exists to catch.
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
                     and not re.search(r"HUMAN-ONLY|human/|AUTO-SKIP|BLOCKED ITEM|\(retired-", l))
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

if not rows:
    print("no queue activity recorded in the last %gh yet" % hours)
    sys.exit(0)

def c(sub):
    """-> (landed, failed, noop, errored), using the canonical GOOD/BAD/BENIGN
    split (ovn_outcome_buckets.py). 2026-09-28 FIX: 'failed' used to be just
    oc in ('fail','revert'), which silently excluded noop:gate (a revert wearing
    a noop: prefix) and noop:flail (a full attempt that produced zero diff) from
    every failure count downstream of this helper (the headline pass-rate line,
    the per-axis failing()/spinning() breakdowns). Those are now correctly
    'failed' (the canonical BAD bucket), and 'noop' below is only the BENIGN
    scout-verdict no-ops (noop:done/noop:blocked) — a cell that only ever
    flailed/gate-reverted is no longer mislabeled as merely 'idle'. 'skip' (an
    exhausted repo skipped before the model ran) stays deliberately excluded
    entirely — it's idle, not wasted work — and is surfaced separately as an
    'Idle' line."""
    landed = sum(1 for r in sub if bucket(r['oc']) == 'good')
    failed = sum(1 for r in sub if bucket(r['oc']) == 'bad')
    noop = sum(1 for r in sub if r['oc'] in ('noop:done', 'noop:blocked'))
    err = sum(1 for r in sub if r['oc'] == 'error')
    return landed, failed, noop, err


# Human-readable label + short gloss + one-line meaning for each no-op cause, so the digest
# tells you WHICH problem to fix: exhausted (refill/features), or a real bug.
# 2026-09-28: added the short `gloss` field (no bare "flailed"/"gate-rev" jargon — see
# CLAUDE.md-adjacent digest plain-language fix) printed as "<label> <count> (<gloss>)"
# everywhere these are shown (the compact "No-op causes: ..." line included), so it reads as
# plain language, not internal shorthand — while keeping "<label> <count>" adjacent for any
# caller (or test) parsing/matching on that exact substring.
NOOP_CAUSES = [
    ('noop:flail',   'flailed',  'too hard for the model',        'too hard for the 27B — route to Claude or simplify the item'),
    ('noop:done',    'done',     'already satisfied in code',     'already satisfied in code — mis-targeted item, retarget or credit it'),
    ('noop:blocked', 'blocked',  'needs a human decision',        'model wants a human decision — the item is under-specified'),
    ('noop:gate',    'gate-rev', 'safety-check reverted it',      'model changed code but a safety gate reverted it'),
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

# 2026-09-16: "no-op" was masking two very different things under one bucket -
# blocked/done cost ONE scout call and stop there, while flailed/gate-reverted burn a
# full multi-attempt implement pass (and for gate-rev, a full test-suite verification)
# before being discarded. Root-caused live: shrike-notify's revoke_token() item alone
# burned 18 of those expensive cycles in ~7.5h before finally landing, invisible inside
# a single "92 no-op" digest line. Split the reporting so cheap and expensive no-ops
# are never summed into one misleading number again.
CHEAP_NOOP_KEYS = ('noop:blocked', 'noop:done')
BURNED_NOOP_KEYS = ('noop:flail', 'noop:gate')

def noop_cost_split(sub):
    nb = noop_breakdown(sub)
    cheap = sum(nb.get(k, 0) for k in CHEAP_NOOP_KEYS)
    burned = sum(nb.get(k, 0) for k in BURNED_NOOP_KEYS)
    return cheap, burned

def repeat_offenders(sub, threshold=5):
    """(repo, file) pairs whose flail/gate-rev no-ops repeat >= threshold times in the
    window - the exact loop this split exists to surface (e.g. the same item silently
    re-attempted and reverted a dozen-plus times while looking like ordinary no-op
    noise). Sorted worst-first."""
    cnt = {}
    for r in sub:
        if r['oc'] in ('noop:flail', 'noop:gate'):
            key = (r.get('repo', '?'), r.get('file', '?'))
            cnt[key] = cnt.get(key, 0) + 1
    out = [(k, v) for k, v in cnt.items() if v >= threshold]
    out.sort(key=lambda x: -x[1])
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

# 2026-09-18: the digest's headline no-op line used to just print a flat count with
# no breakdown ("N no change (item already done, or nothing to do)") - useless for
# telling "the fleet correctly declined 4 already-done items" (fine) apart from "the
# fleet burned 8 real implement+verify attempts and got nothing" (worth investigating).
# This mode reuses the SAME cheap/burned split + per-cause labels already computed
# below for the full report, just condensed to one digest-ready line.
if noop_headline:
    nb = noop_breakdown(rows)
    cheap, burned = noop_cost_split(rows)
    total_noop = cheap + burned
    if total_noop == 0:
        print("")
        sys.exit(0)
    ok_bits = ["%d %s (%s)" % (nb[k], l, g) for k, l, g, _ in NOOP_CAUSES if k in CHEAP_NOOP_KEYS and nb.get(k)]
    bad_bits = ["%d %s (%s)" % (nb[k], l, g) for k, l, g, _ in NOOP_CAUSES if k in BURNED_NOOP_KEYS and nb.get(k)]
    line = "%d no-op" % total_noop
    if ok_bits:
        line += " -- %d cheap, no real attempt made (%s)" % (cheap, ", ".join(ok_bits))
    if bad_bits:
        line += ("; " if ok_bits else " -- ") + "%d worth investigating, a real attempt was burned (%s)" % (burned, ", ".join(bad_bits))
    print(line)
    sys.exit(0)

# 2026-09-28: wasted-attempt-by-subtype + benign-excluded-by-subtype companion
# metrics, computed once and used by both report modes below, so the headline
# pass-rate number is never shown without "why" right next to it.
_bad_bd = oc_bad_breakdown(rows)
_revert_n = _bad_bd.get('revert', 0)
_gate_n = _bad_bd.get('noop:gate', 0)
_flail_n = _bad_bd.get('noop:flail', 0) + _bad_bd.get('noop', 0)  # legacy bare noop folds into flail
_benign_bd = oc_benign_breakdown(rows)
_skip_n = sum(1 for r in rows if r['oc'] == 'skip')
_benign_total = sum(_benign_bd.values())   # 2026-09-30: the breakdown already includes skip; adding _skip_n again double-counted every skip row

if ntfy:
    lines = ["Overnight · %gh · %d cycles" % (hours, total)]
    _cheap_n, _burned_n = noop_cost_split(rows)
    # NOTE: N here is now the BENIGN no-op count only (noop:done/noop:blocked) -
    # noop:gate/noop:flail moved into F (the canonical BAD bucket) as of the
    # 2026-09-28 pass-rate fix, so "no-op" and "failed" no longer double-count the
    # same events the way they briefly would have if this label had stayed generic.
    head = ("✅ %d landed   ➖ %d benign no-op (skipped, not counted against the rate)   "
            "❌ %d wasted (%d reverted, %d gate-rev [safety-check reverted it], %d flailed [too hard for the model])") % (
        L, N, F, _revert_n, _gate_n, _flail_n)
    if E:
        # recency: how long since the last error? a stale spike shouldn't look ongoing.
        last_err_ts = max((r.get('ts', 0) for r in rows if r['oc'] == 'error'), default=0)
        mins = int((time.time() - last_err_ts) / 60) if last_err_ts else 0
        if mins >= 25:
            head += "   ⚠ %d errored (RESOLVED — last %dm ago)" % (E, mins)
        else:
            head += "   ⚠ %d errored (ONGOING — last %dm ago)" % (E, mins)
    lines.append(head)
    if L + F:
        lines.append("pass-rate: %s%%  (%d good / %d good+bad)" % (oc_pass_rate(rows), L, L + F))
    # 2026-10-03: only when the headline is NOT honest (or --since asked for the split) - quiet otherwise.
    _rl, _rr = _real_section()
    if _since_raw:
        lines.extend(_rl)
    elif _rr.get("flags"):
        lines.extend(x.strip() for x in _rl[1:2] + [l for l in _rl if "HEADLINE NOT HONEST" in l])
    _gp, _gn = gpu_busy(24.0)
    if _gp is not None and _gn >= GPU_MIN_SAMPLES:
        lines.append("GPU busy %g%% over 24h (%d samples)%s" % (
            _gp, _gn, "  - LOW, cycles idle outside generation" if _gp < GPU_ALERT_BELOW else ""))
    if _benign_total:
        lines.append("ℹ️ %d benign, not counted (%d already-done, %d blocked, %d skip, %d error)" % (
            _benign_total, _benign_bd.get('noop:done', 0), _benign_bd.get('noop:blocked', 0), _skip_n, _benign_bd.get('error', 0)))
    # always show the most-recent 30 min so current health is unambiguous
    r30 = [r for r in rows if r.get('ts', 0) >= time.time() - 1800]
    if r30:
        l3, f3, n3, e3 = c(r30)
        lines.append("last 30m: ✅ %d  ➖ %d  ❌ %d  ⚠ %d" % (l3, n3, f3, e3))
    # Break the no-op bucket down BY CAUSE so you can tell "needs refill" from a
    # real bug at a glance. flail/done are the ones worth acting on.
    nb = noop_breakdown(rows)
    if nb:
        # "<label> <count> (<gloss>)" — keeps "<label> <count>" adjacent (e.g. "flailed 1")
        # for any caller/test matching on that exact substring, while still glossing the
        # jargon term inline rather than leaving it bare.
        bits = ["%s %d (%s)" % (lbl, nb[key], gloss) for key, lbl, gloss, _ in NOOP_CAUSES if nb.get(key)]
        lines.append("No-op causes: " + " · ".join(bits))
        # point at the single biggest actionable cause. Uses the bare cause key here (not
        # the glossed label above) since `meaning` already spells the same thing out in
        # full — showing both would just repeat the gloss twice in two adjacent lines.
        top_key = max(nb, key=nb.get)
        meaning = next((m for k, _l, _g, m in NOOP_CAUSES if k == top_key), "")
        if meaning and nb[top_key] >= 3:
            lines.append("→ mostly %s: %s" % (top_key.split(":", 1)[-1], meaning))
    # Repeat offenders (2026-09-16): the same (repo, item) burning flail/gate-rev cycles
    # over and over - this is the real signal "no-op" was hiding. A single stuck item
    # can rack up a dozen+ expensive cycles while looking like ordinary digest noise
    # (shrike-notify's revoke_token(): 18 in ~7.5h before finally landing).
    ro = repeat_offenders(rows)
    if ro:
        lines.append("🔁 Stuck (same item retried and thrown away repeatedly): " +
                      " · ".join("%s/%s x%d" % (repo, fname, n) for (repo, fname), n in ro[:5]))
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
        lines.append("⚠ Weak spots (below-average pass-rate, by category): " +
                      " · ".join("%s %d%%" % (k, r) for k, r in fails[:4]))
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
    # 2026-09-28: N is now the BENIGN no-op count only (noop:done/noop:blocked) -
    # noop:gate/noop:flail count as 'failed' (the canonical BAD bucket) instead,
    # broken out below the pass-rate line so "why is it bad" is never hidden.
    line = "  ✅ %d landed   ➖ %d benign no-op (excluded)   ❌ %d failed" % (L, N, F)
    if E:
        line += "   ⚠ %d errored" % E
    print(line)
    if L + F:
        print("  pass-rate (of GOOD-or-BAD attempts): %s%%" % oc_pass_rate(rows))
        print("  wasted attempts: %d (%d revert, %d gate-reverted, %d flailed)" % (
            F, _revert_n, _gate_n, _flail_n))
    _rl, _rr = _real_section()
    if _rl:
        print("\n".join(_rl))
    _gp, _gn = gpu_busy(24.0)
    if _gp is not None:
        print("  GPU busy %g%% over 24h (%d samples, busy = >=%g%% util)" % (_gp, _gn, GPU_BUSY_MIN))
    if _benign_total:
        print("  excluded, not counted (benign): %d (%d already-done, %d blocked, %d skip, %d error)" % (
            _benign_total, _benign_bd.get('noop:done', 0), _benign_bd.get('noop:blocked', 0), _skip_n, _benign_bd.get('error', 0)))
    ro = repeat_offenders(rows)
    if ro:
        print("  🔁 Stuck (repeated flail/gate-rev): " +
              " · ".join("%s/%s x%d" % (repo, fname, n) for (repo, fname), n in ro[:5]))
    print()
    for name, axis in [("COMPLEXITY", "cx"), ("LANGUAGE", "lang"), ("TYPE", "type"), ("VERIFIABILITY", "verif")]:
        print("BY %s:" % name)
        for k, v in sorted(group(axis).items(), key=lambda kv: -c(kv[1])[0]):
            l, f, n, e = c(v)
            rate = ("%d%%" % (100 * l // (l + f))) if (l + f) else "  — "
            print("  %-14s %5s   landed %-3d failed %-2d no-op %-3d%s" % (
                k, rate, l, f, n, ("  err %d" % e) if e else ""))
        print()
