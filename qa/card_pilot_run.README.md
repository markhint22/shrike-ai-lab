# S0 card pilot (Phase 2, shadow) - `qa/card_pilot_run.py`, `qa/card_pilot_report.py`, `qa/card_pilot.json`

Wires the existing `acceptance_card.py` / `card_lint.py` (see `acceptance_card.README.md`) into a nightly, shadow-only pilot so the Phase 2 exit
numbers of `docs/QA_PLAN_2026-10-01.md` section 7 can be measured. Nothing it writes is read by any gate or by the runner: no behaviour change.

## Flags (both default `shadow`, neither has an enforce path)

| flag | values | what it does |
|---|---|---|
| `OVN_QA_CARD_PILOT` | `off` / `shadow` (`enforce` is accepted and behaves as shadow) | the nightly pilot. `off` = NA, zero model calls, nothing written. Also settable in `state/qa_gate_modes.json` as `card_pilot`. |
| `OVN_QA_CARD_CREDIT` | `off` / `shadow` | the S2 advisory in `lib_auto_credit.sh` (`ovn_card_credit_shadow`). Gate name `card_credit`. |

The pilot is OFF on the box until Mark uncomments the cron line in `ops/cron.proposed.txt` (nothing installs it).

## Nightly run: `python3 qa/card_pilot_run.py run [--config F] [--repo NAME] [--max-cards N] [--dry-run]`

1. mode check, loopback-only model URL (`LITELLM_BASE`, default `http://127.0.0.1:4000`; anything else is refused with zero calls).
2. **Idle check, read-only**: skips (UNVERIFIED, zero model calls) when a GPU-wait marker (`coder_window.hold`, the only marker name anything writes) exists, `run.lock` or `hygiene.lock` is held,
   an LLM-using child that outlives `run.lock` runs (`busy_process_patterns`, `pgrep -f`: planner, refill, work supply, explore, art runner), or the newest fresh `state/gpu_util.log` sample is >= 25 %.
   Locks are probed with `fuser`/`lsof`, never opened for locking; if neither tool exists the answer is "unknown" and it skips. Repeated between cards AND right before every model request.
   It never takes `run.lock`/`hygiene.lock`. A request already in flight cannot be recalled (one request can take minutes), so a fleet cycle that starts in that window overlaps it.
   Own serialisation: `run` holds a non-blocking flock on `state/card_pilot.lock` (an overlapping run is UNVERIFIED, zero calls); credit checks use 2 slots (`state/card_credit.lock.N`).
3. **Selection**: open `- [ ]` items read from each repo's progress file at the base ref (`git show`, the live tree is not read), minus HUMAN-tagged, minus
   items that already have a card row, filtered by the `qa/card_pilot.json` allow-list (TAA `backend/**.py`; iptv `iptv-backend/**.py` whose path or text matches
   entitlement/paywall/RevenueCat/subscription/premium/purchase/receipt/billing), then `card_lint.eligibility` (GDScript, Swift, Kotlin, Vue/TSX/CSS/HTML, non-code,
   audit items are excluded here, so they cost no model call). Round-robin over repos, up to `max_cards` (default 6).
4. **Cap**: `max_requests_per_night` (default 12) model requests per night (night = local date of now-12h), every attempt counted including failed ones and retries,
   enforced per request and recorded as a `kind: "call"` row BEFORE each request, so a killed run still counts. A cap hit stops the run; a later run the same night makes zero calls.
5. Per item: draft (Qwen, `acceptance_card.draft_card`, 1 retry on transport/parse failure), lint, run the `verify_cmd` at the base ref in a detached worktree
   (scrubbed env, no network, killed on timeout), append a `kind: "card"` row to `state/qa_shadow/card_pilot.jsonl`:
   `verdict, lint_ok, lint_errors, lint_flags, exec_outcome, fail_before, weak, risk_class, model_calls, gpu_s, wall_s, ms, card{bullets,verify_cmd,files}`.
   A card whose verify passes before the change is `weak` (verdict FLAG). Existence-only / status-swallowing / unsafe cards are lint-rejected (verdict FAIL).
6. A model failure (timeout, HTTP error, unparseable JSON, cap reached) is UNVERIFIED, never an error: the process always exits 0. Two consecutive model failures stop the run. An item that produced no card is retried after all fresh items and parked (not selected) after `max_attempts` (3) failed attempts;
   attempts cut short by the cap or a busy fleet do not count.
   UNVERIFIED rows without a card are retried on the next run.

## Report: `python3 qa/card_pilot_report.py [--state-dir D] [--input F ...] [--no-state] [--out DIR]`

Prints lint pass rate, fail-before rate (of cards and of lint-clean cards; `weak` count), GPU minutes per card (model timings; wall-clock fallback is labelled), class A
share, and writes `card_sample.md` (up to 20 class A cards, lint-clean first, one per item, empty decision boxes). **Mark decides; nothing is auto-approved** and the
report writes nothing else. It also reads the acceptance pilot's `qa/acceptance_pilot/*.jsonl`: on `taa_norepair_cards.jsonl` it reproduces lint pass 21/30 = 70%.
Plan bar: at least 80% of the 20 sampled class A cards sensible (16/20); GPU about 0.5 min averaged, 1.5-3 on class A.

## S2 advisory: `python3 qa/card_pilot_run.py credit --repo R --repo-path DIR --head SHA` (called by the hook)

After `ovn_auto_credit` ticks an item it launches this detached (niced, `timeout -k 30 180`, run.lock fd closed, rc 0 always; SIGTERM unwinds the worktree/temp-dir cleanup, stale `qa-wt-*`/`qa-acc-home-*` dirs older than 2 h are swept; inner timeouts 50+20+40 s + 45 s cleanup). It logs one row to `state/qa_shadow/card_credit.jsonl`:
`credit_without_card` (no stored card for the item), `card_existed`, `verify_passed_at_head` (the stored, lint-clean `verify_cmd` run at the credited sha; re-linted with the
current safety rules first). It cannot refuse or undo a credit.

## Promote to enforce

There is nothing to promote in this package: it is measurement only. The decision it feeds (plan section 7, Phase 2): Mark's 20-card sample at >= 80% sensible, lint pass
rate and GPU minutes per card from the report over at least a week of nightly runs. Only then is a credit-requires-card gate (S2 enforce) a separate, new package.
