#!/usr/bin/env bash
# Regression tests for ovn_log_tokens.sh: appends one {ts,source,repo,tokens_sent,tokens_recv} JSON line to
# state/token_ledger.jsonl; never fails the caller (every error path exits 0). Hermetic: OVERNIGHT_DIR/HOME temp dirs.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/../ovn_log_tokens.sh"; [ -f "$SH" ] || SH="$HOME/overnight-queue/scripts/ovn_log_tokens.sh"
[ -f "$SH" ] || { echo "  SKIP: script not found"; exit 0; }
pass=0; fail=0; warnc=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }
known(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else warnc=$((warnc+1)); echo "  WARN KNOWN-BUG: $l"; fi; }
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
unset OVERNIGHT_DIR
D="$T/d"; L="$D/state/token_ledger.jsonl"
run(){ OVERNIGHT_DIR="$D" bash "$SH" "$@"; }
field(){ python3 -c "import json,sys; print(json.loads(open('$L').read().splitlines()[$1])['$2'])"; }

echo "== happy path =="
run ovn_planner billwatch 1234 567; rc=$?
eqv "exit 0" "0" "$rc"
chk "state dir auto-created" test -d "$D/state"
chk "ledger line is valid JSON" python3 -c "import json; json.loads(open('$L').read())"
eqv "source" "ovn_planner" "$(field 0 source)"
eqv "repo" "billwatch" "$(field 0 repo)"
eqv "tokens_sent is a JSON number" "1234" "$(field 0 tokens_sent)"
eqv "tokens_recv is a JSON number" "567" "$(field 0 tokens_recv)"
chk "tokens are ints not strings" python3 -c "import json; r=json.loads(open('$L').read()); assert isinstance(r['tokens_sent'],int) and isinstance(r['tokens_recv'],int)"
chk "ts is UTC ISO8601 (…Z), close to now" python3 -c "
import json,re,time,calendar
r=json.loads(open('$L').read()); assert re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', r['ts'])
assert abs(calendar.timegm(time.strptime(r['ts'],'%Y-%m-%dT%H:%M:%SZ'))-time.time())<120"
run groom gitlark 10 20 extra ignored
eqv "append, not overwrite (2 lines)" "2" "$(wc -l < "$L" | tr -d ' ')"
eqv "extra args ignored; second line source" "groom" "$(field 1 source)"
chk "every line valid JSON" python3 -c "
import json
[json.loads(l) for l in open('$L')]"

echo "== defaults and null handling =="
rm -rf "$D"
run; eqv "no args: source defaults to 'unknown'" "unknown" "$(field 0 source)"
eqv "no args: repo defaults to '-'" "-" "$(field 0 repo)"
eqv "no args: sent defaults to 0" "0" "$(field 0 tokens_sent)"
eqv "no args: recv defaults to 0" "0" "$(field 0 tokens_recv)"
rm -rf "$D"; run src repo null null
eqv "'null' sent -> 0" "0" "$(field 0 tokens_sent)"
eqv "'null' recv -> 0" "0" "$(field 0 tokens_recv)"
rm -rf "$D"; run src repo "" ""
eqv "empty-string sent -> 0" "0" "$(field 0 tokens_sent)"
eqv "empty-string recv -> 0" "0" "$(field 0 tokens_recv)"
rm -rf "$D"; run src repo 5 null
eqv "mixed: real sent + null recv" "5/0" "$(field 0 tokens_sent)/$(field 0 tokens_recv)"
rm -rf "$D"; run src ""
eqv "empty repo arg -> defaults to '-' (\${2:--} treats empty as unset)" "-" "$(field 0 repo)"

echo "== HOME-based default dir =="
mkdir -p "$T/home"
( unset OVERNIGHT_DIR; HOME="$T/home" bash "$SH" homesrc r 1 2 )
chk "default DIR = \$HOME/overnight-queue" test -f "$T/home/overnight-queue/state/token_ledger.jsonl"

echo "== never fails the caller =="
echo x > "$T/afile"
OVERNIGHT_DIR="$T/afile" bash "$SH" a b 1 2; eqv "mkdir failure (dir path is under a regular file) -> exit 0" "0" "$?"
eqv "mkdir failure: silent on stdout+stderr" "" "$(OVERNIGHT_DIR="$T/afile" bash "$SH" a b 1 2 2>&1)"
rm -rf "$D"; mkdir -p "$D/state"; chmod 500 "$D/state"
out="$(run a b 1 2 2>&1)"; rc=$?
eqv "unwritable state dir -> exit 0" "0" "$rc"
known "unwritable state dir should be silent (2>/dev/null comes AFTER the failing >> redirect, so bash leaks 'Permission denied' to stderr)" test -z "$out"
chmod 700 "$D/state"
mkdir -p "$D/state/token_ledger.jsonl"   # ledger path is a directory: append fails
run a b 1 2 2>/dev/null; eqv "append failure (ledger is a dir) -> exit 0" "0" "$?"
rm -rf "$D"

echo "== input robustness (JSON validity of the ledger) =="
rm -rf "$D"; run 'src"quote' repo 1 2
known "source containing a double-quote must still yield valid JSON (printf %s is unescaped)" python3 -c "import json; json.loads(open('$L').read())"
rm -rf "$D"; run src repo abc 2
known "non-numeric token count must not corrupt the ledger with invalid JSON" python3 -c "import json; json.loads(open('$L').read())"
rm -rf "$D"; run src 'repo\path' 1 2
known "backslash in repo must still yield valid JSON" python3 -c "import json; json.loads(open('$L').read())"

echo
echo "$pass passed, $fail failed ($warnc known-bug warning(s))"
[ "$fail" -eq 0 ]
