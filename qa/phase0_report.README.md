# phase0_report.py - Phase 0 exit and precondition report (read-only)

Plan: `docs/QA_PLAN_2026-10-01.md` section 7. The precondition says gate builds start only when the 48-72 h overnight pass
rate is at least 75 pct and no hygiene stall is over 2 h. The Phase 0 exit items that a file can answer are reported too.
This tool measures and prints. It never flips a mode, never writes, never locks, never calls git, ntfy or the network.

## Run

    python3 qa/phase0_report.py                       # state dir = $QA_STATE_DIR or $OVN_DIR/state (default ~/overnight-queue/state)
    python3 qa/phase0_report.py --state-dir /path/to/state --now 2026-10-15T12:00:00Z
    python3 qa/phase0_report.py --gold qa/gold_set.json

`--now` takes an epoch or an ISO-Z time and defaults to the current time. Output is one JSON line per criterion
(`group` = `precondition` or `phase0_exit`), then one `overall` line. Exit code is always 0.

## Criteria

| criterion | group | rule | cells |
|---|---|---|---|
| `pass_rate_48h`, `pass_rate_72h` | precondition | good / (good + bad) over outcomes in the window, benign excluded (`ovn_outcome_buckets.bucket_from_severity`); PASS at >= 75 | PASS FAIL UNVERIFIED (no non-benign rows, or file missing) |
| `hygiene_stall` | precondition | longest `state/qa_blocked/*.json` age (its `since` stamp); FAIL above 2 h; `blocked_repos` = count | PASS FAIL UNVERIFIED (dir missing, or a record with no readable `since`) |
| `ledger_coverage` | phase0_exit | span in days between the oldest and newest landed row in `state/qa_ledger.jsonl`; PASS at >= 7 days, else FLAG | PASS FLAG UNVERIFIED |
| `gold_open` | phase0_exit | gold rows whose `gate` starts with `pending:` or that carry `"pending": true`; FLAG while any remain | PASS FLAG UNVERIFIED |
| `escape_events` | phase0_exit | info only: strong escape events (revert, escape, emergency, test_watch_red) in the last 30 days | NA |
| `outcomes_malformed` | phase0_exit | only present when malformed outcomes lines were skipped | FLAG |
| `manual_items` | phase0_exit | the human items (manual-minutes log, tool smoke tests, Sentry origin, staging SHA, timings under load, suite runs) | NA |

`overall` is the worst cell of each group (FAIL > UNVERIFIED > FLAG > PASS; NA ignored). `precondition_met` is true only when the
precondition group is PASS.

## Rules

* A missing or unreadable input is UNVERIFIED, never PASS. An empty state dir gives UNVERIFIED on every machine cell.
* Malformed JSON lines are skipped and counted, never fatal.
* Read-only: files are opened for reading only. Nothing is created under the state dir (checked by the test suite with a tree checksum).

## Tests

    python3 scripts/test/test_qa_phase0_report.py     # 44 checks: benign and negative controls, empty state, malformed, read-only, entry point
    bash    scripts/test/test_qa_phase0_report.sh     # wrapper: Python suite + CLI under env -i (absolute and relative path)

`PHASE0_QA_DIR=<dir holding a copy of qa/>` runs the Python suite against another copy (used for mutation proofs).

## Limits

* The stall is measured from `state/qa_blocked/` only. Hygiene pass timings are not in a file this tool reads.
* The 48-72 h windows are measured from the report time, not from the box clock at any particular cron hour.
* The plan's 20-flag manual sample, the Mark manual-minutes log and the Sentry origin trace are not machine-readable and stay NA.
