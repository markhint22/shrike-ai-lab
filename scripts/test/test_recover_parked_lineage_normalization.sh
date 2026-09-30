#!/usr/bin/env bash
# Regression test for ovn_recover_parked.sh's lineage-path normalization fix (2026-09-28).
#
# RECOVERY_LINEAGE_CAP is meant to force an escalation to [CLAUDE] after N decompose rounds
# targeting the SAME underlying file, tracked via a hash of the extracted file path
# (state/recovery_lineage/<repo>__<path>.count). Before this fix, the path was taken VERBATIM
# from the item text, so the same real file phrased two different ways across two recovery
# rounds (e.g. "backend/tests/test_x.py" vs "tests/test_x.py" — both legitimate references to
# one file) hashed to two different lineage keys, silently resetting the cap. Confirmed live
# on gitlark: one file got two separate "cap hit" escalations instead of being capped after
# the first.
#
# Extracts the real normalization block out of ovn_recover_parked.sh (not a reimplementation)
# so this can't silently drift from what's deployed.
set -uo pipefail
RP="${OVN_RECOVER_PARKED:-$HOME/overnight-queue/ovn_recover_parked.sh}"
[ -f "$RP" ] || { echo "  SKIP: $RP not found on this host"; exit 0; }
LIB="${OVN_LIB_PATH_NORMALIZE:-$HOME/overnight-queue/scripts/lib_path_normalize.sh}"
[ -f "$LIB" ] || { echo "  SKIP: lib_path_normalize.sh not found"; exit 0; }
# shellcheck source=/dev/null
source "$LIB"

BLOCK="$(sed -n '/^  lineage_file="\$(printf/,/^  lineage_key="\$(printf/p' "$RP")"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the lineage normalization block from $RP"; exit 1; }
case "$BLOCK" in
  *'PATH-PHRASING NORMALIZATION'*'ovn_normalize_path'*) : ;;
  *) echo "  FAIL: extracted block doesn't look like the expected normalization fix:"; printf '%s\n' "$BLOCK"; exit 1 ;;
esac

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

resolve(){ # $1=rd $2=task -> echoes the normalized lineage_file
  local rd="$1" task="$2" lineage_file lineage_key
  eval "$BLOCK" >/dev/null 2>&1
  printf '%s' "$lineage_file"
}

# --- A: real file lives at backend/tests/test_x.py; item text names it with a shorter,
#     directory-dropped phrasing "tests/test_x.py" -> should resolve to the REAL full path ---
rd="$tmp/repoA"; mkdir -p "$rd/backend/tests"
( cd "$rd" && git init -q && git config user.email t@t.com && git config user.name t \
  && echo x > backend/tests/test_x.py && git add -A && git commit -q -m init )
lf="$(resolve "$rd" '`tests/test_x.py` needs a fix')"
ok "short phrasing resolves to the real full tracked path" "[ '$lf' = 'backend/tests/test_x.py' ]"

# --- B: item text names the FULL real path directly -> unchanged (exact match, no rewrite) ---
lf2="$(resolve "$rd" '`backend/tests/test_x.py` needs a fix')"
ok "full real path is used as-is (exact tracked match)" "[ '$lf2' = 'backend/tests/test_x.py' ]"

# --- C: both phrasings now produce the SAME lineage key (the actual bug this closes) ---
key1="$(printf '%s' "repoA__${lf}" | tr '/' '_')"
key2="$(printf '%s' "repoA__${lf2}" | tr '/' '_')"
ok "both phrasings collapse to the identical lineage key" "[ '$key1' = '$key2' ]"

# --- D: no real file matches at all (e.g. a not-yet-created target) -> falls back to the raw
#     extracted text unchanged, same as the old behavior ---
lf3="$(resolve "$rd" '`brand_new_module.py` will be created')"
ok "no tracked-file match: falls back to the raw extracted text" "[ '$lf3' = 'brand_new_module.py' ]"

# --- E: basename-only match across a totally different directory prefix ---
rd2="$tmp/repoB"; mkdir -p "$rd2/services/billing/tests"
( cd "$rd2" && git init -q && git config user.email t@t.com && git config user.name t \
  && echo x > services/billing/tests/test_invoice.py && git add -A && git commit -q -m init )
lf4="$(resolve "$rd2" '`tests/billing/test_invoice.py` — wrong directory prefix entirely')"
ok "directory-prefix mismatch still resolves via basename match" \
   "[ '$lf4' = 'services/billing/tests/test_invoice.py' ]"

echo "recover-parked lineage normalization: $P passed, $F failed"
[ "$F" -eq 0 ]
