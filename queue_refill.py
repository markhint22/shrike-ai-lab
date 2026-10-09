#!/usr/bin/env python3
"""queue_refill.py — move pre-decomposed items from a backlog into a live overnight queue.

The intelligence (deciding WHAT to do, broken into 27B-sized self-verifying subtasks) is
invested ONCE, in backlog/<repo>.md, by Claude or the release-polish drafters. This script
is the DUMB pull: it takes the top N unconsumed backlog items and appends them to the repo's
OVERNIGHT_PROGRESS.md, then removes them from the backlog. $0, deterministic, no repo scan,
no LLM — which is exactly what kills the recurring "expensive repo survey -> no-op" loop.

An item is any line matching `- [ ] [T` or `- [ ] [CLAUDE`. CLAUDE items are NOT pulled into
the 27B queue (they're for the Claude queue); only [T1..T5] items are moved here.

Usage: queue_refill.py <progress_file> <backlog_file> <max_items>
Prints: REFILL=<n moved>  BACKLOG_REMAINING=<n left>  CREDITED=<n already-satisfied>

2026-09-10: pre-check before pulling. shrike-monitor alone had 19 backlog-authored items that
turned out to already be implemented in current code (a stale decomposition snapshot) — every
one of them cost N wasted no-op cycles before the existing AUTO-SKIP-after-N-cycles safety net
finally parked it. Most items' own VERIFY command is a cheap, side-effect-free existence/import
check (`python -c "from X import Y; ..."` or `grep -q "..."`); running that ONCE against the
CURRENT repo before ever queueing the item is nearly free and catches this class at zero cost
instead of N wasted cycles. Restricted to those two safe shapes — anything heavier (pytest, npm
test, godot) is left to the existing cycle-based safety net, which is reliable if slower. Only
the first SCAN_CAP eligible items are pre-checked per run, bounding worst-case time even if a
run of items all happen to time out.

2026-09-17: prune dedup'd-but-never-removed backlog lines every run, not just pulled/credited
ones. Dedup (the `existing` set below) already refused to ever re-pull a backlog line whose
content already exists in the live queue or done archive — but until now it only REMOVED lines
from backlog/<repo>.md that were actually pulled or credited in that same run, so a line that
was dedup-excluded on every single run (because it duplicates already-completed work) just sat
in the file forever. That's not merely cosmetic: queue_refill.sh's own "is this repo's backlog
dry" check is a raw grep -c over "^- [ ] [T1-5]" lines in the file BEFORE this script ever runs,
with no idea about dedup — so N stale duplicate lines make a truly-exhausted backlog look like
it still has N items available, permanently suppressing the "backlog is dry, needs a human"
alert. Caught live on shrike-monitor: 3 lines added to backlog/shrike-monitor.md on 2026-09-10
(config.py/logging_config.py/version.py polish items) duplicated work already completed and
archived to OVERNIGHT_DONE.md five days earlier (2026-09-05) — a full week of a masked-dry
backlog with zero alerts, the same failure shape as the gitlark/billwatch exhausted-roadmap
bug found separately the same day. Fix: compute `dup` (backlog lines whose content is already
in `existing`) up front and always fold it into the lines removed from the backlog file, even
on the early-return path where nothing was pulled or credited.
"""
import sys, re, datetime, subprocess, os, json

SCAN_CAP = 30

# spec-compiler-v2 (2026-10-09): the parked-line patterns, the VERIFY extraction, the ingest ban filter and the vacuous-echo repair live in
# scripts/ovn_backlog_eligibility.py (shared with the spec gate so the two can never disagree about what an item is). Fallback: inline copies of the two
# parked regexes (a deployment that has queue_refill.py but not the module yet), with the ban filter / echo repair simply off.
_SCRIPTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts")
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)
try:
    import ovn_backlog_eligibility as _E
    _HAVE_E = True
except Exception:  # pragma: no cover - exercised by the fallback test with the module hidden
    _E = None
    _HAVE_E = False

if _HAVE_E:
    PARKED_CI, PARKED_CS = _E.PARKED_CI, _E.PARKED_CS
else:
    PARKED_CI = re.compile(r"AUTO-SKIP|HUMAN-ONLY|HUMAN/|HARD FILE BAN|\(retired-|\[CLAUDE\]", re.I)
    PARKED_CS = re.compile(r"BLOCKED")


if _HAVE_E:
    is_parked = _E.is_parked      # includes the OVN_PARKED_BLOCKED_CI=on kill switch (legacy case-insensitive BLOCKED)
else:
    def is_parked(line):
        if PARKED_CI.search(line) or PARKED_CS.search(line):
            return True
        # module missing = no deploy-order audit available: stay on the legacy behaviour (lowercase 'blocked' parks the line) unless an operator forced the unlock
        return os.environ.get("OVN_PARKED_BLOCKED_CI", "auto") != "off" and bool(re.search("blocked", line, re.I))


def load_banned(repo_root):
    return _E.load_banned(repo_root) if _HAVE_E else []


def is_banned_target(line, patterns):
    return _E.is_banned_target(line, patterns) if _HAVE_E else False


_VAC_FALLBACK = re.compile(r"&&\s+echo\s+[\"']?(FAIL|PASS)[\"']?\s+\|\|\s+echo\s+[\"']?(PASS|FAIL)[\"']?\s*`")


def normalize_verify(line):
    """A3: rewrite the vacuous `<cmd> && echo FAIL || echo PASS` VERIFY (always exits 0) to a command whose exit code means something. (line2, n_repaired)."""
    if _HAVE_E:
        return _E.normalize_vacuous_echo(line)
    return line, 0


def count_vacuous(line):
    if _HAVE_E:
        c = _E.extract_verify(line)
        return 1 if c and _E.is_vacuous_cmd(c) else 0
    return 1 if _VAC_FALLBACK.search(line) else 0


def _extract_verify(line):
    m = re.search(r'VERIFY:\s*`([^`]+)`', line)
    if not m:
        m = re.search(r'VERIFY:\s*(.+?)\s*\(cat:', line)
    return m.group(1).strip() if m else None


_ALWAYS_TRUE_RE = re.compile(r'\|\|\s*(echo|printf|true)\b')
_TEST_ABSENT_RE = re.compile(r'^test\s+!\s+-([fe])\s+([A-Za-z0-9_./@-]+)\s*$')


def already_satisfied(line, repo_root, timeout=8):
    """Best-effort: True only if the item's OWN verify command already passes against the
    current repo. False (never block a pull) on any ambiguity, error, or unsupported shape.

    2026-09-23: reject a `cmd && echo A || echo B` (or `|| printf`/`|| true`) shape outright,
    without ever executing it - the final executed branch there is always the echo/printf/true
    fallback, so its exit code is always 0 regardless of what cmd actually found. Confirmed live
    on shrike-monitor and gitlark: this exact shape false-credited items as done with zero real
    work having happened. ovn_verify_direction_check.sh (shadow-mode alert) has been running clean
    against this pattern for hours with zero remaining open false positives, so promoting it here
    to an actual gate - not just an alert - closes the root vulnerability instead of only
    reporting it after the fact.
    """
    cmd = _extract_verify(line)
    if not cmd:
        return False
    if _ALWAYS_TRUE_RE.search(cmd):
        return False
    # h13 (2026-10-04): `test ! -f <path>` (a "delete X" item whose file an earlier commit already removed) is cheap and side-effect free, but
    # was never recognised, so such items were pulled into the live queue and flailed. Accept ONLY the bare single-path form (no operators), and
    # only when the path is a plain relative repo path.
    m = _TEST_ABSENT_RE.match(cmd)
    if m:
        p = m.group(2)
        if p.startswith("/") or ".." in p.split("/"):
            return False
        return not os.path.lexists(os.path.join(repo_root, p))
    if not (cmd.startswith("python -c") or cmd.startswith("python3 -c") or cmd.startswith("grep -")):
        return False
    try:
        r = subprocess.run(cmd, shell=True, cwd=repo_root, timeout=timeout,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return r.returncode == 0
    except Exception:
        return False


_TEST_BASENAME = re.compile(r"(?:^|/)((?:test_[\w.-]+\.(?:py|gd))|(?:[\w.-]+_test\.(?:py|gd)))")
_PATH_IN_LINE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)+[\w.-]+\.(?:py|gd))")


def collected_test_dir(repo_root):
    """Where this repo's verify command actually collects tests (None = unknown, lint nothing)."""
    if os.path.isdir(os.path.join(repo_root, "iptv-backend", "tests")):
        return "iptv-backend/tests/"
    if os.path.isfile(os.path.join(repo_root, "project.godot")) and os.path.isdir(os.path.join(repo_root, "tests")):
        return "tests/"
    return None


def relocate_new_tests(line, repo_root):
    """2026-10-08: planner items named NEW test files in app/jobs/, app/services/ ... - directories pytest never collects - and the fleet shipped
    8 uncollected test files plus a placeholder `assert True` file that held 235 commits at the antigaming gate for 17h. A NEW test file path
    outside the collected dir is rewritten (everywhere in the line, VERIFY included) to the collected dir. Existing files are never touched.
    Returns (line, [(old, new)])."""
    base = collected_test_dir(repo_root)
    if not base:
        return line, []
    moves = []
    for m in _PATH_IN_LINE.finditer(line):
        path = m.group(1)
        bm = _TEST_BASENAME.search(path)
        if not bm or path.startswith(base) or os.path.exists(os.path.join(repo_root, path)):
            continue
        new = base + bm.group(1)
        if (path, new) not in moves:
            moves.append((path, new))
    for old, new in moves:
        line = line.replace(old, new)
    return line, moves


# ---------------------------------------------------------------- spec gate consumer (C4): queue_refill is the SINGLE writer of the backlog
# scripts/ovn_spec_gate.py scan judges backlog lines into state/spec_gate.jsonl and NEVER writes the backlog. This is where a verdict can take effect, and only
# for the rules named in OVN_SPEC_GATE_ENFORCE_RULES (default empty = nothing enforced; OVN_SPEC_GATE=off disables even that).
#   R01 R02 R03 (+ A3)  repair the pulled line in place (static, no verdict needed)
#   R06                 HOLD: the line stays in the backlog (a delete whose references are not removed yet); later items are pulled first
#   R04 R05 R07 R10     QUARANTINE: moved to backlog/quarantine/<repo>.md with '<!-- spec-gate:RNN <ts> -->' (never an AUTO-SKIP tag: the Claude-queue bridge harvests those)
#   PB                  QUARANTINE a line whose VERIFY already passes (verdict passes-before) as 'already-satisfied?' - never credited
# A line with no fresh verdict is pulled (OVN_SPEC_GATE_UNJUDGED=pull, default) or held (=hold; only meaningful when a verdict-based rule is enforced).
GATE_QUARANTINE_RULES = ("R04", "R05", "R07", "R10")
GATE_HOLD_RULES = ("R06",)
GATE_STATIC_RULES = ("R01", "R02", "R03")
GATE_TTL_S = 6 * 3600


def enforce_rules():
    return {r.strip().upper() for r in os.environ.get("OVN_SPEC_GATE_ENFORCE_RULES", "").split(",") if r.strip()}


def _utcnow():
    return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)


def _gate_now():
    return os.environ.get("OVN_SPEC_GATE_NOW") or _utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_ts(ts):
    try:
        return datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
    except (TypeError, ValueError):
        return None


def verdicts_path(backlog):
    env = os.environ.get("OVN_SPEC_GATE_VERDICTS")
    if env:
        return env
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(backlog))), "state", "spec_gate.jsonl")


def load_verdicts(path, repo=None):
    """{line_hash: latest row}. A row older than the TTL (6h) is ignored, except a `restored` row, which is sticky (a human said keep this line). Restored markers come from
    `spec_gate_restored.jsonl` next to the store (append-only, written by `ovn_spec_gate.py restore`; read LAST so a marker always wins) and, for markers written by an earlier
    version, from `restored` rows inside the store itself."""
    out = {}
    now = _parse_ts(_gate_now()) or _utcnow()
    for p in (path, os.path.join(os.path.dirname(os.path.abspath(path)), "spec_gate_restored.jsonl")):
        try:
            f = open(p, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with f:
            for raw in f:
                try:
                    row = json.loads(raw)
                except ValueError:
                    continue
                if not isinstance(row, dict) or not row.get("item_key"):
                    continue
                if repo and row.get("repo") and row.get("repo") != repo:
                    continue
                h = str(row["item_key"]).split("-")[0]
                ts = _parse_ts(row.get("ts"))
                if not row.get("restored") and (ts is None or (now - ts).total_seconds() > GATE_TTL_S):
                    continue
                out[h] = row
    return out


def consult_gate(line, repo, verdicts):
    """-> (action, line2, rule, note); action is 'pull' | 'hold' | 'quarantine'. A pass-through unless a rule is enforced."""
    rules = enforce_rules()
    if os.environ.get("OVN_SPEC_GATE", "shadow") == "off" or not rules:
        return "pull", line, None, ""
    line2 = line
    static = [r for r in GATE_STATIC_RULES if r in rules]
    if static:
        try:
            import ovn_spec_rules as _R
            line2, _ = _R.lint_static(line, only=set(static))
        except Exception:
            line2 = line
    verdict_rules = [r for r in rules if r in GATE_QUARANTINE_RULES + GATE_HOLD_RULES + ("PB",)]
    if not verdict_rules:
        return "pull", line2, None, ""
    row = verdicts.get(_E.line_hash(line)) if _HAVE_E else None
    if row is None:
        if os.environ.get("OVN_SPEC_GATE_UNJUDGED", "pull") == "hold":
            return "hold", line2, "UNJUDGED", ""
        return "pull", line2, None, ""
    if row.get("restored"):
        return "pull", line2, None, ""
    hit = [f.get("rule") for f in (row.get("findings") or []) if isinstance(f, dict)]
    for r in GATE_QUARANTINE_RULES:
        if r in rules and r in hit:
            return "quarantine", line, r, ""
    for r in GATE_HOLD_RULES:
        if r in rules and r in hit:
            return "hold", line2, r, ""
    ex = row.get("exec") or {}
    if "PB" in rules and ex.get("verdict") == "passes-before":
        return "quarantine", line, "PB", "already-satisfied?"
    return "pull", line2, None, ""


def quarantine_path(backlog):
    repo = os.path.splitext(os.path.basename(backlog))[0]
    return os.path.join(os.path.dirname(os.path.abspath(backlog)), "quarantine", repo + ".md")


def quarantine_lines(backlog, entries):
    """Append (line, rule, note) entries to backlog/quarantine/<repo>.md; an identical original line already quarantined is not written twice."""
    if not entries:
        return
    qp = quarantine_path(backlog)
    os.makedirs(os.path.dirname(qp), exist_ok=True)
    try:
        have = open(qp, encoding="utf-8").read()
    except OSError:
        have = ""
    ts = _gate_now()
    with open(qp, "a", encoding="utf-8") as f:
        for line, rule, note in entries:
            if any(l.startswith(line + "  <!-- spec-gate:") for l in have.split("\n")):
                continue
            f.write("%s  <!-- spec-gate:%s %s%s -->\n" % (line, rule, ts, (" " + note) if note else ""))


def main():
    if len(sys.argv) != 4:
        print("usage: queue_refill.py <progress_file> <backlog_file> <max_items>", file=sys.stderr)
        sys.exit(2)
    progress, backlog, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
    repo_root = os.path.dirname(progress) or "."
    try:
        bl = open(backlog, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        print("REFILL=0  BACKLOG_REMAINING=0  CREDITED=0")
        return
    # 27B-eligible open items only (skip CLAUDE-tagged and already-parked lines)
    is_item = re.compile(r"^- \[ \] \[T[1-5]\]")
    # 2026-09-29 fix: added "HUMAN/" (catches roadmap's own "[HUMAN/design]" tag on
    # items that need a real design call before they're decomposable — see
    # roadmap/README.md convention). Confirmed live on test-automation-agent: a
    # [HUMAN/design]-tagged feature got auto-decomposed anyway (this regex only
    # matched "HUMAN-ONLY", not "HUMAN/"), then its mechanical sub-items thrashed
    # for 3 days (12+ reverts, ~450K tokens) because they conflicted with an
    # unrelated, correct, already-existing migration-drift safety-net test that
    # aider has no shell access to satisfy. run_overnight.sh's own OVERNIGHT_PROGRESS.md
    # skip-greps already use the broader "human/" pattern in several call sites
    # (see e.g. its DOABLE-count checks) - this brings queue_refill.py's backlog-pull
    # gate up to the same standard so a [HUMAN/design] item is excluded at BOTH the
    # decomposition-output stage and the live-queue-pull stage, not just one.
    # 2026-10-09 (spec-compiler-v2): `parked` was re.compile(r"AUTO-SKIP|HUMAN-ONLY|HUMAN/|BLOCKED", re.I) - the re.I parked every line containing the lowercase word
    # blocked/unblocked/test_x_blocked (all 10 open iptv_apps and both open xlite items). is_parked() = PARKED_CI (the tags, any case) + PARKED_CS (BLOCKED, exact case).
    # Dedup guard: never pull an item whose content already exists in the live queue
    # (open OR done) — prevents duplicates when a backlog is re-shipped/overlaps progress.
    #
    # 2026-09-29 (Phase 6b, PREVENTIVE — no live miss observed on this exact path yet): strip the
    # embedded date stamp out of any [feat:<slug>] tag before comparing. A roadmap regeneration
    # mints a fresh YYYYMMDD/MMDDYY stamp on the SAME feat slug when it re-decomposes a stuck
    # feature, so a backlog line identical except for that one date used to look like brand-new
    # work and get pulled again. The bash side already collapses this (ovn_item_hash() in
    # scripts/lib_item_select.sh, same two sed rules: "-NNNNNNNN-" then "-NNNNNN-", first
    # occurrence each) — this keeps the Python and bash sides agreeing on what "the same item"
    # means (the exact cross-boundary mismatch class already found once between record_outcome()
    # and ovn_item_guard.sh). Deliberately strips ONLY the date inside the tag and keeps the rest
    # of the line: ovn_item_hash() hashes the tag alone because it answers "same FEATURE" for
    # streak tracking, but two sibling sub-items sharing one live feat tag are genuinely different
    # content here and must NOT dedup against each other.
    def _strip_feat_date(text):
        def _one(m):
            tag = re.sub(r"-\d{8}-", "-", m.group(0), count=1)
            return re.sub(r"-\d{6}-", "-", tag, count=1)
        return re.sub(r"\[feat:[^\]]+\]", _one, text)
    def _norm(line):
        # 2026-10-07: a parked line carries '[AUTO-SKIP ...]' / '[HUMAN-ONLY ...]' right after the checkbox; without stripping it the roadmap's
        # re-decomposed copy of the SAME item (identical text, no tag) looked brand new and was re-pulled as an eligible item (churn-loop guard parks
        # an item, the backlog re-adds it, the loop restarts).
        line = re.sub(r"^(\s*- \[[ xX]\] )(\[(?:AUTO-SKIP|HUMAN-ONLY)[^\]]*\]\s*)+", r"\1", line)
        m = re.search(r"\]\s*(.*)$", line)  # content after the last tag bracket
        content = _strip_feat_date((m.group(1) if m else line).strip())
        return re.sub(r"\s+", " ", content.lower())
    done_path = os.path.join(repo_root, "OVERNIGHT_DONE.md")
    existing = set()
    # dedup against the live queue AND the completed-items archive (OVERNIGHT_DONE.md), so an
    # item that was completed then archived out of the progress file is never re-pulled.
    for fp in (progress, done_path):
        try:
            for pl in open(fp, encoding="utf-8"):
                if pl.lstrip().startswith("- ["):
                    existing.add(_norm(pl))
        except FileNotFoundError:
            pass
    eligible = [l for l in bl if is_item.match(l) and not is_parked(l) and _norm(l) not in existing]
    if _HAVE_E:   # deploy-order guard (see ovn_backlog_eligibility.is_parked): say so when lowercase-'blocked' items are held back only because other BLOCKED sites are unconverted
        _held = [l for l in bl if is_item.match(l) and _E.held_by_sites_guard(l)]
        if _held:
            sys.stderr.write("queue_refill: %d lowercase-'blocked' backlog item(s) held back: %s\n" % (len(_held), _E.sites_guard_notice()))
    # backlog lines that are real [T1-5] items but whose content is ALREADY in the live queue
    # or done archive — permanently dedup-excluded from `eligible` above, so they'll never be
    # pulled or pre-check-credited. Left in the file, they inflate queue_refill.sh's raw
    # grep-based "backlog avail" count forever (see 2026-09-17 note in the module docstring).
    # Always pruned below, independent of whether this run pulls/credits anything.
    dup = [l for l in bl if is_item.match(l) and not is_parked(l) and _norm(l) in existing]
    # 2026-09-14 REMOVED the old "DEFAULT-PASS on godot" reroute (pulled every .gd backlog item and
    # pre-tagged it AUTO-SKIP/route-to-Claude before it ever reached the active queue) — that was the
    # SAME stale "measured 0%" assumption fixed today in ovn_stage_runner.sh/run_overnight.sh (see
    # project_godot-staging-reenabled-2026-09-14.md), just one layer further upstream. It meant fixing
    # the picker/trigger did nothing for NEW backlog items: they got auto-parked here before either
    # fixed code path ever saw them. Godot items now flow through the normal pull path below like any
    # other item, routing to whichever flow (basic scout+implement or the staged pipeline) their tier
    # naturally selects.

    # Pre-check: scan eligible items in order, crediting any that already pass their own
    # VERIFY, until either the pull quota (n) is filled or SCAN_CAP items have been examined.
    # NOTE: already_satisfied's own docstring restricts pre-checking to python-import/grep VERIFY
    # shapes (cheap, side-effect-free) — a godot item's VERIFY runs the engine, so it's heavier than
    # that restriction allows and will simply never match, falling through to `pull` normally.
    # A2 (2026-10-09): a TARGET path (text before the first ' - ', never a VERIFY path) that is hard-banned (.queue-hard-banned-files) or vendored (addons/) can
    # never land - the cycle is discarded by run_overnight.sh's ban check - so it is quarantined at ingest instead of burning cycles (xlite: 21 vendored-addon
    # items, 48% of its parked lines). OVN_INGEST_BAN_FILTER=off disables. Not counted against SCAN_CAP.
    quarantined = []
    if os.environ.get("OVN_INGEST_BAN_FILTER", "on") != "off" and _HAVE_E:
        banned = load_banned(repo_root)
        keep_elig = []
        for l in eligible:
            if is_banned_target(l, banned):
                quarantined.append((l, "R04", ""))
            else:
                keep_elig.append(l)
        eligible = keep_elig

    verdicts = load_verdicts(verdicts_path(backlog), os.path.splitext(os.path.basename(backlog))[0]) if enforce_rules() else {}
    repo_label = os.path.splitext(os.path.basename(backlog))[0]
    pull, credited, scanned = [], [], 0      # pull / credited hold (original_line, line_to_use)
    held = 0
    for l in eligible:
        if len(pull) >= n or scanned >= SCAN_CAP:
            break
        action, l2, rule, note = consult_gate(l, repo_label, verdicts)
        if action == "hold":        # held / quarantined lines are free (a dict lookup): they must not eat the SCAN_CAP budget, or a long run of held lines starves the queue
            held += 1
            continue
        if action == "quarantine":
            quarantined.append((l, rule, note))
            continue
        scanned += 1
        if already_satisfied(l2, repo_root):
            credited.append((l, l2))
        else:
            pull.append((l, l2))
    # A3: count (and, only when R02 is enforced, repair) the vacuous `cmd && echo FAIL || echo PASS` VERIFYs among the lines about to be queued
    vacuous = sum(count_vacuous(o) for o, _ in pull)
    repaired = 0
    if "R02" in enforce_rules() and os.environ.get("OVN_SPEC_GATE", "shadow") != "off":
        for i, (o, l2) in enumerate(pull):      # consult_gate's R02 repair already did this; this also covers a deployment without ovn_spec_rules.py (idempotent)
            l3, k = normalize_verify(l2)
            if k:
                pull[i] = (o, l3)
        repaired = sum(1 for o, l2 in pull if count_vacuous(o) and not count_vacuous(l2))
    # relocate NEW test files that the item places outside the collected test dir (the backlog copy is removed below by its ORIGINAL text)
    pull_orig = [o for o, _ in pull]
    credited_orig = [o for o, _ in credited]
    pull = [l2 for _, l2 in pull]
    credited_lines = [l2 for _, l2 in credited]
    relocated = 0
    for i, l in enumerate(pull):
        l2, mv = relocate_new_tests(l, repo_root)
        if mv:
            pull[i] = l2
            relocated += 1

    extra = (f"  QUARANTINED={len(quarantined)}" if quarantined else "") + (f"  HELD={held}" if held else "") \
        + (f"  VACUOUS_ECHO={vacuous}" if vacuous else "") + (f"  REPAIRED={repaired}" if repaired else "")
    if not pull and not credited and not dup and not quarantined:
        remaining = len(eligible)
        print(f"REFILL=0  BACKLOG_REMAINING={remaining}  CREDITED=0  PRUNED=0" + extra)
        return

    # remove pulled + credited + already-consumed-duplicate + quarantined lines from the backlog (first
    # occurrence each)
    to_remove = list(pull_orig) + list(credited_orig) + list(dup) + [q[0] for q in quarantined]
    rest = []
    for l in bl:
        if to_remove and l in to_remove:
            to_remove.remove(l)
            continue
        rest.append(l)
    quarantine_lines(backlog, quarantined)   # written BEFORE the backlog is rewritten: a crash between the two duplicates a line, never loses one
    open(backlog, "w", encoding="utf-8").write(("\n".join(rest)).rstrip() + "\n")

    stamp = datetime.date.today().isoformat()

    # append pulled items to the live queue under a dated marker (runner scans `- [ ] [Tn]`)
    with open(progress, "a", encoding="utf-8") as f:
        if pull:
            f.write(f"\n<!-- auto-refill {stamp}: {len(pull)} items pulled from backlog -->\n")
            for l in pull:
                f.write(l + "\n")

    # credited items never enter the active queue at all — straight to the done archive, so
    # queue_refill.py's own dedup (and everyone else's) sees them as already handled.
    if credited:
        with open(done_path, "a", encoding="utf-8") as f:
            f.write(f"\n<!-- pre-verified already-satisfied {stamp}: {len(credited)} item(s), credited without a 27B cycle -->\n")
            for l in credited_lines:
                checked = re.sub(r"^- \[ \] ", "- [x] (pre-verified: VERIFY already passed against current code) ", l, count=1)
                f.write(checked + "\n")

    remaining = len([l for l in rest if is_item.match(l) and not is_parked(l) and _norm(l) not in existing])
    print(f"REFILL={len(pull)}  CREDITED={len(credited)}  BACKLOG_REMAINING={remaining}  PRUNED={len(dup)}" + (f"  RELOCATED_TESTS={relocated}" if relocated else "") + extra)


if __name__ == "__main__":
    main()
