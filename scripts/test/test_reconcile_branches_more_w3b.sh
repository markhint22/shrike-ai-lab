#!/usr/bin/env bash
# Extra coverage for reconcile_branches.sh (wave 3, w3b): LLM-assisted conflict resolution
# (try_llm_resolve, aider + gate stubbed), merge_into / sync_feature failure ladders (git shim injects
# push/worktree failures), merge_sanity_ok variants, DRY_RUN, fetch failures, alerts (curl stubbed).
# Fully hermetic: fixture HOME, bare origins in a temp dir, stub curl/aider/timeout/git shim on PATH.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REC=""; for c in "$HERE/../../reconcile_branches.sh" "$HERE/../reconcile_branches.sh"; do [ -f "$c" ] && { REC="$c"; break; }; done
LIBTG=""; for c in "$HERE/../lib_tree_guard.sh" "$HERE/lib_tree_guard.sh"; do [ -f "$c" ] && { LIBTG="$c"; break; }; done
[ -n "$REC" ] && [ -n "$LIBTG" ] || { echo "SKIP: reconcile_branches.sh / lib_tree_guard.sh not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"
cleanup(){ rm -rf "$tmp" /tmp/reconcile-w3b-* 2>/dev/null; }
trap cleanup EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
REALGIT="$(command -v git)"

export HOME="$tmp/home"
OQ="$HOME/overnight-queue"
mkdir -p "$OQ/repos" "$OQ/logs" "$OQ/scripts" "$OQ/state" "$HOME/aider-venv/bin" "$tmp/shim"
# copy of the real script; ONLY the PATH line is neutralised so the stub curl/timeout/git win over /usr/bin
sed 's|^export PATH="/usr/local/bin:/usr/bin:/bin:\${PATH:-}"|export PATH="${PATH:-}"|' "$REC" > "$OQ/reconcile_branches.sh"
grep -q '^export PATH="${PATH:-}"' "$OQ/reconcile_branches.sh" || { echo "FATAL: PATH line sed failed"; exit 1; }
cp "$LIBTG" "$OQ/scripts/lib_tree_guard.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/tok.log"\n' "$tmp" > "$OQ/scripts/ovn_log_tokens.sh"
cat > "$OQ/branch_hygiene.sh" <<'EOF2'
run_gate() {
  log "gate ran"; echo "gate called for $1 $2"
  return "${GATE_RC:-0}"
}
EOF2
cat > "$HOME/aider-venv/bin/aider" <<'EOF2'
#!/usr/bin/env bash
echo "aider $*" >> "$AIDER_LOG"
files=(); while [ $# -gt 0 ]; do [ "$1" = --file ] && files+=("$2"); shift; done
case "${AIDER_MODE:-resolve}" in resolve) for f in "${files[@]}"; do printf 'resolved by stub\n' > "$f"; done;; esac
echo "Tokens: 1.5k sent, 2k received."
exit 0
EOF2
cat > "$tmp/shim/curl" <<EOF2
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in Title:*) echo "\$a" >> "$tmp/curl.log" ;; esac; done
exit 0
EOF2
cat > "$tmp/shim/timeout" <<'EOF2'
#!/usr/bin/env bash
shift
if [ -n "${TIMEOUT_HOOK:-}" ] && [[ "$*" == *"fetch -q origin develop" ]] && [ ! -f "$TIMEOUT_HOOK.done" ]; then : > "$TIMEOUT_HOOK.done"; bash "$TIMEOUT_HOOK"; fi
exec "$@"
EOF2
cat > "$tmp/shim/git" <<EOF2
#!/usr/bin/env bash
args="\$*"
if [ -n "\${GIT_SHIM_FAIL:-}" ] && [[ "\$args" == *"\$GIT_SHIM_FAIL"* ]]; then exit 1; fi
if [ -n "\${GIT_SHIM_FAIL_ONCE:-}" ] && [[ "\$args" == *"\$GIT_SHIM_FAIL_ONCE"* ]] && [ ! -f "\$GIT_SHIM_ONCE_FLAG" ]; then : > "\$GIT_SHIM_ONCE_FLAG"; exit 1; fi
exec "$REALGIT" "\$@"
EOF2
chmod +x "$OQ/scripts/ovn_log_tokens.sh" "$HOME/aider-venv/bin/aider" "$tmp/shim/"*
export AIDER_LOG="$tmp/aider.log"; : > "$AIDER_LOG"

# ---- fixture helpers ----
newrepo(){ # $1=name [$2=branches to create, default all]
  local n="$1" br="${2:-develop overnight/feature claude/feature}" b
  git init -q --bare "$tmp/o_$n.git"
  git clone -q "$tmp/o_$n.git" "$tmp/s_$n" 2>/dev/null
  ( cd "$tmp/s_$n"
    printf 'one\ntwo\nthree\nfour\nfive\n' > f.txt
    for i in 1 2 3 4; do printf 'one\ntwo\nthree\n' > "c$i.txt"; done
    git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    for b in $br; do git branch "$b"; git push -q origin "$b"; done )
  git clone -q "$tmp/o_$n.git" "$OQ/repos/$n" 2>/dev/null
}
sc(){ # $1=name $2=branch $3=msg ; rest: shell commands run in seed on that branch (from origin/branch)
  local n="$1" b="$2" m="$3"; shift 3
  ( cd "$tmp/s_$n" && git fetch -q origin && git checkout -q -B "$b" "origin/$b" && eval "$*" && git add -A && git commit -q -m "$m" && git push -q origin "$b" )
}
ohead(){ git -C "$tmp/o_$1.git" rev-parse "$2"; }
orun(){ # $1=name, env assignments via exported vars ; output -> $OUT
  OUT="$( cd "$OQ" && PATH="$tmp/shim:$PATH" bash ./reconcile_branches.sh "repos/$1" 2>&1 )"
}
curls(){ cat "$tmp/curl.log" 2>/dev/null; }
reset_logs(){ : > "$tmp/curl.log"; : > "$AIDER_LOG"; rm -f "$tmp/tok.log"; }

# ====================== A: LLM-assisted resolve ladder (develop<->overnight/feature) ======================
newrepo a "develop overnight/feature"
sc a develop "dev edit" "sed -i '2s/.*/dev/' f.txt"
sc a overnight/feature "feat edit" "sed -i '2s/.*/feat/' f.txt"
feat0="$(ohead a overnight/feature)"

reset_logs; touch "$OQ/state/PAUSED"
orun a
ok "A1: PAUSED -> LLM not attempted, reported as conflict" "printf '%s' \"\$OUT\" | grep -q 'CONFLICT develop->overnight/feature' && [ ! -s '$AIDER_LOG' ]"
ok "A1: conflict alert curl fired" "grep -q 'Branch reconcile CONFLICT' '$tmp/curl.log'"
ok "A1: feature untouched" "[ '$(ohead a overnight/feature)' = '$feat0' ]"
rm -f "$OQ/state/PAUSED"

reset_logs; AIDER_MODE=leave orun a
ok "A2: aider leaves markers -> conflict" "printf '%s' \"\$OUT\" | grep -q 'CONFLICT develop->overnight/feature' && [ -s '$AIDER_LOG' ]"
ok "A2: tokens ledger still written (1500/2000)" "grep -q 'reconcile-selfheal w3b.* 1500 2000\|reconcile-selfheal a 1500 2000' '$tmp/tok.log'"

reset_logs; GATE_RC=1 orun a
ok "A3: gate FAIL -> conflict (LLM result rejected)" "printf '%s' \"\$OUT\" | grep -q 'CONFLICT develop->overnight/feature'"
reset_logs; GATE_RC=2 orun a
ok "A3b: gate NOTHING-TO-CHECK also rejected" "printf '%s' \"\$OUT\" | grep -q 'CONFLICT develop->overnight/feature'"
ok "A3: gate log written" "grep -q 'gate called' '$OQ/logs/reconcile_gate_last.log'"
ok "A3: feature still untouched" "[ '$(ohead a overnight/feature)' = '$feat0' ]"

# pushfail after a verified LLM resolve (178-180): every push of HEAD:<tgt> rejected
reset_logs; GIT_SHIM_FAIL="push -q origin HEAD:overnight/feature" orun a
ok "A4: verified LLM resolve but push rejected -> pushfail" "printf '%s' \"\$OUT\" | grep -q 'develop->overnight/feature pushfail'"

# success
reset_logs; orun a
ok "A5: LLM-resolved conflict logged" "printf '%s' \"\$OUT\" | grep -q 'auto-resolved a develop->overnight/feature CONFLICT'"
ok "A5: origin feature now has the resolved file" "[ \"\$(git -C '$tmp/o_a.git' show overnight/feature:f.txt)\" = 'resolved by stub' ]"
ok "A5: feature contains develop" "git -C '$tmp/o_a.git' merge-base --is-ancestor develop overnight/feature"
ok "A5: auto-resolved alert sent" "grep -q 'auto-resolved a conflict' '$tmp/curl.log'"
ok "A5: aider got the conflicted file" "grep -q -- '--file f.txt' '$AIDER_LOG'"
orun a
ok "A6: afterwards in sync" "printf '%s' \"\$OUT\" | grep -q 'in sync'"

# ---- B: more than 3 conflicted files -> no LLM attempt ----
newrepo b "develop overnight/feature"
sc b develop d "for i in 1 2 3 4; do sed -i '2s/.*/dev/' c\$i.txt; done"
sc b overnight/feature f "for i in 1 2 3 4; do sed -i '2s/.*/feat/' c\$i.txt; done"
reset_logs; orun b
ok "B: 4 conflicted files -> straight to conflict, aider not called" "printf '%s' \"\$OUT\" | grep -q 'CONFLICT develop->overnight/feature' && [ ! -s '$AIDER_LOG' ]"

# ---- C: unrelated histories -> merge fails with NO unmerged files ----
newrepo c "develop overnight/feature"
sc c develop d "echo x > dev.txt"
( cd "$tmp/s_c" && git checkout -q --orphan orph && git rm -rfq . && echo o > o.txt && git add -A && git commit -q -m orphan && git push -q -f origin orph:overnight/feature )
reset_logs; orun c
ok "C: merge failure without unmerged files -> conflict, no aider" "printf '%s' \"\$OUT\" | grep -q 'CONFLICT develop->overnight/feature' && [ ! -s '$AIDER_LOG' ]"

# ====================== D: plain merge push ladder ======================
newrepo d "develop overnight/feature"
sc d develop d "echo dev > dev.txt"
sc d overnight/feature f "echo feat > feat.txt"
reset_logs; GIT_SHIM_FAIL_ONCE="push -q origin HEAD:overnight/feature" GIT_SHIM_ONCE_FLAG="$tmp/once_d" orun d
ok "D1: first push rejected, rebase+retry lands it (merged)" "printf '%s' \"\$OUT\" | grep -q 'merged develop->overnight/feature'"
ok "D1: origin feature has both files" "git -C '$tmp/o_d.git' show overnight/feature:dev.txt >/dev/null && git -C '$tmp/o_d.git' show overnight/feature:feat.txt >/dev/null"
newrepo e "develop overnight/feature"
sc e develop d "echo dev > dev.txt"
sc e overnight/feature f "echo feat > feat.txt"
reset_logs; GIT_SHIM_FAIL="push -q origin HEAD:overnight/feature" orun e
ok "D2: plain merge, pushes always rejected -> pushfail" "printf '%s' \"\$OUT\" | grep -q 'develop->overnight/feature pushfail'"

# ====================== F: sync_feature ff rejected 5x -> pushfail ======================
newrepo f "develop overnight/feature"
sc f develop d "echo dev > dev.txt"
reset_logs; GIT_SHIM_FAIL="origin/develop:refs/heads/overnight/feature" orun f
ok "F: fast-forward rejected repeatedly -> pushfail after retries" "printf '%s' \"\$OUT\" | grep -q 'develop->overnight/feature pushfail'"
reset_logs; orun f
ok "F2: without the fault it fast-forwards" "printf '%s' \"\$OUT\" | grep -q 'fast-forwarded overnight/feature to develop'"

# ====================== G: wterror through merge_into (main->develop '*' and develop->feature '*') ======================
newrepo g "develop overnight/feature"
sc g main "direct" "echo hot > hot.txt"
reset_logs; GIT_SHIM_FAIL="worktree add" orun g
ok "G1: main->develop worktree failure reported via generic branch" "printf '%s' \"\$OUT\" | grep -q 'main->develop wterror'"
newrepo h "develop overnight/feature"
sc h develop d "echo dev > dev.txt"
sc h overnight/feature f "echo feat > feat.txt"
reset_logs; GIT_SHIM_FAIL="worktree add" orun h
ok "G2: develop->feature worktree failure reported via generic branch" "printf '%s' \"\$OUT\" | grep -q 'develop->overnight/feature wterror'"

# ====================== H: nochange via a race (feature catches up between the two fetches) ======================
newrepo i "develop overnight/feature"
sc i develop d "echo dev > dev.txt"
cat > "$tmp/hook_i.sh" <<EOF2
cd "$tmp/s_i" && git fetch -q origin && git push -q -f origin origin/develop:refs/heads/overnight/feature
EOF2
reset_logs; TIMEOUT_HOOK="$tmp/hook_i.sh" orun i
ok "H: feature caught up mid-run -> nochange, still counted in sync" "printf '%s' \"\$OUT\" | grep -q 'reconcile complete' && ! printf '%s' \"\$OUT\" | grep -q 'CONFLICT'"

# ====================== I: post-merge sanity variants (main->develop) ======================
mk_both(){ # $1=name $2=file $3=base-content $4=main-sed $5=dev-sed
  newrepo "$1" "develop"
  sc "$1" main base2 "printf '%b' '$3' > $2"
  ( cd "$tmp/s_$1" && git push -q -f origin origin/main:refs/heads/develop )   # one shared base commit (never two timing-dependent twins)
}
# sh syntax
mk_both j t.sh 'echo a\necho b\necho c\necho d\necho e\n'
sc j main m "sed -i '1s/.*/if true; then/' t.sh"; sc j develop d "sed -i '5s/e/f/' t.sh"
reset_logs; orun j
ok "I1: shell syntax error synthesized -> sanityfail (main->develop)" "printf '%s' \"\$OUT\" | grep -q 'main->develop merge would have pushed a BROKEN file'"
ok "I1: reason in sanity log" "grep -q 't.sh: shell syntax error' '$OQ/logs/reconcile_sanity.log'"
ok "I1: sanity alert tag carries (sanity)" "grep -q 'CONFLICT' '$tmp/curl.log'"
# json
mk_both k d.json '{\n"a": 1,\n"b": 2,\n"c": 3,\n"d": 4\n}\n'
sc k main m "sed -i '2s/1,/1/' d.json"; sc k develop d "sed -i '5s/4/5/' d.json"
reset_logs; orun k
ok "I2: invalid json synthesized -> sanityfail" "grep -q 'd.json: invalid json' '$OQ/logs/reconcile_sanity.log'"
# conflict markers in a non-doc file
mk_both l m.cfg 'a\nb\nc\nd\ne\n'
sc l main m "sed -i '1s/.*/=======/' m.cfg"; sc l develop d "sed -i '5s/e/f/' m.cfg"
reset_logs; orun l
ok "I3: marker line in merged .cfg -> sanityfail" "grep -q 'm.cfg: conflict markers' '$OQ/logs/reconcile_sanity.log'"
# same in .md is exempt -> merge proceeds
mk_both m n.md 'a\nb\nc\nd\ne\n'
sc m main m "sed -i '1s/.*/=======/' n.md"; sc m develop d "sed -i '5s/e/f/' n.md"
reset_logs; orun m
ok "I4: marker line in .md exempt -> back-merged" "printf '%s' \"\$OUT\" | grep -q 'back-merged main->develop'"
ok "I4: direct-to-main alert sent" "grep -q 'direct-to-main' '$tmp/curl.log'"
# big + both-deleted files: 200-file cap and the missing-file skip
newrepo n "develop"
( cd "$tmp/s_n" && git checkout -q main && echo gone > a_gone.txt && mkdir -p big && for i in $(seq -w 1 205); do printf 'mid\n' > "big/f$i.txt"; done && git add -A && git commit -q -m files && git push -q origin main && git push -q -f origin main:develop )
sc n main m "git rm -q a_gone.txt; for i in \$(seq -w 1 205); do printf 'top\nmid\n' > big/f\$i.txt; done"
sc n develop d "git rm -q a_gone.txt; for i in \$(seq -w 1 205); do printf 'mid\nbottom\n' > big/f\$i.txt; done"
reset_logs; orun n
ok "I5: 205 co-changed files + both-deleted file: sanity passes (cap + skip), back-merged" "printf '%s' \"\$OUT\" | grep -q 'back-merged main->develop'"

# sanityfail on develop->feature (254)
newrepo o "develop overnight/feature"
sc o develop b "printf 'def f():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n' > mod.py"
( cd "$tmp/s_o" && git push -q -f origin origin/develop:refs/heads/overnight/feature )
sc o develop d "sed -i '5s/4/5/' mod.py"
sc o overnight/feature f "sed -i '1s/.*/x = 0/' mod.py"
reset_logs; orun o
ok "I6: develop->feature synthesized broken python -> sanityfail path" "printf '%s' \"\$OUT\" | grep -q 'develop->overnight/feature merge would have pushed a BROKEN file'"

# ---- main->develop real conflict (alert path, 230) ----
newrepo t "develop"
sc t main m "echo mainside > f.txt"
sc t develop d "echo devside > f.txt"
reset_logs; orun t
ok "I7: main->develop content conflict flagged" "printf '%s' \"\$OUT\" | grep -q 'CONFLICT main->develop'"

# ====================== J: loop guards / DRY / fetch failure ======================
git init -q --bare "$tmp/o_p.git"; git clone -q "$tmp/o_p.git" "$tmp/s_p" 2>/dev/null
( cd "$tmp/s_p" && echo x > x && git add -A && git commit -q -m x && git branch -M main && git push -q origin main )
git clone -q "$tmp/o_p.git" "$OQ/repos/p" 2>/dev/null
reset_logs; orun p
ok "J1: no origin/develop -> silently skipped" "! printf '%s' \"\$OUT\" | grep -q 'in sync' && printf '%s' \"\$OUT\" | grep -q 'reconcile complete'"
git init -q --bare "$tmp/o_q.git"; git clone -q "$tmp/o_q.git" "$tmp/s_q" 2>/dev/null
( cd "$tmp/s_q" && echo x > x && git add -A && git commit -q -m x && git branch -M develop && git push -q origin develop )
git clone -q "$tmp/o_q.git" "$OQ/repos/q" 2>/dev/null
orun q
ok "J2: no origin/main -> silently skipped" "! printf '%s' \"\$OUT\" | grep -q 'in sync'"
git clone -q "$tmp/o_q.git" "$OQ/repos/r" 2>/dev/null; git -C "$OQ/repos/r" remote set-url origin "$tmp/does-not-exist.git"
orun r
ok "J3: fetch failure logged" "printf '%s' \"\$OUT\" | grep -q 'r: fetch failed/timed out'"
mkdir -p "$OQ/repos/notgit"; orun notgit
ok "J4: non-git dir skipped" "printf '%s' \"\$OUT\" | grep -q 'reconcile complete'"

newrepo s "develop overnight/feature"
sc s main direct "echo hot > hot.txt"
sc s develop d "echo dev > dev.txt"
OUT="$( cd "$OQ" && DRY_RUN=1 PATH="$tmp/shim:$PATH" bash ./reconcile_branches.sh repos/s 2>&1 )"
ok "J5: DRY back-merge reported" "printf '%s' \"\$OUT\" | grep -q '\[dry\] back-merge main->develop'"
ok "J5: DRY feature sync reported" "printf '%s' \"\$OUT\" | grep -q '\[dry\] reconcile develop->overnight/feature'"
ok "J5: DRY pushed nothing" "[ \"\$(ohead s main)\" != \"\$(ohead s develop)\" ]"

# default repo list (no args): none of the default repos exist in the fixture
OUT="$( cd "$OQ" && PATH="$tmp/shim:$PATH" bash ./reconcile_branches.sh 2>&1 )"
ok "J6: default repo list with absent repos is a clean no-op" "printf '%s' \"\$OUT\" | grep -q 'reconcile complete'"

# ====================== K: merge_sanity_ok called directly ======================
( cd "$OQ" && source ./reconcile_branches.sh >/dev/null 2>&1
  R="$OQ/repos/q"
  # unrelated origin/develop vs origin/main -> merge-base fails -> tolerated
  git -C "$R" fetch -q origin
  git init -q --bare "$tmp/o_u.git"; git clone -q "$tmp/o_u.git" "$tmp/s_u" 2>/dev/null
  ( cd "$tmp/s_u" && echo m > m && git add -A && git commit -q -m m && git branch -M main && git push -q origin main )
  git -C "$R" remote add u "$tmp/o_u.git"; git -C "$R" fetch -q u main:refs/remotes/origin/main
  merge_sanity_ok "$R" develop main >/dev/null; echo "rc_unrelated=$?" > "$tmp/k.out"
  OVN_MERGE_SANITY=off merge_sanity_ok "$R" develop main >/dev/null; echo "rc_off=$?" >> "$tmp/k.out" )
ok "K1: merge_sanity_ok with unrelated histories returns 0" "grep -q rc_unrelated=0 '$tmp/k.out'"
ok "K2: kill switch returns 0" "grep -q rc_off=0 '$tmp/k.out'"

echo "$P passed, $F failed"
[ "$F" -eq 0 ]
