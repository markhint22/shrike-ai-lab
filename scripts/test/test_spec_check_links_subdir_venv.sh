#!/usr/bin/env bash
# Regression: ovn_spec_check.sh linked only root .venv + iptv-backend/.venv into its worktree, so backend/.venv repos (gitlark, test-automation-agent, shrike-monitor, shrike-notify,
# billwatch-backend/.venv) ran pytest VERIFYs without their venv -> rc 127 -> verify-bad-spec:unrunnable (live 2026-10-18, explorer red-check). Hermetic: fake venv pytest.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
GITQ=(git -c user.name=t -c user.email=t@t)
run_case(){  # $1 = spec-check script dir -> prints the classifier row
  local d="$tmp/live-$2"; mkdir -p "$d/scripts" "$d/state" "$d/repos"
  git init -q --bare "$d/origin.git"; git clone -q "$d/origin.git" "$d/repos/demo" 2>/dev/null
  ( cd "$d/repos/demo" && "${GITQ[@]}" checkout -q -b overnight/feature && mkdir -p backend/tests && printf 'x\n' > backend/tests/test_a.py && printf '# p\n' > OVERNIGHT_PROGRESS.md \
    && printf '.venv/\n' > .gitignore && git add -A && "${GITQ[@]}" commit -q -m init && git push -q origin overnight/feature ) >/dev/null 2>&1
  mkdir -p "$d/repos/demo/backend/.venv/bin"
  printf '#!/bin/sh\necho "1 failed in 0.01s"\nexit 1\n' > "$d/repos/demo/backend/.venv/bin/pytest"; chmod +x "$d/repos/demo/backend/.venv/bin/pytest"
  printf '#!/bin/sh\nexit 0\n' > "$d/repos/demo/backend/.venv/bin/python3"; chmod +x "$d/repos/demo/backend/.venv/bin/python3"
  for f in lib_verify_clause.sh lib_gut_xml.sh lib_worktree.sh ovn_spec_check.sh ovn_spec_classify.py ovn_backlog_eligibility.py ovn_spec_rules.py; do cp "$1/$f" "$d/scripts/" 2>/dev/null; done
  printf -- '- [ ] [T2] backend/app/a.py — Fix a. VERIFY: `cd backend && pytest tests/test_a.py -q`. (cat:python; multifile:no)\n' > "$d/bl.md"
  ( cd "$d" && OVN_DIR="$d" bash scripts/ovn_spec_check.sh demo "$d/bl.md" 2>&1 )
}
out_new="$(run_case "$SRC" new)"
echo "new : $out_new"
ok "backend/.venv linked: the pytest VERIFY runs and is judged RED (not unrunnable)" "printf '%s' \"\$out_new\" | grep -q 'red' && ! printf '%s' \"\$out_new\" | grep -qi 'unrunnable'"
# mutant: the old root-only linking line makes the same case unrunnable
mkdir -p "$tmp/mut"; cp "$SRC"/lib_verify_clause.sh "$SRC"/lib_gut_xml.sh "$SRC"/lib_worktree.sh "$SRC"/ovn_spec_classify.py "$SRC"/ovn_backlog_eligibility.py "$SRC"/ovn_spec_rules.py "$tmp/mut/" 2>/dev/null
python3 - "$SRC/ovn_spec_check.sh" "$tmp/mut/ovn_spec_check.sh" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
a=s.index('_clone_abs="$(cd')
b=s.index("2>/dev/null)\n", s.index("done < <(find", a))+len("2>/dev/null)\n")
s=s[:a]+'for v in .venv iptv-backend/.venv; do [ -e "$clone/$v" ] && [ -d "$(dirname "$wt/$v")" ] && ln -sfn "$clone/$v" "$wt/$v" 2>/dev/null; done\n'+s[b:]
open(sys.argv[2],"w").write(s)
PY
out_mut="$(run_case "$tmp/mut" mut)"
echo "mut : $out_mut"
ok "MUTANT (old root-only link loop) is caught: the case is no longer judged red" "! printf '%s' \"\$out_mut\" | grep -q 'red'"
echo "spec_check subdir venv: $P passed, $F failed"; [ "$F" = 0 ]
