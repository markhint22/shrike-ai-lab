# qa/gpu_ledger.py - Phase 5 GPU-seconds-per-stage ledger (SHADOW)

Plan reference: section 9 metrics, "GPU minutes per landed feature by stage". It only READS existing logs (no model calls, no GPU access, no subprocess or network import: a test asserts that).

## Sources and what is measured vs estimated
| stage | source | seconds |
|---|---|---|
| dev | `state/outcomes.jsonl` | `duration_s` of every attempt (wall time of the aider / stage attempt, tests included) - a PROXY |
| dev / research | `state/token_ledger.jsonl` | `tokens_sent / prefill + tokens_recv / decode` - ESTIMATE. decode = median `tok_s_best` of `state/toks.jsonl` (else 45), prefill = `OVN_GPU_PREFILL_TOKS` (default 1500). Source name picks the stage (research/explore/scout -> research; card; review; mutat; spec; everything else dev) |
| research | `state/qwen_explore.jsonl` | `secs` (measured wall seconds) |
| reviewer | `state/qa_shadow/reviewer.jsonl` | `details.usage.gpu_s` (MEASURED, llama.cpp timings); rows without a model call count 0 |
| card | `state/qa_shadow/acceptance.jsonl` | `details.meta.gpu_s` / `details.usage.gpu_s` / `details.gpu_s` (no such log exists today: 0 rows) |
| spec_gate | `state/spec_gate.jsonl` | row `gpu_s` when present; its `exec.ms` is CPU test time and is reported separately (`spec_gate_cpu_s`) |
| mutation | `state/qa_shadow/mutation.jsonl` | `details.gpu_s` (none today: the Godot mutation scan is CPU) |

Every run prints a `sources` block (rows and seconds per source, `present` flag) so a stage with no log shows as 0 rows, not as a silent zero. Outcome-wall-time and token estimates do not overlap
(outcome rows are aider attempts; the token ledger holds planner / decompose / research calls).

## Attribution
Per landed feature (same grouping as wip_cap.py): outcomes join by `item_hash` or `feat_tag` (ALL attempts of the item, including failed ones, are the cost of landing it); spec_gate rows by `feat`; reviewer / card /
mutation rows by the head commit of `ref` (`A..B` or `B`). Everything else (planner, research, items that never landed) is UNATTRIBUTED and stays in the weekly table, because the plan's metric is total GPU
minutes divided by landed features.

## Outputs (state/qa_shadow/)
* `gpu_ledger.jsonl` - rows merged BY KEY (a recomputed key replaces its older row, other keys are kept, atomic rewrite): `{kind:"feature", stages:{...}, total_s}` and `{kind:"week", week, repo, stage, seconds, landed}`.
* `gpu_ledger_weekly.md` - the weekly table: ISO week x stage (total minutes) with `min / landed`.
`python3 qa/gpu_ledger.py reconcile` re-sums every source straight from the files and compares to the ledger: `ok` when every source and the total agree within 1%.
Acceptance on a scratch copy of the box state (2026-10-17): outcomes 35097 s, token ledger 2905.9 s, qwen_explore 4393 s, reviewer 31.44 s; ledger total 42427.3 s vs raw 42427.3 s (0.000% error).

## Flag `OVN_QA_GPU_LEDGER=off|shadow` (default shadow; any other value, `enforce` included, behaves as shadow - nothing here enforces)
Cron: `qa/phase5_cron.sh` (hourly, runs wip_cap then this). `python3 qa/gpu_ledger.py run [--no-record] [--days 14]`, `report`, `reconcile`.

## How to use it for the plan's verdict rule
A gate is kept only if its catches per GPU-minute justify it: join `gpu_ledger.jsonl` stage seconds with the scorecard's catches per gate at the monthly review. Treat the dev and token numbers as relative, the
reviewer / card numbers as absolute. Replacing the token estimate with measured timings means the token ledger writing `prompt_ms` / `predicted_ms` (a one-line change in ovn_log_tokens.sh, not part of this package).
Tests: `scripts/test/test_qa_gpu_ledger.py` (hand-computable fixtures, hostile rows, 1% reconcile against an independent sum, merge idempotency, mutants).

## Review fixes (2026-10-17)
* Window aligned to the Monday of the oldest week; a week row is never rewritten smaller (the hourly cron used to shrink the oldest week).
* Not summed: token_ledger `qwen-explore` rows (the measured qwen_explore.jsonl row is the same pass), `supervisor-review` (remote), and any token_ledger source mapping to a stage with its own measured log. outcomes `duration_s` and the planner / stage-decompose / recover_parked / groom token estimates cannot be deduped (no shared id) and both stay in `dev`: the dev number is an upper bound.
* `reconcile` re-sums with the same exclusions, so it checks window/bucketing arithmetic, not overlap; overlap is covered by the fixed exclusions and their tests.
