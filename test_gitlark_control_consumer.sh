#!/usr/bin/env bash
# Regression test for gitlark_control_consumer.sh — the consumer side of
# gitlark's P5 conversational control-plane (promote/pause_fleet trigger
# commits written to .gitlark/fleet-control.jsonl on a workspace's target
# branch). Verifies:
#   - no control file present is a silent no-op
#   - a fresh promote line calls promote_to_prod.sh exactly once
#   - a fresh pause line touches state/PAUSED
#   - already-seen lines are never reprocessed on a second run
#   - malformed JSON is skipped without crashing the run
#   - --dry-run touches nothing (no PAUSED, no promote_to_prod.sh call, and —
#     critically — does not advance the idempotency counter either)
#
# Uses real local git repos (a bare "origin" + a working clone per test repo)
# so the consumer's actual `git fetch` / `git show origin/<branch>:<path>`
# calls are exercised, not mocked. promote_to_prod.sh is stubbed (copied next
# to the consumer script under test, in its own $HERE) so a real merge/smoke/
# tag/push flow is never invoked — this test only verifies the CONSUMER wiring.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/gitlark_control_consumer.sh"
[ -f "$SRC" ] || { echo "gitlark_control_consumer.sh not found next to this test"; exit 1; }

rc=0
fail(){ echo "  ❌ $1"; rc=1; }
ok(){ echo "  ✅ $1"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- sandbox: copy the consumer next to a stub promote_to_prod.sh, so $HERE
# (computed from BASH_SOURCE inside the script) resolves to our stub instead
# of the real production-promoting script.
BIN="$tmp/bin"; mkdir -p "$BIN"
cp "$SRC" "$BIN/gitlark_control_consumer.sh"
chmod +x "$BIN/gitlark_control_consumer.sh"

PROMOTE_LOG="$tmp/promote_calls.log"
cat > "$BIN/promote_to_prod.sh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$PROMOTE_LOG"
exit 0
EOF
chmod +x "$BIN/promote_to_prod.sh"

# STATE dir for the run (state/PAUSED + state/gitlark_control_seen_<name>)
export OVERNIGHT_DIR="$tmp/overnight-queue"
mkdir -p "$OVERNIGHT_DIR/state"
export NTFY_TOPIC="test_topic_never_sent"   # curl calls will just fail silently (no network needed, alert() swallows errors)

run(){ "$BIN/gitlark_control_consumer.sh" "$@"; }

# --- helper: build a bare "origin" + a working clone, with an overnight/feature
# branch. $1 = repo dir name (under $tmp/repos), rest are ignored.
make_repo() {
  local name="$1"
  local bare="$tmp/remotes/$name.git"
  local work="$tmp/repos/$name"
  mkdir -p "$(dirname "$bare")"
  git init -q --bare "$bare"
  git clone -q "$bare" "$work"
  git -C "$work" config user.email test@example.com
  git -C "$work" config user.name "Test"
  git -C "$work" checkout -q -b main
  echo "init" > "$work/README.md"
  git -C "$work" add README.md
  git -C "$work" commit -q -m "init"
  git -C "$work" push -q origin main
  git -C "$work" checkout -q -b overnight/feature
  git -C "$work" push -q origin overnight/feature
}

# write_control_lines <repo-work-dir> <line1> [line2 ...] — (re)writes the
# control file with the given lines and pushes overnight/feature.
write_control_lines() {
  local work="$1"; shift
  mkdir -p "$work/.gitlark"
  printf '%s\n' "$@" > "$work/.gitlark/fleet-control.jsonl"
  git -C "$work" add .gitlark/fleet-control.jsonl
  git -C "$work" commit -q -m "control update"
  git -C "$work" push -q origin overnight/feature
}

# ============================================================
# 1. No control file present -> silent no-op
# ============================================================
make_repo "noop_repo"
out="$(run "$tmp/repos/noop_repo" 2>&1)"
rc1=$?
[ "$rc1" -eq 0 ] && ok "no-op run exits 0" || fail "no-op run exited $rc1"
echo "$out" | grep -q "no-op" && ok "no-op logged for missing control file" || fail "expected no-op message, got: $out"
[ -f "$OVERNIGHT_DIR/state/PAUSED" ] && fail "PAUSED touched on no-op run" || ok "PAUSED untouched on no-op run"
[ -f "$PROMOTE_LOG" ] && fail "promote_to_prod.sh called on no-op run" || ok "promote_to_prod.sh not called on no-op run"

# ============================================================
# 2. Fresh promote line -> exactly one promote_to_prod.sh call
# ============================================================
make_repo "promote_repo"
write_control_lines "$tmp/repos/promote_repo" \
  '{"action":"promote","marker":"gitlark-control:promote:ws1:tok1","requested_by":"u1","requested_at":"2026-09-18T00:00:00Z","workspace_id":"ws1"}'
run "$tmp/repos/promote_repo" >/dev/null 2>&1
n="$(grep -cF "repos/promote_repo" "$PROMOTE_LOG" 2>/dev/null || echo 0)"
[ "$n" -eq 1 ] && ok "promote line triggered exactly 1 promote_to_prod.sh call" || fail "expected 1 promote call, got $n"
grep -q -- "--yes" "$PROMOTE_LOG" && ok "promote_to_prod.sh called with --yes" || fail "promote_to_prod.sh not called with --yes"

# ============================================================
# 3. Fresh pause line -> touches state/PAUSED
# ============================================================
make_repo "pause_repo"
write_control_lines "$tmp/repos/pause_repo" \
  '{"action":"pause","marker":"gitlark-control:pause:ws2:tok2","requested_by":"u2","requested_at":"2026-09-18T00:00:00Z","workspace_id":"ws2"}'
[ -f "$OVERNIGHT_DIR/state/PAUSED" ] && fail "PAUSED already existed before pause test" || true
run "$tmp/repos/pause_repo" >/dev/null 2>&1
[ -f "$OVERNIGHT_DIR/state/PAUSED" ] && ok "pause line touched state/PAUSED" || fail "state/PAUSED not created by pause line"
[ -f "$OVERNIGHT_DIR/state/deploy_pause" ] && fail "deploy_pause marker was touched (must be a MANUAL pause only)" || ok "deploy_pause marker correctly untouched (manual pause)"
rm -f "$OVERNIGHT_DIR/state/PAUSED"   # reset for later tests

# ============================================================
# 4. Already-seen lines are not reprocessed on a second run
# ============================================================
run "$tmp/repos/promote_repo" >/dev/null 2>&1
n="$(grep -cF "repos/promote_repo" "$PROMOTE_LOG" 2>/dev/null || echo 0)"
[ "$n" -eq 1 ] && ok "re-running does not reprocess already-seen promote line (still 1 call)" || fail "expected still 1 promote call after re-run, got $n"

run "$tmp/repos/pause_repo" >/dev/null 2>&1
[ -f "$OVERNIGHT_DIR/state/PAUSED" ] && fail "re-running reprocessed an already-seen pause line" || ok "re-running does not reprocess already-seen pause line"

# ============================================================
# 5. Malformed JSON is skipped without crashing, and the run still advances
#    past it (a later good line, if any, still gets processed / the counter
#    moves on so it isn't retried forever)
# ============================================================
make_repo "malformed_repo"
write_control_lines "$tmp/repos/malformed_repo" \
  'not valid json at all' \
  '{"action":"promote","marker":"gitlark-control:promote:ws3:tok3","requested_by":"u3","requested_at":"2026-09-18T00:00:00Z","workspace_id":"ws3"}'
out="$(run "$tmp/repos/malformed_repo" 2>&1)"
rc2=$?
[ "$rc2" -eq 0 ] && ok "malformed-line run exits 0 (doesn't crash)" || fail "malformed-line run exited $rc2"
echo "$out" | grep -qi "malformed" && ok "malformed line logged" || fail "expected a malformed-line log message, got: $out"
n="$(grep -cF "repos/malformed_repo" "$PROMOTE_LOG" 2>/dev/null || echo 0)"
[ "$n" -eq 1 ] && ok "the good promote line after the malformed one still ran (1 call)" || fail "expected 1 promote call for malformed_repo, got $n"
seen="$(cat "$OVERNIGHT_DIR/state/gitlark_control_seen_malformed_repo" 2>/dev/null || echo "MISSING")"
[ "$seen" = "2" ] && ok "seen-counter advanced past both lines (=2)" || fail "expected seen-counter=2, got '$seen'"

# ============================================================
# 6. --dry-run touches nothing: no PAUSED, no promote_to_prod.sh call, and
#    does not advance the idempotency counter (so a later real run still acts)
# ============================================================
make_repo "dryrun_repo"
write_control_lines "$tmp/repos/dryrun_repo" \
  '{"action":"pause","marker":"gitlark-control:pause:ws4:tok4","requested_by":"u4","requested_at":"2026-09-18T00:00:00Z","workspace_id":"ws4"}'
pre_promote_lines="$(wc -l < "$PROMOTE_LOG" 2>/dev/null || echo 0)"
run --dry-run "$tmp/repos/dryrun_repo" >/dev/null 2>&1
[ -f "$OVERNIGHT_DIR/state/PAUSED" ] && fail "--dry-run touched state/PAUSED" || ok "--dry-run left state/PAUSED untouched"
post_promote_lines="$(wc -l < "$PROMOTE_LOG" 2>/dev/null || echo 0)"
[ "$pre_promote_lines" -eq "$post_promote_lines" ] && ok "--dry-run did not call promote_to_prod.sh" || fail "--dry-run appears to have called promote_to_prod.sh"
seenfile="$OVERNIGHT_DIR/state/gitlark_control_seen_dryrun_repo"
[ -f "$seenfile" ] && fail "--dry-run persisted a seen-counter file ($seenfile) — a real run afterward would wrongly skip this line" || ok "--dry-run did not persist a seen-counter (real run afterward will still act on it)"

# now run for real and confirm the dry-run didn't secretly consume the line
run "$tmp/repos/dryrun_repo" >/dev/null 2>&1
[ -f "$OVERNIGHT_DIR/state/PAUSED" ] && ok "real run after a --dry-run trial still processes the pause line" || fail "real run after --dry-run did NOT process the pause line (dry-run leaked state)"
rm -f "$OVERNIGHT_DIR/state/PAUSED"

[ $rc -eq 0 ] && echo "  gitlark_control_consumer: ALL PASS" || echo "  gitlark_control_consumer: FAILURES"
exit $rc
