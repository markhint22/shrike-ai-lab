#!/usr/bin/env python3
"""scripts/ovn_qwen_explore.py - the box-side exploratory researcher: the local Qwen finds NEW work by reading code (2026-10-13).

Why: the Chickadee (iptv_apps) and xlite lanes ran out of work and the GPU idled ~89% of the day. New roadmap features came from (a) the Mac-side headless Claude job (capped, and
Claude hit its usage limit before) and (b) ovn_local_research.py, which only turns evidence from deterministic collectors into items - those collectors are exhausted. Mark's
orders: Qwen does the research itself, no low cap, Claude out of the equation, and it is part of the QUEUE LOOP (event-driven), not another clock-driven scheduler.

How (ONE repo, ONE lens per invocation):
  0. gates   kill switch OVN_QWEN_EXPLORE=off, per-repo + global flock, self-throttle pause, daily cap, cooldown, enough-fuel check, GPU-busy deferral
  1. snapshot  read-only: `git archive` of origin/overnight/feature into state/qwen_explore/snap/<repo>/<sha> (never the live working tree, never a write into repos/*)
  2. lens      rotating lens ledger (bug-hunt, authz-input, test-gaps, performance, api-contract, data-integrity, dead-code, type-safety, a11y-ux, completeness, docs-drift); a lens / file is
               not repeated until its TTL passes
  3. pass A    Qwen sees the file tree (sizes + git churn + recently covered) and the lens and names <= 6 target files (a deterministic fallback fills in when it names too few)
  4. pass B    deterministic code loads those files (token budgeted), adds AGENTS.md + the existing roadmap/backlog/progress/done titles + recent commit subjects, and Qwen returns
               STRICT JSON items (title, file, symbol, evidence_quote, what_is_wrong, proposed_change, verify, size, tier). One JSON repair retry.
  5. verify    MECHANICAL acceptance (what makes a 27B safe to trust; the quote existing is NOT enough, the CLAIM is checked too - review of 2026-10-13):
               file exists in the snapshot AND is one the model was shown; symbol is DEFINED in it and the verbatim evidence_quote sits INSIDE that symbol's body (py / gd / ts / vue spans);
               not out of scope / banned / vendored / protected (prose, title and VERIFY scanned for protected names, injection phrases and files that do not exist);
               VERIFY is ONE command from a closed allow-list (pytest, vitest, GUT, grep, test; no python -c, chaining, pipes, expansions) - static greps only as absence greps (docs-drift: any);
               text rules: no hedged / self-refuting / authority-citing claims, no convention change (tz / type / encoding) without a second file, no schema / migration items, no atomicity
               claim about a function with one commit, no 'missing auth' on a route the repo itself declares public, no 'untested' claim when a test names the symbol / module / route;
               passes ovn_auto_research_validate.py (format, mechanical-gap, duplicate titles, near-duplicates) and the intake lint (ovn_spec_rules.lint_item + ovn_backlog_eligibility);
               not a duplicate of / already done by any roadmap, backlog, progress, done line or recent commit, nor of another item of the same pass (same file + VERIFY / near-identical title);
               its VERIFY is RED on the snapshot (scripts/ovn_spec_check.sh in a scratch copy, under bubblewrap: no network, read-only world; red only because the test file is new => P4);
               finally ONE skeptic call (temperature 0) tries to refute the survivors against the symbol's source; unparseable / missing verdicts drop the item (fail closed).
               A rejection histogram is recorded per pass.
  6. append    accepted items go to roadmap/<repo>.md as [ready] lines tagged [src:qwen-explore] (flock on the planner lock, atomic write, commit ONLY that file, no push)
  7. chain     immediately: ovn_planner.sh <repo> (decomposes the new [ready] features; same flock as the cron/queue passes), then queue_refill.sh <repo>, then state/supply_kick
               wakes the loop's idle wait. No hourly clock gap.
  5b critic  (OVN_QWEN_CRITIC=off|shadow|on, default shadow) every mechanically verified item is then judged by the local Qwen in a FRESH context (item text + verified evidence
             window + red-before result + AGENTS.md summary only; none of the explorer's reasoning) against a fixed JSON rubric, TWICE (different temperature + seed). Accepted only if
             BOTH samples approve and no hard-fail dimension trips; a disagreement is a reject. Survivors are ranked by rubric score and only the top OVN_QWEN_CRITIC_TOPN (6) are
             appended. Every verdict is appended to state/qwen_critic.jsonl (rotated past 8 MB). shadow = AFTER the append (and after the chain), under a hard total budget (OVN_QE_CRITIC_SHADOW_BUDGET_S, 120 s): it cannot delay or lose an accepted item, any failure is swallowed; on = BEFORE the append, filter (a critic
             failure/timeout/malformed reply rejects the item - fail-closed - and it is simply proposed again on a later pass); off = the pre-critic behaviour, untouched.
Self-throttle: items carry the tag; state/outcomes.jsonl tells how the backlog items decomposed from them fared. After >= 20 consumed items with < 40% landed, the explorer pauses
itself (ONE alerts.log warn line) and resumes after 24 h or when the rate recovers. The same rule runs on the subset the critic APPROVED (accepted.jsonl records the verdict): if the critic approves but < 40% of
those consumed items land (>= 20 consumed), the explorer pauses. The summary line carries the critic reject rate.

feature-ideation lens (2026-10-23, scripts/ovn_qe_feature.py): when a repo is STARVING (no [ready] roadmap feature and the doable backlog is below OVN_QE_FEATURE_FUEL) the local Qwen is asked for 3-4 USER-VALUABLE
features the product plausibly still lacks (missing edge-case behaviour / endpoint / screen / setting, UX or reliability gap, a README promise with no implementation). Inputs are deterministic: the vision (README /
ROADMAP / AGENTS), an outline of the app surface (routes, models, screens, classes), the existing titles, recent commits and the recently proposed titles. Every item is anchored to an existing file + symbol with a verbatim
quote from INSIDE that symbol and ONE test VERIFY that is red before, so ALL the mechanical gates, the skeptic and the critic apply unchanged; extra text rules reject helper-only items, outcomes that are not observable,
auth / crypto / payment / schema work, multi-file changes and re-proposals. OVN_QE_FEATURE_LENS=off|shadow|on (DEFAULT shadow): shadow runs everything but appends NOTHING to the roadmap and does not chain the planner: every
would-be item (verdicts, rejection reasons) goes to state/qwen_explore/feature_shadow.jsonl and ONE summary line to logs/qwen_explore.log; on appends [ready] lines tagged [src:qwen-explore-feature]. Its own cap is
OVN_QE_FEATURE_MAX_PER_DAY (8 passes / repo / day) so it never consumes the bug-lens cap. A pass that made ZERO model calls is not counted toward OVN_QE_MAX_PER_DAY (default 72); a lens with fewer than 2 candidate files
is retried with the repo's top-level modules (roots dropped, then the lens extension filter dropped).

usage: ovn_qwen_explore.py <repo> [--dry-run] [--force] [--lens NAME] [--from-queue] [--no-chain] [--max-items N]
env:   OVN_DIR (default ~/overnight-queue), LITELLM_BASE, LITELLM_MASTER_KEY, OVN_MODEL, DRY_RUN=1 (same as --dry-run: nothing is written, no chain), OVN_QWEN_EXPLORE=off (kill switch),
       OVN_QE_MAX_PER_DAY (72 passes/repo; zero-model-call passes are not counted), OVN_QE_FEATURE_LENS (off|shadow|on, default shadow) + the OVN_QE_FEATURE_* knobs of ovn_qe_feature.py, OVN_QE_COOLDOWN_PRODUCTIVE_MIN (45), OVN_QE_COOLDOWN_EMPTY_H (0.25 = 15 min), OVN_QE_LENS_TTL_H (4), OVN_QE_FILE_TTL_H (72), OVN_QE_READY_CAP (4),
       OVN_QE_THROTTLE_MIN_N (20) / OVN_QE_THROTTLE_MIN_RATE (0.4) / OVN_QE_THROTTLE_PAUSE_H (24), OVN_QE_FILE_TOKENS (20000), OVN_QE_MAX_CALLS (6), OVN_QE_GPU_BUSY_PCT (92),
       OVN_QE_CACHE_DIR (snapshot + scratch cache; default state/qwen_explore, a temp dir under --dry-run; a dry run WITH it also keeps its lens/file ledger there), OVN_QE_REF (default origin/overnight/feature),
       OVN_QE_SPEC_CHECK / OVN_QE_PLANNER / OVN_QE_REFILL (script overrides), OVN_QE_VERIFY_SECS (90), OVN_QE_DEBUG_DIR (keep every prompt + reply),
       OVN_QE_LANDABLE=off (xlite: do not restrict to items the 27B can land), OVN_QE_SKEPTIC=off (skip the refutation call; for tests only), OVN_QE_SANDBOX=off / OVN_QE_BWRAP (the red-check sandbox),
       OVN_QE_CRITIC_SHADOW_BUDGET_S (120) / OVN_QE_CRITIC_BUDGET_S (600, on-mode total) / OVN_QE_CRITIC_AUDIT_MAX_MB (8), OVN_QE_SANDBOX=off (the red-check REQUIRES bubblewrap and fails closed when it is missing; off = explicit opt-out), OVN_QWEN_CRITIC (off|shadow|on, default shadow), OVN_QWEN_CRITIC_TOPN (6), OVN_QE_CRITIC_TIMEOUT (120 s per sample), OVN_QE_CRITIC_MAX_CALLS (16 per pass)
KNOWN LIMITS (review rounds 3-4; the deterministic gates do not cover these, the skeptic / critic / the 27B's own tests are the remaining filters):
  - contradicted_by_quote reads only the QUOTED lines, not the whole function span: a claim contradicted two lines below the quote passes; a docstring line can serve as the evidence quote.
  - caller claims that name no file, or a real file that does not call the symbol, are not checked; duplicate detection misses a roadmap line that cites only a basename or a dotted symbol;
    "no tests" claims are only refuted under the test-gaps lens; a red-before on a NEW test file is red for any claim (items are demoted to P4 but the check adds no signal).
  - VERIFY allow-list leftovers (all bounded by the bubblewrap sandbox, which is REQUIRED): `grep -d recurse`, `grep ... .git/config`, `test -f /abs/path` (rejected later as cosmetic), pytest of any repo .py path.
  - semantically false but well-formed items (wrong behaviour described confidently, true-but-cosmetic items) can pass every deterministic gate.
  - the shadow critic runs inside the pass's own lock_global for up to OVN_QE_CRITIC_SHADOW_BUDGET_S after the items are committed (it can no longer delay or lose them).
exit:  0 always (research is best-effort; a model/LiteLLM failure is not an error); prints one summary line and appends it to logs/qwen_explore.log.
"""
import datetime
import fcntl
import hashlib
import http.client
import importlib.util
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ovn_qe_feature as QF

OVN_DIR = os.path.abspath(os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue"))
LITELLM = os.environ.get("LITELLM_BASE", "http://localhost:4000")
LITELLM_KEY = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")
MODEL = os.environ.get("OVN_MODEL", "qwen-dflash-27B")
SRC_TAG = "[src:qwen-explore]"
FEATURE_LENS = QF.FEATURE_LENS
GUT_RUNNER = "addons/gut/gut_cmdln.gd"


def _env_num(name, default, cast=int):
    try:
        return cast(os.environ.get(name, default))
    except (TypeError, ValueError):
        return cast(default)


MAX_PER_DAY = _env_num("OVN_QE_MAX_PER_DAY", 72)         # 2026-10-23: passes take 10-40 s and mostly end empty; 24/day was exhausted by ~10:00-12:00 for 5 of 7 repos. Zero-model-call passes are not counted at all.
LANDABLE = os.environ.get("OVN_QE_LANDABLE", "on")             # off = the xlite landable-items path is disabled
COOLDOWN_PRODUCTIVE_S = int(_env_num("OVN_QE_COOLDOWN_PRODUCTIVE_MIN", 45, float) * 60)
COOLDOWN_EMPTY_S = int(_env_num("OVN_QE_COOLDOWN_EMPTY_H", 0.25, float) * 3600)      # an empty pass costs ~1 GPU-minute; lens + file rotation already prevent repeats (3 h was a hidden low cap)
LENS_TTL_S = int(_env_num("OVN_QE_LENS_TTL_H", 4, float) * 3600)
FILE_TTL_S = int(_env_num("OVN_QE_FILE_TTL_H", 72, float) * 3600)
READY_CAP = _env_num("OVN_QE_READY_CAP", 4)
MIN_FRESH_FILES = _env_num("OVN_QE_MIN_FRESH_FILES", 8)
THROTTLE_MIN_N = _env_num("OVN_QE_THROTTLE_MIN_N", 20)
THROTTLE_MIN_RATE = _env_num("OVN_QE_THROTTLE_MIN_RATE", 0.4, float)
THROTTLE_PAUSE_S = int(_env_num("OVN_QE_THROTTLE_PAUSE_H", 24, float) * 3600)
FILE_TOKENS = _env_num("OVN_QE_FILE_TOKENS", 20000)
MAX_CALLS = _env_num("OVN_QE_MAX_CALLS", 6)
GPU_BUSY_PCT = _env_num("OVN_QE_GPU_BUSY_PCT", 92, float)
VERIFY_SECS = _env_num("OVN_QE_VERIFY_SECS", 90)
DEBOUNCE_ERR_S = 600
CHARS_PER_TOKEN = 3.6
MAX_TARGET_FILES = 6
FULL_VIEW_LINES = 420
MAX_ITEMS = 4
CRITIC_TOPN = max(1, _env_num("OVN_QWEN_CRITIC_TOPN", 6))
CRITIC_TIMEOUT = _env_num("OVN_QE_CRITIC_TIMEOUT", 120)
CRITIC_MAX_CALLS = _env_num("OVN_QE_CRITIC_MAX_CALLS", 16)
CRITIC_SAMPLES = ((0.1, 7101), (0.7, 7202))      # two independent samples: (temperature, seed)

# ------------------------------------------------------------------------------------------------ per-repo configuration
GENERIC_EXCLUDE = (r"(^|/)(node_modules|dist|build|vendor|\.venv|venv|__pycache__|\.godot|\.git|htmlcov|coverage|\.next|Pods)(/|$)", r"\.min\.", r"\.lock$", r"package-lock\.json$")
PROTECTED_FILES = (r"(^|/)AGENTS\.md$", r"(^|/)OVERNIGHT_[A-Z_]+\.md", r"(^|/)CLAUDE[A-Z_]*\.md$", r"(^|/)[A-Z_]*ROADMAP[A-Z_0-9-]*\.md$", r"\.queue-hard-banned-files", r"(^|/)\.env", r"\.github/workflows/")

REPO_CFG = {
    "iptv_apps": dict(
        kinds={"backend", "web"},
        roots=("iptv-backend/app/", "iptv-web/src/"),
        exclude=(r"^iptv-(ios|android|roku)/", r"^iptv-backend/alembic/", r"^store-assets/"),
        snap_exclude=("iptv-ios", "iptv-android", "iptv-roku", "store-assets", "node_modules", ".venv"),
        out_of_scope=(r"(^|[\s`'\"(=/])iptv-(ios|android|roku)/",),
        node_modules=("iptv-web",),
        hints={"bug-hunt": ("`.first()` / `.scalar_one_or_none()` / `db.get()` results dereferenced without a None check; `except Exception: pass` or a bare except that hides a failure the caller needs; a missing `await` on a coroutine; "
                            "a status code that contradicts the branch (200 on a failure path); int/str id mixups between route, model and service; a loop that mutates the list it iterates."),
               "data-integrity": ("a multi-row write loop that commits per row (partial state on failure) or never commits; a delete without its dependents; a value from a request or JSON stored without range / type checks; "
                                  "a counter or balance updated read-modify-write without a lock or an UPDATE ... SET x = x + 1.")},
        dialect=("- backend test: cd iptv-backend && python3 -m pytest tests/test_<name>.py -q   (backend tests live ONLY in iptv-backend/tests/test_*.py; a NEW file is fine - then the proposed_change must say 'Add iptv-backend/tests/test_<name>.py')\n"
                 "- web test: cd iptv-web && npx vitest run src/<dir>/<name>.test.ts   (new test file fine, same rule: say 'Add <path>')\n"
                 "- static (only when deleting that exact text IS the fix): ! grep -n '<12+ chars copied from the defective line>' <file>   (a presence grep is NOT accepted: a comment would satisfy it)"),
    ),
    "xlite": dict(
        landable=True,
        kinds={"game"},
        roots=("scripts/", "tests/"),
        exclude=(r"^addons/", r"^assets/"),
        snap_exclude=(),
        out_of_scope=(r"(^|[\s`'\"(=/])addons/",),
        node_modules=(),
        hints={"bug-hunt": ("an Array or Dictionary modified while it is iterated; a node used after `queue_free()` without `is_instance_valid`; division or modulo by a count / speed / stat that can be 0; "
                            "a grid or array index used without a bounds check (negative or >= size); `dict[key]` read for a key that no code path sets; a signal connected again on every call of a setup function; "
                            "integer division where a fraction is wanted; a function that returns on one branch and falls off the end (null) on another."),
               "type-safety": ("`:=` inference from a Dictionary / Array element or a Variant-returning call; an int compared with a String; a typed variable assigned `null`; `get_node()` result used without a null check."),
               "completeness": ("an enum value handled in one `match` / dict and missing from its sibling; a stat / status / mechanic that is written but never read (or read but never written); a function whose name promises behaviour but returns a placeholder.")},
        dialect=("- GUT test: godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_<name>.gd -gexit   (tests live FLAT in tests/ named test_*.gd; a NEW file is fine - then the proposed_change must say 'Add tests/test_<name>.gd')\n"
                 "- static (only when deleting that exact text IS the fix): ! grep -n '<12+ chars copied from the defective line>' <file>   (a presence grep is NOT accepted: a comment would satisfy it)"),
    ),
    "billwatch": dict(kinds={"backend", "web"}, roots=("billwatch-backend/app/", "billwatch-web/src/", "tests/"), exclude=(r"^billwatch-(android|ios)/",), snap_exclude=("billwatch-android", "billwatch-ios", "node_modules", ".venv"),
                      out_of_scope=(r"(^|[\s`'\"(=/])billwatch-(android|ios)/",), node_modules=("billwatch-web",), dialect=("- backend test: cd billwatch-backend && python3 -m pytest tests/test_<name>.py -q   (backend tests live ONLY in billwatch-backend/tests/test_*.py; a NEW file is fine - then the proposed_change must say 'Add billwatch-backend/tests/test_<name>.py'). Write the bare command: no 'test:' label, no .venv/bin prefix, no coverage flags.\n"
                 "- web test: cd billwatch-web && npx vitest run src/<dir>/<name>.test.ts   (new test file fine, same rule: say 'Add <path>')\n"
                 "- static (only when deleting that exact text IS the fix): ! grep -n '<12+ chars copied from the defective line>' <file>   (a presence grep is NOT accepted: a comment would satisfy it)")),
    "gitlark": dict(kinds={"backend", "web"}, roots=("backend/app/", "web/src/"), exclude=(r"^(android|ios|vscode-extension|frontend|src)/",), snap_exclude=("android", "ios", "vscode-extension", "node_modules", ".venv"),
                    out_of_scope=(r"(^|[\s`'\"(=/])(android|ios|vscode-extension)/",), node_modules=("web",), dialect=("- backend test: cd backend && python3 -m pytest tests/test_<name>.py -q   (backend tests live ONLY in backend/tests/test_*.py; a NEW file is fine - then the proposed_change must say 'Add backend/tests/test_<name>.py'). Write the bare command: no 'test:' label, no .venv/bin prefix, no coverage flags.\n"
                 "- web test: cd web && npx vitest run src/<dir>/<name>.test.ts   (new test file fine, same rule: say 'Add <path>')\n"
                 "- static (only when deleting that exact text IS the fix): ! grep -n '<12+ chars copied from the defective line>' <file>   (a presence grep is NOT accepted: a comment would satisfy it)")),
    "test-automation-agent": dict(kinds={"backend", "web"}, roots=("backend/app/", "frontend/src/"), exclude=(r"^(android|sdk|return|task|examples)/",), snap_exclude=("android", "node_modules", ".venv"),
                                  out_of_scope=(r"(^|[\s`'\"(=/])android/",), node_modules=("frontend",), dialect=("- backend test: cd backend && python3 -m pytest tests/test_<name>.py -q   (backend tests live ONLY in backend/tests/test_*.py; a NEW file is fine - then the proposed_change must say 'Add backend/tests/test_<name>.py'). Write the bare command: no 'test:' label, no .venv/bin prefix, no coverage flags.\n"
                 "- web test: cd frontend && npx vitest run src/<dir>/<name>.test.ts   (new test file fine, same rule: say 'Add <path>')\n"
                 "- static (only when deleting that exact text IS the fix): ! grep -n '<12+ chars copied from the defective line>' <file>   (a presence grep is NOT accepted: a comment would satisfy it)")),
    "shrike-monitor": dict(kinds={"backend"}, roots=("backend/app/", "aegis.py"), exclude=(), snap_exclude=(".venv",), out_of_scope=(), node_modules=(), dialect=("- backend test: cd backend && python3 -m pytest tests/test_<name>.py -q   (backend tests live ONLY in backend/tests/test_*.py; a NEW file is fine - then the proposed_change must say 'Add backend/tests/test_<name>.py'). Write the bare command: no 'test:' label, no .venv/bin prefix, no coverage flags.\n"
                 "- static (only when deleting that exact text IS the fix): ! grep -n '<12+ chars copied from the defective line>' <file>   (a presence grep is NOT accepted: a comment would satisfy it)")),
    "shrike-notify": dict(kinds={"backend"}, roots=("backend/app/",), exclude=(), snap_exclude=(".venv",), out_of_scope=(), node_modules=(), dialect=("- backend test: cd backend && python3 -m pytest tests/test_<name>.py -q   (backend tests live ONLY in backend/tests/test_*.py; a NEW file is fine - then the proposed_change must say 'Add backend/tests/test_<name>.py'). Write the bare command: no 'test:' label, no .venv/bin prefix, no coverage flags.\n"
                 "- static (only when deleting that exact text IS the fix): ! grep -n '<12+ chars copied from the defective line>' <file>   (a presence grep is NOT accepted: a comment would satisfy it)")),
}
DEFAULT_CFG = dict(kinds={"backend", "web"}, roots=None, exclude=(), snap_exclude=("node_modules", ".venv"), out_of_scope=(), node_modules=(), dialect=None)
GENERIC_DIALECT = ("- test: the repo's own runner on ONE test file, as AGENTS.md documents it (a NEW test file is fine - then the proposed_change must say 'Add <path>')\n"
                   "- static (only when deleting that exact text IS the fix): ! grep -n '<12+ chars copied from the defective line>' <file>   (a presence grep is NOT accepted: a comment would satisfy it)")
SRC_EXTS = (".py", ".ts", ".tsx", ".vue", ".gd", ".js")
PARKED_RE = re.compile(r"route to CLAUDE|\[CLAUDE\]|Claude[- ]only|AUTO-SKIP|beyond (?:the )?27B", re.I)
LANDABLE_NOTE = ("LANDABLE ONLY (the 27B that implements these has failed repeatedly on wiring work): propose ONLY an S item that changes ONE small, self-contained, GDScript-pure piece of logic "
                 "(a class_name helper / static func / RefCounted or Resource script: no scene, node, signal or `get_node` involved, no change to any other production file) and that a NEW GUT test in tests/ can drive "
                 "directly, failing now for the claimed reason. Do NOT propose: wiring a helper into battle code or any node script, edits that need a second production file, UI / scene / animation work, anything the "
                 "ALREADY-ON-THE-ROADMAP list shows as skipped or routed to CLAUDE.\n\n")
NODE_BOUND_RE = re.compile(r"^extends\s+(?:Node\w*|Control|Container|Button|Label|Panel\w*|Sprite\w*|Camera\w*|CanvasLayer|CanvasItem|Area\w*|Body\w*|Character\w*|Window|Popup\w*|TextureRect|Tree|ItemList|\w*Container|\"[^\"]+\")", re.M)
NODE_API_RE = re.compile(r"\bget_node\(|\$[A-Za-z_\"]|@onready\b|\.queue_free\(|\bget_tree\(|\badd_child\(")


def is_pure_gd(text):
    """GDScript logic a headless GUT test can drive without a scene: no node base class, no node API."""
    return not NODE_BOUND_RE.search(text or "") and not NODE_API_RE.search(text or "")

# lens -> (one line, guidance, file extensions or None, repo kinds or None)
LENSES = {
    "bug-hunt": ("error handling and logic bugs",
                 "Find REAL bugs: swallowed or over-broad exception handling that hides failures, wrong status codes, unchecked None/null/empty values, off-by-one and boundary errors, missing await, "
                 "wrong comparisons, stale state, resource leaks, int/str mixups.", None, None),
    "authz-input": ("authorization and input validation",
                    "Find endpoints/handlers missing an auth dependency, queries by an id without an owner/user filter (IDOR), unvalidated or unbounded input (sizes, page limits, regex), path traversal, "
                    "user-controlled URLs fetched server-side, secrets in logs.", (".py", ".ts", ".js"), {"backend"}),
    "test-gaps": ("missing tests for critical paths",
                  "Find critical, PURE or easily-driven logic (money/entitlement checks, parsing, state transitions, save/load) whose behaviour no test pins down. The item adds ONE focused test for ONE concrete "
                  "behaviour (it may also fix the defect the test exposes). Never a test for a trivial getter, never a test for code that is not called in production.", None, None),
    "performance": ("performance defects",
                    "Find N+1 queries, unbounded queries or lists with no pagination/limit on DATA-DRIVEN sizes (rows from the database or a request, not a small fixed grid), full-table loads to derive a small result, "
                    "and work repeated inside a per-frame callback (_process/_physics_process/_draw) or a per-row loop that could be hoisted out. Say where the size comes from.", None, None),
    "api-contract": ("API contract consistency",
                     "Find mismatches between what a client calls and what the server serves (wrong paths, wrong body fields, wrong status codes), response models that omit returned fields, inconsistent "
                     "field naming between schema and frontend types, error shapes that differ between endpoints.", (".py", ".ts", ".vue", ".js"), {"backend", "web"}),
    "data-integrity": ("data integrity and migrations",
                       "Find multi-step writes that are not atomic, missing commit/rollback, missing uniqueness or foreign-key constraints implied by the code, model/migration drift, values read from files/JSON/DB "
                       "without type coercion or clamping, save/load round-trips that lose or alias data.", None, None),
    "dead-code": ("dead code and duplication",
                  "Find functions/classes/branches with ZERO production callers (say you grepped and name the grep) and copy-pasted logic that has already diverged between copies. Deleting dead code needs the "
                  "callers analysis in the item.", None, None),
    "type-safety": ("type safety",
                    "Find unsafe casts, `any`, Optional misuse, missing null checks before attribute access, GDScript `:=` inference on Variant/Dictionary/Array indexing, int-vs-String comparisons, "
                    "untyped values crossing a boundary.", None, None),
    "a11y-ux": ("accessibility and UX defects visible in code",
                "Find buttons without type=\"button\", icon-only controls without an accessible name, modals without role=dialog or focus handling, images without alt, missing loading/empty/error "
                "states, click handlers on non-interactive elements, keyboard traps.", (".vue", ".tsx", ".ts", ".html"), {"web"}),
    "completeness": ("unfinished or inconsistent implementations",
                     "Find places where the code is visibly incomplete: an enum value or key handled in one match/dict/switch but missing from its sibling, a branch that returns a placeholder (0 / null / empty / pass) "
                     "in a function whose name promises behaviour, a field/constant that is written but never read (or read but never written), a mechanic defined in data or a class and never connected to its "
                     "obvious caller. The fix WIRES or COMPLETES the existing piece (name the caller file and function); it never adds a new helper nothing calls.", None, None),
    FEATURE_LENS: (QF.FEATURE_DESC, QF.FEATURE_GUIDE, None, None),   # only eligible through applicable_lenses(feature=True) (starving repo, OVN_QE_FEATURE_LENS != off)
    "docs-drift": ("documentation drift",
                   "Find documentation (README, docs/) that states an endpoint, command, env var, file path or behaviour the code no longer has. The fix is a doc edit; VERIFY greps for the stale text.",
                   (".md",), None),
}

# ------------------------------------------------------------------------------------------------ small helpers


def now_ts():
    return time.time()


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def atomic_write(path, text):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)                                        # never leave an orphan .tmp behind (ENOSPC mid-write)
        except OSError:
            pass
        raise


def norm_ws(s):
    return re.sub(r"\s+", " ", s or "").strip()


def norm_title(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


STOP = {"the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "is", "are", "with", "from", "that", "this", "it", "by", "as", "at", "be", "add", "fix", "new", "when", "not", "no"}


def words(s):
    return {w for w in norm_title(s).split() if len(w) > 2 and w not in STOP}


PATHISH = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.(?:py|ts|tsx|js|vue|gd|kt|swift|sh|sql|md|json|yml|yaml|toml|html|tres|tscn))(?![\w/])")


def paths_in(s):
    return set(PATHISH.findall(s or ""))


HIDDEN_CATS = ("Cf", "Cc", "Zl", "Zp", "Co", "Cs")


def clean_text(s):
    """NFKC-normalise and drop every invisible / control / bidi / zero-width character (and turn line separators into spaces). Model-controlled text is cleaned BEFORE any steering scan and before it is
    written anywhere: `ｉgnore` (fullwidth), `ig<ZWSP>nore` and U+202E / ESC must not slip past a regex blocklist (reviewer 3)."""
    t = unicodedata.normalize("NFKC", str(s or ""))
    return "".join(" " if ch in "\n\r\t\u2028\u2029\x0b\x0c" else ch for ch in t if ch in "\n\r\t" or unicodedata.category(ch) not in HIDDEN_CATS or ch in "\u2028\u2029")


def has_hidden(s):
    return any(unicodedata.category(ch) in HIDDEN_CATS and ch not in "\n\r\t" for ch in str(s or ""))


STRUCT_RE = re.compile(r"\[(?:feat|src):[^\]]*\]|\[(?:P[1-4]|T[1-4]|ready|decomposed|parked|done|[xX ])\]|\{\s*(?:cat|size|multifile|research)\s*:[^}]*\}", re.I)


STRUCT_OPEN_RE = re.compile(r"\[(?:feat|src):|\{\s*(?:cat|size|multifile|research)\s*:", re.I)


def defang(s):
    """Structural roadmap / backlog tokens in model text ([feat:ID], {cat: ...}, [P1], [ready], [x]) become parentheses: the planner and the validator consume those tokens."""
    t = STRUCT_RE.sub(lambda m: "(" + m.group(0)[1:-1] + ")", s or "")
    return STRUCT_OPEN_RE.sub(lambda m: "(" + m.group(0)[1:].lstrip(), t)           # an opener that never closes is defanged too (a later ']' in the line would close it for grep -oE)


def one_line(s, n):
    s = norm_ws(clean_text(s)).replace("`", "'").replace("—", "-").replace("–", "-")
    return s[:n].rstrip()


def cut_tokens(s, n):
    """one_line + cut to <= n chars at a whitespace boundary (never mid-token: `platform=(body.platform i` read like a corrupt line)."""
    t = one_line(s, 100000)
    if len(t) <= n:
        return t
    cut = t[:n]
    if t[n] != " ":
        k = cut.rfind(" ")
        cut = cut[:k] if k > 0 else cut
    return cut.rstrip()


def fit(s, n):
    """one_line + cut to <= n chars at a SENTENCE boundary (else a word boundary): a roadmap line must stay under the validator's 1500-char cap but never ends mid-word."""
    t = one_line(s, 100000)
    if len(t) <= n:
        return t
    cut = t[:n]
    k = max(cut.rfind(". "), cut.rfind("! "), cut.rfind("? "))
    if k >= n // 3:
        return cut[:k + 1]
    k = cut.rfind(" ")
    return (cut[:k] if k > 0 else cut).rstrip(",;:") + "..."


def feat_slug(feature_text):
    """The slug ovn_planner.sh puts in [feat:<repo>-<YYYYMMDD>-<slug>]: lowercase, non-alnum runs -> '-', trimmed, then the first 40 chars (shell: sed; cut -c1-40)."""
    s = re.sub(r"[^a-z0-9]+", "-", (feature_text or "").lower()).strip("-")[:40]
    return s or "item"


def git(clone, *args, timeout=60, binary=False):
    try:
        r = subprocess.run(["git", "-C", clone] + list(args), capture_output=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    if binary:
        return r
    r.stdout = r.stdout.decode("utf-8", "replace")
    r.stderr = r.stderr.decode("utf-8", "replace")
    return r


class Row:
    """The per-pass record (state/qwen_explore.jsonl)."""

    def __init__(self, repo):
        self.d = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "repo": repo, "result": "", "lens": "", "mode": "", "sha": "", "files": [], "proposed": 0, "accepted": 0,
                  "rejected": {}, "calls": 0, "ptok": 0, "ctok": 0, "secs": 0, "note": "", "slugs": []}

    cur = ""                                         # title of the item being judged (per-item trace for the debug dir)
    trace = None

    def reject(self, reason):
        self.d["rejected"][reason] = self.d["rejected"].get(reason, 0) + 1
        if self.trace is None:
            self.trace = []
        self.trace.append({"title": self.cur, "reason": reason})


# ------------------------------------------------------------------------------------------------ model
class ModelDown(Exception):
    pass


def call_model(messages, max_tokens, timeout, stats, temperature=0.2, seed=None, max_calls=None):
    """One chat completion. Raises ModelDown on any transport/HTTP/shape problem (the caller exits 0 best-effort)."""
    cap = MAX_CALLS if max_calls is None else max_calls
    if stats["calls"] >= cap:
        raise ModelDown("call budget (%d) exhausted" % cap)
    stats["calls"] += 1
    payload = {"model": MODEL, "messages": messages, "temperature": temperature, "max_tokens": max_tokens}
    if seed is not None:
        payload["seed"] = seed
    body = json.dumps(payload).encode()
    req = urllib.request.Request(LITELLM + "/v1/chat/completions", data=body, headers={"Content-Type": "application/json", "Authorization": "Bearer " + LITELLM_KEY})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            d = json.load(r)
        text = d["choices"][0]["message"]["content"] or ""
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError, KeyError, IndexError, TypeError, AttributeError) as e:     # IncompleteRead (a truncated reply) is an HTTPException, not an OSError
        raise ModelDown("%s: %s" % (type(e).__name__, str(e)[:140]))
    u = d.get("usage") if isinstance(d.get("usage"), dict) else {}
    for k, key in (("ptok", "prompt_tokens"), ("ctok", "completion_tokens")):
        try:
            stats[k] += int(u.get(key) or 0)
        except (TypeError, ValueError):
            pass                                                  # a non-numeric usage value is not worth failing the pass
    dbg = os.environ.get("OVN_QE_DEBUG_DIR")                    # evidence runs: keep every prompt and reply
    if dbg:
        try:
            os.makedirs(dbg, exist_ok=True)
            n = "%s_%d" % (time.strftime("%H%M%S"), stats["calls"])
            open(os.path.join(dbg, n + "_prompt.txt"), "w").write(messages[-1]["content"] if messages else "")
            open(os.path.join(dbg, n + "_reply.txt"), "w").write(text)
        except OSError:
            pass
    return text


def strip_think(text):
    text = re.sub(r"<think>.*?</think>", "", text or "", flags=re.S)
    if "</think>" in text:
        text = text.split("</think>", 1)[1]
    return text.strip()


def _repair_json(s):
    s = re.sub(r",\s*([}\]])", r"\1", s)
    s = s.replace("“", '"').replace("”", '"')
    return s


def extract_json(text):
    """First JSON object/array in a model reply (think blocks and code fences stripped, trailing commas repaired). None when there is none."""
    text = strip_think(text)
    text = re.sub(r"```(?:json)?", "", text)
    dec = json.JSONDecoder()
    for variant in (text, _repair_json(text)):
        for m in re.finditer(r"[{\[]", variant):
            try:
                obj, _ = dec.raw_decode(variant[m.start():])
            except ValueError:
                continue
            if isinstance(obj, (dict, list)):
                return obj
    return None


# ------------------------------------------------------------------------------------------------ gates: locks, ledger, self-throttle
class Lock:
    def __init__(self, path):
        self.path, self.fd = path, None

    def acquire(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return False
        self.fd = fd
        return True

    def release(self):
        if self.fd is not None:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None


def qdir():
    return os.path.join(OVN_DIR, "state", "qwen_explore")


LEDGER_ROOT = [None]      # a --dry-run with an explicit OVN_QE_CACHE_DIR keeps its lens / file ledger THERE (evidence runs rotate lenses and files without touching state/)


def ledger_path(repo):
    return os.path.join(LEDGER_ROOT[0] or qdir(), "ledger_%s.json" % repo)


def load_ledger(repo):
    L = read_json(ledger_path(repo), {})
    if not isinstance(L, dict):
        L = {}
    L.setdefault("lenses", {})
    L.setdefault("files", {})
    L.setdefault("day", "")
    L.setdefault("day_count", 0)
    L.setdefault("last_pass_ts", 0)
    L.setdefault("last_accepted", 0)
    L.setdefault("ffiles", {})                      # files already shown to the feature-ideation lens (separate from the bug lenses' file ledger)
    L.setdefault("feature_day", "")
    L.setdefault("feature_day_count", 0)
    return L


def today_str(t=None):
    return datetime.date.fromtimestamp(t or now_ts()).isoformat()


def next_midnight(t):
    d = datetime.date.fromtimestamp(t) + datetime.timedelta(days=1)
    return time.mktime(datetime.datetime(d.year, d.month, d.day).timetuple())


def write_next(repo, ts):
    """state/qwen_explore/next_<repo>: epoch before which the QUEUE HOOK must not even fork a process (the cheap gate in lib_fixup.sh ovn_qwen_explore_kick)."""
    atomic_write(os.path.join(qdir(), "next_%s" % repo), "%d\n" % int(ts))


def alert(level, repo, msg):
    try:
        with open(os.path.join(OVN_DIR, "state", "alerts.log"), "a") as f:
            f.write("[%s] %s | qwen-explore:%s | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), level, repo, msg))
    except OSError:
        pass


def outcome_stats(repo, now):
    """How the backlog items decomposed from this explorer's roadmap features fared: {consumed, landed, rate}. Attribution: accepted.jsonl slugs vs outcomes.jsonl feat_tag
    (<repo>-<YYYYMMDD>-<slug>); consumed = distinct item_hash with at least one non-skipped, non-error row; landed = one of its rows has class 'landed'."""
    slugs, csl = set(), set()
    for ln in read_text(os.path.join(qdir(), "accepted.jsonl")).split("\n"):
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        if r.get("repo") == repo and now - float(r.get("ts_epoch") or 0) < 21 * 86400 and r.get("slug"):
            slugs.add(r["slug"])
            if r.get("critic") == "approve":                                     # the critic approved this item (shadow or on)
                csl.add(r["slug"])
    out = {"consumed": 0, "landed": 0, "rate": None, "slugs": len(slugs), "critic_consumed": 0, "critic_landed": 0, "critic_rate": None}
    if not slugs:
        return out
    path = os.path.join(OVN_DIR, "state", "outcomes.jsonl")
    cap = int(_env_num("OVN_QE_OUTCOMES_TAIL_MB", 40, float) * 1024 * 1024)
    try:
        with open(path, "rb") as f:
            size = os.fstat(f.fileno()).st_size
            if size > cap:
                f.seek(size - cap)
                f.readline()
            data = f.read()
    except OSError:
        return out
    pat = re.compile(r"^%s-\d{8}-(.+)$" % re.escape(repo))
    seen, seen_slug = {}, {}
    for raw in data.split(b"\n"):                      # `grep -a` semantics: tolerate binary junk, skip anything that is not a JSON row
        if b'"feat_tag"' not in raw:
            continue
        try:
            r = json.loads(raw.decode("utf-8", "replace"))
        except ValueError:
            continue
        if r.get("repo") != repo:
            continue
        m = pat.match(str(r.get("feat_tag") or ""))
        if not m or m.group(1) not in slugs:
            continue
        cls = r.get("class") or ""
        if cls in ("skipped", "error", ""):
            continue
        h = r.get("item_hash") or "%s/%s" % (r.get("id"), r.get("ts"))
        seen[h] = seen.get(h, False) or cls == "landed"
        seen_slug[h] = m.group(1)
    out["consumed"] = len(seen)
    out["landed"] = sum(1 for v in seen.values() if v)
    out["rate"] = (out["landed"] / float(out["consumed"])) if seen else None
    cseen = [v for h, v in seen.items() if seen_slug.get(h) in csl]
    out["critic_consumed"] = len(cseen)
    out["critic_landed"] = sum(1 for v in cseen if v)
    out["critic_rate"] = (out["critic_landed"] / float(len(cseen))) if cseen else None
    return out


def throttle_check(repo, now, dry):
    """-> (paused: bool, info str). Enters/leaves the pause state in state/qwen_explore/paused_<repo>.json (writes only when not dry)."""
    pf = os.path.join(qdir(), "paused_%s.json" % repo)
    st = read_json(pf, None)
    s = outcome_stats(repo, now)
    bad_all = s["consumed"] >= THROTTLE_MIN_N and s["rate"] is not None and s["rate"] < THROTTLE_MIN_RATE
    bad_critic = s["critic_consumed"] >= THROTTLE_MIN_N and s["critic_rate"] is not None and s["critic_rate"] < THROTTLE_MIN_RATE   # critic approved, yet it did not land
    bad = bad_all or bad_critic
    if st:
        recovered = s["rate"] is not None and s["rate"] >= THROTTLE_MIN_RATE and not bad_critic
        if now >= float(st.get("until") or 0) or recovered:
            if not dry:
                try:
                    os.unlink(pf)
                except OSError:
                    pass
            return False, "resumed (%s)" % ("rate recovered" if recovered else "pause elapsed")
        return True, "paused until %s: %d/%d landed (%.0f%%)" % (time.strftime("%m-%d %H:%M", time.localtime(float(st.get("until") or 0))), s["landed"], s["consumed"], 100.0 * (s["rate"] or 0))
    if bad:
        if not dry:
            atomic_write(pf, json.dumps({"since": now, "until": now + THROTTLE_PAUSE_S, "consumed": s["consumed"], "landed": s["landed"], "rate": s["rate"],
                                         "critic_consumed": s["critic_consumed"], "critic_landed": s["critic_landed"], "critic_rate": s["critic_rate"]}))
            if bad_all:
                alert("warn", repo, "self-throttle PAUSED for %dh: only %d of %d consumed qwen-explore item(s) landed (%.0f%% < %.0f%%) - fix the proposal quality or raise OVN_QE_THROTTLE_MIN_RATE" % (
                    THROTTLE_PAUSE_S // 3600, s["landed"], s["consumed"], 100.0 * s["rate"], 100.0 * THROTTLE_MIN_RATE))
            else:
                alert("warn", repo, "self-throttle PAUSED for %dh: the critic approved but only %d of %d consumed critic-approved item(s) landed (%.0f%% < %.0f%%) - the critic is not predicting landings; tighten the rubric" % (
                    THROTTLE_PAUSE_S // 3600, s["critic_landed"], s["critic_consumed"], 100.0 * s["critic_rate"], 100.0 * THROTTLE_MIN_RATE))
        if bad_all:
            return True, "self-throttle: %d/%d landed (%.0f%%)" % (s["landed"], s["consumed"], 100.0 * s["rate"])
        return True, "self-throttle (critic-approved): %d/%d landed (%.0f%%)" % (s["critic_landed"], s["critic_consumed"], 100.0 * s["critic_rate"])
    return False, ""


def gpu_busy():
    """True when the GPU is saturated (mean of 3 samples >= OVN_QE_GPU_BUSY_PCT). No nvidia-smi / any error -> False."""
    exe = os.environ.get("OVN_QE_NVIDIA_SMI") or shutil.which("nvidia-smi")
    if not exe:
        return False
    vals = []
    for _ in range(3):
        try:
            r = subprocess.run([exe, "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=8)
            vals += [float(x) for x in r.stdout.split() if re.fullmatch(r"\d+(\.\d+)?", x)]
        except (OSError, subprocess.SubprocessError, ValueError):
            return False
        time.sleep(0.4)
    return bool(vals) and sum(vals) / len(vals) >= GPU_BUSY_PCT


# ------------------------------------------------------------------------------------------------ snapshot (read-only view of origin/overnight/feature)
def resolve_ref(clone):
    cands = [os.environ.get("OVN_QE_REF") or "origin/overnight/feature", "overnight/feature", "HEAD"]
    for ref in cands:
        r = git(clone, "rev-parse", "--verify", "-q", ref + "^{commit}")
        if r is not None and r.returncode == 0 and r.stdout.strip():
            return ref, r.stdout.strip()
    return None, None


def make_snapshot(repo, clone, ref, sha, cfg, cache_root):
    """Extract `git archive <sha>` once per sha into <cache_root>/snap/<repo>/<sha>. Never touches the clone's working tree or index."""
    base = os.path.join(cache_root, "snap", repo)
    snap = os.path.join(base, sha)
    if os.path.isfile(os.path.join(snap, ".qe_ok")):
        os.utime(snap, None)
        return snap
    os.makedirs(base, exist_ok=True)
    tmp = os.path.join(base, ".tmp-%s-%d" % (sha[:8], os.getpid()))
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    try:
        ga = subprocess.Popen(["git", "-C", clone, "archive", "--format=tar", sha], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        excl = []
        for e in cfg.get("snap_exclude") or ():
            excl += ["--exclude=./%s" % e, "--exclude=%s" % e]
        tr = subprocess.run(["tar", "-x", "-C", tmp] + excl, stdin=ga.stdout, capture_output=True, timeout=300)
        ga.stdout.close()
        ga.wait(timeout=60)
        if ga.returncode != 0 or tr.returncode != 0:
            raise RuntimeError("git archive/tar failed (%s/%s)" % (ga.returncode, tr.returncode))
        open(os.path.join(tmp, ".qe_ok"), "w").write(sha)
        shutil.rmtree(snap, ignore_errors=True)
        os.replace(tmp, snap)
    except Exception:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    try:                                              # keep the two newest snapshots of this repo
        olds = sorted((os.path.join(base, d) for d in os.listdir(base) if not d.startswith(".tmp-")), key=os.path.getmtime, reverse=True)
        for d in olds[2:]:
            shutil.rmtree(d, ignore_errors=True)
    except OSError:
        pass
    return snap


def snapshot_files(snap):
    out = []
    for dp, dns, fns in os.walk(snap):
        dns[:] = [d for d in dns if d not in (".git", ".godot", "node_modules", "__pycache__")]
        for fn in fns:
            if fn == ".qe_ok":
                continue
            out.append(os.path.relpath(os.path.join(dp, fn), snap).replace(os.sep, "/"))
    return sorted(out)


def refresh_work(repo, snap, clone, cfg, cache_root):
    """The scratch copy the red-before check runs in (tracked files from the snapshot; .godot / node_modules / .venv are kept between passes)."""
    work = os.path.join(cache_root, "work", repo)
    os.makedirs(work, exist_ok=True)
    keep = (".godot", "node_modules", ".venv")
    if shutil.which("rsync"):
        cmd = ["rsync", "-a", "--delete"] + ["--exclude=" + k for k in keep] + [snap.rstrip("/") + "/", work + "/"]
        r = subprocess.run(cmd, capture_output=True, timeout=300)
        if r.returncode != 0:
            raise RuntimeError("rsync failed: %s" % r.stderr.decode("utf-8", "replace")[:120])
    else:
        for name in os.listdir(work):
            if name not in keep:
                p = os.path.join(work, name)
                shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
        for name in os.listdir(snap):
            s, d = os.path.join(snap, name), os.path.join(work, name)
            if os.path.isdir(s):
                shutil.copytree(s, d, dirs_exist_ok=True, symlinks=True)
            else:
                shutil.copy2(s, d)
    warm_godot(work)
    # a web package's node_modules: hard-linked copy (new files stay in the scratch copy; the clone's tree is never written)
    for pkg in cfg.get("node_modules") or ():
        src, dst = os.path.join(clone, pkg, "node_modules"), os.path.join(work, pkg, "node_modules")
        if os.path.isdir(src) and not os.path.exists(dst) and os.path.isdir(os.path.join(work, pkg)):
            subprocess.run(["cp", "-al", src, dst], capture_output=True, timeout=300)
    return work


def warm_godot(work):
    """A Godot project's first headless run imports every asset (minutes) - longer than a GUT VERIFY's timeout. Import once into the scratch copy's .godot (kept between passes).
    Best effort: no godot binary / no project.godot / any failure is silent."""
    if not os.path.isfile(os.path.join(work, "project.godot")) or os.path.isdir(os.path.join(work, ".godot", "imported")):
        return
    exe = os.environ.get("OVN_QE_GODOT") or next((p for p in (os.path.expanduser("~/godot/godot4"), shutil.which("godot4") or "", shutil.which("godot") or "") if p and os.path.isfile(p)), None)
    if not exe:
        return
    try:
        subprocess.run([exe, "--headless", "--path", work, "--import"], capture_output=True, timeout=_env_num("OVN_QE_GODOT_IMPORT_S", 420), stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass


# ------------------------------------------------------------------------------------------------ scope
def compile_all(pats):
    out = []
    for p in pats or ():
        try:
            out.append(re.compile(p))
        except re.error:
            pass
    return out


def load_banned(snap):
    out = []
    for raw in read_text(os.path.join(snap, ".queue-hard-banned-files")).split("\n"):
        p = raw.strip()
        if p and not p.startswith("#"):
            try:
                out.append(re.compile(p))
            except re.error:
                pass
    return out


class Scope:
    def __init__(self, cfg, snap):
        self.cfg = cfg
        self.exclude = compile_all(GENERIC_EXCLUDE + tuple(cfg.get("exclude") or ()))
        self.protected = compile_all(PROTECTED_FILES)
        self.banned = load_banned(snap)
        self.oos = compile_all(cfg.get("out_of_scope"))
        self.roots = cfg.get("roots")

    def in_roots(self, path):
        if not self.roots:
            return True
        return any(path == r or path.startswith(r) for r in self.roots)

    def forbidden(self, path):
        """Why `path` may not be touched by an item, or ''."""
        if path.startswith("addons/") or "/addons/" in path:
            return "vendored"
        if any(p.search(path) for p in self.banned):
            return "banned"
        if any(p.search(path) for p in self.exclude):
            return "out-of-scope"
        if any(p.search(path) for p in self.protected):
            return "protected"
        return ""

    def text_violation(self, text):
        """A banned / vendored / out-of-scope path NAMED anywhere in an item's prose or VERIFY."""
        for p in paths_in(text):
            why = self.forbidden(p)
            if why:
                return "%s:%s" % (why, p)
        for rx in self.oos:
            if rx.search(text or ""):
                return "out-of-scope:%s" % rx.pattern[:40]
        return ""


def is_test_path(p):
    return bool(re.search(r"(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]*$|\.(test|spec)\.", p))


# ------------------------------------------------------------------------------------------------ lenses + candidate files
def applicable_lenses(cfg, feature=False):
    out = []
    for name, (_, _, exts, kinds) in LENSES.items():
        if name == FEATURE_LENS and not feature:
            continue
        if kinds is not None and not (kinds & set(cfg.get("kinds") or ())):
            continue
        out.append(name)
    return out


def lens_ttl(name):
    return QF.lens_ttl_s() if name == FEATURE_LENS else LENS_TTL_S


def pick_lens(cfg, L, now, forced=None, feature=False, only_feature=False):
    """-> (lens, wait_until). Least-recently-used applicable lens whose TTL has passed; wait_until = earliest expiry when none is available. `feature` makes the feature-ideation lens eligible (a starving repo; it is
    then preferred whenever its own TTL has passed: the bug lenses have no evidence left); `only_feature` = the bug-lens daily cap is spent, only the feature lens may run."""
    names = applicable_lenses(cfg, feature=feature)
    if forced:
        return (forced, 0) if forced in names else (None, 0)
    if only_feature:
        names = [n for n in names if n == FEATURE_LENS]
        if not names:
            return None, 0
    ready = [(L["lenses"].get(n, 0), i, n) for i, n in enumerate(names) if now - L["lenses"].get(n, 0) >= lens_ttl(n)]
    if ready:
        if any(n == FEATURE_LENS for _, _, n in ready):
            return FEATURE_LENS, 0
        ready.sort()
        return ready[0][2], 0
    return None, min(L["lenses"].get(n, 0) + lens_ttl(n) for n in names)


def churn_counts(clone, sha):
    r = git(clone, "log", "--since=120.days", "--name-only", "--pretty=format:", sha, timeout=60)
    cnt = {}
    if r is not None and r.returncode == 0:
        for ln in r.stdout.split("\n"):
            ln = ln.strip()
            if ln:
                cnt[ln] = cnt.get(ln, 0) + 1
    return cnt


def test_reference_counts(snap, files, prod_paths):
    """{prod path: number of test files that mention its module stem / class_name} - the test-gaps lens shows it and sorts the untested files first."""
    tests = [read_text(os.path.join(snap, p)) for p in files if is_test_path(p) and p.endswith(SRC_EXTS)]
    out = {}
    for p in prod_paths:
        stem = os.path.splitext(os.path.basename(p))[0]
        names = {stem}
        m = re.search(r"^class_name (\w+)", read_text(os.path.join(snap, p)), re.M)
        if m:
            names.add(m.group(1))
        out[p] = sum(1 for t in tests if any(n and n in t for n in names))
    return out


def candidate_files(snap, files, scope, lens, L, churn, now, landable=False, relax=0):
    """[(path, lines, churn, covered_ts, tests_mentioning_it | None)] for the lens: in-scope production files (docs-drift: docs), not recently covered, files that fit the view budget first, then
    churn (test-gaps: the files no test mentions first)."""
    exts = (LENSES[lens][2] or SRC_EXTS) if relax < 2 else SRC_EXTS      # relax 1: the repo's top-level modules too (roots dropped); relax 2: and the lens extension filter dropped (small repos: <2 files for the lens)
    out = []
    for p in files:
        if not p.endswith(exts) or scope.forbidden(p) or not scope.in_roots(p) and lens != "docs-drift" and not relax:
            continue
        if lens == "docs-drift":
            if not (p.startswith("docs/") or p.count("/") == 0 and p.lower().startswith("readme")):
                continue
        elif is_test_path(p):
            continue                                  # targets are production files (a test-gaps item ADDS a test for one)
        try:
            txt = read_text(os.path.join(snap, p))
        except OSError:
            continue
        n = txt.count("\n") + 1
        if n < 6:
            continue
        out.append((p, n, churn.get(p, 0), L["files"].get(p, 0)))
    fresh = [c for c in out if now - c[3] >= FILE_TTL_S]
    pool = fresh if len(fresh) >= MIN_FRESH_FILES else sorted(out, key=lambda c: c[3])[:max(len(fresh), 60)]   # everything covered recently: oldest-covered first
    pool.sort(key=lambda c: (c[1] > FULL_VIEW_LINES, -c[2], -c[1], c[0]))      # files that fit the budget (shown WHOLE) first: a model reading the first 300 lines of a 1100-line file finds nothing
    if lens == "test-gaps":
        refs = test_reference_counts(snap, files, [c[0] for c in pool])
        pool = [c + (refs.get(c[0], 0),) for c in pool]
        if landable:
            pure = {c[0] for c in pool if is_pure_gd(read_text(os.path.join(snap, c[0])))}
            pool.sort(key=lambda c: (c[0] not in pure, c[4], c[1] > FULL_VIEW_LINES, -c[2], c[0]))
            return [c + ((c[0] in pure),) for c in pool[:260]]
        pool.sort(key=lambda c: (c[4], c[1] > FULL_VIEW_LINES, -c[2], c[0]))   # untested files first
        return pool[:260]
    refs = test_reference_counts(snap, files, [c[0] for c in pool])
    pool = [c + (None,) for c in pool]
    if landable and lens != "docs-drift":
        pure = {c[0] for c in pool if is_pure_gd(read_text(os.path.join(snap, c[0])))}
        pool.sort(key=lambda c: (c[0] not in pure, c[1] > FULL_VIEW_LINES, min(refs.get(c[0], 0), 3), -c[2], c[0]))   # xlite: files a 27B can actually land a fix in come first
        return [c[:5] + ((c[0] in pure),) for c in pool[:260]]
    pool.sort(key=lambda c: (c[1] > FULL_VIEW_LINES, min(refs.get(c[0], 0), 3), -c[2], c[0]))      # a file nobody tests is likelier to hold a bug than one the fleet has already hardened (xlite: 12 empty passes over heavily-tested files)
    return pool[:260]


def select_files_prompt(repo, lens, cands, recent, feature=None):
    desc, guide = LENSES[lens][0], LENSES[lens][1]
    tree = "\n".join("%s | %d lines | %d commits/120d%s%s" % (c[0], c[1], c[2], (" | %d test file(s) mention it" % c[4]) if c[4] is not None else "", " | pure logic" if len(c) > 5 and c[5] else "") for c in cands)
    if feature:
        return QF.feature_select_prompt(repo, feature[0], feature[1], tree, recent, MAX_TARGET_FILES, FULL_VIEW_LINES)
    rec = ", ".join(recent[:40]) or "(none)"
    return ("You are the research planner of an autonomous coding fleet working on the repo %s. Pick the files most likely to contain REAL, concrete defects for ONE research lens.\n\n"
            "LENS: %s - %s\n\nRULES: choose at most %d paths, copied EXACTLY from the FILES list below. Prefer files with non-trivial logic and recent churn; skip files that look trivial. Only the first ~300 lines of a file longer than %d lines can be shown to the reviewer, so prefer files of at most %d lines.\n\n"
            "FILES (path | size | git churn):\n%s\n\nRECENTLY COVERED (do not pick): %s\n\nReply with ONLY this JSON and nothing else: {\"files\": [\"path1\", \"path2\"]}") % (repo, lens, desc + ". " + guide, MAX_TARGET_FILES, FULL_VIEW_LINES, FULL_VIEW_LINES, tree, rec)


def parse_file_pick(reply, cand_paths):
    obj = extract_json(reply)
    raw = []
    if isinstance(obj, dict) and isinstance(obj.get("files"), list):
        raw = [str(x) for x in obj["files"]]
    elif isinstance(obj, list):
        raw = [str(x) for x in obj]
    else:
        raw = PATHISH.findall(strip_think(reply))
    out = []
    for p in raw:
        p = p.strip().strip("`'\" ")
        if p.startswith("./"):
            p = p[2:]
        if p in cand_paths and p not in out:
            out.append(p)
    return out[:MAX_TARGET_FILES]


# ------------------------------------------------------------------------------------------------ corpus (duplicate / already-done avoidance)
def corpus_lines(repo, clone, sha, roadmap_text):
    """Every roadmap / backlog / progress / done line the new item must not duplicate. Repo files are read at the snapshot sha (git show), never from the working tree."""
    texts = [roadmap_text, read_text(os.path.join(OVN_DIR, "backlog", repo + ".md"))]
    for fn in ("OVERNIGHT_PROGRESS.md", "OVERNIGHT_DONE.md"):
        r = git(clone, "show", "%s:%s" % (sha, fn))
        if r is not None and r.returncode == 0:
            texts.append(r.stdout)
    lines = []
    for t in texts:
        for ln in t.split("\n"):
            if re.match(r"^\s*- \[[ xX]\]", ln):
                lines.append(ln)
    return lines


def parked_lines(clone, sha, corpus):
    """Lines that say the 27B could not land this and it is routed to Claude (AUTO-SKIP / `route to CLAUDE` / `[CLAUDE]` in the roadmap, backlog, progress and done files) plus every open line of CLAUDE_QUEUE.md.
    A new item that repeats one of them is the same unlandable work under another title."""
    out = [ln for ln in corpus if PARKED_RE.search(ln)]
    r = git(clone, "show", "%s:CLAUDE_QUEUE.md" % sha)
    if r is not None and r.returncode == 0:
        out += [ln for ln in r.stdout.split("\n") if re.match(r"^\s*- \[ \]", ln)]
    return out


def parked_reason(it, parked):
    """'parked-for-claude' when a parked line names this file AND (this symbol, or a topic overlapping the item's title + claim)."""
    f, base = it["file"], os.path.basename(it["file"])
    bag = words(it["title"] + " " + it["wrong"])
    for ln in parked:
        if f not in ln and base not in ln:
            continue
        if has_word(it["sym"], ln):
            return "parked-for-claude"
        lw = words(ln)
        if bag and lw and len(bag & lw) / float(len(bag | lw)) >= 0.2:
            return "parked-for-claude"
    return ""


def landable_reason(it, text, lens):
    """xlite: only items a 27B can land. '' or a reject reason. S only; no second production file (wiring work is exactly what the fleet parks as `route to CLAUDE`); the target is GDScript-pure
    (a node or scene script needs a running scene to test)."""
    if lens == "docs-drift":
        return ""
    if it["size"] != "S":
        return "not-landable-size"
    others = {p for p in paths_in(it["change"] + " " + it["title"] + " " + it["wrong"]) if p != it["file"] and not is_test_path(p)}
    if others:
        return "not-landable-wiring"
    if it["file"].endswith(".gd") and not is_pure_gd(text):
        return "not-landable-node-bound"
    return ""


def recent_subjects(clone, sha, n=80):
    r = git(clone, "log", "-n", str(n), "--format=%s", sha)
    return [x for x in (r.stdout.split("\n") if r is not None and r.returncode == 0 else []) if x.strip()]


def has_word(sym, text):
    return bool(sym) and re.search(r"(?<![\w])%s(?![\w])" % re.escape(sym), text or "") is not None


def duplicate_reason(it, corpus, subjects, accepted_claims, topical_open=False):
    """'' or a reason. Same normalised title (roadmap `[ready] <title> - ...` or backlog `[T2] <path> - <description>`); same file AND symbol named on any line (open or done);
    heavy word overlap on a line naming the same file; a recent commit about it; the same (file, symbol, quote) proposed before."""
    key, tw, f, sym = norm_title(it["title"]), words(it["title"]), it["file"], it["sym"]
    item_bag = words(" ".join([it["title"], it["wrong"], it["change"]]))
    for ln in corpus:
        t = re.sub(r"\[feat:[^\]]*\]", "", ln)
        m = re.match(r"^\s*- \[[ xX]\] (?:\[[^\]]*\] )*(.{0,200}?)(?: \u2014 (.*))?$", t)
        if m:
            if norm_title(m.group(1)) == key:
                return "duplicate-title"
            desc = re.split(r"\sVERIFY:", m.group(2) or "")[0][:120]
            dw = words(desc)
            if dw and tw and len(tw & dw) / float(len(tw | dw)) >= 0.6:
                return "duplicate-title"
        if f in t:
            if has_word(sym, t):
                if not re.match(r"^\s*- \[[xX]\]", t):
                    if topical_open:                        # feature lens: the symbol is only the insertion point (often a hot spot with open lines about other concerns): an open line counts only when its topic is the item's
                        lw = words(re.split(r"\sVERIFY:", re.split(r"\s\u2014\s", t, maxsplit=1)[-1])[0])
                        if lw and len(lw & item_bag) / float(len(lw)) >= 0.5:
                            return "already-covered"
                        continue
                    return "already-covered"                # an OPEN line (roadmap / backlog / progress, parked ones included) already targets this file + symbol
                lw = words(re.split(r"\sVERIFY:", re.split(r"\s\u2014\s", t, maxsplit=1)[-1])[0])
                if lw and len(lw & item_bag) / float(len(lw)) >= 0.5:
                    return "already-covered"                # a DONE line about the same file + symbol whose topic the item repeats (a different defect in a worked symbol is allowed)
                continue
            lw = words(t)
            if tw and len(tw & lw) / float(len(tw | lw) or 1) >= 0.45:
                return "near-duplicate"
    for s in subjects:
        if has_word(sym, s) and (os.path.basename(f) in s or len(tw & words(s)) >= 2):
            return "recently-committed"
    sig = hashlib.sha1(("%s|%s|%s" % (f, sym, norm_ws(it["quote"])[:160])).encode()).hexdigest()[:16]
    if sig in accepted_claims:
        return "already-proposed"
    return ""


def accepted_claim_sigs(repo, now):
    out = set()
    for ln in read_text(os.path.join(qdir(), "accepted.jsonl")).split("\n"):
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        if r.get("repo") == repo and now - float(r.get("ts_epoch") or 0) < 30 * 86400 and r.get("sig"):
            out.add(r["sig"])
    return out


# ------------------------------------------------------------------------------------------------ pass B prompt
def load_budgeted(snap, paths, budget_chars):
    """[(path, shown_text, total_lines, truncated)] - water-filling: short files whole, the budget split over the long ones; a long file is cut at a line boundary."""
    docs = []
    for p in paths:
        t = read_text(os.path.join(snap, p))
        docs.append([p, t, t.count("\n") + 1])
    left, remaining = budget_chars, sorted(range(len(docs)), key=lambda i: len(docs[i][1]))
    shown = {}
    while remaining:
        share = left // len(remaining)
        i = remaining.pop(0)
        t = docs[i][1]
        if len(t) <= share:
            shown[i] = (t, False)
            left -= len(t)
        else:
            cut = t[:max(share, 400)]
            cut = cut[:cut.rfind("\n")] if "\n" in cut else cut
            shown[i] = (cut, True)
            left -= len(cut)
    return [(docs[i][0], shown[i][0], docs[i][2], shown[i][1]) for i in range(len(docs))]


def agents_excerpt(snap):
    t = read_text(os.path.join(snap, "AGENTS.md"))
    return t[:6500] + ("\n[... AGENTS.md truncated ...]" if len(t) > 6500 else "") if t else "(no AGENTS.md)"


def readable_title(ln):
    """OPEN/DONE flag + a short human title for a roadmap line (`[P3] [ready] <title> - ...`) or a backlog / done line (`[T2] <path> - <description> VERIFY: ...`, annotations dropped)."""
    t = re.sub(r"\[feat:[^\]]*\]", "", ln)
    m = re.match(r"^\s*- \[([ xX])\] (.*)$", t)
    if not m:
        return None
    flag, rest = ("OPEN" if m.group(1) == " " else "DONE"), m.group(2)
    rest = re.sub(r"^(?:\[[^\]]*\]\s*|\([^)]*\)\s*)+", "", rest)
    parts = re.split(r"\s\u2014\s", rest, maxsplit=1)
    if len(parts) == 2 and re.search(r"\.\w+$", parts[0].strip("` ")):          # `<path> - <description>`: keep both, the path says WHERE
        desc = re.split(r"\sVERIFY:", parts[1])[0]
        rest = "%s: %s" % (parts[0].strip("` "), desc)
    else:
        rest = parts[0]
    return flag, norm_ws(rest)[:110]


def existing_titles(corpus, cap=70):
    out, seen = [], set()
    for ln in reversed(corpus):
        r = readable_title(ln)
        if r and norm_title(r[1]) not in seen:
            seen.add(norm_title(r[1]))
            out.append("%s %s" % r)
        if len(out) >= cap:
            break
    return out


def build_item_prompt(repo, lens, cfg, snap, docs, corpus, subjects, scope=None):
    desc, guide = LENSES[lens][0], LENSES[lens][1]
    hint = (cfg.get("hints") or {}).get(lens)
    if hint:
        guide += " Concrete patterns in THIS codebase worth checking first: " + hint
    files = "\n".join("=== FILE %s (%d lines)%s ===\n%s\n=== END %s ===" % (p, n, " [showing only the first part]" if tr else "", txt, p) for p, txt, n, tr in docs)
    titles = "\n".join("- " + t for t in existing_titles(corpus))
    subj = "\n".join("- " + s[:100] for s in subjects[:30])
    dialect = cfg.get("dialect") or GENERIC_DIALECT
    off = ", ".join(sorted({p.pattern for p in scope.banned})[:24]) if scope is not None and scope.banned else ""
    land_note = LANDABLE_NOTE if (cfg.get("landable") and LANDABLE != "off") else ""
    off_note = land_note + (("OFF-LIMITS (hard-banned paths: never target, name or add tests for them): %s\n\n" % off) if off else "")
    return ("You are a senior reviewer finding REAL defects for an autonomous coding fleet (a local 27B model implements one item at a time, each gated by the repo's tests). REPO: %s.\n"
            "LENS: %s - %s\n\n"
            "REPO RULES (AGENTS.md):\n%s\n\n%s"
            "FILES TO REVIEW (the ONLY code you may cite):\n%s\n\n"
            "ALREADY ON THE ROADMAP / BACKLOG / DONE (do not duplicate, do not redo):\n%s\n\nRECENT COMMITS:\n%s\n\n"
            "TASK: return up to %d items. Go through the shown files function by function, write down every candidate the LENS describes, then keep the %d most solid ones that satisfy the rules below. "
            "A second reviewer audits every item you return and refutes the weak ones, and a wrong item costs a coder cycle and a revert, so prefer a few solid items to many marginal ones; "
            "return {\"items\": []} only after you have checked every function and found nothing that holds. "
            "Report a defect only when the shown code ALONE proves it. Rules:\n"
            "  1. One item = ONE behavioural defect that gives a caller or user a wrong result, a crash, lost data or a security hole. NOT: style, naming, deprecation swaps, speculative optimisation of code that runs on small or bounded inputs, 'defensive' checks for values the signature or callers never pass.\n"
            "  2. The quoted lines must sit INSIDE the function or class named in `symbol`.\n"
            "  3. Do not claim a test is missing, or that a write is not atomic, unless the shown code proves it. Do not repeat the same defect for several functions: one item per distinct defect.\n"
            "  4. Never change a convention (timezone awareness, column or return types, serialisation, encoding) unless you also name the OTHER file (model, column, caller) that must change with it. No new unique constraints, indexes, columns or migrations.\n"
            "  5. An item concerns ONLY the shown files and at most one test file. Never mention or ask to edit AGENTS.md, roadmap or backlog files, the queue's own scripts, CI, ban lists or gates. Do not cite roadmap or AGENTS rules as authority: justify with the code.\n"
            "  6. If the quoted code is actually safe, fine or already correct, leave the item out.\n"
            "  7. The shown code must prove the claim. Do NOT assert how a third-party API, SDK, library or engine behaves (response fields, parameter names, defaults, return values) unless the shown code itself shows it: "
            "your memory of an outside API is a guess (a real run claimed a YouTube field lives in a different `part`; it is in `snippet`).\n"
            "Never invent a path, function or line: every item is checked mechanically and dropped when the file, the symbol or the quoted lines do not exist or are not in that symbol.\n"
            "Each item has EXACTLY these keys:\n"
            "  title            imperative, under 100 chars, no em dash\n"
            "  file             exact path of one shown FILE\n"
            "  symbol           the function / class / variable / node name that contains the defect, exactly as written in the file\n"
            "  evidence_quote   1-4 consecutive lines copied VERBATIM from that file (no line numbers, no ellipsis, no markers)\n"
            "  what_is_wrong    1-2 sentences: the concrete failure a user or caller sees, stated as a FACT about the quoted code (never 'may', 'might', 'could', 'potentially': if you are not sure the quoted code is wrong, leave the item out)\n"
            "  proposed_change  1-3 sentences: the minimal change (name the caller/test that must change with it; no new helper nothing calls)\n"
            "  verify           ONE single-line command that FAILS on the code as it is now because of THIS defect and passes once it is fixed, from this closed list (no python -c, no pipes, no chaining, no redirects except 2>/dev/null). Prefer a test that exercises the behaviour, and the test file MUST be a NEW path that does not exist yet (say 'Add <path>' in proposed_change): an existing test file already passes, which makes the VERIFY worthless.\n%s\n"
            "  size             \"S\" (one function) or \"M\" (two or three small edits); never larger\n"
            "  tier             1 (trivial, local) | 2 (normal) | 3 (needs care)\n"
            "Reply with ONLY this JSON object: {\"review\": [\"<function>: ok\" or \"<function>: suspect - <why>\", ... one short line per function in the shown files], \"items\": [ {...}, ... ]}. "
            "Fill `review` FIRST (it is your scratch work: every function gets a line), then `items` from the suspects that survive the rules.") % (repo, lens, desc + ". " + guide, agents_excerpt(snap), off_note, files, titles or "(none)", subj or "(none)", MAX_ITEMS, MAX_ITEMS, dialect)


def build_feature_item_prompt(repo, cfg, snap, docs, corpus, subjects, scope, vision, outline, seen, max_items):
    files = "SHOWN FILES (anchor ONLY in these): %s\n" % ", ".join(d[0] for d in docs) + "\n".join("=== FILE %s (%d lines)%s ===\n%s\n=== END %s ===" % (p, n, " [showing only the first part]" if tr else "", txt, p) for p, txt, n, tr in docs)
    off = ", ".join(sorted({p.pattern for p in scope.banned})[:24]) if scope is not None and scope.banned else ""
    land_note = LANDABLE_NOTE if (cfg.get("landable") and LANDABLE != "off") else ""
    off_note = land_note + (("OFF-LIMITS (hard-banned paths: never target, name or add tests for them): %s\n\n" % off) if off else "")
    titles = "\n".join("- " + t for t in existing_titles(corpus))
    seen_titles = "\n".join("- " + r["title"][:110] for r in seen[-30:])
    return QF.build_feature_prompt(repo, agents_excerpt(snap), vision, outline, off_note, files, titles, seen_titles, subjects, cfg.get("dialect") or GENERIC_DIALECT, max_items, landable=bool(land_note), shapes=QF.shapes_for(cfg.get("kinds")))


def parse_items_feature(reply):
    """parse_items + salvage: a feature reply cut off mid-item (token limit) or whose first decodable JSON is not the item list still yields its complete items."""
    items = parse_items(reply)
    if items:
        return items
    salv = QF.salvage_items(strip_think(reply))
    return salv or items


def parse_items(reply):
    obj = extract_json(reply)
    if isinstance(obj, dict):
        obj = obj.get("items", obj.get("results"))
    if not isinstance(obj, list):
        return None
    return [x for x in obj if isinstance(x, dict)]


# ------------------------------------------------------------------------------------------------ mechanical verification
def category_of(path):
    if is_test_path(path):
        return "test"
    return {".py": "python", ".ts": "typescript", ".tsx": "typescript", ".js": "typescript", ".vue": "vue", ".gd": "godot", ".md": "docs"}.get(os.path.splitext(path)[1], "refactor")


def backend_cat(path):
    return "endpoint" if re.search(r"(^|/)routers?/", path) and path.endswith(".py") else category_of(path)


HEDGE_RE = re.compile(r"\b(?:may|might|could|would|potentially|possibly|perhaps|probably|presumably|likely|conceivably|arguably|seems?|appears?\s+to|in\s+theory|in\s+principle)\b", re.I)


CLAIM_TAIL_RE = re.compile(r",?\s+(?:and\s+)?(?:potentially|possibly)\s+\w+ing\b")


def claim_clause(wrong):
    """The first sentence of what_is_wrong WHOLE (hedges after ';', ', so', ', which', 'allowing' are guesses about the claim too - reviewer 3), except a trailing impact phrase ', potentially <verb>ing ...'
    that only says how bad a stated fact is."""
    t = re.sub(r"\b(?:e\.g|i\.e|etc|vs|cf|approx|incl|resp|viz|al)\.", lambda m: m.group(0).replace(".", "\x00"), wrong)         # an abbreviation's full stop does not end the sentence ("e.g. a stolen cookie may ...")
    first = re.split(r"(?<=[.!?])\s", t, maxsplit=1)[0].replace("\x00", ".")
    return CLAIM_TAIL_RE.split(first, maxsplit=1)[0]


SYMBOL_RE = re.compile(r"^[A-Za-z_]\w*(?:(?:\.|::|#)[A-Za-z_]\w*)*$")
DOC_SYMBOL_RE = re.compile(r"^\w[\w .,:/#()'-]{0,70}$")
SYMBOL_PREFIX_RE = re.compile(r"^(?:(?:async|static|public|private|export)\s+)*(?:def|func|class|function|const|var)\s+")
SYMBOL_ARGS_RE = re.compile(r"\(\s*[\w\s,:=.\[\]*&?|<>'\"-]*\)\s*(?:->\s*[\w.\[\]]+)?$")
INJECT_EXTRA = re.compile(r"\b(?:ignore|disregard|forget|override|bypass)\b[^\n]{0,20}\b(?:(?:previous|prior|above|earlier|system|your|my|safety|fleet|queue|repo(?:sitory)?|agents?)\s+(?:instructions?|rules?|prompts?|polic(?:y|ies)|guidelines?|safeguards?)|instructions?|prompts?|safeguards?)\b|"
                          r"\bas an? (?:ai|assistant|language model)\b|\bnew instructions?\b|"
                          r"\b(?:assistant|planner|coder|agent|llm|qwen|claude|model)\b[^\n]{0,15}\b(?:must|should|shall|please|now)\b[^\n]{0,30}\b(?:delete|remove|disable|ignore|skip|overwrite|push|execute)\b|"
                          r"\b(?:delete|remove|disable|overwrite)\b[^\n]{0,30}\.queue-hard-banned", re.I)


def clean_symbol(sym, lens=None):
    """-> the symbol as a plain identifier / dotted path (a `def ` / `func ` prefix and a trailing `(args)` are dropped), or None. The symbol goes verbatim into the roadmap line and from there into the planner
    prompt: a free-text symbol is a prompt-injection channel (reviewer 2), so anything that is not an identifier path (docs-drift: a short heading) is refused."""
    t = SYMBOL_PREFIX_RE.sub("", str(sym or "").replace("`", "").strip())          # backticks: a code span in a doc heading would nest inside the roadmap line's own `symbol` span
    t = SYMBOL_ARGS_RE.sub("", t).strip()
    ok = SYMBOL_RE.match(t) or (lens == "docs-drift" and DOC_SYMBOL_RE.match(t) and not re.search(r"\s{2,}", t))
    if not ok or len(t) > 80:
        return None
    return t


HOME_RE = re.compile(r"(?:^|[\s`'\"(=:])~/|\$HOME\b|/home/\w|/Users/\w|/root\b|\.ssh\b|\bid_(?:rsa|ed25519|ecdsa)|\.netrc|\.aws\b|\.pem\b|\bgit\s+(?:push|reset|checkout|clean|remote|config)\b|--force\b|force[- ]push|\bforce[- ]with[- ]lease", re.I)
SECRET_VERB_RE = re.compile(r"\b(?:exfiltrat\w*|print|echo|dump|cat|upload|copy|curl)\b[^.\n]{0,40}\b(?:secrets?|passwords?|api[ _-]?keys?|credentials?|private keys?|tokens?)\b", re.I)
INJECT_LABEL_RE = re.compile(r"(?:^|[\s(])(?:system|assistant)\s*:|<\|im_(?:start|end)\|>|\[/?INST\]|<<SYS>>|\b(?:assistant|planner|coder|agent|model)\s+must\b|\b(?:rm\s+-rf|sudo\s+(?:-\w+\s+)*(?:rm|chmod|chown|cp|mv|tee|bash|sh|apt|pip|systemctl|curl|wget|kill|dd)\b|chmod\s+[0-7]{3,4}|curl\s+\S+\s*\|\s*(?:ba)?sh|\|\s*(?:ba)?sh\b)", re.I)


PROSE_URL_RE = re.compile(r"https?://|ftp://|\bwww\.|\bdata:[a-z]+/|\]\(|<!--|-->|%[0-9a-fA-F]{2}", re.I)
PROSE_B64_RE = re.compile(r"(?=[A-Za-z0-9+/=]*[A-Z])(?=[A-Za-z0-9+/=]*[a-z])(?=[A-Za-z0-9+/=]*[0-9+=])[A-Za-z0-9+/=]{24,}")
PROSE_PHRASE_RE = re.compile(r"\byour\s+new\s+(?:task|instructions?|role)\b|\bfrom\s+now\s+on\b|\binstead\s+of\s+the\s+above\b|\bforget\s+(?:everything|all|what)\b|\bdisregard\w*\b|\boverride\s*:|\bnew\s+task\s*[:-]|\bignore\s+(?:the\s+)?(?:above|everything|all\s+(?:of\s+)?(?:that|this|the))\b|\bstop\s*[.:]\s*(?:instead|now)\b|\bact\s+as\b|\bpretend\s+(?:to|you)\b|\b(?:ignora|ignorar|ignorez|ignoriere|instrucciones|anweisungen|instrucoes)\b|\binstructions\s+pr[eé]c[eé]dentes\b", re.I)


def prose_denied(text):
    """Model prose (title, claim, change) goes verbatim into the planner prompt: only printable ASCII, no URL / markdown-link / HTML-comment / percent-encoding / base64-looking blob, and no
    'new task' style phrases (reviewer 4: homoglyph, encoded and non-English payloads cannot be enumerated by a blocklist, so the CHARSET is closed instead)."""
    t = str(text or "")
    return any(ord(ch) > 126 or ord(ch) < 32 for ch in t) or bool(PROSE_URL_RE.search(t) or PROSE_B64_RE.search(t) or PROSE_PHRASE_RE.search(t))


def comment_tails(code):
    """The comment text of each line of a code quote (# ..., // ..., /* ... */, <!-- ... -->): instruction labels are only a signal there (`system: str` is a type hint, `# system: delete x` is not)."""
    out = []
    for ln in str(code or "").split("\n"):
        m = re.search(r"(?:#|//|/\*|<!--)(.*)$", ln)
        if m:
            out.append(m.group(1))
    return "\n".join(out)


def steering(s, code=False):
    """True when text that will be pasted into the roadmap line / planner prompt names a protected file, a home path, a secret or git push, or tries to instruct the model. `s` is NFKC-cleaned first.
    code=True (an evidence quote): the instruction LABELS (`system:` ...) are only checked in comment text."""
    t = clean_text(s)
    if PROTECTED_PROSE.search(t) or INJECT_EXTRA.search(t) or HOME_RE.search(t) or SECRET_VERB_RE.search(t):
        return True
    return bool(INJECT_LABEL_RE.search(comment_tails(t) if code else t))


def normalise_item(raw, lens=None):
    """-> (item dict | None, reason). Field presence / types / size / tier only; nothing here trusts the content."""
    try:
        title = one_line(raw.get("title"), 110)
        file_ = clean_text(raw.get("file")).strip().strip("`'\" ")
        if file_.startswith("./"):
            file_ = file_[2:]
        sym = clean_text(raw.get("symbol")).strip().strip("`'\" ")
        quote = str(raw.get("evidence_quote") or raw.get("quote") or "").strip("\n")
        wrong = fit(raw.get("what_is_wrong") or raw.get("current_gap"), 420)
        outcome = fit(raw.get("user_outcome"), 240)
        change = fit(raw.get("proposed_change"), 420)
        verify = clean_text(raw.get("verify")).strip().strip("`").strip()
        verify = VERIFY_LABEL_RE.sub("", verify, count=1).strip()   # the model echoes the dialect bullet's label ("test: cd backend && ...", "VERIFY: ...") in front of the command (live 2026-10-18: ~all verify-dialect rejects)
    except Exception:
        return None, "schema"
    if not (title and file_ and sym and quote.strip() and wrong and change and verify):
        return None, "schema"
    if has_hidden(quote):
        return None, "hidden-chars"                      # zero-width / bidi / control characters in the quoted code: an injection channel (the quote is written into the roadmap line)
    sym = clean_symbol(sym, lens)
    if sym is None:
        return None, "symbol-invalid"
    title, wrong, change = defang(title), defang(wrong), defang(change)
    size = str(raw.get("size") or "").strip().upper()
    if size not in ("S", "M"):
        return None, "size"
    if HEDGE_RE.search(claim_clause(wrong)):   # the CLAIM (first sentence) is a fact about THIS code; "may / might / could" there is a guess the quote does not back (first real run: 2 of 2 accepted items hedged). Hedges in the consequence sentences are fine.
        return None, "hedged-claim"
    t = re.sub(r"[^0-9]", "", str(raw.get("tier") or "2")) or "2"
    tier = min(3, max(1, int(t[0])))
    item = {"title": title, "file": file_, "sym": sym, "quote": quote, "wrong": wrong, "change": change, "verify": verify, "size": size, "tier": tier}
    if lens == FEATURE_LENS:
        if not outcome:
            return None, "feature-no-outcome"                 # a feature must name the user-visible result
        if has_hidden(str(raw.get("user_outcome") or "")):
            return None, "hidden-chars"
        item["outcome"] = defang(outcome)
        item["tag"] = QF.FEATURE_TAG
    return item, ""


def symbol_ok(sym, text):
    base = re.sub(r"\(.*$", "", sym).strip()
    parts = [x for x in re.split(r"[.:#/\s]+", base) if x]
    if not parts:
        return False
    name = parts[-1]
    return len(name) >= 2 and has_word(name, text) or (len(parts) > 1 and has_word(parts[0], text) and has_word(name, text))


def locate_quote(quote, text):
    """(ok, quote_used, line_no). Whitespace-normalised substring match; a model-added `12|` / `12:` line-number prefix is stripped when that makes it match."""
    n_text = norm_ws(text)
    q = quote
    for attempt in (q, "\n".join(re.sub(r"^\s*\d+\s*[|:]\s?", "", ln) for ln in q.split("\n"))):
        nq = norm_ws(attempt)
        if len(nq) >= 12 and "..." not in nq and "…" not in nq and nq in n_text:
            line_no = 0
            for ln in attempt.split("\n"):
                s = ln.strip()
                if len(s) >= 4:
                    for i, tl in enumerate(text.split("\n"), 1):
                        if s in tl.strip() or norm_ws(s) in norm_ws(tl):
                            line_no = i
                            break
                if line_no:
                    break
            return True, attempt, line_no or 1
    return False, quote, 0


TRIVIAL_LINE = re.compile(r"^(#|//|/\*|\*|import |from \S+ import |extends |class_name |[})\]]|pass\b)")


def quote_trivial(quote):
    """True when every non-blank line of the quote is a comment / import / closer: it shows no behaviour."""
    ls = [l.strip() for l in quote.split("\n") if l.strip()]
    return not ls or all(TRIVIAL_LINE.match(l) for l in ls)
VERIFY_LABEL_RE = re.compile(r"^(?:VERIFY|verify|(?:backend |web |GUT |static )?test)\s*:\s+")
VERIFY_BAD = re.compile(r"`|\$\(|\brm\s|\bcurl\b|\bwget\b|\bssh\b|\bsudo\b|\bchmod\b|\bgit\s+(push|commit|checkout|reset)|\bmv\s|\bcp\s|\bdd\s|\bkill\b|\bnc\b")
_SQ_RE = re.compile(r"'[^']*'")
_DQ_RE = re.compile(r'"(?:[^"\\]|\\.)*"')
_REL = r"(?!/)(?!.*\.\.)[\w./-]+"
_PYTEST_PATH = re.compile(r"^(?!/)(?!.*\.\.)[\w./-]+(?:\.py)?(?:::[\w\[\]\-.:]+)?$")
_VITEST_PATH = re.compile(r"^(?!/)(?!.*\.\.)[\w./-]+\.(?:ts|tsx|js|vue)$")
_GODOT_FLAG = re.compile(r"^(?:--headless|--quit|-gexit|-gexit_on_success|-gdisable_colors|-glog=\d|-gtest=res://(?!.*\.\.)[\w./-]+|-gselect=[\w.]+|-gunit_test_name=\w+|-gdir=res://(?!.*\.\.)[\w./-]+|-gprefix=\w+|-gsuffix=[\w.]+)$")
_PYTEST_FLAG = re.compile(r"^(?:-q|-qq|-x|-v|-vv|-s|-rN|-ra|--no-cov|--tb=(?:short|no|line|native|auto)|--maxfail=\d+|--no-header|--disable-warnings|-p no:cacheprovider)$")
_GREP_FLAG = re.compile(r"^-(?![A-Za-z0-9]*[fPrR])[A-Za-z0-9]+$")   # no -f (patterns from a file) / -P / -r -R (recursion follows symlinks out of the scratch copy)
KNOWN_GODOT = {"godot", "godot4", "Godot", "~/Applications/Godot.app/Contents/MacOS/Godot", "~/godot/godot4", "/usr/local/bin/godot", "/usr/bin/godot", "/usr/local/bin/godot4", "/usr/bin/godot4"}
VERIFY_UNSAFE_CHARS = re.compile(r"[;&|`<>(){}\\]|\$")


def _verify_tokens(v):
    """-> (leading `cd dir`, negated, [shell words]) or None when the command is not ONE simple command (chaining, pipes, redirects other than 2>/dev/null, substitutions, expansions)."""
    v = v.strip()
    m = re.match(r"^cd (%s) && (.*)$" % _REL, v)
    cd = None
    if m:
        cd, v = m.group(1), m.group(2).strip()
    neg = False
    if v.startswith("!"):
        neg, v = True, v[1:].strip()
    v = re.sub(r"\s2>/dev/null$", "", v)
    stripped = _SQ_RE.sub("''", v)                         # single quotes are literal: `$store` / `a|b` inside them is data
    stripped = _DQ_RE.sub(lambda mm: mm.group(0) if re.search(r"[$`\\]", mm.group(0)) else '""', stripped)   # a `$` or backslash inside double quotes expands / escapes: keep it visible to the check
    if VERIFY_UNSAFE_CHARS.search(stripped) or "\n" in v:
        return None
    try:
        words = shlex.split(v, posix=True)
    except ValueError:
        return None
    return cd, neg, words


VERIFY_NORMALIZE = os.environ.get("OVN_QE_VERIFY_NORMALIZE", "on").strip().lower() not in ("off", "0", "no", "false")
_VENV_PYTEST_HEAD = re.compile(r"^(?:\./)?(?:[\w-]+/)?\.?venv/bin/pytest$")
_VENV_PYTHON_HEAD = re.compile(r"^(?:\./)?(?:[\w-]+/)?\.?venv/bin/python3?$")


def normalize_verify(v, fset=()):
    """Mechanically rewrite a model-written pytest VERIFY into the one dialect verify_dialect_reason() accepts (and the red-check runner resolves), BEFORE the strict check.
    Real rejects (2026-10-18, shrike-monitor / shrike-notify / test-automation-agent: AGENTS.md says `cd backend && .venv/bin/pytest -q --no-cov`, so the 27B copied it):
      * `.venv/bin/pytest` / `venv/bin/pytest` / `<venv>/bin/python -m pytest`  -> `pytest` (a plain `python3 -m pytest` is kept) (lib_verify_clause.sh substitutes the repo's own venv for a bare pytest)
      * `pytest backend/tests/test_x.py` from the repo root while the suite (pytest.ini) lives in backend/  -> `cd backend && pytest tests/test_x.py`
      * `cd backend && pytest backend/tests/test_x.py` (double prefix)  -> `cd backend && pytest tests/test_x.py`
      * `pytest tests/test_x.py` from the root when only backend/ has pytest.ini and the root has none -> `cd backend && pytest tests/test_x.py`
    Only a command that already parses as ONE simple command (no chaining beyond a leading `cd <rel> &&`, no pipes / redirects / expansions) is touched, and the result still goes through
    verify_dialect_reason(): this never widens what may run, it only fixes the spelling. Anything else comes back unchanged (and is then rejected as before)."""
    if not VERIFY_NORMALIZE or not isinstance(v, str) or "\n" in v or len(v) > 300:
        return v
    quiet = bool(re.search(r"\s2>/dev/null\s*$", v))
    toks = _verify_tokens(v)
    if toks is None:
        return v
    cd, neg, w = toks
    if not w:
        return v
    head, args = w[0], list(w[1:])
    lead = ["pytest"]                                  # a plain `python3 -m pytest` keeps its spelling (the repo dialect for iptv_apps / billwatch); only a venv-path head is replaced
    if _VENV_PYTEST_HEAD.match(head):
        head = "pytest"
    elif _VENV_PYTHON_HEAD.match(head) and args[:2] == ["-m", "pytest"]:
        head, args = "pytest", args[2:]
    elif head in ("python", "python3") and args[:2] == ["-m", "pytest"]:
        head, args, lead = "pytest", args[2:], [head, "-m", "pytest"]
    if head != "pytest":
        return v
    fset = set(fset or ())
    idx, i = [], 0                                     # indexes of the path arguments (flags and the -k expression are skipped)
    while i < len(args):
        a = args[i]
        if a == "-k" and i + 1 < len(args):
            i += 2
            continue
        if not a.startswith("-") and _PYTEST_PATH.match(a):
            idx.append(i)
        i += 1
    if idx:
        firsts = {args[j].split("/", 1)[0] for j in idx if "/" in args[j]}
        if cd and all(args[j].startswith(cd.rstrip("/") + "/") for j in idx):
            for j in idx:
                args[j] = args[j][len(cd.rstrip("/")) + 1:]
        elif not cd and len(firsts) == 1 and all("/" in args[j] for j in idx):
            d = next(iter(firsts))
            if re.match(r"^[\w.-]+$", d) and d not in ("tests", "test") and "pytest.ini" not in fset and any(("%s/%s" % (d, n)) in fset for n in ("pytest.ini", "conftest.py", "tests/conftest.py", "setup.cfg")):
                cd = d
                for j in idx:
                    args[j] = args[j][len(d) + 1:]
        if not cd and "pytest.ini" not in fset and all(args[j].startswith("tests/") for j in idx):
            dirs = sorted({f.split("/", 1)[0] for f in fset if f.count("/") == 1 and f.endswith("/pytest.ini")})
            if len(dirs) == 1:
                cd = dirs[0]
    out = " ".join(shlex.quote(x) for x in lead + args)
    if neg:
        out = "! " + out
    if cd:
        out = "cd %s && %s" % (cd, out)
    if quiet:
        out += " 2>/dev/null"
    return out


def verify_dialect_reason(v):
    """'' when the VERIFY is ONE command from a closed allow-list whose arguments cannot execute, write or fetch anything of the model's choosing:
       grep/egrep/fgrep (letter flags only), pytest (python -m pytest) on relative paths with a small flag set, `npx vitest run <relative test files>`, `npm (run) test`, godot GUT
       (-s addons/gut/gut_cmdln.gd and gut flags), test/[ on plain operands. `python3 -c`, interpreters, chaining, pipes, redirects and expansions are refused: the VERIFY text is model
       output that read repo text (a prompt-injection / side-effect channel; reviewer finding 2)."""
    if "\n" in v or len(v) > 300 or not v.strip():
        return "verify-shape"
    if VERIFY_BAD.search(v) or v.rstrip().endswith(";"):
        return "verify-dialect"
    toks = _verify_tokens(v)
    if toks is None:
        return "verify-dialect"
    cd, neg, w = toks
    if not w:
        return "verify-dialect"
    head, args = w[0], w[1:]
    if head in ("grep", "egrep", "fgrep"):
        i = 0
        while i < len(args) and args[i].startswith("-"):
            if not _GREP_FLAG.match(args[i]):
                return "verify-dialect"
            i += 1
        rest = args[i:]
        return "" if len(rest) >= 2 and all(not r.startswith("-") for r in rest[1:]) and all(re.match(_REL + r"$", r) for r in rest[1:]) else "verify-dialect"
    if head in ("python3", "python") and args[:2] == ["-m", "pytest"]:
        args = args[2:]
    elif head != "pytest":
        head = ""
    else:
        pass
    if head in ("python3", "python", "pytest"):
        i, paths = 0, 0
        while i < len(args):
            a = args[i]
            if a == "-k" and i + 1 < len(args) and re.match(r"^[\w ()\-.]+$", args[i + 1]):
                i += 2
                continue
            if _PYTEST_FLAG.match(a):
                i += 1
                continue
            if _PYTEST_PATH.match(a) and not a.startswith("-"):
                paths += 1
                i += 1
                continue
            return "verify-dialect"
        return "" if paths >= 1 else "verify-dialect"
    if head == "" and w[0] == "npx" and args[:2] == ["vitest", "run"]:
        rest = args[2:]
        i, paths = 0, 0
        while i < len(rest):
            if rest[i] == "-t" and i + 1 < len(rest) and re.match(r"^[\w ()\-.]+$", rest[i + 1]):
                i += 2
            elif _VITEST_PATH.match(rest[i]):
                paths += 1
                i += 1
            else:
                return "verify-dialect"
        return "" if paths >= 1 else "verify-dialect"
    if head == "" and w[0] == "npm" and args and args[0] in ("test", "run") and (args[:2] == ["run", "test"] or args[0] == "test"):
        rest = args[2:] if args[0] == "run" else args[1:]
        if rest and (rest[0] != "--" or not all(_VITEST_PATH.match(r) for r in rest[1:])):
            return "verify-dialect"
        return ""
    if head == "" and w[0] in KNOWN_GODOT:
        i, gut = 0, False
        while i < len(args):
            a = args[i]
            if a == "-s" and i + 1 < len(args) and args[i + 1] == "addons/gut/gut_cmdln.gd":
                gut = True
                i += 2
            elif a == "--path" and i + 1 < len(args) and re.match(_REL + r"$", args[i + 1]):
                i += 2
            elif _GODOT_FLAG.match(a):
                i += 1
            else:
                return "verify-dialect"
        return "" if gut else "verify-dialect"
    if w[0] in ("test", "["):
        ops = args[:-1] if w[0] == "[" and args and args[-1] == "]" else args
        return "" if ops and all(re.match(r"^[\w./=\-!]+$", o) for o in ops) and not (w[0] == "[" and args[-1:] != ["]"]) else "verify-dialect"
    return "verify-dialect"


# ------------------------------------------------------------------------------------------------ claim-level checks (the quote exists is not enough: it must sit IN the named symbol and the claim must be about it)
def _indent(line):
    return len(line) - len(line.lstrip(" \t"))


def _indent_block_end(lines, i, base):
    """Index of the last line of the indentation block that starts at line index i (indent > base continues it; blank lines, closers `)]}` at the base indent and decorators belong to it)."""
    end = i
    for j in range(i + 1, len(lines)):
        ln = lines[j]
        if not ln.strip():
            continue
        if _indent(ln) > base or (_indent(ln) == base and re.match(r"\s*[)\]}]", ln)):
            end = j
        else:
            break
    return end


def _brace_block_end(lines, i):
    """Index of the line where the `{ ... }` block opened at (or just after) line index i closes; i itself when no brace opens within 3 lines (an expression-bodied arrow / one-liner)."""
    depth, opened = 0, False
    for j in range(i, min(len(lines), i + 400)):
        ln = re.sub(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"|`(?:[^`\\]|\\.)*`", "", lines[j])
        ln = re.sub(r"//.*$", "", ln)
        for ch in ln:
            if ch == "{":
                depth += 1
                opened = True
            elif ch == "}":
                depth -= 1
        if opened and depth <= 0:
            return j
        if not opened and j >= i + 3:
            return i
    return i if not opened else min(len(lines) - 1, i + 400)


def symbol_spans(path, text, sym):
    """[(first_line, last_line)] (1-based, inclusive) of every DEFINITION of the symbol's last name part in the file: python def / class / module or class assignment (decorators included),
    GDScript func / class / var / const / signal / enum (class_name = the whole file), TS / JS / Vue function / const / class / method / object member. Docs and templates: the whole file when the
    word occurs. [] when the symbol is never defined (a call or a mention is not a definition)."""
    base = re.sub(r"\(.*$", "", sym or "").strip()
    parts = [x for x in re.split(r"[.:#/\s]+", base) if x]
    if not parts:
        return []
    name = re.escape(parts[-1])
    lines = text.split("\n")
    ext = os.path.splitext(path)[1]
    spans = []
    if ext in (".md", ".html", ".json", ".yml", ".yaml", ".toml", ".txt"):
        return [(1, len(lines))] if has_word(parts[-1], text) else []
    if ext == ".gd" and re.search(r"^class_name\s+%s\b" % name, text, re.M):
        return [(1, len(lines))]
    if ext == ".py":
        decl = re.compile(r"^(\s*)(?:async\s+def|def|class)\s+%s\b|^(\s*)%s\s*(?::[^=\n]+)?=(?!=)" % (name, name))
    elif ext == ".gd":
        decl = re.compile(r"^(\s*)(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(?:func|class|var|const|signal|enum)\s+%s\b" % name)
    else:
        decl = re.compile(r"^(\s*)(?:export\s+)?(?:default\s+)?(?:async\s+)?(?:function\*?\s+%s\b|(?:const|let|var)\s+%s\b|class\s+%s\b|(?:static\s+|public\s+|private\s+|protected\s+|async\s+|get\s+|set\s+)*%s\s*(?:<[^>]*>)?\s*\([^)]*\)\s*(?::\s*[^{=]+)?\{|%s\s*:\s*(?:async\s*)?(?:function\b|\())" % ((name,) * 5))
    for i, ln in enumerate(lines):
        m = decl.match(ln)
        if not m:
            continue
        base_ind = _indent(ln)
        if ext in (".py", ".gd"):
            end = _indent_block_end(lines, i, base_ind)
            start = i
            while start > 0 and lines[start - 1].strip().startswith("@") and _indent(lines[start - 1]) == base_ind:
                start -= 1
        else:
            end, start = _brace_block_end(lines, i), i
        spans.append((start + 1, end + 1))
    return spans


def quote_ranges(quote, text):
    """[(first_line, last_line)] of EVERY place in the file where the quote's lines occur consecutively (whitespace-normalised, blank text lines between quote lines allowed; the first and
    last quote line may be a part of a longer text line). The first match alone is not enough: `except Exception: pass` occurs in many functions."""
    q = [norm_ws(l) for l in quote.split("\n") if norm_ws(l)]
    if not q:
        return []
    tl = text.split("\n")
    nt = [norm_ws(l) for l in tl]
    out = []
    for i in range(len(tl)):
        if q[0] not in nt[i] or (len(q) > 1 and not nt[i].endswith(q[0])):
            continue
        j, k = i, 1
        while k < len(q):
            j += 1
            while j < len(tl) and not nt[j]:
                j += 1
            if j >= len(tl):
                break
            ok_line = nt[j] == q[k] if k < len(q) - 1 else (q[k] in nt[j] and nt[j].startswith(q[k]))
            if not ok_line:
                break
            k += 1
        if k == len(q):
            out.append((i + 1, j + 1))
    return out


def quote_in_symbol(path, text, sym, quote, lens):
    """True when the (verbatim) quote lies inside a definition of the symbol. Vue / HTML templates (a11y lens) and docs have no symbol bodies: the whole file counts there. -> (ok, why)"""
    spans = symbol_spans(path, text, sym)
    if not spans and lens == "a11y-ux" and path.endswith((".vue", ".html", ".tsx")) and symbol_ok(sym, text):
        spans = [(1, text.count("\n") + 1)]
    if not spans:
        return False, "symbol-not-defined"
    rng = quote_ranges(quote, text)
    if not rng:
        return True, ""                                   # the quote matched only after whitespace folding across lines: nothing to locate it by (rare); the symbol exists
    if any(ss <= qs and qe <= se for (qs, qe) in rng for (ss, se) in spans):
        return True, ""
    return False, "quote-outside-symbol"


def span_text(text, spans):
    ls = text.split("\n")
    return "\n".join("\n".join(ls[a - 1:b]) for a, b in spans)


def module_names(path, text):
    """The names a test would use to reach this module: its stem and (GDScript) its class_name."""
    names = {os.path.splitext(os.path.basename(path))[0]}
    m = re.search(r"^class_name\s+(\w+)", text, re.M)
    if m:
        names.add(m.group(1))
    return {n for n in names if len(n) >= 3}


def route_paths(text):
    """HTTP paths a FastAPI / Express router file serves: `prefix + path` for every decorator (the prefix of APIRouter(prefix=...) when present)."""
    pm = re.search(r"APIRouter\([^)]*prefix\s*=\s*['\"]([^'\"]+)['\"]", text)
    prefix = pm.group(1) if pm else ""
    out = set()
    for m in re.finditer(r"@\w+\.(?:get|post|put|delete|patch)\(\s*['\"]([^'\"]*)['\"]", text):
        full = prefix + m.group(1)
        if len(full.strip("/")) >= 3:
            out.add(full.rstrip("/") or "/")
    return out


UNTESTED_CLAIM_RE = re.compile(r"\b(?:no|not|without|lacks?|lacking|missing|absent|zero)\b[^.]{0,40}\b(?:tests?|test coverage|coverage|tested|covered)\b|\b(?:untested|uncovered|unpinned)\b|\btests?\b[^.]{0,30}\b(?:missing|absent|lacking)\b", re.I)


def covered_by_tests(path, text, sym, env):
    """The test-gaps claim ('nothing tests this') is refuted when ANY test file names the symbol, imports / names the module (stem or class_name), or requests one of the routes the file serves."""
    if "test_texts" not in env:
        env["test_texts"] = [read_text(os.path.join(env["snap"], p)) for p in env["files"] if is_test_path(p) and p.endswith(SRC_EXTS)]
    name = [x for x in re.split(r"[.:#/\s]+", re.sub(r"\(.*$", "", sym).strip()) if x]
    needles = set(module_names(path, text)) | ({name[-1]} if name else set())
    routes = route_paths(text)
    for t in env["test_texts"]:
        if any(has_word(n, t) for n in needles):
            return True
        if any(r in t for r in routes):
            return True
    return False


# self-contradiction / authority / convention / schema / atomicity heuristics: cheap text rules over the item's own claim
SELF_REFUTING_RE = re.compile(r"\b(?:is|are|remains?|stays?) (?:already )?(?:safe|fine|harmless|acceptable|correct|valid|harmless in practice)\b|\bnot (?:really )?an? (?:bug|problem|defect|issue)\b|\bno (?:real |practical |functional )?(?:impact|issue|problem)\b|\bworks (?:correctly|as intended)\b|\bonly a (?:style|readability|cosmetic)\b", re.I)
AUTHORITY_RE = re.compile(r"\b(?:roadmap|AGENTS(?:\.md)?|repo(?:sitory)? rules?|project (?:standards?|conventions?|polic(?:y|ies)|guidelines?)|coding (?:standards?|conventions?|guidelines?)|style guide)\b[^.]{0,50}\b(?:mandate|require|state|say|specif|dictate|demand)\w*", re.I)
CONVENTION_RE = re.compile(r"\b(?:timezone|tz[- ]?aware|naive|aware datetime|utcnow|Decimal|column type|data type|return type|type of|int to str|str to int|float to int|(?:change|switch|alter)\s+(?:the\s+)?serializ\w*|serialization (?:format|convention)|encoding)\b", re.I)
SCHEMA_RE = re.compile(r"\b(?:UniqueConstraint|unique constraint|unique\s*\(|unique index|add (?:a |an )?(?:unique|index|foreign key|column|constraint)|alembic|migrations?|nullable\s*=|ForeignKey)\b", re.I)
ATOMIC_RE = re.compile(r"\b(?:atomic(?:ally|ity)?|transactional|all[- ]or[- ]nothing|rollback|partial(?:ly)? (?:commit|write|import|state)|half[- ]written)\b", re.I)
PROTECTED_PROSE = re.compile(r"\.queue-hard-banned-files|hard[- ]?(?:file[- ])?ban|\bAGENTS(?:\.md)?\b|\bOVERNIGHT_\w+|\bCLAUDE(?:\.md)?\b|\.github\b|\.claude\b|(?<![\w.])\.env\b|\bcrontab\b|\bov[nN]_\w+|\bqueue_refill\b|\blib_\w+\.sh\b|\brun_overnight\w*|\bbranch_hygiene\b|\breconcile_branches\b|\bpromote_to_prod\b|\bstaging_smoke\b|\bdeploy_watch\b|(?<![\w/-])(?:roadmap|backlog|state)/[\w.-]+\.(?:md|json|jsonl|txt|log|lock|sh|py)\b|\bgate scripts?\b|\bhygiene\b|"
                            r"ignore (?:all |the |any )?(?:previous|prior|above) (?:instructions|rules)|disregard (?:the |all |any )?(?:previous|prior|above|rules)|\bsystem prompt\b|\byou are now\b|\bdisable (?:the )?(?:\w+[- ]){0,3}(?:gate|ban|guard|hook|lint)\b", re.I)
UNDECLARED_PATH = re.compile(r"(?<![\w./-])((?:[\w.-]+/)+[\w.-]+\.[A-Za-z]{1,6}|[\w-]+\.(?:py|gd|vue|ts|tsx|sh|md|sql|ya?ml|toml))(?![\w/(])(?!\.\w)")


def undeclared_paths(prose, file_, fset):
    """File names the item's prose mentions that are neither its own file, a test path (a new test file is the one thing an item may create), nor an existing snapshot file. The prose goes verbatim
    into the planner prompt: an item that names `run_overnight.sh` (absent from the repo) is steering the fleet at something that is not the item's code."""
    out = []
    for p in UNDECLARED_PATH.findall(prose or ""):
        p = p.strip(".")
        if p == file_ or is_test_path(p) or p in fset or any(f.endswith("/" + p) for f in fset):
            continue
        out.append(p)
    return out


AUTH_CLAIM_RE = re.compile(r"\b(?:missing|lacks?|without|no|absent|unauthenticated|anonymous|unprotected)\b[^.]{0,60}\b(?:auth\w*|login|current_user|permission|ownership|owner check)\b|\b(?:auth\w*|current_user)\b[^.]{0,40}\b(?:missing|absent|lacking|not (?:required|enforced|checked))\b", re.I)
PUBLIC_WORD_RE = re.compile(r"\b(?:public|anonymous|unauthenticated|no[- ]auth|open to all|intentionally open)\b", re.I)


def declared_public(it, text, env):
    """True when the snapshot itself says the route (or the function) of this item is public: any test / policy / doc line that names the route path (or the function) next to 'public' / 'anonymous' /
    'unauthenticated'. The first real run proposed 'missing auth' for GET /api/discovery/similar/{channel_id}, which tests/paywall/route_policy.py declares \"public\"."""
    if "policy_texts" not in env:
        env["policy_texts"] = [(p, read_text(os.path.join(env["snap"], p))) for p in env["files"] if p.endswith((".py", ".md", ".json", ".yml", ".yaml", ".ts", ".gd", ".txt")) and (is_test_path(p) or p.startswith("docs/") or p.endswith((".md", ".json")))]
    name = [x for x in re.split(r"[.:#/\s]+", re.sub(r"\(.*$", "", it["sym"]).strip()) if x]
    needles = set(route_paths(text))
    needles = {re.sub(r"\{[^}]*\}", "{", r).split("{")[0].rstrip("/") for r in needles}
    needles = {n for n in needles if len(n) >= 4}
    if name and len(name[-1]) >= 6:
        needles.add(name[-1])
    if not needles:
        return False
    for _p, t in env["policy_texts"]:
        for ln in t.split("\n"):
            if PUBLIC_WORD_RE.search(ln) and any(n in ln for n in needles):
                return True
    return False


def commit_in_loop(src):
    """True when a commit() call sits inside a for / while block of the given source (one textual commit that runs once per row is not 'a single commit')."""
    ls = src.split("\n")
    for i, ln in enumerate(ls):
        if not re.search(r"\bcommit\s*\(", ln):
            continue
        cur = _indent(ln)
        for j in range(i - 1, -1, -1):
            if not ls[j].strip() or _indent(ls[j]) >= cur:
                continue
            if re.match(r"\s*(?:async\s+)?(?:for|while)\b|.*\.forEach\(", ls[j]):
                return True
            cur = _indent(ls[j])
    return False


SCOPE_CLAIM_RE = re.compile(r"\b(?:all|every|any|other)\s+(?:the\s+)?(?:users?|accounts?|tenants?|customers?|profiles?)\b|\bacross\s+(?:users|accounts|tenants)\b|\b(?:unfiltered|unscoped)\b|\bnot scoped\b|\bnever scopes?\b|\bno (?:user|owner|tenant) (?:filter|scope|check)\b|\bwithout (?:a |an )?(?:user|owner|tenant) (?:filter|scope|check)\b", re.I)
OWNER_FILTER_RE = re.compile(r"\b(?:user_id|owner_id|tenant_id|account_id|profile_id|userId|ownerId)\b\s*(?:==|=|!=|in\b)|(?:==|=)\s*(?:current_)?user(?:\.id|_id|Id)?\b|\.filter(?:_by)?\([^)]*\buser", re.I)
AUTH_QUOTE_RE = re.compile(r"Depends\(\s*(?:get_current_user|require_\w+|current_user\w*)|@(?:login_required|requires_auth|authenticated)|\bcurrent_user\b|\bauthenticat\w+\(", re.I)
NEVER_COMMIT_RE = re.compile(r"\bnever\s+(?:commits?|persists?|saves?|flushes)\b|\bnot\s+(?:committed|persisted|saved|flushed)\b|\bwithout\s+(?:a\s+)?commit\b|\bno\s+commit\b", re.I)
COMMIT_QUOTE_RE = re.compile(r"\.commit\(|\bcommit\(|\.save\(|\.flush\(|\bsave\(", re.I)
NO_NONE_CHECK_RE = re.compile(r"\b(?:without|no|missing|lacks?|unchecked)\s+(?:a\s+)?(?:None|null|undefined|empty|existence)\s+(?:check|guard|validation)\b|\bnever\s+checks?\b|\bdoes\s+not\s+check\b", re.I)
NONE_QUOTE_RE = re.compile(r"\bis\s+(?:not\s+)?None\b|[!=]=\s*None\b|[!=]==?\s*null\b|\bif\s+not\s+\w+|\?\?|\?\.", re.I)
UNBOUNDED_CLAIM_RE = re.compile(r"\b(?:no\s+limit|unbounded|without\s+(?:a\s+)?(?:limit|pagination)|no\s+pagination)\b", re.I)
LIMIT_QUOTE_RE = re.compile(r"\.limit\(|\bLIMIT\b|\[\s*:\s*\d+\s*\]|\bpaginat\w+|\bpage_size\b", re.I)
CONCURRENCY_RE = re.compile(r"\b(?:race(?:\s+conditions?)?|races|concurrent(?:ly)?|parallel\s+(?:requests?|calls?|callers?)|simultaneous(?:ly)?|double[- ](?:redeem|spend|submit|charge|click)\w*|under\s+load|at\s+the\s+same\s+time|thread[- ]?safe|two\s+(?:requests|callers))\b", re.I)


NONE_TOPIC_RE = re.compile(r"\b(?:none|null|undefined|empty|exist\w*|missing)\b", re.I)


def contradicted_by_quote(it, lens=None):
    """A claim whose own evidence says the opposite ('returns all users' records' above `if r.user_id == user.id`, 'no auth' above `Depends(get_current_user)`, 'never commits' above `db.commit()`, 'no None check'
    above `if x is None`, 'no limit' above `.limit(`) is a misreading, whatever the skeptic says. -> '' or 'contradicted-by-quote'."""
    claim, q = clean_text(it["title"] + " " + it["wrong"]), it["quote"]
    if SCOPE_CLAIM_RE.search(claim) and OWNER_FILTER_RE.search(q):
        return "contradicted-by-quote"
    if AUTH_CLAIM_RE.search(claim) and AUTH_QUOTE_RE.search(q):
        return "contradicted-by-quote"
    if NEVER_COMMIT_RE.search(claim) and COMMIT_QUOTE_RE.search(q):
        return "contradicted-by-quote"
    if NO_NONE_CHECK_RE.search(claim) and NONE_QUOTE_RE.search(q) and (lens != FEATURE_LENS or NONE_TOPIC_RE.search(claim)):
        return "contradicted-by-quote"                   # feature lens: 'does not check for duplicates' is a gap about duplicates, not a claim that a None check is missing (live dry run 2026-10-23: 2 of 3 TAA items)
    if UNBOUNDED_CLAIM_RE.search(claim) and LIMIT_QUOTE_RE.search(q):
        return "contradicted-by-quote"
    return ""


def claim_reason(it, lens, span_src, env=None):
    """'' or a reject reason from the text rules above. `span_src` = the source of the named symbol (the atomicity rule reads it). `env` (snap + files) lets the convention rule check that a named second file
    really uses the symbol."""
    prose = " ".join([it["title"], it["wrong"], it["change"]])
    if SELF_REFUTING_RE.search(prose):
        return "self-refuting"
    if AUTHORITY_RE.search(prose):
        return "authority-claim"
    if lens != "docs-drift" and SCHEMA_RE.search(prose):
        return "needs-migration"
    other_paths = {p for p in paths_in(it["change"]) if p != it["file"] and not is_test_path(p)}
    if CONVENTION_RE.search(prose) and lens != "docs-drift":
        leaf = [x for x in re.split(r"[.:#/\s]+", re.sub(r"\(.*$", "", it["sym"]).strip()) if x]
        users = [p for p in other_paths if env and p in env["files"] and leaf and has_word(leaf[-1], read_text(os.path.join(env["snap"], p)))]
        if not users:
            return "convention-change"                   # a type / timezone / encoding convention change must name a second file that REALLY uses the symbol (the caller / column): a bare filename proves nothing (reviewer 3)
    if lens != "docs-drift" and CONCURRENCY_RE.search(it["title"] + " " + it["wrong"]):
        return "concurrency-claim-unsupported"           # a race is not provable from one function and a red-before test cannot reproduce it deterministically
    if ATOMIC_RE.search(it["title"] + " " + it["wrong"]) and it["file"].endswith((".py", ".ts", ".js")) and len(re.findall(r"\bcommit\s*\(", span_src)) <= 1 and not commit_in_loop(span_src):
        return "atomicity-claim-unsupported"             # at most one commit() in the named function: it already commits (or fails) as one unit
    return ""


_TEST_VERIFY = re.compile(r"^(?:cd [\w./-]+ && )?(?P<neg>!\s*)?(?:test|\[)\s+(?P<neg2>!\s*)?-[a-zA-Z]\s")
ABSENCE_DEFECT_RE = re.compile(r"eval\(|exec\(|console\.log|\bprint\(|debugger|breakpoint\(|\bpdb\.|\bTODO\b|FIXME|\bXXX\b|\bHACK\b|password\s*=|secret|verify\s*=\s*False|except\s*:|except\s+Exception\s*:|\b1234\b|http://|\blocalhost\b|\balert\(|window\.location|\.innerHTML|dangerouslySetInnerHTML|\bmd5\b|\bsha1\(|Math\.random|random\.random|\bpass\b\s*$", re.I)
STATIC_ABSENCE_OK = {"bug-hunt", "authz-input", "api-contract", "dead-code", "type-safety", "a11y-ux", "docs-drift"}


def static_verify_reason(verify, lens, quote=None):
    """A static grep can be satisfied by a cosmetic edit. Allowed: docs-drift (a doc edit IS the change) and ABSENCE greps (`! grep P f`, red while the quoted defect text is present) of at least 12
    characters for lenses where deleting the text is the fix. A PRESENCE grep (a comment satisfies it) and any static grep for performance / test-gaps / completeness / data-integrity must be a
    behavioural test instead."""
    if lens == "docs-drift":
        return ""
    mt = _TEST_VERIFY.match(verify.strip())
    if mt:                                                  # `test -f new_test_file` is satisfied by creating an empty file: never evidence of a defect; only `test ! -e <file>` for deleting dead code
        return "" if (lens == "dead-code" and (mt.group("neg") or mt.group("neg2"))) else "verify-cosmetic"
    m = _GREP_VERIFY.match(verify.strip())
    if not m:
        return ""
    if not m.group("neg"):
        return "verify-cosmetic"
    pat = (m.group("qp") or m.group("bp") or "")
    if lens not in STATIC_ABSENCE_OK or len(norm_ws(pat)) < 12:
        return "verify-cosmetic"
    if quote is not None and norm_ws(pat).lower() not in norm_ws(quote).lower():
        return ""                                           # not even in the quoted lines: verify_unanchored refuses it with its own reason
    if not (ABSENCE_DEFECT_RE.search(pat) or (lens == "dead-code" and re.match(r"^(?:async\s+)?(?:def|class|func|function|const)\s+\w+", pat.strip()))):
        return "verify-cosmetic"                            # an absence grep must name text that IS the defect (debug print, eval, bare except, hard-coded secret ...): any other pattern is satisfied by re-spelling the line
    return ""


_GREP_VERIFY = re.compile(r"^(?:cd [\w./-]+ && )?(?P<neg>!\s*)?(?:grep|egrep|fgrep)\s+(?:-[A-Za-z0-9]+\s+)*(?:(?P<q>['\"])(?P<qp>.+?)(?P=q)|(?P<bp>[^\s'\"-]\S*))")


def verify_unanchored(verify, change, quote):
    """A static VERIFY must be consistent with what the item says: a PRESENCE grep (`grep -q P f`, red because P is absent) must look for text the fix tells the implementer to write (P is in
    proposed_change), an ABSENCE grep (`! grep P f`, red because P is present) must look for text of the quoted defect (P is in evidence_quote). Otherwise the red is vacuous (the first
    real run accepted `grep -q 'limiter.limit(\"20/minute/user\")'`, a literal nobody was told to write). -> True when the VERIFY is unanchored."""
    m = _GREP_VERIFY.match(verify.strip())
    if not m:
        return False
    pat = norm_ws(m.group("qp") or m.group("bp") or "").lower()
    if len(pat) < 3:
        return False
    hay = norm_ws(quote if m.group("neg") else change).lower()
    return pat not in hay


def new_test_paths(verify, snap_files):
    """Test paths the VERIFY names that do not exist in the snapshot (resolved against a leading `cd <dir> &&`): the item creates them."""
    m = re.match(r"^cd ([\w./-]+) && ", verify.strip())
    pre = (m.group(1).rstrip("/") + "/") if m else ""
    return [p for p in sorted(paths_in(verify)) if is_test_path(p) and p not in snap_files and (pre + p) not in snap_files]


def render_t_line(repo, it, snap_files):
    """The backlog-format line the intake lint + the red-before check consume (no backticks in the prose: R08 would read them as symbols)."""
    change = it["change"]
    for p in new_test_paths(it["verify"], snap_files):
        if p not in change:
            change += " Add %s." % p                  # the item creates that test: declared_paths() must see it (R12 / the classifier's new-target rule)
    text = "%s. %s" % (it["title"].rstrip("."), change)
    return "- [ ] [T%d] %s — %s VERIFY: `%s`. (cat:%s; multifile:no)" % (it["tier"], it["file"], text, it["verify"], backend_cat(it["file"]))


def roadmap_line(it, line_no):
    q = defang(cut_tokens(it["quote"], 150))
    multi = len({p for p in paths_in(it["change"] + " " + it["title"]) if not is_test_path(p)}) >= 2
    change = it["change"]
    for p in new_test_paths(it["verify"], it.get("snap_files", ())):
        if p not in change:
            change += " Add %s." % p
    tag = it.get("tag") or SRC_TAG
    outcome = (" Outcome: %s" % it["outcome"].rstrip()) if it.get("outcome") else ""
    body = "`%s:%d` (`%s`) %s%s Evidence: `%s`. Fix: %s VERIFY: `%s`. %s" % (it["file"], line_no, it["sym"], it["wrong"].rstrip(), outcome, q, change, it["verify"], tag)
    body = norm_ws(body)
    if len(body) > 1300:
        body = norm_ws("`%s:%d` (`%s`) %s%s Fix: %s VERIFY: `%s`. %s" % (it["file"], line_no, it["sym"], it["wrong"][:260], outcome[:200], change[:300], it["verify"], tag))
    meta = "{cat: %s; size: %s; multifile: %s; research: none}" % (cat_for_roadmap(it["file"]), it["size"], "yes" if multi else "no")
    return "- [ ] [P3] [ready] %s — %s %s" % (it["title"], body, meta)


def cat_for_roadmap(path):
    if is_test_path(path):
        return "test"
    ext = os.path.splitext(path)[1]
    if ext == ".gd":
        return "game"
    if ext in (".vue", ".tsx", ".ts", ".js"):
        return "web"
    return "backend"


def load_module(path, name):
    try:
        spec = importlib.util.spec_from_file_location(name, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception:
        return None


def find_script(*cands):
    return next((p for p in cands if p and os.path.isfile(p)), None)


def run_validator(lines, roadmap_path):
    """ovn_auto_research_validate.py (format, mechanical-gap, duplicate titles, near-duplicates, 1500-char cap, cites a path).
    -> (accepted_titles | None when the validator is unavailable, [(reject reason, stderr line)])"""
    val = find_script(os.path.join(OVN_DIR, "ovn_auto_research_validate.py"), os.path.join(HERE, "..", "ovn_auto_research_validate.py"))
    if not val:
        return None, []
    d = tempfile.mkdtemp(prefix="qe-val-")
    try:
        prop = os.path.join(d, "proposed.md")
        open(prop, "w").write("\n".join(lines) + "\n")
        r = subprocess.run([sys.executable, val, prop, roadmap_path, "99"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None, []
    finally:
        shutil.rmtree(d, ignore_errors=True)
    rejects = []
    for ln in r.stderr.split("\n"):
        m = re.match(r"^reject: ([^:]+)", ln)
        if m:
            rejects.append((m.group(1).strip(), ln))
    titles = set()
    for l in r.stdout.split("\n"):
        m = re.match(r"^- \[ \] \[P[1-4]\] \[ready\] ([^\u2014]+?) \u2014 ", l)
        if m:
            titles.add(norm_title(m.group(1)))
    return titles, rejects


def lint_reason(t_line, ctx, banned):
    """'' when the intake lint passes; else 'lint:<rule>' / a parked / banned / no-verify reason. Repairs (R01-R03, R11, R16) are accepted: the repaired line is returned."""
    elig = load_module(os.path.join(HERE, "ovn_backlog_eligibility.py"), "qe_elig")
    rules = load_module(os.path.join(HERE, "ovn_spec_rules.py"), "qe_rules")
    if elig is None or rules is None:
        return "lint-unavailable", t_line
    if not elig.extract_verify(t_line):
        return "no-verify", t_line
    if elig.is_parked(t_line):
        return "lint:parked-pattern", t_line
    if elig.is_banned_target(t_line, banned):
        return "lint:banned-target", t_line
    try:
        line2, findings = rules.lint_item(t_line, ctx)
    except Exception as e:
        return "lint-error", t_line
    for f in findings:
        if f.get("sev") in ("reject", "flag"):
            return "lint:%s" % f.get("rule"), line2
    return "", line2


_SANDBOX = {}


def sandbox_prefix(work, tmp):
    """argv prefix that runs the red-before check with NO network and a read-only view of everything except the scratch worktree and the scratch tmp dir (bubblewrap), or [] when bwrap is missing /
    unusable / OVN_QE_SANDBOX=off. The VERIFY allow-list already refuses commands that fetch or write; this is the second wall against what a repo's own test code would do with an item's
    arguments (reviewer finding 2)."""
    if os.environ.get("OVN_QE_SANDBOX", "on") == "off":
        return []
    exe = os.environ.get("OVN_QE_BWRAP") or shutil.which("bwrap")
    if not exe:
        return None                                       # None = sandbox REQUIRED but unavailable (the caller fails closed); [] = sandbox explicitly off
    base = [exe, "--unshare-net", "--unshare-pid", "--die-with-parent", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp"]
    if exe not in _SANDBOX:
        try:
            _SANDBOX[exe] = subprocess.run(base + ["true"], capture_output=True, timeout=15).returncode == 0
        except (OSError, subprocess.SubprocessError):
            _SANDBOX[exe] = False
    return base + _sandbox_secret_masks() + ["--bind", work, work, "--bind", tmp, tmp] if _SANDBOX[exe] else None


# Credential locations under HOME that the red-check must not be able to read (the read-only root bind above would otherwise expose them). A directory is hidden with an
# empty tmpfs, a file is shadowed by /dev/null; only paths that EXIST are masked (bwrap cannot create a mount point inside the read-only root). OVN_QE_SANDBOX_MASK=off disables.
# SCOPE (2026-10-14 review): this is an explicit HOME list plus top-level HOME dotfiles named .env* (matched by prefix, so .env.railway is covered too). It does NOT scrub the
# environment (env vars such as tokens are still inherited by the sandboxed command) and does not mask repo-level .env files inside the scratch worktree; those are documented
# known limits, not guarantees. Build-cache dirs (~/.m2, ~/.gradle) are NOT masked as directories (an empty tmpfs would break offline builds); only their credential files are.
_SECRET_DIRS = (".ssh", ".gnupg", ".aws", ".kube", ".docker", ".config/gh", ".config/gcloud", ".local/share/keyrings")
_SECRET_FILES = (".netrc", ".npmrc", ".pypirc", ".git-credentials", ".pgpass", ".m2/settings.xml", ".gradle/gradle.properties")


def _sandbox_secret_masks():
    if os.environ.get("OVN_QE_SANDBOX_MASK", "on") == "off":
        return []
    home = os.path.expanduser("~")
    out = []
    for rel in _SECRET_DIRS:
        p = os.path.join(home, rel)
        if os.path.isdir(p):
            out += ["--tmpfs", p]
    for rel in _SECRET_FILES:
        p = os.path.join(home, rel)
        if os.path.isfile(p):
            out += ["--ro-bind", "/dev/null", p]
    try:                                                  # top-level HOME dotfiles named .env* (".env", ".env.railway", ...)
        env_names = sorted(n for n in os.listdir(home) if n.startswith(".env"))
    except OSError:
        env_names = []
    for n in env_names:
        p = os.path.join(home, n)
        if os.path.isfile(p):
            out += ["--ro-bind", "/dev/null", p]
    return out


def sandbox_alert(repo):
    """ONE alerts.log warn line per 6 h: the explorer is refusing every item because the red-check sandbox (bubblewrap) is unavailable."""
    mark = os.path.join(qdir(), "sandbox_alert_ts")
    try:
        if time.time() - os.path.getmtime(mark) < 6 * 3600:
            return
    except OSError:
        pass
    alert("warn", repo, "explorer red-check REFUSED every item: bubblewrap (bwrap) is missing or unusable on this host - install it, or set OVN_QE_SANDBOX=off to accept unsandboxed VERIFY runs")
    try:
        with open(mark, "w") as f:
            f.write(str(int(time.time())))
    except OSError:
        pass


def run_redcheck(repo, t_lines, work, row):
    """ovn_spec_check.sh on the scratch copy (same denylist / timeouts / classifier as the deterministic supply), inside the network-less read-only sandbox when available. -> {index: (verdict, sub)} or None when it could not run."""
    sh = find_script(os.environ.get("OVN_QE_SPEC_CHECK"), os.path.join(OVN_DIR, "scripts", "ovn_spec_check.sh"), os.path.join(HERE, "ovn_spec_check.sh"))
    if not sh:
        return None
    d = tempfile.mkdtemp(prefix="qe-spec-")
    try:
        f = os.path.join(d, "items.md")
        open(f, "w").write("\n".join(t_lines) + "\n")
        env = dict(os.environ, OVN_DIR=OVN_DIR, OVN_SPEC_WT=work, PYTHONDONTWRITEBYTECODE="1", VERIFY_TIMEOUT_SECS=str(VERIFY_SECS), CI="true", TMPDIR=d)
        pre = sandbox_prefix(os.path.realpath(work), os.path.realpath(d))
        if pre is None:                                 # FAIL CLOSED: the VERIFY would run unsandboxed - nothing is red-checked, nothing is accepted, and the log says why (OVN_QE_SANDBOX=off opts out explicitly)
            row.d["sandbox"] = "unavailable"
            row.d["note"] = (row.d.get("note", "") + " sandbox-unavailable: bubblewrap missing/unusable - red-check refused, no item accepted (install bwrap or set OVN_QE_SANDBOX=off)").strip()
            return None
        row.d["sandbox"] = "net-off+ro" if pre else "none"
        if pre:                                         # Godot (and pytest / vitest caches) write under $HOME: in a read-only world Godot crashes (rc 134, a false 'bad-spec'); point them at the writable scratch dir
            for var, sub in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
                os.makedirs(os.path.join(d, "xdg", sub), exist_ok=True)
                env[var] = os.path.join(os.path.realpath(d), "xdg", sub)
        r = subprocess.run(pre + ["bash", sh, repo, f], capture_output=True, text=True, timeout=max(300, VERIFY_SECS * 2 * len(t_lines) + 120), env=env, cwd=OVN_DIR if os.path.isdir(OVN_DIR) else None)
    except (OSError, subprocess.SubprocessError):
        return None
    finally:
        shutil.rmtree(d, ignore_errors=True)
    out = {}
    for ln in r.stdout.split("\n"):
        m = re.match(r"^(\d+)\t(\w[\w-]*)", ln)
        if m:
            cols = ln.split("\t")
            out[int(m.group(1)) - 1] = (m.group(2), cols[3].strip() if len(cols) > 3 else "")
    return out


def feature_reason(it, env):
    """The feature-ideation text rules ('' or a reject reason); they run next to ALL the existing gates (symbol / quote-inside-symbol / VERIFY allow-list / duplicates / red-before / skeptic / critic)."""
    if QF.helper_only(it["title"], it["change"], it["sym"]):
        return "feature-helper-only"                       # rule (a): a standalone helper / predicate / constant is not a feature
    why = QF.not_observable(it.get("outcome", ""))
    if why:
        return why
    prose = " ".join([it["title"], it["wrong"], it["change"], it.get("outcome", "")])
    if QF.sensitive_area(prose, it["file"]):
        return "feature-sensitive-area"                    # auth / crypto / payment work is never the 27B's to design
    others = {p for p in paths_in(prose) if p != it["file"] and not it["file"].endswith("/" + p) and not is_test_path(p)}      # the item's own file may be named by its bare basename
    if others:
        return "feature-multifile"
    if not QF.verify_is_test_runner(it["verify"]):
        return "feature-verify-not-test"                   # the red-before must come from a behavioural test, never an existence check
    seen = QF.seen_reason(it["title"], it["file"], it["sym"], env.get("feature_seen") or [])
    if seen:
        return seen
    return ""


def feature_concept_dup(it, env):
    """'feature-duplicate-concept' when an existing roadmap / backlog / progress / done title is the same feature reworded (any file): heavy title word overlap. Runs after duplicate_reason (which owns same-file / same-title)."""
    tw = words(it["title"])
    for ln in env.get("corpus") or []:
        r = readable_title(ln)
        lw = words(r[1].split(": ", 1)[-1]) if r else set()
        inter = len(tw & lw)
        if tw and lw and inter >= 3 and (inter / float(len(tw | lw)) >= 0.5 or inter / float(min(len(tw), len(lw))) >= 0.8):
            return "feature-duplicate-concept"             # the same feature under another title, in any file (title word overlap; the item's file / symbol need not match)
    return ""


def verify_items(repo, raw_items, ctx_env, row):
    """The mechanical acceptance pipeline. -> [accepted item dicts]. Every drop records a reason in row['rejected']."""
    snap, snap_files, scope, cfg = ctx_env["snap"], ctx_env["files"], ctx_env["scope"], ctx_env["cfg"]
    fset = set(snap_files)
    survivors = []
    pass_seen = {"verify": set(), "titles": []}
    for raw in raw_items:
        row.cur = one_line((raw or {}).get("title") if isinstance(raw, dict) else "", 110)
        it, why = normalise_item(raw, ctx_env["lens"])
        if it is None:
            row.reject(why)
            continue
        if it["file"] not in fset:
            row.reject("path-missing")
            continue
        f_why = scope.forbidden(it["file"])
        if f_why or not (scope.in_roots(it["file"]) or ctx_env["lens"] == "docs-drift" or ctx_env.get("relaxed")):
            row.reject("banned-path" if f_why in ("banned", "vendored", "protected") else "out-of-scope")
            continue
        v_why = scope.text_violation(" ".join([it["title"], it["wrong"], it["change"], it.get("outcome", ""), it["verify"].replace(GUT_RUNNER, "")]))      # the GUT runner is the ONE addons/ path a VERIFY must name (every xlite test VERIFY does)
        if v_why:
            row.reject("banned-path" if v_why.split(":")[0] in ("banned", "vendored", "protected") else "out-of-scope")
            continue
        nv = normalize_verify(it["verify"], fset)
        if nv != it["verify"]:
            it["verify"] = nv                            # same command, repo-dialect spelling (venv pytest, backend/ prefix): still checked by the strict allow-list right below
            row.d["normalized"] = int(row.d.get("normalized", 0)) + 1
        d_why = verify_dialect_reason(it["verify"])
        if d_why:
            row.reject(d_why)                            # the VERIFY runs on this box: a closed allow-list, checked before anything else reads the item's text
            continue
        if it["file"] not in ctx_env["shown"]:
            row.reject("file-not-shown")                 # the quote must come from a file the model was actually shown (a quote from an unseen file is recalled, not read)
            continue
        prose = " ".join([it["title"], it["wrong"], it["change"], it.get("outcome", ""), it["verify"]])
        if any(prose_denied(it[k]) for k in ("title", "wrong", "change") + (("outcome",) if "outcome" in it else ())):
            row.reject("prose-denied")                   # non-ASCII, URL / markup / encoded blob, or a 'your new task' phrase in the text the planner will read
            continue
        if steering(prose) or steering(it["sym"]) or steering(it["quote"], code=True):
            row.reject("protected-name")                 # prompt-injection / steering text: title, claim, change, VERIFY, symbol AND quoted lines go verbatim into the roadmap line and the planner prompt (reviewer findings 3 + rev2)
            continue
        if undeclared_paths(prose, it["file"], fset):
            row.reject("undeclared-path")
            continue
        text = read_text(os.path.join(snap, it["file"]))
        if not symbol_ok(it["sym"], text):
            row.reject("symbol-missing")
            continue
        ok, quote, line_no = locate_quote(it["quote"], text)
        if not ok:
            row.reject("quote-missing")
            continue
        if quote_trivial(quote):
            row.reject("quote-trivial")
            continue
        in_sym, why_sym = quote_in_symbol(it["file"], text, it["sym"], quote, ctx_env["lens"])
        if not in_sym:
            row.reject(why_sym)                          # a real quote at the wrong symbol proves nothing about the claim (reviewer finding 4)
            continue
        it["quote"], it["line"] = quote, line_no
        span_src = span_text(text, symbol_spans(it["file"], text, it["sym"])) or text
        c_why = claim_reason(it, ctx_env["lens"], span_src, ctx_env) or contradicted_by_quote(it, ctx_env["lens"])
        if c_why:
            row.reject(c_why)
            continue
        if ctx_env["lens"] == FEATURE_LENS:
            fr = feature_reason(it, ctx_env)
            if fr:
                row.reject(fr)
                continue
        if AUTH_CLAIM_RE.search(it["title"] + " " + it["wrong"]) and declared_public(it, text, ctx_env):
            row.reject("declared-public")                # the repo itself declares this route public / anonymous (a policy map, a test, the docs): 'missing auth' is the design
            continue
        it["span_src"] = span_src
        if ctx_env["lens"] == "test-gaps" and UNTESTED_CLAIM_RE.search(it["title"] + " " + it["wrong"]) and covered_by_tests(it["file"], text, it["sym"], ctx_env):
            row.reject("already-tested")                 # a test names the symbol, imports the module or requests its routes: the 'untested' claim is false
            continue
        s_why = static_verify_reason(it["verify"], ctx_env["lens"], it["quote"])
        if s_why:
            row.reject(s_why)
            continue
        if verify_unanchored(it["verify"], it["change"], it["quote"]):
            row.reject("verify-unanchored")
            continue
        dup = duplicate_reason(it, ctx_env["corpus"], ctx_env["subjects"], ctx_env["claims"], topical_open=ctx_env["lens"] == FEATURE_LENS)
        if dup:
            row.reject(dup)
            continue
        if dup == "" and ctx_env["lens"] == FEATURE_LENS:
            dup = feature_concept_dup(it, ctx_env)
        if dup:
            row.reject(dup)
            continue
        pk = parked_reason(it, ctx_env.get("parked") or []) if ctx_env.get("landable") else ""
        if pk:
            row.reject(pk)                               # the fleet already parked this (route to CLAUDE): re-proposing it is a guaranteed non-landing
            continue
        l_why = landable_reason(it, text, ctx_env["lens"]) if ctx_env.get("landable") else ""
        if l_why:
            row.reject(l_why)
            continue
        vkey = (it["file"], norm_ws(it["verify"]))
        if vkey in pass_seen["verify"] or any(f == it["file"] and (tw & words(it["title"])) and len(tw & words(it["title"])) / float(len(tw | words(it["title"])) or 1) >= 0.5 for f, tw in pass_seen["titles"]):
            row.reject("duplicate-in-pass")              # same file + same VERIFY (the utcnow trio) or same file + near-identical title: one item, not three
            continue
        pass_seen["verify"].add(vkey)
        pass_seen["titles"].append((it["file"], words(it["title"])))
        it["snap_files"] = fset
        survivors.append(it)
    if not survivors:
        return []
    # 1) the validator the Claude job and the local research use (format, mechanical-gap, duplicate titles, near-duplicates, length, cites a path)
    rm_path = os.path.join(OVN_DIR, "roadmap", repo + ".md")
    rlines = [roadmap_line(it, it["line"]) for it in survivors]
    accepted_titles, rejects = run_validator(rlines, rm_path)
    if accepted_titles is None:
        for _ in survivors:
            row.reject("validator-unavailable")
        return []
    keep = []
    for it, rl in zip(survivors, rlines):
        if norm_title(it["title"]) in accepted_titles:
            it["roadmap_line"] = rl
            keep.append(it)
            continue
        reason = next((r for r, ln in rejects if it["title"][:60] in ln or rl[:80] in ln), "rejected")
        row.reject("validator:" + re.sub(r"[^a-z-]+", "-", reason.lower()).strip("-")[:30])
    survivors, keep = keep, []
    # 2) the intake lint on the backlog-shaped line
    for it in survivors:
        tl = render_t_line(repo, it, fset)
        why, tl2 = lint_reason(tl, ctx_env["ctx"], scope.banned)
        if why:
            row.reject(why)
            continue
        it["t_line"] = tl2
        keep.append(it)
    if not keep:
        return []
    # 3) RED before: the VERIFY must fail on the snapshot
    verdicts = run_redcheck(repo, [it["t_line"] for it in keep], ctx_env["work"], row)
    out = []
    for i, it in enumerate(keep):
        if verdicts is None or i not in verdicts:
            row.reject("redcheck-no-sandbox" if row.d.get("sandbox") == "unavailable" else "redcheck-unavailable")
            continue
        v, sub = verdicts[i]
        it["red"] = "%s%s" % (v, ("/" + sub) if sub else "")
        if v == "red":
            if sub == "new-target" and ctx_env["lens"] != "test-gaps":
                it["roadmap_line"] = it["roadmap_line"].replace("- [ ] [P3] [ready]", "- [ ] [P4] [ready]", 1)     # red only because the test file does not exist yet: it proves nothing about the claimed defect -> lowest priority (reviewer minor 6)
                it["red"] += "/demoted-P4"
            out.append(it)
        elif v == "passes-before":
            row.reject("verify-already-green")
        elif v == "no-verify":
            row.reject("no-verify")
        else:
            row.reject("verify-bad-spec:%s" % (sub or "unknown"))
    return out


# ------------------------------------------------------------------------------------------------ skeptic pass (one model call that tries to REFUTE the survivors)
SKEPTIC_MARK = "SKEPTICAL AUDIT"


SKEPTIC_FEATURE_NOTE = ("FEATURE REPORTS (lens feature-ideation): each report proposes NEW behaviour instead of a defect. Read `claim` as the stated GAP (what the code does not do today). real=true ONLY when the SOURCE shows the behaviour is "
                        "really absent (not handled elsewhere in the source), a realistic user or client would value it, and the proposed change is small, self-contained and fits what the source does; real=false for a gap the product "
                        "owner would reasonably not want, a rename or helper in disguise, or a change that needs another file, schema or authentication work.\n\n")


def skeptic_prompt(repo, lens, items):
    blocks = []
    for i, it in enumerate(items, 1):
        src = it.get("span_src") or ""
        src = src if len(src) <= 7000 else src[:7000] + "\n[... cut ...]"
        blocks.append("REPORT %d\n  title: %s\n  file: %s\n  symbol: %s\n  claim: %s\n  quoted lines: %s\n  proposed change: %s\n  verify command: %s\n  SOURCE of %s (the code the report is about):\n%s\n=== END REPORT %d ===" % (
            i, it["title"], it["file"], it["sym"], it["wrong"], one_line(it["quote"], 400), it["change"], it["verify"], it["sym"], src, i))
    return ("%s. You audit defect reports that a junior model wrote about the repo %s (lens: %s). Reports like these are often WRONG: the claim is false for the code shown, the code is already handled, the case cannot occur "
            "for the types or callers involved, the fix would break a caller or a convention, or the effect is theoretical. A wrong report costs a coder cycle and a revert, so your DEFAULT is to refute.\n"
            "For EACH report decide `real`: true ONLY when ALL hold: (1) the claim is literally true of the SOURCE shown; (2) the quoted lines are what the claim is about; (3) a realistic caller or user hits the problem "
            "(not a contrived input); (4) the proposed change fixes exactly that and would not break callers, tests, types or conventions; (5) it is not already handled elsewhere in the shown source; (6) the claim does NOT rest on outside knowledge of how a third-party API, SDK, library or engine behaves (field names, parameters, defaults, return values) that the SOURCE does not show: "
            "you cannot verify that from here, so answer real=false.\n\n%s\n\n"
            "%s"
            "Do NOT think out loud: your whole reply is the JSON below, nothing before or after it, and each reason is at most 25 words.\n"
            "{\"verdicts\": [{\"id\": 1, \"real\": true, \"reason\": \"<=25 words\"}, ...]} with one entry per report.") % (SKEPTIC_MARK, repo, lens, "\n\n".join(blocks), SKEPTIC_FEATURE_NOTE if lens == FEATURE_LENS else "")


def parse_verdicts(reply, n):
    obj = extract_json(reply)
    if isinstance(obj, dict):
        obj = obj.get("verdicts", obj.get("results"))
    if not isinstance(obj, list):
        return None
    out = {}
    for v in obj:
        if not isinstance(v, dict):
            continue
        try:
            i = int(v.get("id"))
        except (TypeError, ValueError):
            continue
        real = v.get("real")
        real = real if isinstance(real, bool) else str(real).strip().lower() in ("true", "yes")
        if 1 <= i <= n:
            out[i] = (real, one_line(v.get("reason"), 200))
    return out


def skeptic_filter(repo, lens, items, stats, row):
    """-> the items the skeptic could not refute. Fail CLOSED: an unparseable verdict list (after one repair retry) or a missing verdict drops the item. ModelDown propagates (the caller records an error pass)."""
    if not items:
        return []
    msgs = [{"role": "user", "content": skeptic_prompt(repo, lens, items)}]
    reply = call_model(msgs, 1200, 300, stats, temperature=0.0)
    verdicts = parse_verdicts(reply, len(items))
    if verdicts is None:
        reply2 = call_model(msgs + [{"role": "assistant", "content": reply[:4000]}, {"role": "user", "content": "Not valid JSON of the required shape. Resend ONLY {\"verdicts\": [...]} with reasons of at most 25 words."}], 1200, 300, stats, temperature=0.0)
        verdicts = parse_verdicts(reply2, len(items))
    keep = []
    notes = row.d.setdefault("skeptic", [])
    for i, it in enumerate(items, 1):
        if verdicts is None:
            row.reject("skeptic-unparseable")
            continue
        real, why = verdicts.get(i, (False, "no verdict"))
        row.cur = it["title"]
        notes.append("%s: %s - %s" % (it["title"][:60], "real" if real else "refuted", why))
        if real:
            keep.append(it)
        else:
            row.reject("skeptic-refuted")
    return keep


# ------------------------------------------------------------------------------------------------ critic (second, independent Qwen opinion)
CRITIC_POS = ("real_problem", "scoped_s_m", "verify_discriminates", "not_dup_cosmetic", "within_27b")
CRITIC_HARD_MIN = 3          # a positive dimension scoring below this (1-5 scale) is a hard fail
CRITIC_RISK_MAX = 3          # risk is 1 (safe) .. 5 (dangerous); above this is a hard fail


def critic_mode():
    m = (os.environ.get("OVN_QWEN_CRITIC") or "shadow").strip().lower()
    return m if m in ("off", "shadow", "on") else "shadow"


def item_hash(it):
    return hashlib.sha1(("%s|%s|%s|%s" % (it["title"], it["file"], it["sym"], norm_ws(it["quote"])[:200])).encode()).hexdigest()[:16]


def evidence_window(snap, it, radius=10):
    lines = read_text(os.path.join(snap, it["file"])).split("\n")
    n = int(it.get("line") or 1)
    lo, hi = max(0, n - 1 - radius), min(len(lines), n - 1 + radius + 8)
    return "\n".join("%d| %s" % (i + 1, lines[i]) for i in range(lo, hi))


def build_critic_prompt(repo, it, snap):
    """FRESH context: the item as written, the verified evidence (quote + code window from the snapshot + red-before result), an AGENTS.md summary. Nothing from the explorer's prompts or reasoning."""
    return ("You are an independent, skeptical reviewer deciding whether ONE proposed work item is worth giving to a small autonomous coding model (a local 27B that implements one item at a time, "
            "gated by the repo's tests). You did not write the item. Judge only from the evidence below. REPO: %s.\n\n"
            "REPO RULES (AGENTS.md summary):\n%s\n\n"
            "PROPOSED ITEM:\n  title: %s\n  file: %s\n  symbol: %s\n  size: %s   tier: %s\n  what_is_wrong: %s\n  proposed_change: %s\n  verify: %s\n\n"
            "VERIFIED EVIDENCE (mechanically checked): the quoted lines exist verbatim in %s line %s:\n<<<\n%s\n>>>\nSurrounding code from the snapshot:\n<<<\n%s\n>>>\n"
            "Red-before check: the verify command was RUN on this code and it %s (it must fail now and pass once the change is made).\n\n"
            "RUBRIC - score every dimension as an integer 1 (worst) to 5 (best), except risk:\n"
            "  real_problem          the evidence shows a real defect or gap that a user or caller would hit (not speculation, not style)\n"
            "  scoped_s_m            the change is genuinely S/M sized and bounded for a 27B (one function or 2-3 small edits, no cross-cutting redesign)\n"
            "  verify_discriminates  the verify command fails on the current code for the RIGHT reason and would pass only once the described fix is made (not already true, not trivially satisfiable)\n"
            "  not_dup_cosmetic      NOT a duplicate, rename, formatting change, churn, dead-helper creation or test of a trivial getter\n"
            "  within_27b            NOT beyond a 27B model (no deep design judgement, no unfamiliar framework internals, no multi-service change)\n"
            "  risk                  1 (safe, local) .. 5 (could break production behaviour or security); higher is WORSE\n"
            "Approve ONLY if every dimension is 3 or better and risk is 3 or lower and you would genuinely want this landed.\n"
            "Reply with ONLY this JSON object: {\"scores\": {\"real_problem\": n, \"scoped_s_m\": n, \"verify_discriminates\": n, \"not_dup_cosmetic\": n, \"within_27b\": n, \"risk\": n}, "
            "\"approve\": true|false, \"reasons\": [\"one short reason\", ...]}") % (
        repo, agents_excerpt(snap)[:2500], it["title"], it["file"], it["sym"], it.get("size", "?"), it.get("tier", "?"), it["wrong"], it["change"], it["verify"],
        it["file"], it.get("line", "?"), it["quote"], evidence_window(snap, it), it.get("red", "red"))


def parse_critique(reply):
    """-> dict(scores, approve, reasons) or None when the reply is not the required shape."""
    obj = extract_json(reply)
    if not isinstance(obj, dict):
        return None
    sc = obj.get("scores") if isinstance(obj.get("scores"), dict) else obj
    scores = {}
    for k in CRITIC_POS + ("risk",):
        v = sc.get(k)
        if isinstance(v, bool) or not isinstance(v, (int, float)) or not 1 <= v <= 5:
            return None
        scores[k] = v
    ap = obj.get("approve")
    if not isinstance(ap, bool):
        return None
    rs = obj.get("reasons")
    reasons = [str(x)[:200] for x in rs][:5] if isinstance(rs, list) else ([str(rs)[:200]] if rs else [])
    return {"scores": scores, "approve": ap, "reasons": reasons}


def hard_fails(scores):
    out = ["%s<%d" % (k, CRITIC_HARD_MIN) for k in CRITIC_POS if scores[k] < CRITIC_HARD_MIN]
    if scores["risk"] > CRITIC_RISK_MAX:
        out.append("risk>%d" % CRITIC_RISK_MAX)
    return out


def critic_sample(prompt, temperature, seed, cstats, down):
    """One independent critique -> record {temp, seed, status ok|malformed|error, verdict approve|reject|error, scores, reasons, score}."""
    rec = {"temp": temperature, "seed": seed, "status": "ok", "verdict": "error", "scores": None, "reasons": [], "score": None}
    if down["v"]:
        rec["status"], rec["reasons"] = "error", ["critic skipped: model unavailable earlier in this pass"]
        return rec
    left = (down["deadline"] - time.time()) if down.get("deadline") else CRITIC_TIMEOUT
    if left < 1:
        rec["status"], rec["reasons"] = "error", ["critic skipped: total time budget spent"]
        return rec
    try:
        reply = call_model([{"role": "user", "content": prompt}], 700, min(CRITIC_TIMEOUT, left), cstats, temperature=temperature, seed=seed, max_calls=CRITIC_MAX_CALLS)
    except ModelDown as e:
        down["v"] = True
        rec["status"], rec["reasons"] = "error", ["critic call failed: %s" % e]
        return rec
    c = parse_critique(reply)
    if c is None:
        rec["status"], rec["reasons"] = "malformed", ["critic reply was not the required JSON"]
        return rec
    hf = hard_fails(c["scores"])
    rec["scores"], rec["reasons"] = c["scores"], c["reasons"] + (["hard-fail: " + ",".join(hf)] if hf else [])
    rec["score"] = sum(c["scores"][k] for k in CRITIC_POS) - c["scores"]["risk"]
    rec["verdict"] = "approve" if (c["approve"] and not hf) else "reject"
    return rec


def combine_samples(samples):
    """-> (verdict approve|reject|disagree|error, score). Approve needs BOTH; one approve + one reject is a disagreement (= reject); an unusable sample with no decisive reject is an error."""
    vs = [s["verdict"] for s in samples]
    if all(v == "approve" for v in vs):
        return "approve", sum(s["score"] for s in samples) / float(len(samples))
    if "approve" in vs and "reject" in vs:
        return "disagree", 0.0
    if "reject" in vs:
        return "reject", 0.0
    return "error", 0.0


def critique_item(repo, it, snap, cstats, down):
    prompt = build_critic_prompt(repo, it, snap)
    samples = [critic_sample(prompt, t, sd, cstats, down) for t, sd in CRITIC_SAMPLES]
    verdict, score = combine_samples(samples)
    reasons = []
    for s in samples:
        for r in s["reasons"]:
            if r not in reasons:
                reasons.append(r)
    return {"verdict": verdict, "score": round(score, 2), "samples": samples, "reasons": reasons[:6]}


CRITIC_AUDIT_MAX_BYTES = int(_env_num("OVN_QE_CRITIC_AUDIT_MAX_MB", 8, float) * 1048576)


def critic_audit(repo, lens, mode, items, dry):
    """Append-only state/qwen_critic.jsonl: one line per critiqued item (never written under --dry-run). Rotated to qwen_critic.jsonl.1 past OVN_QE_CRITIC_AUDIT_MAX_MB (8)."""
    if dry:
        return
    try:
        ap = os.path.join(OVN_DIR, "state", "qwen_critic.jsonl")
        try:
            if os.path.getsize(ap) > CRITIC_AUDIT_MAX_BYTES:
                os.replace(ap, ap + ".1")
        except OSError:
            pass
        with open(ap, "a") as f:
            for it in items:
                c = it["critic"]
                f.write(json.dumps({"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "repo": repo, "lens": lens, "mode": mode, "item_hash": item_hash(it),
                                    "title": it["title"], "file": it["file"], "verdict": c["verdict"], "score": c["score"], "outcome": c.get("outcome", ""), "reasons": c["reasons"],
                                    "samples": c["samples"]}) + "\n")
    except OSError:
        pass


def apply_critic(repo, lens, items, snap, row, mode, topn, dry, stats, budget=None):
    """The critic stage (mode shadow|on). -> items that go on to the append. shadow keeps ALL items (verdicts only logged); on keeps the approved ones, best score first, at most topn.
    `budget` = hard total wall seconds for all critic calls of the pass (items not judged by then get verdict 'error': shadow keeps them, on rejects them)."""
    cstats = {"calls": 0, "ptok": 0, "ctok": 0}
    down = {"v": False, "deadline": (time.time() + budget) if budget else None}
    cd = {"mode": mode, "evaluated": 0, "approved": 0, "rejected": 0, "disagree": 0, "errors": 0, "cut": 0, "reject_rate": 0.0}
    for it in items:
        it["critic"] = critique_item(repo, it, snap, cstats, down)
        v = it["critic"]["verdict"]
        cd["evaluated"] += 1
        cd[{"approve": "approved", "reject": "rejected", "disagree": "disagree", "error": "errors"}[v]] += 1
    stats["calls"] += cstats["calls"]
    stats["ptok"] += cstats["ptok"]
    stats["ctok"] += cstats["ctok"]
    judged = cd["approved"] + cd["rejected"] + cd["disagree"]
    cd["reject_rate"] = round((cd["rejected"] + cd["disagree"]) / float(judged), 3) if judged else 0.0
    if mode == "shadow":                                   # observe only: nothing is filtered, an unavailable critic is fail-open
        for it in items:
            it["critic"]["outcome"] = "shadow-" + it["critic"]["verdict"]
        keep = list(items)
    else:
        approved = sorted((it for it in items if it["critic"]["verdict"] == "approve"), key=lambda it: -it["critic"]["score"])
        keep = approved[:topn]
        cd["cut"] = len(approved) - len(keep)
        kept_ids = {id(it) for it in keep}
        for it in items:
            c = it["critic"]
            c["outcome"] = "accepted" if id(it) in kept_ids else ("cut-top-n" if c["verdict"] == "approve" else "rejected-" + c["verdict"])
            if id(it) not in kept_ids:
                row.cur = it["title"]
                row.reject({"approve": "critic-cut", "reject": "critic-reject", "disagree": "critic-disagree", "error": "critic-error"}[c["verdict"]])
    row.d["critic"] = cd
    row.d["critic_verdicts"] = [{"title": it["title"][:70], "verdict": it["critic"]["verdict"], "outcome": it["critic"].get("outcome", ""), "score": it["critic"]["score"], "reasons": it["critic"]["reasons"][:3]} for it in items]
    critic_audit(repo, lens, mode, items, dry)
    return keep


# ------------------------------------------------------------------------------------------------ append + commit, chain
def record_critic(repo, items, now):
    """Shadow verdicts that arrive AFTER the append: extra accepted.jsonl rows (slug + verdict) so the self-throttle still sees which landed items the critic approved."""
    try:
        with open(os.path.join(qdir(), "accepted.jsonl"), "a") as f:
            for it in items:
                if it.get("_written") and it.get("critic"):
                    feat = it["roadmap_line"].split("[ready] ", 1)[1]
                    f.write(json.dumps({"ts_epoch": now, "repo": repo, "slug": feat_slug(feat), "critic": it["critic"]["verdict"], "critic_score": it["critic"]["score"], "item_hash": item_hash(it)}) + "\n")
    except OSError:
        pass


def shadow_critic(repo, lens, items, snap, row, stats, now):
    """Shadow mode runs AFTER the append (the items are already committed and can never be lost or delayed by it), under a hard total budget; ANY failure of the critic is swallowed."""
    try:
        apply_critic(repo, lens, [it for it in items if it.get("_written")], snap, row, "shadow", CRITIC_TOPN, False, stats, budget=_env_num("OVN_QE_CRITIC_SHADOW_BUDGET_S", 120, float))
    except Exception as e:
        row.d["note"] = (row.d["note"] + " critic-shadow-error:%s" % type(e).__name__).strip()
    record_critic(repo, items, now)


def feature_starving(repo, roadmap_text):
    """The repo is starving: no [ready] roadmap feature AND the open doable backlog (T1-T3, not parked) is below the enough-fuel threshold (OVN_QE_FEATURE_FUEL, default 15 = queue_refill's MIN_DOABLE)."""
    elig = load_module(os.path.join(HERE, "ovn_backlog_eligibility.py"), "qe_elig")
    parked = elig.is_parked if elig is not None and hasattr(elig, "is_parked") else (lambda ln: bool(PARKED_RE.search(ln)))
    return QF.is_starving(ready_count(roadmap_text), QF.doable_backlog(read_text(os.path.join(OVN_DIR, "backlog", repo + ".md")), parked))


DUP_REASONS = {"duplicate-title", "already-covered", "near-duplicate", "recently-committed", "already-proposed", "duplicate-in-pass", "feature-already-proposed", "feature-duplicate-concept"}


def feature_report(raw_items, accepted, row):
    """One record per proposed item: {title, file, symbol, status accepted|rejected, reasons, raw}. Reasons come from the pass trace (every reject is recorded with the item title)."""
    reasons = {}
    for t in row.trace or []:
        reasons.setdefault(t["title"], []).append(t["reason"])
    acc = {it["title"] for it in accepted}
    out = []
    for r in raw_items or []:
        if not isinstance(r, dict):
            continue
        title = one_line(r.get("title"), 110)
        status = "accepted" if title in acc else "rejected"
        keep = ("title", "file", "symbol", "evidence_quote", "current_gap", "what_is_wrong", "user_outcome", "proposed_change", "verify", "size", "tier")
        out.append({"title": title, "file": str(r.get("file") or ""), "symbol": str(r.get("symbol") or ""), "status": status,
                    "reasons": [] if status == "accepted" else (reasons.get(title) or ["cut-by-max-items"]), "raw": {k: r[k] for k in keep if k in r}})
    return out


def feature_seen_rows(report, accepted, row):
    """What the next pass must not propose again: items that passed every gate, and items rejected as duplicates."""
    acc = {it["title"] for it in accepted}
    rows = []
    for rec in report:
        dup = rec["status"] == "rejected" and any(x in DUP_REASONS or (x.startswith("validator:") and "dup" in x) for x in rec["reasons"])
        if rec["title"] in acc or dup:
            rows.append({"title": rec["title"], "file": rec["file"], "symbol": rec["symbol"], "why": "accepted" if rec["title"] in acc else "duplicate"})
    return rows


def write_feature_shadow(repo, sha, picked, row, report, accepted, now):
    """state/qwen_explore/feature_shadow.jsonl (rotated past 8 MB): one `item` line per proposed item (accepted ones carry the roadmap line, red-before result, skeptic notes and critic verdict) and one `pass` line with the
    histogram. NOTHING is written to the roadmap or the backlog and the planner is not chained. -> number of would-be (accepted) items."""
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    pass_id = "%s-%s-%d" % (repo, ts, os.getpid())
    by_title = {it["title"]: it for it in accepted}
    recs = []
    for rec in report:
        r = {"type": "item", "pass": pass_id, "ts": ts, "repo": repo, "sha": sha[:10], "title": rec["title"], "file": rec["file"], "symbol": rec["symbol"], "status": rec["status"], "reasons": rec["reasons"], "raw": rec["raw"]}
        it = by_title.get(rec["title"])
        if it:
            r["roadmap_line"] = it.get("roadmap_line", "")
            r["red"] = it.get("red", "")
            r["critic"] = {k: v for k, v in (it.get("critic") or {}).items() if k in ("verdict", "score", "outcome", "reasons")}
        recs.append(r)
    recs.append({"type": "pass", "pass": pass_id, "ts": ts, "repo": repo, "sha": sha[:10], "files": picked, "proposed": row.d["proposed"], "accepted": len(accepted), "rejected": row.d["rejected"],
                 "skeptic": row.d.get("skeptic", []), "critic": row.d.get("critic"), "calls": row.d["calls"], "mode": "shadow"})
    QF.append_jsonl_rotating(os.path.join(qdir(), "feature_shadow.jsonl"), recs)
    return len(accepted)


def ready_count(text):
    return len(re.findall(r"^- \[ \] \[P[1-4]\] \[ready\]", text, re.M))


def append_and_commit(repo, items, lens, sha):
    """flock on the planner lock (the planner edits roadmap files with sed -i), re-read, de-duplicate once more, atomic write, commit ONLY roadmap/<repo>.md. -> (n_written, note)."""
    rm = os.path.join(OVN_DIR, "roadmap", repo + ".md")
    lock = Lock(os.path.join(OVN_DIR, "state", "ovn_planner.lock"))
    deadline = time.time() + _env_num("OVN_QE_ROADMAP_LOCK_S", 240)
    while not lock.acquire():
        if time.time() > deadline:
            return 0, "roadmap-lock-timeout"
        time.sleep(2)
    try:
        cur = read_text(rm)
        have = {norm_title(m.group(1)) for m in re.finditer(r"^- \[[ xX]\] \[P[1-4]\] \[[a-z-]+\] ([^—]+?)(?: — |$)", cur, re.M)}
        fresh = [it for it in items if norm_title(it["title"]) not in have]
        if not fresh:
            return 0, "already-present"
        hdr = "\n## Qwen explore %s (ovn_qwen_explore.py; lens %s; %d item(s) proposed by the local 27B; file, symbol and quote verified in the snapshot %s, VERIFY red-before; review)\n" % (
            time.strftime("%Y-%m-%d %H:%M"), lens, len(fresh), sha[:10])
        sep = "" if cur.endswith("\n") or not cur else "\n"
        atomic_write(rm, cur + sep + hdr + "\n".join(it["roadmap_line"] for it in fresh) + "\n")
        ident = ["-c", "user.name=shrike-fleet", "-c", "user.email=22970726+markhint22@users.noreply.github.com"]
        for attempt in range(2):
            subprocess.run(["git"] + ident + ["add", "roadmap/%s.md" % repo], cwd=OVN_DIR, capture_output=True, timeout=60)
            r = subprocess.run(["git"] + ident + ["commit", "-q", "-m", "chore(roadmap): qwen-explore %s - %d verified item(s) for %s (%s)" % (lens, len(fresh), repo, (QF.FEATURE_TAG if lens == FEATURE_LENS else SRC_TAG).strip("[]")), "--", "roadmap/%s.md" % repo],
                               cwd=OVN_DIR, capture_output=True, timeout=60)
            if r.returncode == 0:
                break
            time.sleep(3)
        for it in fresh:
            it["_written"] = True
        return len(fresh), "committed" if r.returncode == 0 else "written-not-committed"
    finally:
        lock.release()


def record_accepted(repo, items, lens, now):
    """accepted.jsonl bookkeeping AFTER the commit: an OSError here (disk full) must not turn a pass that already landed its items into an 'error' with no ledger."""
    try:
        with open(os.path.join(qdir(), "accepted.jsonl"), "a") as f:
            for it in items:
                if not it.get("_written"):
                    continue
                feat = it["roadmap_line"].split("[ready] ", 1)[1]
                f.write(json.dumps({"ts_epoch": now, "repo": repo, "lens": lens, "title": it["title"], "file": it["file"], "symbol": it["sym"], "slug": feat_slug(feat),
                                    "sig": hashlib.sha1(("%s|%s|%s" % (it["file"], it["sym"], norm_ws(it["quote"])[:160])).encode()).hexdigest()[:16],
                                    "critic": (it.get("critic") or {}).get("verdict", ""), "critic_score": (it.get("critic") or {}).get("score"), "item_hash": item_hash(it)}) + "\n")
    except OSError:
        pass


def _bash(script, *args, env=None, timeout=300, log=None):
    logf = open(log, "a") if log else subprocess.DEVNULL
    try:
        return subprocess.run(["bash", script] + list(args), cwd=OVN_DIR, env=env, stdout=logf, stderr=subprocess.STDOUT, timeout=timeout).returncode
    except (OSError, subprocess.SubprocessError):
        return -1
    finally:
        if log:
            logf.close()


def chain(repo, n_new, slugs):
    """Make the new [ready] features runnable NOW: planner (decompose; same flock + dedupe as the cron / queue passes), queue_refill (bounded), supply_kick (wakes the idle wait)."""
    notes = []
    planner = find_script(os.environ.get("OVN_QE_PLANNER"), os.path.join(OVN_DIR, "ovn_planner.sh"))
    refill = find_script(os.environ.get("OVN_QE_REFILL"), os.path.join(OVN_DIR, "queue_refill.sh"))
    plog = os.path.join(OVN_DIR, "logs", "ovn_planner.log")
    os.makedirs(os.path.join(OVN_DIR, "logs"), exist_ok=True)
    rm = os.path.join(OVN_DIR, "roadmap", repo + ".md")
    n_dec, tries = 0, 0
    max_feats, max_tries, gap = _env_num("OVN_QE_CHAIN_MAX_FEATS", 3), _env_num("OVN_QE_CHAIN_TRIES", 6), _env_num("OVN_QE_CHAIN_RETRY_S", 15)
    if planner:
        while n_dec < max_feats and tries < max_tries and ready_count(read_text(rm)) > 0:
            tries += 1
            before, off = ready_count(read_text(rm)), (os.path.getsize(plog) if os.path.exists(plog) else 0)
            _bash(planner, repo, timeout=300, log=plog)
            tail = ""
            try:
                with open(plog, "rb") as f:
                    f.seek(off)
                    tail = f.read().decode("utf-8", "replace")
            except OSError:
                pass
            if ready_count(read_text(rm)) < before:
                n_dec += 1
                continue
            if "no planning needed" in tail:                     # the backlog is healthy: the new features wait for the next planner pass
                notes.append("backlog-full")
                break
            if "already running" in tail:
                time.sleep(gap)                                  # the cron / queue-pass planner holds the lock: wait it out and retry
                continue
            break                                                # the planner ran and declined (miss counters, needs-decompose, paused): do not hammer it
        notes.append("planner x%d decomposed %d" % (tries, n_dec))
    else:
        notes.append("no-planner")
    if refill:
        rc = _bash(refill, repo, env=dict(os.environ, MIN_DOABLE="15"), timeout=180, log=os.path.join(OVN_DIR, "logs", "queue_refill.log"))
        notes.append("refill rc=%s" % rc)
    try:
        open(os.path.join(OVN_DIR, "state", "supply_kick"), "a").close()
        os.utime(os.path.join(OVN_DIR, "state", "supply_kick"), None)
    except OSError:
        pass
    return ", ".join(notes)


# ------------------------------------------------------------------------------------------------ main
def finish(row, t0, dry, line_extra=""):
    row.d["secs"] = int(time.time() - t0)
    d = row.d
    dbg = os.environ.get("OVN_QE_DEBUG_DIR")                    # evidence runs: which item was dropped for which reason
    if dbg and row.trace:
        try:
            os.makedirs(dbg, exist_ok=True)
            with open(os.path.join(dbg, "trace.jsonl"), "a") as f:
                for t in row.trace:
                    f.write(json.dumps({"repo": d["repo"], "lens": d["lens"], "title": t["title"], "reason": t["reason"]}) + "\n")
        except OSError:
            pass
    rej = ",".join("%s:%d" % kv for kv in sorted(d["rejected"].items(), key=lambda kv: -kv[1])) or "-"
    line = "%s %s lens=%s result=%s files=%d proposed=%d accepted=%d rejected={%s} calls=%d tok=%d/%d %ds%s%s" % (
        time.strftime("%Y-%m-%d %H:%M:%S"), d["repo"], d["lens"] or "-", d["result"], len(d["files"]), d["proposed"], d["accepted"], rej, d["calls"], d["ptok"], d["ctok"], d["secs"],
        (" note=" + d["note"]) if d["note"] else "", line_extra)
    cd = d.get("critic")
    if cd:
        line += " critic=%s eval=%d approved=%d rejected=%d disagree=%d errors=%d cut=%d critic_reject_rate=%.0f%%" % (
            cd["mode"], cd["evaluated"], cd["approved"], cd["rejected"], cd["disagree"], cd["errors"], cd["cut"], 100.0 * cd["reject_rate"])
    if dry:
        line += " [DRY-RUN: nothing written]"
    else:
        try:
            os.makedirs(os.path.join(OVN_DIR, "logs"), exist_ok=True)
            with open(os.path.join(OVN_DIR, "logs", "qwen_explore.log"), "a") as f:
                f.write(line + "\n")
            with open(os.path.join(OVN_DIR, "state", "qwen_explore.jsonl"), "a") as f:
                f.write(json.dumps(d) + "\n")
        except OSError:
            pass
    print(line)
    return 0


def main(argv):
    if len(argv) < 2 or argv[1].startswith("-"):
        print("usage: ovn_qwen_explore.py <repo> [--dry-run] [--force] [--lens NAME] [--from-queue] [--no-chain] [--max-items N]")
        return 0
    repo, flags = argv[1], argv[2:]
    dry = "--dry-run" in flags or os.environ.get("DRY_RUN") in ("1", "true", "yes")
    force = "--force" in flags
    forced_lens = flags[flags.index("--lens") + 1] if "--lens" in flags and flags.index("--lens") + 1 < len(flags) else None
    max_items = int(flags[flags.index("--max-items") + 1]) if "--max-items" in flags and flags.index("--max-items") + 1 < len(flags) else MAX_ITEMS
    t0 = time.time()
    try:                                          # the queue hook starts us from inside a live repo clone: never keep that as the working directory
        os.chdir(OVN_DIR if os.path.isdir(OVN_DIR) else os.path.expanduser("~"))
    except OSError:
        pass
    row = Row(repo)
    row.d["mode"] = "dry" if dry else ("queue" if "--from-queue" in flags else "manual")
    now = now_ts()
    if os.environ.get("OVN_QWEN_EXPLORE", "on") == "off":
        row.d["result"] = "skip-killswitch"
        if not dry:
            try:
                write_next(repo, now + 3600)
            except OSError:
                pass
        print("%s: OVN_QWEN_EXPLORE=off - skip" % repo)
        return 0
    clone = os.path.join(OVN_DIR, "repos", repo)
    rm = os.path.join(OVN_DIR, "roadmap", repo + ".md")
    if not (os.path.isdir(clone) and os.path.isfile(rm)):
        print("%s: no checkout or roadmap - skip" % repo)
        return 0
    cfg = REPO_CFG.get(repo, DEFAULT_CFG)
    if dry and os.environ.get("OVN_QE_CACHE_DIR"):
        LEDGER_ROOT[0] = os.environ["OVN_QE_CACHE_DIR"]
    tmp_cache = dry and not os.environ.get("OVN_QE_CACHE_DIR")
    tmp_cache_dir = tempfile.mkdtemp(prefix="qe-dry-") if tmp_cache else None      # the only dir this call may delete (never the caller-supplied OVN_QE_CACHE_DIR)
    cache_root = os.environ.get("OVN_QE_CACHE_DIR") or (tmp_cache_dir if dry else qdir())
    locks = [Lock(os.path.join(cache_root if dry else qdir(), "lock_global")), Lock(os.path.join(cache_root if dry else qdir(), "lock_%s" % repo))]
    got = []
    try:
        for lk in locks:
            if not lk.acquire():
                for g in got:
                    g.release()
                print("%s: another explorer pass holds the lock - skip" % repo)
                return 0
            got.append(lk)
        return _locked_main(repo, cfg, clone, rm, cache_root, row, flags, dry, force, forced_lens, max_items, t0, now)
    except Exception as e:                       # best-effort: never a traceback into the queue loop
        row.d["result"] = "error"
        row.d["note"] = ("internal: %s: %s" % (type(e).__name__, e))[:200]
        if not dry:
            try:
                write_next(repo, now_ts() + DEBOUNCE_ERR_S)
            except OSError:
                pass
        return finish(row, t0, dry)
    finally:
        for g in got:
            g.release()
        if tmp_cache_dir:
            shutil.rmtree(tmp_cache_dir, ignore_errors=True)


def _locked_main(repo, cfg, clone, rm, cache_root, row, flags, dry, force, forced_lens, max_items, t0, now):
    os.makedirs(qdir(), exist_ok=True) if not dry else None
    L = load_ledger(repo)
    today = today_str(now)
    if L["day"] != today:
        L["day"], L["day_count"] = today, 0
    if L.get("feature_day") != today:
        L["feature_day"], L["feature_day_count"] = today, 0
    # ---- gates
    paused, info = throttle_check(repo, now, dry)
    if paused and os.environ.get("OVN_QE_IGNORE_PAUSE") != "1":
        row.d["result"], row.d["note"] = "skip-paused", info
        if not dry:
            pf = read_json(os.path.join(qdir(), "paused_%s.json" % repo), {})
            write_next(repo, min(float(pf.get("until") or now + 3600), now + 3600))
        return finish(row, t0, dry)
    roadmap_text = read_text(rm)
    fmode = QF.feature_mode()
    feat_wanted = fmode != "off" and (forced_lens == FEATURE_LENS or (not forced_lens and feature_starving(repo, roadmap_text)))
    feat_avail = feat_wanted and (force or int(L["feature_day_count"]) < QF.max_per_day())
    bug_capped = (not force) and L["day_count"] >= MAX_PER_DAY
    if not force:
        if bug_capped and not feat_avail:
            row.d["result"], row.d["note"] = "skip-cap", "%d passes today" % L["day_count"]
            if not dry:
                write_next(repo, next_midnight(now))
            return finish(row, t0, dry)
        cool = COOLDOWN_PRODUCTIVE_S if L["last_accepted"] > 0 else COOLDOWN_EMPTY_S
        if L["last_pass_ts"] and now - L["last_pass_ts"] < cool:
            row.d["result"], row.d["note"] = "skip-cooldown", "%ds left" % int(cool - (now - L["last_pass_ts"]))
            if not dry:
                write_next(repo, L["last_pass_ts"] + cool)
            return finish(row, t0, dry)
        if ready_count(roadmap_text) >= READY_CAP:
            row.d["result"], row.d["note"] = "skip-enough-fuel", "%d [ready] features already queued" % ready_count(roadmap_text)
            if not dry:
                write_next(repo, now + 900)
            return finish(row, t0, dry)
        if gpu_busy():
            dp = os.path.join(qdir(), "gpu_defer_%s" % repo)
            n = int(read_text(dp) or 0) + 1 if not dry else 0
            if n <= 3:
                row.d["result"], row.d["note"] = "skip-gpu-busy", "defer %d/3" % n
                if not dry:
                    atomic_write(dp, str(n))
                    write_next(repo, now + 600)
                return finish(row, t0, dry)
        if not dry:
            try:
                os.unlink(os.path.join(qdir(), "gpu_defer_%s" % repo))
            except OSError:
                pass
    if sandbox_prefix(cache_root, cache_root) is None:        # preflight BEFORE any model call: no bwrap = no red-check = nothing could be accepted, so do not burn model calls, the lens or the file ledger
        row.d["result"], row.d["sandbox"] = "skip-no-sandbox", "unavailable"
        row.d["note"] = "sandbox-unavailable: bubblewrap missing/unusable - pass skipped before any model call (install bwrap or set OVN_QE_SANDBOX=off)"
        if not dry:
            sandbox_alert(repo)
            write_next(repo, now + 3600)
        return finish(row, t0, dry)
    lens, wait_until = pick_lens(cfg, L, now, forced_lens, feature=feat_avail, only_feature=bug_capped)
    if lens is None:
        row.d["result"], row.d["note"] = ("skip-bad-lens", forced_lens) if forced_lens else ("skip-lens-ttl", "all lenses covered within %dh" % (LENS_TTL_S // 3600))
        if not dry and not forced_lens:
            write_next(repo, wait_until)
        return finish(row, t0, dry)
    row.d["lens"] = lens
    stats = {"calls": 0, "ptok": 0, "ctok": 0}

    def sync_stats():
        row.d["calls"], row.d["ptok"], row.d["ctok"] = stats["calls"], stats["ptok"], stats["ctok"]

    # ---- snapshot (read-only)
    ref, sha = resolve_ref(clone)
    if not sha:
        row.d["result"], row.d["note"] = "error", "no ref to snapshot"
        if not dry:
            write_next(repo, now + DEBOUNCE_ERR_S)
        return finish(row, t0, dry)
    snap = make_snapshot(repo, clone, ref, sha, cfg, cache_root)
    row.d["sha"] = sha[:10]
    files = snapshot_files(snap)
    scope = Scope(cfg, snap)
    churn = churn_counts(clone, sha)
    landable = bool(cfg.get("landable")) and LANDABLE != "off"
    ffeat = lens == FEATURE_LENS
    Lc = dict(L, files=L["ffiles"]) if ffeat else L           # the feature lens keeps its own file ledger: a file shown to it is not 'covered' for the bug lenses
    cands = candidate_files(snap, files, scope, lens, Lc, churn, now, landable)
    relaxed = 0
    for lvl in (1, 2):                                          # small repos: fewer than 2 files for the lens -> try the repo's top-level modules, then drop the lens extension filter
        if len(cands) >= 2:
            break
        more = candidate_files(snap, files, scope, lens, Lc, churn, now, landable, relax=lvl)
        if len(more) > len(cands):
            cands, relaxed = more, lvl
    if relaxed and len(cands) >= 2:
        row.d["note"] = ("relaxed-files=%d" % relaxed)
    if len(cands) < 2:
        row.d["result"], row.d["note"] = "empty", "fewer than 2 candidate files for lens %s" % lens
        return _end_pass(repo, L, lens, [], row, t0, dry, now, 0, "")
    recent = [p for p, ts in sorted(Lc["files"].items(), key=lambda kv: -kv[1]) if now - ts < FILE_TTL_S]
    cand_paths = {c[0] for c in cands}
    vision = outline = ""
    if ffeat:
        vision = QF.build_vision(lambda q: read_text(os.path.join(snap, q)), files)
        outline = QF.build_outline(snap, [q for q in files if q.endswith(QF.OUTLINE_EXTS) and not scope.forbidden(q) and not is_test_path(q) and (scope.in_roots(q) or relaxed)])
    # ---- pass A: target files
    try:
        reply = call_model([{"role": "user", "content": select_files_prompt(repo, lens, cands, recent, (vision, outline) if ffeat else None)}], 500, 150, stats)
    except ModelDown as e:
        sync_stats()
        row.d["result"], row.d["note"] = "error", "model: %s" % e
        if not dry:
            write_next(repo, now_ts() + DEBOUNCE_ERR_S)
        return finish(row, t0, dry)
    picked = parse_file_pick(reply, cand_paths)
    fallback = 0
    if len(picked) < 2:                                 # the model named too few valid paths: fill deterministically (top churn not yet picked)
        for p in [c[0] for c in cands]:
            if p not in picked:
                picked.append(p)
                fallback += 1
            if len(picked) >= 4:
                break
    row.d["files"] = picked
    if fallback:
        row.d["note"] = ("%s fallback-files=%d" % (row.d["note"], fallback)).strip()
    # ---- pass B: items
    corpus = corpus_lines(repo, clone, sha, roadmap_text)
    subjects = recent_subjects(clone, sha)
    seen_root = LEDGER_ROOT[0] or qdir()
    fseen = QF.load_seen(seen_root, repo, now) if ffeat else []
    if ffeat:
        docs = load_budgeted(snap, picked, int(_env_num("OVN_QE_FEATURE_FILE_TOKENS", 14000) * CHARS_PER_TOKEN))
        prompt = build_feature_item_prompt(repo, cfg, snap, docs, corpus, subjects, scope, vision, outline, fseen, max_items)
    else:
        docs = load_budgeted(snap, picked, int(FILE_TOKENS * CHARS_PER_TOKEN))
        prompt = build_item_prompt(repo, lens, cfg, snap, docs, corpus, subjects, scope)
    msgs = [{"role": "user", "content": prompt}]
    raw_items = None
    try:
        reply = call_model(msgs, 3200, 420, stats, temperature=0.4 if ffeat else 0.2)
        raw_items = (parse_items_feature if ffeat else parse_items)(reply)
        if raw_items is None:                           # JSON repair retry (once)
            reply2 = call_model(msgs + [{"role": "assistant", "content": reply[:6000]},
                                        {"role": "user", "content": "That was not valid JSON of the required shape. Resend ONLY the JSON object {\"items\": [ ... ]} (double quotes, no comments, no trailing commas, no prose)."}], 3200, 420, stats)
            raw_items = (parse_items_feature if ffeat else parse_items)(reply2)
            row.d["note"] = (row.d["note"] + " json-repair-retry").strip()
    except ModelDown as e:
        sync_stats()
        row.d["result"], row.d["note"] = "error", ("model: %s" % e)
        if not dry:
            write_next(repo, now_ts() + DEBOUNCE_ERR_S)
        return finish(row, t0, dry)
    sync_stats()
    if not dry:
        try:
            _bash(find_script(os.path.join(OVN_DIR, "scripts", "ovn_log_tokens.sh")) or "/nonexistent", "qwen-explore", repo, str(stats["ptok"]), str(stats["ctok"]), env=dict(os.environ, OVERNIGHT_DIR=OVN_DIR), timeout=20)
        except Exception:
            pass
    if raw_items is None:
        row.d["result"], row.d["note"] = "empty", (row.d["note"] + " unparseable-json").strip()
        row.reject("unparseable-json")
        return _end_pass(repo, L, lens, picked, row, t0, dry, now, 0, "")
    row.d["proposed"] = len(raw_items)
    raw_items = raw_items[:max_items + 2]
    # ---- mechanical verification
    try:
        work = refresh_work(repo, snap, clone, cfg, cache_root)
    except Exception as e:
        row.d["result"], row.d["note"] = "error", "scratch copy failed: %s" % str(e)[:120]
        if not dry:
            write_next(repo, now_ts() + DEBOUNCE_ERR_S)
        return finish(row, t0, dry)
    rules = load_module(os.path.join(HERE, "ovn_spec_rules.py"), "qe_rules")
    ctx = rules.Ctx(clone, sha, banned=scope.banned) if rules is not None else None
    env = {"snap": snap, "files": files, "shown": set(picked), "scope": scope, "cfg": cfg, "lens": lens, "corpus": corpus, "subjects": subjects, "claims": accepted_claim_sigs(repo, now), "work": work, "ctx": ctx,
           "landable": landable, "parked": parked_lines(clone, sha, corpus) if landable else [], "relaxed": relaxed, "feature_seen": fseen}
    accepted = verify_items(repo, raw_items, env, row)[:max_items]
    if row.d.get("sandbox") == "unavailable" and not dry:
        sandbox_alert(repo)
    if accepted and os.environ.get("OVN_QE_SKEPTIC", "on") != "off":
        try:
            accepted = skeptic_filter(repo, lens, accepted, stats, row)
        except ModelDown as e:                          # an item nobody could double-check is not accepted
            sync_stats()
            row.d["result"], row.d["note"] = "error", ("model: %s" % e)
            if not dry:
                write_next(repo, now_ts() + DEBOUNCE_ERR_S)
            return finish(row, t0, dry)
        sync_stats()
    mode = critic_mode()
    feat_shadow = ffeat and fmode == "shadow"
    if feat_shadow and mode != "off" and not dry:
        mode = "shadow"                                           # the feature shadow batch keeps EVERY mechanically accepted item with its critic verdict (observe only) and runs the critic BEFORE the audit record
    if mode != "off" and accepted and (mode == "on" or dry or feat_shadow):          # shadow (non-dry) runs AFTER the append: it must never delay or lose an accepted item
        accepted = apply_critic(repo, lens, accepted, snap, row, mode, CRITIC_TOPN, dry, stats, budget=_env_num("OVN_QE_CRITIC_BUDGET_S", 600, float))
        sync_stats()
        cd = row.d["critic"]
        if mode == "on" and cd["errors"] and not accepted:        # fail-closed: nothing was judged usable; the items are simply proposed again on the next pass
            row.d["result"], row.d["note"] = "error", (row.d["note"] + " critic-unavailable (%d item(s) not judged; retry next pass)" % cd["errors"]).strip()
            if not dry:
                write_next(repo, now_ts() + DEBOUNCE_ERR_S)
            return finish(row, t0, dry)
    accepted = accepted[:max_items]
    row.d["accepted"] = len(accepted)
    row.d["result"] = "accepted" if accepted else "empty"
    freport = feature_report(raw_items, accepted, row) if ffeat else []
    if dry:
        print("%s lens=%s: proposed %d, accepted %d, rejected %s" % (repo, lens, row.d["proposed"], len(accepted), json.dumps(row.d["rejected"], sort_keys=True)))
        if ffeat:
            print("FEATURE files shown: %s%s" % (", ".join(picked), (" (relaxed=%d)" % relaxed) if relaxed else ""))
            for rec in freport:
                print("PROPOSED [%s] %s" % (rec["status"] if rec["status"] == "accepted" else "rejected: " + ",".join(rec["reasons"]), json.dumps(rec["raw"], sort_keys=True)))
            if LEDGER_ROOT[0]:                              # an evidence dry run that keeps its ledger (OVN_QE_CACHE_DIR) keeps the dup memory there too: the next dry run does not repeat these ideas
                QF.record_seen(seen_root, repo, feature_seen_rows(freport, accepted, row), now)
        for it in accepted:
            print("ACCEPTED [red=%s] %s" % (it["red"], it["roadmap_line"]))
        for note in row.d.get("skeptic", []):
            print("SKEPTIC " + note)
        for v in row.d.get("critic_verdicts", []):
            print("CRITIC %s (%s, score %s) %s | %s" % (v["verdict"], v["outcome"], v["score"], v["title"], " ; ".join(v["reasons"])))
        return _end_pass(repo, L, lens, picked, row, t0, dry, now, 0, "")
    if feat_shadow:
        n_shadow = write_feature_shadow(repo, sha, picked, row, freport, accepted, now)
        QF.record_seen(seen_root, repo, feature_seen_rows(freport, accepted, row), now)
        row.d["result"] = "shadow" if accepted else "empty"
        row.d["note"] = (row.d["note"] + " feature-shadow:%d" % n_shadow).strip()
        return _end_pass(repo, L, lens, picked, row, t0, dry, now, 0, " feature=shadow shadow_items=%d" % n_shadow)
    if ffeat and accepted and not dry:
        QF.record_seen(seen_root, repo, feature_seen_rows(freport, accepted, row), now)
    extra = ""
    written = 0
    if accepted:
        written, note = append_and_commit(repo, accepted, lens, sha)
        row.d["accepted"] = written
        row.d["note"] = (row.d["note"] + " roadmap:" + note).strip()
        if not written:
            row.d["result"] = "empty"
        else:
            record_accepted(repo, accepted, lens, now)
            row.d["slugs"] = [feat_slug(it["roadmap_line"].split("[ready] ", 1)[1]) for it in accepted if it.get("_written")]
    if written and "--no-chain" not in flags:
        # The ledger, the cooldown stamp and the log row are written BEFORE the chain (reviewer minor 5): the unit is KillMode=control-group, so the pass end can kill us mid-chain; the accepted
        # items are already committed, the chain is best-effort and resumable (the planner cron / the next explorer pass / queue_refill pick the [ready] features up), and nothing re-runs the pass.
        _ledger_pass(repo, L, lens, picked, written, dry, now)
        finish(row, t0, dry, " chain: started")
        t1 = time.time()
        try:
            note = chain(repo, written, row.d["slugs"])
        except Exception as e:
            note = "chain-error: %s" % str(e)[:80]
        line = "%s %s chain: %s (%ds)" % (time.strftime("%Y-%m-%d %H:%M:%S"), repo, note, int(time.time() - t1))
        try:
            with open(os.path.join(OVN_DIR, "logs", "qwen_explore.log"), "a") as f:
                f.write(line + "\n")
        except OSError:
            pass
        print(line)
        if mode == "shadow" and written:
            tail = Row(repo)                         # the pass row is already logged: the shadow verdicts get their own log line + the audit log
            tail.d["note"] = ""
            shadow_critic(repo, lens, accepted, snap, tail, {"calls": 0, "ptok": 0, "ctok": 0}, now)
            cd = tail.d.get("critic")
            if cd:
                try:
                    with open(os.path.join(OVN_DIR, "logs", "qwen_explore.log"), "a") as f:
                        f.write("%s %s critic-shadow: eval=%d approved=%d rejected=%d disagree=%d errors=%d critic_reject_rate=%.0f%%%s\n" % (
                            time.strftime("%Y-%m-%d %H:%M:%S"), repo, cd["evaluated"], cd["approved"], cd["rejected"], cd["disagree"], cd["errors"], 100.0 * cd["reject_rate"], (" " + tail.d["note"]) if tail.d["note"] else ""))
                except OSError:
                    pass
        return 0
    if mode == "shadow" and written:
        shadow_critic(repo, lens, accepted, snap, row, stats, now)
        sync_stats()
    return _end_pass(repo, L, lens, picked, row, t0, dry, now, written, extra)


DIALECT_RETRY = os.environ.get("OVN_QE_DIALECT_RETRY", "on").strip().lower() not in ("off", "0", "no", "false")


def dialect_only_empty(row, written):
    """True when the pass found candidates but EVERY one died on the VERIFY spelling check (verify-dialect only): that is a formatting miss, not 'this lens / these files hold nothing'."""
    d = row.d if row is not None else {}
    return bool(DIALECT_RETRY and not written and int(d.get("proposed") or 0) > 0 and int(d.get("accepted") or 0) == 0 and set(d.get("rejected") or {}) == {"verify-dialect"})


def _ledger_pass(repo, L, lens, files_shown, written, dry, now, dialect_only=False, calls=None):
    if not dry or LEDGER_ROOT[0]:
        done = now_ts()                                # the cooldown runs from the END of the pass (a pass takes minutes: the model + the red-before runs)
        # 2026-10-18: a pass whose proposals ALL died on verify-dialect used to stamp the lens (4h TTL) and every shown file (72h TTL) as 'covered', so after ~9 such passes every lens was
        # 'skip-lens-ttl' and the candidate-file pool 'fewer than 2 files': the repo starved on a spelling problem. Such a pass now leaves the files unstamped and re-opens the lens after 1/4 TTL.
        L["lenses"][lens] = (done - lens_ttl(lens) * 3 // 4) if dialect_only else done
        fkey = "ffiles" if lens == FEATURE_LENS else "files"
        for p in ([] if dialect_only else files_shown):
            L[fkey][p] = done
        L[fkey] = {p: ts for p, ts in L[fkey].items() if done - ts < 4 * FILE_TTL_S}
        if calls is None or calls > 0:                 # a pass that made ZERO model calls (e.g. fewer than 2 candidate files) cost nothing: it does not eat the daily cap
            if lens == FEATURE_LENS:
                L["feature_day_count"] = int(L.get("feature_day_count") or 0) + 1
            else:
                L["day_count"] = int(L["day_count"]) + 1
        L["last_pass_ts"], L["last_accepted"], L["last_lens"] = done, written, lens
        atomic_write(ledger_path(repo), json.dumps(L, indent=1, sort_keys=True))
        if not dry:
            write_next(repo, done + (COOLDOWN_PRODUCTIVE_S if written else COOLDOWN_EMPTY_S))


def _end_pass(repo, L, lens, files_shown, row, t0, dry, now, written, extra):
    _ledger_pass(repo, L, lens, files_shown, written, dry, now, dialect_only=dialect_only_empty(row, written), calls=int(row.d.get("calls") or 0))
    return finish(row, t0, dry, extra)


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.exit(main(sys.argv))
