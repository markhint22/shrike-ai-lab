#!/usr/bin/env bash
# qa_enforce.sh - one-command flip + rollback for QA gate modes (written 2026-10-02; see docs/QA_GATES_SPEC.md "Enforcement").
#
#   qa_enforce.sh <gate> <shadow|enforce|off>   persist the mode in state/qa_gate_modes.json (atomic) and record who/when
#   qa_enforce.sh status                        every installed gate (+ the promote-time staging_check): effective mode, where it comes from, last change (who/when), blocked repos
#   qa_enforce.sh unblock <repo> [branch]       drop the block record(s) in state/qa_blocked/ (keyed repo+branch; no branch = every branch of <repo>) (the next hygiene pass re-evaluates and re-alerts if still bad)
#
# ROLLBACK = the same command:  qa_enforce.sh <gate> shadow   (takes effect on the next hygiene pass; nothing to restart).
# Global kill switch without touching any file:  OVN_QA_ENFORCE=off  (in the environment of branch_hygiene.sh).
# A per-gate env var OVN_QA_<GATE> still outranks the file (status shows source=env so an override is never a surprise).
# Nothing here takes a lock, restarts a service or touches a repo. Every gate defaults to shadow; enforce is only ever set by this command.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
PY="$(command -v python3.12 || command -v python3)"
[ -n "$PY" ] || { echo "qa_enforce: no python3" >&2; exit 2; }
GD="${QA_GATES_DIR:-$HERE}"
usage(){ sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
who(){ echo "${QA_ENFORCE_WHO:-${SUDO_USER:-${USER:-$(id -un 2>/dev/null)}}@$(hostname -s 2>/dev/null)}"; }
case "${1:-}" in
  ""|-h|--help) usage ;;
  status)
    QA_GD="$GD" HERE_PY="$HERE" "$PY" - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["HERE_PY"])
import qa_common as qc
gd = os.environ["QA_GD"]
gates = sorted(f[5:-3] for f in os.listdir(gd) if f.startswith("gate_") and f.endswith(".py")) if os.path.isdir(gd) else []
last = {}
try:
    for l in open(os.path.join(qc.state_dir(), qc.GATE_MODES_HISTORY)):
        try:
            r = json.loads(l); last[r["gate"]] = r
        except (ValueError, KeyError):
            pass
except OSError:
    pass
kill = os.environ.get("OVN_QA_ENFORCE", "on") == "off"
print("global enforcement kill switch (OVN_QA_ENFORCE=off): %s" % ("ON - nothing enforces" if kill else "off"))
for g in gates:
    m, src = qc.mode_source(g)
    r = last.get(g)
    print("%-14s %-8s source=%-7s last change: %s" % (g, m, src, ("%s -> %s by %s at %s" % (r.get("from"), r.get("to"), r.get("who"), r.get("ts"))) if r else "never (default)"))
# promote-time gates (qa/promote_gate.py): staging_check ENFORCES by default since 2026-10-03 (A3) - show the effective mode + where it comes from
try:
    import promote_gate as pg
    pm = pg.gate_mode()
    penv = os.environ.get("OVN_PROMOTE_STAGING_GATE") in qc.MODES
    psrc = "env(OVN_PROMOTE_STAGING_GATE)" if penv else qc.mode_source(pg.GATE)[1]
    print("%-14s %-8s source=%-7s promote-time (promote_to_prod.sh): %s" % (pg.GATE, pm, psrc if psrc != "default" else "default(enforce)", "blocks a repo with a staging backend on FAIL / stale evidence" if pm == "enforce" else "log only"))
except Exception as ex:
    print("staging_check  ?        promote_gate unavailable: %s" % type(ex).__name__)
bd = os.path.join(qc.state_dir(), "qa_blocked")
try:
    for f in sorted(os.listdir(bd)):
        if f.endswith(".json"):
            try:
                b = json.load(open(os.path.join(bd, f)))
                print("BLOCKED %s%s: gate=%s commit=%s since %s - %s" % (b.get("repo"), (" [" + b["branch"] + "]") if b.get("branch") else "", b.get("gate"), str(b.get("commit"))[:12], b.get("since"), b.get("finding", "")[:100]))
            except ValueError:
                pass
except OSError:
    pass
PY
    ;;
  unblock)
    r="${2:-}"; b="${3:-}"; case "$r" in ""|*/*|.*) echo "usage: qa_enforce.sh unblock <repo> [branch]" >&2; exit 2;; esac
    # 2026-10-02: records are keyed repo__branch (see qa_enforce_run.py blocked_key); no branch given = every branch of the repo (and a legacy repo-only file)
    bd="${QA_STATE_DIR:-$OVN_DIR/state}/qa_blocked"
    if [ -n "$b" ]; then rm -f "$bd/${r}__${b//[^A-Za-z0-9._-]/_}.json"; else rm -f "$bd/$r.json" "$bd/${r}__"*.json; fi
    echo "unblocked $r${b:+ ($b)} (next hygiene pass re-evaluates it)" ;;
  *)
    g="${1:-}"; m="${2:-}"
    case "$m" in shadow|enforce|off) ;; *) usage ;; esac
    case "$g" in ""|*[!a-z0-9_-]*) echo "qa_enforce: bad gate name '$g'" >&2; exit 2;; esac
    # refuse to enforce a gate that is not installed (a typo must not look like a successful flip); shadow/off are always allowed (rollback)
    # staging_check is a PROMOTE-time gate (qa/promote_gate.py), not a gate_*.py hygiene gate
    if [ "$m" = enforce ] && [ ! -f "$GD/gate_$g.py" ] && ! { [ "$g" = staging_check ] && [ -f "$HERE/promote_gate.py" ]; }; then echo "qa_enforce: no such gate: $GD/gate_$g.py" >&2; exit 2; fi
    QA_WHO="$(who)" QA_G="$g" QA_M="$m" HERE_PY="$HERE" "$PY" - <<'PY' || exit 1
import os, sys
sys.path.insert(0, os.environ["HERE_PY"])
import qa_common as qc
prev = qc.set_gate_mode(os.environ["QA_G"], os.environ["QA_M"], os.environ["QA_WHO"])
print("%s: %s -> %s (by %s)" % (os.environ["QA_G"], prev or "default(shadow)", os.environ["QA_M"], os.environ["QA_WHO"]))
PY
    [ "$m" = enforce ] && echo "ENFORCING: a FAIL verdict from '$g' now blocks the offending commit(s) at the pre-push step of branch_hygiene.sh. Rollback: $0 $g shadow" ;;
esac
