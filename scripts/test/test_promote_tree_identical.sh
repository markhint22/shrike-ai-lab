#!/usr/bin/env bash
# promote_to_prod.sh + daily_promote.sh (2026-10-09): billwatch, gitlark, test-automation-agent, shrike-labs-website and iptv_apps were promoted "+1" every day
# where the +1 was a tree-identical 'chore(sync): reconcile main -> develop' commit: an empty "release: promote" merge and a Railway/Vercel prod deploy with NO
# content change. promote_to_prod.sh now skips a repo whose develop tree equals main's ("nothing to promote (tree identical)", through the existing
# No-change path); daily_promote.sh lists it under "No change (tree identical)". Never skips when any file differs; --force and OVN_PROMOTE_SKIP_IDENTICAL=0 keep
# the old behaviour. Runs the REAL scripts against temp bare origins + clones in a hermetic fake HOME (env -i, curl is a recording shim: nothing can reach a
# network, ntfy.sh or a real deploy), then runs the same scenarios against 5 mutants, each of which must be caught.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ="$HERE/../.."; [ -f "$OQ/promote_to_prod.sh" ] || OQ="$HERE/.."
for f in promote_to_prod.sh daily_promote.sh; do [ -f "$OQ/$f" ] || { echo "  SKIP: $f not found"; exit 0; }; done
OQ="$(cd "$OQ" && pwd)"
T="$(mktemp -d)"; trap 'cd /; rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # /private/var vs /var on macOS
P=0; F=0
# assertions are evaluated with pipefail OFF (no `x | grep -q` flakiness); conditions use grep -c / [ ] only
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $SUITE: $1"; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$T/shim"
printf '#!/bin/sh\nshift\nexec "$@"\n' > "$T/shim/timeout"          # our own timeout: the fake env has no coreutils on PATH
printf '#!/bin/sh\necho "CURL_CALL $*" >> "$FAKE_CURL_LOG"\nexit 0\n' > "$T/shim/curl"
chmod +x "$T/shim/timeout" "$T/shim/curl"
ENVPATH="$T/shim:/usr/bin:/bin:/usr/local/bin"
EXTRA=()

# ---- fake queue dir + repos -------------------------------------------------------------------------------------------------------------------------
setup(){  # $1=promote_to_prod.sh to test  $2=daily_promote.sh to test
  rm -rf "$T/home" "$T/origin" "$T/seed"
  export HOME="$T/home"; Q="$HOME/overnight-queue"; OUT="$T/out.log"
  mkdir -p "$Q/state" "$Q/repos" "$Q/logs" "$T/origin" "$T/seed"
  cp "$1" "$Q/promote_to_prod.sh"; cp "$2" "$Q/daily_promote.sh"; chmod +x "$Q/promote_to_prod.sh" "$Q/daily_promote.sh"
  : > "$T/curl.log"; EXTRA=()
}
mkrepo(){  # $1=name $2=kind: identical (empty sync commit) | cancel (add then remove a file: +2, same tree) | diff (one real file)
  local n="$1" kind="$2" o="$T/origin/$1.git" s="$T/seed/$1"
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s" && echo base > f.txt && git add f.txt && git commit -q -m base && git branch -M main && git push -q origin main
    git checkout -q -b develop
    case "$kind" in
      identical) git commit -q --allow-empty -m "chore(sync): reconcile main -> develop";;
      cancel) echo tmp > tmp.txt && git add tmp.txt && git commit -q -m "feat: add tmp" && git rm -q tmp.txt && git commit -q -m "revert: drop tmp";;
      diff) echo "one line" > feature.txt && git add feature.txt && git commit -q -m "feat: one real change";;
    esac
    git push -q origin develop ) >/dev/null 2>&1
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
}
sha(){ git -C "$T/origin/$1.git" rev-parse "$2" 2>/dev/null; }
ntags(){ git -C "$T/origin/$1.git" tag -l 'prod-*' | wc -l | tr -d ' '; }
cronenv(){ env -i HOME="$HOME" PATH="$ENVPATH" NTFY_SERVER=http://127.0.0.1:9 FAKE_CURL_LOG="$T/curl.log" NTFY_TOPIC=selftest_ignore \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    ${EXTRA[@]+"${EXTRA[@]}"} "$@"; }
runp(){ ( cd "$Q" && cronenv bash "$Q/promote_to_prod.sh" "$@" > "$OUT" 2>&1 < /dev/null ); }
rund(){ ( cd "$Q" && cronenv OVN_PROMOTE_REPOS="$1" bash "$Q/daily_promote.sh" > "$OUT" 2>&1 < /dev/null ); }
cnt(){ grep -c -F -- "$1" "$OUT"; }

run_suite(){  # $1=label $2=promote script $3=daily script
  SUITE="$1"
  setup "$2" "$3"
  mkrepo idrepo identical; mkrepo cancelrepo cancel; mkrepo difrepo diff; mkrepo forcerepo identical
  local id0 ca0 di0; id0="$(sha idrepo main)"; ca0="$(sha cancelrepo main)"; di0="$(sha difrepo main)"
  ok "fixture: the identical repo really is +1 ahead with a byte-identical tree, the cancel repo +2, the diff repo +1 with a real diff" \
     "[ \"\$(git -C '$Q/repos/idrepo' rev-list --count origin/main..origin/develop)\" = 1 ] && git -C '$Q/repos/idrepo' diff --quiet origin/main origin/develop && [ \"\$(git -C '$Q/repos/cancelrepo' rev-list --count origin/main..origin/develop)\" = 2 ] && git -C '$Q/repos/cancelrepo' diff --quiet origin/main origin/develop && ! git -C '$Q/repos/difrepo' diff --quiet origin/main origin/develop"

  # ---- daily_promote over a tree-identical, a cancelling (+2, same tree) and a real-diff repo: all three assertions of the acceptance in ONE run ----
  rund "idrepo cancelrepo difrepo"
  ok "daily: the identical repo is skipped with the new log line (and was +1 ahead)" "[ \"\$(cnt 'idrepo: develop is +1 ahead of main')\" = 1 ] && [ \"\$(cnt 'nothing to promote (tree identical)')\" -ge 2 ]"
  ok "daily: no merge commit and no prod tag is created for the identical repo (origin main unchanged)" "[ \"\$(sha idrepo main)\" = '$id0' ] && [ \"\$(ntags idrepo)\" = 0 ]"
  ok "daily: +2 commits that cancel out (same tree) are skipped too" "[ \"\$(sha cancelrepo main)\" = '$ca0' ] && [ \"\$(ntags cancelrepo)\" = 0 ]"
  ok "daily: the one-file diff repo is PROMOTED as before (release merge on main, prod tag, main tree == develop tree)" \
     "[ \"\$(sha difrepo main)\" != '$di0' ] && [ \"\$(ntags difrepo)\" = 1 ] && [ \"\$(git -C '$T/origin/difrepo.git' log -1 --format=%s main | cut -c1-16)\" = 'release: promote' ] && [ \"\$(git -C '$T/origin/difrepo.git' rev-parse main^{tree})\" = \"\$(git -C '$T/origin/difrepo.git' rev-parse develop^{tree})\" ]"
  ok "daily summary: 'Promoted: difrepo'" "[ \"\$(grep -c '^Promoted: difrepo\$' '$OUT')\" = 1 ]"
  ok "daily summary: both skipped repos are in the 'No change' list and in the 'No change (tree identical)' list" \
     "[ \"\$(grep -c '^No change: idrepo cancelrepo\$' '$OUT')\" = 1 ] && [ \"\$(grep -c '^No change (tree identical): idrepo cancelrepo\$' '$OUT')\" = 1 ]"
  ok "daily: the skipped repos are not reported as blocked or held" "[ \"\$(cnt 'BLOCKED')\" = 0 ] && [ \"\$(cnt 'HELD')\" = 0 ]"

  # ---- promote_to_prod.sh directly ----
  runp --yes repos/idrepo
  ok "promote --yes on the identical repo prints 'nothing to promote (tree identical)' and changes nothing" "[ \"\$(cnt 'nothing to promote (tree identical)')\" = 1 ] && [ \"\$(cnt PROMOTED)\" = 0 ] && [ \"\$(sha idrepo main)\" = '$id0' ]"
  runp --dry-run repos/idrepo
  ok "--dry-run reports the skip as well (no 'would merge' line)" "[ \"\$(cnt 'nothing to promote (tree identical)')\" = 1 ] && [ \"\$(cnt 'would merge')\" = 0 ]"
  runp --yes --force repos/forcerepo
  ok "--force still promotes a tree-identical repo (explicit operator override)" "[ \"\$(cnt PROMOTED)\" = 1 ] && [ \"\$(ntags forcerepo)\" = 1 ]"
  EXTRA=(OVN_PROMOTE_SKIP_IDENTICAL=0)
  rund "idrepo"
  ok "kill switch OVN_PROMOTE_SKIP_IDENTICAL=0: the identical repo is promoted again (old behaviour: release merge + tag) and not listed as tree identical" \
     "[ \"\$(sha idrepo main)\" != '$id0' ] && [ \"\$(ntags idrepo)\" = 1 ] && [ \"\$(grep -c '^Promoted: idrepo\$' '$OUT')\" = 1 ] && [ \"\$(cnt 'tree identical')\" = 0 ]"
  EXTRA=()
  rund "idrepo"
  ok "after a promote there is nothing ahead: the plain 'nothing to promote.' path is unchanged and is not labelled tree identical" \
     "[ \"\$(cnt 'idrepo: develop is +0 ahead of main')\" = 1 ] && [ \"\$(grep -c '^No change: idrepo\$' '$OUT')\" = 1 ] && [ \"\$(cnt 'tree identical')\" = 0 ]"
}

run_suite "real" "$OQ/promote_to_prod.sh" "$OQ/daily_promote.sh"
[ "$F" -eq 0 ] && echo "  ok   real scripts: all scenario assertions hold"

mutate(){  # $1=label $2=file(promote|daily) $3=old $4=new : the suite against the mutant must produce at least one FAIL line
  local src="$OQ/promote_to_prod.sh"; [ "$2" = daily ] && src="$OQ/daily_promote.sh"
  OLD="$3" NEW="$4" python3 - "$src" "$T/mutant.sh" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { F=$((F+1)); echo "  FAIL: mutation '$1' could not be applied"; return; }
  local out
  if [ "$2" = daily ]; then out="$(run_suite "mutant" "$OQ/promote_to_prod.sh" "$T/mutant.sh" 2>&1)"
  else out="$(run_suite "mutant" "$T/mutant.sh" "$OQ/daily_promote.sh" 2>&1)"; fi
  if [ "$(printf '%s\n' "$out" | grep -c 'FAIL: mutant')" -gt 0 ]; then P=$((P+1)); echo "  ok   mutation caught: $1"; else F=$((F+1)); echo "  FAIL: mutation NOT caught: $1"; fi
}
mutate "skip never happens" promote 'git -C "$repo" diff --quiet "origin/$DEF" origin/develop 2>/dev/null' 'false'
mutate "skip always happens (even with a real diff)" promote 'git -C "$repo" diff --quiet "origin/$DEF" origin/develop 2>/dev/null' 'true'
mutate "--force no longer overrides the skip" promote '[ "$FORCE" -ne 1 ] && git -C "$repo" diff --quiet' 'git -C "$repo" diff --quiet'
mutate "kill switch ignored" promote '[ "${OVN_PROMOTE_SKIP_IDENTICAL:-1}" != "0" ] && [ "$FORCE" -ne 1 ]' '[ "$FORCE" -ne 1 ]'
mutate "daily summary forgets the tree-identical list" daily 'echo "$out" | grep -q "nothing to promote (tree identical)" && identical="$identical $r"' 'true'

echo "promote_tree_identical: $P passed, $F failed"
[ "$F" -eq 0 ]
