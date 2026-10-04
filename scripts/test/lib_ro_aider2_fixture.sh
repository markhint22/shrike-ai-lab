#!/usr/bin/env bash
# Shared hermetic fixture for test_run_overnight_aider2_*.sh (coverage of the SECOND HALF of
# run_aider_fix_task in run_overnight.sh: implement loop .. final statuses).
#
# Sources the REAL run_overnight.sh with OVN_SOURCE_ONLY=1 inside a fake tree (OVN_SCRIPT_DIR) and
# lets the test call the real run_aider_fix_task() against a fake git repo with a bare origin, driven by
# a scenario-driven stub `aider` ($HOME/aider-venv/bin/aider) and a scenario-driven repo-owned
# `.ovn-verify.sh`. Everything lives under mktemp -d; nothing real is touched.
#
# Scenario control (all files under $CASE_DIR, exported):
#   aider.<N>.sh / aider.default.sh   snippet SOURCED by the stub for its Nth call (cwd = repo). `exit K` = aider rc.
#   verify.<N>.sh / verify.default.sh snippet sourced by the repo's .ovn-verify.sh for its Nth run (`exit 1` = fail)
#   tsc.out, mig.<N> / mig.default, extract.out, autogen.sh, credit.sh : controls for stubbed helper scripts.
# Helpers usable inside aider snippets (defined in $W/stublib.sh): gc <file> <line> <msg>, scout <verdict> <plan> <files>.

HERE="${HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
RO_REAL="${OVN_RUN_OVERNIGHT:-$HERE/../../run_overnight.sh}"
[ -f "$RO_REAL" ] || RO_REAL="$HOME/overnight-queue/run_overnight.sh"
[ -f "$RO_REAL" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }
Q="$(cd "$(dirname "$RO_REAL")" && pwd)"

P=0; F=0; W_WARN=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
known_bug(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else W_WARN=$((W_WARN+1)); echo "  WARN (KNOWN-BUG, non-fatal): $1"; fi; }
eq(){ # desc actual expected
  if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
summary(){ echo "$P passed, $F failed${W_WARN:+, $W_WARN known-bug warning(s)}"; [ "$F" -eq 0 ]; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
REAL_HOME="$HOME"
export HOME="$W/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
mkdir -p "$HOME/aider-venv/bin" "$HOME/godot" "$W/cases"
TREE="$W/tree"
mkdir -p "$TREE/state" "$TREE/logs" "$TREE/reports" "$TREE/scripts" "$TREE/repos"
cp "$Q"/scripts/*.sh "$Q"/scripts/*.py "$TREE/scripts/" 2>/dev/null
cp "$Q"/*.sh "$Q"/*.py "$TREE/" 2>/dev/null
echo '[]' > "$TREE/tasks.json"

# ---- stubbed helper scripts inside the fake tree (real ones are covered by their own tests) ----
cat > "$TREE/scripts/ovn_retire_vague.py" <<'EOF'
print("")
EOF
cat > "$TREE/scripts/ovn_generate_items.py" <<'EOF'
print("GENERATED=0")
EOF
cat > "$TREE/scripts/ovn_tsc_gate.sh" <<'EOF'
#!/bin/bash
[ -f "$CASE_DIR/tsc.out" ] && cat "$CASE_DIR/tsc.out"
exit 0
EOF
cat > "$TREE/scripts/ovn_extract_failure.sh" <<'EOF'
#!/bin/bash
[ -f "$CASE_DIR/extract.out" ] && cat "$CASE_DIR/extract.out"
exit 0
EOF
cat > "$TREE/scripts/ovn_alembic_autogen.sh" <<'EOF'
#!/bin/bash
[ -f "$CASE_DIR/autogen.sh" ] && source "$CASE_DIR/autogen.sh"
exit 0
EOF
cat > "$TREE/scripts/ovn_credit_already_satisfied.sh" <<'EOF'
#!/bin/bash
if [ -f "$CASE_DIR/credit.sh" ]; then source "$CASE_DIR/credit.sh"; else echo "CREDITED=0"; fi
EOF
cat > "$TREE/scripts/check_migrations.py" <<'EOF'
import os, sys
d = os.environ["CASE_DIR"]
p = d + "/mig.n"
n = (int(open(p).read()) if os.path.exists(p) else 0) + 1
open(p, "w").write(str(n))
f = d + "/mig.%d" % n
if not os.path.exists(f):
    f = d + "/mig.default"
rc = 0
if os.path.exists(f):
    lines = open(f).read().split("\n")
    if lines and lines[0].startswith("rc="):
        rc = int(lines[0][3:]); lines = lines[1:]
    sys.stdout.write("\n".join(lines))
sys.exit(rc)
EOF
chmod +x "$TREE"/scripts/*.sh

# ---- stub aider / curl on PATH (script prepends $HOME/aider-venv/bin) ----
cat > "$HOME/aider-venv/bin/curl" <<'EOF'
#!/bin/bash
echo '{"data":[{"id":"qwen-dflash-27B"}]}'
exit 0
EOF
cat > "$HOME/aider-venv/bin/aider" <<'EOF'
#!/bin/bash
d="${CASE_DIR:?}"
n=$(( $(cat "$d/aider.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/aider.n"
printf '%s\n' "$@" > "$d/aider.args.$n"
source "$(dirname "$d")/../stublib.sh"
echo "Aider v0.stub  (call $n)"
f="$d/aider.$n.sh"; [ -f "$f" ] || f="$d/aider.default.sh"
[ -f "$f" ] && source "$f"
echo "Tokens: 1.2k sent, 80 received."
exit 0
EOF
chmod +x "$HOME/aider-venv/bin/"*
cat > "$W/stublib.sh" <<'EOF'
gc(){ # file line msg : append a line to file and commit
  mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" >> "$1"; git add -A >/dev/null 2>&1; git commit -q -m "$3"; }
scout(){ printf 'VERDICT: %s\nPLAN: %s\nFILES: %s\n' "$1" "$2" "$3"; }
EOF

# ---- fake litellm health etc is handled by the curl stub; now source the REAL script ----
export OVN_SCRIPT_DIR="$TREE" OVN_SOURCE_ONLY=1
export CASE_DIR="$W/cases/_boot"; mkdir -p "$CASE_DIR"
# shellcheck disable=SC1090
. "$RO_REAL" >/dev/null 2>&1
declare -F run_aider_fix_task >/dev/null || { echo "  FAIL: could not source run_overnight.sh in OVN_SOURCE_ONLY mode"; exit 1; }
set +e   # run_overnight.sh does set -uo pipefail; keep -u, drop nothing else (no -e was set)
unset OVN_SOURCE_ONLY

PROMPT_DEFAULT='Work the single top not-yet-done item in OVERNIGHT_PROGRESS.md and commit it.'

# mk_case <name> [noverify]  -> creates $CASE_DIR, bare origin (main + claude/feature), clone at $REPO, seed clone at $OTHER
mk_case(){
  local name="$1" mode="${2:-}"
  CASE_DIR="$W/cases/$name"; export CASE_DIR
  rm -rf "$CASE_DIR"; mkdir -p "$CASE_DIR"
  ORIGIN="$CASE_DIR/origin.git"; OTHER="$CASE_DIR/other"; REPO="$CASE_DIR/repo"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$OTHER"
  ( cd "$OTHER" || exit 1
    printf 'def hello():\n    return 1\n' > app.py
    printf 'def other():\n    return 0\n' > other.py
    printf 'def old():\n    return 0\n' > old.py
    mkdir -p tests; printf 'def test_app():\n    assert True\n' > tests/test_app.py
    cat > OVERNIGHT_PROGRESS.md <<'EOP'
# Progress

## Next Steps
- [ ] Fix `hello` in app.py to return 2
- [ ] Add a test for other.py
- [ ] Tidy dead code in old.py
- [ ] Update extra.py helper
- [ ] Polish README wording

## Completed
EOP
    if [ "$mode" != noverify ]; then
      cat > .ovn-verify.sh <<'EOV'
#!/bin/bash
d="${CASE_DIR:?}"
n=$(( $(cat "$d/verify.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/verify.n"
f="$d/verify.$n.sh"; [ -f "$f" ] || f="$d/verify.default.sh"
[ -f "$f" ] && source "$f"
exit 0
EOV
      chmod +x .ovn-verify.sh
    fi
    git add -A; git commit -q -m init
    git remote add origin "$ORIGIN"; git push -q origin main
    git push -q origin main:claude/feature
  ) >/dev/null 2>&1
  git clone -q "$ORIGIN" "$REPO" >/dev/null 2>&1
  TASK_LOG="$CASE_DIR/task.log"; : > "$TASK_LOG"
  : > "$TREE/state/alerts.log"
}
aplan(){ printf '%s\n' "$2" > "$CASE_DIR/aider.$1.sh"; }   # aplan <N|default> <snippet>
vplan(){ printf '%s\n' "$2" > "$CASE_DIR/verify.$1.sh"; }  # vplan <N|default> <snippet>
scout_ok(){ aplan 1 'scout PROCEED "change hello in app.py to return 2" "app.py"'; }

# run_case [prompt] [persistent] [branch] [protected] [max_files] : runs the real function; sets OUT (last stdout line)
run_case(){
  local prompt="${1:-$PROMPT_DEFAULT}" persistent="${2:-false}" branch="${3:-claude/feature}" prot="${4:-}" mf="${5:-2}"
  : > "$TREE/state/alerts.log"
  OUT="$(run_aider_fix_task "t-app" "$REPO" "$prompt" "$branch" "$persistent" "$TASK_LOG" "" "false" "$mf" "$prot" 60 2>/dev/null | tail -1)"
  LOGTXT="$(cat "$TASK_LOG" 2>/dev/null)"
  ALERTS="$(cat "$TREE/state/alerts.log" 2>/dev/null)"
}
logged(){ grep -qF -- "$1" "$TASK_LOG"; }
repo_head(){ git -C "$REPO" rev-parse HEAD; }
origin_has(){ local _o; _o="$(git -C "$ORIGIN" log --format=%s "${1:-claude/feature}" 2>/dev/null)"; printf '%s\n' "$_o" | grep -qF -- "$2"; }   # capture first: `git log | grep -q` under pipefail SIGPIPEs (rc 141) when grep exits on the first line before git finishes writing - load flake (h13 review)
