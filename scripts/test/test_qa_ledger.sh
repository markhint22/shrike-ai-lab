#!/usr/bin/env bash
# test_qa_ledger.sh - S12 ledger + scorecard + cron wrapper, through the REAL entry points (absolute path, relative path from
# scripts/overnight-queue, env -i with a minimal PATH, NTFY_SERVER set). Fixture = a throwaway git repo with dated commits and a
# synthetic outcomes.jsonl; OVN_DIR is a temp dir so real state is never touched; a stub curl proves nothing reaches the network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"            # scripts/overnight-queue
QA="$ROOT/qa"
[ -f "$QA/qa_ledger.py" ] || { echo "  SKIP: qa/qa_ledger.py not found"; exit 0; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
OVN="$tmp/ovn"; mkdir -p "$OVN/state" "$OVN/repos" "$tmp/bin"
printf '#!/bin/sh\necho "$@" >> %s/curl.log\nexit 0\n' "$tmp" > "$tmp/bin/curl"; chmod +x "$tmp/bin/curl"
MINPATH="$tmp/bin:/usr/bin:/bin:$(dirname "$PY")"
run(){ env -i PATH="$MINPATH" HOME="$tmp" NTFY_SERVER=http://127.0.0.1:9 OVN_DIR="$OVN" OVN_REPOS_DIR="$OVN/repos" "$@"; }
jq1(){ "$PY" -c "import json,sys; d=json.loads(sys.stdin.read().strip().splitlines()[-1]); print(eval(sys.argv[1]))" "$1"; }

# ---------------------------------------------------------------- fixture
"$PY" - "$OVN" <<'PYEOF' || { echo "  ❌ fixture build failed"; exit 1; }
import json, os, subprocess, sys, time
ovn = sys.argv[1]; rd = os.path.join(ovn, "repos", "fixrepo"); os.makedirs(rd)
now = int(time.time()); D = 86400
def git(*a, **kw):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    if "when" in kw: env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = "%d +0000" % kw["when"]
    return subprocess.run(["git", "-C", rd] + list(a), env=env, capture_output=True, text=True, check=True).stdout.strip()
git("init", "-q", "-b", "main")
def commit(files, msg, when, body=""):
    for p, c in files.items():
        fp = os.path.join(rd, p); os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "a").write(c + "\n")
        git("add", p)
    git("commit", "-q", "-m", msg + ("\n\n" + body if body else ""), when=when)
    return git("rev-parse", "HEAD")
fx = {}
T_old = now - 9 * D       # benign, mature record (test-only)
T_a = now - 6 * D         # revert target (risk A: billing)
T_b = now - 5 * D         # hotfix target (risk A: auth)
T_c = now - 4 * D         # emergency/test-watch target
fx["old"] = commit({"tests/test_widget.py": "def test_w(): assert 1"}, "test: add widget test", T_old)
fx["a"] = commit({"backend/app/billing/stripe_client.py": "def refund(): pass"}, "feat: add refund", T_a)
fx["b"] = commit({"backend/app/auth.py": "def login(): pass"}, "feat: add login check", T_b)
fx["c"] = commit({"backend/app/routers/widgets.py": "def widgets(): pass"}, "feat: widgets endpoint", T_c)
# events
git("revert", "--no-edit", fx["a"]) if False else None
fx["revert"] = commit({"backend/app/billing/stripe_client.py": "# reverted"}, 'Revert "feat: add refund"', T_a + D, "This reverts commit %s." % fx["a"])
fx["hotfix"] = commit({"backend/app/auth.py": "# fix"}, "fix: repair broken auth import in login", T_b + 2 * D)
fx["generic_other_file"] = commit({"backend/app/unrelated.py": "x=1"}, "fix: repair broken thing in unrelated", T_b + 2 * D + 60)
fx["inflight"] = commit({"backend/app/routers/widgets.py": "# repair"}, "fix(fixrepo): repair staged item to pass verification (round 1)", T_c + 60)
fx["queue_fix"] = commit({"OVERNIGHT_PROGRESS.md": "- [ ] x"}, "fix(queue): housekeeping", T_c + 120)
open(os.path.join(rd, "OVERNIGHT_PROGRESS.md"), "a").write("- [ ] [EMERGENCY][T2] api suite is RED - Failing: tests/x.py backend/app/routers/widgets.py\n")
git("add", "OVERNIGHT_PROGRESS.md")
git("commit", "-q", "-m", "fix(queue): [EMERGENCY] api suite red - triage+fix queued by test-watch", when=T_c + 2 * D)
fx["emerg"] = git("rev-parse", "HEAD")
for ref in ("origin/overnight/feature", "origin/develop", "origin/main"):
    git("update-ref", "refs/remotes/" + ref, "HEAD")
def iso(e): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))
def row(e, ident, feat, tier="2", cat="endpoint", status="pushed(tests:pass)", dur=120, repo="fixrepo"):
    return json.dumps({"ts": iso(e + 60), "repo": repo, "id": ident, "type": "aider_fix", "tier": tier, "category": cat, "class": "landed",
                       "severity": "good", "attempt": 1, "fail_reason": "", "status": status, "duration_s": dur, "item_hash": ident, "feat_tag": feat})
lines = [
    row(T_old, "i-old", "fixrepo-20260101-widget-test", tier="1", cat="test"),
    row(T_a, "i-a", "fixrepo-20260101-refund", tier="3"),
    row(T_b, "i-b", "fixrepo-20260101-login", tier="3", status="pushed(tests:pass) [untested-change]"),
    row(T_c, "i-c", "fixrepo-20260101-widgets"),
    # not landed / not a landing: must never become ledger rows
    json.dumps({"ts": iso(T_c + 500), "repo": "fixrepo", "id": "i-x", "class": "noop", "status": "no-op(reverted-red)", "type": "aider_fix", "tier": "2"}),
    json.dumps({"ts": iso(T_c + 600), "repo": "fixrepo", "id": "i-y", "class": "landed", "status": "U OVERNIGHT_PROGRESS.md", "type": "aider_fix", "tier": "2"}),
    "this is not json {",
]
open(os.path.join(ovn, "state", "outcomes.jsonl"), "w").write("\n".join(lines) + "\n")
json.dump(fx, open(os.path.join(ovn, "..", "fx.json"), "w"))
PYEOF
FX="$tmp/fx.json"
SHA(){ "$PY" -c "import json;print(json.load(open('$FX'))['$1'])"; }
LED="$OVN/state/qa_ledger.jsonl"
q(){ "$PY" - "$LED" "$1" <<'PYEOF'
import json, sys
recs, evs = [], []
for l in open(sys.argv[1]):
    d = json.loads(l); (recs if d["kind"] == "landed" else evs).append(d)
print(eval(sys.argv[2]))
PYEOF
}

# ---------------------------------------------------------------- 1. derive via ABSOLUTE path, env -i
out="$(run "$PY" "$QA/qa_ledger.py" derive --no-record 2>&1)"
[ "$(echo "$out" | jq1 "d['verdict']")" = "FLAG" ] && [ "$(echo "$out" | jq1 "d['details']['skipped_rows']")" = "1" ] && ok "derive (absolute path, env -i): verdict JSON as last line; the unparseable line is COUNTED and the verdict is FLAG, not PASS" || fail "derive verdict: $out"
[ "$(q 'len(recs)')" = "4" ] && ok "exactly the 4 real landings became records (noop row, garbage-status row, torn JSON skipped)" || fail "record count $(q 'len(recs)')"
[ "$(q '[r["risk"] for r in recs if r["id"]=="i-a"][0]')" = "A" ] && ok "billing file -> risk A (negative control for classifier)" || fail "billing not A"
[ "$(q '[r["risk"] for r in recs if r["id"]=="i-b"][0]')" = "A" ] && ok "auth file -> risk A" || fail "auth not A"
[ "$(q '[r["risk"] for r in recs if r["id"]=="i-old"][0]')" = "C" ] && ok "tests-only change -> risk C (benign control)" || fail "tests-only not C"
[ "$(q '[r["risk"] for r in recs if r["id"]=="i-c"][0]')" = "B" ] && ok "plain endpoint source change -> risk B" || fail "endpoint not B"
[ "$(q '[r["commits"][0][:8] for r in recs if r["id"]=="i-a"][0]')" = "$(SHA a | cut -c1-8)" ] && ok "commit attributed by time window to its record" || fail "commit attribution wrong"
[ "$(q '"untested-change" in [r for r in recs if r["id"]=="i-b"][0]["flags"]')" = "True" ] && ok "status flag [untested-change] carried" || fail "flag missing"

# ---------------------------------------------------------------- 2. events: negative controls fire, benign ones do not
[ "$(q 'sorted(e["ref"] for e in evs if e["type"]=="revert")')" = "['$(SHA revert | cut -c1-12)']" ] && ok "revert of a landed commit detected (by sha)" || fail "revert event: $(q '[(e["type"],e["ref"]) for e in evs]')"
[ "$(q '[e["rec"] for e in evs if e["type"]=="revert"][0] == [r["key"] for r in recs if r["id"]=="i-a"][0]')" = "True" ] && ok "revert attached to the right record" || fail "revert attached wrong"
[ "$(q 'len([e for e in evs if e["type"]=="hotfix" and e["confidence"]=="strong"])')" = "1" ] && ok "repair-subject fix on same file within 7d = ONE strong hotfix event" || fail "hotfix events: $(q '[(e["type"],e["confidence"],e["note"]) for e in evs]')"
[ "$(q 'len([e for e in evs if "unrelated" in e.get("note","")])')" = "0" ] && ok "fix touching an unrelated file is not a hotfix (benign control)" || fail "unrelated fix flagged"
[ "$(q 'len([e for e in evs if "repair staged item" in e.get("note","") or "housekeeping" in e.get("note","")])')" = "0" ] && ok "in-flight staged repair + queue housekeeping ignored" || fail "inflight repair counted"
[ "$(q 'len([e for e in evs if e["type"]=="test_watch_red" and e["confidence"]=="file-overlap"])')" = "1" ] && ok "test-watch EMERGENCY attributed by file overlap" || fail "test_watch_red: $(q '[(e["type"],e["confidence"]) for e in evs]')"
[ "$(q 'len([e for e in evs if e["type"]=="test_watch_red" and e["confidence"]=="repo-level"])')" = "1" ] && ok "repo-level EMERGENCY event also recorded (unattributed count stays visible)" || fail "repo-level event missing"
[ "$(q 'len([e for e in evs if e["rec"] and [r for r in recs if r["key"]==e["rec"]][0]["id"]=="i-old"])')" = "0" ] && ok "mature clean record has no events" || fail "events on the clean record"

# ---------------------------------------------------------------- 3. idempotence + incremental cursor + torn last line
n1="$(wc -l < "$LED" | tr -d ' ')"
run "$PY" "$QA/qa_ledger.py" derive --no-record >/dev/null 2>&1
[ "$(wc -l < "$LED" | tr -d ' ')" = "$n1" ] && ok "second derive appends nothing (cursor + keys)" || fail "derive not idempotent"
off="$(cat "$OVN/state/qa_ledger.cursor")"; sz="$(wc -c < "$OVN/state/outcomes.jsonl" | tr -d ' ')"
[ "$off" = "$sz" ] && ok "cursor at end of outcomes.jsonl ($off bytes)" || fail "cursor $off != size $sz"
printf '{"ts":"2026-01-01T00:00:00Z","repo":"fixrepo","id":"torn","class":"landed","status":"pushed(tests:pass)"' >> "$OVN/state/outcomes.jsonl"
run "$PY" "$QA/qa_ledger.py" derive --no-record >/dev/null 2>&1
[ "$(q 'len(recs)')" = "4" ] && [ "$(cat "$OVN/state/qa_ledger.cursor")" = "$sz" ] && ok "torn (unterminated) last line is not consumed and cursor does not pass it" || fail "torn line handling"
printf '}\n' >> "$OVN/state/outcomes.jsonl"
run "$PY" "$QA/qa_ledger.py" derive --no-record >/dev/null 2>&1
[ "$(q 'len(recs)')" = "5" ] && ok "line completed later is picked up exactly once" || fail "completed line not picked up ($(q 'len(recs)'))"
printf '{"ts":"2026-01-02T00:00:00Z","repo":"nosuchrepo","id":"n1","class":"landed","status":"pushed(tests:pass)","tier":"2","category":"endpoint"}\n\x00junk\x00\n' >> "$OVN/state/outcomes.jsonl"
out="$(run "$PY" "$QA/qa_ledger.py" derive --no-record 2>&1)"; r_=$?
[ $r_ -eq 0 ] && [ "$(q '[r["commit_basis"] for r in recs if r["repo"]=="nosuchrepo"]')" = "['no-clone']" ] && ok "unknown clone + NUL byte tolerated: record kept with commit_basis=no-clone, exit 0" || fail "no-clone/NUL handling: $out"

# ---------------------------------------------------------------- 4. RELATIVE path from scripts/overnight-queue
( cd "$ROOT" && run "$PY" qa/qa_ledger.py summary --no-record ) > "$tmp/sum.out" 2>&1
[ "$(jq1 "d['verdict']" < "$tmp/sum.out")" = "PASS" ] && ok "summary via relative path from scripts/overnight-queue" || fail "relative path: $(cat "$tmp/sum.out")"

# ---------------------------------------------------------------- 5. UNVERIFIED on infrastructure problems, exit 0
empty="$tmp/empty"; mkdir -p "$empty/state"
out="$(env -i PATH="$MINPATH" HOME="$tmp" NTFY_SERVER=http://127.0.0.1:9 OVN_DIR="$empty" "$PY" "$QA/qa_ledger.py" derive --no-record 2>&1)"; r_=$?
[ $r_ -eq 0 ] && [ "$(echo "$out" | jq1 "d['verdict']")" = "UNVERIFIED" ] && ok "missing outcomes.jsonl -> UNVERIFIED, exit 0" || fail "missing outcomes: rc=$r_ $out"
out="$(run "$PY" "$QA/qa_ledger.py" bogus 2>&1)"; [ -n "$out" ] && ok "unknown subcommand prints usage" || fail "no usage"

# ---------------------------------------------------------------- 6. mark-escape (manual)
out="$(run "$PY" "$QA/qa_ledger.py" mark-escape --repo fixrepo --ref "$(SHA c)" --note "found by hand: widgets 500s" --no-record 2>&1)"
[ "$(q 'len([e for e in evs if e["type"]=="escape" and e["manual"] and e["rec"]])')" = "1" ] && ok "mark-escape by commit sha attaches a manual escape to its record" || fail "mark-escape: $out / $(q '[e["type"] for e in evs]')"
run "$PY" "$QA/qa_ledger.py" mark-escape --repo fixrepo --ref "$(SHA c)" --note again --no-record >/dev/null 2>&1
[ "$(q 'len([e for e in evs if e["type"]=="escape"])')" = "1" ] && ok "mark-escape is idempotent per (record, sha)" || fail "mark-escape duplicated"
out="$(run "$PY" "$QA/qa_ledger.py" mark-escape --repo fixrepo --ref deadbeefdeadbeef --note x --no-record 2>&1)"
[ "$(echo "$out" | jq1 "d['verdict']")" = "UNVERIFIED" ] && ok "mark-escape with unresolvable ref -> UNVERIFIED" || fail "bad ref: $out"
out="$(run "$PY" "$QA/qa_ledger.py" mark-escape --repo fixrepo --ref "$(SHA c)" --no-record 2>&1)"; [ -n "$out" ] && ok "mark-escape without note still prints a verdict line" || fail "mark-escape no note"

# ---------------------------------------------------------------- 7. scorecards
mkdir -p "$OVN/state/qa_shadow"
SC=(run "$PY" "$QA/qa_scorecard.py")
"$PY" - "$OVN/state/qa_shadow" "$(SHA a)" "$(SHA old)" <<'PYEOF'
import json, sys
d, a, old = sys.argv[1:4]
with open(d + "/gate_antigaming.jsonl", "w") as f:
    f.write(json.dumps({"gate": "antigaming", "repo": "fixrepo", "ref": a[:12], "verdict": "FAIL", "summary": "removed assert in tests/x.py"}) + "\n")
    f.write(json.dumps({"gate": "antigaming", "repo": "fixrepo", "ref": old[:12], "verdict": "PASS", "summary": "clean"}) + "\n")
with open(d + "/scanners.jsonl", "w") as f:
    f.write(json.dumps({"gate": "scanners", "repo": "fixrepo", "ref": "1234567890ab", "verdict": "PASS", "summary": "elsewhere"}) + "\n")
PYEOF
out="$("${SC[@]}" feature --repo fixrepo --feat fixrepo-20260101-refund 2>&1)"
echo "$out" | grep -q "antigaming" && ok "feature scorecard prints" || fail "feature scorecard: $out"
cells="$("${SC[@]}" feature --repo fixrepo --feat fixrepo-20260101-refund --json | "$PY" -c "import json,sys; c=json.load(sys.stdin)[0]['cells']; print(c['antigaming'],c['scanners'],c['migrations'],c['escape'])")"
[ "$cells" = "FAIL UNVERIFIED NA FAIL" ] && ok "cells: seeded gate FAIL, gate log w/o this ref UNVERIFIED, no log NA, reverted feature escape=FAIL" || fail "cells=$cells"
cells="$("${SC[@]}" feature --repo fixrepo --feat fixrepo-20260101-widget-test --json | "$PY" -c "import json,sys; c=json.load(sys.stdin)[0]['cells']; print(c['antigaming'],c['escape'])")"
[ "$cells" = "PASS PASS" ] && ok "benign mature feature: gate PASS, escape PASS" || fail "benign cells=$cells"
cells="$("${SC[@]}" feature --repo fixrepo --feat fixrepo-20260101-widgets --json | "$PY" -c "import json,sys; c=json.load(sys.stdin)[0]['cells']; print(c['escape'])")"
[ "$cells" = "FAIL" ] && ok "feature with a test-watch/manual escape -> escape FAIL" || fail "widgets escape=$cells"
"${SC[@]}" feature --repo fixrepo --feat nonexistent | grep -q "no ledger records" && ok "unknown feature -> says so, exit 0" || fail "unknown feature output"
out="$("${SC[@]}" promote --repo fixrepo --from "$(SHA old)" --to "origin/main" 2>&1)"
echo "$out" | grep -q "PROMOTE SCORECARD" && echo "$out" | grep -q "ledger feature" && ok "promote scorecard groups commits by feature and counts unattributed" || fail "promote: $out"
echo "$out" | grep -Eqi "overall score|total score|score: *[0-9]" && fail "a composite score appeared" || ok "no composite score in promote output"
out="$("${SC[@]}" promote --repo fixrepo --from nosuchref --to origin/main 2>&1)"; echo "$out" | grep -q "UNVERIFIED" && ok "promote with bad ref -> UNVERIFIED text, exit 0" || fail "promote bad ref: $out"
out="$("${SC[@]}" report --days 30 2>&1)"
echo "$out" | grep -q "per 100" && echo "$out" | grep -q "weak-oracle" && echo "$out" | grep -q "stage-unverified" && ok "report prints escape/100, weak-oracle, stage-unverified" || fail "report: $out"
"${SC[@]}" report --days 30 --json | "$PY" -c "import json,sys; d=json.load(sys.stdin); assert d['records']==4, d" && ok "report --json parses (4 records in window)" || fail "report json"
( cd "$ROOT" && run "$PY" qa/qa_scorecard.py report --days 30 ) | grep -q "ESCAPE REPORT" && ok "scorecard via relative path" || fail "scorecard relative path"

# ---------------------------------------------------------------- 8. cron wrapper (copy of qa/ inside a temp ovn dir so the default OVN_DIR is the temp dir)
CW="$tmp/cw"; mkdir -p "$CW/qa" "$CW/state"; cp "$QA"/qa_common.py "$QA"/qa_ledger.py "$QA"/qa_ledger_cron.sh "$CW/qa/"; chmod +x "$CW/qa/qa_ledger_cron.sh"
cp "$OVN/state/outcomes.jsonl" "$CW/state/"
cenv(){ env -i PATH="$MINPATH" HOME="$tmp" NTFY_SERVER=http://127.0.0.1:9 OVN_REPOS_DIR="$OVN/repos" "$@"; }
cenv bash "$CW/qa/qa_ledger_cron.sh"; r1=$?
[ $r1 -eq 0 ] && [ -s "$CW/state/qa_ledger.jsonl" ] && grep -q "derive" "$CW/logs/qa_ledger_cron.log" && ok "cron wrapper (absolute path, env -i, OVN_DIR defaulted from its own location) derived the ledger, exit 0" || fail "cron abs: rc=$r1"
rm -f "$CW/state/qa_ledger."*
( cd "$CW" && cenv bash qa/qa_ledger_cron.sh ); r2=$?
[ $r2 -eq 0 ] && [ -s "$CW/state/qa_ledger.jsonl" ] && ok "cron wrapper via RELATIVE path resolves its own dir before cd" || fail "cron relative: rc=$r2"
( cd "$CW/qa" && cenv bash ./qa_ledger_cron.sh ); [ $? -eq 0 ] && ok "cron wrapper via ./name from inside qa/" || fail "cron ./name"
if command -v flock >/dev/null 2>&1; then
  ( exec 8>"$CW/state/qa_ledger.lock"; flock -n 8; cenv bash "$CW/qa/qa_ledger_cron.sh"; echo $? > "$tmp/lockrc" )
  [ "$(cat "$tmp/lockrc")" = "0" ] && grep -q "holds the lock" "$CW/logs/qa_ledger_cron.log" && ok "lock contention -> skipped quietly, exit 0" || fail "lock contention"
fi
mv "$CW/qa/qa_ledger.py" "$CW/qa/qa_ledger.py.bak"
cenv bash "$CW/qa/qa_ledger_cron.sh"; [ $? -eq 0 ] && ok "broken install (derive script missing) still exits 0" || fail "cron failed loudly"
mv "$CW/qa/qa_ledger.py.bak" "$CW/qa/qa_ledger.py"

# ---------------------------------------------------------------- 8b. FIX round: hostile rows (reviewer repros) - each fails on the pre-fix code
P2="$tmp/ovn2"; mkdir -p "$P2/state"
now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
good='{"ts":"'"$now_iso"'","repo":"fixrepo","id":"g1","type":"aider_fix","tier":"2","category":"endpoint","class":"landed","status":"pushed(tests:pass)","duration_s":60,"item_hash":"g1","feat_tag":"fixrepo-20260101-good"}'
run2(){ env -i PATH="$MINPATH" HOME="$tmp" NTFY_SERVER=http://127.0.0.1:9 OVN_DIR="$P2" OVN_REPOS_DIR="$OVN/repos" "$@"; }
{
  echo '{"class":"landed","repo":"fixrepo","status":5,"ts":"'"$now_iso"'","id":"p1"}'
  echo '{"class":"landed","repo":["a","b"],"status":"pushed(x)","ts":"'"$now_iso"'","id":"p2"}'
  echo '{"class":"landed","repo":"fixrepo","status":"pushed(x)","ts":12345,"id":"p3"}'
  echo '{"class":"landed","repo":"fixrepo","status":"pushed(x)","ts":"'"$now_iso"'","id":"p4","feat_tag":{"a":1},"item_hash":["x"],"duration_s":"abc","tier":["3"],"attempt":{"n":1}}'
  echo '{"class":"landed","repo":"../repos/fixrepo","status":"pushed(x)","ts":"'"$now_iso"'","id":"p5"}'
  echo '[1,2]'; echo 'null'; echo '"str"'
  echo "$good"
} > "$P2/state/outcomes.jsonl"
sz2="$(wc -c < "$P2/state/outcomes.jsonl" | tr -d ' ')"
out="$(run2 "$PY" "$QA/qa_ledger.py" derive --no-record 2>&1)"
[ "$(cat "$P2/state/qa_ledger.cursor" 2>/dev/null)" = "$sz2" ] && ok "poison rows (non-string status, list repo, int ts, path-traversal repo, non-dict rows) do NOT freeze the cursor" || fail "cursor stuck: $out"
[ "$(echo "$out" | jq1 "d['verdict']")" = "FLAG" ] && [ "$(echo "$out" | jq1 "d['details']['skipped_rows'] >= 7")" = "True" ] && ok "poison rows are counted and the verdict is FLAG (not PASS, not a crash)" || fail "poison verdict: $out"
LED2="$P2/state/qa_ledger.jsonl"
[ "$("$PY" -c "import json;print(sum(1 for l in open('$LED2') if json.loads(l)['kind']=='landed' and json.loads(l)['id']=='g1'))")" = "1" ] && ok "the valid row after the poison rows is still recorded" || fail "good row lost after poison"
[ "$("$PY" -c "import json;print(sum(1 for l in open('$LED2') if json.loads(l)['kind']=='landed' and json.loads(l)['id']=='p4'))")" = "1" ] && ok "dict/list/str-typed optional fields are coerced, row kept (no unhashable crash)" || fail "p4 not recorded"
printf '%s\n' "$good" | sed 's/"g1"/"g2"/g' >> "$P2/state/outcomes.jsonl"
run2 "$PY" "$QA/qa_ledger.py" derive --no-record >/dev/null 2>&1
[ "$("$PY" -c "import json;print(sum(1 for l in open('$LED2') if json.loads(l)['kind']=='landed' and json.loads(l)['id']=='g2'))")" = "1" ] && ok "later rows keep flowing after poison (ledger not frozen)" || fail "ledger frozen after poison"
out="$(run2 "$PY" "$QA/qa_scorecard.py" report --days 30 2>&1)"
echo "$out" | grep -q "scorecard crashed" && fail "scorecard crashed on non-dict row: $out" || ok "scorecard report survives non-dict / wrong-typed outcomes rows"
echo "$out" | grep -q "WARNING: .* unreadable" && ok "scorecard report says how many outcome rows it could not read" || fail "no unreadable-rows warning: $out"
# hostile shadow rows must not crash a card, and an unreadable verdict is never a PASS
mkdir -p "$P2/state/qa_shadow"; printf '%s\n' '[1]' '{"gate":["x"],"verdict":{"a":1},"ref":99}' '{"gate":"antigaming","repo":"fixrepo","verdict":["PASS"],"ref":"'"$(SHA a | cut -c1-12)"'"}' > "$P2/state/qa_shadow/gate_antigaming.jsonl"
cp "$LED" "$P2/state/qa_ledger.jsonl"
cells="$(run2 "$PY" "$QA/qa_scorecard.py" feature --repo fixrepo --feat fixrepo-20260101-refund --json 2>&1 | "$PY" -c "import json,sys; print(json.load(sys.stdin)[0]['cells']['antigaming'])")"
[ "$cells" = "UNVERIFIED" ] && ok "hostile shadow rows: unreadable gate verdict -> UNVERIFIED (never PASS), no crash" || fail "shadow cell=$cells"
out="$(run2 "$PY" "$QA/qa_scorecard.py" feature --repo fixrepo --feat fixrepo-20260101-widget-test 2>&1)"
echo "$out" | grep -q "NOT proof of no escape" && ok "a clean escape cell states it is a lower bound, not proof" || fail "escape PASS note missing"
# hand-corrupted ledger lines are skipped, not fatal
printf '%s\n' '{"kind":"landed","key":5,"repo":["x"]}' '[1]' '{"kind":"event","key":"k"}' >> "$P2/state/qa_ledger.jsonl"
out="$(run2 "$PY" "$QA/qa_ledger.py" summary --no-record 2>&1)"
[ "$(echo "$out" | jq1 "d['verdict']")" = "PASS" ] && ok "malformed ledger lines are skipped by readers" || fail "corrupt ledger: $out"
# mark-escape input hardening
before="$(wc -l < "$LED" | tr -d ' ')"
for badrepo in "../repos/fixrepo" "../../etc" "-x" ".hidden" "a/b"; do
  out="$(run "$PY" "$QA/qa_ledger.py" mark-escape --repo "$badrepo" --ref "$(SHA c)" --note x --no-record 2>&1)"
  [ "$(echo "$out" | jq1 "d['verdict']")" = "UNVERIFIED" ] && ok "mark-escape rejects repo '$badrepo'" || fail "repo '$badrepo' accepted: $out"
done
for badref in "-x" "--output=/tmp/x" "a b"; do
  out="$(run "$PY" "$QA/qa_ledger.py" mark-escape --repo fixrepo --ref "$badref" --note x --no-record 2>&1)"
  echo "$out" | grep -q "commit-ish" && ok "mark-escape rejects ref '$badref' before git sees it" || fail "ref '$badref': $out"
done
[ "$(wc -l < "$LED" | tr -d ' ')" = "$before" ] && ok "rejected mark-escape inputs wrote nothing" || fail "rejected input wrote to ledger"
out="$(run "$PY" "$QA/qa_ledger.py" mark-escape --repo fixrepo --ref "$(SHA old)" --note "attach test" --no-record 2>&1)"
echo "$out" | grep -q '"verdict": "PASS"' && ok "mark-escape on a commit owned by a record: PASS" || fail "owned commit: $out"
out="$(run "$PY" "$QA/qa_ledger.py" mark-escape --repo fixrepo --ref "$(SHA queue_fix)" --note "unattached" --no-record 2>&1)"
[ "$(echo "$out" | jq1 "d['verdict']")" = "FLAG" ] && ok "mark-escape that attaches to no record -> FLAG (stored but invisible on cards), not PASS" || fail "unattributed escape verdict: $out"

# ---------------------------------------------------------------- 9. nothing touched the network
[ ! -s "$tmp/curl.log" ] && ok "no curl/ntfy call was made by any entry point" || fail "network call attempted: $(cat "$tmp/curl.log")"
# real state untouched
[ ! -e "$ROOT/state/qa_ledger.jsonl" ] && ok "real state/ untouched (OVN_DIR respected)" || fail "wrote into the real state dir"

exit $rc
