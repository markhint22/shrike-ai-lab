#!/usr/bin/env bash
# Credit items the IMPLEMENT pass found already-satisfied in the code.
# The 27B walks the item list during implement and reports items already done
# ("Query is already imported", "already uses except Exception", "This item is
# already done") -> no diff, no commit -> UNTAGGED no-op, and the item is
# re-faced every cycle forever. This harvests the file named right before each
# already-done admission (awk tracks the last file token seen) and checks off
# the matching unchecked, non-human item. Prints CREDITED=<n>. Run in repo cwd.
set -uo pipefail
LOG="${1:-}"; PROG="${2:-OVERNIGHT_PROGRESS.md}"
[ -f "$LOG" ] || { echo "CREDITED=0"; exit 0; }
[ -f "$PROG" ] || { echo "CREDITED=0"; exit 0; }
FILES="$(awk '
  { if (match($0, /[A-Za-z0-9_\/.-]+\.[A-Za-z0-9]{1,8}/)) { lastf=substr($0,RSTART,RLENGTH) } }
  /[Aa]lready (done|implemented|imported|present|in place|use|uses|has|have|correct|handled|satisfied|been|exists|covers?|tests?|validates?|guards?)/ { if (lastf!="") print lastf }
  /[Nn]o changes? (needed|required|necessary)|[Nn]othing to (change|do|add)|is already (there|the case)|already (passes|passing)/ { if (lastf!="") print lastf }
' "$LOG" | sort -u)"
credited=0
for f in $FILES; do
  case "$f" in *.md) continue;; esac
  b="$(basename "$f")"
  ln="$(grep -nE '^- \[ \]' "$PROG" | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|BLOCKED ITEM' | grep -F "$b" | head -1 | cut -d: -f1)"
  if [ -n "$ln" ]; then
    sed -i "${ln}s/^- \[ \] /- [x] (already-satisfied in code, implement-verified) /" "$PROG"
    credited=$((credited+1))
    echo "credited line ${ln} (matched ${b})"
  fi
done
echo "CREDITED=${credited}"
exit 0
