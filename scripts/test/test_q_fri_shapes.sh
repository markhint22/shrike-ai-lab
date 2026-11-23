#!/usr/bin/env bash
# Regression test: package q-fri-shapes (2026-11-20). PART 1 = test_q_fri_shapes.py (GD_PRELOAD_NO_PAREN shadow rule, TS1 env switches + park opt-in, annotation-insensitive duplicate-def dedupe, ovn_placeholder_report.py;
# every source mutant must be killed, count printed by the python suite). PART 2 = branch_hygiene.sh hyg_placeholder_landed (SHADOW hook: once per repo per UTC day scan guard, per-file 7-day dedupe in the report, DRY_RUN / off honoured, placed before the merge step)
# with mutants of the shell function. Sandboxed (lib_safe_tmp.sh + lib_mac_test_sandbox.sh); needs only git + python3.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"; Q="$(cd "$SC/.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
for f in "$Q/ovn_verify_lint.py" "$Q/dedupe_python_duplicate_defs.py" "$SC/ovn_placeholder_report.py" "$Q/branch_hygiene.sh"; do [ -f "$f" ] || { echo "  SKIP: $f not found"; exit 77; }; done
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: mac test sandbox"; exit 1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TMPDIR="$T"
PY="$(command -v python3.12 || command -v python3)"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# ---- PART 1
PYOUT="$("$PY" "$HERE/test_q_fri_shapes.py" 2>&1)"; PYRC=$?
printf '%s\n' "$PYOUT" | tail -5
ok "python suite (rules + dedupe + placeholder report, 0 mutants survive)" "[ '$PYRC' = 0 ]"
ok "python files compile" "'$PY' -m py_compile '$Q/ovn_verify_lint.py' '$Q/dedupe_python_duplicate_defs.py' '$SC/ovn_placeholder_report.py'"

# ---- PART 2: the hygiene hook (function extracted from the real script, run in a throwaway STATE_DIR against a throwaway repo)
HY="$Q/branch_hygiene.sh"
ok "branch_hygiene.sh parses" "bash -n '$HY'"
mkrepo(){ local r="$T/$1"; mkdir -p "$r/tests"; git -C "$r" init -q -b develop && git -C "$r" config user.email t@t && git -C "$r" config user.name t \
  && printf '"""Placeholder - the implement step fills this in."""\n' > "$r/tests/test_empty.py" && git -C "$r" add -A \
  && GIT_AUTHOR_DATE=2026-10-01T00:00:00Z GIT_COMMITTER_DATE=2026-10-01T00:00:00Z git -C "$r" commit -q -m old && git -C "$r" update-ref refs/remotes/origin/develop HEAD; echo "$r"; }
runhook(){ # <hygiene copy> <repo> <state> [VAR=val ...]
  local hy="$1" repo="$2" st="$3"; shift 3
  ( for kv in "$@"; do export "$kv"; done; SCRIPT_DIR="$Q"; STATE_DIR="$st"; mkdir -p "$st"
    eval "$(sed -n '/^hyg_placeholder_landed() {/,/^}/p' "$hy")"; hyg_placeholder_landed "$(basename "$repo")" "$repo" develop ) >/dev/null 2>&1; }
R="$(mkrepo r1)"; S="$T/s1"
runhook "$HY" "$R" "$S"
ok "hook: first pass logs the file + one alerts.log warn" "[ \"\$(wc -l < '$S/placeholder_landed.log' | tr -d ' ')\" = 1 ] && [ \"\$(grep -c 'warn | placeholder-landed:r1 |' '$S/alerts.log')\" = 1 ]"
ok "hook: day stamp written" "[ -s '$S/placeholder_landed_day/r1' ]"
# a second placeholder lands the same day: the stamp stops a rescan (once per repo per day)
( cd "$R" && printf '# Placeholder - the implement step fills this in.\n' > tests/test_two.gd && git add -A && GIT_AUTHOR_DATE=2026-10-01T00:00:00Z GIT_COMMITTER_DATE=2026-10-01T00:00:00Z git commit -q -m two && git update-ref refs/remotes/origin/develop HEAD )
runhook "$HY" "$R" "$S"
ok "hook: same UTC day does not rescan" "[ \"\$(wc -l < '$S/placeholder_landed.log' | tr -d ' ')\" = 1 ] && [ \"\$(grep -c placeholder-landed '$S/alerts.log')\" = 1 ]"
echo 2000-01-01 > "$S/placeholder_landed_day/r1"
runhook "$HY" "$R" "$S"
ok "hook: stamp cleared -> rescan reports only the file not yet reported today (per-file dedupe)" "[ \"\$(wc -l < '$S/placeholder_landed.log' | tr -d ' ')\" = 2 ] && [ \"\$(grep -c placeholder-landed '$S/alerts.log')\" = 2 ]"
R2="$(mkrepo r2)"; S2="$T/s2"
runhook "$HY" "$R2" "$S2" OVN_PLACEHOLDER_LANDED=off
ok "hook: OVN_PLACEHOLDER_LANDED=off writes nothing" "[ ! -e '$S2/placeholder_landed.log' ] && [ ! -e '$S2/alerts.log' ] && [ ! -e '$S2/placeholder_landed_day' ]"
runhook "$HY" "$R2" "$S2" DRY_RUN=1
ok "hook: DRY_RUN=1 writes nothing" "[ ! -e '$S2/placeholder_landed.log' ] && [ ! -e '$S2/alerts.log' ] && [ ! -e '$S2/placeholder_landed_day' ]"
runhook "$HY" "$T/not-a-repo" "$T/s3"
ok "hook: a missing repo is silent and never fails" "runhook '$HY' '$T/not-a-repo' '$T/s3'"
# wiring
ok "hook is called before the merge step (step 4)" "[ \"\$(grep -n '^  hyg_placeholder_landed ' '$HY' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n '# 4. reconcile' '$HY' | head -1 | cut -d: -f1)\" ]"
ok "hook default is shadow (off honoured)" "grep -q 'OVN_PLACEHOLDER_LANDED:-shadow' '$HY'"
ok "hook only reports (no git write command in the function)" "! sed -n '/^hyg_placeholder_landed() {/,/^}/p' '$HY' | grep -Eq 'git .* (push|commit|reset|merge|checkout|fetch)'"

# mutants of the shell function: each must change a verdict above
gmut(){ local lbl="$1" expr="$2"; local d="$T/gm_$(echo "$lbl" | tr -c 'A-Za-z0-9' _)"; mkdir -p "$d"; sed -E "$expr" "$HY" > "$d/branch_hygiene.sh"
  if cmp -s "$HY" "$d/branch_hygiene.sh"; then F=$((F+1)); echo "  FAIL: mutant '$lbl' did not change the file"; return; fi
  local r="$(mkrepo "m_$(echo "$lbl" | tr -c 'A-Za-z0-9' _)")" s="$d/state" bad=0
  runhook "$d/branch_hygiene.sh" "$r" "$s"
  ( cd "$r" && printf '# Placeholder - the implement step fills this in.\n' > tests/test_two.gd && git add -A && GIT_AUTHOR_DATE=2026-10-01T00:00:00Z GIT_COMMITTER_DATE=2026-10-01T00:00:00Z git commit -q -m two && git update-ref refs/remotes/origin/develop HEAD )
  runhook "$d/branch_hygiene.sh" "$r" "$s"
  [ "$(wc -l < "$s/placeholder_landed.log" 2>/dev/null | tr -d ' ')" = 1 ] || bad=1                 # stamp keeps the second file out
  local r2="$(mkrepo "n_$(echo "$lbl" | tr -c 'A-Za-z0-9' _)")" s2="$d/state2"
  runhook "$d/branch_hygiene.sh" "$r2" "$s2" OVN_PLACEHOLDER_LANDED=off; [ ! -e "$s2/placeholder_landed.log" ] || bad=1
  runhook "$d/branch_hygiene.sh" "$r2" "$s2" DRY_RUN=1; [ ! -e "$s2/placeholder_landed.log" ] || bad=1
  if [ "$bad" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: mutant '$lbl' SURVIVED"; fi; }
gmut "stamp check removed" 's/^  \[ "\$\(cat "\$stamp" 2>\/dev\/null\)" = "\$day" \] && return 0$/  :/'
gmut "off ignored" 's/^  \[ "\$\{OVN_PLACEHOLDER_LANDED:-shadow\}" = "off" \] && return 0$/  :/'
gmut "dry-run ignored" 's/^  if \[ "\$\{DRY_RUN:-0\}" = 1 \]; then return 0; fi$/  :/'
echo "q-fri-shapes: $P passed, $F failed"
[ "$F" = 0 ]
