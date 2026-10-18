#!/usr/bin/env python3
"""scripts/ovn_needs_research_promote.py - bounded, code-grounded promotion of roadmap [needs-research] features to [ready] (2026-10-18).

Why: a repo whose roadmap has no [ready] feature starves the planner ("backlog low (0) but no [ready] roadmap feature (needs Claude research?)") until a Mac-side Claude pass
promotes something. Claude passes are capped (8/day), time out (rc=124) and are allow-listed per repo, so five repos starved for 16-22 h. Some [needs-research] features do NOT
need web/market research: the feature text names real files of this repo and says so (`research: repo|code|none` or no research field). Those can be promoted mechanically; the
planner's own gates (ground guard, dedupe, red-before spec check, stage-runner) still judge every item that comes out of them.

A feature is promotable only when ALL hold (anything doubtful is left for Claude):
  - open checkbox, status exactly [needs-research]
  - none of the HELD markers (HUMAN-ONLY, AUTO-SKIP, BLOCKED, decision-needed, (retired-, needs-human, requires an API key/account/credential/legal/pricing/store decision)
  - metadata `research:` absent or one of none|repo|code (web|market|legal|competitor = a real research need)
  - not `size: L`; the line is at most MAX_LINE chars
  - it cites >= 1 backticked path of the checkout that EXISTS and is not a test file (grounded), and every other cited path exists or is a new test file
Bounded: at most OVN_NRP_MAX_PER_PASS (default 1) per pass and OVN_NRP_QUOTA (default 2) per repo per calendar day (state/nrp_count_<repo>_<date>).

OVN_NEEDS_RESEARCH_PROMOTE=off|shadow|enforce   (default shadow: print + log what WOULD be promoted, change nothing; off: do nothing; enforce: rewrite the status to [ready]
and append ` -- AUTO-PROMOTED <date> (ovn_needs_research_promote.py: paths verified in checkout)`).

usage: ovn_needs_research_promote.py <repo>      env: OVN_DIR (default ~/overnight-queue)
stdout (last line, machine-readable): PROMOTED <n> | SHADOW <n> | NONE <reason> | OFF
exit: 0 always (best-effort; the planner must never fail on it)
"""
import datetime
import fcntl
import os
import re
import sys

OVN_DIR = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
MODES = ("off", "shadow", "enforce")
MAX_LINE = 1500
PATHISH = re.compile(r"`([\w./-]+\.(?:py|ts|tsx|js|vue|gd|kt|swift|sh|sql|json|yml|yaml|toml|html))(?::\d+(?:-\d+)?)?`")
LINE_RE = re.compile(r"^- \[ \] (\[P[1-4]\]) \[needs-research\] (.*)$")
HELD_RE = re.compile(r"HUMAN-ONLY|AUTO-SKIP|BLOCKED|decision-needed|\(retired-|needs-human|"
                     r"requires? (an? )?(api[ -]?key|account|credential|secret|legal|pricing|store|app store|human|owner|mark)", re.I)
RESEARCH_RE = re.compile(r"research:\s*([a-z-]+)")
OK_RESEARCH = ("none", "repo", "code")


def mode():
    m = os.environ.get("OVN_NEEDS_RESEARCH_PROMOTE", "shadow").strip().lower()
    return m if m in MODES else "shadow"  # an unknown value is the SAFE setting, never enforce


def is_test_path(r):
    return bool(re.search(r"(^|/)(tests?|__tests__|spec)(/|$)|(^|/)test_[^/]+$|\.(test|spec)\.", r))


def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def judge(rest, root):
    """(promotable, reason) for the text after `[needs-research] `."""
    if len(rest) > MAX_LINE:
        return False, "line over %d chars" % MAX_LINE
    if HELD_RE.search(rest):
        return False, "held marker"
    m = RESEARCH_RE.search(rest)
    if m and m.group(1) not in OK_RESEARCH:
        return False, "research:%s needs real research" % m.group(1)
    if re.search(r"size:\s*L\b", rest):
        return False, "size L"
    paths = PATHISH.findall(rest)
    if not paths:
        return False, "cites no path"
    real = [p for p in paths if os.path.exists(os.path.join(root, p)) and not is_test_path(p)]
    if not real:
        return False, "cites no existing non-test path"
    for p in paths:
        if not os.path.exists(os.path.join(root, p)) and not is_test_path(p):
            return False, "cites a path that does not exist: %s" % p
    return True, "grounded in %s" % real[0]


def main(argv):
    if len(argv) < 2 or argv[1].startswith("-"):
        print("usage: ovn_needs_research_promote.py <repo>")
        return 0
    repo, md = argv[1], mode()
    if md == "off":
        print("OFF")
        return 0
    root = os.path.join(OVN_DIR, "repos", repo)
    rm = os.path.join(OVN_DIR, "roadmap", repo + ".md")
    state = os.path.join(OVN_DIR, "state")
    if not os.path.isdir(root) or not os.path.isfile(rm):
        print("NONE no checkout or roadmap")
        return 0
    quota = int(os.environ.get("OVN_NRP_QUOTA", "2"))
    per_pass = int(os.environ.get("OVN_NRP_MAX_PER_PASS", "1"))
    cnt = os.path.join(state, "nrp_count_%s_%s" % (repo, datetime.date.today().isoformat()))
    used = int(read(cnt).strip() or 0) if os.path.exists(cnt) else 0
    if md == "enforce" and used >= quota:
        print("NONE daily quota %d reached" % quota)
        return 0
    os.makedirs(state, exist_ok=True)
    lk = open(os.path.join(state, "nrp.lock"), "w")
    try:
        fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("NONE another promotion pass holds the lock")
        return 0
    lines = read(rm).split("\n")
    take = min(per_pass, max(quota - used, 0) if md == "enforce" else per_pass)
    hits, skipped = [], {}
    for i, l in enumerate(lines):
        m = LINE_RE.match(l)
        if not m:
            continue
        ok, why = judge(m.group(2), root)
        if ok and len(hits) < take:
            hits.append((i, m.group(1), why))
        elif not ok:
            skipped[why.split(":")[0]] = skipped.get(why.split(":")[0], 0) + 1
    if not hits:
        print("%s: no promotable [needs-research] feature (skipped: %s)" % (repo, skipped or "none found"))
        print("NONE %s" % ("skipped " + str(skipped) if skipped else "no [needs-research] features"))
        return 0
    for i, pr, why in hits:
        print("%s: %s promote line %d (%s): %s" % (repo, "WOULD" if md == "shadow" else "WILL", i + 1, why, lines[i][:110]))
    if md == "shadow":
        print("SHADOW %d" % len(hits))
        return 0
    stamp = " -- AUTO-PROMOTED %s (ovn_needs_research_promote.py: paths verified in checkout)" % datetime.date.today().isoformat()
    for i, pr, _ in hits:
        lines[i] = lines[i].replace("%s [needs-research]" % pr, "%s [ready]" % pr, 1) + stamp
    tmp = rm + ".nrp.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.replace(tmp, rm)
    with open(cnt, "w") as f:
        f.write(str(used + len(hits)))
    try:
        with open(os.path.join(state, "alerts.log"), "a") as f:
            f.write("[%s] info | needs-research-promote:%s | auto-promoted %d [needs-research] feature(s) to [ready] (code-grounded)\n" % (
                datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), repo, len(hits)))
    except OSError:
        pass
    print("PROMOTED %d" % len(hits))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as e:  # never fail the planner
        print("NONE error %s: %s" % (type(e).__name__, e))
        sys.exit(0)
