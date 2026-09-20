#!/usr/bin/env bash
# Regression test for run_overnight.sh's MIGRATION-SAFETY GATE bounded fix-up
# (2026-09-20). Before this, a commit that forked/broke the Alembic migration chain
# reverted with ZERO repair attempts - the one structural gate in run_aider_fix_task
# that hadn't gotten the same bounded-repair treatment as BUILD-GATE (build-red) and
# the Tier-2 fix-up (test-red). Mirrors the deployed decision logic (grounded-summary
# extraction + "still broken after one repair attempt -> revert") so this can't drift
# from what's deployed; exercises it against check_migrations.py's REAL output shapes.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
CM="${OVN_CHECK_MIGRATIONS:-$HOME/overnight-queue/scripts/check_migrations.py}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }
[ -f "$CM" ] || { echo "  SKIP: $CM not found on this host"; exit 0; }

grep -q "MIGRATION-SAFETY fix-up" "$RO" || { echo "  FAIL: migration-safety fix-up not found in $RO"; exit 1; }
SUMMARY_LINE="$(grep -n "_migfix_summary=\"" "$RO" | head -1)"
[ -n "$SUMMARY_LINE" ] || { echo "  FAIL: could not find the grounding-summary extraction in $RO"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed extraction exactly (grep -E '^  ✗|MULTIPLE HEADS')
extract_summary(){ printf '%s' "$1" | grep -E '^  ✗|MULTIPLE HEADS' | tr '\n' ' ' | tr -s ' ' | cut -c1-500; }

# mirrors the deployed decision: fix-up fires only if a summary was extractable, then a
# fresh check_migrations.py run decides revert-or-not (never a second regex pass on stale log text)
run_gate(){ # $1=repo_dir $2=would-a-fixup-fix-it(0|1, simulates aider "fixing" the chain)
  local d="$1" would_fix="$2" out rc summary
  out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && { echo "landed(clean)"; return; }
  summary="$(extract_summary "$out")"
  [ -z "$summary" ] && { echo "reverted(migration-fork)"; return; }  # no groundable text -> no fix-up attempted
  if [ "$would_fix" -eq 1 ]; then
    echo "landed(fixup-repaired)"
  else
    echo "reverted(migration-fork)"
  fi
}

mkvdir(){ mkdir -p "$1/alembic/versions"; }

# ---- 1. duplicate revision id -> groundable summary extracted, repair succeeds -> lands ----
d=$(mktemp -d); mkvdir "$d"
cat > "$d/alembic/versions/001_initial.py" <<'EOF'
revision = "001_initial"
down_revision = None
EOF
cat > "$d/alembic/versions/013_add_plans.py" <<'EOF'
revision = "013"
down_revision = "001_initial"
EOF
cat > "$d/alembic/versions/013_create_plans_table.py" <<'EOF'
revision = "013"
down_revision = "001_initial"
EOF
out="$(python3 "$CM" "$d" 2>&1)"
summary="$(extract_summary "$out")"
ok "duplicate-revision output yields a non-empty grounded summary" '[ -n "$summary" ]'
ok "the summary names the actual colliding revision id" "printf '%s' \"\$summary\" | grep -q \"revision '013'\""
result="$(run_gate "$d" 1)"
ok "duplicate-revision + successful repair -> lands, not reverted" "[ '$result' = 'landed(fixup-repaired)' ]"
result="$(run_gate "$d" 0)"
ok "duplicate-revision + failed repair -> still reverts (safety net intact)" "[ '$result' = 'reverted(migration-fork)' ]"
rm -rf "$d"

# ---- 2. multiple heads -> also groundable ----
d=$(mktemp -d); mkvdir "$d"
cat > "$d/alembic/versions/001_initial.py" <<'EOF'
revision = "001_initial"
down_revision = None
EOF
cat > "$d/alembic/versions/002_main_head.py" <<'EOF'
revision = "002_main_head"
down_revision = "001_initial"
EOF
cat > "$d/alembic/versions/orphan_head.py" <<'EOF'
revision = "orphan_head"
down_revision = None
EOF
out="$(python3 "$CM" "$d" 2>&1)"
summary="$(extract_summary "$out")"
ok "multiple-heads output yields a non-empty grounded summary" '[ -n "$summary" ]'
ok "the summary names MULTIPLE HEADS" "printf '%s' \"\$summary\" | grep -q 'MULTIPLE HEADS'"
rm -rf "$d"

# ---- 3. clean chain -> gate never fires at all (no summary, no fix-up, no revert) ----
d=$(mktemp -d); mkvdir "$d"
cat > "$d/alembic/versions/001_initial.py" <<'EOF'
revision = "001_initial"
down_revision = None
EOF
result="$(run_gate "$d" 0)"
ok "clean chain -> no gate action at all" "[ '$result' = 'landed(clean)' ]"
rm -rf "$d"

echo "migration-gate fix-up: $P passed, $F failed"
[ "$F" -eq 0 ]
