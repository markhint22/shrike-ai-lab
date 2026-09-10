#!/usr/bin/env python3
"""billwatch_summary_backfill.py — nightly, TIME-BOXED AI-summary backfill for BillWatch prod.

Why this exists: BillWatch's Railway backend has no LLM it can reach (it hardcoded a localhost Ollama
that doesn't exist on Railway), so every AI bill-summary silently failed and — worse — persisted a
"temporarily unavailable" placeholder that blocked the real summary forever. All 151 prod summaries were
placeholders (cleaned 2026-09-09). This job runs on the GPU box (where the fleet's local LLM lives),
connects to BillWatch's prod DB over its public proxy, finds bills with no summary, generates a real one
with qwen-dflash-27B, and writes it back.

TIME-BOXED so it does a little each night and catches up without hogging the fleet's LLM queue:
stops after MAX_BILLS or MAX_SECONDS, whichever comes first. At 15 bills/night it clears ~151 in ~10 nights.

Env (set by the cron wrapper; DB url lives in a gitignored state file, never committed):
  BILLWATCH_DB_URL   postgres public-proxy url
  LITELLM_BASE       default http://localhost:4000
  LITELLM_MASTER_KEY default sk-shrike-local
  LLM_MODEL          default qwen-dflash-27B
  MAX_BILLS          default 15
  MAX_SECONDS        default 600
"""
import os, sys, json, time, urllib.request
import psycopg2

DB      = os.environ.get("BILLWATCH_DB_URL")
LITELLM = os.environ.get("LITELLM_BASE", "http://localhost:4000")
LKEY    = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")
MODEL   = os.environ.get("LLM_MODEL", "qwen-dflash-27B")
MAX_BILLS   = int(os.environ.get("MAX_BILLS", "15"))
MAX_SECONDS = int(os.environ.get("MAX_SECONDS", "600"))

def log(m): print(f"{time.strftime('%F %T')} {m}", flush=True)

def llm(prompt):
    body = json.dumps({"model": MODEL, "messages": [{"role": "user", "content": prompt}],
                       "max_tokens": 700, "temperature": 0.2}).encode()
    req = urllib.request.Request(f"{LITELLM}/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json",
                                          "Authorization": f"Bearer {LKEY}"})
    with urllib.request.urlopen(req, timeout=150) as r:
        d = json.loads(r.read())
    return d["choices"][0]["message"]["content"], int(d.get("usage", {}).get("completion_tokens", 0))

def make_summary(title, text):
    prompt = (
        "You are summarizing U.S. federal legislation for everyday citizens. Neutral, plain English, no jargon.\n"
        f"Bill title: {title}\n"
        f"Bill text: {text[:3000]}\n\n"
        'Respond with ONLY a JSON object, no prose:\n'
        '{"summary": "<2-3 sentence plain-English summary of what the bill does>", '
        '"key_points": "<3-5 short points, one per line>", '
        '"impact": "<1-2 sentences: who it affects and how>"}'
    )
    raw, toks = llm(prompt)
    i, j = raw.find("{"), raw.rfind("}")
    if i >= 0 and j > i:
        try:
            o = json.loads(raw[i:j+1])
            s = (o.get("summary") or "").strip()
            if s:
                return s, (o.get("key_points") or "").strip(), (o.get("impact") or "").strip(), toks
        except Exception:
            pass
    t = raw.strip()
    return (t[:1200], "", "", toks) if t else (None, None, None, toks)  # never a placeholder

def main():
    if not DB:
        log("ERROR: BILLWATCH_DB_URL not set"); sys.exit(1)
    start = time.time()
    conn = psycopg2.connect(DB, connect_timeout=15); conn.autocommit = True
    cur = conn.cursor()
    cur.execute("""SELECT b.id, b.title, b.short_title, b.summary FROM bills b
                   WHERE NOT EXISTS (SELECT 1 FROM bill_summaries s WHERE s.bill_id = b.id)
                   ORDER BY b.id DESC LIMIT %s""", (MAX_BILLS,))
    bills = cur.fetchall()
    done = 0
    for bid, title, short_title, bsummary in bills:
        if time.time() - start > MAX_SECONDS:
            log("time budget reached — stopping for tonight"); break
        text = "\n\n".join(x for x in (title, short_title, bsummary) if x)
        t0 = time.time()
        try:
            summ, kp, impact, toks = make_summary(title or "", text)
        except Exception as e:
            log(f"  bill {bid}: LLM error {e}"); continue
        if not summ:  # never persist a non-summary (that was the original bug)
            log(f"  bill {bid}: empty generation, skipping (will retry)"); continue
        gen_ms = int((time.time() - t0) * 1000)
        cur.execute("""INSERT INTO bill_summaries
                       (bill_id, summary, key_points, impact_analysis, tokens_used, model,
                        version, generation_time_ms, created_at, updated_at)
                       VALUES (%s,%s,%s,%s,%s,%s,1,%s,now(),now())""",
                    (bid, summ, kp, impact, toks, MODEL, gen_ms))
        done += 1
        log(f"  bill {bid}: summarized ({toks} tok, {gen_ms}ms)")
    cur.execute("""SELECT count(*) FROM bills b
                   WHERE NOT EXISTS (SELECT 1 FROM bill_summaries s WHERE s.bill_id = b.id)""")
    remaining = cur.fetchone()[0]
    conn.close()
    log(f"backfill done: +{done} real summaries in {int(time.time()-start)}s; {remaining} bills still need one")

if __name__ == "__main__":
    main()
