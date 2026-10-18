#!/usr/bin/env bash
# 2026-10-13 (night review platform P6 / P7): ops/fleet_review/run_review.sh computes + prepends the review window (UTC and CDT) to the prompt, and guard.py keeps an audit trail
# (logs/guard.jsonl, one JSON line per decision) whose per-run denial count run_review.sh prints into runs.log. Everything runs against a temp HOME with a stub `claude`.
# Mutation controls at the end: break each fix in a scratch copy and show the matching assertions fail.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
OPS="$HERE/../../ops/fleet_review"
[ -f "$OPS/run_review.sh" ] || { echo "  SKIP: ops/fleet_review not present"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
b(){ if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has(){ grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
hasnt(){ grep -qF -- "$2" <<<"$1" && echo 0 || echo 1; }
epoch(){ python3 -c 'import calendar,sys,time; print(calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")))' "$1"; }

mkhome(){ # mkhome <dir> <ops-dir>: a fake HOME with ~/fleet_review installed from <ops-dir> and a stub claude
  local h="$1" src="$2"; rm -rf "${h:?}"; mkdir -p "$h/fleet_review/logs" "$h/.local/bin" "$h/repo"
  cp "$src/run_review.sh" "$src/guard.py" "$src/prompt.md" "$src/settings.json" "$h/fleet_review/"
  cat > "$h/.local/bin/claude" <<'STUB'
#!/bin/bash
# stub claude: save the prompt, then append guard decisions the way guard.py would (2 deny, 1 error, 3 allow) so run_review.sh has something to count
printf '%s' "$2" > "$HOME/prompt.seen"
g="$HOME/fleet_review/logs/guard.jsonl"
for d in allow deny allow deny error allow; do printf '{"ts":"2026-10-13T00:50:00Z","tool":"Bash","decision":"%s","reason":"r","cmd":"c"}\n' "$d" >> "$g"; done
echo "review done"
STUB
  chmod +x "$h/.local/bin/claude"
}
dry(){ HOME="$1" FLEET_REVIEW_DRYRUN=1 FLEET_REVIEW_NOW="$2" ${3:+FLEET_REVIEW_WINDOW_H=$3} bash "$1/fleet_review/run_review.sh"; }

echo "== P6: review window in the prompt =="
mkhome "$T/h1" "$OPS"
N="$(epoch 2026-10-13T00:43:00Z)"
OUT="$(dry "$T/h1" "$N")"
ok "the 19:43 CDT run (00:43Z): WINDOW_START_UTC / END_UTC are the 12h before launch (the 10-12 evening run once used 07:43Z)" "$([ "$(has "$OUT" 'WINDOW_START_UTC=2026-10-12T12:43:00Z')" = 1 ] && [ "$(has "$OUT" 'WINDOW_END_UTC=2026-10-13T00:43:00Z')" = 1 ] && echo 1 || echo 0)"
ok "the CDT equivalents are given too (07:43 and 19:43 on 10-12)" "$([ "$(has "$OUT" 'WINDOW_START_CDT=2026-10-12 07:43:00 CDT')" = 1 ] && [ "$(has "$OUT" 'WINDOW_END_CDT=2026-10-12 19:43:00 CDT')" = 1 ] && echo 1 || echo 0)"
ok "WINDOW_HOURS is stated" "$(has "$OUT" 'WINDOW_HOURS=12')"
ok "the header tells the review to filter by the window over the whole file and never to tail" "$([ "$(has "$OUT" 'Filter by the window over the WHOLE file')" = 1 ] && [ "$(has "$OUT" "Never use 'tail -N'")" = 1 ] && echo 1 || echo 0)"
ok "the zones are spelled out (outcomes.jsonl UTC, logs dirs CDT)" "$([ "$(has "$OUT" '"ts" values are UTC')" = 1 ] && [ "$(has "$OUT" 'are CDT')" = 1 ] && echo 1 || echo 0)"
ok "the window header comes BEFORE the original prompt text" "$([ "$(printf '%s\n' "$OUT" | grep -n 'WINDOW_START_UTC=' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$OUT" | grep -n 'HEADLESS recurring fleet failure review' | head -1 | cut -d: -f1)" ] && echo 1 || echo 0)"
ok "the original prompt is still there in full" "$([ "$(printf '%s\n' "$OUT" | grep -c 'HARD GUARDRAILS')" = 1 ] && echo 1 || echo 0)"
OUT7="$(HOME="$T/h1" FLEET_REVIEW_DRYRUN=1 FLEET_REVIEW_NOW="$(epoch 2026-10-12T12:43:00Z)" bash "$T/h1/fleet_review/run_review.sh")"
ok "the 07:43 CDT run (12:43Z) gets 00:43Z..12:43Z" "$([ "$(has "$OUT7" 'WINDOW_START_UTC=2026-10-12T00:43:00Z')" = 1 ] && [ "$(has "$OUT7" 'WINDOW_END_CDT=2026-10-12 07:43:00 CDT')" = 1 ] && echo 1 || echo 0)"
OUTW="$(HOME="$T/h1" FLEET_REVIEW_DRYRUN=1 FLEET_REVIEW_NOW="$(epoch 2026-12-01T00:43:00Z)" bash "$T/h1/fleet_review/run_review.sh")"
ok "in winter the Chicago clock reads CST (the variable name stays *_CDT, the value carries the real zone)" "$([ "$(has "$OUTW" 'WINDOW_END_CDT=2026-11-30 18:43:00 CST')" = 1 ] && echo 1 || echo 0)"
OUT6="$(HOME="$T/h1" FLEET_REVIEW_DRYRUN=1 FLEET_REVIEW_NOW="$N" FLEET_REVIEW_WINDOW_H=24 bash "$T/h1/fleet_review/run_review.sh")"
ok "FLEET_REVIEW_WINDOW_H=24 widens it; garbage falls back to 12" "$([ "$(has "$OUT6" 'WINDOW_START_UTC=2026-10-12T00:43:00Z')" = 1 ] && [ "$(HOME="$T/h1" FLEET_REVIEW_DRYRUN=1 FLEET_REVIEW_NOW="$N" FLEET_REVIEW_WINDOW_H=abc bash "$T/h1/fleet_review/run_review.sh" | grep -c 'WINDOW_HOURS=12')" = 1 ] && echo 1 || echo 0)"
ok "dry run takes no lock and starts nothing" "$([ ! -d "$T/h1/fleet_review/lock" ] && [ ! -s "$T/h1/fleet_review/logs/runs.log" ] && echo 1 || echo 0)"
ok "prompt.md points the review at the window instead of 'last 12-24h'" "$([ "$(grep -c 'REVIEW WINDOW stated at the very top' "$OPS/prompt.md")" = 1 ] && [ "$(grep -c 'in the last 12-24h from state/outcomes.jsonl' "$OPS/prompt.md")" = 0 ] && echo 1 || echo 0)"

echo "== P7: guard audit trail =="
GOUT="$(python3 "$OPS/guard.py" --selftest 2>&1)"; GRC=$?
ok "guard.py --selftest passes (allow/deny table + audit-log checks)" "$([ "$GRC" = 0 ] && [ "$(has "$GOUT" 'selftest: ')" = 1 ] && [ "$(has "$GOUT" '0 mismatches')" = 1 ] && [ "$(has "$GOUT" 'selftest(log): ')" = 1 ] && [ "$(hasnt "$GOUT" 'LOG MISMATCH')" = 1 ] && echo 1 || echo 0)"
GL="$T/guard.jsonl"; rm -f "$GL"
DENY_OUT="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git stash"},"cwd":"/tmp/wt-x"}' | FLEET_GUARD_LOG="$GL" python3 "$OPS/guard.py")"
ALLOW_OUT="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git log --oneline -3"},"cwd":"/tmp/wt-x"}' | FLEET_GUARD_LOG="$GL" python3 "$OPS/guard.py")"
ok "CLI: a deny still prints the deny decision, an allow prints nothing" "$([ "$(has "$DENY_OUT" '"permissionDecision": "deny"')" = 1 ] && [ -z "$ALLOW_OUT" ] && echo 1 || echo 0)"
ok "CLI: two lines in the audit log, valid JSON, fields ts/tool/decision/reason/cmd" "$(python3 - "$GL" <<'PY' && echo 1 || echo 0
import json, sys
r = [json.loads(l) for l in open(sys.argv[1])]
assert len(r) == 2 and [x["decision"] for x in r] == ["deny", "allow"], r
assert all(set(x) == {"ts", "tool", "decision", "reason", "cmd"} for x in r)
assert r[0]["cmd"] == "git stash" and "stash is forbidden" in r[0]["reason"] and r[1]["cmd"].startswith("git log")
PY
)"
printf '%s' '{ broken' | FLEET_GUARD_LOG="$GL" python3 "$OPS/guard.py" >/dev/null 2>&1; GRC2=$?
ok "CLI: malformed input fails OPEN (rc 0, no output) and is recorded as decision=error" "$([ "$GRC2" = 0 ] && [ "$(tail -1 "$GL" | grep -c '"decision":"error"')" = 1 ] && echo 1 || echo 0)"
BEFORE="$(wc -l < "$GL")"; printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git stash"}}' | FLEET_GUARD=off FLEET_GUARD_LOG="$GL" python3 "$OPS/guard.py"; 
ok "FLEET_GUARD=off (a person running the review) neither blocks nor logs" "$([ "$(wc -l < "$GL")" = "$BEFORE" ] && echo 1 || echo 0)"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git stash"},"cwd":"/tmp/x"}' | FLEET_GUARD_LOG="/nonexistent-root-dir/sub/guard.jsonl" python3 "$OPS/guard.py" > "$T/unw.out" 2>&1
ok "an unwritable log path changes nothing: the deny is still printed" "$([ "$(grep -c permissionDecision "$T/unw.out")" = 1 ] && echo 1 || echo 0)"
ok "the default log path is ~/fleet_review/logs/guard.jsonl" "$([ "$(grep -c 'DEFAULT_LOG = os.path.expanduser("~/fleet_review/logs/guard.jsonl")' "$OPS/guard.py")" = 1 ] && echo 1 || echo 0)"

echo "== P7: denial count in runs.log (real run_review.sh, stub claude) =="
runfull(){ # runfull <home> : 4 pre-existing guard lines (2 deny) from an earlier run, then one full run
  printf '%s\n' '{"decision":"deny"}' '{"decision":"allow"}' '{"decision":"deny"}' '{"decision":"allow"}' > "$1/fleet_review/logs/guard.jsonl"
  HOME="$1" FLEET_REVIEW_REPO="$1/repo" FLEET_REVIEW_POLL_S=1 FLEET_REVIEW_NOW="$N" bash "$1/fleet_review/run_review.sh" >/dev/null 2>&1; echo $?
}
mkhome "$T/h2" "$OPS"; RRC="$(runfull "$T/h2")"; RL="$(cat "$T/h2/fleet_review/logs/runs.log")"
ok "the run completes (rc 0) and logs start/end" "$([ "$RRC" = 0 ] && [ "$(has "$RL" ' start')" = 1 ] && [ "$(has "$RL" ' end')" = 1 ] && echo 1 || echo 0)"
ok "runs.log carries this run's denial count (2 denied, 1 internal error, 6 decisions: the 4 earlier lines are not counted)" "$(has "$RL" 'guard: 2 denied, 1 internal errors (fail-open), 6 decisions (logs/guard.jsonl)')"
ok "the guard line comes before the 'end' line" "$([ "$(grep -n 'guard:' "$T/h2/fleet_review/logs/runs.log" | cut -d: -f1)" -lt "$(grep -n ' end$' "$T/h2/fleet_review/logs/runs.log" | cut -d: -f1)" ] && echo 1 || echo 0)"
PS="$(cat "$T/h2/prompt.seen" 2>/dev/null)"
ok "claude -p received the window header followed by the prompt" "$([ "$(has "$PS" 'WINDOW_START_UTC=2026-10-12T12:43:00Z')" = 1 ] && [ "$(has "$PS" 'HARD GUARDRAILS')" = 1 ] && echo 1 || echo 0)"
mkhome "$T/h3" "$OPS"; printf '#!/bin/bash\necho nothing\n' > "$T/h3/.local/bin/claude"; chmod +x "$T/h3/.local/bin/claude"; rm -f "$T/h3/fleet_review/logs/guard.jsonl"
HOME="$T/h3" FLEET_REVIEW_REPO="$T/h3/repo" FLEET_REVIEW_POLL_S=1 bash "$T/h3/fleet_review/run_review.sh" >/dev/null 2>&1
ok "a run with no guard log at all reports 0 denied / 0 decisions (no crash, no negative numbers)" "$(has "$(cat "$T/h3/fleet_review/logs/runs.log")" 'guard: 0 denied, 0 internal errors (fail-open), 0 decisions')"

echo "== MUTATION controls =="
mut(){ # mut <name> <file> <old> <new>: scratch ops dir with ONE edit; prints the dir
  local d="$T/mut_$1"; rm -rf "$d"; mkdir -p "$d"; cp "$OPS"/* "$d"/ 2>/dev/null
  python3 - "$d/$2" "$3" "$4" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
assert s.count(a) == 1, (p, a, s.count(a))
open(p, "w").write(s.replace(a, b))
PY
  echo "$d"
}
M1="$(mut nowin run_review.sh 'compose_prompt() { fleet_window_header; echo; cat "$D/prompt.md"; }' 'compose_prompt() { cat "$D/prompt.md"; }')"
mkhome "$T/m1" "$M1"
ok "MUTATION: without the window header the prompt has no WINDOW_START_UTC" "$([ "$(dry "$T/m1" "$N" | grep -c 'WINDOW_START_UTC=')" = 0 ] && echo 1 || echo 0)"
M2="$(mut utcbug run_review.sh '  end="$now"; start=$(( now - hrs * 3600 ))' '  end="$now"; start=$(( now - hrs * 3600 - 5 * 3600 ))')"
mkhome "$T/m2" "$M2"
ok "MUTATION: a 5h-shifted window (the original bug's size) is caught by the exact-value assertions" "$([ "$(dry "$T/m2" "$N" | grep -c 'WINDOW_START_UTC=2026-10-12T12:43:00Z')" = 0 ] && echo 1 || echo 0)"
M3="$(mut nolog guard.py '    log_decision(ev, out)
    return json.dumps(out) if out else None' '    return json.dumps(out) if out else None')"
ok "MUTATION: a guard that never logs fails its own selftest" "$([ "$(python3 "$M3/guard.py" --selftest >/dev/null 2>&1; echo $?)" != 0 ] && echo 1 || echo 0)"
M4="$(mut cnt run_review.sh "gj_deny=\"\$(printf '%s' \"\$gj_new\" | grep -c '\"decision\":\"deny\"')\"" "gj_deny=\"\$(printf '%s' \"\$gj_new\" | grep -c '\"decision\":\"')\"")"
mkhome "$T/m4" "$M4"; runfull "$T/m4" >/dev/null
ok "MUTATION: counting every decision as a denial is caught (expects '2 denied')" "$([ "$(grep -c 'guard: 2 denied' "$T/m4/fleet_review/logs/runs.log")" = 0 ] && echo 1 || echo 0)"
M5="$(mut allruns run_review.sh 'gj0="${gj0:-0}"' 'gj0=0')"
mkhome "$T/m5" "$M5"; runfull "$T/m5" >/dev/null
ok "MUTATION: counting the earlier runs' lines too is caught (expects 6 decisions, not 10)" "$([ "$(grep -c '6 decisions' "$T/m5/fleet_review/logs/runs.log")" = 0 ] && echo 1 || echo 0)"
M6="$(mut openfail guard.py '        log_decision(ev if isinstance(ev, dict) else {}, None, err=e)
        return None' '        return None')"
ok "MUTATION: a guard that fails open silently (no 'error' record) fails its selftest" "$([ "$(python3 "$M6/guard.py" --selftest >/dev/null 2>&1; echo $?)" != 0 ] && echo 1 || echo 0)"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
