#!/usr/bin/env bash
# Z7-C (2026-11-09): scripts/ovn_timeout_park_precision.py (replay of OVN_STAGE_TIMEOUT_PARK over state/stage_runs journals) + the pinned decision that the default stays SHADOW.
# Measured 2026-11-09 on the box (7 days): 10 items / 15 would-park events; item-level precision 7/10 = 70% (landed later by the fleet itself: get_epg_guide 239a3e9c, PlayerView 9c0b9505,
# clear_cache b546ba49; two more landed only through a Claude commit and count as true parks) < the 80% bar. Mutants must be killed.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
T="$(safe_mktemp_dir z7tp)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
SRC="${Z7_TP_SRC:-$HERE/../ovn_timeout_park_precision.py}"
Q="$HERE/../.."; [ -f "$Q/ovn_stage_runner.sh" ] || Q="$HERE/.."
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1 (expected [$2] got [$3])"; fi; }
mkdir -p "$T/state/stage_runs"
# run <id> <repo> <item> then step rows "files|attempt|verdict|reason"; summary pushed N
mk(){ local id="$1" repo="$2" item="$3" pushed="$4"; shift 4; local f="$T/state/stage_runs/${repo}-${id}.jsonl"
  printf '{"run":"%s","repo":"%s","tier":3,"item":"%s","event":"decomposed","steps":1}\n' "$id" "$repo" "$item" > "$f"
  local s; for s in "$@"; do IFS='|' read -r fl at vd rs <<< "$s"; printf '{"run":"%s","step":0,"desc":"d","files":"%s","attempt":%s,"verdict":"%s","fail_reason":"%s","duration_s":350}\n' "$id" "$fl" "$at" "$vd" "$rs" >> "$f"; done
  printf '{"run":"%s","event":"summary","passed":0,"total":1,"commits_pushed":%s}\n' "$id" "$pushed" >> "$f"; }
# X: 2 timeouts (event), later a PASS on the same files -> FALSE park
mk 20261105-100000-1 r "[T3] X item" 0 "a.py|1|fail|timeout" "a.py|2|fail|timeout"
mk 20261105-120000-2 r "[T3] X item" 0 "a.py|1|pass|"
# U: 2 timeouts, a later run of the same item pushed commits through another step (no pass on the same files) -> FALSE park (item level)
mk 20261105-130000-9 r "[T3] U item" 0 "u.py|1|fail|timeout" "u.py|2|fail|timeout"
mk 20261105-150000-10 r "[T3] U item" 2 "w.py|1|fail|test-red"
# Y: 2 timeouts, never lands -> true park (and a third timeout later: same item, one item)
mk 20261106-100000-3 r "[T3] Y item" 0 "b.py|1|fail|timeout" "b.py|2|fail|timeout"
mk 20261106-130000-4 r "[T3] Y item" 0 "b.py|1|fail|timeout"
# Z: two timeouts on DIFFERENT file sets -> no event
mk 20261106-140000-5 r "[T3] Z item" 0 "c.py|1|fail|timeout" "d.py|1|fail|timeout"
# W: old item (outside 7 days of the newest run) -> not counted
mk 20261020-100000-6 r "[T3] W item" 0 "e.py|1|fail|timeout" "e.py|2|fail|timeout"
# V: a PASS BEFORE the event does not make it a false park; non-timeout failures never count; file order must not matter
mk 20261107-100000-7 r "[T3] V item" 0 "f.py g.py|1|pass|" "g.py|1|fail|timeout" "f.py|2|fail|timeout" "f.py|3|fail|test-red"
mk 20261107-110000-8 r "[T3] V item" 0 "f.py g.py|1|fail|timeout" "g.py f.py|2|fail|timeout"
run(){ "$PY" "${1:-$SRC}" --state "$T/state" "${@:2}"; }
j(){ "$PY" -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
chk "T1 events: X(1) Y(2: 2nd and 3rd timeout) V(1) = 4 within 7 days (V: only the f.py|g.py key reaches 2); Z split key, W old, non-timeouts ignored" "5 4" "$(run | j '"%d %d" % (d["events"], d["items"])')"
chk "T2 false parks: X (a later attempt on the same files passed) + U (a later run of the item pushed)" 2 "$(run | j 'd["false_parks"]')"
chk "T3 precision 2/4" 0.5 "$(run | j 'd["precision"]')"
chk "T4 --at 3: only Y's third timeout counts -> 1 event / 1 item, not false" "1 1 0" "$(run "$SRC" --at 3 | j '"%d %d %d" % (d["events"], d["items"], d["false_parks"])')"
chk "T5 --days 60 brings the old item W in" 5 "$(run "$SRC" --days 60 | j 'd["items"]')"
chk "T6 a PASS before the event is not a later pass (V)" False "$(run | j '[x for x in d["detail"] if x["item"].startswith("[T3] V")][0]["false_park"]')"
chk "T7 empty state -> precision null" None "$(mkdir -p "$T/empty/stage_runs"; "$PY" "$SRC" --state "$T/empty" | j 'd["precision"]')"
chk "T8 a journal without a parsable run id is skipped, not a crash" 0 "$(printf 'garbage\n' > "$T/state/stage_runs/x.jsonl"; run >/dev/null; echo $?)"
# the decision is pinned: default stays SHADOW, on/off still selectable
grep -q 'OVN_STAGE_TIMEOUT_PARK:-shadow' "$Q/ovn_stage_runner.sh" && chk "T9 default stays shadow (7/10 = 70% < 80%)" 1 1 || chk "T9 default stays shadow" 1 0
grep -q '70%' "$Q/ovn_stage_runner.sh" && chk "T10 the runner documents the measured precision" 1 1 || chk "T10 runner documents the precision" 1 0
mutants=0; survived=0
if [ -z "${Z7_TP_SRC:-}" ]; then
mut(){ local label="$1" old="$2" new="$3"; mutants=$((mutants+1)); OLD="$old" NEW="$new" "$PY" - "$SRC" "$T/mut.py" <<'PYEOF' || { echo "  FAIL mutant not applicable: $label"; survived=$((survived+1)); return; }
import os, sys
s = open(sys.argv[1]).read(); old = os.environ["OLD"]
if old not in s: sys.exit(3)
open(sys.argv[2], "w").write(s.replace(old, os.environ["NEW"], 1))
PYEOF
  if Z7_TP_SRC="$T/mut.py" bash "$0" >/dev/null 2>&1; then echo "  FAIL mutant SURVIVED: $label"; survived=$((survived+1)); else echo "  ok   mutant killed: $label"; fi
}
mut "later pass ignored"                   'd["later_pass_same_files"] = any(x > d["_seq"] for x in passes.get(d["_key"], []))' 'd["later_pass_same_files"] = False'
mut "item-level landing ignored"            'd["landed_later_stage"] = any(' 'd["landed_later_stage"] = False and any('
mut "a pass BEFORE the event counts"      'd["later_pass_same_files"] = any(x > d["_seq"] for x in passes.get(d["_key"], []))' 'd["later_pass_same_files"] = bool(passes.get(d["_key"]))'
mut "any failure counts as a timeout"      'if s.get("fail_reason") != "timeout":' 'if False:'
mut "file order matters"                   'files = sorted(set(f for f in' 'files = list((f for f in'
mut "no 7-day window"                      'and r["ts"] >= lo' ''
mut "events not per file set"              'k = (r["repo"], _ihash(r["item"]), "|".join(files))' 'k = (r["repo"], _ihash(r["item"]), "")'
mut "N threshold ignored"                  'if cnt[k] >= at and' 'if cnt[k] >= 1 and'
fi
chk "T11 mutants survived" 0 "$survived"
echo "timeout park precision: $P passed, $F failed ($mutants mutants)"
[ "$F" -eq 0 ]
