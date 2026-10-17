# qa_tool_health - gate tool health sentinel (P1, SHADOW)

**Problem it closes.** After the 2026-10-16 box home wipe, bandit/semgrep/gitleaks/pip-audit/mutmut/schemathesis, `state/staging_url_*`, `state/qa_creds`,
`state/qa_gate_modes.json` and the contract-fuzz baseline were gone. The gates handled that "correctly" (UNVERIFIED, never PASS) - but 16 of 20 scanner rows
saying UNVERIFIED is invisible on a dashboard. The sentinel converts "a gate cannot run" into one loud alert.

    python3 qa/qa_tool_health.py [--no-record] [--enforce-exit]

Read-only. It installs nothing, repairs nothing, and **never blocks a gate** (no gate reads its verdict). One JSON line on stdout, one row per run in
`state/qa_shadow/tool_health.jsonl`, exit 0 always.

## What it checks
| area | check |
|---|---|
| tools | `bandit semgrep gitleaks pip-audit mutmut schemathesis mypy ruff docker flock`: `ok` / `missing` / `broken` (script whose `#!` interpreter is gone - including `#!/usr/bin/env <missing>` - or whose own `<tool> --version` dies with an exec / ImportError / shared-library error; a timeout or a plain non-zero exit is NOT broken; `OVN_QA_TOOL_HEALTH_PROBE=0` disables the probe). Lookup = the gates' own order: env `QA_TOOL_<NAME>` > `~/qa-venv/bin` > `~/qa-tools/bin` > PATH > `<OVN_DIR>/qa-tools/.venv/bin` (last: the install venv only fills a gap, it never changes which tool an already-working gate uses) |
| state | `staging_url_<repo>` for each repo in `qa/staging_smoke.conf`; `qa_creds/<repo>.json` (JSON with email+password, **mode 600**: 644 is flagged; the file may be ABSENT when the conf declares a `repo_default` or the `email_env`/`password_env` pair is set, because staging_smoke resolves env > file > repo_default) for repos whose login has no `auto_register`; `qa_gate_modes.json` (a corrupt file is flagged; a missing one is NOT: every gate then runs in its default shadow mode); `qa_shadow/contract_fuzz_baseline_<repo>.json` |
| cron | each QA job script (ledger, manual notes, daily shadow, baseline refresh, block watch, staging e2e run/ingest, evidence freshness, **contract fuzz**, this sentinel) must be in a non-comment crontab line (`crontab -l`, or `OVN_QA_CRONTAB_FILE`). A crontab that cannot be read skips this check; it is never reported as "missing" |

## Verdict and flag
`OVN_QA_TOOL_HEALTH=off|shadow|enforce` (default **shadow**; env > `state/qa_gate_modes.json` > shadow).
PASS = nothing wrong; FLAG = at least one finding. `off` prints NA and records/alerts nothing. `enforce` turns FLAG into FAIL and, **only with `--enforce-exit`**,
exits 1. Nothing else changes: no gate, hook or cron consumes it.

## Alert (de-duplicated)
A finding must persist for **2+ consecutive passes** (`OVN_QA_TOOL_HEALTH_MIN_PASSES`) before it alerts. Everything that crossed the bar in one pass is ONE bounded line (finding keys, ~300 chars, pointer to the jsonl) in
`state/alerts.log` (`WARN | qa-tool-health | ...`). Because alerts.log is a file nobody reads, every run while a finding is past the bar ALSO writes a high-priority note to
`state/notify_notes.jsonl` (same mechanism as `qa_block_watch`), so the ONE hourly update from `scripts/ovn_notify.py` lists it (`OVN_QA_TOOL_HEALTH_NOTE=0` disables). The same finding is re-announced only after
`OVN_QA_TOOL_HEALTH_REALERT_H` hours (default 24, 0 = never); a finding that clears is forgotten so its next outage alerts at once. Counters: `state/tool_health_state.json`, written via a unique temp file + `os.replace` under an `flock` on `state/tool_health_state.lock` (overlapping cron/manual runs cannot clobber it or reset the de-dup memory).
`tool_health.jsonl` rows are compact (healthy tools: status + path) and the file is trimmed to the last `OVN_QA_TOOL_HEALTH_MAX_ROWS` rows (default 1500, 0 = never).
`--no-record` is a dry run: no row, no counter change, no alert. `OVN_QA_TOOL_HEALTH_SKIP="docker,flock"` ignores named tools.

## What it does NOT do: restore
The sentinel only DETECTS. Restoring is deliberately manual (the box is live; nothing here writes tools or state): tools -> `bash ops/qa_tools_install.sh`; `staging_url_*` ->
`provision_test_envs.sh` / the Railway staging URLs; `qa_creds/<repo>.json` -> only needed for repos with no `repo_default`/env (chmod 600); fuzz baseline ->
`python3 qa/contract_fuzz.py --accept-baseline`; a missing `qa_gate_modes.json` needs nothing.

## Installing the tools
`bash ops/qa_tools_install.sh [--check|--dry-run]` - idempotent; pip tools into the dedicated venv `<OVN_DIR>/qa-tools/.venv` (never a repo venv), gitleaks as a
sha256-verified release binary. The gates (`gate_scanners.find_tool`, `contract_fuzz.find_schemathesis`) look there LAST. The installer prefers python3.12, 3.13, 3.11, 3.10 before plain `python3` (the box default may be 3.14, which semgrep/mutmut/schemathesis wheels may not support); override with `QA_TOOLS_PYTHON=`.

## Cron (PROPOSED in `ops/cron.proposed.txt`, not applied)
`40 * * * *` sentinel, `20 4 * * *` contract fuzz.

## Promote to enforce
There is nothing to enforce on other gates. If you want a red exit code in a runbook: `OVN_QA_TOOL_HEALTH=enforce python3 qa/qa_tool_health.py --enforce-exit`.
Revert: unset the variable / `off`; the file is additive (delete `qa/qa_tool_health.py` and its cron line).
