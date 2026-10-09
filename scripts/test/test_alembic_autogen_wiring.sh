#!/usr/bin/env bash
# Wiring tests for the Alembic autogen hook (2026-10-02). test_alembic_autogen.sh proves the hook's own gates;
# this proves it is PLUGGED IN correctly:
#   S  static: run_overnight.sh calls it after implement + before verify/MIGRATION-SAFETY/NO-NEW-RED; the staged runner
#      calls it before its independent full_verify, with the worktree-aware env.
#   B  behaviour: the REAL block extracted from run_overnight.sh is evaluated in a fixture repo (AFTER_SHA tracking,
#      kill switch, allowlist defaults incl. iptv_apps, non-allowlisted repo untouched, revert of the cycle drops the
#      generated migration AND its credit).
#   C  ovn_alembic_credit.py: the T2 "create migration" sibling is credited only when it is really satisfied.
#   W  worktree: hook works from a git worktree with no .venv (staged-runner shape).
# Needs a python with alembic+sqlalchemy for B/C-integration/W: $OVN_TEST_PY, else the test-automation-agent venv;
# those sections SKIP (static ones still run) if none exists.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPTS="$(cd "$HERE/.." && pwd)"; QROOT="$(cd "$SCRIPTS/.." && pwd)"
RO="$QROOT/run_overnight.sh"; SR="$QROOT/ovn_stage_runner.sh"
fail=0; ok(){ echo "  ok   - $1"; }; bad(){ echo "  FAIL - $1"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "S1 run_overnight.sh: hook sits after the implement loop and before every verifying gate"
ln_impl="$(grep -n 'implement attempt \${ATTEMPT}' "$RO" | head -1 | cut -d: -f1)"
ln_hook="$(grep -n 'scripts/ovn_alembic_autogen.sh" "\$(pwd)" "\$BEFORE_SHA" "\$AFTER_SHA"' "$RO" | head -1 | cut -d: -f1)"
ln_ver="$(grep -n '# Post-commit verification' "$RO" | head -1 | cut -d: -f1)"
ln_mig="$(grep -n 'MIGRATION-SAFETY GATE: commit forked' "$RO" | head -1 | cut -d: -f1)"
ln_red="$(grep -n 'NO-NEW-RED GUARD (2026' "$RO" | head -1 | cut -d: -f1)"
ln_syn="$(grep -n 'AFTER_SHA="\$_ovn_ag_head"' "$RO" | head -1 | cut -d: -f1)"
[ -n "$ln_impl" ] && [ -n "$ln_hook" ] && [ -n "$ln_ver" ] && [ -n "$ln_mig" ] && [ -n "$ln_red" ] && [ -n "$ln_syn" ] && ok "all markers found" || bad "marker missing impl=$ln_impl hook=$ln_hook ver=$ln_ver mig=$ln_mig red=$ln_red syn=$ln_syn"
[ "${ln_impl:-0}" -lt "${ln_hook:-0}" ] && ok "hook after implement loop" || bad "hook not after implement"
[ "${ln_hook:-0}" -lt "${ln_ver:-0}" ] && [ "${ln_syn:-0}" -lt "${ln_ver:-0}" ] && ok "hook (and AFTER_SHA refresh) before post-commit verification" || bad "hook not before verification"
[ "${ln_hook:-0}" -lt "${ln_mig:-0}" ] && ok "hook before MIGRATION-SAFETY gate (gate validates the generated file)" || bad "hook after MIGRATION-SAFETY"
[ "${ln_hook:-0}" -lt "${ln_red:-0}" ] && ok "hook before NO-NEW-RED guard" || bad "hook after NO-NEW-RED"
[ -x "$SCRIPTS/ovn_alembic_autogen.sh" ] && [ -x "$SCRIPTS/ovn_alembic_autogen.py" ] && [ -f "$SCRIPTS/ovn_alembic_credit.py" ] && ok "hook files present and executable (the wiring is guarded by -x)" || bad "hook files missing / not executable"

echo "S2 staged runner: hook runs before the independent full_verify, worktree-aware"
ln_sh="$(grep -n 'scripts/ovn_alembic_autogen.sh "\$wt"' "$SR" | head -1 | cut -d: -f1)"
ln_fv="$(grep -n '^  if full_verify; then VERIFIED=1' "$SR" | head -1 | cut -d: -f1)"
[ -n "$ln_sh" ] && [ -n "$ln_fv" ] && [ "$ln_sh" -lt "$ln_fv" ] && ok "staged runner calls the hook before its first full_verify" || bad "staged wiring (hook=$ln_sh full_verify=$ln_fv)"
grep -q 'OVN_ALEMBIC_AUTOGEN_NAME="\$repo"' "$SR" && grep -q 'OVN_ALEMBIC_AUTOGEN_VENV_ROOT=' "$SR" && ok "passes repo name + main-clone venv root (worktree has neither)" || bad "staged env missing"
grep -q 'GIT_COMMITTER_NAME=shrike-fleet' "$SR" && ok "staged hook commits as the fleet identity" || bad "staged identity"

PYX="${OVN_TEST_PY:-$HOME/overnight-queue/repos/test-automation-agent/backend/.venv/bin/python}"
"$PYX" -c 'import alembic, sqlalchemy' 2>/dev/null || { echo "SKIP B/C/W: no python with alembic+sqlalchemy ($PYX)"; [ "$fail" = 0 ] && echo "ALL PASS (static only)" || { echo FAILURES; exit 1; }; exit 0; }

mkrepo() {  # $1 = repo dir name (basename matters: allowlist)
  local R; R="$(mktemp -d "$T/r.XXXXXX")/$1"; mkdir -p "$R/proj/app" "$R/proj/alembic/versions" "$R/proj/tests"; cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  ln -s "$(dirname "$(dirname "$PYX")")" proj/.venv
  printf '[alembic]\nscript_location = alembic\nprepend_sys_path = .\n' > proj/alembic.ini
  : > proj/app/__init__.py
  printf 'from app import models  # noqa: F401\n' > proj/app/main.py
  cat > proj/app/models.py <<'PY'
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import declarative_base
Base = declarative_base()
class Item(Base):
    __tablename__ = "items"
    id = Column(Integer, primary_key=True)
    name = Column(String(50), nullable=False)
PY
  cat > proj/alembic/env.py <<'PY'
import os
from alembic import context
from sqlalchemy import create_engine
import app.main  # noqa: F401
from app.models import Base
def run():
    eng = create_engine(os.environ["DATABASE_URL"])
    with eng.connect() as c:
        context.configure(connection=c, target_metadata=Base.metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
run()
PY
  cat > proj/alembic/script.py.mako <<'PY'
"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
"""
from alembic import op
import sqlalchemy as sa
${imports if imports else ""}
revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = None
depends_on = None


def upgrade():
    ${upgrades if upgrades else "pass"}


def downgrade():
    ${downgrades if downgrades else "pass"}
PY
  cat > proj/alembic/versions/0001_baseline.py <<'PY'
"""baseline"""
from alembic import op
import sqlalchemy as sa
revision = "0001_baseline"
down_revision = None
branch_labels = None
depends_on = None
def upgrade():
    op.create_table("items", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(50), nullable=False))
def downgrade():
    op.drop_table("items")
PY
  echo "def test_alembic_head_matches_models(): pass" > proj/tests/test_migration_drift.py
  printf '.venv\n__pycache__/\n' > .gitignore
  # the backlog, as the fleet has it: T1 model item (already ticked by the cycle below) + T2 migration item
  cat > OVERNIGHT_PROGRESS.md <<'MD'
- [ ] [T1] proj/app/models.py — Add `note` column (String(20), nullable) to Item model. VERIFY: python -c "pass" (cat:schema; multifile:no)
- [ ] [T2] proj/alembic/versions/0002_item_note.py — Create migration to add `note` column to items table. VERIFY: alembic upgrade head && alembic downgrade -1 (cat:schema; multifile:no)
- [ ] [T2] proj/alembic/versions/0003_item_other.py — Create migration to add `other_col` column to items table. (cat:schema; multifile:no)
- [ ] [T2] proj/app/helpers.py — Add `note` helper that migration code can call. (cat:python)
MD
  git add -A && git commit -qm base && echo "$R"
}
model_change() { sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; git add -A; git commit -qm "feat(models): add item note column"; }
# the block under test, extracted from the REAL run_overnight.sh (from the -x guard through its closing fi)
blk="$T/block.sh"
awk '/if \[ -x "\$SCRIPT_DIR\/scripts\/ovn_alembic_autogen.sh" \]; then/{p=1} p{print} p&&/^      fi$/{exit}' "$RO" > "$blk"
[ -s "$blk" ] && grep -q 'AFTER_SHA="\$_ovn_ag_head"' "$blk" && ok "extracted the real wired block ($(wc -l < "$blk") lines)" || bad "could not extract the block"
run_block() {  # $1 = BEFORE ; env passes through. prints new AFTER_SHA on the last line
  ( BEFORE_SHA="$1"; AFTER_SHA="$(git rev-parse HEAD)"; SCRIPT_DIR="$QROOT"; task_log="$T/task.log"; : > "$task_log"
    # cron-shaped: minimal PATH (the hook must find python3 etc. on its own)
    export PATH=/usr/local/bin:/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:8099
    . "$blk"; echo "AFTER=$AFTER_SHA"; echo "LOG<<$(cat "$task_log" | tr '\n' '|')" )
}
nfiles() { ls proj/alembic/versions/*.py | wc -l | tr -d ' '; }

echo "B1 iptv_apps by DEFAULT allowlist: model-only change -> migration generated in the same cycle, AFTER_SHA advances"
R="$(mkrepo iptv_apps)"; cd "$R"; B=$(git rev-parse HEAD); model_change; H=$(git rev-parse HEAD)
out="$(run_block "$B")"; A="$(echo "$out" | sed -n 's/^AFTER=//p')"
[ "$A" != "$H" ] && [ "$A" = "$(git rev-parse HEAD)" ] && ok "AFTER_SHA now covers the generated commit (revert/NO-NEW-RED/progress range include it)" || bad "AFTER_SHA not advanced: $out"
echo "$out" | grep -q -- '--- ALEMBIC-AUTOGEN: generated and committed' && ok "outcome lands in task_log" || bad "no log line: $out"
[ "$(nfiles)" = 2 ] && ok "exactly one new migration" || bad "files: $(ls proj/alembic/versions)"
git diff --name-only "$B" "$A" | grep -q 'alembic/versions/0002_' && ok "generated file is inside BEFORE..AFTER" || bad "not in range"

echo "B2 test-automation-agent still default-on"
R="$(mkrepo test-automation-agent)"; cd "$R"; B=$(git rev-parse HEAD); model_change; H=$(git rev-parse HEAD)
out="$(run_block "$B")"; [ "$(echo "$out" | sed -n 's/^AFTER=//p')" != "$H" ] && ok "generated" || bad "not generated: $out"

echo "B3 non-allowlisted repo untouched (silent, HEAD unchanged, no stray file)"
R="$(mkrepo billwatch)"; cd "$R"; B=$(git rev-parse HEAD); model_change; H=$(git rev-parse HEAD)
out="$(run_block "$B")"; [ "$(echo "$out" | sed -n 's/^AFTER=//p')" = "$H" ] && [ "$(git rev-parse HEAD)" = "$H" ] && [ "$(nfiles)" = 1 ] && ok "billwatch untouched" || bad "$out"

echo "B4 kill switch OVN_ALEMBIC_AUTOGEN_DISABLE=1"
R="$(mkrepo iptv_apps)"; cd "$R"; B=$(git rev-parse HEAD); model_change; H=$(git rev-parse HEAD)
out="$(OVN_ALEMBIC_AUTOGEN_DISABLE=1 run_block "$B")"; [ "$(echo "$out" | sed -n 's/^AFTER=//p')" = "$H" ] && [ "$(nfiles)" = 1 ] && ok "disabled: nothing generated" || bad "$out"

echo "B5 OVN_ALEMBIC_AUTOGEN_REPOS narrows the allowlist (iptv_apps excluded)"
R="$(mkrepo iptv_apps)"; cd "$R"; B=$(git rev-parse HEAD); model_change; H=$(git rev-parse HEAD)
out="$(OVN_ALEMBIC_AUTOGEN_REPOS=test-automation-agent run_block "$B")"; [ "$(echo "$out" | sed -n 's/^AFTER=//p')" = "$H" ] && ok "override respected" || bad "$out"

echo "B6 model-only commit + the model's OWN forked migration (stale down_revision) = the 2026-10-02 iptv incident: one clean head, no fork"
R="$(mkrepo iptv_apps)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py
printf 'revision = "0002_item_note"\ndown_revision = "0009"\nbranch_labels = None\ndepends_on = None\ndef upgrade(): pass\ndef downgrade(): pass\n' > proj/alembic/versions/0002_item_note.py
git add -A; git commit -qm "feat: note + hand-written migration"; H=$(git rev-parse HEAD)
out="$(run_block "$B")"; A="$(echo "$out" | sed -n 's/^AFTER=//p')"
[ "$A" != "$H" ] && python3 "$SCRIPTS/check_migrations.py" "$R/proj" >/dev/null 2>&1 && ok "single linear chain, passes the MIGRATION-SAFETY check the loop runs next" || bad "chain not repaired: $out"
! grep -q 'down_revision = "0009"' proj/alembic/versions/*.py && ok "model's stale-down_revision file is gone" || bad "forked file survived"

echo "C1 T2 sibling: credited only when truly satisfied (named alembic path absent + every added column named)"
R="$(mkrepo iptv_apps)"; cd "$R"; B=$(git rev-parse HEAD); model_change
out="$(run_block "$B")"; A="$(echo "$out" | sed -n 's/^AFTER=//p')"
grep -q '^- \[x\] (satisfied by auto-generated migration 0002_.*\.py) \[T2\] proj/alembic/versions/0002_item_note.py' OVERNIGHT_PROGRESS.md && ok "T2 'create migration add note' ticked" || bad "T2 not credited: $(cat OVERNIGHT_PROGRESS.md)"
grep -q '^- \[ \] \[T2\] proj/alembic/versions/0003_item_other.py' OVERNIGHT_PROGRESS.md && ok "T2 for a DIFFERENT column (other_col) stays open (no false credit)" || bad "false credit for other_col"
grep -q '^- \[ \] \[T2\] proj/app/helpers.py' OVERNIGHT_PROGRESS.md && ok "non-migration item that merely says 'migration' stays open" || bad "false credit for helper item"
grep -q '^- \[ \] \[T1\] proj/app/models.py' OVERNIGHT_PROGRESS.md && ok "T1 left to the cycle's own bookkeeping (helper never touches it)" || bad "T1 touched"
[ "$(git log --format=%s -1)" = "chore(queue): credit migration item(s) satisfied by the auto-generated migration" ] && git diff --name-only "$B" "$A" | grep -q OVERNIGHT_PROGRESS.md && ok "credit is a commit inside BEFORE..AFTER" || bad "credit not committed in range"
echo "C2 no duplicate migration: re-running the hook after the T2 step is a no-op (NODRIFT) and the chain stays single-head"
H1=$(git rev-parse HEAD); out="$(run_block "$B")"; [ "$(git rev-parse HEAD)" = "$H1" ] && [ "$(nfiles)" = 2 ] && python3 "$SCRIPTS/check_migrations.py" "$R/proj" >/dev/null 2>&1 && ok "idempotent, 2 migrations total, single head" || bad "$out"
echo "C3 reverting the cycle (reset --hard BEFORE_SHA, what every revert path does) drops the migration AND the credit"
git reset -q --hard "$B"; git clean -fdq
[ "$(nfiles)" = 1 ] && ! grep -q 'satisfied by auto-generated' OVERNIGHT_PROGRESS.md && ok "migration and credit both gone" || bad "residue after revert"

echo "C4 credit helper edge cases (direct)"
R="$(mkrepo iptv_apps)"; cd "$R"
printf 'revision="0002_x"\ndown_revision="0001_baseline"\ndef upgrade():\n    op.add_column("items", sa.Column("note", sa.String(length=20), nullable=True))\ndef downgrade():\n    op.drop_column("items", "note")\n' > proj/alembic/versions/0002_x.py
cp OVERNIGHT_PROGRESS.md "$T/p0"
printf -- '- [ ] [T2] proj/alembic/versions/0003_n.py — Create migration for `note`. (cat:schema)\n- [ ] [CLAUDE] [T2] proj/alembic/versions/0004_n.py — Create migration for `note`.\n- [ ] [AUTO-SKIP staged 1/2] [T2] proj/alembic/versions/0005_n.py — migration for `note`.\n- [ ] [T2] proj/alembic/versions/0006_n.py — Create migration for `notebook`.\n' > OVERNIGHT_PROGRESS.md
out="$(python3 "$SCRIPTS/ovn_alembic_credit.py" OVERNIGHT_PROGRESS.md proj/alembic/versions/0002_x.py "$PWD")"
[ "$(echo "$out" | tail -1)" = "CREDITED=1" ] && grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md | grep -q '^1$' && ok "only the plain open item credited; CLAUDE/AUTO-SKIP/near-miss name 'notebook' stay open" || bad "$out / $(cat OVERNIGHT_PROGRESS.md)"
printf -- '- [ ] [T2] proj/alembic/versions/0001_baseline.py — Create migration for `note`. (cat:schema)\n' > OVERNIGHT_PROGRESS.md
out="$(python3 "$SCRIPTS/ovn_alembic_credit.py" OVERNIGHT_PROGRESS.md proj/alembic/versions/0002_x.py "$PWD")"; [ "$(echo "$out" | tail -1)" = "CREDITED=0" ] && ok "item whose named file EXISTS is a normal item: never credited" || bad "$out"
printf 'revision="0002_x"\ndef upgrade():\n    op.alter_column("items", "name", nullable=True)\n    op.add_column("items", sa.Column("note", sa.String(length=20)))\ndef downgrade(): pass\n' > proj/alembic/versions/0002_x.py
printf -- '- [ ] [T2] proj/alembic/versions/0009_y.py — Create migration for `note`. (cat:schema)\n' > OVERNIGHT_PROGRESS.md
out="$(python3 "$SCRIPTS/ovn_alembic_credit.py" OVERNIGHT_PROGRESS.md proj/alembic/versions/0002_x.py "$PWD")"; [ "$(echo "$out" | tail -1)" = "CREDITED=0" ] && ok "migration with an op beyond add_column/create_table/create_index: no credit" || bad "$out"
out="$(python3 "$SCRIPTS/ovn_alembic_credit.py" /nonexistent proj/alembic/versions/nope.py "$PWD" 2>/dev/null)"; [ "$(echo "$out" | tail -1)" = "CREDITED=0" ] && ok "missing files: CREDITED=0, exit 0" || bad "$out"

echo "W1 worktree (staged-runner shape): no .venv in the checkout, basename is stage-<repo>.XXXX"
R="$(mkrepo iptv_apps)"; cd "$R"; B=$(git rev-parse HEAD); git branch -q fb
WT="$T/stage-iptv_apps.AbCd"; git worktree add -q "$WT" fb; cd "$WT"; rm -f proj/.venv 2>/dev/null; [ ! -e proj/.venv ] || rm -rf proj/.venv
model_change; H=$(git rev-parse HEAD)
o1="$(OVN_ALEMBIC_AUTOGEN_REPOS= bash "$SCRIPTS/ovn_alembic_autogen.sh" "$WT" "$B" "$H" 2>&1)"; [ "$(git rev-parse HEAD)" = "$H" ] && ok "without the overrides the worktree is skipped (name/venv) - proves the overrides are what makes it work" || bad "ran without overrides: $o1"
o2="$(OVN_ALEMBIC_AUTOGEN_NAME=iptv_apps OVN_ALEMBIC_AUTOGEN_VENV_ROOT="$R" GIT_AUTHOR_NAME=shrike-fleet GIT_COMMITTER_NAME=shrike-fleet GIT_AUTHOR_EMAIL=f@x GIT_COMMITTER_EMAIL=f@x bash "$SCRIPTS/ovn_alembic_autogen.sh" "$WT" "$B" "$H" 2>&1)"
echo "$o2" | grep -q 'generated and committed' && [ "$(git rev-parse HEAD)" != "$H" ] && ok "worktree: migration generated using the main clone's venv" || bad "$o2"
[ "$(git log -1 --format=%an)" = "shrike-fleet" ] && ok "committed as the fleet identity" || bad "identity: $(git log -1 --format=%an)"
cd "$R"; git worktree remove --force "$WT" 2>/dev/null

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
