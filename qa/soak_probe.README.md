# soak_probe + deploy_drill (QA Phase 4, SHADOW)

Closes the gap "staging passed one smoke right after the deploy, then degraded". Three parts, all additive and revertible:

| piece | what | mode |
|---|---|---|
| `qa/soak_probe.py probe` | (cron passes `--candidate auto` = develop head of the repo clone, `OVN_SOAK_CANDIDATE_REF`, `off` = none, so a healthy-but-STALE staging is a provenance FAIL in production, not only in the drill) one synthetic journey against STAGING: health (+ provenance against `--candidate`), canonical login, ONE business endpoint, ONE write + read-back + cleanup tagged `soak-<hhmmss>-<hex>`, CORS preflight from the real frontend origin. Reuses `staging_smoke.py` (cells, `is_staging` allow-list, `qa_creds`). Row to `state/qa_shadow/soak.jsonl` | shadow (cron every 15 min: `qa/soak_probe_cron.sh`) |
| `qa/soak_probe.py summary` | per-candidate-SHA summary: clean hours, new error signatures, verdict, decision | pure read |
| `promote_gate.py` soak read | adds `soak_*` fields and one `[staging-soak]` log line to the promote evidence | `OVN_QA_SOAK=off\|shadow\|enforce`, default **shadow** |
| `qa/soak_probe.py readiness` | from the REAL rows: how many served builds reached the soak minimum before staging moved on (the enforce-readiness number) | pure read |
| `qa/deploy_drill.py run` | injects 4 broken-staging classes, 2 outage classes (staging unreachable / probe dead after a clean streak) and extras into a loopback stub and proves the gate chain would hold the promote | fixtures only |

## Verdict rules
Sample: PASS | FLAG (N/A by design, e.g. gitlark has no password login; or SLOW: a request over `OVN_SOAK_SLOW_MS`, default 8000) | FAIL (a step failed: 5xx, non-JSON, write not visible, CORS broken, stale build) | UNVERIFIED (no URL / no creds / no HTTP response; the refusal of a non-staging URL is UNVERIFIED and is not recorded).
Summary for a candidate SHA: only samples served by the candidate or a descendant (git ancestor test), or asked to verify it, count. A FAIL or slow sample breaks the clean streak; UNVERIFIED samples carry no signal and a hole longer than 3 intervals breaks the streak.
**Recency**: a PASS also needs the newest clean sample younger than 3 intervals. Probe rows of an unreachable staging have no served sha, so they are not attributable to any build; the summary therefore counts UNVERIFIED rows of the repo after the streak (`trailing_unverified`) and checks the age of the newest clean sample (`stale`). A clean streak followed by an outage, a dead cron or a 5-day gap is `FLAG`/`HOLD` ("no current coverage = no soak"), never PASS.
**Deploy lag**: a bad row of a build that is not the candidate (staging still deploying it; only attributable through `row.candidate`) breaks the streak but is not a FAIL once staging serves the candidate again, so a deploy lag costs a restarted streak, not 2 h of FAIL.
`UNVERIFIED` (no attributable sample, or only UNVERIFIED ones) is **never reported as PASS** and never holds. `FLAG` = clean but still soaking (< minimum), `FAIL` = bad sample or a NEW error signature in the window, `PASS` = clean streak >= minimum.
`decision`: HOLD for FAIL and FLAG, OK for PASS, UNVERIFIED for UNVERIFIED.

## promote_gate integration (shadow)
`promote_to_prod.sh` already prints promote_gate's log lines. With soak rows present it adds, e.g.
`[staging-soak] mode=shadow soak=FLAG clean=0.75h/2.0h samples=4 new_sigs=0 -> soak would HOLD (shadow) (...)`.
No soak.jsonl rows for the repo => no line (output byte-identical to before). `OVN_QA_SOAK=off` => no read at all.
**Enforce** (`OVN_QA_SOAK=enforce`, or `qa/qa_enforce.sh soak enforce`) only turns the logged "would HOLD" into a real HOLD (`block`, reason `SOAK_HOLD`) for repos in the explicit allow-list: `OVN_QA_SOAK_ENFORCE_REPOS=iptv_apps` or lines in `state/qa_soak_enforce_repos`. Default allow-list: EMPTY, so enforce with no allow-list still only logs ("enforce, repo not in the allow-list").
UNVERIFIED never holds, an internal error never holds.

## The soak minimum (decided from drill output)
`python3 qa/deploy_drill.py run` replays 12 samples (15 min apart) per class through the real summary + `promote_gate.decide_soak_block("enforce", ...)` and reports detection times. Output of the run that fixed the default (2026-10-17, fixtures):
- stale_sha, health_500, cors_failure, readback_failure: detected at sample 0 (0.0 h), held for the whole replay. Control (clean) is let through at sample 8 (2.0 h of clean samples), so the gate does not hold forever.
- late_onset (clean for 5 samples, then 500s on the business endpoint, i.e. a failure that appears 1.25 h after the deploy): detected after 1.25 h. `recommended_min_hours` = slowest detection + one interval, rounded up to 15 min = **1.5 h**.
- With `--min-hours 1.0` the drill reports FLAG: the promote would have passed at sample 4, before the late failure appeared. With the default 2.0 it is held.
- Postcheck fixtures: a FAILED prod deploy of the promoted SHA -> `promote_postcheck.evaluate` = FAILED (EMERGENCY path); the promoted SHA never appearing -> never SUCCESS; healthy -> SUCCESS.
Default `OVN_QA_SOAK_MIN_HOURS` = **2.0**: the drill's lower bound (1.5 h) plus margin for one missed cron sample and a cold start. It is a judgment on fixtures, not a measured property of the real staging: revisit after the first week of real soak.jsonl (`summary` over the last promoted candidates; look at how long after a deploy real failures first appeared).

## Drill: what "would hold" means, and its limits
The drill proves the **gate chain's logic** on fixtures: probe -> summary -> `decide_soak_block` (+ `staging_check.decide` -> `decide_block` for the stale class; `promote_postcheck.evaluate` for the prod-deploy fixtures). It never touches real staging or prod (loopback stub only, private state dir, random password scrubbed from the report).
`--mutant cors` / `--mutant write_read` remove that check from the probe and the drill must then report `would not hold: cors_failure` (verdict FAIL): the proof that the drill is not vacuous.
It does NOT prove the real staging URLs and credentials work (that is what UNVERIFIED rows from the real probe say), nor that `OVN_QA_SOAK=enforce` is armed (it is not: default shadow, empty allow-list).

## How to promote to enforce (when the data supports it)
1. Provision `state/staging_url_<repo>` and `state/qa_creds/<repo>.json` (wiped on 2026-10-16), install the cron (`phase4_cron.proposed.txt`), wait >= 7 days of rows.
2. Run `python3 qa/soak_probe.py readiness --repo R` and check `summary` for the last 5 candidates per repo: no false HOLD (a healthy candidate reaches PASS within about min hours of its deploy) and no missed incident. `readiness` says how many served builds were replaced before reaching the minimum; develop receives hygiene merges hourly and each merge redeploys staging, so a low `pass_share` (verdict FLAG, "do NOT enforce yet") means enforcing would starve promotes. This is NOT measured yet: do not enforce a repo before the number exists and is acceptable.
3. `OVN_QA_SOAK_ENFORCE_REPOS=<one repo>` + `qa/qa_enforce.sh soak enforce` (or `OVN_QA_SOAK=enforce` in the promote cron env). One repo first. Rollback: `qa/qa_enforce.sh soak shadow` or empty the allow-list, no deploy needed.

## Shared QA account (billwatch)
The billwatch write step PATCHes `display_name` on the canonical staging account, a field `staging_smoke` / `staging_e2e` also write with their own marker. Two changes: the config now restores the name (`cleanup` PATCH `display_name: "QA Smoke"`, `staging_smoke` sends a cleanup `body`), and the soak probe retries a lost read-back ONCE with a fresh marker (`details.write_read_retry`), so an overlapping writer does not record a FAIL while a real read-back failure (fails twice) stays one. Not reproduced live: this is from reading the config; check `write_read_retry` counts in the first week of rows.
