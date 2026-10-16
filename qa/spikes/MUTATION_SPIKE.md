# Spike W2a - diff-scoped mutation testing on the GPU box (mutmut 3.8.0)

Measured 2026-10-01 on the box (16 cores) against real landed commits of the six Python repos. Harness: `qa/spikes/mutation_spike.py`
(CLI `check --repo --base --head`, advisory, UNVERIFIED on timeout, tests in `scripts/test/test_qa_spike_mutation.py`, 36 checks green on
Mac and on the box). Raw per-run JSON lines are what the numbers below were copied from; they were not committed (scratch only).

## Verdict

**Usable on this box for pure-Python service/util functions, as an advisory report per feature range (not per commit), with a 600 s cap.
Not usable out of the box for FastAPI route handlers. iptv_apps needs test selection to fit the cap. Do not wire it as a gate.**

- It works and it finds real untested behaviour. Of 87 surviving mutants I read, 48 (55%) looked like real or probably-real test gaps and
  39 (45%) were noise (log/detail text, dead code, default constants, a time boundary). Of 3 survivors I tried to kill by writing a test,
  3 were killed, so those gaps were real. **I did not measure a bug-catch rate and found no production bug; the output is test gaps.**
- Cost is dominated by running the whole suite twice (mutmut's "stats" pass under tracing, then its "clean tests" pass), not by mutants.
  Mutants themselves ran at 0.06-0.4 s each. Cold wall time therefore tracks the service's full serial suite: 26-80 s
  (shrike-monitor, shrike-notify, test-automation-agent), 190-340 s (gitlark, billwatch range), 602 s (billwatch single run, at the cap),
  and **over the cap** for iptv_apps (the stats pass alone ran 552-576 s of 600 s, on both commits tried).
- **mutmut 3.8 never mutates a decorated function** (checked in its source: only a single `@staticmethod`/`@classmethod` is allowed). Every
  FastAPI handler (`@router.get/post/...`) is invisible: all 4 router-only commits I tried gave UNVERIFIED (`all N changed function(s) are
  decorated`), and in a fifth (sn1) two routers were skipped and listed in `skipped_decorated` while the rest was measured. The plan's worry ("mutmut with FastAPI dependency injection is unproven") is worse than DI: it is the decorators.
  `--unwrap-decorators` (rewrite `@dec def f` as `def f` + `f = dec(f)` in the throwaway copy) worked on the 2 async routers I could
  run (shrike-monitor PATCH handler: 66 mutants; gitlark refresh endpoint: 43 mutants) and is still **experimental**.
- Per-commit is the wrong granularity for this fleet. In shrike-monitor's last 6 days (`qa_replay`, 14 commits) 12 were NA and the 2 FLAGs
  were single staged steps. Tests land in separate commits: billwatch `is_bill_dead` is "no test executes it" at its own commit
  (17 mutants unreachable) and 94% killed (16/17) over the 3-commit feature range that includes the tests.

## Recommended limits (if S7 proceeds)

| Setting | Value | Why |
|---|---|---|
| Unit | feature range (all commits of one item/promote batch), changed functions only | tests arrive in later commits |
| Wall cap | 600 s, whole process group killed, UNVERIFIED on hit | measured: 2 of 12 full-suite runs hit it (bw1 finished at 602 s after retries) |
| Workers | `--max-children 4`, `nice -n 15`, `ionice -c3` | box load average was 8-56 from other builders while I measured |
| Services | run un-selected only when the full serial suite is under about 3 min; otherwise `--select-tests` (iptv_apps, billwatch) | cold cost is about 2x the suite |
| Survivors shown | at most 10, grouped by function, `detail=`/log-text survivors labelled noise | 411 mutants gave 280 survivors in one function |
| Output | advisory report only; never FAIL; no auto-generated kill tests until yield is shown | 45% noise in what I read |
| Nightly | one full "stats" refresh per repo into a kept worktree/cache | warm reuse cut 224 s to 65 s (below) |

## What was measured

Wall time is on a shared box, so `cpu_s` (CPU seconds of the reaped process tree) and `loadavg_1m` are in every JSON line. Early
runs (mon1, mon2, bw1, taa1, sn1 cold) ran at load 18-55, so their wall times are inflated; treat cpu_s as the stable figure.

| id | repo @ commit | changed function(s) | mode | verdict | mutants | killed / survived | cold wall (cpu) | warm re-run |
|---|---|---|---|---|---|---|---|---|
| mon1 | shrike-monitor f41c53b | `MonitorScheduler.run_forever` | full suite | FLAG | 6 | 2 / 4 | 26 s | 17 s |
| mon2 | shrike-monitor 29c4e4b | `MonitorPersistence.update_monitor` | full | PASS | 12 | 12 / 0 | 37 s | 21 s |
| r2 | shrike-monitor range 5968277^..398723e | 4 functions in `scheduler.py` | full | FLAG | 246 | 209 / 37 | 71 s (53 s) | - |
| sn1 | shrike-notify 5a28a0e | `require_wildcard_or_bootstrap`, `Broker.history` (2 routers skipped: decorated) | full | FLAG | 78 | 55 / 23 | 68 s (36 s) | 80 s, 54 / 24 (see flakiness) |
| taa1 | test-automation-agent 6eccfbfc | `calculate_trend_ratio` | full (3 tests deselected) | PASS | 10 | 10 / 0 | 228 s (72 s) at load 55; 191 s on rerun | 50 s |
| taa2 | test-automation-agent 451bd973 | `render_html_report` (new, 82 lines) | full | FLAG | 98 unreachable | no test executes it | 80 s (47 s) | - |
| bw1 | billwatch a24ba93b | `should_update_status` | full (2 deselected) | FLAG | 15 | 9 / 6 | 602 s (372 s) | 234 s |
| bw2 | billwatch 5ee555ff | `is_bill_dead` (impl only) | full | FLAG | 17 unreachable | no test executes it | 194 s (184 s) | - |
| r1 | billwatch range 5ee555ff^..6b6d35c8 | `is_bill_dead` + its tests | full | FLAG | 17 | 16 / 1 | 338 s (341 s) | - |
| gl1 | gitlark 22a5ad76 | `redact_secrets` | full (11 deselected) | FLAG | 30 | 22 / 8 | 316 s (167 s) | - |
| mon3 | shrike-monitor 61d20a6 | `update_monitor` (PATCH route) | default | UNVERIFIED: decorated | 0 | - | 14 s | - |
| mon3u | same | same | `--unwrap-decorators` | FLAG | 66 | 28 / 38 | 31 s (16 s) | - |
| gl3 | gitlark f0450963 | `refresh_token_endpoint` (route) | default | UNVERIFIED: decorated | 0 | - | <1 s | - |
| gl3u | same | same | `--unwrap-decorators` | FLAG | 43 | 20 / 23 | 420 s (243 s) | - |
| ip1 | iptv_apps 5f51ee49 | `classify_event` (RevenueCat) | full | UNVERIFIED: hit 600 s cap | 28 not checked | stats pass alone ran 552-576 s | 600 s | - |
| ip1s | same | same | `--select-tests` (6 files) | FLAG | 28 | 27 / 1 | 89 s (91 s) | 46 s |
| ip3 | iptv_apps 5d453c8c | account deletion (3 functions) | full | UNVERIFIED: hit cap | 411 not checked | - | 600 s (548 s) | - |
| ip3s | same | same | `--select-tests` (1 file) | FLAG | 411 | 131 / 280 | 197 s (575 s) | - |
| bw3 | billwatch 497afc6f | `delete_device_token` (route) | default / unwrap | UNVERIFIED | - | - | 0-5 s | - |
| gl2 | gitlark 56e076dd | `DispatcherService.dispatch` | default | UNVERIFIED | - | - | 11 s | - |
| ip2 | iptv_apps a6f481e3 | `/import/m3u`, `/import/xtream` (routes, premium gate) | default | UNVERIFIED: decorated | 0 | - | <1 s | - |

bw3 and gl2: the commit's own HEAD does not import (`bw3`: `cannot import name 'DeviceTokenDelete' from app.schemas.auth`; `gl2`: conftest
import error), so pytest cannot start; the harness reports the pytest error text instead of a verdict. That is a real finding about those
commits (the staged step left HEAD broken), not a mutmut problem.

### Warm cache

- Identical re-run in a kept worktree skips only the stats pass: mon1 26 to 17 s, mon2 37 to 21 s, taa1 228 to 50 s, bw1 602 to 234 s,
  ip1s 89 to 46 s, sn1 68 to 80 s (no gain). The "clean tests" pass still runs the covering tests every time.
- **Incremental** (the realistic case): test-automation-agent 6eccfbfc then 6d1c9e9a in the same kept worktree took 65 s (stats 1 s),
  versus 224 s for 6d1c9e9a from scratch (stats 47 s, plus 3 extra rounds re-discovering 3 red tests). Same result both ways (85 killed / 33
  survived of 118). I measured this on one repo only.

### Test selection (`--select-tests`) trades fidelity for time

| case | full suite | selected | 
|---|---|---|
| taa1 | 10/0 in 228 s | 10/0 in 8 s |
| mon3u | 28/38 | 28/38 (identical) |
| bw1 | 9 killed / 6 survived, 602 s | 7 / 8, 36 s (2 kills lost) |
| sn1 | 55 killed / 23 survived | 33 / 45 (**22 of 55 kills lost**) |
| ip1 / ip3 | cap hit | 27/1 in 89 s; 131/280 in 197 s (no full run exists to compare) |

Selection (test files that mention the changed module or function) misses tests that reach the code through the HTTP client or fixtures,
so survivors are over-reported, in the worst case almost doubled. Fine as a "where to look" list on a repo that otherwise cannot run, not
as a score.

### xdist is a trap

`-n 4` made iptv_apps stats finish in 176 s wall (567 s CPU) but the result was a false "no test executes any of the changed functions
(28 mutants unreachable)", because the trampoline hits are recorded in the xdist workers and lost. The harness now refuses `-n`/`--dist`
(UNVERIFIED).

## Survivors I read

87 survivors read in full or in the first 10 (r2, gl1, mon1, bw1, ip1s, r1 all of them; sn1, mon3u, gl3u first 10; ip3s first 60 not judged).
Judged by reading the mutated line against the source and tests: **39 noise / equivalent, 48 real or probably real.**

Worst 10 (what to fix, with the evidence):

1. **gl1 `redact_secrets` (gitlark security.py)**: 7 of 8 survivors are the regexes themselves: `r'XX(sk|pk|api[_-]?key)...XX'` (pattern can never match),
   `[A-ZA-Z0-9/+=]{40}` (drops lowercase), `[a-za-z0-9_-]{16,}` (drops uppercase). The sk/pk/api-key and generic 40-char patterns have no
   test that a secret is actually redacted. A secret-redaction function with untested patterns is the paywall/auth class the plan targets.
2. **gl3u refresh endpoint**: every mutant of the two `HTTPException(401, "Invalid token...")` branches survives, including one that removes
   the `status_code` argument (would raise `TypeError` if executed). The invalid-token branches are never executed by any test.
3. **r2 `tick()` passes the URL to the probe** (`checker.probe(None, ...)` survives): killed by a new 4-line test (proven real).
4. **r2 `probed += 1`** (`probed = 1` survives): no test probes two monitors; killed by a new test (proven real).
5. **r2 failure-counter reset on success** (`= 0` to `= 1` survives): killed by a new test (proven real).
6. **mon3u `if mon.type == "heartbeat"`** (flipped to `!=` survives): the exact condition the commit changed is untested, and the
   neighbouring `effective_type = update_data.get("type", mon.type)` mutants (7 of the first 10) all survive because the commit left it as
   dead code. Mutation testing found the leftover dead assignment too.
7. **bw1 `should_update_status`**: the terminal-status override for `vetoed` and `died` is untested (5 survivors); `enacted` is covered.
8. **r1 `is_bill_dead`**: `current_congress(current_date)` mutated to `current_congress(None)` survives, so the "all branches" tests only
   pass on today's real clock, not because the injected date is used (a latent time-dependent test).
9. **sn1 `Broker.history`**: `ttl_seconds > 0` mutated to `>= 0` survives: the TTL=0 boundary has no test. (The other 9 of the first 10
   survivors are 401 `detail` strings, one whitespace-only equivalent, and an equivalent default.)
10. **ip3s account deletion**: `EPGSource.user_id != user_id` (inverted delete filter) survives, as do `.delete(synchronize_session=None)`
    and `stream_ids = None`: the data-deletion queries are not verified by `tests/test_account.py` (selected file only, so some of the 280 may
    be covered by tests the selection missed).

Noise patterns to filter: `logger.*` call text (mon1: 4 of 4), `detail=`/`message=` strings (sn1: 8 of 10), time-boundary `<` vs `<=`
on `time.time()` (ip1s: its only survivor), default-argument constants, and whitespace-only mutants. The harness labels the first two and
whitespace; it cannot see dead code or boundaries.

## What breaks

| Failure | Seen on | Harness behaviour |
|---|---|---|
| Decorated functions skipped by mutmut | every router (4/4 router-only commits; 2 more skipped inside sn1) | UNVERIFIED with the function list; `--unwrap-decorators` experimental |
| Suite too slow for the cap | iptv_apps (full), billwatch at 602 s | UNVERIFIED with partial counts; use `--select-tests` |
| Red or layout-sensitive tests (mutmut copies code into `mutants/`, one directory deeper) | gitlark (11, frozen OpenAPI contract), shrike-notify (5), taa (2-3), billwatch (1-2) | enumerated with one plain pytest pass, `--deselect`/`--ignore`d, reported in the summary; repo-root files are symlinked into the service dir for `parents[N]` lookups |
| HEAD does not import | bw3, gl2 | UNVERIFIED with the pytest error text |
| xdist | iptv_apps | refused |
| Unreachable code (no test executes it) | taa2, bw2 | FLAG `untested_functions` |
| Flaky kills | sn1 cold 55/23 vs warm 54/24; bw1 cold vs warm differ by one deselected test; gl1 failed once with `rc=1` (load 16) and passed on the rerun | not diagnosed |

## mutmut diagnosis (the traceback)

`mutmut --version` failing is **not** a broken install. mutmut 3.x loads its config at import and guesses `source_paths` from the cwd name;
in `$HOME` that raises `FileNotFoundError: Could not figure out where the code to mutate is`. A fresh `pip install mutmut` on the Mac does
the same. mutmut 3.8.0 + libcst 1.9.0 in `~/qa-venv` import and run fine from inside a project. mutmut must live in the same Python as the
tests, so the harness borrows it (appended last on `sys.path`) into each repo venv; both are Python 3.12 on the box. cosmic-ray 8.7.0 is
downloadable (the box has PyPI access) but I did not try it: mutmut worked, and cosmic-ray needs a per-project session/config database.

## Not verified

- A bug-catch rate (no seeded-bug study; confirmed outcomes are test gaps, 3 of 3 attempted kill tests succeeded).
- Fidelity of `--select-tests` on iptv_apps (no full run fits the cap) and the incremental warm cache on more than one repo.
- Whether the 13 unread sn1 survivors, 28 unread mon3u survivors, 13 unread gl3u survivors and 220 unread ip3s survivors follow the same
  noise ratio.
- Anything with Postgres-backed tests (every suite here uses SQLite/in-memory), Mac venvs for these repos, and cosmic-ray.
- Flakiness causes (above). Timing at an idle box: the fleet dev lanes were off, but other QA builders kept the load average at 8-56.
