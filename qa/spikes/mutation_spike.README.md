# qa/spikes/mutation_spike.py (key: spike-mutation)

Spike W2a. Measures whether **diff-scoped mutation testing** (mutmut 3.8.0) is usable per feature on the GPU box.
It is a measurement harness, not a gate to wire: advisory only, never returns `FAIL`. The measured verdict is in
`MUTATION_SPIKE.md` next to this file.

## What it does

`check --repo R --base B --head H`:

1. Lists non-test `.py` files changed in `B..H` and, with `git diff -U0` plus `ast`, the **changed functions** in them
   (top-level functions and methods of top-level classes; a pure deletion inside a function counts as a change).
2. Detached worktree of `H` (via `qa_common.worktree`, always removed). The clone's service `.venv` is symlinked in; repo-root
   files are symlinked into the service dir (tests that use `Path(__file__).parents[N]` see mutmut's extra `mutants/` level).
3. Writes a `[mutmut]` block into the worktree's `setup.cfg` (`source_paths=<pkg>`, `only_mutate=<changed files>`,
   `also_copy=<every top-level entry of the service dir>`), then runs
   `mutmut run --max-children 4 <globs of the changed functions' mutants>` niced, in its own **process group**, with a hard wall
   cap (default 600 s). On timeout the whole group is SIGTERM/SIGKILLed (no orphan workers; tested).
4. mutmut stops at the first red test of its clean run. The harness enumerates all red tests with one plain pytest pass in
   mutmut's layout, adds `--deselect=<test>` / `--ignore=<module>` for them (<= 40, reported in `details.deselected_tests`)
   and re-runs. Collection/conftest errors it cannot attribute -> `UNVERIFIED`.
5. Reads `mutants/**/*.meta`, counts killed / survived / no_tests / timeout, shows up to 10 survivors (diff + heuristic label).

Verdicts: `PASS` (all mutants killed), `FLAG` (survivors, or changed functions no test executes), `NA` (no changed function body),
`UNVERIFIED` (timeout, no venv/mutmut, red baseline, decorated-only change, mutmut error). Exit 0 always.

## Run

    # box (python3.12 or the default python3 both work; the gate is stdlib-only)
    OVN_DIR=/tmp/qa-x OVN_REPOS_DIR=~/overnight-queue/repos python3 qa/spikes/mutation_spike.py check \
        --repo shrike-monitor --base <sha>^ --head <sha> --no-record
    # flags: --cap 600  --max-children 4  --service <dir>  --python <path>  --survivors 10  --report <file.json>
    #        --keep <dir>  (persistent worktree = warm mutmut cache; remove with: ... cleanup --repo R --keep <dir>)
    #        --unwrap-decorators  (EXPERIMENTAL, see below)
    #        --select-tests       (run only test files that mention the changed module/functions: fast, but over-reports survivors)
    #        --paths a.py,dir/    (restrict a wide base..head range to these repo-relative files)
    #        --pytest-arg X       (repeatable, extra pytest arg; -n/--dist are refused: xdist hides mutmut's stats)
    # replay over history: python3 qa/qa_replay.py qa/spikes/mutation_spike.py <repo> --days 7 --limit 10

mutmut is taken from the service venv if it has it, else borrowed (appended LAST on `sys.path`, so the repo's own pytest and deps
win) from `$QA_VENV` (default `~/qa-venv`); the two Pythons must have the same minor version (3.12 on the box).

## Diagnosis of "mutmut --version prints a traceback"

Not a broken install. mutmut 3.x loads its config at import time and, with no `[mutmut]` config, guesses `source_paths` from the
current directory name; in `$HOME` that fails with `FileNotFoundError: Could not figure out where the code to mutate is`.
A fresh `pip install mutmut` on the Mac prints the same. It works inside a project. No fix needed in `~/qa-venv`
(mutmut 3.8.0, libcst 1.9.0 import fine). cosmic-ray 8.7.0 is downloadable (the box has PyPI access) but was not needed.

## Known limitations (all measured, see MUTATION_SPIKE.md)

- **mutmut 3.8 never mutates a decorated function** (only a single `@staticmethod`/`@classmethod`). Every FastAPI route handler
  (`@router.get/post/...`) is invisible to it; the harness reports `UNVERIFIED: all N changed function(s) are decorated`.
  `--unwrap-decorators` rewrites `@dec def f` into `def f` + `f = dec(f)` in the throwaway copy; it works for sync handlers in the
  fixture but is **experimental**, see the spike notes for what happened on real routers (async handlers break because the
  trampoline is a sync wrapper).
- Sibling `mutation_spike` measurements and the verdict: `MUTATION_SPIKE.md`. Headline: 4/4 router-only commits are UNVERIFIED by default;
  iptv_apps' full suite does not fit the 600 s cap.
- Whole-suite cost dominates: mutmut runs the full suite once under tracing ("stats") and again as "clean tests" before any mutant.
  Mutating itself (killed/survived per mutant) is seconds.
- The 4 mutants-per-line style noise (log message text, tuning constants) is not filtered; the heuristic label is a hint only.
- Only the service with the most changed files is measured per run; files at the service root (not in a package dir) are skipped.
- A second `[mutmut]` config already in the service's `setup.cfg` makes the harness `UNVERIFIED` rather than override it.
- Timing is wall time on a shared box (load average was 8-27 while measuring because other builders were running); `details.cpu_s`
  and `details.loadavg_1m` are recorded so contention can be judged.
- I added local helpers instead of changing `qa_common.py`: `run_group` (process-group kill; `qa_common.run` only kills the direct
  child, which would leave mutmut workers running) and the KeptWorktree helper for the warm-cache measurement.
