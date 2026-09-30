#!/usr/bin/env bash
# Runs the REAL scripts/ovn_tier_stats.py (by its real path, so coverage attributes to it) as a subprocess with $HOME pointed at
# throwaway trees holding synthetic state/outcomes.jsonl + token_ledger.jsonl. Covers every mode (default tier table, --headline,
# --tokens-only, --oneline, --all-time, hours window), every empty-data exit, malformed rows, the per-item rate, hidden reverts,
# benign-only tiers, the Ongoing-lane label, token formatting, and the pipeline-overhead ledger section.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=""
for c in "$HERE/../ovn_tier_stats.py" "$HERE/../../scripts/ovn_tier_stats.py" "$HERE/ovn_tier_stats.py"; do [ -f "$c" ] && { TS="$c"; break; }; done
[ -n "$TS" ] || { echo "  SKIP: ovn_tier_stats.py not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
has(){ printf '%s' "$OUT" | grep -qF -- "$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

python3 - "$T" <<'PY'
import json, os, sys, time
T = sys.argv[1]
now = time.time()
def iso(age_min):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - age_min * 60))
def write(name, rows=None, ledger=None, raw_out=None, raw_ledger=None):
    st = os.path.join(T, name, "overnight-queue", "state")
    os.makedirs(st, exist_ok=True)
    if rows is not None or raw_out is not None:
        with open(os.path.join(st, "outcomes.jsonl"), "w") as f:
            for r in rows or []:
                r = dict(r); age = r.pop("age", 10); r.setdefault("ts", iso(age)); f.write(json.dumps(r) + "\n")
            for l in raw_out or []:
                f.write(l + "\n")
    if ledger is not None or raw_ledger is not None:
        with open(os.path.join(st, "token_ledger.jsonl"), "w") as f:
            for r in ledger or []:
                r = dict(r); age = r.pop("age", 10); r.setdefault("ts", iso(age)); f.write(json.dumps(r) + "\n")
            for l in raw_ledger or []:
                f.write(l + "\n")
def R(cls, sev, tier="1", status="", **kw):
    d = {"class": cls, "severity": sev, "status": status}
    if tier is not None: d["tier"] = tier
    d.update(kw); return d

full = [
  R("landed", "good", "1", item_hash="h1", tokens_sent=1000, tokens_recv=500),
  R("landed", "good", "1", item_hash="h2", tokens_sent=2000, tokens_recv=1000),
  R("reverted", "bad", "1", item_hash="h3", fail_reason="timeout", tokens_sent=3000, tokens_recv=2000),
  R("noop", "bad", "1", "no-op(reverted-red)", item_hash="h4", tokens_sent=500, tokens_recv=100),
  R("noop", "neutral", "1", "no-op(ALREADY-DONE)"),
  R("error", "bad", "1", tokens_sent=100, tokens_recv=0),
  R("noop", "neutral", "2", "no-op(BLOCKED)"),                       # T2 only benign
  R("landed", "good", None, tokens_sent=10, tokens_recv=5),          # no tier -> Ongoing-lane
  R("landed", "good", "9", tokens_sent=0, tokens_recv=0),            # unknown tier -> "?"
  R("noop", "neutral", "3", "no-op(NEEDS-DECISION)"),
  R("landed", "good", "3", age=600),                                 # 10h old: outside the 3h window
]
ledger = [
  {"source": "planner", "tokens_sent": 1000, "tokens_recv": 400},
  {"source": "planner", "tokens_sent": 1000, "tokens_recv": 400},
  {"source": "groom", "tokens_sent": 500, "tokens_recv": 100},
  {"tokens_sent": None, "tokens_recv": None},                        # source missing -> '?', zero tokens
  {"source": "old", "tokens_sent": 999999, "tokens_recv": 1, "age": 900},
]
write("full", full, ledger, raw_out=["", "not json", '{"ts":"garbage","class":"landed"}', '{"class":"landed"}'], raw_ledger=["", "{bad", '{"source":"x"}', '{"source":"x","ts":"nope"}'])
write("empty_files", [], [])
os.makedirs(os.path.join(T, "nodata", "overnight-queue", "state"), exist_ok=True)
write("benign_only", [R("noop", "neutral", "2", "no-op(ALREADY-DONE)"), R("skipped", "expected", "2")])
write("skipped_only", [R("skipped", "expected", "1"), R("skipped", "expected", "1")])
write("landed_only", [R("landed", "good", "1", tokens_sent=1800, tokens_recv=999), R("landed", "good", "1", tokens_sent=250000, tokens_recv=2500000)])
write("headline", [
  R("landed", "good"), R("reverted", "bad"), R("noop", "bad", "1", "no-op(reverted-red)"), R("noop", "bad", "1", "no-op(stage-unverified)"),
  R("noop", "neutral", "1", "no-op(ALREADY-DONE)")])
write("ledger_only", [], [{"source": "groom", "tokens_sent": 120000, "tokens_recv": 3000}, {"source": "planner", "tokens_sent": 1500, "tokens_recv": 10}])
write("old_only", [R("landed", "good", "1", age=700, tokens_sent=5, tokens_recv=5)])
# legacy rows without severity: class/status inference
write("legacy", [
  {"class": "landed", "status": "", "tier": "1"},
  {"class": "reverted", "status": "", "tier": "1"},
  {"class": "noop", "status": "no-op(needs_decision)", "tier": "1"},
  {"class": "noop", "status": "no-op", "tier": "1"},
  {"class": "held", "status": "", "tier": "1"}])
# only task tokens, nothing failed -> no non-landed line
write("tok_nofail", [R("landed", "good", "1", tokens_sent=40, tokens_recv=60)])
write("tok_zero", [R("landed", "good", "1")])
PY
ts(){ local d="$1"; shift; OUT="$(HOME="$T/$d" python3 "$TS" "$@" 2>&1)"; RC=$?; }

# ---------- empty-data exits, all modes ----------
for m in "" "--headline" "--tokens-only" "--oneline"; do
  ts nodata $m; ok "no outcomes file, mode '${m:-default}': empty output, exit 0" "$([ "$RC" = 0 ] && [ -z "$OUT" ] && echo 1 || echo 0)"
done
ts empty_files; ok "empty files: empty output" "$([ -z "$OUT" ] && echo 1 || echo 0)"
ts old_only; ok "only rows older than the window: empty output" "$([ -z "$OUT" ] && echo 1 || echo 0)"
ts old_only 12; ok "hours arg widens the window (12h sees the 11.6h-old row)" "$([ -n "$OUT" ] && [ "$(has 'last 12h')" = 1 ] && echo 1 || echo 0)"
ts old_only --all-time; ok "--all-time ignores the cutoff" "$([ "$(has 'all-time')" = 1 ] && echo 1 || echo 0)"

# ---------- default tier table ----------
ts full
ok "default: header with window" "$(has '📊 By tier (last 3h):')"
ok "T1 per-attempt rate (2 landed of 5 good+bad attempts)" "$(has 'T1: 2/5 (40%)')"
ok "T1 per-item rate collapses retries by item_hash (2/4)" "$(has 'per-item: 2/4 (50%)')"
ok "T1 no-op breakdown names hidden reverts" "$(has '1 no-op (1 of which reverted code)')"
ok "T1 reverted / timeout / other / benign-excluded fragments" "$([ "$(has '1 reverted')" = 1 ] && [ "$(has '1 timeout')" = 1 ] && [ "$(has '1 other')" = 1 ] && [ "$(has '1 excluded (already-done/blocked, not counted)')" = 1 ] && echo 1 || echo 0)"
ok "T2 with only benign rows is summarised, not silently dropped" "$(has 'T2: 1 benign no-op(s) only (already-done/blocked), no good/bad attempts')"
ok "T3 benign-only inside window (10h-old landed row excluded)" "$(has 'T3: 1 benign no-op(s) only')"
ok "untagged + unknown tiers fold into 'Ongoing-lane'" "$(has 'Ongoing-lane: 2/2 (100%)')"
ok "Ongoing-lane rows have no item_hash -> no per-item fragment on that line" "$(printf '%s' "$OUT" | grep 'Ongoing-lane' | grep -q 'per-item' && echo 0 || echo 1)"
ok "fleet-wide pass-rate line" "$(has '✅ pass-rate this window: 57% (4 good / 7 good+bad)')"
ok "wasted-attempt line splits reverted/gate-reverted/flailed" "$(has '💥 3 wasted attempt(s) this window (1 reverted, 1 gate-reverted, 0 flailed/unverified)')"
ok "benign no-op exclusion line" "$(has 'ℹ️ 3 benign no-op(s) excluded from the rate')"
ok "timeouts total line" "$(has '⏱ 1 timeout(s) total this window')"
ok "real-revert total line (labeled + gate)" "$(has '↩️ 2 real revert(s) total this window (1 labeled reverted + 1 labeled no-op')"
ok "task tokens line (M/k/plain formatting)" "$(has '🔤 Tokens: 6.6k sent / 3.6k received')"
ok "non-landed token spend line" "$(has '💸 On non-landed attempts: 3.6k sent / 2.1k received (')"
ok "ledger section: overhead totals and call count" "$(has '🔧 Pipeline overhead (planning/grooming/recovery/review): 2.5k sent / 900 received (4 calls)')"
ok "ledger top sources ranked" "$(has 'planner 2.8k · groom 600')"
ok "Σ overall line" "$(has 'Σ Overall (tasks + overhead): 9.1k sent / 4.5k received')"
ok "out-of-window ledger row excluded" "$(printf '%s' "$OUT" | grep -q '999999\|1000.0k\|old ' && echo 0 || echo 1)"
ts full 1
ok "narrow 1h window still includes rows 10 minutes old" "$(has 'last 1h')"
ts full --all-time
ok "--all-time table includes the 10h-old T3 landed row and old ledger" "$([ "$(has 'all-time')" = 1 ] && [ "$(has 'T3: 1/1 (100%)')" = 1 ] && [ "$(has '1.0M')" = 1 ] && echo 1 || echo 0)"
ts landed_only
ok "no-failure tokens: no non-landed line; M/k formatting" "$([ "$(has '🔤 Tokens: 252k sent / 2.5M received')" = 1 ] && [ "$(has 'On non-landed')" = 0 ] && echo 1 || echo 0)"
ok "no bad rows: no wasted-attempt / revert lines" "$([ "$(has '💥')" = 0 ] && [ "$(has '↩️')" = 0 ] && [ "$(has '⏱')" = 0 ] && echo 1 || echo 0)"
ts benign_only
ok "benign-only window: benign line but no pass-rate line" "$([ "$(has 'ℹ️ 1 benign no-op(s) excluded')" = 1 ] && [ "$(has 'pass-rate this window')" = 0 ] && echo 1 || echo 0)"
ts skipped_only
ok "only skipped rows: nothing to report -> empty" "$([ -z "$OUT" ] && echo 1 || echo 0)"
ts ledger_only
ok "ledger-only window: overhead section without a tier table or task tokens" "$([ "$(has '🔧 Pipeline overhead')" = 1 ] && [ "$(has '📊 By tier')" = 0 ] && [ "$(has 'Σ Overall')" = 0 ] && [ "$(has '122k sent / 3.0k received (2 calls)')" = 1 ] && echo 1 || echo 0)"
ts legacy
ok "legacy rows w/o severity infer buckets from class+status (1 good of 3 good+bad)" "$(has 'T1: 1/3 (33%)')"

# ---------- --headline ----------
ts headline --headline
ok "headline: plain-language lead" "$(has 'Last 3h: 1 of ~4 real attempts landed (25%)')"
ok "headline: wasted breakdown (1 reverted, 1 gate-reverted, 1 flailed)" "$(has '3 wasted attempt(s) — work the fleet threw away: 1 reverted (code was rolled back), 1 gate-reverted (rolled back after failing the safety check), 1 flailed')"
ok "headline: benign skipped line" "$(has '1 skipped with no attempt made')"
ts headline --headline --all-time
ok "headline --all-time label" "$(has 'All-time: 1 of ~4')"
ts headline --headline 24
ok "headline hours label" "$(has 'Last 24h:')"
ts benign_only --headline
ok "headline with only benign: 'no real attempts yet' + skipped line" "$([ "$(has 'Last 3h: no real attempts yet')" = 1 ] && [ "$(has 'wasted')" = 0 ] && [ "$(has 'skipped with no attempt made')" = 1 ] && echo 1 || echo 0)"
ts landed_only --headline
ok "headline with only landed: no wasted/benign lines" "$([ "$(has '2 of ~2 real attempts landed (100%)')" = 1 ] && [ "$(has 'wasted')" = 0 ] && echo 1 || echo 0)"
ts skipped_only --headline
ok "headline with nothing countable -> empty" "$([ -z "$OUT" ] && echo 1 || echo 0)"
ts ledger_only --headline
ok "headline with ledger-only data -> empty" "$([ -z "$OUT" ] && echo 1 || echo 0)"

# ---------- --tokens-only ----------
ts full --tokens-only
ok "tokens-only: one-line summary with task count" "$(has '🔤 last 3h tokens: 6.6k sent / 3.6k received (10 tasks)')"
ok "tokens-only: non-landed spend + pct" "$(has '💸 of which on non-landed attempts: 3.6k sent / 2.1k received (')"
ok "tokens-only: pipeline overhead + sources + grand total" "$([ "$(has '🔧 pipeline overhead')" = 1 ] && [ "$(has 'planner 2.8k · groom 600')" = 1 ] && [ "$(has 'Σ overall (tasks + overhead): 9.1k sent / 4.5k received')" = 1 ] && echo 1 || echo 0)"
ts full --tokens-only --all-time
ok "tokens-only all-time label" "$(has '🔤 all-time tokens:')"
ts tok_nofail --tokens-only
ok "tokens-only with no failures and no ledger: just the one line" "$([ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
ts tok_zero --tokens-only
ok "tokens-only with zero tokens anywhere -> empty" "$([ -z "$OUT" ] && echo 1 || echo 0)"
ts ledger_only --tokens-only
ok "tokens-only with ledger but no task rows still reports overhead" "$([ "$(has '🔤 last 3h tokens: 0 sent / 0 received (0 tasks)')" = 1 ] && [ "$(has '🔧 pipeline overhead')" = 1 ] && echo 1 || echo 0)"

# ---------- --oneline ----------
ts full --oneline
ok "oneline: landed/no-op/reverted + failed count" "$(has '✅ 4 landed, 4 no-op, 1 reverted, 1 failed')"
ts landed_only --oneline
ok "oneline without failures omits the failed fragment" "$([ "$(has '✅ 2 landed, 0 no-op, 0 reverted')" = 1 ] && [ "$(has 'failed')" = 0 ] && echo 1 || echo 0)"
ts ledger_only --oneline
ok "oneline with no outcome rows -> empty" "$([ -z "$OUT" ] && echo 1 || echo 0)"

echo "ovn_tier_stats_run: $P passed, $F failed"
[ "$F" = 0 ]
