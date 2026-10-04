#!/usr/bin/env bash
# ovn_test_collect_canary.sh - "ghost test" canary (2026-10-04 QA audit C).
# Counts the test files that exist on disk vs the test files the repo's verify command actually COLLECTS, per repo, and writes ONE alerts.log warn
# line (deduped on the exact set of missing files) when MORE THAN OVN_CANARY_MAX (default 3) test files are never collected.
#   iptv_apps (python): disk = tracked test_*.py / *_test.py under iptv-backend; collected = `pytest --collect-only -q` (same testpaths as the gate;
#                       OVN_COLLECT_APP_TESTS=on adds `app`, mirroring the opt-in verify switch).
#   xlite (GUT):        disk = tracked tests/ + test/ *.gd files containing `func test_`; collected = <testsuite name> entries of a real GUT junit run
#                       (-gdir=res://tests, + -ginclude_subdirs unless OVN_GUT_SUBDIRS=off).
# Read-only on the live clones (a detached scratch worktree of origin/claude/feature is used and removed), nice'd, never takes run.lock or a verify lock,
# ALWAYS exits 0. Infra trouble (no pytest/godot, timeout, worktree failure) => one log line "infra", NO alert (never a false alarm).
# Kill switch: OVN_TEST_COLLECT_CANARY=off. Cron line (shipped, NOT installed): scripts/cron.txt.
# Env (tests): OVN_DIR, OVN_REPOS_DIR, OVN_CANARY_REPOS="name:kind:subdir ...", OVN_CANARY_REF, OVN_CANARY_PYTEST, OVN_CANARY_GODOT, OVN_CANARY_MAX.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVN="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
REPOS="${OVN_REPOS_DIR:-$OVN/repos}"
STATE="${OVN_STATE_DIR:-$OVN/state}"; mkdir -p "$STATE" 2>/dev/null
LOGF="${OVN_CANARY_LOG:-$OVN/logs/test_collect_canary.log}"; mkdir -p "$(dirname "$LOGF")" 2>/dev/null
MAX="${OVN_CANARY_MAX:-3}"
REF="${OVN_CANARY_REF:-origin/claude/feature}"
log(){ echo "$(date '+%F %T') [collect-canary] $*" | tee -a "$LOGF" 2>/dev/null; }
[ "${OVN_TEST_COLLECT_CANARY:-on}" = "off" ] && { log "disabled (OVN_TEST_COLLECT_CANARY=off)"; exit 0; }
command -v nice >/dev/null 2>&1 && NICE="nice -n 15" || NICE=""

alert_missing(){ # repo count listfile
  local repo="$1" n="$2" lf="$3" sig
  sig="$repo:$(sort "$lf" | { md5sum 2>/dev/null || md5 -q; } | cut -c1-12)"
  grep -qxF "$sig" "$STATE/test_collect_canary_seen.txt" 2>/dev/null && return 0
  echo "$sig" >> "$STATE/test_collect_canary_seen.txt" 2>/dev/null
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] warn | test-collect-canary:$repo | $n test file(s) exist but are NEVER collected by the verify command (ghost tests; limit $MAX): $(sort "$lf" | head -5 | tr '\n' ' ')" >> "$STATE/alerts.log" 2>/dev/null
}

report(){ # repo disk_file collected_file
  local repo="$1" d="$2" c="$3" miss n nd nc
  miss="$(mktemp)"; LC_ALL=C sort -u "$d" > "$d.s"; LC_ALL=C sort -u "$c" > "$c.s"
  LC_ALL=C comm -23 "$d.s" "$c.s" > "$miss"
  n="$(grep -c . "$miss")"; nd="$(grep -c . "$d.s")"; nc="$(grep -c . "$c.s")"
  log "$repo: disk=$nd collected=$nc not_collected=$n"
  if [ "$n" -gt "$MAX" ]; then alert_missing "$repo" "$n" "$miss"; log "$repo: ALERT (> $MAX uncollected): $(head -3 "$miss" | tr '\n' ' ')"; fi
  rm -f "$miss" "$d.s" "$c.s"
}

canary_py(){ # name rd wt sub
  local name="$1" rd="$2" wt="$3" sub="${4:-.}" pytest d c out rc args
  pytest="${OVN_CANARY_PYTEST:-}"
  if [ -z "$pytest" ]; then for p in "$rd/$sub/.venv/bin/pytest" "$rd/.venv/bin/pytest"; do [ -x "$p" ] && pytest="$p" && break; done; fi
  [ -n "$pytest" ] && [ -x "$pytest" ] || { log "$name: infra (no pytest) - skipped, no alert"; return 0; }
  d="$(mktemp)"; c="$(mktemp)"
  ( cd "$wt" && git ls-files -- "$sub" ) | grep -E '(^|/)(test_[^/]*|[^/]*_test)\.py$' | grep -vE '(^|/)(node_modules|\.venv|venv)/' | sed "s#^${sub%/}/##" > "$d"
  args=""; [ "${OVN_COLLECT_APP_TESTS:-off}" = "on" ] && args="app"
  out="$( cd "$wt/$sub" && PYTHONDONTWRITEBYTECODE=1 timeout 240 $NICE "$pytest" --collect-only -q -p no:cacheprovider -o addopts="" $args 2>&1 )"; rc=$?
  case "$rc" in 0|1|2|5) : ;; *) log "$name: infra (pytest rc=$rc) - skipped, no alert"; rm -f "$d" "$c"; return 0 ;; esac
  printf '%s\n' "$out" | grep -E '^[^ ]+\.py(::|$)' | sed 's/::.*//' | sed 's#^\./##' > "$c"
  printf '%s\n' "$out" | grep -E '^ERROR ' | grep -oE '[^ ]+\.py' | sed 's#^\./##' >> "$c"   # files that fail at collection ARE collected (red in the gate, not ghosts)
  [ -s "$c" ] || { log "$name: infra (pytest collected nothing, rc=$rc) - skipped, no alert"; rm -f "$d" "$c"; return 0; }
  report "$name" "$d" "$c"; rm -f "$d" "$c"
}

canary_gd(){ # name rd wt
  local name="$1" rd="$2" wt="$3" godot d c xml sub="-ginclude_subdirs" rc
  godot="${OVN_CANARY_GODOT:-$HOME/godot/godot4}"
  [ -x "$godot" ] && [ -f "$wt/project.godot" ] && [ -f "$wt/addons/gut/gut_cmdln.gd" ] || { log "$name: infra (no godot/gut) - skipped, no alert"; return 0; }
  [ "${OVN_GUT_SUBDIRS:-on}" = "off" ] && sub=""
  d="$(mktemp)"; c="$(mktemp)"; xml="$(mktemp)"
  ( cd "$wt" && git ls-files -- tests test ) | grep -E '\.gd$' | while IFS= read -r f; do grep -qE '^[[:space:]]*func[[:space:]]+test_' "$wt/$f" 2>/dev/null && echo "$f"; done > "$d"
  if [ -z "${OVN_CANARY_GODOT_NOIMPORT:-}" ]; then
    command -v rsync >/dev/null 2>&1 && git -C "$rd" ls-files -z --others --ignored --exclude-standard 2>/dev/null | grep -zE '(^|/)\.godot/|\.import$' | rsync -a --from0 --files-from=- "$rd/" "$wt/" >/dev/null 2>&1
    ( cd "$wt" && timeout 120 $NICE "$godot" --headless --path . --import ) >/dev/null 2>&1
  fi
  ( cd "$wt" && timeout 180 $NICE "$godot" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests $sub -gexit "-gjunit_xml_file=$xml" ) >/dev/null 2>&1; rc=$?
  [ -s "$xml" ] || { log "$name: infra (GUT produced no junit xml, rc=$rc) - skipped, no alert"; rm -f "$d" "$c" "$xml"; return 0; }
  grep -oE '<testsuite [^>]*name="[^"]+"' "$xml" | sed -E 's/.*name="([^"]+)".*/\1/' | sed 's#^res://##' > "$c"
  report "$name" "$d" "$c"; rm -f "$d" "$c" "$xml"
}

for spec in ${OVN_CANARY_REPOS:-iptv_apps:py:iptv-backend xlite:gd:.}; do
  name="${spec%%:*}"; rest="${spec#*:}"; kind="${rest%%:*}"; sub="${rest#*:}"
  rd="$REPOS/$name"
  [ -d "$rd/.git" ] || [ -f "$rd/.git" ] || { log "$name: infra (no clone at $rd) - skipped"; continue; }
  wt="$(mktemp -d "/tmp/wt-collectcanary-$name.XXXX")" || continue
  if ! git -C "$rd" worktree add --quiet --detach "$wt" "$REF" >/dev/null 2>&1; then
    rmdir "$wt" 2>/dev/null; log "$name: infra (worktree of $REF failed) - skipped"; continue
  fi
  case "$kind" in py) canary_py "$name" "$rd" "$wt" "$sub" ;; gd) canary_gd "$name" "$rd" "$wt" ;; *) log "$name: unknown kind $kind" ;; esac
  git -C "$rd" worktree remove --force "$wt" >/dev/null 2>&1; git -C "$rd" worktree prune >/dev/null 2>&1; rm -rf "$wt"
done
exit 0
