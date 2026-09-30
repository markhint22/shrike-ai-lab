#!/usr/bin/env bash
# Regression test for gitlark_control_consumer.sh - the consumer side of gitlark's P5 conversational control plane
# (promote / pause trigger lines in .gitlark/fleet-control.jsonl on a repo's overnight/feature branch).
# Moved here from the tree root (2026-09-30) and extended. Uses REAL local git repos (bare origin + clone per case) so the
# consumer's actual `git fetch` / `git show origin/<branch>:<path>` run; promote_to_prod.sh is a stub sitting next to a COPY
# of the consumer (so $HERE resolves to the stub); curl is an exported function (logs, never hits the network).
# Original coverage: no-file no-op, promote, pause (manual, no deploy_pause), idempotent re-run, malformed JSON, --dry-run.
# Added coverage: usage errors, SKIP no-checkout / no-branch, empty file, nothing-new, garbage + oversized seen marker,
# blank lines, unrecognised action, non-object / non-string / empty action JSON, missing marker, incremental append,
# alerts (ntfy title/tags/priority/body), shrike-notify dual publish + lib absent, failing promote still advances,
# multi-repo runs, dry-run on promote, state dir auto-create, 120-char truncation of malformed lines.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../gitlark_control_consumer.sh"; [ -f "$SRC" ] || SRC="$HERE/../gitlark_control_consumer.sh"; [ -f "$SRC" ] || SRC="$HERE/gitlark_control_consumer.sh"
LIB="$(dirname "$SRC")/shrike_notify_lib.sh"
[ -f "$SRC" ] || { echo "gitlark_control_consumer.sh not found"; exit 1; }
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"; printf '[user]\n\temail = t@t\n\tname = t\n' > "$GIT_CONFIG_GLOBAL"; export GIT_CONFIG_NOSYSTEM=1

BIN="$tmp/bin"; mkdir -p "$BIN"; cp "$SRC" "$BIN/gitlark_control_consumer.sh"; chmod +x "$BIN/gitlark_control_consumer.sh"
PROMOTE_LOG="$tmp/promote_calls.log"
cat > "$BIN/promote_to_prod.sh" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "$PROMOTE_LOG"
exit "\${PROMOTE_RC:-0}"
STUB
chmod +x "$BIN/promote_to_prod.sh"
# second sandbox that also carries the real shrike_notify_lib.sh (dual publish)
BIN2="$tmp/bin2"; mkdir -p "$BIN2"; cp "$BIN/gitlark_control_consumer.sh" "$BIN/promote_to_prod.sh" "$BIN2/"
[ -f "$LIB" ] && cp "$LIB" "$BIN2/shrike_notify_lib.sh"

export OVERNIGHT_DIR="$tmp/overnight-queue"; STATE="$OVERNIGHT_DIR/state"; mkdir -p "$STATE"
export NTFY_TOPIC="test_topic_never_sent"; export NTFY_LOG="$tmp/ntfy.log"
curl(){ echo "CURL $*" >> "$NTFY_LOG"; return 0; }; export -f curl
unset SHRIKE_NOTIFY_URL
run(){ "$BIN/gitlark_control_consumer.sh" "$@"; }
promotes(){ [ -f "$PROMOTE_LOG" ] && awk -v p="$1" 'index($0,p){n++} END{print n+0}' "$PROMOTE_LOG" || echo 0; }

make_repo() {   # $1 name [$2 = "nobranch" to skip pushing overnight/feature]
  local name="$1" bare="$tmp/remotes/$1.git" work="$tmp/repos/$1"
  mkdir -p "$(dirname "$bare")"; git init -q --bare "$bare"; git clone -q "$bare" "$work" 2>/dev/null
  git -C "$work" checkout -q -b main; echo init > "$work/README.md"; git -C "$work" add README.md; git -C "$work" commit -q -m init
  git -C "$work" push -q origin main
  git -C "$work" checkout -q -b overnight/feature
  [ "${2:-}" = nobranch ] || git -C "$work" push -q origin overnight/feature
}
write_control_lines() {  # (re)write whole file, commit, push
  local work="$1"; shift; mkdir -p "$work/.gitlark"; printf '%s\n' "$@" > "$work/.gitlark/fleet-control.jsonl"
  git -C "$work" add .gitlark/fleet-control.jsonl; git -C "$work" commit -q -m "control update"; git -C "$work" push -q origin overnight/feature
}
append_control_line() {  # append + push
  local work="$1"; shift; printf '%s\n' "$@" >> "$work/.gitlark/fleet-control.jsonl"
  git -C "$work" add -A; git -C "$work" commit -q -m "control append"; git -C "$work" push -q origin overnight/feature
}
PROMO(){ printf '{"action":"promote","marker":"gitlark-control:promote:%s:tok","requested_by":"u","requested_at":"2026-09-18T00:00:00Z","workspace_id":"%s"}' "$1" "$1"; }
PAUSE(){ printf '{"action":"pause","marker":"gitlark-control:pause:%s:tok","requested_by":"u","requested_at":"2026-09-18T00:00:00Z","workspace_id":"%s"}' "$1" "$1"; }
seen(){ cat "$STATE/gitlark_control_seen_$1" 2>/dev/null || echo MISSING; }
clear_state(){ rm -f "$STATE/PAUSED" "$NTFY_LOG"; }

# ---- 0. usage ----
out="$(run 2>&1)"; rc=$?
ok "no args -> usage on stdout, exit 2" "$([ $rc = 2 ] && printf '%s' "$out" | grep -q '^usage: gitlark_control_consumer.sh' && echo 1 || echo 0)"
out="$(run --dry-run 2>&1)"; rc=$?
ok "only --dry-run (no repos) -> usage, exit 2" "$([ $rc = 2 ] && printf '%s' "$out" | grep -q usage && echo 1 || echo 0)"
out="$(run "$tmp/repos/ghost" 2>&1)"; rc=$?
ok "repo dir without .git -> 'SKIP <name> (no checkout)', exit 0" "$([ $rc = 0 ] && printf '%s' "$out" | grep -q 'SKIP ghost (no checkout)' && echo 1 || echo 0)"
ok "state dir is created on start (mkdir -p)" "$( ( rm -rf "$tmp/fresh"; OVERNIGHT_DIR="$tmp/fresh" "$BIN/gitlark_control_consumer.sh" "$tmp/repos/ghost" >/dev/null 2>&1; [ -d "$tmp/fresh/state" ] ) && echo 1 || echo 0)"

# ---- 1. no control file / branch / empty file ----
make_repo noop_repo
out="$(run "$tmp/repos/noop_repo" 2>&1)"; rc=$?
ok "no control file: exit 0, 'no-op' logged" "$([ $rc = 0 ] && printf '%s' "$out" | grep -q 'no-op' && echo 1 || echo 0)"
ok "no control file: PAUSED untouched, promote not called, no seen file" "$([ ! -f "$STATE/PAUSED" ] && [ ! -f "$PROMOTE_LOG" ] && [ ! -f "$STATE/gitlark_control_seen_noop_repo" ] && echo 1 || echo 0)"
make_repo nobranch_repo nobranch
out="$(run "$tmp/repos/nobranch_repo" 2>&1)"
ok "remote without overnight/feature -> 'SKIP <name> (no overnight/feature)'" "$(printf '%s' "$out" | grep -q 'SKIP nobranch_repo (no overnight/feature)' && echo 1 || echo 0)"
make_repo empty_repo; mkdir -p "$tmp/repos/empty_repo/.gitlark"; : > "$tmp/repos/empty_repo/.gitlark/fleet-control.jsonl"
git -C "$tmp/repos/empty_repo" add -A; git -C "$tmp/repos/empty_repo" commit -q -m empty; git -C "$tmp/repos/empty_repo" push -q origin overnight/feature
out="$(run "$tmp/repos/empty_repo" 2>&1)"
ok "empty control file treated as no-op" "$(printf '%s' "$out" | grep -q 'empty_repo: no .gitlark/fleet-control.jsonl (no-op)' && echo 1 || echo 0)"

# ---- 2. promote ----
make_repo promote_repo; write_control_lines "$tmp/repos/promote_repo" "$(PROMO ws1)"; clear_state
out="$(run "$tmp/repos/promote_repo" 2>&1)"
ok "promote line -> exactly one promote_to_prod.sh call" "$([ "$(promotes repos/promote_repo)" = 1 ] && echo 1 || echo 0)"
ok "promote_to_prod.sh invoked as '--yes <repo>'" "$(grep -q -- "^--yes $tmp/repos/promote_repo\$" "$PROMOTE_LOG" && echo 1 || echo 0)"
ok "promote logged with its marker" "$(printf '%s' "$out" | grep -q 'gitlark-triggered PROMOTE (gitlark-control:promote:ws1:tok)' && echo 1 || echo 0)"
ok "promote: seen counter = 1" "$([ "$(seen promote_repo)" = 1 ] && echo 1 || echo 0)"
ok "promote: ntfy alert title/tag/priority/body" "$(grep -q 'Title: gitlark-triggered promote: promote_repo' "$NTFY_LOG" && grep -q 'Tags: rocket' "$NTFY_LOG" && grep -q 'Priority: default' "$NTFY_LOG" && grep -q 'marker=gitlark-control:promote:ws1:tok' "$NTFY_LOG" && grep -q 'https://ntfy.sh/test_topic_never_sent' "$NTFY_LOG" && echo 1 || echo 0)"
ok "promote does not pause the fleet" "$([ ! -f "$STATE/PAUSED" ] && echo 1 || echo 0)"

# ---- 3. pause ----
make_repo pause_repo; write_control_lines "$tmp/repos/pause_repo" "$(PAUSE ws2)"; clear_state
run "$tmp/repos/pause_repo" >/dev/null 2>&1
ok "pause line touches state/PAUSED" "$([ -f "$STATE/PAUSED" ] && echo 1 || echo 0)"
ok "pause is MANUAL: no deploy_pause marker" "$([ ! -f "$STATE/deploy_pause" ] && echo 1 || echo 0)"
ok "pause does not call promote_to_prod.sh" "$([ "$(promotes repos/pause_repo)" = 0 ] && echo 1 || echo 0)"
ok "pause alert: 'warning' tag + names the workspace repo" "$(grep -q 'Title: gitlark-triggered fleet pause' "$NTFY_LOG" && grep -q 'Tags: warning' "$NTFY_LOG" && grep -q "via pause_repo's workspace" "$NTFY_LOG" && echo 1 || echo 0)"
rm -f "$STATE/PAUSED"

# ---- 4. idempotency ----
run "$tmp/repos/promote_repo" >/dev/null 2>&1
ok "re-run does not reprocess promote (still 1 call)" "$([ "$(promotes repos/promote_repo)" = 1 ] && echo 1 || echo 0)"
out="$(run "$tmp/repos/pause_repo" 2>&1)"
ok "re-run does not reprocess pause; logs 'nothing new (1/1 ...)'" "$([ ! -f "$STATE/PAUSED" ] && printf '%s' "$out" | grep -q 'nothing new (1/1 already processed)' && echo 1 || echo 0)"
append_control_line "$tmp/repos/pause_repo" "$(PAUSE ws2b)"; clear_state
out="$(run "$tmp/repos/pause_repo" 2>&1)"
ok "appended line is the ONLY one processed (1 new, seen 1 total 2)" "$([ -f "$STATE/PAUSED" ] && printf '%s' "$out" | grep -q '1 new control line(s) (seen 1, total 2)' && [ "$(seen pause_repo)" = 2 ] && echo 1 || echo 0)"
rm -f "$STATE/PAUSED"
echo 99 > "$STATE/gitlark_control_seen_pause_repo"; out="$(run "$tmp/repos/pause_repo" 2>&1)"
ok "seen marker larger than the file (file rewritten shorter) -> 'nothing new', no crash" "$(printf '%s' "$out" | grep -q 'nothing new (99/2' && [ ! -f "$STATE/PAUSED" ] && echo 1 || echo 0)"
echo "garbage" > "$STATE/gitlark_control_seen_pause_repo"; clear_state
run "$tmp/repos/pause_repo" >/dev/null 2>&1
ok "non-numeric seen marker resets to 0 -> whole file reprocessed, marker repaired to 2" "$([ -f "$STATE/PAUSED" ] && [ "$(seen pause_repo)" = 2 ] && echo 1 || echo 0)"
rm -f "$STATE/PAUSED"; : > "$STATE/gitlark_control_seen_pause_repo"; run "$tmp/repos/pause_repo" >/dev/null 2>&1
ok "empty seen marker file treated as 0" "$([ -f "$STATE/PAUSED" ] && echo 1 || echo 0)"
rm -f "$STATE/PAUSED"

# ---- 5. malformed / odd lines ----
make_repo malformed_repo
long="$(printf 'x%.0s' $(seq 1 200))"
write_control_lines "$tmp/repos/malformed_repo" 'not valid json at all' "$long" '' '[1,2,3]' '"just a string"' '123' 'null' '{"action":""}' '{"action":7,"marker":"m"}' '{"marker":"no action"}' '{"action":"deploy_prod","marker":"mk-unknown"}' "$(PROMO ws3)"
clear_state; : > "$PROMOTE_LOG"
out="$(run "$tmp/repos/malformed_repo" 2>&1)"; rc=$?
ok "malformed/odd-line run exits 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "invalid JSON logged as malformed with its line number" "$(printf '%s' "$out" | grep -q 'malformed control line #1 — skipping: not valid json' && echo 1 || echo 0)"
ok "malformed line echo is truncated to 120 chars" "$(printf '%s' "$out" | grep 'malformed control line #2' | grep -q "x\{120\}\$" && ! printf '%s' "$out" | grep 'malformed control line #2' | grep -q "x\{121\}" && echo 1 || echo 0)"
ok "blank line skipped silently (no malformed log for #3)" "$(! printf '%s' "$out" | grep -q 'malformed control line #3' && echo 1 || echo 0)"
nm="$(printf '%s' "$out" | grep -c 'malformed control line')"
ok "non-object JSON (array/string/number/null), empty action, non-string action, missing action are ALL malformed (9 total)" "$([ "$nm" = 9 ] && echo 1 || echo "0")"
ok "unrecognised action logged + skipped (no promote/pause side effect)" "$(printf '%s' "$out" | grep -q "unrecognized control action 'deploy_prod' (mk-unknown) — skipping" && echo 1 || echo 0)"
ok "the valid promote at the END still ran exactly once" "$([ "$(promotes repos/malformed_repo)" = 1 ] && [ ! -f "$STATE/PAUSED" ] && echo 1 || echo 0)"
ok "seen counter advanced past every line (12)" "$([ "$(seen malformed_repo)" = 12 ] && echo 1 || echo "0 got $(seen malformed_repo)")"
run "$tmp/repos/malformed_repo" >/dev/null 2>&1
ok "malformed lines are not retried on the next run" "$([ "$(promotes repos/malformed_repo)" = 1 ] && echo 1 || echo 0)"

# marker-less promote
make_repo nomarker_repo; write_control_lines "$tmp/repos/nomarker_repo" '{"action":"promote"}'; : > "$PROMOTE_LOG"
out="$(run "$tmp/repos/nomarker_repo" 2>&1)"
ok "promote without a marker still runs (empty marker)" "$([ "$(promotes repos/nomarker_repo)" = 1 ] && printf '%s' "$out" | grep -q 'PROMOTE ()' && echo 1 || echo 0)"

# ---- 6. promote failure must not cause a retry storm ----
make_repo failp_repo; write_control_lines "$tmp/repos/failp_repo" "$(PROMO ws9)"; : > "$PROMOTE_LOG"; clear_state
PROMOTE_RC=1 run "$tmp/repos/failp_repo" >/dev/null 2>&1; rc=$?
ok "promote_to_prod.sh failing: consumer still exits 0, line marked seen (no endless retry)" "$([ $rc = 0 ] && [ "$(seen failp_repo)" = 1 ] && echo 1 || echo 0)"
run "$tmp/repos/failp_repo" >/dev/null 2>&1
ok "failed promote is not re-attempted" "$([ "$(promotes repos/failp_repo)" = 1 ] && echo 1 || echo 0)"

# ---- 7. dry run ----
make_repo dryrun_repo; write_control_lines "$tmp/repos/dryrun_repo" "$(PAUSE ws4)" "$(PROMO ws4p)"; : > "$PROMOTE_LOG"; clear_state
out="$(run --dry-run "$tmp/repos/dryrun_repo" 2>&1)"
ok "--dry-run: no PAUSED, no promote call, no ntfy, no seen file" "$([ ! -f "$STATE/PAUSED" ] && [ ! -s "$PROMOTE_LOG" ] && [ ! -f "$NTFY_LOG" ] && [ ! -f "$STATE/gitlark_control_seen_dryrun_repo" ] && echo 1 || echo 0)"
ok "--dry-run announces both actions" "$(printf '%s' "$out" | grep -q "\[dry-run\] would touch $STATE/PAUSED" && printf '%s' "$out" | grep -q "\[dry-run\] would run: .*promote_to_prod.sh --yes $tmp/repos/dryrun_repo" && echo 1 || echo 0)"
out="$(run "$tmp/repos/dryrun_repo" --dry-run 2>&1)"
ok "--dry-run accepted after the repo arg too" "$(printf '%s' "$out" | grep -q 'would touch' && echo 1 || echo 0)"
run "$tmp/repos/dryrun_repo" >/dev/null 2>&1
ok "real run after dry-runs still processes both lines (dry-run leaked no state)" "$([ -f "$STATE/PAUSED" ] && [ "$(promotes repos/dryrun_repo)" = 1 ] && [ "$(seen dryrun_repo)" = 2 ] && echo 1 || echo 0)"
rm -f "$STATE/PAUSED"

# ---- 8. multi-repo run ----
make_repo multi_a; make_repo multi_b; make_repo multi_c
write_control_lines "$tmp/repos/multi_a" "$(PROMO a)"; write_control_lines "$tmp/repos/multi_b" "$(PAUSE b)"; : > "$PROMOTE_LOG"; clear_state
out="$(run "$tmp/repos/multi_a" "$tmp/repos/nonexistent" "$tmp/repos/multi_b" "$tmp/repos/multi_c" 2>&1)"; rc=$?
ok "multi-repo: each repo handled independently in one run (promote a, skip missing, pause b, no-op c)" "$([ $rc = 0 ] && [ "$(promotes repos/multi_a)" = 1 ] && [ -f "$STATE/PAUSED" ] && printf '%s' "$out" | grep -q 'SKIP nonexistent' && printf '%s' "$out" | grep -q 'multi_c: no .gitlark' && echo 1 || echo 0)"
ok "multi-repo: independent seen markers per repo" "$([ "$(seen multi_a)" = 1 ] && [ "$(seen multi_b)" = 1 ] && [ "$(seen multi_c)" = MISSING ] && echo 1 || echo 0)"
rm -f "$STATE/PAUSED"

# ---- 9. shrike-notify dual publish ----
if [ -f "$BIN2/shrike_notify_lib.sh" ]; then
  make_repo sn_repo; write_control_lines "$tmp/repos/sn_repo" "$(PAUSE s1)"; clear_state
  SHRIKE_NOTIFY_URL="https://sn.example.app/" "$BIN2/gitlark_control_consumer.sh" "$tmp/repos/sn_repo" >/dev/null 2>&1
  ok "SHRIKE_NOTIFY_URL set -> also published to <url>/fleet_<repo>_control" "$(grep -q 'CURL .*https://sn.example.app/fleet_sn_repo_control' "$NTFY_LOG" && grep -q 'https://ntfy.sh/test_topic_never_sent' "$NTFY_LOG" && echo 1 || echo 0)"
  ok "shrike payload carries title + tags" "$(grep 'fleet_sn_repo_control' "$NTFY_LOG" | grep -q 'gitlark-triggered fleet pause' && echo 1 || echo 0)"
  rm -f "$STATE/PAUSED" "$NTFY_LOG" "$STATE/gitlark_control_seen_sn_repo"
  "$BIN2/gitlark_control_consumer.sh" "$tmp/repos/sn_repo" >/dev/null 2>&1
  ok "SHRIKE_NOTIFY_URL unset (lib present) -> only ntfy.sh is called" "$([ "$(grep -c '^CURL' "$NTFY_LOG")" = 1 ] && grep -q ntfy.sh "$NTFY_LOG" && echo 1 || echo 0)"
else echo "  skip shrike dual-publish cases (shrike_notify_lib.sh not found)"; fi
make_repo nolib_repo; write_control_lines "$tmp/repos/nolib_repo" "$(PAUSE n1)"; clear_state
SHRIKE_NOTIFY_URL="https://sn.example.app" run "$tmp/repos/nolib_repo" >/dev/null 2>&1; rc=$?
ok "shrike lib absent next to the script: still works, only ntfy.sh called" "$([ $rc = 0 ] && [ -f "$STATE/PAUSED" ] && [ "$(grep -c '^CURL' "$NTFY_LOG")" = 1 ] && ! grep -q sn.example "$NTFY_LOG" && echo 1 || echo 0)"
rm -f "$STATE/PAUSED"

echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
