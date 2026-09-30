#!/usr/bin/env bash
# Runs the REAL branch_hygiene.sh against throwaway bare origins + clones. Gate tools (pytest/npm/gradlew/godot/docker),
# curl and a git wrapper (to inject worktree failures) are stub executables first on PATH; HOME is a fake tree that holds a
# fake check_migrations.py. STATE_DIR/REPORT_FILE point into the fixture. Nothing real is touched or pushed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BH="$HERE/../../branch_hygiene.sh"; [ -f "$BH" ] || BH="$HERE/../branch_hygiene.sh"
[ -f "$BH" ] || { echo "  SKIP: branch_hygiene.sh not found"; exit 0; }
for t in flock timeout jq; do command -v $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = 1 ]; then pass=$((pass+1)); else echo "  WARN KNOWN-BUG: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(mktemp -d)"; export T; trap 'rm -rf "$T"' EXIT
REALGIT="$(command -v git)"; export REALGIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; export STATE_DIR="$T/state"; export REPORT_FILE="$T/report.md"; OUT="$T/out.log"
BIN="$T/bin"; mkdir -p "$BIN"
mkstub(){ printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
mkstub curl 'echo "curl $*" >> "$T/curl.log"; exit 0'
mkstub git 'if [ -n "${FAIL_WT:-}" ] && [ "$3" = worktree ] && [ "$4" = add ]; then case "$*" in *"$FAIL_WT"*) exit 1;; esac; fi
exec "$REALGIT" "$@"'
# npm: behaviour driven by marker files in the package dir (cwd)
mkstub npm 'echo "npm $* (cwd=$PWD)" >> "$T/npm.log"
case "$1 $2" in
  "ci --no-audit"*|"install --no-audit"*) exit 0;;
  "run build") [ -f build_slow.flag ] && { sleep 5; exit 0; }; [ -f build_red.flag ] && exit 1; exit 0;;
esac
[ "$1" = test ] && { [ -f test_red.flag ] && exit 1; exit 0; }
exit 0'
# pytest in the clone's .venv; count calls; red.flag => fail; slow_once.flag => hang on first call only
PYTEST_BODY='echo "pytest $*" >> "$T/pytest.log"; echo "cwd=$PWD" >> "$T/pytest.log"
if [ -f slow_first.flag ]; then c="$T/slowcount"; n=$(cat "$c" 2>/dev/null || echo 0); echo $((n+1)) > "$c"; [ "$n" = 0 ] && sleep 6; fi
if [ -f slow_always.flag ]; then sleep 6; fi
[ -f red.flag ] && { echo "1 failed"; exit 1; }; echo ". passed"; exit 0'
mkstub docker 'echo "docker $*" >> "$T/docker.log"; [ "$1" = build ] && { [ -f "$PWD/docker_red.flag" ] && exit 1; [ -f "$PWD/docker_slow.flag" ] && sleep 6; }; exit 0'

setup(){ # fresh fixture tree
  rm -rf "$T/home" "$T/origin" "$T/seed" "$T/repos" "$T/state" "$T/report.md" "$T"/*.log "$T/slowcount" "$T/godot_mode"
  mkdir -p "$HOME/overnight-queue/scripts" "$T/origin" "$T/seed" "$T/repos" "$STATE_DIR"
  cat > "$HOME/overnight-queue/scripts/check_migrations.py" <<'PY'
import os, sys
if os.path.exists(os.path.expanduser("~/mig_fail")): sys.exit(1)
PY
  unset FAIL_WT HYGIENE_MERGE_TARGET HYGIENE_FEATURE_BRANCH AUTO_MERGE_DEFAULT DRY_RUN KEEP_DAYS TEST_TIMEOUT OVN_XDIST_REPOS HYGIENE_LOCK_WAIT NTFY_TOPIC LOCK_ALERT_COOLDOWN_SECS
}
# mk <name> <kind> [nfeat]: kinds (files on main so every branch has them): py | none | web | webnotest | vscode | gradle | godot | shellbad | docker | dockerchg
mk(){
  local n="$1" kind="$2" nf="${3:-2}" o="$T/origin/$1.git" s="$T/seed/$1" i
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt
    case "$kind" in
      py) mkdir -p pkg; echo "def t(): pass" > pkg/test_x.py;;
      web) mkdir -p web; echo '{"scripts":{"build":"x","test":"y"}}' > web/package.json;;
      webnotest) mkdir -p web; echo '{"scripts":{"build":"x"}}' > web/package.json;;
      webtestonly) mkdir -p web; echo '{"scripts":{"test":"y"}}' > web/package.json;;
      webnone) mkdir -p web; echo '{"scripts":{}}' > web/package.json;;
      vscode) mkdir -p vscode-extension; echo '{"scripts":{"build":"x","test":"y"}}' > vscode-extension/package.json;;
      gradle) mkdir -p android; printf '#!/bin/sh\necho "gradlew $*" >> "$T/gradle.log"\nif [ -f ../gradle_daemon.flag ] && [ ! -f "$T/gd_done" ]; then touch "$T/gd_done"; echo "Gradle build daemon disappeared unexpectedly"; exit 1; fi\n[ -f ../gradle_red.flag ] && exit 1\nexit 0\n' > android/gradlew; chmod +x android/gradlew; echo "" > android/settings.gradle.kts;;
      godot) echo "x" > project.godot; mkdir -p addons/gut; echo "x" > addons/gut/gut_cmdln.gd;;
      shellbad) echo 'if then fi ((' > bad.sh;;
      shellok) echo 'echo hi' > good.sh;;
      docker|dockerchg) mkdir -p svc; echo "FROM scratch" > svc/Dockerfile;;
    esac
    git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature
    for i in $(seq 1 "$nf"); do echo "feat$i" > "feat$i.txt"; git add -A; git commit -q -m "feat: $i"; done
    git push -q origin overnight/feature
    git checkout -q develop; git branch claude/feature; git push -q origin claude/feature
    [ "$kind" = dockerchg ] && { git checkout -q overnight/feature; echo "RUN echo hi" >> svc/Dockerfile; git commit -qam "docker change"; git push -q origin overnight/feature; } )
  git clone -q "$o" "$T/repos/$n" 2>/dev/null
  git -C "$T/repos/$n" config user.email t@t; git -C "$T/repos/$n" config user.name t
  [ "$kind" = py ] && { mkdir -p "$T/repos/$n/.venv/bin"; printf '#!/usr/bin/env bash\n%s\n' "$PYTEST_BODY" > "$T/repos/$n/.venv/bin/pytest"; chmod +x "$T/repos/$n/.venv/bin/pytest"; }
  return 0
}
flagfile(){ # commit a marker file onto overnight/feature (so the worktree of the feature branch has it)
  local n="$1" f="$2" sub="${3:-.}" s="$T/seed/$1"; ( cd "$s"; git checkout -q overnight/feature; mkdir -p "$sub"; echo 1 > "$sub/$f"; git add -A; git commit -q -m "flag $f"; git push -q origin overnight/feature; git checkout -q develop ); git -C "$T/repos/$n" fetch -q origin; }
sha(){ git -C "$T/origin/$1.git" rev-parse --verify -q "$2" 2>/dev/null; true; }
run(){ ( cd "$T" && PATH="$BIN:$PATH" bash "$BH" "$@" > "$OUT" 2>&1 ); echo $? > "$T/rc"; }
merged(){ git -C "$T/origin/$1.git" merge-base --is-ancestor "${3:-overnight/feature}" "${2:-develop}" && echo 1 || echo 0; }
flag(){ echo "$STATE_DIR/branch_hygiene_review_$1"; }

# ===== repo list resolution =====
setup; run
ok "no args -> 'no repos to process' exit 0" "$([ "$(cat $T/rc)" = 0 ] && [ "$(has $OUT 'no repos to process')" = 1 ] && echo 1 || echo 0)"
run --from-config
ok "--from-config with no config file -> no repos, exit 0" "$([ "$(cat $T/rc)" = 0 ] && [ "$(has $OUT 'no repos to process')" = 1 ] && echo 1 || echo 0)"
run --repos-dir "$T/nonexistent"
ok "--repos-dir missing dir -> no repos" "$(has $OUT 'no repos to process')"
run "$T/repos/ghost"
ok "explicit path without .git -> SKIP + report" "$([ "$(has $OUT 'SKIP ghost')" = 1 ] && [ "$(has $REPORT_FILE 'skipped (no checkout)')" = 1 ] && echo 1 || echo 0)"
setup; mk a py; mkdir -p "$T/repos/notrepo"; export OVN_XDIST_REPOS=none; run --repos-dir "$T/repos"
ok "--repos-dir picks up git repos and ignores plain dirs" "$([ "$(has $OUT '=== a (')" = 1 ] && [ "$(has $OUT 'notrepo')" = 0 ] && echo 1 || echo 0)"
ok "merge to develop by default (env unset)" "$([ "$(merged a develop)" = 1 ] && [ "$(has $OUT 'MERGED a overnight/feature (+2) -> develop')" = 1 ] && echo 1 || echo 0)"

# ===== gated merge: pass =====
setup; mk app py 2; export OVN_XDIST_REPOS=none; d0="$(sha app develop)"; m0="$(sha app main)"; echo stale > "$(flag app)"; run "$T/repos/app"
ok "green gate: feature merged into develop (merge commit, --no-ff)" "$([ "$(merged app develop)" = 1 ] && [ "$(sha app develop)" != "$d0" ] && [ "$(git -C $T/origin/app.git rev-list --merges --count main..develop)" = 1 ] && echo 1 || echo 0)"
ok "green gate: main untouched" "$([ "$(sha app main)" = "$m0" ] && echo 1 || echo 0)"
ok "green gate: stale review flag cleared" "$([ ! -f "$(flag app)" ] && echo 1 || echo 0)"
ok "green gate: report line merged gated" "$(has $REPORT_FILE 'merged +2 to develop (gated)')"
ok "green gate: pytest ran in the worktree with serial args (no -n)" "$([ "$(has $T/pytest.log 'pytest -q -o addopts= -p no:cacheprovider')" = 1 ] && [ "$(has $T/pytest.log ' -n ')" = 0 ] && [ "$(has $T/pytest.log 'cwd=/tmp/hygiene-app.')" = 1 ] && echo 1 || echo 0)"
ok "worktrees cleaned up" "$([ "$(git -C $T/repos/app worktree list | wc -l)" = 1 ] && echo 1 || echo 0)"
run "$T/repos/app"
ok "second run: already in develop - nothing to land" "$([ "$(has $OUT 'already in develop')" = 1 ] && [ "$(has $REPORT_FILE 'in sync')" = 1 ] && echo 1 || echo 0)"

# pytest parallel-arg wiring
setup; mk iptv_apps py 1; mkdir -p "$T/repos/iptv_apps/.venv/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/repos/iptv_apps/.venv/bin/python"; chmod +x "$T/repos/iptv_apps/.venv/bin/python"
export OVN_XDIST_REPOS=iptv_apps; run "$T/repos/iptv_apps"
ok "allowlisted repo + xdist importable -> pytest gets -n 8" "$(has $T/pytest.log 'pytest -q -n 8 -o addopts=')"
setup; mk iptv_apps py 1; printf '#!/usr/bin/env bash\nexit 1\n' > "$T/repos/iptv_apps/.venv/bin/python"; chmod +x "$T/repos/iptv_apps/.venv/bin/python"; export OVN_XDIST_REPOS=iptv_apps; run "$T/repos/iptv_apps"
ok "xdist not importable -> serial" "$([ "$(has $T/pytest.log ' -n ')" = 0 ] && [ "$(has $T/pytest.log 'pytest -q')" = 1 ] && echo 1 || echo 0)"
setup; mk iptv_apps py 1; export OVN_XDIST_REPOS=iptv_apps OVN_PYTEST_WORKERS=0; run "$T/repos/iptv_apps"; unset OVN_PYTEST_WORKERS
ok "OVN_PYTEST_WORKERS=0 disables parallel" "$([ "$(has $T/pytest.log ' -n ')" = 0 ] && echo 1 || echo 0)"

# ===== gate fail -> not merged, flagged =====
setup; mk app py 2; flagfile app red.flag; export OVN_XDIST_REPOS=none; d0="$(sha app develop)"; run "$T/repos/app"
ok "red gate: NOT merged" "$([ "$(sha app develop)" = "$d0" ] && echo 1 || echo 0)"
ok "red gate: review flag written with reason" "$(has "$(flag app)" 'gate FAILED (build/tests red)')"
ok "red gate: report flags needs review" "$(has $REPORT_FILE 'needs review')"
ok "red gate (non-timeout) does not retry" "$([ "$(has $OUT 'retrying once')" = 0 ] && echo 1 || echo 0)"
# no gate available
setup; mk app none 1; run "$T/repos/app"
ok "no detectable gate -> flagged, never merged" "$([ "$(has "$(flag app)" 'no build/test gate available')" = 1 ] && [ "$(merged app develop)" = 0 ] && echo 1 || echo 0)"
# migration safety
setup; mk app py 1; touch "$HOME/mig_fail"; export OVN_XDIST_REPOS=none; run "$T/repos/app"
ok "migration safety failure blocks merge" "$([ "$(has $OUT 'MIGRATION SAFETY FAILED')" = 1 ] && [ "$(merged app develop)" = 0 ] && echo 1 || echo 0)"

# ===== timeout retry =====
setup; mk app py 1; flagfile app slow_first.flag; export OVN_XDIST_REPOS=none TEST_TIMEOUT=2; run "$T/repos/app"
ok "timeout (124) on first gate -> one retry -> merged" "$([ "$(has $OUT 'known infra flake')" = 1 ] && [ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
setup; mk app py 1; flagfile app slow_always.flag; export OVN_XDIST_REPOS=none TEST_TIMEOUT=2; run "$T/repos/app"
ok "timeout twice -> flagged not merged" "$([ "$(has $OUT 'retrying once')" = 1 ] && [ "$(merged app develop)" = 0 ] && [ -f "$(flag app)" ] && echo 1 || echo 0)"
setup; mk app py 1; flagfile app slow_always.flag; export OVN_XDIST_REPOS=none TEST_TIMEOUT=2; FAIL_WT=hygiene-app-retry run "$T/repos/app"
ok "retry worktree creation failing -> falls through to flagged" "$([ -f "$(flag app)" ] && [ "$(merged app develop)" = 0 ] && echo 1 || echo 0)"
unset TEST_TIMEOUT

# ===== npm gates =====
setup; mk app web 1; run "$T/repos/app"
ok "npm build+test green -> merged" "$([ "$(has $T/npm.log 'run build')" = 1 ] && [ "$(has $T/npm.log 'test --silent')" = 1 ] && [ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
setup; mk app web 1; flagfile app build_red.flag web; run "$T/repos/app"
ok "npm build red -> flagged" "$([ "$(merged app develop)" = 0 ] && [ -f "$(flag app)" ] && echo 1 || echo 0)"
setup; mk app web 1; flagfile app test_red.flag web; run "$T/repos/app"
ok "npm test red (exit 1) -> flagged (regression: used to be -gt 1)" "$([ "$(merged app develop)" = 0 ] && [ -f "$(flag app)" ] && echo 1 || echo 0)"
setup; mk app web 1; flagfile app build_slow.flag web; export TEST_TIMEOUT=2; run "$T/repos/app"
ok "npm build timeout -> infra-flake retry attempted" "$([ "$(has $OUT 'known infra flake')" = 1 ] && echo 1 || echo 0)"
setup; mk app web 1; flagfile app test_red.flag web; run "$T/repos/app"; unset TEST_TIMEOUT
setup; mk app webnotest 1; run "$T/repos/app"
ok "build-only package gates on build" "$([ "$(has $T/npm.log 'test --silent')" = 0 ] && [ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
setup; mk app webtestonly 1; run "$T/repos/app"
ok "test-only package runs npm test" "$([ "$(has $T/npm.log 'test --silent')" = 1 ] && [ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
setup; mk app webtestonly 1; flagfile app test_red.flag web; export TEST_TIMEOUT=2; run "$T/repos/app"; unset TEST_TIMEOUT
setup; mk app webnone 1; run "$T/repos/app"
ok "package.json with no build/test scripts -> nothing to gate (flagged)" "$([ "$(has "$(flag app)" 'no build/test gate available')" = 1 ] && echo 1 || echo 0)"
setup; mk app vscode 1; run "$T/repos/app"
ok "vscode-extension: build gated, npm test skipped" "$([ "$(has $T/npm.log 'run build')" = 1 ] && [ "$(has $T/npm.log 'test --silent')" = 0 ] && echo 1 || echo 0)"

# ===== gradle gates =====
setup; mk app gradle 1; run "$T/repos/app"
ok "gradlew green -> merged" "$([ "$(has $T/gradle.log 'gradlew test --console=plain')" = 1 ] && [ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
ok "gradle: local.properties sdk.dir created in the worktree run" "$(has $OUT 'gate: ./gradlew test in')"
setup; mk app gradle 1; flagfile app gradle_red.flag; run "$T/repos/app"
ok "gradlew red -> flagged, no retry" "$([ "$(merged app develop)" = 0 ] && [ "$(has $OUT 'retrying once')" = 0 ] && echo 1 || echo 0)"
setup; mk app gradle 1; flagfile app gradle_daemon.flag; run "$T/repos/app"
ok "gradle daemon crash -> retried once in fresh worktree -> merged" "$([ "$(has $OUT 'known infra flake')" = 1 ] && [ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"

# ===== godot gate =====
mkgodot(){ mkdir -p "$HOME/godot"; cat > "$HOME/godot/godot4" <<'G'
#!/usr/bin/env bash
mode="$(cat "$T/godot_mode" 2>/dev/null || echo ok)"
for a in "$@"; do case "$a" in -gjunit_xml_file=*) xml="${a#-gjunit_xml_file=}";; esac; done
case " $* " in *" --import "*) case "$mode" in parse_err) echo "SCRIPT ERROR: Parse Error: bad";; benign) echo "SCRIPT ERROR: x Cannot call method 'a' on a null value";; esac; exit 0;; esac
[ -n "${xml:-}" ] || exit 0
case "$mode" in
  ok|benign) echo '<testsuites><testsuite failures="0"/></testsuites>' > "$xml";;
  red) echo '<testsuites><testsuite failures="2"/></testsuites>' > "$xml";;
  noasserts) echo '<testsuites><testsuite failures="0"><testcase status="no asserts"/></testsuite></testsuites>' > "$xml";;
  compile) echo "Failed to load script res://x.gd"; echo '<testsuites><testsuite failures="0"/></testsuites>' > "$xml";;
  empty) : > "$xml";;
esac
exit 0
G
chmod +x "$HOME/godot/godot4"; }
for gm in ok:1 benign:1 parse_err:0 red:0 noasserts:0 compile:0 empty:0; do
  setup; mk app godot 1; mkgodot; echo "${gm%%:*}" > "$T/godot_mode"; run "$T/repos/app"
  ok "godot mode ${gm%%:*} -> merged=${gm##*:}" "$([ "$(merged app develop)" = "${gm##*:}" ] && echo 1 || echo 0)"
done
setup; mk app godot 1; echo x > /dev/null; rm -rf "$HOME/godot"; run "$T/repos/app"
ok "godot repo without installed godot -> nothing to gate (flagged)" "$([ "$(has "$(flag app)" 'no build/test gate available')" = 1 ] && echo 1 || echo 0)"
setup; mk app godot 1; mkgodot; rm -rf "$T/seed/app/addons"; ( cd "$T/seed/app" && git checkout -q overnight/feature && git rm -rqf addons && git commit -qm "drop gut" && git push -q origin overnight/feature ); git -C "$T/repos/app" fetch -q; run "$T/repos/app"
ok "godot without vendored gut still passes import-only gate" "$([ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"

# ===== shell + docker gates =====
setup; mk app shellok 1; run "$T/repos/app"
ok "bash -n clean scripts -> gate passes (merged)" "$([ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
setup; mk app shellbad 1; run "$T/repos/app"
ok "bash -n syntax error -> flagged" "$([ "$(has $OUT 'bash -n FAILED for bad.sh')" = 1 ] && [ "$(merged app develop)" = 0 ] && echo 1 || echo 0)"
setup; mk app docker 1; run "$T/repos/app"
ok "unchanged Dockerfile -> build skipped (no docker build call), nothing else to gate" "$([ "$(has $T/docker.log 'build')" = 0 ] && [ -f "$(flag app)" ] && echo 1 || echo 0)"
setup; mk app dockerchg 1; run "$T/repos/app"
ok "changed Dockerfile -> docker build + rmi, merged" "$([ "$(has $T/docker.log 'build -t hygiene-gate-app-')" = 1 ] && [ "$(has $T/docker.log 'rmi hygiene-gate-app-')" = 1 ] && [ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
setup; mk app dockerchg 1; flagfile app docker_red.flag svc; run "$T/repos/app"
ok "docker build failure -> flagged" "$([ "$(merged app develop)" = 0 ] && [ -f "$(flag app)" ] && echo 1 || echo 0)"
setup; mk app dockerchg 1; flagfile app docker_slow.flag svc; export TEST_TIMEOUT=2; run "$T/repos/app"; unset TEST_TIMEOUT

# ===== branch/env handling =====
setup; mk app py 2; export OVN_XDIST_REPOS=none HYGIENE_FEATURE_BRANCH=claude/feature
( cd "$T/seed/app" && git checkout -q claude/feature && echo c > claude.txt && git add -A && git commit -qm "claude work" && git push -q origin claude/feature ); git -C "$T/repos/app" fetch -q
run "$T/repos/app"
ok "HYGIENE_FEATURE_BRANCH=claude/feature lands the claude branch" "$([ "$(merged app develop claude/feature)" = 1 ] && [ "$(merged app develop overnight/feature)" = 0 ] && [ "$(has $OUT 'MERGED app claude/feature (+1) -> develop')" = 1 ] && echo 1 || echo 0)"
setup; mk app py 1; export OVN_XDIST_REPOS=none HYGIENE_MERGE_TARGET=main; m0="$(sha app main)"; run "$T/repos/app"
ok "explicit HYGIENE_MERGE_TARGET=main merges into main" "$([ "$(merged app main)" = 1 ] && [ "$(sha app main)" != "$m0" ] && echo 1 || echo 0)"
setup; mk app py 1; export OVN_XDIST_REPOS=none HYGIENE_MERGE_TARGET=nonesuch; run "$T/repos/app"
ok "missing merge target -> WARNING + fallback to repo default branch" "$([ "$(has $OUT "merge target 'nonesuch' has no origin ref")" = 1 ] && [ "$(merged app main)" = 1 ] && echo 1 || echo 0)"
setup; mk app py 1; export OVN_XDIST_REPOS=none; git -C "$T/repos/app" remote set-head origin -d >/dev/null 2>&1; run "$T/repos/app"
ok "unresolvable origin/HEAD defaults DEF to main; develop still the target" "$([ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
setup; mk app py 1; git -C "$T/seed/app" push -q origin --delete overnight/feature; git -C "$T/repos/app" fetch -q --prune; run "$T/repos/app"
ok "missing feature branch -> 'no overnight/feature' report" "$(has $REPORT_FILE 'no overnight/feature')"
setup; mk app py 2; export OVN_XDIST_REPOS=none AUTO_MERGE_DEFAULT=false; run "$T/repos/app"
ok "AUTO_MERGE_DEFAULT=false -> flag-only, not merged" "$([ "$(has $OUT 'FLAG-ONLY')" = 1 ] && [ "$(merged app develop)" = 0 ] && [ "$(has $REPORT_FILE 'flag-only')" = 1 ] && echo 1 || echo 0)"
setup; mk billwatch py 1; export OVN_XDIST_REPOS=none AUTO_MERGE_DEFAULT=false; run "$T/repos/billwatch"
ok "AUTO_MERGE_OVERRIDE[billwatch]=true overrides the default-off" "$([ "$(merged billwatch develop)" = 1 ] && echo 1 || echo 0)"
# feature behind develop, ahead 0
setup; mk app py 1; ( cd "$T/seed/app" && git checkout -q develop && git merge -q --no-ff overnight/feature -m "land" && echo dv > dv.txt && git add -A && git commit -qm "develop moves" && git push -q origin develop ); git -C "$T/repos/app" fetch -q; run "$T/repos/app"
ok "feature fully in develop but behind -> reconcile note, nothing to land" "$([ "$(has $OUT 'behind develop')" = 1 ] && [ "$(has $OUT 'nothing to land')" = 1 ] && echo 1 || echo 0)"

# ===== conflict / push failure / worktree failure =====
setup; mk app py 1; export OVN_XDIST_REPOS=none
( cd "$T/seed/app" && git checkout -q overnight/feature && echo F > clash.txt && git add -A && git commit -qm "feat clash" && git push -q origin overnight/feature && git checkout -q develop && echo D > clash.txt && git add -A && git commit -qm "dev clash" && git push -q origin develop ); git -C "$T/repos/app" fetch -q
d0="$(sha app develop)"; run "$T/repos/app"
ok "merge conflict: aborted, develop untouched, flagged" "$([ "$(has $OUT 'MERGE CONFLICT for app')" = 1 ] && [ "$(sha app develop)" = "$d0" ] && [ "$(has "$(flag app)" 'MERGE CONFLICT')" = 1 ] && [ "$(has $REPORT_FILE 'merge CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "conflict leaves no stray worktrees" "$([ "$(git -C $T/repos/app worktree list | wc -l)" = 1 ] && echo 1 || echo 0)"
setup; mk app py 1; export OVN_XDIST_REPOS=none; printf '#!/bin/sh\nexit 1\n' > "$T/origin/app.git/hooks/pre-receive"; chmod +x "$T/origin/app.git/hooks/pre-receive"; d0="$(sha app develop)"; run "$T/repos/app"
ok "push rejected twice -> 'push failed' flag, develop untouched" "$([ "$(has $OUT 'push to develop failed')" = 1 ] && [ "$(sha app develop)" = "$d0" ] && [ "$(has "$(flag app)" 'push failed')" = 1 ] && [ "$(has $REPORT_FILE 'push failed')" = 1 ] && echo 1 || echo 0)"
setup; mk app py 1; export OVN_XDIST_REPOS=none; printf '#!/bin/sh\nif [ ! -f "%s/first_rejected" ]; then touch "%s/first_rejected"; exit 1; fi\nexit 0\n' "$T" "$T" > "$T/origin/app.git/hooks/pre-receive"; chmod +x "$T/origin/app.git/hooks/pre-receive"; run "$T/repos/app"
ok "first push raced/rejected -> rebase-retry lands it" "$([ "$(merged app develop)" = 1 ] && [ "$(has $OUT 'MERGED app')" = 1 ] && echo 1 || echo 0)"
setup; mk app py 1; export OVN_XDIST_REPOS=none; FAIL_WT=/tmp/hygiene-app. run "$T/repos/app"
ok "gate worktree creation failure -> flagged" "$([ "$(has $OUT 'could not create worktree')" = 1 ] && [ "$(has "$(flag app)" 'worktree add failed')" = 1 ] && echo 1 || echo 0)"
setup; mk app py 1; export OVN_XDIST_REPOS=none; FAIL_WT=hygiene-main run "$T/repos/app"
ok "develop worktree creation failure -> flagged, not merged" "$([ "$(has $OUT 'could not create main worktree')" = 1 ] && [ "$(merged app develop)" = 0 ] && echo 1 || echo 0)"

# ===== dry run + pruning =====
setup; mk app py 1; export OVN_XDIST_REPOS=none DRY_RUN=1 KEEP_DAYS=3
( cd "$T/seed/app" && git branch old-merged main && git push -q origin old-merged && git branch keep-open develop && git checkout -q keep-open && echo k > k.txt && git add -A && git commit -qm k && git push -q origin keep-open && git checkout -q develop && git branch dependabot/npm/x main && git push -q origin dependabot/npm/x && for b in overnight/2020-01-01/old "overnight/$(date +%F)/fresh"; do git checkout -q -b "$b" main && echo x > "dated_$(echo $b | tr / _).txt" && git add -A && git commit -qm dated && git push -q origin "$b"; git checkout -q develop; done; git branch -q -D overnight/2020-01-01/old )
git -C "$T/repos/app" fetch -q; git -C "$T/repos/app" branch -q old-merged origin/old-merged; git -C "$T/repos/app" branch -q loc-merged origin/main
d0="$(sha app develop)"; run "$T/repos/app"
ok "dry-run: gate green message, develop untouched" "$([ "$(has $OUT '[dry-run] gate green')" = 1 ] && [ "$(sha app develop)" = "$d0" ] && [ "$(has $REPORT_FILE '[dry-run] would merge')" = 1 ] && echo 1 || echo 0)"
ok "dry-run: would-prune logs for local/remote/stale-dated" "$([ "$(has $OUT 'would prune local (merged): loc-merged')" = 1 ] && [ "$(has $OUT 'would prune remote (merged): old-merged')" = 1 ] && [ "$(has $OUT 'would prune stale dated: overnight/2020-01-01/old')" = 1 ] && echo 1 || echo 0)"
ok "dry-run: nothing actually deleted" "$([ -n "$(sha app old-merged)" ] && [ -n "$(sha app overnight/2020-01-01/old)" ] && echo 1 || echo 0)"
unset DRY_RUN; run "$T/repos/app"
ok "prune: merged remote branch deleted" "$([ -z "$(sha app old-merged)" ] && echo 1 || echo 0)"
ok "prune: merged local branch deleted" "$(git -C $T/repos/app show-ref --verify --quiet refs/heads/loc-merged && echo 0 || echo 1)"
ok "prune: stale dated overnight branch deleted" "$([ -z "$(sha app overnight/2020-01-01/old)" ] && echo 1 || echo 0)"
ok "prune: fresh dated branch kept" "$([ -n "$(sha app "overnight/$(date +%F)/fresh")" ] && echo 1 || echo 0)"
ok "prune: unmerged + dependabot + protected branches kept" "$([ -n "$(sha app keep-open)" ] && [ -n "$(sha app dependabot/npm/x)" ] && [ -n "$(sha app develop)" ] && [ -n "$(sha app main)" ] && [ -n "$(sha app claude/feature)" ] && echo 1 || echo 0)"
unset KEEP_DAYS

# ===== lock =====
setup; mk app py 1; export OVN_XDIST_REPOS=none
( flock "$STATE_DIR/hygiene.lock" sleep 4 ) & lp=$!; sleep 0.5
run "$T/repos/app"
ok "lock held (wait 0): skips this tick, exit 0, nothing merged" "$([ "$(cat $T/rc)" = 0 ] && [ "$(has $OUT 'another pass is already running')" = 1 ] && [ "$(merged app develop)" = 0 ] && echo 1 || echo 0)"
ok "lock wait 0 sends no alert" "$([ ! -s "$T/curl.log" ] && echo 1 || echo 0)"
export HYGIENE_LOCK_WAIT=1 NTFY_TOPIC=selftest; run "$T/repos/app"
ok "bounded wait times out -> ntfy contention alert via curl" "$([ "$(has $T/curl.log 'branch-hygiene lock contention')" = 1 ] && echo 1 || echo 0)"
n1="$(grep -c contention "$T/curl.log")"; run "$T/repos/app"
ok "repeat contention within cooldown: alert deduped" "$([ "$(grep -c contention "$T/curl.log")" = "$n1" ] && [ "$(has $OUT 'within cooldown')" = 1 ] && echo 1 || echo 0)"
wait $lp 2>/dev/null
run "$T/repos/app"
ok "after lock released the pass runs (wait>0 path) and merges" "$([ "$(merged app develop)" = 1 ] && echo 1 || echo 0)"
unset HYGIENE_LOCK_WAIT NTFY_TOPIC

# --from-config via a symlinked script dir (SCRIPT_DIR is the logical dirname, so recurring_tasks.json resolves in the fake tree)
setup; mk app py 1; mk other py 1; export OVN_XDIST_REPOS=none
mkdir -p "$T/tree"; ln -sf "$(cd "$(dirname "$BH")" && pwd)/$(basename "$BH")" "$T/tree/branch_hygiene.sh"; ln -sfn "$(cd "$(dirname "$BH")" && pwd)/scripts" "$T/tree/scripts"
cat > "$T/tree/recurring_tasks.json" <<JSON
[{"repo":"$T/repos/app","persistent_branch":true},{"repo":"$T/repos/other","persistent_branch":false},{"repo":null,"persistent_branch":true},{"repo":"$T/repos/app","persistent_branch":true}]
JSON
( cd "$T" && PATH="$BIN:$PATH" bash "$T/tree/branch_hygiene.sh" --from-config > "$OUT" 2>&1 )
ok "--from-config: only persistent_branch repos, de-duplicated, null ignored" "$([ "$(merged app develop)" = 1 ] && [ "$(merged other develop)" = 0 ] && [ "$(grep -c '=== app' $OUT)" = 1 ] && echo 1 || echo 0)"

echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
