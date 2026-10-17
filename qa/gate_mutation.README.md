# Gate S7 - per-range mutation advisory (`qa/gate_mutation.py`, registry key `mutation`) and S8 label-bar tracker (`qa/qa_gate_precision.py`)

Promotes `qa/spikes/mutation_spike.py` (mutmut 3.8, changed functions only; verdict in `qa/spikes/MUTATION_SPIKE.md`) into a registered
**advisory** gate. It answers one question per merged feature range: *of the function bodies this range changed, how many mutants did the
tests fail to kill?* It never blocks, alerts or credits anything.

## It is NOT a per-merge gate

The file is named `gate_mutation.py` because the mode key is `mutation`, but a mutation run costs minutes of CPU (mutmut runs the whole suite
twice before the first mutant). `qa_run_shadow.sh` therefore skips it (`case "$name" in mutation) continue`) and `qa_enforce_run.py` never lists
it (`DAILY_ONLY`). It runs from **`qa_daily_shadow.sh`** (last block, after every other gate) or on its own cron:

    # full daily run (as today, now ends with the mutation pass):        50 8 * * *  $HOME/overnight-queue/qa/qa_daily_shadow.sh
    # or a separate pass (mutation only), e.g. early afternoon:          30 13 * * * $HOME/overnight-queue/qa/qa_daily_shadow.sh --mutation-only
    # (not installed: add to the crontab after the first reviewed run; `--staging-only`, the hourly pass, never runs it)

`gate_mutation.py daily` resolves the range per repo (`origin/develop`; base = the head it measured last time if that is an ancestor, else the last
commit older than 24 h), so a commit is measured once, as part of the range it landed in. Repos: `QA_DAILY_MUT_REPOS`
(default `billwatch gitlark iptv_apps test-automation-agent`; xlite is GDScript, the website has no Python).

## Guards (the pass is skipped, logged `mutation: SKIPPED ...`; no gate row, but every skip is appended to `state/qa_gate_skips.jsonl`)

`qa_gate_precision.py verdict-rule` has a `skipped` column fed from that file, and lists a gate that ONLY skipped as `no runs (N skipped)`, so a gate that never
runs is visible in the monthly review. `python3 qa/gate_mutation.py status` prints one JSON line: mutmut installed?, run.lock policy, busy reason, last measured
head per repo, recent skips.

| guard | default | note |
|---|---|---|
| mode | `OVN_QA_MUTATION=shadow` | `off` -> skipped / NA. `enforce` is a **documented no-op** (rows carry `details.enforce_note`): there is no enforcement path |
| load | 1-min load average > `OVN_MUT_LOAD_MAX` (6) | re-checked before every repo |
| run.lock | **ignored by default** (`OVN_MUT_RUN_LOCK=ignore`). `skip` = skip while any process holds it (observed read-only with `fuser`/`lsof`; the gate never takes the lock) | `run_overnight` holds `run.lock` for its whole life (box 2026-10-17: 10 pids on it), so the old default `skip` meant the daily pass NEVER ran. The pass is niced, capped, `--max-children <= 4`, runs in a throwaway worktree and only READS the service venv (`PYTHONDONTWRITEBYTECODE=1`); the load guard is the throttle |
| tooling | mutmut present in the QA venv (see Tooling) | otherwise the pass is skipped up front (recorded in `qa_gate_skips.jsonl`) instead of producing a day of UNVERIFIED rows |
| budget | `OVN_MUT_DAILY_BUDGET_S` (1800) | a repo is STARTED only if the remaining budget >= its wall cap + `OVN_MUT_MARGIN_S` (200: range fetch, worktree, teardown), so the pass ends inside the budget. The wrapper's hard wall is budget + 180 s with a SIGTERM grace (`OVN_MUT_TERM_GRACE_S`, 30 s): on SIGTERM the gate kills the in-flight mutmut process group (own session, so qa_timeout cannot reach it), removes the worktree and writes an UNVERIFIED row. Worktrees leaked by a SIGKILL are swept (`qc.sweep_stale_scratch`, > 2 h old) at the start of each repo |

## Limits (hard, whatever the caller passes)

wall cap **<= 600 s for the whole check, survivor diffs included** (`OVN_MUT_CAP_S` can only lower it; mutmut gets the cap minus a 10 % / 45 s reserve, each `mutmut show` is bounded by what is left, a survivor listed without its diff says so; whole process group SIGTERM/SIGKILL on expiry, no orphan workers), `nice -n 15` + `ionice -c3`,
`--max-children <= 4`, **<= 10 named survivors**. `iptv_apps` (full suite over the cap) always runs with **test selection by touched module**
(`OVN_MUT_SELECT_REPOS`, default `iptv_apps`): if no test file mentions the changed modules/functions it is `UNVERIFIED` immediately with the reason
(no doomed 600 s run), and a cap hit says "over the 600s cap even with test selection". With selection, survivors can be over-reported.

## Decorated handlers

mutmut 3.8 never mutates a decorated function (every FastAPI route handler). They are listed in `details.skipped_decorated`; a range that changes only
decorated functions is `UNVERIFIED` with that reason. The experimental `--unwrap-decorators` (rewrite `@dec def f` as `def f` + `f = dec(f)` in the throwaway
copy) runs **only with `OVN_MUT_UNWRAP=1`**; the flag on the command line alone is ignored.

## Row (one per range, `state/qa_shadow/mutation.jsonl`)

`verdict` is `PASS` (every mutant of the changed functions killed) | `FLAG` (survivors or changed functions no test executes) | `UNVERIFIED` (cap, no tool/venv,
red baseline, only decorated, selection found nothing) | `NA` (no changed function body). **Never `FAIL`**, exit 0 always.
`details`: `range{base,head,source,measured[,partial]}` (see Baseline), `yield{survivors, killed, mutants, runtime_s, cpu_s}`, `survivors_shown[<=10]` (diff + noise label, secrets redacted),
`untested_functions`, `skipped_decorated`, `limits`, `tests_selected`, `deselected_tests` (preexisting red tests excluded, <= 40), `counts`.

    python3 qa/gate_mutation.py check --repo R --base B --head H [--paths a.py,dir/] [--service DIR] [--no-record]
    python3 qa/gate_mutation.py daily [--repos "r1 r2"] [--hours 24] [--no-record]
    python3 qa/gate_mutation.py busy          # prints why a daily pass would be skipped ("" = free)
    python3 qa/gate_mutation.py status        # readiness: tooling, guards, last measured heads, recent skips

## Baseline (what counts as "already measured")

A range advances the next daily base only when the row is `source=daily` (not a manual `check`), `measured=true` (verdict `PASS|FLAG|NA` and not restricted with
`--paths`). `UNVERIFIED` (tool missing, wall cap, undecided mutants, red clean run, SIGTERM, decorated-only) is recorded for visibility but its commits are covered
again by the next pass, so installing mutmut later backfills them. A measured base more than `OVN_MUT_MAX_RANGE_COMMITS` (300) behind, or one that is not an ancestor of
the current head, falls back to the 24 h window.
Tooling: mutmut + pytest, found in this order: `$QA_VENV` (explicit, the only candidate when set), `~/qa-venv`, `<OVN_DIR>/qa-tools/.venv` (what
`bash ops/qa_tools_install.sh` builds: it installs `mutmut>=3,<4` with the other QA tools). **After the 2026-10-16 rebuild the box has no mutmut**; deploy step for the lead:
`bash ~/overnight-queue/ops/qa_tools_install.sh` (idempotent; `--check` lists what is missing), then `python3 qa/gate_mutation.py status` must say `mutmut_installed: true`.
The venv's Python minor must equal the service venv's (mutmut is borrowed into it); the installer prefers python3.12. Until then the daily pass is skipped and recorded as a skip.
`OVN_REQUIRE_QA_VENV=1` makes the real-mutmut tests FAIL instead of SKIP when no venv is found: set it wherever a green suite gates a deploy (including `run_all_sandboxed.sh` on the box).

## qa_gate_precision.py (S8 bar + monthly verdict rule)

    python3 qa/qa_gate_precision.py [precision] [--json]
    python3 qa/qa_gate_precision.py verdict-rule [--month YYYY-MM] [--json]

`precision` reuses `qa_reviewer_label.py`'s label logic: labelled count, TP/FP/unclear, precision (shown only from 50 decisive labels), and whether the bar
**>= 50 labelled AND >= 60 % precision** is met. With 0 labels it prints `bar ... NOT MET (insufficient sample: 0 of 50 decisive labels)`.
`verdict-rule` is the monthly table: per gate, runs, catches (FLAG|FAIL rows), UNVERIFIED rows, minutes (GPU for `OVN_QA_GPU_GATES`, default `reviewer`; CPU
for the rest, using `details.cpu_s` when a row has it) and catches per minute, with a *suggested* rule (`insufficient data` < 20 scored runs, `retire?` >= 10
minutes and 0 catches, `weak` = at least one catch but below 0.05 catches/min (an always-green gate with little time spent is `keep`), else `keep`; gates in
`OVN_QA_ADVISORY_GATES`, default `mutation`, show `advisory` instead: their FLAG is a survivor to read, not a catch). Thresholds: `QA_RULE_MIN_RUNS`, `QA_RULE_MIN_MINUTES`, `QA_RULE_MIN_RATE`. Read-only.

## Tests

`scripts/test/test_qa_gate_mutation.sh` (+ `.py`) and `test_qa_gate_precision.sh` (+ `.py`), registered in `run_all.sh`. They include failure-injection
mutants (M1 changed-function scoping, M2 cap clamp, M3 FAIL mapping, M4 unwrap switch, M5 iptv selection, M6 load guard, M7 per-merge exclusion; M9-M20: budget guard,
fuser exit status, is-ancestor check, survivor cap, --no-record, repo-name filter, mid-loop load re-check, load parsing, run.lock default, baseline source / measured /
MEASURED set; precision M5-M9: retire boundary, 0-catch-is-weak, advisory, skip-only gates, skip month filter). Without mutmut the 8 real-mutmut tests print SKIP.
