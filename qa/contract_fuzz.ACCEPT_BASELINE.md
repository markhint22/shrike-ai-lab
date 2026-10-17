# Contract fuzz: install, first run and `--accept-baseline` checklist (Phase 4)

Applies to every repo in `contract_fuzz.REPOS` (iptv_apps) and `qa/contract_fuzz_repos.json` (billwatch, gitlark). Shadow only; nothing here can block a deploy.
A baseline is a HUMAN decision ("these signatures are understood or ticketed"); `--accept-baseline` is the only thing that writes one, and a plain run never does.

## 0. Why it is not running today
The 2026-10-16 home wipe removed `~/qa-venv`, `state/qa_shadow/contract_fuzz_baseline_<repo>.json` and the cron line was never installed. Result: `UNVERIFIED schemathesis missing`.

## 1. Tooling (box)
```
bash qa/fuzz_tool_install.sh            # dry run: what the P1 installer (ops/qa_tools_install.sh) would install, schemathesis only
bash qa/fuzz_tool_install.sh --check    # exit 0 only when schemathesis is present in $OVN_DIR/qa-tools/.venv (read-only)
bash qa/fuzz_tool_install.sh --apply    # install it (and nothing else: every other QA tool is skipped via QA_TOOLS_SKIP)
```
There is one installer: P1's `ops/qa_tools_install.sh` (the wrapper only narrows it). `contract_fuzz.find_schemathesis` finds the venv last, so an old `~/qa-venv` copy still wins when present. The P1 installer
pins `schemathesis>=4,<5`; this README was validated on 4.28.0 and every verdict records `schemathesis_version`, so note it when you accept a baseline.
Each repo also needs its own backend venv on the box (`<clone>/<app_dir>/.venv/bin/python`, the repo's `requirements.txt` installed): billwatch `billwatch-backend/.venv`, gitlark `backend/.venv` (or `venv`), iptv_apps `iptv-backend/.venv`. A missing one reports `UNVERIFIED no venv`.

## 2. First run per repo (manual, from `~/overnight-queue`, never against a live working tree: it uses a detached worktree)
```
python3 qa/contract_fuzz.py check --repo billwatch --ref origin/develop       # => FLAG "no baseline: N signatures observed"
```
Read `details.signatures`, `details.blocked_outbound` (must be 0; non-zero = a route reached for the network: add it to the repo's `exclude_paths` and say why), `details.operations_excluded`,
`details.responses_401` (an authenticated repo with a high 401 share reports UNVERIFIED "lost its auth": exclude the route that revokes the throwaway token).

## 3. Triage (the checklist; do not skip)
- [ ] `blocked_outbound` is 0, or every host in `blocked_outbound_hosts` is explained and its route excluded. Re-run until 0.
- [ ] Every `[not_a_server_error] 5xx` signature is either (a) already in `CLAUDE_QUEUE.md` / an open ticket (put the signature text in the ticket), or (b) added to the queue now. A real 5xx is a bug, not baseline noise.
- [ ] `[response_schema_conformance]` signatures: decide per signature: fix the response model, or accept (a known loose schema). Write the decision next to the baseline commit message.
- [ ] `transient_network_errors` are listed but not signatures: if the same operation shows up two nights in a row it is a real timeout, queue it.
- [ ] The run is not UNVERIFIED (venv, schemathesis, startup, auth bootstrap all fine) and `schemathesis_version` is the pin.
- [ ] Two consecutive runs on the same SHA give the identical signature set (the fuzz is seeded and the DB is fresh; a difference means flake, investigate before accepting).

## 4. Accept
```
python3 qa/contract_fuzz.py check --repo billwatch --ref origin/develop --accept-baseline
```
Writes `state/qa_shadow/contract_fuzz_baseline_billwatch.json` atomically with the parameter fingerprint (seed, -n, phases, checks, excludes). Changing any of those makes the old baseline UNVERIFIED (re-accept on purpose).
After accepting, a nightly run is PASS (nothing new), FLAG (new signature: look at it the next morning) or UNVERIFIED (could not judge). `details.fixed` lists signatures that disappeared.
- [ ] Note the accepted SHA and the signature count in the queue's status file / memory so the next reviewer knows what was accepted.

## 5. Schedule
Install the lines from `qa/phase4_cron.proposed.txt` (box crontab, lead only) after steps 1-4 for at least iptv_apps. Add a repo to the nightly run by naming it in `OVN_FUZZ_REPOS` (default `iptv_apps billwatch gitlark`);
a repo with no baseline just reports FLAG "no baseline" nightly, which is harmless.

## Onboarding a new repo
Add an entry to `qa/contract_fuzz_repos.json` (same schema as `contract_fuzz.REPOS`; an entry missing a required key is ignored and the repo reports NA). Fill `env` with NON-SECRET placeholders only, blank every outbound-service key
(some backends run an AI/sync job at startup and bail out only because the key is blank), write `exclude_paths` as `[regex, reason]` for every route that can open a socket to anything but the app's own DB, and give it a throwaway login in `auth`
(`json` or `form` body) unless the app has none (gitlark: OAuth only, so it fuzzes unauthenticated with `auth_loss_max: 1.01`; reaching its authenticated routes needs a test-only token, a documented follow-up).
