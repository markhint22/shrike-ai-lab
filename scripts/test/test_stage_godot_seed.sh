#!/usr/bin/env bash
# Regression test for the 2026-10-09 godot import seed in ovn_stage_runner.sh.
#
# Real incident: the stage runner's fresh `git worktree add` has no .godot/ import cache (gitignored), so the per-step gate
# (ovn_autotest.sh -> `godot --check-only --script res://<file>`) reported 'Identifier "ScreenBg" not declared' / 'Preload file ... has no resource
# loaders' on files the model never touched (7 false parse errors, 0 after `--import`); the model burned ~300s per attempt on non-errors and all three
# tech_tree/tech_manager T3 runs ended 'escalated to Claude'. The runner now seeds the cache (wt_seed_godot) and runs `godot --headless --path . --import`
# in the worktree right after creating it (kill switch OVN_STAGE_GODOT_SEED=off; missing binary => log + continue).
#
# Default mode: extracts the REAL block from ovn_stage_runner.sh (not a reimplementation) and runs it against a real git worktree with a shim `godot`
# that records its arguments/cwd and what the worktree looked like at call time. Runs anywhere. The battery is also run against mutated copies of the
# block; every mutant must fail it.
# --live (box only; needs ~/godot/godot4 + a repos/xlite clone): same block against a git archive of repos/xlite HEAD copied to a scratch dir; shows the
# SCRIPT ERROR count of `--check-only --script res://scripts/mission/tech_tree.gd` before vs after the seed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SR="${OVN_STAGE_RUNNER:-}"
for c in "$SR" "$HERE/../../ovn_stage_runner.sh" "$HOME/overnight-queue/ovn_stage_runner.sh"; do [ -n "$c" ] && [ -f "$c" ] && { SR="$c"; break; }; done
[ -f "$SR" ] || { echo "  SKIP: ovn_stage_runner.sh not found"; exit 0; }
LIBWT="$(cd "$(dirname "$SR")" && pwd)/scripts/lib_worktree.sh"
[ -f "$LIBWT" ] || { echo "  FAIL: $LIBWT not found"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

BLOCK="$(awk 'index($0,"# 2026-10-09 (xlite godot lane): same class of bug as node_modules above"){on=1} on{print} index($0,"# end godot import seed"){exit}' "$SR")"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the godot seed block from $SR"; exit 1; }
case "$BLOCK" in *'wt_seed_godot'*'--import'*) : ;; *) echo "  FAIL: extracted block does not look like the seed block"; exit 1 ;; esac

T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GODOT_LOG="$T/godot.log"

# queue-dir stand-in: the block sources scripts/lib_worktree.sh and writes logs/ relative to the cwd (the runner cd's to ~/overnight-queue)
Q="$T/queue"; mkdir -p "$Q/scripts" "$Q/logs"; cp "$LIBWT" "$Q/scripts/lib_worktree.sh"
SAYLOG="$T/say.log"

mk_home(){ # $1 = with|without godot
  rm -rf "$T/home"; mkdir -p "$T/home/godot"
  [ "$1" = with ] || return 0
  cat > "$T/home/godot/godot4" <<'EOF'
#!/usr/bin/env bash
# records: mode, cwd, whether the import cache + a *.import file were ALREADY in the worktree at call time
mode=check; for a in "$@"; do [ "$a" = --import ] && mode=import; done
seeded=no; [ -f .godot/global_script_class_cache.cfg ] && [ -f assets/a.png.import ] && seeded=yes
echo "$mode cwd=$(pwd) seeded=$seeded args=$*" >> "$GODOT_LOG"
if [ "$mode" = import ]; then mkdir -p .godot; echo cfg > .godot/global_script_class_cache.cfg; exit 0; fi
[ -f .godot/global_script_class_cache.cfg ] || echo 'SCRIPT ERROR: Parse Error: Identifier "ScreenBg" not declared in the current scope.'
exit 0
EOF
  chmod +x "$T/home/godot/godot4"
}

# a real repo with an origin/overnight/feature ref, a godot project at the root (and a second one in a subdir), the import cache present but gitignored
mk_repo(){
  rm -rf "$T/rd" "$T/origin.git" "$T/wt"
  git init -q --bare "$T/origin.git"
  git clone -q "$T/origin.git" "$T/rd" 2>/dev/null
  ( cd "$T/rd"; git config user.email t@t; git config user.name t
    printf '.godot/\n*.import\n' > .gitignore
    echo 'config_version=5' > project.godot
    mkdir -p scripts assets; echo 'extends Node' > scripts/a.gd; echo png > assets/a.png
    git add -A; git commit -q -m init; git branch -M overnight/feature; git push -q origin overnight/feature
    mkdir -p .godot; echo cfg > .godot/global_script_class_cache.cfg; echo imp > assets/a.png.import )
  git -C "$T/origin.git" symbolic-ref HEAD refs/heads/overnight/feature
  git -C "$T/rd" fetch -q origin overnight/feature 2>/dev/null
  git -C "$T/rd" worktree add -q "$T/wt" origin/overnight/feature
}

run_block(){ # $1 = block text; rest = env assignments; sets RC
  local blk="$1"; shift
  : > "$GODOT_LOG"; : > "$SAYLOG"
  ( cd "$Q" && env HOME="$T/home" "$@" bash -c '
      set -uo pipefail
      repo=xlite; rd="'"$T"'/rd"; wt="'"$T"'/wt"
      say(){ echo "$*" >> "'"$SAYLOG"'"; }
      '"$blk"'
    ' ) > "$T/block.out" 2>&1
  RC=$?
}
calls(){ wc -l < "$GODOT_LOG" | tr -d ' '; }

battery(){ # $1 = block text (real or mutant); returns the number of failed assertions
  local blk="$1" BF=0
  chk(){ [ "$2" = 1 ] || { BF=$((BF+1)); [ -n "${BATTERY_VERBOSE:-}" ] && echo "  FAIL: $1"; }; return 0; }

  mk_home with; mk_repo
  run_block "$blk"
  first="$(head -1 "$GODOT_LOG" 2>/dev/null)"
  chk "1 the block exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
  chk "2 exactly one godot call (the --import); no --check-only before/instead" "$([ "$(calls)" = 1 ] && [ "$(grep -c '^check ' "$GODOT_LOG")" = 0 ] && echo 1 || echo 0)"
  chk "3 the call is --headless --path . --import" "$([[ $first == import*'args=--headless --path . --import' ]] && echo 1 || echo 0)"
  chk "4 it ran in the NEW worktree, not the live clone" "$([[ $first == "import cwd=$T/wt "* ]] && echo 1 || echo 0)"
  chk "5 wt_seed_godot ran BEFORE the import (cache + *.import already in the worktree at call time)" "$([[ $first == *'seeded=yes'* ]] && echo 1 || echo 0)"
  chk "6 *.import files were COPIED not symlinked" "$([ -f "$T/wt/assets/a.png.import" ] && [ ! -L "$T/wt/assets/a.png.import" ] && [ ! -L "$T/wt/.godot" ] && echo 1 || echo 0)"
  chk "7 a say line records the seed" "$([ "$(grep -c 'godot seed: seeded' "$SAYLOG")" = 1 ] && echo 1 || echo 0)"
  # after the seed, the per-step gate sees no false error on an unedited file
  out="$(cd "$T/wt" && HOME="$T/home" "$T/home/godot/godot4" --headless --path . --check-only --script res://scripts/a.gd 2>&1)"
  chk "8 a following --check-only reports 0 SCRIPT ERROR" "$([[ $out == *'SCRIPT ERROR'* ]] && echo 0 || echo 1)"
  # control: an UNSEEDED worktree gives the false error (the shim models the real symptom)
  rm -rf "$T/wt2"; git -C "$T/rd" worktree add -q "$T/wt2" origin/overnight/feature
  out="$(cd "$T/wt2" && HOME="$T/home" "$T/home/godot/godot4" --headless --path . --check-only --script res://scripts/a.gd 2>&1)"
  chk "9 control: without the seed the same check-only reports the false ScreenBg error" "$([[ $out == *ScreenBg* ]] && echo 1 || echo 0)"
  git -C "$T/rd" worktree remove --force "$T/wt2" 2>/dev/null

  # kill switch
  git -C "$T/rd" worktree remove --force "$T/wt" 2>/dev/null; mk_repo
  run_block "$blk" OVN_STAGE_GODOT_SEED=off
  chk "11 OVN_STAGE_GODOT_SEED=off: no godot call" "$([ "$(calls)" = 0 ] && echo 1 || echo 0)"
  chk "12 OVN_STAGE_GODOT_SEED=off: no cache copied into the worktree" "$([ ! -e "$T/wt/.godot" ] && [ ! -e "$T/wt/assets/a.png.import" ] && echo 1 || echo 0)"
  chk "13 OVN_STAGE_GODOT_SEED=off: block still exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"

  # missing binary: log and continue
  git -C "$T/rd" worktree remove --force "$T/wt" 2>/dev/null; mk_repo; mk_home without
  run_block "$blk"
  chk "14 missing godot binary: block exits 0 (continues)" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
  chk "15 missing godot binary: a log line says it was skipped" "$([ "$(grep -c 'godot seed: .* not found - skipping' "$SAYLOG")" = 1 ] && echo 1 || echo 0)"
  chk "16 missing godot binary: nothing seeded" "$([ ! -e "$T/wt/.godot" ] && echo 1 || echo 0)"

  # non-godot repo: the block is a silent no-op
  git -C "$T/rd" worktree remove --force "$T/wt" 2>/dev/null; mk_repo; mk_home with
  rm -f "$T/wt/project.godot"
  run_block "$blk"
  chk "17 repo without project.godot: no godot call, no say line" "$([ "$(calls)" = 0 ] && [ ! -s "$SAYLOG" ] && echo 1 || echo 0)"

  # project in a subdir only: seeded + imported there
  git -C "$T/rd" worktree remove --force "$T/wt" 2>/dev/null; rm -rf "$T/rd" "$T/origin.git" "$T/wt"
  git init -q --bare "$T/origin.git"; git clone -q "$T/origin.git" "$T/rd" 2>/dev/null
  ( cd "$T/rd"; git config user.email t@t; git config user.name t
    printf '.godot/\n*.import\n' > .gitignore; mkdir -p game/assets; echo 'config_version=5' > game/project.godot; echo png > game/assets/a.png
    git add -A; git commit -q -m init; git branch -M overnight/feature; git push -q origin overnight/feature
    mkdir -p game/.godot; echo cfg > game/.godot/global_script_class_cache.cfg; echo imp > game/assets/a.png.import )
  git -C "$T/origin.git" symbolic-ref HEAD refs/heads/overnight/feature
  git -C "$T/rd" fetch -q origin overnight/feature 2>/dev/null; git -C "$T/rd" worktree add -q "$T/wt" origin/overnight/feature
  run_block "$blk"
  chk "18 project in a subdir: import runs in <wt>/game" "$([ "$(grep -c "^import cwd=$T/wt/game " "$GODOT_LOG")" = 1 ] && [ -f "$T/wt/game/.godot/global_script_class_cache.cfg" ] && echo 1 || echo 0)"
  git -C "$T/rd" worktree remove --force "$T/wt" 2>/dev/null
  return "$BF"
}

live(){
  GB="$HOME/godot/godot4"; XL="${OVN_LIVE_XLITE:-$HOME/overnight-queue/repos/xlite}"
  [ -x "$GB" ] && [ -d "$XL/.git" ] || { echo "  SKIP --live: need $GB and $XL"; return 0; }
  S="$(mktemp -d "$HOME/scratch-stageseed-XXXXXX")"
  echo "  live: scratch=$S"
  mkdir -p "$S/src" "$S/rd"
  git -C "$XL" archive HEAD | tar -x -C "$S/rd"
  ( cd "$S/rd" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -q -m snap && git branch -M overnight/feature \
      && git init -q --bare "$S/origin.git" && git remote add origin "$S/origin.git" && git push -q origin overnight/feature && git fetch -q origin overnight/feature )
  # the "live clone" import cache: import once in the scratch clone itself (this is what the live clone has)
  ( cd "$S/rd" && timeout 600 "$GB" --headless --path . --import >/dev/null 2>&1 )
  # worktree WITHOUT seed = the old behaviour
  git -C "$S/rd" worktree add -q "$S/wt_old" origin/overnight/feature
  before="$(cd "$S/wt_old" && timeout 120 "$GB" --headless --path . --check-only --script res://scripts/mission/tech_tree.gd 2>&1 | grep -c 'SCRIPT ERROR')"
  # worktree WITH the real block
  git -C "$S/rd" worktree add -q "$S/wt" origin/overnight/feature
  ( cd "$Q" && HOME="$HOME" bash -c 'set -uo pipefail; repo=xlite; rd="'"$S"'/rd"; wt="'"$S"'/wt"; say(){ echo "live-say: $*"; }; '"$BLOCK" )
  # `--check-only --script` never loads the [autoload] singletons, so a script that names one (tech_tree.gd -> TechManager) keeps ONE
  # 'Compile Error: Identifier not found: <Autoload>' no cache can fix; that is an engine limitation, not an import-cache symptom (the per-step gate's
  # baseline-relative check ignores it because the pre-edit blob reports it too). Count it separately.
  allout="$(cd "$S/wt" && timeout 120 "$GB" --headless --path . --check-only --script res://scripts/mission/tech_tree.gd 2>&1 | grep -a 'SCRIPT ERROR')"
  after="$(printf '%s\n' "$allout" | grep -ac 'SCRIPT ERROR')"
  autoload_names="$(sed -n '/^\[autoload\]/,/^\[/p' "$S/wt/project.godot" | grep -aoE '^[A-Za-z0-9_]+=' | tr -d '=' | paste -sd'|' -)"
  residual="$(printf '%s\n' "$allout" | grep -a 'SCRIPT ERROR' | grep -avE "Identifier not found: (${autoload_names:-NONE})" | grep -ac 'SCRIPT ERROR')"
  echo "  live: tech_tree.gd check-only SCRIPT ERROR count: before seed=$before after seed=$after (of which NOT an autoload-singleton limitation: $residual)"
  ok "live: 0 import-cache SCRIPT ERROR after the seed (only autoload-singleton 'Identifier not found' may remain)" "$([ "$residual" = 0 ] && echo 1 || echo 0)"
  ok "live: the seed removed errors (after < before)" "$([ "$after" -lt "$before" ] && echo 1 || echo 0)"
  ok "live: the unseeded worktree showed the false errors (before > 0)" "$([ "$before" -gt 0 ] && echo 1 || echo 0)"
  rm -rf "$S"
}

if [ "${1:-}" = "--live" ]; then
  live
  echo "Stage godot seed (live): $P passed, $F failed"
  [ "$F" -eq 0 ]; exit $?
fi

BATTERY_VERBOSE=1 battery "$BLOCK"; brc=$?
ok "real block passes the whole battery ($brc failed assertion(s))" "$([ "$brc" = 0 ] && echo 1 || echo 0)"

mutate(){ # <name> <old> <new>
  local name="$1" old="$2" new="$3" mb
  mb="$(OLD="$old" NEW="$new" BLK="$BLOCK" python3 - <<'PY'
import os, sys
b, o, n = os.environ["BLK"], os.environ["OLD"], os.environ["NEW"]
if b.count(o) != 1:
    sys.exit(3)
sys.stdout.write(b.replace(o, n))
PY
)" || { F=$((F+1)); echo "  FAIL: mutation '$name' could not be applied (block drifted)"; return; }
  battery "$mb"; local mrc=$?
  if [ "$mrc" -gt 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: mutant '$name' survived (battery stayed green)"; fi
}
mutate no-seed-copy   'wt_seed_godot "$rd" "$wt" "$_gsub"' ':'
mutate no-import      '--headless --path . --import' '--headless --path . --version'
mutate no-killswitch  '[ "${OVN_STAGE_GODOT_SEED:-on}" != off ]' ':'
mutate no-bin-guard   'if [ ! -x "$_gbin" ]; then' 'if false; then'
mutate wrong-dir      '( cd "$_gpd" &&' '( cd "$rd" &&'

echo "Stage godot seed: $P passed, $F failed"
[ "$F" -eq 0 ]
