#!/usr/bin/env bash
# Regression test for the 2026-10-09 xlite godot-lane changes in scripts/ovn_autotest.sh (the aider --test-cmd gate):
#   (a) a project with no .godot/global_script_class_cache.cfg gets `godot --import` BEFORE the first --check-only (a fresh worktree has no import
#       cache; --check-only then reported 'Identifier "ScreenBg" not declared' on files the model never touched - 7 false errors on tech_tree.gd).
#   (b) baseline-relative check-only: an error fails the step only when it is NOT also reported on the pre-edit blob; line numbers do not matter.
#   (c) the pre-edit result is cached by sha1(path+blob) in state/godot_checkonly_cache (second call = cache hit, no second baseline run).
#   (d) gdlint advisories are hidden whenever a hard error is present.
# A shim `godot` (HOME/godot/godot4) records every call and decides its output from the file content and the presence of the import cache, so the
# whole test runs anywhere (no real Godot). The assertions are one battery that is ALSO run against mutated copies of the gate: every mutant must
# make the battery fail (proves the assertions bite). Assertions are evaluated with pipefail off and never use `x | grep -q`.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AT_REAL=""
for c in "$HERE/../ovn_autotest.sh" "$HERE/../../scripts/ovn_autotest.sh" "$HERE/ovn_autotest.sh"; do [ -f "$c" ] && { AT_REAL="$c"; break; }; done
[ -n "$AT_REAL" ] || { echo "  SKIP: ovn_autotest.sh not found"; exit 0; }
P=0; F=0
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT

H="$T/home"; mkdir -p "$H/aider-venv/bin" "$H/godot" "$T/qdir/state"
export GODOT_LOG="$T/godot.log"
cat > "$H/godot/godot4" <<'EOF'
#!/usr/bin/env bash
mode=""; f=""
while [ $# -gt 0 ]; do case "$1" in --import) mode=import;; --check-only) mode=check;; --script) shift; f="${1#res://}";; esac; shift; done
if [ "$mode" = import ]; then
  echo "IMPORT cwd=$(pwd)" >> "$GODOT_LOG"
  mkdir -p .godot; echo cfg > .godot/global_script_class_cache.cfg; exit 0
fi
echo "CHECK $f $(git hash-object "$f" 2>/dev/null)" >> "$GODOT_LOG"
# GODOT_PROBE = the LIVE file under test: log its content hash at the moment of every engine call (the live file must never hold the pre-edit blob)
[ -n "${GODOT_PROBE:-}" ] && echo "PROBE $(git hash-object "$GODOT_PROBE" 2>/dev/null) cwd=$(pwd)" >> "$GODOT_LOG"
# GODOT_SLOW_HASH = hash of the pre-edit blob: a run on that content (the baseline run, wherever it happens) takes GODOT_SLOW seconds
if [ -n "${GODOT_SLOW_HASH:-}" ] && [ "$(git hash-object "$f" 2>/dev/null)" = "$GODOT_SLOW_HASH" ]; then sleep "${GODOT_SLOW:-3}"; echo "SLOW_END $f" >> "$GODOT_LOG"; fi
if [ ! -f .godot/global_script_class_cache.cfg ]; then echo 'SCRIPT ERROR: Parse Error: Identifier "ScreenBg" not declared in the current scope.'; fi
# one message per PREBAD line (a second use of the same undeclared identifier gives a second identical message with another line number)
grep -n PREBAD "$f" 2>/dev/null | cut -d: -f1 | while read -r ln; do echo "SCRIPT ERROR: Parse Error: pre-existing problem (res://$f:$ln)"; done
ln="$(grep -n NEWBAD "$f" 2>/dev/null | head -1 | cut -d: -f1)"
[ -n "$ln" ] && echo "SCRIPT ERROR: Parse Error: freshly introduced problem (res://$f:$ln)"
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$H/aider-venv/bin/gdparse"
printf '#!/usr/bin/env bash\necho "x.gd:3: Warning: max-line-length"\nexit 0\n' > "$H/aider-venv/bin/gdlint"
chmod +x "$H/godot/godot4" "$H/aider-venv/bin/"*

# project repo with one tracked .gd (clean) and one tracked .gd that ALREADY has an engine error (PREBAD)
mkrepo(){ # $1 name; leaves R set. Import cache present unless $2 = nocache
  R="$T/$1"; rm -rf "$R"; mkdir -p "$R/scripts"
  ( cd "$R" && git init -q && git config user.email t@t && git config user.name t
    echo 'config_version=5' > project.godot
    printf 'extends Node\nfunc a():\n\tpass\n' > scripts/clean.gd
    printf 'extends Node\nvar PREBAD = 1\nfunc a():\n\tpass\n' > scripts/prebad.gd
    echo ".godot/" > .gitignore
    git add -A && git commit -q -m base )
  [ "${2:-}" = nocache ] || { mkdir -p "$R/.godot"; echo cfg > "$R/.godot/global_script_class_cache.cfg"; }
  : > "$GODOT_LOG"
}
run_at(){ # $1 = autotest script; rest = env assignments
  local at="$1"; shift
  OUT="$(cd "$T" && HOME="$H" OVN_DIR="$T/qdir" OVN_GODOT_CACHE_DIR="$T/qdir/state/godot_checkonly_cache" env "$@" bash "$at" "$R" 2>&1)"; RC=$?
}
checks(){ grep -c '^CHECK ' "$GODOT_LOG" 2>/dev/null || true; }
imports(){ grep -c '^IMPORT ' "$GODOT_LOG" 2>/dev/null || true; }
has(){ case "$OUT" in *"$1"*) return 0;; *) return 1;; esac; }

# the whole battery, parameterised on the script under test. Every failed assertion bumps BF.
battery(){
  local AT="$1" BF=0
  chk(){ if [ "$2" = 1 ]; then :; else BF=$((BF+1)); [ -n "${BATTERY_VERBOSE:-}" ] && echo "  FAIL: $1"; fi; }
  rm -rf "$T/qdir/state/godot_checkonly_cache"

  # (a) import-before-check when the cache is missing
  mkrepo imp nocache; echo 'extends Node' > "$R/scripts/new1.gd"
  run_at "$AT"
  first="$(head -1 "$GODOT_LOG")"
  chk "a1 import ran first when the class cache is missing" "$([[ $first == 'IMPORT cwd='* ]] && echo 1 || echo 0)"
  chk "a2 import ran in the project dir ($R)" "$([ "$(grep -c "^IMPORT cwd=$R\$" "$GODOT_LOG")" = 1 ] && echo 1 || echo 0)"
  chk "a3 the unedited-looking new file passes after the import (no false ScreenBg error): rc=0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
  chk "a4 exactly one import for one changed file" "$([ "$(imports)" = 1 ] && echo 1 || echo 0)"
  mkrepo imp2; echo 'extends Node' > "$R/scripts/new1.gd"
  run_at "$AT"
  chk "a5 no import when the class cache already exists" "$([ "$(imports)" = 0 ] && [ "$(checks)" -ge 1 ] && echo 1 || echo 0)"
  mkrepo imp3 nocache; echo 'extends Node' > "$R/scripts/new1.gd"
  run_at "$AT" OVN_AUTOTEST_GODOT_IMPORT=off
  chk "a6 OVN_AUTOTEST_GODOT_IMPORT=off skips the import (and the false error then fails the step, as before)" "$([ "$(imports)" = 0 ] && [ "$RC" = 1 ] && has 'ScreenBg' && echo 1 || echo 0)"

  # (b) baseline-relative
  mkrepo base; printf 'extends Node\nvar PREBAD = 1\nfunc a():\n\tpass\nfunc b():\n\tpass\n' > "$R/scripts/prebad.gd"
  run_at "$AT"
  chk "b1 edit leaves only the PRE-EXISTING error (line moved) -> exit 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
  chk "b2 the pre-existing error is not shown to the model" "$(has 'pre-existing problem' && echo 0 || echo 1)"
  printf 'extends Node\nvar PREBAD = 1\nvar NEWBAD = 2\nfunc a():\n\tpass\n' > "$R/scripts/prebad.gd"
  run_at "$AT"
  chk "b3 an error absent on the pre-edit blob fails the step (rc=1, [API] report)" "$([ "$RC" = 1 ] && has '[API] scripts/prebad.gd' && has 'freshly introduced problem' && echo 1 || echo 0)"
  chk "b4 ...and the pre-existing one is still filtered out of that report" "$(has 'pre-existing problem' && echo 0 || echo 1)"
  mkrepo base2; echo 'extends Node' > "$R/scripts/brandnew.gd"; echo 'var NEWBAD = 1' >> "$R/scripts/brandnew.gd"
  run_at "$AT"
  chk "b5 a brand-new file has no baseline: its error fails" "$([ "$RC" = 1 ] && has 'freshly introduced problem' && echo 1 || echo 0)"
  mkrepo base3; echo '# touched' >> "$R/scripts/prebad.gd"
  run_at "$AT" OVN_GODOT_BASELINE=off
  chk "b6 OVN_GODOT_BASELINE=off restores the absolute behaviour (pre-existing error fails)" "$([ "$RC" = 1 ] && has 'pre-existing problem' && echo 1 || echo 0)"
  mkrepo base4; echo 'var NEWBAD = 1' >> "$R/scripts/clean.gd"
  git -C "$R" add -A; git -C "$R" commit -q -m "edit clean"; base_sha="$(git -C "$R" rev-parse HEAD~1)"
  run_at "$AT" OVN_BASE_SHA="$base_sha"
  chk "b7 OVN_BASE_SHA: an edit already COMMITTED since the base is still seen and fails" "$([ "$RC" = 1 ] && has 'freshly introduced problem' && echo 1 || echo 0)"

  # (c) cache by sha1(path+blob)
  rm -rf "$T/qdir/state/godot_checkonly_cache"   # b1 already cached this very blob (same path+content in the earlier repo)
  mkrepo cache; echo '# touched' >> "$R/scripts/prebad.gd"; before="$(cat "$R/scripts/prebad.gd")"
  run_at "$AT"
  blob="$(git -C "$R" rev-parse HEAD:scripts/prebad.gd)"
  n1="$(grep -c "^CHECK scripts/prebad.gd $blob\$" "$GODOT_LOG")"
  chk "c1 first call ran the baseline command on the pre-edit blob exactly once" "$([ "$n1" = 1 ] && echo 1 || echo 0)"
  chk "c2 the live file is byte-identical after the baseline swap" "$([ "$(cat "$R/scripts/prebad.gd")" = "$before" ] && echo 1 || echo 0)"
  chk "c3 a cache entry exists" "$([ "$(ls "$T/qdir/state/godot_checkonly_cache" 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
  : > "$GODOT_LOG"; run_at "$AT"
  n2="$(grep -c "^CHECK scripts/prebad.gd $blob\$" "$GODOT_LOG")"
  chk "c4 second call is a cache hit (no baseline run), result unchanged rc=0" "$([ "$n2" = 0 ] && [ "$RC" = 0 ] && echo 1 || echo 0)"
  # a different blob must NOT reuse the entry
  mkrepo cache2; printf 'extends Node\nvar PREBAD = 1\nvar x\n' > "$R/scripts/prebad.gd"; git -C "$R" add -A; git -C "$R" commit -q -m v2; echo '# t' >> "$R/scripts/prebad.gd"
  blob2="$(git -C "$R" rev-parse HEAD:scripts/prebad.gd)"; : > "$GODOT_LOG"; run_at "$AT"
  chk "c5 a different pre-edit blob gets its own baseline run" "$([ "$(grep -c "^CHECK scripts/prebad.gd $blob2\$" "$GODOT_LOG")" = 1 ] && echo 1 || echo 0)"

  # (d) advisories vs hard errors
  mkrepo adv; echo 'var NEWBAD = 1' >> "$R/scripts/clean.gd"
  run_at "$AT"
  chk "d1 hard error present: gdlint advisory (max-line-length) is NOT shown" "$(has 'lint-advisory' && echo 0 || echo 1)"
  chk "d2 hard error still reported" "$([ "$RC" = 1 ] && has '[API]' && echo 1 || echo 0)"
  mkrepo adv2; echo '# fine' >> "$R/scripts/clean.gd"
  run_at "$AT"
  chk "d3 no hard error: advisory still shown, rc=0" "$([ "$RC" = 0 ] && has '[lint-advisory] scripts/clean.gd' && echo 1 || echo 0)"
  # (f) occurrence COUNTS, not membership (reviewer round 2: a second use of an already-undeclared identifier has the same normalised message as the
  #     baseline one and was invisible)
  rm -rf "$T/qdir/state/godot_checkonly_cache"
  mkrepo dup; printf 'extends Node\nvar PREBAD = 1\nfunc a():\n\tpass\n' > "$R/scripts/prebad.gd"; git -C "$R" add -A; git -C "$R" commit -q -m one >/dev/null 2>&1
  printf 'extends Node\nvar PREBAD = 1\nfunc a():\n\tpass\nfunc zz_dup():\n\tvar PREBAD_again = 2\n' > "$R/scripts/prebad.gd"
  run_at "$AT"
  chk "f1 the SAME message once more than the pre-edit blob had it fails the step (rc=1, [API])" "$([ "$RC" = 1 ] && has '[API] scripts/prebad.gd' && echo 1 || echo 0)"
  chk "f2 ...and the report carries exactly the one extra occurrence, not the old one too" "$([ "$(grep -c 'pre-existing problem' <<< "$OUT")" = 1 ] && echo 1 || echo 0)"
  rm -rf "$T/qdir/state/godot_checkonly_cache"
  mkrepo dup2; printf 'extends Node\nvar PREBAD = 1\nvar PREBAD_b = 2\nfunc a():\n\tpass\n' > "$R/scripts/prebad.gd"; git -C "$R" add -A; git -C "$R" commit -q -m two >/dev/null 2>&1
  printf '# moved down\nextends Node\n\nvar PREBAD = 1\nvar PREBAD_b = 2\nfunc a():\n\tpass\n' > "$R/scripts/prebad.gd"
  run_at "$AT"
  chk "f3 baseline had the message twice, the edit still has it twice (lines moved): rc=0, nothing shown" "$([ "$RC" = 0 ] && has 'pre-existing problem' && echo 0 || echo 1)"
  printf 'extends Node\nvar PREBAD = 1\nvar PREBAD_b = 2\nvar PREBAD_c = 3\nfunc a():\n\tpass\n' > "$R/scripts/prebad.gd"
  run_at "$AT"
  chk "f4 baseline twice, edit three times: the step fails and shows exactly one" "$([ "$RC" = 1 ] && [ "$(grep -c 'pre-existing problem' <<< "$OUT")" = 1 ] && echo 1 || echo 0)"

  # (g) cache key covers sibling and import-cache state; atomic write; stale entries pruned
  rm -rf "$T/qdir/state/godot_checkonly_cache"
  mkrepo gsib; echo '# touched' >> "$R/scripts/prebad.gd"; gblob="$(git -C "$R" rev-parse HEAD:scripts/prebad.gd)"
  run_at "$AT"; : > "$GODOT_LOG"; run_at "$AT"
  chk "g1 unchanged siblings: the second call is a cache hit (0 baseline runs)" "$([ "$(grep -c "^CHECK scripts/prebad.gd $gblob\$" "$GODOT_LOG")" = 0 ] && echo 1 || echo 0)"
  echo '# a sibling changed' >> "$R/scripts/clean.gd"; : > "$GODOT_LOG"; run_at "$AT"
  chk "g2 a SIBLING .gd changed since the entry was written: the baseline is recomputed (1 run), not reused" "$([ "$(grep -c "^CHECK scripts/prebad.gd $gblob\$" "$GODOT_LOG")" = 1 ] && echo 1 || echo 0)"
  rm -rf "$T/qdir/state/godot_checkonly_cache"
  mkrepo gcc nocache; echo '# touched' >> "$R/scripts/prebad.gd"; gblob="$(git -C "$R" rev-parse HEAD:scripts/prebad.gd)"
  run_at "$AT" OVN_AUTOTEST_GODOT_IMPORT=off      # no class cache at all: baseline cached under the 'nocache' key
  mkdir -p "$R/.godot"; echo cfg > "$R/.godot/global_script_class_cache.cfg"; : > "$GODOT_LOG"; run_at "$AT"
  chk "g3 the import cache appeared since the entry was written: baseline recomputed" "$([ "$(grep -c "^CHECK scripts/prebad.gd $gblob\$" "$GODOT_LOG")" = 1 ] && echo 1 || echo 0)"
  echo cfg2 > "$R/.godot/global_script_class_cache.cfg"; : > "$GODOT_LOG"; run_at "$AT"
  chk "g4 the import cache content changed (class_names moved): baseline recomputed" "$([ "$(grep -c "^CHECK scripts/prebad.gd $gblob\$" "$GODOT_LOG")" = 1 ] && echo 1 || echo 0)"
  : > "$GODOT_LOG"; run_at "$AT"
  chk "g5 nothing changed: cache hit again" "$([ "$(grep -c "^CHECK scripts/prebad.gd $gblob\$" "$GODOT_LOG")" = 0 ] && echo 1 || echo 0)"
  # atomic write: the entry arrives by mv from a temp file in the same dir (a shim mv records its calls); no temp file is left behind
  rm -rf "$T/qdir/state/godot_checkonly_cache"; mkdir -p "$T/shimbin"; : > "$T/mv.log"
  printf '#!/usr/bin/env bash\necho "MV $*" >> "%s"\nexec /bin/mv "$@"\n' "$T/mv.log" > "$T/shimbin/mv"; chmod +x "$T/shimbin/mv"
  mkrepo gatom; echo '# touched' >> "$R/scripts/prebad.gd"
  run_at "$AT" PATH="$T/shimbin:$PATH"
  chk "g6 the cache entry is moved into place from a temp file (atomic), not written in place" "$([ "$(grep -c "^MV .*\.tmp\..* $T/qdir/state/godot_checkonly_cache/[0-9a-f]\{40\}\$" "$T/mv.log")" = 1 ] && echo 1 || echo 0)"
  chk "g7 exactly one entry, no temp file left behind" "$([ "$(ls -A "$T/qdir/state/godot_checkonly_cache" | wc -l | tr -d ' ')" = 1 ] && [ "$(ls -A "$T/qdir/state/godot_checkonly_cache" | grep -c tmp)" = 0 ] && echo 1 || echo 0)"
  # entries older than a day are dropped when a new one is written
  touch -t 200001010000 "$T/qdir/state/godot_checkonly_cache/stale_entry"
  mkrepo gold; printf 'extends Node\nvar PREBAD = 1\nvar q\n' > "$R/scripts/prebad.gd"; git -C "$R" add -A; git -C "$R" commit -q -m q >/dev/null 2>&1; echo '# touched' >> "$R/scripts/prebad.gd"
  run_at "$AT"
  chk "g8 a day-old cache entry is pruned on the next write, the fresh entries stay" "$([ ! -e "$T/qdir/state/godot_checkonly_cache/stale_entry" ] && [ "$(ls -A "$T/qdir/state/godot_checkonly_cache" | wc -l | tr -d ' ')" = 2 ] && echo 1 || echo 0)"
  # (h) bash 3.2 portability of THIS file and of test_stage_godot_seed.sh: no case-with-')' inside a command substitution in double quotes (parse error on 3.2)
  chk "h1 no case-in-command-substitution construct in the two godot test files (bash 3.2 cannot parse them)" "$([ "$(cat "$HERE/test_autotest_godot_baseline.sh" "$HERE/test_stage_godot_seed.sh" 2>/dev/null | grep -c '[$](case')" = 0 ] && echo 1 || echo 0)"

  # (e) the live file is NEVER written by the baseline run (reviewer finding: the in-place swap lived in a command-substitution subshell whose
  #     trap does not see a TERM sent to the parent, so a test-cmd timeout left the pre-edit blob in the file, or resurrected a reverted edit later)
  rm -rf "$T/qdir/state/godot_checkonly_cache"   # an earlier case cached this very blob
  mkrepo live; echo '# edited' >> "$R/scripts/prebad.gd"
  edited="$(git hash-object "$R/scripts/prebad.gd")"; pre="$(git -C "$R" rev-parse HEAD:scripts/prebad.gd)"
  run_at "$AT" GODOT_PROBE="$R/scripts/prebad.gd"
  probes="$(grep -c '^PROBE ' "$GODOT_LOG")"; bad_probes="$(grep '^PROBE ' "$GODOT_LOG" | grep -vc "^PROBE $edited ")"
  chk "e1 the engine was called on the edited file AND on the pre-edit blob (2 probes)" "$([ "$probes" -ge 2 ] && echo 1 || echo 0)"
  chk "e2 at every engine call (baseline run included) the live file held the EDITED content, never the pre-edit blob" "$([ "$bad_probes" = 0 ] && echo 1 || echo 0)"
  chk "e3 the baseline engine run did not happen in the live project dir" "$([ "$(grep -c "^CHECK scripts/prebad.gd $pre\$" "$GODOT_LOG")" = 1 ] && [ "$(grep -c "^PROBE .* cwd=$R\$" "$GODOT_LOG")" -lt "$probes" ] && echo 1 || echo 0)"
  chk "e4 no overlay dir is left behind" "$([ "$(ls -d "${TMPDIR:-/tmp}"/ovn_gdbase.* 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && echo 1 || echo 0)"
  # TERM the gate while the (slow) baseline run is in flight: the live file must be intact right away and must stay intact after the run would have ended
  rm -rf "$T/qdir/state/godot_checkonly_cache"
  mkrepo term; echo '# edited again' >> "$R/scripts/prebad.gd"
  edited="$(git hash-object "$R/scripts/prebad.gd")"; pre="$(git -C "$R" rev-parse HEAD:scripts/prebad.gd)"
  ( cd "$T" && exec env HOME="$H" OVN_DIR="$T/qdir" OVN_GODOT_CACHE_DIR="$T/qdir/state/godot_checkonly_cache" GODOT_SLOW_HASH="$pre" GODOT_SLOW=3 bash "$AT" "$R" >/dev/null 2>&1 ) &
  gpid=$!; disown "$gpid" 2>/dev/null || true   # no 'Terminated' job notice on stderr
  i=0; while [ "$i" -lt 300 ] && [ "$(grep -c "^CHECK scripts/prebad.gd $pre\$" "$GODOT_LOG" 2>/dev/null)" = 0 ]; do sleep 0.1; i=$((i+1)); done
  kill -TERM "$gpid" 2>/dev/null
  during="$(git hash-object "$R/scripts/prebad.gd")"
  # handshake, not a wall-clock guess: the slow baseline engine run logs SLOW_END when it has finished (it outlives the TERMed gate); only then look again
  i=0; while [ "$i" -lt 300 ] && [ "$(grep -c '^SLOW_END ' "$GODOT_LOG" 2>/dev/null)" = 0 ]; do sleep 0.1; i=$((i+1)); done
  after="$(git hash-object "$R/scripts/prebad.gd")"
  chk "e5 TERM during the baseline run: live file is the edited content immediately" "$([ "$during" = "$edited" ] && echo 1 || echo 0)"
  chk "e6 ...and is still the edited content after the baseline run would have finished (nothing resurrected or restored later)" "$([ "$after" = "$edited" ] && echo 1 || echo 0)"
  wait "$gpid" 2>/dev/null || true
  # the TERMed gate's baseline subshell outlives it by a moment (it finishes its engine run and writes its cache entry): wait until nothing of this test's tree is
  # running any more, or the EXIT-trap rm -rf races its last write ("Directory not empty")
  i=0; while [ "$i" -lt 300 ] && [ "$(ps -axo command 2>/dev/null | grep -c -- "[${T:0:1}]${T:1}/")" != 0 ]; do sleep 0.1; i=$((i+1)); done
  return "$BF"
}

BATTERY_VERBOSE=1 battery "$AT_REAL"; brc=$?
if [ "$brc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: real ovn_autotest.sh failed $brc assertion(s)"; fi

if [ -n "${AT_TEST_REAL_ONLY:-}" ]; then   # developer/stability shortcut: the real-script battery only (skip the slow mutation pass)
  echo "Autotest godot baseline (real script only): $P passed, $F failed"; [ "$F" -eq 0 ]; exit
fi

# ---- mutation checks: each mutant breaks one new behaviour; the battery must notice ----
mutate(){ # <name> <old> <new>
  local name="$1" old="$2" new="$3" out="$T/mut_$1.sh"
  python3 - "$AT_REAL" "$out" "$old" "$new" <<'PY' || { F=$((F+1)); echo "  FAIL: mutation '$name' could not be applied (source drifted)"; return; }
import sys
src, out, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit(1)
open(out, "w").write(s.replace(old, new))
PY
  battery "$out"; local mrc=$?
  if [ "$mrc" -gt 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: mutant '$name' survived (battery stayed green)"; fi
}
mutate no-import        '[ ! -f .godot/global_script_class_cache.cfg ]' '[ -f .godot/global_script_class_cache.cfg ]'
mutate no-baseline      '-lt "$(grep -cxF -- "$n" <<< "$base_errs")" ]' '-lt 0 ]'
mutate baseline-all-ok  '-lt "$(grep -cxF -- "$n" <<< "$base_errs")" ]' '-lt 999 ]'
mutate lint-shown       'gd_lint="${gd_lint}' 'gd_report="${gd_report}'
mutate no-cache-read    'if [ -n "$key" ] && [ -f "$cf" ]; then' 'if [ -n "$key" ] && [ -f "$cf.never" ]; then'
mutate baseline-in-live 'bout="$(cd "$ov" && timeout 60' 'bout="$(timeout 60'
mutate baseline-edited  'git show "$ref:$f" > "$cd_/$part"' 'cat "$f" > "$cd_/$part"'
mutate membership-only  '<<< "$used")" -lt' '<<< "")" -lt'
mutate key-no-import    '"$cc" "$(gd_sibling_sig "$f" "$ref")"' '"" "$(gd_sibling_sig "$f" "$ref")"'
mutate key-no-sibling   '"$cc" "$(gd_sibling_sig "$f" "$ref")"' '"$cc" ""'
mutate cache-in-place   '{ printf '"'%s\\n'"' "$bout" > "$tmpf" && mv -f "$tmpf" "$cf"; }' '{ printf '"'%s\\n'"' "$bout" > "$cf"; }'
mutate no-prune         '-mtime +0 -delete' '-mtime +9999 -delete'
mutate ref-ignored      'gd_base_ref="$OVN_BASE_SHA"' 'gd_base_ref="HEAD"'

echo "Autotest godot baseline: $P passed, $F failed"
[ "$F" -eq 0 ]
