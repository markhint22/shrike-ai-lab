#!/usr/bin/env bash
# Regression test: ovn_stale_top_item_check.py must track staleness via a persisted
# "first observed as #1" timestamp, not via git-blame on the roadmap line (2026-09-28).
#
# Bug this closes: git blame on OVERNIGHT_PROGRESS.md's #1 line measured "when was this
# LINE last edited", not "how long has this been the #1 PICK". A bulk backlog reformat
# stamps every line with the same edit time, so any item that LATER rotates into #1
# inherits that old shared timestamp and gets reported stale on its FIRST appearance.
# Confirmed live on iptv_apps: 7 different items alerted "stale" across ~30h, several
# already claiming 107-113h of staleness the moment they first became #1 — traced to a
# shared bulk-edit commit days earlier, not to when each item actually became #1.
#
# Verifies: (1) an item newly observed as #1 never alerts immediately, and only alerts
# once its OWN persisted clock (not git blame) crosses STALE_HOURS across repeated
# "runs" of an advancing fake clock; (2) a DIFFERENT item rotating into #1 on a line
# with an ancient git-blame/author timestamp does NOT inherit that age — its clock
# resets to zero instead of firing immediately.
set -uo pipefail
PY="${OVN_STALE_TOP_ITEM_PY:-$HOME/overnight-queue/scripts/ovn_stale_top_item_check.py}"
[ -f "$PY" ] || { echo "  SKIP: $PY not found on this host"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "  SKIP: git not available"; exit 0; }

PASS=0; FAIL=0
ok(){ if eval "$2" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
QUEUE_ROOT="$tmp/overnight-queue"
mkdir -p "$QUEUE_ROOT/state" "$QUEUE_ROOT/repos/repoA" "$QUEUE_ROOT/repos/repoB"

# $1=repo dir  $2=roadmap item text  $3=optional git author/committer date (approxidate)
mk_repo(){
  local dir="$1" text="$2" gdate="${3:-}"
  ( cd "$dir" && git init -q && git config user.email t@t && git config user.name t
    printf '# Roadmap\n\n%s\n' "$text" > OVERNIGHT_PROGRESS.md
    git add -A
    if [ -n "$gdate" ]; then
      GIT_AUTHOR_DATE="$gdate" GIT_COMMITTER_DATE="$gdate" git commit -q -m init
    else
      git commit -q -m init
    fi
  )
}

run_check(){ # $1=queue_root $2=stale_hours $3..=repos
  local qr="$1" sh="$2"; shift 2
  python3 "$PY" "$qr" "$sh" "$@" 2>/dev/null
}

STALE_HOURS=2

# ---- scenario A: item A is #1 across 3 "runs" of an advancing fake clock, tracked via
#      the SAME persisted first-seen file. The target file (app/itemA.py) is never
#      created/committed, so the "was the file touched in the window" corroboration
#      check always reads as untouched — isolating the test to the age logic itself. ----
mk_repo "$QUEUE_ROOT/repos/repoA" "- [ ] [T1] app/itemA.py fix the untouched thing"

out="$(run_check "$QUEUE_ROOT" "$STALE_HOURS" repoA)"
ok "run 1 (freshly observed as #1): no alert" "[ -z '$out' ]"
ok "run 1 creates the first-seen state file" \
   "[ -f '$QUEUE_ROOT/state/stale_top_item_first_seen_repoA' ]"

seen1="$(cat "$QUEUE_ROOT/state/stale_top_item_first_seen_repoA")"
key="${seen1%%|*}"
now="$(date +%s)"

# fake clock, run 2: rewind the persisted first-seen ts to STALE_HOURS-1 ago, same key
printf '%s|%s' "$key" "$(( now - (STALE_HOURS - 1) * 3600 ))" \
  > "$QUEUE_ROOT/state/stale_top_item_first_seen_repoA"
out="$(run_check "$QUEUE_ROOT" "$STALE_HOURS" repoA)"
ok "run 2 (same item aged $((STALE_HOURS - 1))h): still no alert (< STALE_HOURS)" "[ -z '$out' ]"
seen2="$(cat "$QUEUE_ROOT/state/stale_top_item_first_seen_repoA")"
ok "run 2 preserves the clock (same key, not reset)" "[ '${seen2%%|*}' = '$key' ]"

# fake clock, run 3: rewind past STALE_HOURS -> must alert now
printf '%s|%s' "$key" "$(( now - (STALE_HOURS + 1) * 3600 ))" \
  > "$QUEUE_ROOT/state/stale_top_item_first_seen_repoA"
out="$(run_check "$QUEUE_ROOT" "$STALE_HOURS" repoA)"
ok "run 3 (same item aged $((STALE_HOURS + 1))h): alerts" "printf '%s' '$out' | grep -q '^repoA'"

# ---- scenario B: item B rotates into #1 on a line whose git author/committer date is
#      deliberately ancient (stand-in for a bulk-edit timestamp) — must NOT alert
#      immediately; the persisted clock resets to ~0 regardless of blame age. ----
ancient_ts="@$(( $(date +%s) - 500 * 3600 ))"
mk_repo "$QUEUE_ROOT/repos/repoB" \
  "- [ ] [T1] app/itemB.py fix the other untouched thing" "$ancient_ts"

out="$(run_check "$QUEUE_ROOT" "$STALE_HOURS" repoB)"
ok "item B rotating onto an ancient git-blame line does not immediately alert" "[ -z '$out' ]"
ok "item B gets a freshly-created first-seen state file" \
   "[ -f '$QUEUE_ROOT/state/stale_top_item_first_seen_repoB' ]"

b_ts="$(cut -d'|' -f2 "$QUEUE_ROOT/state/stale_top_item_first_seen_repoB" | cut -d'.' -f1)"
b_age_h=$(( ( $(date +%s) - b_ts ) / 3600 ))
ok "item B's persisted age is ~0h, not ~500h (git blame is not the age source)" \
   "[ $b_age_h -lt 1 ]"

echo "Stale top item check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
