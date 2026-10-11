# qa/gate_gdparse.py - GDScript parse + lint cells (gate `gdparse`, SHADOW) - analysis F12, 2026-10-10

`gate_scanners` has no GDScript tool, so xlite (the highest-escape repo) read "scanners PASS" while effectively only gitleaks ran, and GUT **silently skips** a test script it
cannot parse (still exits green: the `gut-skips:xlite` alerts). This gate parses every changed `.gd` with gdtoolkit.

    python3 qa/gate_gdparse.py check --repo xlite --base REF --head REF [--no-record] [--enforce-exit] [--timeout S]

It is picked up by `qa_run_shadow.sh` (globs `gate_*.py`) and listed by `qa_enforce.sh`; default mode is **shadow**.
**Second consumer (coupling):** `release_candidate.py` (`run_gates_on`, used by `release_candidate cut --run-gates`) ALSO globs every `qa/gate_*.py`, so this gate runs against
`main..candidate` there too. In `cut --run-gates` any gate verdict outside PASS/NA/FLAG turns the candidate UNVERIFIED and a gdparse FLAG turns it FLAG (release_candidate itself is shadow and
not in `qa_gate_modes.json`, so nothing blocks today). Because gdtoolkit is NOT installed on the box (`~/qa-venv` has no gdtoolkit), the not-installed case is **NA in shadow** (details.gdtoolkit_missing=true,
summary names the install step) so neither the daily shadow rows nor an xlite release-candidate cut are polluted by a tool that was never deployed; once the gate is **enforced** the same case is
UNVERIFIED (an enforced gate that could not check must not read clean). Lead decision before the first xlite cut you want gated: install gdtoolkit into `~/qa-venv` (below).

| cell | what | effect on the verdict |
|---|---|---|
| `gdparse` | every changed/added `*.gd` (not under `addons/`, `.godot/`) must parse; invalid UTF-8 counts as a parse error (Godot refuses it too) | a parse error => **FLAG in shadow, FAIL once enforced** (`details.would_be_verdict` always says FAIL); each error lists file, `line N col M: message` and whether the file was ALREADY broken at the merge-base (`preexisting`, rename-aware; still counted: the author touched it and left GUT skipping it) |
| `gdlint` | gdtoolkit DEFAULT lint rules (a repo `gdlintrc` is deliberately not read), baseline-relative: only findings in EXCESS of the merge-base count per (file, rule, message with digits masked) are `new` | **advisory only**: never changes the verdict; counts + first 40 in `details.gdlint` |

Verdicts: `NA` (gate off / no changed `.gd` / only vendored `.gd` / gdtoolkit not installed while shadow), `UNVERIFIED` (gdtoolkit not installed while ENFORCED, or crashed, git failure, a changed `.gd` unreadable/over 1 MB/tool error on it, helper
timeout: never PASS), `FLAG`|`FAIL` (parse errors), `PASS`. Blobs come out of `git archive` of the two refs into a temp dir (removed in `finally`); nothing is executed, no live clone or checkout is touched.

gdtoolkit discovery: `$QA_GDTOOLKIT_PYTHON`, else the python beside the `gdparse` binary (`$QA_TOOL_GDPARSE` > `~/qa-venv/bin` > `~/qa-tools/bin` > PATH), else the running interpreter. Helper `qa/gdtoolkit_run.py`
(stdlib + gdtoolkit; run with `python -I`) speaks JSON so one process parses/lints a whole range.
**Install on the box (NOT done by this change):** `~/qa-venv/bin/pip install gdtoolkit` (4.5.0 verified in a scratch venv with python3.12 on the box on 2026-10-10: imports, parses all 565 non-addons `.gd` of xlite origin/develop in 3.5 s, lints them in 6.6 s).
Kill switches: `OVN_QA_GDPARSE=off` (or `qa_enforce.sh gdparse off`), `QA_GDLINT=off` (skip only the lint cell). Tunables: `QA_GDPARSE_TIMEOUT` (180), `QA_GDPARSE_MAX_FILES` (1500).

## Measured (2026-10-10, scratch venv, read-only archives of xlite)

* Parse errors on current xlite HEAD: **0 of 565** (origin/develop 90b412d), **0 of 563** (origin/claude/feature 25397cf), **0 of 563** (origin/main fdf4ca7). gdlint default rules: 718 / 721 / 700 findings on those trees (mostly `max-line-length`), which is why the lint cell is advisory and baseline-relative.
* Replay of the gate over the last 400 non-merge commits of xlite origin/develop (14 days): 209 PASS, 191 NA (no changed .gd), **0 FLAG**: false-positive rate 0 of 209 scanned ranges.
* Recall (seeded syntax breakage of 60 random xlite files): dropping a function's `:` 39 of 39 caught; deleting the first `(` 38 of 58 (the rest were `(` inside comments or strings, so still valid); a mixed tab/space indent 0 of 55 (gdparse accepts it; Godot rejects it; gdlint's `mixed-tabs-and-spaces` is off by default). So this catches syntax breakage, **not** the other silent-skip causes seen on xlite (`extends GUTTest` typo, empty/placeholder test files: that is F7 / `E_GD_TEST_NOT_GUT`, a different package).
* The shadow rows here are the only evidence that exists; plan: at least 5 days of shadow, then `qa_enforce.sh gdparse enforce` for the parse cell only (nothing here enables it).
