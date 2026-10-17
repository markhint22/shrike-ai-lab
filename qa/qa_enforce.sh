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
# second keys inside gate_antigaming.py (2026-10-10): FAIL severities only armed when the shared `antigaming` gate AND the sub-key are enforce
for sub, what in (("antigaming_frozen", "D_FROZEN_EDIT FAIL"), ("antigaming_testfiles", "A_TESTFILE_EMPTIED + E_TEST_NOT_COLLECTED(new file) FAIL"),
                  ("antigaming_emptied", "A_TESTFILE_EMPTIED FAIL (this rule alone)"), ("antigaming_newpath", "N_NEWPATH_LOOKALIKE FAIL (off = rule skipped)")):
    sm, ssrc = qc.mode_source(sub)
    sr = last.get(sub)
    print("%-20s %-8s source=%-7s second key of antigaming: %s when enforce (else FLAG); last change: %s" % (sub, sm, ssrc, what, ("%s -> %s by %s at %s" % (sr.get("from"), sr.get("to"), sr.get("who"), sr.get("ts"))) if sr else "never (default)"))
# promote-time gates (qa/promote_gate.py): staging_check ENFORCES by default since 2026-10-03 (A3) - show the effective mode + where it comes from
try:
    import promote_gate as pg
    pm = pg.gate_mode()
    penv = os.environ.get("OVN_PROMOTE_STAGING_GATE") in qc.MODES
    psrc = "env(OVN_PROMOTE_STAGING_GATE)" if penv else qc.mode_source(pg.GATE)[1]
    print("%-14s %-8s source=%-7s promote-time (promote_to_prod.sh): %s" % (pg.GATE, pm, psrc if psrc != "default" else "default(enforce)", "blocks a repo with a staging backend on FAIL / stale evidence" if pm == "enforce" else "log only"))
except Exception as ex:
    print("staging_check  ?        promote_gate unavailable: %s" % type(ex).__name__)
# promote-time live-staging e2e evidence (QA-N1, 2026-10-09): SHADOW by default; enforce blocks only a commit-matched, fresh FAIL
try:
    em, esrc = qc.mode_source("staging_e2e")
    elast = last.get("staging_e2e")
    print("%-14s %-8s source=%-7s promote-time (promote_to_prod.sh): %s; last change: %s" % ("staging_e2e", em, esrc, "blocks ONLY a FAIL of the commit under promote (< 12 h old)" if em == "enforce" else "evidence line only, never blocks", ("%s -> %s by %s at %s" % (elast.get("from"), elast.get("to"), elast.get("who"), elast.get("ts"))) if elast else "never (default)"))
except Exception as ex:
    print("staging_e2e    ?        unavailable: %s" % type(ex).__name__)
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
    # staging_e2e is promote-time too (promote_gate.py reads the live-staging e2e evidence)
    # soak (2026-10-17, Phase 4) is promote-time too (promote_gate.py reads state/qa_shadow/soak.jsonl); enforce additionally needs the repo in the soak allow-list
    # antigaming_frozen / antigaming_testfiles (2026-10-10) are second keys INSIDE gate_antigaming.py (severity of D_FROZEN_EDIT; A_TESTFILE_EMPTIED + E_TEST_NOT_COLLECTED for new files)
    # antigaming_emptied / antigaming_newpath (2026-10-13, package qa): A_TESTFILE_EMPTIED alone; N_NEWPATH_LOOKALIKE (new file in a directory that doubles / typos an existing one)
    if [ "$m" = enforce ] && [ ! -f "$GD/gate_$g.py" ] && ! { { [ "$g" = staging_check ] || [ "$g" = staging_e2e ] || [ "$g" = soak ]; } && [ -f "$HERE/promote_gate.py" ]; } \
       && ! { case "$g" in antigaming_frozen|antigaming_testfiles|antigaming_emptied|antigaming_newpath) [ -f "$GD/gate_antigaming.py" ] ;; *) false ;; esac; }; then echo "qa_enforce: no such gate: $GD/gate_$g.py" >&2; exit 2; fi
    QA_WHO="$(who)" QA_G="$g" QA_M="$m" HERE_PY="$HERE" "$PY" - <<'PY' || exit 1
import os, sys
sys.path.insert(0, os.environ["HERE_PY"])
import qa_common as qc
prev = qc.set_gate_mode(os.environ["QA_G"], os.environ["QA_M"], os.environ["QA_WHO"])
print("%s: %s -> %s (by %s)" % (os.environ["QA_G"], prev or "default(shadow)", os.environ["QA_M"], os.environ["QA_WHO"]))
PY
    if [ "$g" = staging_e2e ]; then
      [ "$m" = enforce ] && echo "ENFORCING: a FAIL of the live-staging e2e for the commit being promoted (evidence < 12 h old, commit-matched) now holds that repo at promote_to_prod.sh; UNVERIFIED / stale / non-matching evidence never blocks. Rollback: $0 $g shadow"
      exit 0
    fi
    if [ "$g" = soak ]; then
      [ "$m" = enforce ] && echo "ENFORCING the soak gate mode: it only HOLDS a promote for repos in the explicit allow-list (OVN_QA_SOAK_ENFORCE_REPOS=a,b or state/qa_soak_enforce_repos, default EMPTY = still only logs 'soak would HOLD'); UNVERIFIED never holds. Rollback: $0 $g shadow"
      exit 0
    fi
    # 2026-10-10: was `[ "$m" = enforce ] && echo ...` as the LAST command, so a successful flip to shadow/off exited 1
    if [ "$m" = enforce ]; then
      case "$g" in
        antigaming_frozen|antigaming_testfiles|antigaming_emptied|antigaming_newpath) echo "ENFORCING the second key '$g': the FAIL severities it arms only block a merge prefix while the shared 'antigaming' gate is ALSO enforce. Rollback: $0 $g shadow" ;;
        *) echo "ENFORCING: a FAIL verdict from '$g' now blocks the offending commit(s) at the pre-push step of branch_hygiene.sh. Rollback: $0 $g shadow" ;;
      esac
    fi
    exit 0 ;;
esac
