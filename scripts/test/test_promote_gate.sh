#!/usr/bin/env bash
# Tests for the 2026-10-02 additions to promote_to_prod.sh / daily_promote.sh (qa/h4-promotegate):
#   (1) the staging-evidence gate (qa/promote_gate.py): blocks ONE repo only when staging_check is in `enforce` AND the verdict is a FAIL;
#   (2) the release-branch flow behind the kill switch OVN_RELEASE_FLOW=on (default OFF): fast-forward main to the release CANDIDATE, never a merge, never a force push.
# Runs the REAL promote_to_prod.sh / daily_promote.sh against throwaway bare origins + clones under a fake HOME, as cron would:
# `env -i` with a minimal PATH and NTFY_SERVER pointing at a closed local port (nothing here can reach ntfy.sh or any network).
# Overridable for "does this test fail on the OLD code" proofs: OVN_PROMOTE_TO_PROD=<path> (and OVN_DAILY_PROMOTE=<path>).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ="$HERE/../.."; [ -f "$OQ/promote_to_prod.sh" ] || OQ="$HERE/.."
P2P="${OVN_PROMOTE_TO_PROD:-$OQ/promote_to_prod.sh}"; DPR="${OVN_DAILY_PROMOTE:-$OQ/daily_promote.sh}"; QA="$OQ/qa"
[ -f "$P2P" ] && [ -f "$DPR" ] && [ -f "$QA/promote_gate.py" ] || { echo "  SKIP: promote scripts / qa/promote_gate.py not found"; exit 0; }
PYB="$(command -v python3.12 || command -v python3)"; [ -n "$PYB" ] || { echo "  SKIP: no python3"; exit 0; }
pass=0; fail=0
ck(){ if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export HOME="$T/home"; Q="$HOME/overnight-queue"; OUT="$T/out.log"
# macOS has no timeout(1) and the promote script calls it: a pass-through shim (only when the real one is missing) keeps this test runnable on the Mac.
mkdir -p "$T/shim"
command -v timeout >/dev/null || { printf '#!/bin/sh\nshift\nexec "$@"\n' > "$T/shim/timeout"; chmod +x "$T/shim/timeout"; }
printf '#!/bin/sh\necho "CURL_CALL $*" >> "$FAKE_CURL_LOG"\nexit 0\n' > "$T/shim/curl"; chmod +x "$T/shim/curl"
ENVPATH="$T/shim:$(dirname "$PYB"):/usr/bin:/bin:/usr/local/bin"
EXTRA=()
GREEN="chore(overnight): reconcile overnight/feature into develop (branch-hygiene, gate=tests-green)"

setup(){  # fresh fake tree with the REAL qa helpers copied in (what the box has under ~/overnight-queue/qa)
  rm -rf "$T/home" "$T/origin" "$T/seed"; mkdir -p "$Q/state" "$Q/scripts" "$Q/qa" "$Q/repos" "$T/origin" "$T/seed"
  for f in qa_common release_candidate staging_check promote_gate qa_timeout; do cp "$QA/$f.py" "$Q/qa/"; done
  cp "$P2P" "$Q/promote_to_prod.sh"; : > "$T/curl.log"; EXTRA=()
  printf 'import sys\nsys.exit(0)\n' > "$Q/scripts/check_migrations.py"
}
mkrepo(){  # $1=name $2=layout: green (tip is a green hygiene merge) | nongreen (a direct, ungated commit on top of the green merge) | diverged (hotfix on main, not in develop)
  local n="$1" lay="${2:-green}" o="$T/origin/$1.git" s="$T/seed/$1"
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s" && echo base > f.txt && git add f.txt && git commit -q -m base && git branch -M main && git push -q origin main
    git checkout -q -b side && echo side > side.txt && git add side.txt && git commit -q -m "side work" && git push -q origin side
    git checkout -q main && git checkout -q -b develop && git checkout -q -b feat1 && echo f1 > feat1.txt && git add feat1.txt && git commit -q -m "feat: one" \
      && git checkout -q develop && git merge -q --no-ff -m "$GREEN" feat1
    [ "$lay" = nongreen ] && { echo m > manual.txt && git add manual.txt && git commit -q -m "fix: manual direct commit"; }
    git push -q origin develop
    [ "$lay" = diverged ] && { git checkout -q main && echo hot > hot.txt && git add hot.txt && git commit -q -m "hotfix on main" && git push -q origin main; }
    true )
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
}
sha(){ git -C "$T/origin/$1.git" rev-parse "$2" 2>/dev/null; }
snap(){  # $1=repo, rest = STATUS:sha newest first; SNAP_AGE seconds old (default 0); SNAP_RAW overrides the file content
  mkdir -p "$Q/state/staging_deploys"
  if [ -n "${SNAP_RAW:-}" ]; then printf '%s' "$SNAP_RAW" > "$Q/state/staging_deploys/$1.json"; return; fi
  local r="$1"; shift
  "$PYB" - "$Q/state/staging_deploys/$r.json" "${SNAP_AGE:-0}" "$@" <<'PY'
import json, sys, time
path, age, specs = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
deps = []
for i, sp in enumerate(specs):
    st, sh = sp.split(":", 1)
    deps.append({"id": "dep%05d" % i, "status": st, "createdAt": "2026-10-02T08:%02d:00Z" % (59 - i), "meta": {"commitHash": sh, "branch": "develop"}})
json.dump({"repo": "x", "fetched_at": time.time() - age, "deployments": deps}, open(path, "w"))
PY
}
runp(){  # real promote_to_prod.sh under env -i, as cron would
  env -i HOME="$HOME" PATH="$ENVPATH" NTFY_SERVER=http://127.0.0.1:9 FAKE_CURL_LOG="$T/curl.log" \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    ${EXTRA[@]+"${EXTRA[@]}"} bash "$Q/promote_to_prod.sh" "$@" > "$OUT" 2>&1 < /dev/null; echo $? > "$T/rc"
}
has(){ grep -qF -- "$1" "$OUT"; }
alerts(){ local n=0; [ -f "$Q/state/alerts.log" ] && n="$(grep -c 'promote-staging-gate' "$Q/state/alerts.log")"; echo "$n"; }
norm(){ sed -E "s/[0-9]{8}-[0-9]{4}/NOW/g; s#$T#T#g; s/[0-9a-f]{7,40}/SHA/g"; }
nreleases(){ git -C "$T/origin/$1.git" for-each-ref --format='%(refname)' refs/heads/release | wc -l | tr -d ' '; }

# ===== (1) staging-evidence gate =====
# explicit shadow (the rollback state): a BEHIND staging is logged, never blocks; today's merge promote happens.
# (2026-10-03, A3: with NOTHING set the promote gate now ENFORCES - see the "default = enforce" block below.)
setup; mkrepo app green; c="$(sha app develop)"; snap app "SUCCESS:$(sha app main)"; EXTRA=(OVN_QA_STAGING_CHECK=shadow); runp --yes "$Q/repos/app"
ck "explicit shadow: BEHIND staging still promotes (merge)" "has 'PROMOTED app develop -> main'"
ck "explicit shadow: evidence lines in the promote log" "has '[candidate] ${c:0:10}' && has '[staging-gate] mode=shadow staging_check=FAIL/MISMATCH_BEHIND' && has '-> proceed'"
ck "explicit shadow: no alert written" "[ \"\$(alerts)\" = 0 ]"
ck "explicit shadow: main is a merge commit with develop as parent 2 (today's behaviour)" "[ \"\$(git -C $T/origin/app.git rev-list --parents -n1 main | wc -w | tr -d ' ')\" = 3 ] && [ \"\$(git -C $T/origin/app.git rev-parse main^2)\" = $c ]"
ck "explicit shadow: no release branch created" "[ \"\$(nreleases app)\" = 0 ]"

# enforce + each FAIL relation => THIS repo skipped, one WARN, main untouched
for rel in BEHIND DIVERGED FAILED; do
  setup; mkrepo app green; m0="$(sha app main)"; EXTRA=(OVN_QA_STAGING_CHECK=enforce)
  case "$rel" in BEHIND) snap app "SUCCESS:$m0";; DIVERGED) snap app "SUCCESS:$(sha app side)";; FAILED) snap app "FAILED:$(sha app develop)" "SUCCESS:$m0";; esac
  runp --yes "$Q/repos/app"
  ck "enforce+$rel: skipped with STAGING-GATE BLOCK, main untouched, not PROMOTED" "has 'STAGING-GATE BLOCK' && ! has PROMOTED && [ \"\$(sha app main)\" = $m0 ]"
  ck "enforce+$rel: evidence line says BLOCK with the relation" "has 'MISMATCH_$rel' && has '-> BLOCK'"
  ck "enforce+$rel: exactly one WARN in alerts.log" "[ \"\$(alerts)\" = 1 ] && grep -q 'WARN | promote-staging-gate | app promote SKIPPED' $Q/state/alerts.log"
  ck "enforce+$rel: no tag pushed" "[ -z \"\$(git -C $T/origin/app.git tag -l 'prod-*')\" ]"
done
# benign controls under enforce: PASS / NA / every UNVERIFIED flavour must NEVER block
benign(){  # $1=label ; expects the caller to have set up the fixture; asserts it promoted
  runp --yes "$Q/repos/app"
  ck "enforce+$1: promotes (never blocks)" "has 'PROMOTED app' && ! has 'STAGING-GATE BLOCK' && [ \"\$(alerts)\" = 0 ]"
}
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:$(sha app develop)"; benign "MATCH"
ck "enforce+MATCH: evidence says PASS/MATCH" "has 'staging_check=PASS/MATCH'"
setup; mkrepo app nongreen; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:$(sha app develop)"; benign "MATCH_SUPERSET (staging serves tip, candidate older)"
ck "enforce+SUPERSET: candidate is the green merge, not the tip, 1 held back" "has '[candidate] $(sha app develop~1 | cut -c1-10)' && has '1 develop merge(s) held back'"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); benign "NA (no snapshot / no staging backend)"
ck "enforce+NA: evidence names NA" "has 'staging_check=NA'"
# 2026-10-03 (A3): a stale / missing / corrupt exported deploy list for a repo WITH staging now FAILS CLOSED in enforce mode
setup; mkrepo app green; m0="$(sha app main)"; EXTRA=(OVN_QA_STAGING_CHECK=enforce); SNAP_AGE=7200 snap app "SUCCESS:$m0"; runp --yes "$Q/repos/app"
ck "enforce+stale snapshot (2h old): BLOCKED fail-closed, main untouched" "has 'STAGING-GATE BLOCK' && has 'EVIDENCE_STALE' && ! has PROMOTED && [ \"\$(sha app main)\" = $m0 ] && [ \"\$(alerts)\" = 1 ]"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=shadow); SNAP_AGE=7200 snap app "SUCCESS:$(sha app main)"; runp --yes "$Q/repos/app"
ck "shadow+stale snapshot: promotes, but says UNVERIFIED (never silent)" "has 'PROMOTED app' && has '[unverified] staging gate could not verify app: EVIDENCE_STALE' && [ \"\$(alerts)\" = 0 ]"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "BUILDING:$(sha app develop)" "SUCCESS:$(sha app main)"; m0="$(sha app main)"; runp --yes "$Q/repos/app"
ck "enforce+candidate deploy still BUILDING: HELD (transient, reason BUILDING): the smoke would hit the OLD build" "has 'STAGING-GATE BLOCK' && has '(BUILDING)' && ! has PROMOTED && [ \"\$(sha app main)\" = $m0 ]"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "BUILDING:0123456789abcdef0123456789abcdef01234567" "SUCCESS:$(sha app main)"; benign "deploy BUILDING an unknown/unrelated commit"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:0123456789abcdef0123456789abcdef01234567"; benign "staging commit unknown to the clone"
setup; mkrepo app green; m0="$(sha app main)"; EXTRA=(OVN_QA_STAGING_CHECK=enforce); SNAP_RAW='{not json' snap app; runp --yes "$Q/repos/app"
ck "enforce+corrupt snapshot file: unusable evidence for a staged repo => BLOCKED fail-closed" "has 'STAGING-GATE BLOCK' && has 'EVIDENCE_MISSING' && [ \"\$(sha app main)\" = $m0 ]"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:$(sha app main)"; printf 'import sys\nsys.exit(3)\n' > "$Q/qa/promote_gate.py"; benign "helper crashes (exit 3, no output)"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:$(sha app main)"; printf 'print("garbage")\n' > "$Q/qa/promote_gate.py"; benign "helper prints garbage"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:$(sha app main)"; printf 'import time\ntime.sleep(30)\n' > "$Q/qa/promote_gate.py"; EXTRA+=(OVN_PROMOTE_GATE_TIMEOUT=2); benign "helper hangs (bounded by qa_timeout)"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:$(sha app main)"; rm -rf "$Q/qa"; benign "qa/ dir absent entirely (older checkout)"
ck "no qa/ dir: no evidence lines, output unchanged" "! has '[staging-gate]'"
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=off); snap app "SUCCESS:$(sha app main)"; benign "mode=off"
# --force overrides an enforced block (a human decision), loudly
setup; mkrepo app green; EXTRA=(OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:$(sha app main)"; runp --yes --force "$Q/repos/app"
ck "--force overrides the enforced block with a warning" "has 'would block app but --force given' && has 'PROMOTED app' && [ \"\$(alerts)\" = 0 ]"

# mode sources: state/qa_gate_modes.json (when present), env wins over it, junk falls back to shadow
setup; mkrepo app green; m0="$(sha app main)"; snap app "SUCCESS:$m0"; echo '{"staging_check":"enforce"}' > "$Q/state/qa_gate_modes.json"; runp --yes "$Q/repos/app"
ck "qa_gate_modes.json enforce (no env) blocks" "has 'STAGING-GATE BLOCK' && [ \"\$(sha app main)\" = $m0 ]"
setup; mkrepo app green; snap app "SUCCESS:$(sha app main)"; echo '{"modes":{"staging_check":{"mode":"enforce"}}}' > "$Q/state/qa_gate_modes.json"; runp --yes "$Q/repos/app"
ck "qa_gate_modes.json nested {modes:{gate:{mode}}} also read" "has 'STAGING-GATE BLOCK'"
setup; mkrepo app green; snap app "SUCCESS:$(sha app main)"; echo '{"staging_check":"enforce"}' > "$Q/state/qa_gate_modes.json"; EXTRA=(OVN_QA_STAGING_CHECK=shadow); runp --yes "$Q/repos/app"
ck "env shadow overrides modes file enforce (one-command rollback)" "has 'PROMOTED app' && has 'mode=shadow'"
setup; mkrepo app green; snap app "SUCCESS:$(sha app main)"; echo 'nonsense{' > "$Q/state/qa_gate_modes.json"; runp --yes "$Q/repos/app"
ck "corrupt modes file => falls through to the default (enforce), BLOCKS - an unreadable flip file never silently disables the gate" "has 'STAGING-GATE BLOCK' && has 'mode=enforce'"
setup; mkrepo app green; snap app "SUCCESS:$(sha app main)"; echo '{"staging_check":"enforce"}' > "$Q/state/qa_modes.json"; runp --yes "$Q/repos/app"
ck "qa_modes.json (qa_common's own file) enforce is honoured too" "has 'STAGING-GATE BLOCK'"

# dry-run shows evidence, writes nothing
setup; mkrepo app green; m0="$(sha app main)"; snap app "SUCCESS:$m0"; EXTRA=(OVN_QA_STAGING_CHECK=shadow); runp --dry-run "$Q/repos/app"
ck "dry-run: evidence shown, main untouched, today's dry-run line" "has '[staging-gate]' && has '[dry-run] would merge develop -> main' && [ \"\$(sha app main)\" = $m0 ]"

# daily_promote.sh: each repo independent; held repo reported; evidence lines kept in the log
setup; mkrepo gA green; mkrepo gB green; mA="$(sha gA main)"; EXTRA=(OVN_QA_STAGING_CHECK=enforce)
snap gA "SUCCESS:$mA"; snap gB "SUCCESS:$(sha gB develop)"; cp "$DPR" "$Q/daily_promote.sh"
env -i HOME="$HOME" PATH="$ENVPATH" NTFY_SERVER=http://127.0.0.1:9 FAKE_CURL_LOG="$T/curl.log" NTFY_TOPIC=selftest_ignore OVN_PROMOTE_REPOS='gA gB' OVN_QA_STAGING_CHECK=enforce OVN_PROMOTE_RETRY_S=1 \
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null bash "$Q/daily_promote.sh" > "$OUT" 2>&1 < /dev/null
ck "daily: held repo gA skipped, main untouched" "[ \"\$(sha gA main)\" = $mA ]"
ck "daily: the OTHER repo gB still promoted (one skip != skip all)" "grep -q 'Promoted: gB' $OUT && git -C $T/origin/gB.git merge-base --is-ancestor develop main"
ck "daily: summary names the held repo with a HELD line, high priority" "grep -q 'HELD.*gA' $OUT && grep -q 'Priority: high' $T/curl.log"
ck "daily: gA not listed as Promoted" "! grep -qE 'Promoted:.*gA' $OUT"
# gA is BEHIND (transient) => daily_promote retries it once (OVN_PROMOTE_RETRY_S=1), so its evidence appears twice: 3 lines in total
ck "daily: candidate + staging evidence lines for both repos are in the log (held gA twice: first pass + retry)" "[ \"\$(grep -c '^  \[candidate\]' $OUT)\" = 3 ] && [ \"\$(grep -c '^  \[staging-gate\]' $OUT)\" = 3 ] && grep -q 'retry in 1s' $OUT"
ck "daily: one WARN for gA only" "[ \"\$(alerts)\" = 1 ] && grep -q 'gA promote SKIPPED' $Q/state/alerts.log"
# daily with nothing held (staging serves the candidate): no HELD line, normal priority
setup; mkrepo gA green; snap gA "SUCCESS:$(sha gA develop)"; cp "$DPR" "$Q/daily_promote.sh"
env -i HOME="$HOME" PATH="$ENVPATH" NTFY_SERVER=http://127.0.0.1:9 FAKE_CURL_LOG="$T/curl.log" NTFY_TOPIC=selftest_ignore OVN_PROMOTE_REPOS='gA' \
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null bash "$Q/daily_promote.sh" > "$OUT" 2>&1 < /dev/null
ck "daily green: promoted, no HELD line, default priority" "grep -q 'Promoted: gA' $OUT && ! grep -q HELD $OUT && grep -q 'Priority: default' $T/curl.log"

# ===== (2) release-branch flow, kill switch OVN_RELEASE_FLOW=on =====
# OFF (unset / off / anything but exactly "on") = today's merge promote, byte-for-byte the same result
offstate(){ git -C "$T/origin/$1.git" rev-parse "main^{tree}"; git -C "$T/origin/$1.git" log -1 --format='%s' main | sed -E 's/[0-9]{8}-[0-9]{4}/NOW/'; git -C "$T/origin/$1.git" rev-list --parents -n1 main | wc -w | tr -d ' '; git -C "$T/origin/$1.git" for-each-ref --format='%(refname)' refs/heads | sort | tr '\n' ' '; git -C "$T/origin/$1.git" tag -l | sed -E 's/[0-9]{8}-[0-9]{4}/NOW/' | tr '\n' ' '; }
setup; mkrepo app nongreen; runp --yes "$Q/repos/app"; base_state="$(offstate app)"; base_out="$(grep -vE '^  \[(candidate|staging-gate)\]' "$OUT" | norm)"
ck "OFF (unset): merge commit 'release: promote develop -> main', no release branch" "has 'PROMOTED app develop -> main (+3). Prod deploy triggered' && [ \"\$(nreleases app)\" = 0 ] && git -C $T/origin/app.git log -1 --format=%s main | grep -q 'release: promote develop -> main'"
for v in off shadow enforce ON 1 true ""; do
  setup; mkrepo app nongreen; EXTRA=(OVN_RELEASE_FLOW="$v"); runp --yes "$Q/repos/app"
  o="$(grep -vE '^  \[(candidate|staging-gate)\]' "$OUT" | norm)"; same=0
  [ "$(offstate app)" = "$base_state" ] && [ "$o" = "$base_out" ] && same=1
  ck "OVN_RELEASE_FLOW='$v' is OFF: identical result tree/message/refs/tags and output as unset" "[ $same = 1 ]"
done
# ON: ff to the candidate (green merge), NOT develop's tip with a non-green commit on top
setup; mkrepo app nongreen; cand="$(sha app develop~1)"; tip="$(sha app develop)"; m0="$(sha app main)"; EXTRA=(OVN_RELEASE_FLOW=on); runp --yes "$Q/repos/app"
ck "ON: PROMOTED via fast-forward to the release candidate" "has 'PROMOTED app develop -> main (+3, fast-forward to release candidate ${cand:0:10} via release/'"
ck "ON: main == candidate exactly, NOT develop's tip" "[ \"\$(sha app main)\" = $cand ] && [ \"\$(sha app main)\" != $tip ] && ! git -C $T/origin/app.git merge-base --is-ancestor $tip main"
ck "ON: pure fast-forward (old main is an ancestor, no merge commit, no 'release: promote' subject)" "git -C $T/origin/app.git merge-base --is-ancestor $m0 main && ! git -C $T/origin/app.git log -1 --format=%s main | grep -q 'release: promote'"
ck "ON: release/YYYYMMDD branch exists on origin at the candidate" "[ \"\$(nreleases app)\" = 1 ] && [ \"\$(git -C $T/origin/app.git rev-parse refs/heads/release/$(date +%Y%m%d))\" = $cand ]"
ck "ON: prod rollback tag pushed at the candidate; rollback hint printed" "t=\$(git -C $T/origin/app.git tag -l 'prod-*-app'); [ -n \"\$t\" ] && [ \"\$(git -C $T/origin/app.git rev-parse \"\$t^{commit}\")\" = $cand ] && has \"Rollback: git checkout \$t\""
ck "ON: evidence lines say 1 held back and main is fast-forwardable" "has '1 develop merge(s) held back' && has 'main fast-forwardable: yes'"
runp --yes "$Q/repos/app"
ck "ON: re-run with only an ungated commit left ahead: not promoted again, main stays at the candidate" "! has PROMOTED && [ \"\$(sha app main)\" = $cand ]"
# ON, tip is itself the green merge: main == develop tip
setup; mkrepo app green; tip="$(sha app develop)"; EXTRA=(OVN_RELEASE_FLOW=on); runp --yes "$Q/repos/app"
ck "ON green tip: main == develop tip, fast-forward" "[ \"\$(sha app main)\" = $tip ] && has 'fast-forward to release candidate ${tip:0:10}'"
# ON + dry-run: nothing written
setup; mkrepo app nongreen; m0="$(sha app main)"; EXTRA=(OVN_RELEASE_FLOW=on); runp --dry-run "$Q/repos/app"
ck "ON dry-run: says fast-forward, origin untouched (no branch, no tag, main same)" "has '[dry-run] release flow ON: would fast-forward main to candidate' && [ \"\$(sha app main)\" = $m0 ] && [ \"\$(nreleases app)\" = 0 ] && [ -z \"\$(git -C $T/origin/app.git tag -l)\" ]"
# ON, hotfix on main not in develop: no candidate contains main => never promotes, never rewrites main
setup; mkrepo app diverged; m0="$(sha app main)"; EXTRA=(OVN_RELEASE_FLOW=on); runp --yes "$Q/repos/app"
ck "ON diverged main: NOT promoted, main untouched, no release branch, no tag" "has 'NOT promoting app' && ! has PROMOTED && [ \"\$(sha app main)\" = $m0 ] && [ \"\$(nreleases app)\" = 0 ] && [ -z \"\$(git -C $T/origin/app.git tag -l)\" ]"
setup; mkrepo app diverged; EXTRA=(OVN_RELEASE_FLOW=off); runp --yes "$Q/repos/app"
ck "OFF diverged main (control): today's merge flow still promotes it (merge of develop into main)" "has 'PROMOTED app'"
# ON + enforced staging FAIL: blocked before any branch/main write
setup; mkrepo app nongreen; m0="$(sha app main)"; EXTRA=(OVN_RELEASE_FLOW=on OVN_QA_STAGING_CHECK=enforce); snap app "SUCCESS:$m0"; runp --yes "$Q/repos/app"
ck "ON + enforce BEHIND: blocked, no release branch, main untouched" "has 'STAGING-GATE BLOCK' && [ \"\$(nreleases app)\" = 0 ] && [ \"\$(sha app main)\" = $m0 ]"
# ON, main push refused by the server: reported, main untouched, not PROMOTED
setup; mkrepo app nongreen; m0="$(sha app main)"; EXTRA=(OVN_RELEASE_FLOW=on)
printf '#!/bin/sh\nwhile read o n r; do [ "$r" = refs/heads/main ] && exit 1; done\nexit 0\n' > "$T/origin/app.git/hooks/pre-receive"; chmod +x "$T/origin/app.git/hooks/pre-receive"
runp --yes "$Q/repos/app"
ck "ON, main push rejected: 'push failed', not PROMOTED, main untouched" "has 'push failed' && ! has PROMOTED && [ \"\$(sha app main)\" = $m0 ]"
# ON, main MOVES between the plan and the push (a hotfix lands right after the release branch is created): git refuses the non-ff push, no force
setup; mkrepo app green; m0="$(sha app main)"; EXTRA=(OVN_RELEASE_FLOW=on)
cat > "$T/origin/app.git/hooks/post-receive" <<'HOOK'
#!/bin/sh
# after the release branch lands, a "hotfix" appears on main (a new commit whose parent is the old main)
while read o n r; do case "$r" in refs/heads/release/*)
  m=$(git rev-parse refs/heads/main); t=$(git rev-parse "$m^{tree}")
  h=$(GIT_AUTHOR_NAME=h GIT_AUTHOR_EMAIL=h@h GIT_COMMITTER_NAME=h GIT_COMMITTER_EMAIL=h@h git commit-tree "$t" -p "$m" -m "hotfix lands mid-promote")
  git update-ref refs/heads/main "$h" "$m";; esac; done
HOOK
chmod +x "$T/origin/app.git/hooks/post-receive"; runp --yes "$Q/repos/app"
hf="$(sha app main)"
ck "ON, main moved mid-promote: push refused (no force), hotfix on main NOT overwritten, not PROMOTED" "[ \"\$hf\" != $m0 ] && git -C $T/origin/app.git log -1 --format=%s main | grep -q 'hotfix lands mid-promote' && has 'push failed' && ! has PROMOTED"
ck "ON, main moved mid-promote: no prod tag pushed" "[ -z \"\$(git -C $T/origin/app.git tag -l 'prod-*')\" ]"
# static guarantee: the ON block never uses a force push / '+' refspec
blk="$(awk '/RELEASE_FLOW" -eq 1 \]; then$/,/^  fi$/' "$P2P")"
ck "ON block located in the script (guard against a vacuous grep)" "echo \"\$blk\" | grep -q 'refs/heads/\$DEF'"
ck "ON block contains no --force / -f / --force-with-lease / '+refspec' pushes" "! echo \"\$blk\" | grep -E 'push[^|]*(--force| -f |\\+[a-zA-Z\$])'"

echo "promote gate + release flow: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
