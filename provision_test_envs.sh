#!/bin/bash
set -uo pipefail

BASE="$HOME/overnight-queue/repos"
LOG_DIR="$HOME/overnight-queue/provision-logs"
mkdir -p "$LOG_DIR"

# repo:subdir:kind triples
TARGETS=(
  "billwatch:billwatch-backend:python"
  "billwatch:billwatch-web:node"
  "gitlark:backend:python"
  "gitlark:web:node"
  "task-manager-platform:backend:python"
  "task-manager-platform:web:node"
  "shrike-labs-website:.:node"
  "iptv_apps:iptv-backend:python"
  "iptv_apps:iptv-web:node"
  "social-media-manager:backend:python"
  "social-media-manager:web:node"
  "test-automation-agent:backend:python"
  "test-automation-agent:frontend:node"
  "shrike-notify:backend:python"
  "shrike-monitor:backend:python"
)

echo "repo,subdir,kind,status" > "$LOG_DIR/summary.csv"
FAILS=0

for t in "${TARGETS[@]}"; do
  IFS=':' read -r repo subdir kind <<< "$t"
  DIR="$BASE/$repo/$subdir"
  LOG="$LOG_DIR/${repo}__$(echo "$subdir" | tr '/.' '__').log"
  echo "=== $repo/$subdir ($kind) ==="
  if [ ! -d "$DIR" ]; then
    echo "  MISSING DIR - skipping"
    # not counted toward FAILS: some TARGETS entries are known-discontinued projects
    # that are never expected to have a local clone, so this would otherwise trip a
    # permanent, un-actionable non-zero exit on every run.
    echo "$repo,$subdir,$kind,missing-dir" >> "$LOG_DIR/summary.csv"
    continue
  fi
  cd "$DIR" || continue

  if [ "$kind" = "python" ]; then
    if [ ! -d ".venv" ]; then
      python3.12 -m venv .venv > "$LOG" 2>&1
    fi
    if [ -f "requirements.txt" ]; then
      # 2026-09-10 fix: STATUS used to be set only from the LAST of these three installs
      # (the generic pytest-tooling one), so a failed project requirements.txt install
      # (the one that actually matters) was masked by a successful tooling install
      # afterward, falsely reporting "ok" in summary.csv. Now any of the three failing
      # marks STATUS non-zero, while all three still run (same as before) so the log
      # always has full context.
      STATUS=0
      .venv/bin/pip install --quiet --upgrade pip >> "$LOG" 2>&1 || STATUS=$?
      .venv/bin/pip install --quiet -r requirements.txt >> "$LOG" 2>&1 || STATUS=$?
      .venv/bin/pip install --quiet pytest pytest-asyncio pytest-cov httpx >> "$LOG" 2>&1 || STATUS=$?
      # 2026-09-30: some repos' requirements.txt pins are stale relative to their own code/tests (shrike-notify: pytest==8.0.0 +
      # pytest-asyncio==0.23.0 crash with INTERNALERROR "'Package' object has no attribute 'obj'", and fastapi==0.115.0/starlette 0.38 break
      # its SSE tests). The fleet's ORIGINAL venv there had current versions; a rebuild from the pins produced a non-working test env and
      # red hygiene gates. Repos listed here get the test toolchain + fastapi/starlette upgraded after the pinned install (the repo's own
      # requirements.txt, which a test asserts on, is left untouched).
      case " ${OVN_PROVISION_UPGRADE_REPOS:-shrike-notify} " in
        *" $repo "*) .venv/bin/pip install --quiet -U fastapi starlette pytest pytest-asyncio pytest-cov httpx >> "$LOG" 2>&1 || STATUS=$? ;;
      esac
    else
      echo "  no requirements.txt found" >> "$LOG"
      STATUS=1
    fi
  else
    # 2026-09-11 fix: billwatch-web's and iptv-web's REAL node_modules each turned into a
    # symlink pointing AT ITSELF overnight (mechanism never conclusively pinned down - nothing
    # in this pipeline is known to write a node_modules symlink directly into a main clone,
    # only into isolated stage-runner worktrees), which crashed aider's file-scan on every
    # single overnight cycle for hours (OSError: too many levels of symlinks -> uncaught
    # RuntimeError, misclassified as "model-api-error" since the crash looks like a failed
    # model turn). This runs every 2h across every repo regardless of cause, so self-healing
    # HERE bounds the damage to at most ~2h instead of persisting for a whole night: if
    # node_modules is a symlink that doesn't resolve to a real, distinct directory, remove it
    # first so npm install starts clean instead of tripping over it.
    if [ -L "node_modules" ] && [ "$(find -L "node_modules" -maxdepth 0 2>/dev/null | wc -l)" -eq 0 ]; then
      echo "  node_modules is an unresolvable symlink (self-referencing or broken) - removing before install" > "$LOG"
      rm -f "node_modules"
    else
      : > "$LOG"   # fresh log each run (matches the python branch's venv-creation reset below)
    fi
    npm install --no-audit --no-fund >> "$LOG" 2>&1
    STATUS=$?
  fi

  if [ "$STATUS" -eq 0 ]; then
    echo "  OK"
    echo "$repo,$subdir,$kind,ok" >> "$LOG_DIR/summary.csv"
  else
    echo "  FAILED (exit $STATUS) - see $LOG"
    echo "$repo,$subdir,$kind,failed" >> "$LOG_DIR/summary.csv"
    FAILS=$((FAILS+1))
  fi
done

echo ""
echo "=== SUMMARY ==="
cat "$LOG_DIR/summary.csv"

# 2026-09-10 fix: the script used to always exit 0 (its last command was `cat
# summary.csv`), so no caller (cron, this suite, a human's `&&`) could detect a
# provisioning failure without manually reading summary.csv.
[ "$FAILS" -eq 0 ]
