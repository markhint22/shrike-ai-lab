# Claude-queue triage (2026-10-07)

Measures how many open `[CLAUDE]` lines in a repo's OVERNIGHT_PROGRESS.md are real work, and clears the ones that are not - with zero Claude capacity.

1. `claude_triage.sh <repo>` (run ON THE BOX, read-only): checks out `origin/overnight/feature` in a scratch worktree and runs every open `[CLAUDE]` line's own `VERIFY:` clause through the fleet's `shadow_check` (denylist, timeouts, venv/godot resolution). Writes `/tmp/ct_<repo>.tsv` = `line<TAB>PASS|FAIL|NO_VERIFY_CLAUSE|TIMEOUT|UNRUNNABLE<TAB>text`.
2. `ct_apply.py <repo> dry|apply` (run on the Mac, needs `scp` of the tsv): `PASS` lines are ticked `[x] (already-satisfied ...)`; `NO_VERIFY_CLAUSE` lines that are diagnostic notes ("recovered/decomposed N times", "hard-banned", model prose) are ticked `[x] (dismissed ...)`. Lines containing `bug-escalated` or `EMERGENCY` are never touched. Matches by exact text (the fleet edits the file constantly), commits only the ticks via a temp worktree and pushes non-force to `overnight/feature` with retry.

First run 2026-10-07: 165 open lines (iptv 105, xlite 60) -> 34 already satisfied + 35 non-actionable notes cleared -> 96 left (see memory handoff for the bucket split). `PASS` can be shallow (65% of VERIFY clauses are existence-only): treat it as "probably done", spot-check anything security-relevant.
