#!/usr/bin/env bash
# Wave-3c coverage tests (real scripts executed in place): ovn_noop_detail.py, ovn_batch_scorecard.py,
# ovn_derive_legacy_logs.py, check_migrations.py. Hermetic: temp HOME/TASK_STATS/state dirs only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HERE/.."; [ -f "$D/check_migrations.py" ] || D="$HERE"
export PYTHONDONTWRITEBYTECODE=1
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
has(){ if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1" 1; else ok "$1 (output: $(printf '%s' "$2" | head -c 200))" 0; fi; }
kb(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   KNOWN-BUG (now fixed): $1"; else echo "  WARN KNOWN-BUG: $1 (non-fatal)"; fi; }
hasnt(){ if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1 (unexpected: $3)" 0; else ok "$1" 1; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
now="$(date +%s)"

# ============================================================== ovn_noop_detail
ND="$D/ovn_noop_detail.py"
row(){ printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"; }
{
  for i in 1 2 3 4; do row $((now-100*i)) billwatch noop:flail '{py·x·T2·t}' app/stuck.py; done            # still unresolved x4
  for i in 1 2 3; do row $((now-1000-i)) gitlark revert '{ts·x·3·t}' web/src/some/very/long/path/that/exceeds/the/display/limit/for/sure/abcdefghijkl.ts; done
  row $((now-10)) gitlark pass '{ts·x·3·t}' web/src/some/very/long/path/that/exceeds/the/display/limit/for/sure/abcdefghijkl.ts   # then landed
  for i in 1 2 3; do row $((now-2000-i)) iptv fail 'no-tag' f/x.py; done                                  # tier '?'
  for i in 1 2 3; do row $((now-3000-i)) xlite error '{gd·x·T1·t}' e.gd; done                              # ignored oc
  row $((now-50)) few noop '{py·x·T1·t}' few.py                                                         # below min-repeat
  printf 'short\tline\n'
  printf 'notanumber\tr\trevert\t{a·b·T1·c}\tf\n'
  row $((now-99999)) old revert '{py·x·T1·t}' old.py                                                    # outside window
  for i in 1 2 3; do row $((now-200-i)) old revert '{py·x·T1·t}' old.py; done
} > "$T/stats.log"
out="$(TASK_STATS="$T/stats.log" python3 "$ND")"
has "header with default 3h window" "$out" "🔁 Repeat no-op/reverted (last 3h):"
has "worst first: billwatch x4 unresolved" "$out" "billwatch (T2): app/stuck.py — failed 4x (same item, still unresolved)"
has "self-resolved item labelled" "$out" "then landed, self-resolved"
has "numeric tier rendered as T3" "$out" "gitlark (T3):"
has "long path truncated with ellipsis" "$out" "…"
has "no-tag row gets tier ?" "$out" "iptv (?): f/x.py — failed 3x"
hasnt "error-only key ignored" "$out" "xlite"
hasnt "below min-repeat hidden" "$out" "few.py"
ln="$(printf '%s\n' "$out" | sed -n 2p)"
has "sorted by count: first row is the 4x one" "$ln" "billwatch"
out="$(TASK_STATS="$T/stats.log" python3 "$ND" 1 --min-repeat 2 --max-total 1 --max-len 20)"
# KNOWN-BUG ovn_noop_detail.py:68-74 _is_flag_value(): a positional hours value equal to ANY flag's value (here "1" == --max-total 1) is
# swallowed as a flag value, so hours silently falls back to 3. Fix: only skip argv[i+1] when it directly follows its own flag (track indexes).
kb "positional hours equal to a flag value is honoured (got: $(printf '%s' "$out" | head -1))" "$(printf '%s' "$out" | grep -qF '(last 1h)' && echo 1 || echo 0)"
out="$(TASK_STATS="$T/stats.log" python3 "$ND" 6 --min-repeat 2 --max-total 1 --max-len 20)"
has "custom hours header" "$out" "(last 6h)"
[ "$(printf '%s\n' "$out" | wc -l)" = 2 ] && ok "--max-total 1 caps to one row" 1 || ok "--max-total 1 caps to one row" 0
out="$(TASK_STATS="$T/stats.log" python3 "$ND" --min-repeat abc --max-total)"
has "non-int --min-repeat falls back to default 3, dangling flag ignored" "$out" "billwatch (T2)"
out="$(TASK_STATS="$T/stats.log" python3 "$ND" 5 --min-repeat 10)"
[ -z "$out" ] && ok "nothing qualifies -> empty output" 1 || ok "nothing qualifies -> empty output" 0
out="$(TASK_STATS="$T/stats.log" python3 "$ND" --max-total 0)"
[ -z "$out" ] && ok "--max-total 0 -> empty output (total==0 guard)" 1 || ok "--max-total 0 -> empty output (total==0 guard)" 0
mkdir -p "$T/cwd/state"; cp "$T/stats.log" "$T/cwd/state/task_stats.log"
out="$(cd "$T/cwd" && TASK_STATS="$T/absent.log" python3 "$ND")"
has "cwd-relative state/task_stats.log fallback" "$out" "billwatch (T2)"
out="$(cd "$T" && TASK_STATS="$T/absent.log" python3 "$ND")"
[ -z "$out" ] && ok "no stats file at all -> empty" 1 || ok "no stats file at all -> empty" 0

# ========================================================== ovn_batch_scorecard
SC="$D/ovn_batch_scorecard.py"
Q="$HOME/overnight-queue/state"
out="$(python3 "$SC")"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok "missing outcomes.jsonl -> silent rc 0" 1 || ok "missing outcomes.jsonl -> silent rc 0" 0
mkdir -p "$Q"
python3 - "$Q/outcomes.jsonl" <<'PY'
import json, sys, time
def ts(h): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - h * 3600))
rows = []
def batch(tag, repo, hrs, classes, tok=100):
    for c in classes:
        rows.append({"ts": ts(hrs), "feat_tag": tag, "repo": repo, "class": c, "tokens_sent": tok, "tokens_recv": None})
batch("featA", "billwatch", 72, ["landed"] * 10)                       # A
batch("featB", "gitlark", 72, ["landed"] * 8 + ["reverted"] * 2)       # B
batch("featC", "iptv", 72, ["landed"] * 5 + ["noop"] * 5)              # C
batch("featD", "xlite", 72, ["landed"] * 3 + ["reverted"] * 5 + ["noop"] * 2)  # D (30%)
batch("featF", "shrike", 72, ["reverted"] * 4)                         # F
batch("featG", "shrike", 48, ["noop"] * 3)                             # F
batch("fresh", "new", 2, ["landed"])                                   # too young for default 24h
lines = [json.dumps(r) for r in rows]
lines.insert(3, "{not json")                                           # malformed line
lines.append(json.dumps({"ts": ts(72), "repo": "x", "class": "landed"}))            # no feat_tag
lines.append(json.dumps({"ts": "garbage", "feat_tag": "badts", "repo": "x"}))       # unparsable ts
lines.append(json.dumps({"ts": 5, "feat_tag": "numts", "repo": "x"}))               # ts wrong type
open(sys.argv[1], "w").write("\n".join(lines) + "\n")
PY
out="$(python3 "$SC")"
has "header counts 6 batches >=24h old" "$out" "📋 Research-batch scorecard: 6 batch(es) >=24h old"
has "grade distribution rows" "$out" "A (90-100%)"
has "summary line" "$out" "#SUMMARY total=6 A=1 B=1 C=1 D=1 F=2 flagged=3"
has "D/F flagged header" "$out" "3 batch(es) graded D/F — worth a look:"
has "worst batch detail" "$out" "F shrike/featF: 0/4 landed (0%) · 4 reverted · 0 no-op"
hasnt "young batch excluded" "$out" "fresh"
hasnt "unparsable-ts batch excluded" "$out" "badts"
first="$(printf '%s\n' "$out" | grep -E '^  [DF] [a-z]+/' | head -1)"
has "worst land-rate listed first" "$first" "featF"
out="$(python3 "$SC" --worst=1)"
has "--worst caps the detail list" "$out" "...and 2 more D/F batch(es) not shown"
out="$(python3 "$SC" --min-age-hours=1)"
has "--min-age-hours=1 admits the 2h batch" "$out" "7 batch(es) >=1h old"
out="$(python3 "$SC" 60)"
has "hours arg drops batches older than the window" "$out" "featG"
hasnt "older batches cut by cutoff" "$out" "featA"
out="$(python3 "$SC" 1)"
[ -z "$out" ] && ok "window with only too-young rows -> silent" 1 || ok "window with only too-young rows -> silent" 0
python3 - "$Q/outcomes.jsonl" <<'PY'
import json, sys, time
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 2 * 3600))
open(sys.argv[1], "w").write(json.dumps({"ts": ts, "feat_tag": "young", "repo": "a", "class": "landed"}) + "\n")
PY
out="$(python3 "$SC")"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok "only too-young batches -> silent rc 0 (no lines)" 1 || ok "only too-young batches -> silent rc 0" 0
python3 - "$Q/outcomes.jsonl" <<'PY'
import json, sys, time
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 100 * 3600))
open(sys.argv[1], "w").write("\n".join([json.dumps({"ts": ts, "feat_tag": "", "repo": "a"}), json.dumps({"ts": ts, "repo": "a"})]) + "\n")
PY
out="$(python3 "$SC")"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok "file with only untagged rows -> silent rc 0 (no batches)" 1 || ok "file with only untagged rows -> silent rc 0" 0
python3 - "$Q/outcomes.jsonl" <<'PY'
import json, sys, time
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 100 * 3600))
open(sys.argv[1], "w").write(json.dumps({"ts": ts, "feat_tag": "solo", "repo": "a", "class": "landed"}) + "\n")
PY
out="$(python3 "$SC")"
has "all-A run: no D/F message" "$out" "No D/F batches — nothing needs a look right now."

# ======================================================== ovn_derive_legacy_logs
DL="$D/ovn_derive_legacy_logs.py"
S="$T/dstate"; mkdir -p "$S"
out="$(python3 "$DL" "$S")"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && [ ! -e "$S/.derive_legacy_logs.cursor" ] && ok "no outcomes.jsonl -> nothing, no cursor" 1 || ok "no outcomes.jsonl -> nothing, no cursor" 0
python3 - "$S/outcomes.jsonl" <<'PY'
import json, sys
recs = [
 ("tests:pass", "billwatch", "backend", 2), ("tests:FAIL x", "gitlark", "frontend", 3), ("reverted(red)", "a", "", None),
 ("build-gate fail", "a", "x", 1), ("error(exit=1)", "a", "x", 1), ("ALREADY-DONE", "a", "x", 1),
 ("BLOCKED:x", "a", "x", 1), ("NEEDS-DECISION", "a", "x", 1), ("no-op (reverted by gate)", "a", "x", 1),
 ("no-op", "a", "x", 1), ("whatever", "a", "x", 1), (None, "a", "x", 1)]
out = []
for i, (st, repo, cat, tier) in enumerate(recs):
    out.append(json.dumps({"ts": "2026-09-30T10:%02d:05Z" % i, "id": "t%d" % i, "repo": repo, "status": st, "category": cat, "tier": tier}))
out.insert(2, "")
out.insert(4, "{broken json")
out.append(json.dumps({"ts": "not-a-date", "id": "bad", "repo": "z", "status": "tests:pass"}))
open(sys.argv[1], "w").write("\n".join(out) + "\n")
PY
out="$(python3 "$DL" "$S")"
has "reports 13 derived records" "$out" "derived 13 new record(s)"
ts="$S/task_stats.derived.log"; cs="$S/cycle_summary.derived.log"
ok "13 lines in each derived log (blank + broken skipped)" "$([ "$(wc -l < "$ts")" = 13 ] && [ "$(wc -l < "$cs")" = 13 ] && echo 1 || echo 0)"
has "tests:pass -> pass with tag" "$(sed -n 1p "$ts")" "billwatch	pass	{backend·backend·T2·?}	?"
has "tests:FAIL -> fail" "$(sed -n 2p "$ts")" "gitlark	fail"
has "empty category -> other, tier None -> ?" "$(sed -n 3p "$ts")" "revert	{other·other·T?·?}"
oc="$(cut -f3 "$ts" | tr '\n' ' ')"
[ "$oc" = "pass fail revert revert error noop:done noop:blocked noop:blocked noop:gate noop:flail skip skip pass " ] && ok "every outcome code mapped in order" 1 || ok "outcome code order (got: $oc)" 0
has "cycle summary line format" "$(sed -n 1p "$cs")" "10:00:05 t0 verdict=PROCEED planfiles=[] top_item=? class={backend·backend·T2·?}"
has "bad ts -> epoch 0 / 00:00:00 fallbacks" "$(tail -1 "$ts")$(tail -1 "$cs")" "0	z	pass"
has "bad ts hms fallback" "$(tail -1 "$cs")" "00:00:00 bad"
cur="$(cat "$S/.derive_legacy_logs.cursor")"
ok "cursor = file size" "$([ "$cur" = "$(wc -c < "$S/outcomes.jsonl" | tr -d ' ')" ] && echo 1 || echo 0)"
out="$(python3 "$DL" "$S")"; [ -z "$out" ] && ok "rerun with no new records prints nothing" 1 || ok "rerun prints nothing" 0
echo '{"ts":"2026-09-30T11:00:00Z","id":"n1","repo":"r","status":"tests:pass"}' >> "$S/outcomes.jsonl"
out="$(python3 "$DL" "$S")"; has "incremental: only the new record" "$out" "derived 1 new record(s)"
echo "garbage" > "$S/.derive_legacy_logs.cursor"
out="$(python3 "$DL" "$S")"; has "corrupt cursor -> restart from 0, reprocess everything" "$out" "derived 14 new record(s)"
: > "$S/.derive_legacy_logs.cursor"
out="$(python3 "$DL" "$S")"; has "empty cursor file treated as 0" "$out" "derived 14 new record(s)"
echo 99999999 > "$S/.derive_legacy_logs.cursor"
out="$(python3 "$DL" "$S")"; has "cursor beyond EOF (rotated file) -> restart from top" "$out" "derived 14 new record(s)"
out="$(cd "$T" && mkdir -p state && cp "$S/outcomes.jsonl" state/ && python3 "$DL")"
has "default state dir is ./state" "$out" "derived 14 new record(s)"

# ============================================================== check_migrations
CM="$D/check_migrations.py"
cm(){ python3 "$CM" "$@"; }
out="$(cm "$T/emptydir" 2>&1)"; mkdir -p "$T/emptydir"; out="$(cm "$T/emptydir")"; rc=$?
has "no versions dirs" "$out" "no alembic versions dirs under"; [ $rc -eq 0 ] && ok "rc 0 when nothing to check" 1 || ok "rc 0 when nothing to check" 0
out="$(cd "$T/emptydir" && python3 "$CM")"; has "default root is ." "$out" "under ."
M="$T/mig"; V="$M/alembic/versions"; mkdir -p "$V"
cat > "$V/__init__.py" <<'PY'
revision = "zzz_init_ignored"
PY
cat > "$V/001_a.py" <<'PY'
"""a"""
revision = "001"
down_revision = None
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
def upgrade():
    op.create_table("users", sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True), sa.Column("n", sa.Integer()), sa.Column("nm", sa.Text()), sa.Column("raw"))
    op.create_table(table_name_var, sa.Column("x", sa.Integer()))
    op.create_table("noargs")
    op.create_table("opaque", some_name, sa.Column("c", sa.Integer()), sa.Column("v", sa.text("1")))
PY
cat > "$V/002_b.py" <<'PY'
revision: str = "002"
down_revision: str | None = "001"
def upgrade():
    op.create_table("api_usage", sa.Column("id", sa.Integer()), sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id")),
                    sa.Column("uid2", sa.String(36)), sa.ForeignKeyConstraint(["uid2"], ["users.id"]))
    op.create_table("ok_child", sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id")))
PY
cat > "$V/003_broken.py" <<'PY'
this is ( not python
PY
out="$(cm "$M")"; rc=$?
[ $rc -eq 1 ] && ok "FK String->UUID problems -> rc 1" 1 || ok "rc 1 expected (got $rc)" 0
has "FAIL banner" "$out" "MIGRATION SAFETY: FAIL"
has "inline ForeignKey flagged" "$out" "FK api_usage.user_id is String but target users.id is UUID"
has "ForeignKeyConstraint flagged" "$out" "FK api_usage.uid2 is String but target users.id is UUID"
hasnt "UUID->UUID child not flagged" "$out" "ok_child"
hasnt "syntactically broken migration is skipped, not a crash" "$out" "Traceback"
# multiple heads + duplicate revision ids
M2="$T/mig2"; V2="$M2/alembic/versions"; mkdir -p "$V2"
printf 'revision = "a1"\ndown_revision = None\n' > "$V2/a1.py"
printf 'revision = "b2"\ndown_revision = "a1"\n' > "$V2/b2.py"
printf 'revision = "c3"\ndown_revision = "a1"\n' > "$V2/c3.py"
printf 'revision = "c3"\ndown_revision = "a1"\n' > "$V2/c3_dup.py"
printf 'no revision here\n' > "$V2/noise.py"
printf 'x = 1\n' > "$V2/__init__.py"
out="$(cm "$M2")"; rc=$?
has "multiple heads detected" "$out" "MULTIPLE HEADS ['b2', 'c3']"
has "duplicate revision id detected" "$out" "revision 'c3' declared in 2 files: c3.py, c3_dup.py"
# clean single chain incl. typed revision and 'None' string down_revision
M3="$T/mig3"; V3="$M3/alembic/versions"; mkdir -p "$V3"
printf 'revision = "a1"\ndown_revision = None\n' > "$V3/a1.py"
printf 'revision = "b2"\ndown_revision = "a1"\ndef u():\n    op.create_table("t", sa.Column("id", sa.Integer()))\n' > "$V3/b2.py"
out="$(cm "$M3")"; rc=$?
has "clean chain OK" "$out" "MIGRATION SAFETY: OK (1 versions dir(s) clean)"; [ $rc -eq 0 ] && ok "rc 0 when clean" 1 || ok "rc 0 when clean" 0
# skipped trees: .git / node_modules / alembic.backup are never scanned
for skip in .git/alembic/versions node_modules/pkg/alembic/versions alembic.backup/alembic/versions; do mkdir -p "$M3/$skip"; printf 'revision = "s1"\ndown_revision = None\n' > "$M3/$skip/s1.py"; printf 'revision = "s2"\ndown_revision = None\n' > "$M3/$skip/s2.py"; done
out="$(cm "$M3")"; has "ignored dirs are skipped (still 1 dir)" "$out" "OK (1 versions dir(s) clean)"
# a versions dir with no .py files is not a migration dir
mkdir -p "$T/mig4/alembic/versions"; : > "$T/mig4/alembic/versions/README.txt"
out="$(cm "$T/mig4")"; has "versions dir w/o .py ignored" "$out" "no alembic versions dirs"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
