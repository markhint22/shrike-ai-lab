#!/usr/bin/env bash
# Regression: billwatch_summary_backfill.py (nightly, time-boxed AI summary backfill). psycopg2 is a stub module (the box has
# none, and we must never reach a real prod DB) that serves bills from a JSON file and records every INSERT; the LLM is a
# throw-away 127.0.0.1 http.server that answers according to the bill title. HOME is a temp dir (token ledger lands there).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT=""; for c in "$HERE/../../billwatch_summary_backfill.py" "$HERE/../billwatch_summary_backfill.py" "$HERE/billwatch_summary_backfill.py"; do [ -f "$c" ] && { SUT="$c"; break; }; done
[ -n "$SUT" ] || { echo "billwatch_summary_backfill.py not found"; exit 2; }
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; SRV=""; trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME" "$T/stub"

# ---- stub psycopg2 ----
cat > "$T/stub/psycopg2.py" <<'PY'
import json, os
LOG = os.environ["FAKE_DB_LOG"]
def _w(rec):
    open(LOG, "a").write(json.dumps(rec) + "\n")
class Cur:
    def execute(self, sql, params=None):
        self.sql = " ".join(sql.split())
        _w({"sql": self.sql, "params": params})
    def fetchall(self):
        return [tuple(b) for b in json.load(open(os.environ["FAKE_BILLS"]))]
    def fetchone(self):
        return (int(os.environ.get("FAKE_REMAINING", "0")),)
class Conn:
    autocommit = False
    def cursor(self): return Cur()
    def close(self): _w({"closed": True})
def connect(url, connect_timeout=None):
    _w({"connect": url, "connect_timeout": connect_timeout}); return Conn()
PY
# ---- fake LLM ----
cat > "$T/llm.py" <<'PY'
import json, sys, http.server
PORTFILE, REQLOG = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        prompt = body["messages"][0]["content"]
        open(REQLOG, "a").write(json.dumps({"auth": self.headers.get("Authorization"), "path": self.path,
                                            "model": body["model"], "max_tokens": body["max_tokens"], "prompt": prompt}) + "\n")
        if "ERRBILL" in prompt:
            self.send_response(500); self.end_headers(); self.wfile.write(b"boom"); return
        if "JSONBILL" in prompt:
            c = 'Sure! {"summary": " Does a thing. ", "key_points": "a\\nb", "impact": "Everyone."} hope that helps'
        elif "NOSUMM" in prompt:
            c = '{"summary": "", "key_points": "k", "impact": "i"}'
        elif "BADJSON" in prompt:
            c = 'here { not valid json } done'
        elif "EMPTYBILL" in prompt:
            c = '   '
        elif "LONGPROSE" in prompt:
            c = "x" * 2000
        else:
            c = "Plain prose summary."
        out = json.dumps({"choices": [{"message": {"content": c}}], "usage": {"completion_tokens": 7, "prompt_tokens": 100}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(out)
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(PORTFILE, "w").write(str(s.server_address[1])); s.serve_forever()
PY
python3 "$T/llm.py" "$T/port" "$T/llm_req.log" & SRV=$!
for i in $(seq 1 50); do [ -s "$T/port" ] && break; sleep 0.1; done
PORT="$(cat "$T/port" 2>/dev/null)"; [ -n "$PORT" ] || { echo "fake LLM failed to start"; exit 2; }

run(){  # extra env assignments as args; prints nothing, sets rc, stdout in $T/out
  : > "$T/db.log"; : > "$T/llm_req.log"
  env PYTHONPATH="$T/stub" FAKE_DB_LOG="$T/db.log" FAKE_BILLS="$T/bills.json" LITELLM_BASE="http://127.0.0.1:$PORT" \
      BILLWATCH_DB_URL="postgres://stub/db" "$@" python3 "$SUT" > "$T/out" 2> "$T/err"; rc=$?
}
inserts(){ python3 -c '
import json,sys
for l in open(sys.argv[1]):
    r=json.loads(l)
    if r.get("sql","").startswith("INSERT"): print(json.dumps(r["params"]))' "$T/db.log"; }
ins(){ python3 - "$T/db.log" "$1" "$2" <<'P'
import json,sys
rows={}
for l in open(sys.argv[1]):
    r=json.loads(l)
    if r.get("sql","").startswith("INSERT"): rows[r["params"][0]]=r["params"]
bid=int(sys.argv[2]); p=rows.get(bid)
chk=sys.argv[3]
if chk=="json": print(1 if p and p[1:6]==["Does a thing.","a\nb","Everyone.",7,"test-model"] and p[6]>=0 else 0)
elif chk=="prose": print(1 if p and p[1:6]==["Plain prose summary.","","",7,"test-model"] else 0)
elif chk=="cap": print(1 if p and p[1]=="x"*1200 and p[2]=="" and p[3]=="" else 0)
elif chk=="nosumm": print(1 if p and p[1]=='{"summary": "", "key_points": "k", "impact": "i"}' else 0)
elif chk=="badjson": print(1 if p and p[1]=="here { not valid json } done" else 0)
P
}
LEDGER="$HOME/overnight-queue/state/token_ledger.jsonl"

# 1. no DB url
env -u BILLWATCH_DB_URL PYTHONPATH="$T/stub" FAKE_DB_LOG="$T/db.log" python3 "$SUT" > "$T/out" 2>&1; rc=$?
ok "no BILLWATCH_DB_URL -> exit 1 with ERROR log" "$([ $rc = 1 ] && grep -q 'ERROR: BILLWATCH_DB_URL not set' "$T/out" && echo 1 || echo 0)"

# 2. no bills need summaries
echo '[]' > "$T/bills.json"; run FAKE_REMAINING=0
ok "empty bill list -> exit 0, no inserts" "$([ $rc = 0 ] && [ -z "$(inserts)" ] && echo 1 || echo 0)"
ok "empty: 'backfill done: +0' line logged" "$(grep -q 'backfill done: +0 real summaries' "$T/out" && grep -q '0 bills still need one' "$T/out" && echo 1 || echo 0)"
ok "empty: no LLM calls, no token ledger" "$([ ! -s "$T/llm_req.log" ] && [ ! -e "$LEDGER" ] && echo 1 || echo 0)"
ok "connects with connect_timeout=15 and closes the connection" "$(grep -q '"connect_timeout": 15' "$T/db.log" && grep -q '"closed": true' "$T/db.log" && echo 1 || echo 0)"
ok "candidate query is anti-join on bill_summaries, newest first, parametrised LIMIT 15 default" "$(grep -q 'NOT EXISTS (SELECT 1 FROM bill_summaries' "$T/db.log" && grep -q 'ORDER BY b.id DESC LIMIT %s' "$T/db.log" && grep -q '"params": \[15\]' "$T/db.log" && echo 1 || echo 0)"

# 3. mixed batch
python3 - "$T/bills.json" <<'P'
import json,sys
long_text = "L" * 5000
json.dump([
 [1, "JSONBILL act", "JB", "sum one"],
 [2, "plain bill", None, None],
 [3, "ERRBILL act", None, None],
 [4, "NOSUMM act", None, None],
 [5, "BADJSON act", None, None],
 [6, "EMPTYBILL act", None, None],
 [7, "LONGPROSE act", None, None],
 [8, None, None, long_text],
], open(sys.argv[1], "w"))
P
run FAKE_REMAINING=3 LLM_MODEL=test-model LITELLM_MASTER_KEY=sk-test MAX_BILLS=50
ok "mixed batch: exit 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "LLM request: custom model, bearer key, chat-completions path, max_tokens 700" "$(python3 - "$T/llm_req.log" <<'P'
import json,sys
r=[json.loads(l) for l in open(sys.argv[1])]
print(1 if r and all(x["model"]=="test-model" and x["auth"]=="Bearer sk-test" and x["path"]=="/v1/chat/completions" and x["max_tokens"]==700 for x in r) else 0)
P
)"
ok "MAX_BILLS flows into the SQL LIMIT parameter" "$(grep -q '"params": \[50\]' "$T/db.log" && echo 1 || echo 0)"
ok "prompt carries title and requests JSON-only output" "$(grep -q 'Bill title: JSONBILL act' "$T/llm_req.log" && grep -q 'Respond with ONLY a JSON object' "$T/llm_req.log" && echo 1 || echo 0)"
ok "bill text joins title/short_title/summary, truncated to 3000 chars" "$(python3 - "$T/llm_req.log" <<'P'
import json,sys
r=[json.loads(l)["prompt"] for l in open(sys.argv[1])]
a=[p for p in r if "JSONBILL" in p][0]; b=[p for p in r if "Bill title: \nBill text" in p or "LLLL" in p][0]
seg=b.split("Bill text: ",1)[1].split("\n\nRespond",1)[0]
print(1 if "JB\n\nsum one" in a and len(seg)==3000 else 0)
P
)"
ok "LLM errors (HTTP 500) are logged and skipped, run continues" "$(grep -q 'bill 3: LLM error' "$T/out" && echo 1 || echo 0)"
ok "empty generation is skipped, never persisted as a placeholder" "$(grep -q 'bill 6: empty generation, skipping' "$T/out" && echo 1 || echo 0)"
N="$(inserts | wc -l | tr -d ' ')"
ok "6 of 8 bills inserted (500 + empty skipped)" "$([ "$N" = 6 ] && echo 1 || echo 0)"
ok "valid JSON (embedded in chatter) parsed: stripped summary/key_points/impact" "$(ins 1 json)"
ok "plain prose fallback stored as summary with empty key_points/impact" "$(ins 2 prose)"
ok "JSON with empty summary falls back to raw text" "$(ins 4 nosumm)"
ok "invalid-JSON braces fall back to raw text" "$(ins 5 badjson)"
ok "prose fallback capped at 1200 chars" "$(ins 7 cap)"
ok "null title handled (bill 8 summarised from bill text)" "$(inserts | grep -q '^\[8,' && echo 1 || echo 0)"
ok "insert SQL writes version 1 + now() timestamps" "$(grep -q 'INSERT INTO bill_summaries (bill_id, summary, key_points, impact_analysis, tokens_used, model, version, generation_time_ms, created_at, updated_at) VALUES (%s,%s,%s,%s,%s,%s,1,%s,now(),now())' "$T/db.log" && echo 1 || echo 0)"
ok "final log reports +6 and remaining count from DB" "$(grep -q 'backfill done: +6 real summaries' "$T/out" && grep -q '3 bills still need one' "$T/out" && echo 1 || echo 0)"
ok "per-bill 'summarized' log lines with token count" "$(grep -q 'bill 1: summarized (7 tok,' "$T/out" && echo 1 || echo 0)"
ok "token ledger written to HOME state with run totals" "$(python3 - "$LEDGER" <<'P'
import json,sys
r=[json.loads(l) for l in open(sys.argv[1])]
x=r[-1]
# 7 LLM calls answered (bill 3 errored before counting): 6 inserts + 1 empty = 7 calls*(100 in / 7 out)
print(1 if len(r)==1 and x["source"]=="billwatch-summary-backfill" and x["repo"]=="billwatch" and x["tokens_sent"]==700 and x["tokens_recv"]==49 and x["ts"].endswith("Z") else 0)
P
)"
run FAKE_REMAINING=0
ok "ledger is append-only across runs" "$([ "$(wc -l < "$LEDGER" | tr -d ' ')" = 2 ] && echo 1 || echo 0)"

# 4. time budget
rm -f "$LEDGER"; run MAX_SECONDS=-1 FAKE_REMAINING=8
ok "exhausted time budget -> stops before any LLM call/insert" "$(grep -q 'time budget reached' "$T/out" && [ -z "$(inserts)" ] && [ ! -s "$T/llm_req.log" ] && echo 1 || echo 0)"
ok "time-boxed run with zero work writes no ledger row" "$([ ! -e "$LEDGER" ] && echo 1 || echo 0)"

# 5. ledger write failure is non-fatal
rm -rf "$HOME/overnight-queue"; mkdir -p "$HOME/overnight-queue"; : > "$HOME/overnight-queue/state"   # 'state' is a FILE -> makedirs raises OSError
echo '[[1,"plain bill",null,null]]' > "$T/bills.json"; run FAKE_REMAINING=0
ok "unwritable ledger dir -> OSError swallowed, exit 0, insert still done" "$([ $rc = 0 ] && [ -n "$(inserts)" ] && ! grep -q Traceback "$T/err" && echo 1 || echo 0)"

# 6. LLM unreachable
run LITELLM_BASE="http://127.0.0.1:1" FAKE_REMAINING=1
ok "LLM unreachable -> error logged per bill, no inserts, exit 0" "$([ $rc = 0 ] && grep -q 'bill 1: LLM error' "$T/out" && [ -z "$(inserts)" ] && echo 1 || echo 0)"
echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
