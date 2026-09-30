#!/usr/bin/env bash
# Wave-3 coverage: remaining branches of the small top-level python tools (real files, run in place):
# dedupe_progress_headers.py, dedupe_gd_duplicate_functions.py, dedupe_python_duplicate_defs.py,
# ovn_auto_research_validate.py, ovn_filesize_retag.py.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'chmod -R u+rw "$T" 2>/dev/null; rm -rf "$T"' EXIT

# ---- usage exits ----
for s in dedupe_progress_headers dedupe_gd_duplicate_functions dedupe_python_duplicate_defs; do
  [ -f "$R/$s.py" ] || continue
  err="$(python3 "$R/$s.py" 2>&1 >/dev/null)"; rc=$?
  ok "$s: no args -> exit 2 + usage" "$([ $rc = 2 ] && [ "$(has "$err" usage)" = 1 ] && echo 1 || echo 0)"
  err="$(python3 "$R/$s.py" a b 2>&1 >/dev/null)"; rc=$?
  ok "$s: two args -> exit 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
done

# ---- dedupe_progress_headers: duplicate header whose sections start with blank lines ----
f="$T/prog.md"
printf '%s\n' '## Decisions' '' '- one' '' '## Other' '- x' '' '## Decisions' '' '' '- two' '' > "$f"
out="$(python3 "$R/dedupe_progress_headers.py" "$f")"
ok "headers: merged reported" "$(has "$out" 'merged headers')"
ok "headers: one Decisions header left" "$([ "$(grep -c '^## Decisions' "$f")" = 1 ] && echo 1 || echo 0)"
ok "headers: both bullets kept" "$([ "$(grep -c '^- ' "$f")" = 3 ] && echo 1 || echo 0)"
out="$(python3 "$R/dedupe_progress_headers.py" "$f")"
ok "headers: second run unchanged" "$([ "$out" = unchanged ] && echo 1 || echo 0)"
# fewer than 2 bullets: dedupe_bullets early return
printf '%s\n' '## A' '- only bullet' > "$T/one.md"
out="$(python3 "$R/dedupe_progress_headers.py" "$T/one.md")"
ok "headers: single bullet unchanged" "$([ "$out" = unchanged ] && echo 1 || echo 0)"

# ---- gd: fewer than 2 units ----
printf 'extends Node\n\nfunc a():\n\tpass\n' > "$T/one.gd"
out="$(python3 "$R/dedupe_gd_duplicate_functions.py" "$T/one.gd")"
ok "gd: single unit unchanged" "$([ "$out" = unchanged ] && echo 1 || echo 0)"

# ---- python dedupe: still exercises a plain dup + trailing blank trimming ----
printf 'def a():\n    return 1\n\n\ndef a():\n    return 1\n\n' > "$T/d.py"
out="$(python3 "$R/dedupe_python_duplicate_defs.py" "$T/d.py")"
ok "pydefs: duplicate removed" "$(has "$out" 'removed duplicate')"
ok "pydefs: one def remains" "$([ "$(grep -c '^def a' "$T/d.py")" = 1 ] && echo 1 || echo 0)"

# ---- ovn_auto_research_validate ----
V="$R/ovn_auto_research_validate.py"
out="$(python3 "$V" "$T/missing-proposed.md" "$T/missing-existing.md" 2>&1)"
ok "validate: missing inputs -> accepted 0/0, exit 0" "$(has "$out" 'accepted 0/0')"
printf '%s\n' '- [ ] [P2] [ready] Tidy the parser — edit app/parser.py to tidy {cat: python}' > "$T/prop.md"
out="$(python3 "$V" "$T/prop.md" "$T/missing-existing.md" 2>/dev/null)"
ok "validate: valid line accepted without existing roadmap" "$(has "$out" '[ready] Tidy the parser')"
long="$(python3 -c 'print("x"*1600)')"
printf '%s\n' "- [ ] [P2] [ready] Long one — edit app/long.py $long {cat: python}" > "$T/long.md"
err="$(python3 "$V" "$T/long.md" "$T/missing-existing.md" 2>&1 >/dev/null)"
ok "validate: over-long line rejected" "$(has "$err" 'reject: too long')"
ok "validate: long reject counts 0/1" "$(has "$err" 'accepted 0/1')"

# ---- ovn_filesize_retag ----
S="$R/ovn_filesize_retag.py"
mkdir -p "$T/repo/app"
python3 -c 'print("\n".join("x"*5 for _ in range(10)))' > "$T/repo/app/big.py"
cp "$T/repo/app/big.py" "$T/repo/app/locked.py"; chmod 000 "$T/repo/app/locked.py"
printf '%s\n' '## Next' \
  '- [ ] [T2] see docs/readme.md then app/big.py — change' \
  '- [ ] [T1] app/locked.py — change' > "$T/PROG.md"
out="$(python3 "$S" "$T/PROG.md" "$T/repo" 3)"
ok "filesize: skips .md token, retags big.py" "$([ "$out" = "RETAGGED=1" ] && echo 1 || echo 0)"
if [ -r "$T/repo/app/locked.py" ]; then
  echo "  note: running as a user that can read chmod 000 files; OSError branch not exercised"
else
  ok "filesize: unreadable target left untouched" "$(grep -q '^- \[ \] \[T1\] app/locked.py' "$T/PROG.md" && echo 1 || echo 0)"
fi

echo "small_py_more: $P passed, $F failed"
[ "$F" -eq 0 ]
