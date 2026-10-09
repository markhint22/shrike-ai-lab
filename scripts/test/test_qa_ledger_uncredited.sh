#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity round-3 review): a green push the auto-credit refused to tick is outcome class `landed-uncredited` (neutral: not a landing for the pass
# rate). The commits are REAL code on claude/feature/develop/staging/prod, so the QA ledger (risk classification, escapes, scorecards) must still record them - before this
# change qa_ledger.is_landed() required class == "landed" and such pushes never entered the ledger. Drives the REAL `qa_ledger.py derive` on a throwaway repo (OVN_DIR is a temp dir).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"; QA="$ROOT/qa"
[ -f "$QA/qa_ledger.py" ] || { echo "  SKIP: qa/qa_ledger.py not found"; exit 0; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
OVN="$tmp/ovn"; mkdir -p "$OVN/state" "$OVN/repos"
run(){ env -i PATH="/usr/bin:/bin:$(dirname "$PY")" HOME="$tmp" NTFY_SERVER=http://127.0.0.1:9 OVN_DIR="$OVN" OVN_REPOS_DIR="$OVN/repos" "$@"; }
"$PY" - "$OVN" <<'PYEOF' || { echo "  FAIL fixture build failed"; exit 1; }
import json, os, subprocess, sys, time
ovn = sys.argv[1]; rd = os.path.join(ovn, "repos", "fixrepo"); os.makedirs(rd)
now = int(time.time()); D = 86400
def git(*a, when=None):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    if when: env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = "%d +0000" % when
    return subprocess.run(["git", "-C", rd] + list(a), env=env, capture_output=True, text=True, check=True).stdout.strip()
git("init", "-q", "-b", "main")
def commit(path, content, msg, when):
    fp = os.path.join(rd, path); os.makedirs(os.path.dirname(fp), exist_ok=True); open(fp, "a").write(content + "\n")
    git("add", path); git("commit", "-q", "-m", msg, when=when); return git("rev-parse", "HEAD")
T1, T2 = now - 6 * D, now - 5 * D
sha1 = commit("backend/app/routers/widgets.py", "def widgets(): pass", "feat: widgets endpoint", T1)
sha2 = commit("backend/app/billing/stripe_client.py", "def refund(): pass", "feat: add refund (green push, credit refused)", T2)
for ref in ("origin/overnight/feature", "origin/develop", "origin/main"):
    git("update-ref", "refs/remotes/" + ref, "HEAD")
def iso(e): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))
def row(e, ident, cls, status="pushed(tests:pass)", repo="fixrepo"):
    return json.dumps({"ts": iso(e + 60), "repo": repo, "id": ident, "type": "aider_fix", "tier": "3", "category": "endpoint", "class": cls, "severity": "good" if cls == "landed" else "neutral",
                       "attempt": 1, "fail_reason": "", "status": status, "duration_s": 120, "item_hash": ident, "feat_tag": "fixrepo-20260101-" + ident})
lines = [row(T1, "i-credited", "landed"), row(T2, "i-uncred", "landed-uncredited"),
         row(T2 + 500, "i-unc-nopush", "landed-uncredited", status="U OVERNIGHT_PROGRESS.md"),   # same status guard as a landed row: a non-push status is no landing
         row(T2 + 600, "i-noop", "noop", status="no-op(reverted-red)")]
open(os.path.join(ovn, "state", "outcomes.jsonl"), "w").write("\n".join(lines) + "\n")
json.dump({"sha2": sha2}, open(os.path.join(ovn, "..", "fx.json"), "w"))
PYEOF
LED="$OVN/state/qa_ledger.jsonl"
q(){ "$PY" - "$LED" "$1" <<'PYEOF'
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1]) if json.loads(l)["kind"] == "landed"]
print(eval(sys.argv[2]))
PYEOF
}
run "$PY" "$QA/qa_ledger.py" derive --no-record --no-events >/dev/null 2>&1
ok "derive: the credited landing AND the uncredited push are ledger records (2), the non-push uncredited row and the noop row are not" "[ \"\$(q 'sorted(r[\"id\"] for r in recs)')\" = \"['i-credited', 'i-uncred']\" ]"
ok "the uncredited record carries the 'uncredited' flag (visible as not credited); the credited one does not" "[ \"\$(q '\"uncredited\" in [r for r in recs if r[\"id\"]==\"i-uncred\"][0][\"flags\"]')\" = True ] && [ \"\$(q '\"uncredited\" in [r for r in recs if r[\"id\"]==\"i-credited\"][0][\"flags\"]')\" = False ]"
ok "the uncredited push is risk-classified from its REAL commit (billing file -> risk A) and the commit is attributed" "[ \"\$(q '[r[\"risk\"] for r in recs if r[\"id\"]==\"i-uncred\"][0]')\" = A ] && [ \"\$(q '[r[\"commits\"][0] for r in recs if r[\"id\"]==\"i-uncred\"][0]')\" = \"\$(python3 -c \"import json;print(json.load(open('$tmp/fx.json'))['sha2'])\")\" ]"
ok "is_landed unit: landed-uncredited + pushed => True; + non-push status => False; unknown class => False" "'$PY' -c \"
import sys; sys.path.insert(0,'$QA'); import qa_ledger as q
assert q.is_landed({'class':'landed-uncredited','repo':'r','status':'pushed(tests:pass)'})
assert not q.is_landed({'class':'landed-uncredited','repo':'r','status':'U x'})
assert not q.is_landed({'class':'landed-whatever','repo':'r','status':'pushed(tests:pass)'})
assert q.is_landed({'class':'landed','repo':'r','status':'pushed(tests:pass)'})
assert q.clean_outcome({'class':'landed-uncredited'}) == (None, True)
\""
# MUTATION: the old is_landed (class == 'landed' only) drops the uncredited push - the first two assertions would fail
cp -R "$QA" "$tmp/qa_mut"; sed -i.bak 's/d.get("class") in LANDED_CLASSES and/d.get("class") == "landed" and/' "$tmp/qa_mut/qa_ledger.py"
ok "MUTATION sanity: the mutant differs from the real file" "! cmp -s '$QA/qa_ledger.py' '$tmp/qa_mut/qa_ledger.py'"
rm -f "$LED" "$OVN/state/qa_ledger.cursor"* "$OVN/state/qa_ledger_"* 2>/dev/null; ls "$OVN/state" >/dev/null
run "$PY" "$tmp/qa_mut/qa_ledger.py" derive --no-record --no-events >/dev/null 2>&1
ok "MUTATION: with the old is_landed the uncredited push never enters the ledger (the derive assertion above would fail)" "[ \"\$(q 'sorted(r[\"id\"] for r in recs)')\" = \"['i-credited']\" ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
