# S11 - Android device lane (advisory)

Nightly, headless Android emulator (KVM) on the GPU box + the Chickadee Appium/WebdriverIO e2e suite, run against the STAGING backend.
**Advisory only**: verdicts are `PASS | FLAG | UNVERIFIED`, never `FAIL`; nothing can block on it; exit code is always 0.
Retry once, then report; failed specs keep a screen recording and the logcat.

## One-time setup (already done on the box)

1. `sudo usermod -aG kvm mhintermeister` (the only system-wide change; new login/cron sessions pick it up, `cron_nightly.sh` re-execs under `sg kvm` otherwise). Already effective for this user as of 2026-10-02.
2. `qa/device_lane/setup_emulator.sh` - idempotent, no root: SDK packages into `~/android-sdk` (emulator, platform-tools, android-34
   google_apis x86_64 image), AVD `qa_api34` (pixel_6, 1080x2400 @420dpi, 3 GB, 4 cores) under `~/qa-avd`, Appium 3 + uiautomator2 into
   `~/qa-tools/appium`. `--check` is read-only, `--measure` also boots the AVD and records boot time and idle CPU/RAM.
3. Credentials file `~/.config/qa-devicelane/staging.env` (mode 600): `CHICK_EMAIL/CHICK_PASSWORD` (staging free account) and
   `CHICK_PREMIUM_EMAIL/CHICK_PREMIUM_PASSWORD` (staging premium account). Never printed; spec output is redacted before it is saved.
4. Cron: the line is in `cron.txt` (NOT installed; Mark/the integrator adds it with `crontab -e`). One run nightly at 01:20 (box sar: 9-10% mean CPU 01:00-05:59 vs 14-21%
   in the afternoon; ends before the 03:10/03:30/04:00 jobs).

## Production-safety contract (2026-10-02)

* ONE scheduled bounded run per night, advisory: verdict PASS|FLAG|UNVERIFIED, exit always 0, never takes `run.lock`/a repo lock, never blocks hygiene or promote.
* Resources: the whole run is pinned to `QA_CPUSET` (default 10-15 = 6 of 16 cores), `nice -n 10`, `ionice -c2 -n7`; the emulator itself runs `ionice -c2 -n7` (idle class starved the one real boot) with a 420 s boot timeout (retried once).
* Time: hard overall cap `DL_OVERALL_TIMEOUT` (default 6000 s) enforced by a watchdog inside `run_nightly.sh` (abort -> teardown -> UNVERIFIED line), plus a backstop
  kill in `cron_nightly.sh` at cap + 420 s. Spec phase capped at `DL_MAX_SECONDS` (4200 s), each spec at `DL_SPEC_TIMEOUT` (420 s).
* Retry-once-then-report: every failing spec is retried once; an emulator boot failure (timeout/early exit) is retried once; then reported, never looped.
* Teardown: `trap` cleanup (appium, emulator, adb-if-idle) and then `verify_teardown`, an independent process check for anything carrying our avd name or appium
  port (escalates TERM -> KILL, writes `runs/<id>/teardown.json`, logs `teardown verified clean` or `TEARDOWN LEAK`). `cron_nightly.sh` repeats the check after
  the run (`state/qa_devicelane/teardown_cron.json`), skipping it only if a manual run holds `lane.lock`.
* Tests never launch a real emulator: `test_qa_devicelane.sh` uses a stub SDK; the single real-boot check is behind `DL_REAL_EMULATOR_TEST=1` (OFF by default;
  `run_all.sh` force-unsets it, so the 6-hourly sweep can never start one).
* No flake loops: do not write or run repeated-emulator loops; a flake table comes from the nightly `history.jsonl` (`flake_stats.py`), one run per night.
* KVM: needs `/dev/kvm` rw for the user. If not: verdict UNVERIFIED with `KVM unavailable ... run sudo usermod -aG kvm <user>`, and nothing is built or booted.
  The one human command (once, then a NEW login/cron session, no reboot): `sudo usermod -aG kvm mhintermeister`. On the box today `id` already lists `kvm`,
  `/dev/kvm` is rw for the user, and `emulator -accel-check` says "KVM (version 12) is installed and usable".

## What a run does (`run_nightly.sh`, called by `cron_nightly.sh`)

lock -> preflight (SDK/AVD/appium present, staging `/health`, both test-account logins) -> build the debug APK pointed at staging from
`git archive` of `origin/develop` in a /tmp scratch copy (cached by sha+backend; the live clone is never touched) -> staging janitor (put
the two test accounts back to canonical) -> `seed_data.py` -> boot emulator (cpuset `QA_CPUSET`, default 10-15) -> install -> private
Appium on :4733 -> every spec, retry once -> janitor again (also on abort) -> verdict line + `state/qa_shadow/devicelane.jsonl` +
`state/qa_devicelane/history.jsonl` -> emulator, appium and adb are always cleaned up (own process groups; only our pids/port).

| File | Role |
|---|---|
| `lane_env.sh` | shared config + portable helpers (kvm check, start/stop emulator and appium, kill_tree, timeout shim) |
| `setup_emulator.sh` | idempotent provisioning, `--check`, `--measure` |
| `build_apk.sh` | scratch build of the debug APK (staging URL patched in, refuses to build if it cannot patch) + e2e extraction |
| `prep_e2e.py` | scratch-copy adaptation of the repo suite (see "Adapting the suite" below) |
| `seed_data.py` | extra staging data the suite assumes, through the public API only, idempotent |
| `lane_runner.py` | runs specs sequentially, retry-once, screenrecord + logcat on failure, Appium-crash detection and restart |
| `lane_report.py` | verdict + shadow log + history; applies `known_issues.json` |
| `known_issues.json` | quarantine of specs that fail for non-app reasons (still run once, never FLAG, recovery is reported) |
| `flake_stats.py` | per-spec reliable/flaky/broken classification from `history.jsonl` |
| `make_xmltv.py` | generates the multi-channel guide fixture (see "Open item") |
| `overlay/tests/` | replacement specs for repo specs the app has drifted away from |
| `cron.txt` | the crontab line (not installed) |
| `cron_nightly.sh` | cron entry: path resolved before cd, minimal PATH, `flock -n`, cpuset, `sg kvm` re-exec |

Tests: `scripts/test/test_qa_devicelane.sh` (hermetic: fake adb/emulator/appium/node/gradle, stub backend; real entry points by absolute and
relative path under `env -i`). Register it in `run_all.sh` (integrator).

## What the suite is (inventory, resolved)

`iptv_apps/iptv-android/e2e` (identical on main, develop and claude/feature): 34 specs in `tests/*.test.mjs`, plus the root `login.test.mjs`
smoke, 15 page objects in `pages/`, `capture-screenshots.mjs`, `run-all.mjs`. It is plain Node scripts using `webdriverio`'s `remote()`
against Appium (UiAutomator2) - there is no `wdio.conf`, no Jest/Mocha, files are `.mjs`. That is why inventories that look for wdio config or `*.test.js`
report "none". Each spec is self-contained and exits 0 pass / 1 fail / 2 skip.

## Adapting the suite (scratch copy only; the repo is never edited)

The suite was written against PROD accounts and an older UI. `prep_e2e.py` rewrites, on the scratch copy:

* prod test-account literals -> env lookups (no fallback to the prod literal: a missing variable fails loudly instead of driving prod);
* the channel-row pixel regex `[42..1038]` -> also `[42..996]` (Discover grew an A-Z fast-scroll rail; the old regex matched nothing, which
  failed browse-search, playback and everything that opens a channel);
* the EPG add-source success assertion (the app now shows `Guide loaded: N channel(s)...`, not `EPG source added...`);
* the playlist-import assertion (the app returns straight to the stream list, there is no `Imported N channels` card);
* `overlay/tests/watchlist-screen.test.mjs` replaces the repo spec (the Watchlist toggle moved into each row's "More options" menu).

Each patch is a plain substring replacement that does nothing once the repo fixes its own spec. These are repo-side bugs worth fixing in
`iptv_apps` (the lane found them).

## Staging data

`seed_data.py` adds to the staging PREMIUM account: a vod stream "Big Buck Bunny", a live stream "Mux Live Test" (distinct URLs: the backend
400s on duplicates), a guide mapping QA Test Channel 1 -> `qa.test.channel`, one watch-history row. `iptv_apps/scripts/e2e_janitor.py --env staging`
(extracted from the same ref) runs before and after; it deletes everything non-canonical again. `DL_NO_JANITOR=1` disables both sweeps.

## Verdicts

* `PASS` every non-quarantined, non-skipped spec passed first try, no app crash/ANR in logcat.
* `FLAG` a spec failed twice/timed out, was flaky (failed then passed), or the app crashed during a passing spec.
* `UNVERIFIED` could not run (not provisioned, lock held, staging down, test login rejected, build/emulator/appium failure, or ALL specs failed - environment suspected).

## Open item (one human step)

`guide-channel-picker` and `guide-program-loadmore` need >= 2 EPG-mapped channels and a long schedule; the canonical staging feed has 1 channel / 1 program, and the
backend only accepts guide sources by public URL. Route (built, not yet exercised end to end because nothing is hosted): `python3 make_xmltv.py >qa-test-guide-multi.xml`,
host it publicly (e.g. as another file in the existing QA fixture gist, 14-day window, regenerate monthly), then `DL_GUIDE_MULTI_URL=<raw url>` in the credentials file:
`seed_data.py` adds the source and auto-maps it, the janitor removes it after the run, and both specs leave `known_issues.json` automatically.
`favorites-screen` is quarantined as an obsolete spec (it opens a Favorites drawer item that no longer exists; the toolbar star is covered by `favorites.test.mjs`).

## Measured on the box (16 cores, 123 GB)

See the report that accompanies this commit for boot time, idle CPU/RAM, run duration and the flake table.
