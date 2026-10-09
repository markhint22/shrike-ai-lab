#!/usr/bin/env python3
"""scripts/ovn_backlog_eligibility.py (spec-compiler-v2 part A, 2026-10-09).

A1 safety differential: the old queue_refill / work-supply predicates vs is_parked(). The ONLY lines that flip parked -> eligible are those whose sole match was the
lowercase word 'blocked'; no AUTO-SKIP / HUMAN-ONLY / HUMAN/ / [CLAUDE] / retired / BLOCKED-tag line ever flips that way.
A2 ingest ban filter (target path only), A3 vacuous echo repair, pullable() dedupe incl. feat-date stamps, the CLI count, parity with queue_refill.py's pull set.
Mutation checks: the strict-case claim fails when PARKED_CS is made case-insensitive; the repair polarity fails when PASS/FAIL are swapped."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import ovn_backlog_eligibility as E  # noqa: E402
import ovn_convert_blocked_sites as CV  # noqa: E402

P = F = 0
# The default mode (OVN_PARKED_BLOCKED_CI unset = auto) keeps lowercase-'blocked' items parked while ANY tree site still matches BLOCKED case-insensitively (deploy-order guard).
# The behavioural sections below describe the CLEAN-tree behaviour, so they run against an empty site root; the guard has its own section.
_CLEAN_ROOT = tempfile.mkdtemp(prefix="elig-clean-")
os.environ["OVN_PARKED_SITES_ROOT"] = _CLEAN_ROOT


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


# the twelve real open items the old `re.I BLOCKED` parked (cut from the live backlogs 2026-10-09; 10 iptv_apps, 2 xlite; long VERIFY tails trimmed)
REAL12 = [
    "- [ ] [T2] iptv-backend/app/routers/streams.py — Update stream import endpoint to enforce `validate_content_rights` before processing M3U/Xtream imports. VERIFY: pytest tests/test_streams_import_guard.py::test_unlicensed_import_blocked -q (cat:endpoint; multifile:no)",
    "- [ ] [T1] iptv-backend/app/services/parental_rating_gate.py — Implement `is_content_allowed(rating: str, kid_max_rating: str, blocked_categories: list[str]) -> bool` using the existing hierarchy map. VERIFY: python -m pytest iptv-backend/tests/test_parental_rating_gate.py::test_is_content_allowed_blocks_higher_rating -q. (cat:python; multifile:no)",
    "- [ ] [T1] iptv-backend/app/services/parental_rating_gate.py — Add `is_content_allowed(rating: str, kid_max_rating: str, blocked_categories: list[str])` pure function that returns False if rating exceeds max or category is blocked. VERIFY: pytest iptv-backend/tests/test_parental_rating_gate.py::test_is_content_allowed_blocks_higher_rating -q. (cat:python; multifile:no)",
    "- [ ] [T2] iptv-backend/app/services/parental_rating_gate.py — Add `filter_streams_for_profile(streams: list[dict], profile: dict)` pure function that applies rating and category filters to a stream list. VERIFY: pytest iptv-backend/tests/test_parental_rating_gate.py::test_filter_streams_for_profile_excludes_blocked -q. (cat:python; multifile:no)",
    "- [ ] [T3] iptv-ios/ChickadeeStreams/Services/APIService+Extended.swift — Modify `addEPGSource()` to call `autoMap(sourceId:)` in a `Task` so the main flow is not blocked by auto-map latency. VERIFY: `grep -A 10 \"func addEPGSource\" iptv-ios/ChickadeeStreams/Services/APIService+Extended.swift | grep -q \"autoMap\"`. (cat:swift; multifile:no)",
    "- [ ] [T2] iptv-web/src/stores/parental.ts — `setupPIN()`, `removePIN()`, `blockStream()`, `unblockStream()`, and `fetchBlockedStreams()` (all called live from `ParentalView.vue`) are only referenced as `vi.fn()` mocks; add store tests that invoke them. VERIFY: `grep -q fetchBlockedStreams iptv-web/src/stores/__tests__/parental.test.ts`. (cat:test; multifile:no)",
    "- [ ] [T3] iptv-android/app/src/main/java/com/chickadeestreams/iptv/data/api/ChickadeeApi.kt — Android's parental-controls surface is read/PIN-only: declare `PUT /settings` and the blocked-stream routes. VERIFY: `grep -q blocked iptv-android/app/src/main/java/com/chickadeestreams/iptv/data/api/ChickadeeApi.kt`. (cat:kotlin; multifile:no)",
    "- [ ] [T4] iptv-backend/app/routers/parental.py — In the `unblock_stream` endpoint (`DELETE /api/parental/blocked/{stream_id}`), add a call to `check_pin_lockout(db, user.id)` before PIN verification and raise 429 if locked out. VERIFY: `pytest iptv-backend/app/routers/test_parental.py::test_unblock_stream_locked_out -v` passes. (cat:endpoint; multifile:no) [feat:iptv_apps-20261004-fix-pin-lockout]",
    "- [ ] [T5] iptv-backend/tests/test_stream_import_flow.py — Create an integration test to ensure stream imports succeed for `.m3u` and `xtream` URLs without being blocked. VERIFY: python -m pytest iptv-backend/tests/test_stream_import_flow.py -v. (cat:test; multifile:yes) [feat:iptv_apps-20261004-delete-dead-validate-content-rights-and-]",
    "- [ ] [T4] iptv-backend/tests/test_stream_ssrf.py — Create integration test mocking `_http_client.get` to raise if called, asserting `/{id}/check` returns offline and `/{id}/proxy` fails for `http://127.0.0.1:9/x`. VERIFY: `pytest iptv-backend/tests/test_stream_ssrf.py::test_ssrf_blocked -v` passes. (cat:test; multifile:yes) [feat:iptv_apps-20261005-route-the-stream-proxy-and-health-check-]",
    "- [ ] [T2] test/battle/test_overwatch.gd — Write unit test for `overwatch.gd` verifying true when LOS is clear and range valid, false when blocked. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle/test_overwatch.gd`. (cat:test; multifile:no)",
    "- [ ] [T2] scripts/units/ability_resolver.gd — Add a `##` doc-comment on the line above each of `is_usable`, `blocked_reason`. Comments only. VERIFY: `python3 -c \"import re;names=['is_usable','blocked_reason'];assert not names\"`. (cat:docs; multifile:no)",
]

# the predicates as they were before this change
OLD_REFILL = re.compile(r"AUTO-SKIP|HUMAN-ONLY|HUMAN/|BLOCKED", re.I)                                  # queue_refill.py:157
OLD_SUPPLY = re.compile(r"HUMAN-ONLY|AUTO-SKIP|BLOCKED ITEM|\(retired-|\[CLAUDE\]")                    # ovn_work_supply._HELD (+ HUMAN/ at the call site)
TAGGED = [
    "- [ ] [T2] [AUTO-SKIP after 4 cycles] scripts/a.py — do a thing. VERIFY: `grep -q x scripts/a.py`. (cat:python)",
    "- [ ] [T2] [HUMAN-ONLY: needs a design call] scripts/b.py — do a thing. VERIFY: `true`. (cat:python)",
    "- [ ] [T3] [HUMAN/design] scripts/c.py — do a thing. VERIFY: `true`. (cat:python)",
    "- [ ] [T2] scripts/d.py — do a thing (retired-dead-path). VERIFY: `true`. (cat:python)",
    "- [ ] [T2] scripts/e.py — BLOCKED ITEM: the file is read-only. VERIFY: `true`. (cat:python)",
    "- [ ] [T2] scripts/f.py — route this to the queue [CLAUDE] VERIFY: `true`. (cat:python)",
    "- [ ] [T2] scripts/g.py — do not touch. HARD FILE BAN VERIFY: `true`. (cat:python)",
    "- [ ] [T2] [auto-skip after 4 cycles] scripts/h.py — lowercase tag still parks. VERIFY: `true`. (cat:python)",
    "- [ ] [T2] scripts/i.py — this one is BLOCKED and also mentions blocked_reason. VERIFY: `true`. (cat:python)",
]
CLEAN = [
    "- [ ] [T1] scripts/clean1.py — add a pure function. VERIFY: `python3 -c \"import sys;sys.exit(1)\"`. (cat:python)",
    "- [ ] [T2] scripts/clean2.py — unblocked flows should still work. VERIFY: `true`. (cat:python)",
]
ALL = REAL12 + TAGGED + CLEAN

print("== A1: differential (old predicates vs is_parked)")
ok("fixture: exactly 12 real 'blocked' items", len(REAL12) == 12)
ok("old queue_refill predicate parked all 12 real items (the measured defect)", all(OLD_REFILL.search(l) for l in REAL12))
ok("new predicate parks none of the 12", not any(E.is_parked(l) for l in REAL12), [l[:60] for l in REAL12 if E.is_parked(l)])
ok("clean lines stay eligible", not any(E.is_parked(l) for l in CLEAN))

def _sole_lowercase_blocked(line):
    return bool(re.search("blocked", line, re.I)) and not re.search(E.PARKED_CI, line) and "BLOCKED" not in line


flips_to_eligible = {l for l in ALL if OLD_REFILL.search(l) and not E.is_parked(l)}
sole = {l for l in ALL if OLD_REFILL.search(l) and _sole_lowercase_blocked(l)}
ok("parked->eligible flips are EXACTLY the lines whose sole match was lowercase 'blocked'", flips_to_eligible == sole, (len(flips_to_eligible), len(sole)))
ok("... that is the 12 real items plus the clean line that merely says 'unblocked'", flips_to_eligible == set(REAL12) | {CLEAN[1]})
ok("no AUTO-SKIP/HUMAN-ONLY/HUMAN/[CLAUDE]/retired/HARD FILE BAN/BLOCKED line flips to eligible",
   all(E.is_parked(l) for l in TAGGED), [l[:50] for l in TAGGED if not E.is_parked(l)])
ok("'BLOCKED ITEM' (the harness tag) still parks", E.is_parked("- [ ] [T2] x.py — BLOCKED ITEM: read-only"))
ok("lowercase tags still park (AUTO-SKIP is case-insensitive)", E.is_parked(TAGGED[7]))
supply_only = [l for l in ALL if OLD_SUPPLY.search(l) and not E.is_parked(l)]
ok("everything the work-supply _HELD held is still held (new predicate is a superset)", not supply_only, supply_only[:1])
ok("lines newly parked (old queue_refill let them through) carry only tags queue_refill lacked",
   all(re.search(r"\(retired-|\[CLAUDE\]|HARD FILE BAN", l, re.I) for l in ALL if E.is_parked(l) and not OLD_REFILL.search(l)))
ok("is_open_item: only the [ ] [T1-5] form", E.is_open_item(CLEAN[0]) and not E.is_open_item("- [x] [T1] a") and not E.is_open_item("- [ ] [CLAUDE] a") and not E.is_open_item("  - [ ] [T1] a"))

old_env = os.environ.get("OVN_PARKED_BLOCKED_CI")
os.environ["OVN_PARKED_BLOCKED_CI"] = "on"
ok("kill switch OVN_PARKED_BLOCKED_CI=on restores the legacy behaviour (all 12 parked again)", all(E.is_parked(l) for l in REAL12))
if old_env is None:
    del os.environ["OVN_PARKED_BLOCKED_CI"]
else:
    os.environ["OVN_PARKED_BLOCKED_CI"] = old_env
ok("kill switch off again: 12 eligible", not any(E.is_parked(l) for l in REAL12))

# mutation: a case-insensitive PARKED_CS must be caught by the differential
_saved = E.PARKED_CS
E.PARKED_CS = re.compile("BLOCKED", re.I)
mut_caught = any(E.is_parked(l) for l in REAL12)
E.PARKED_CS = _saved
ok("MUTATION (PARKED_CS made case-insensitive): the 12-pullable check fails", mut_caught)
_saved_ci = E.PARKED_CI
E.PARKED_CI = re.compile(r"AUTO-SKIP|HUMAN-ONLY", re.I)   # drop HUMAN/, retired, [CLAUDE], HARD FILE BAN
mut2 = [l for l in TAGGED if not E.is_parked(l)]
E.PARKED_CI = _saved_ci
ok("MUTATION (PARKED_CI loses tags): the tagged-lines-stay-parked check fails", len(mut2) >= 3, mut2)

print("== pullable(): dedupe against queued / done incl. feat-date stamps")
bl = "\n".join(REAL12 + CLEAN + TAGGED)
ok("12 + 2 clean pullable, tagged excluded", len(E.pullable(bl, "", "")) == 14)
prog = "# progress\n" + REAL12[7].replace("20261004", "20260901") + "\n"        # queued copy with an older feat-date stamp
ok("queued copy with a different feat-date stamp dedupes", E.norm_line(REAL12[7]) == E.norm_line(prog.split("\n")[1]) and len(E.pullable(bl, prog, "")) == 13)
done = "- [x] (pre-verified: VERIFY already passed against current code) " + CLEAN[0][len("- [ ] "):]
ok("done-archive copy dedupes (only the checkbox/prefix differs)", len(E.pullable(bl, "", done)) == 13 or len(E.pullable(bl, "", "- [x] " + CLEAN[0][6:])) == 13)
queued_tagged = "- [ ] [AUTO-SKIP after 4 cycles] " + CLEAN[1][len("- [ ] "):]
ok("a queued copy parked with an [AUTO-SKIP ...] tag still dedupes the clean backlog copy", E.norm_line("- [ ] [AUTO-SKIP after 4 cycles] [T2] x") == E.norm_line("- [ ] [T2] x") and CLEAN[1] not in E.pullable(bl, queued_tagged, ""))
ok("NEGATIVE: genuinely different content is not deduped", len(E.pullable(bl, "- [ ] [T1] other — other thing\n", "")) == 14)
ok("sibling lines sharing one feat tag are different items", E.norm_line(REAL12[7]) != E.norm_line(REAL12[9]))

print("== CLI count")
d = tempfile.mkdtemp(prefix="elig-")
try:
    repo = os.path.join(d, "repo")
    os.makedirs(repo)
    open(os.path.join(repo, "OVERNIGHT_PROGRESS.md"), "w").write("# progress\n")
    bf = os.path.join(d, "bl.md")
    open(bf, "w").write("# backlog\n" + "\n".join(REAL12) + "\n")
    cli = [sys.executable, os.path.join(ROOT, "scripts", "ovn_backlog_eligibility.py")]
    r = subprocess.run(cli + ["count", repo, bf], capture_output=True, text=True)
    ok("CLI count on the fixture with the 12 real texts == 12", r.stdout.strip() == "12", r.stdout + r.stderr)
    open(bf, "a").write(TAGGED[0] + "\n")
    ok("CLI count ignores a parked line", subprocess.run(cli + ["count", repo, bf], capture_output=True, text=True).stdout.strip() == "12")
    open(os.path.join(repo, ".queue-hard-banned-files"), "w").write("# comment\nscripts/units/ability_resolver.gd\n\n")
    ok("CLI count applies the repo's hard-ban list (A2): 11", subprocess.run(cli + ["count", repo, bf], capture_output=True, text=True).stdout.strip() == "11")
    ok("OVN_INGEST_BAN_FILTER=off counts it again", subprocess.run(cli + ["count", repo, bf], capture_output=True, text=True, env=dict(os.environ, OVN_INGEST_BAN_FILTER="off")).stdout.strip() == "12")
    r = subprocess.run(cli + ["count", repo, os.path.join(d, "missing.md")], capture_output=True, text=True)
    ok("missing backlog file: 0, exit 0", r.returncode == 0 and r.stdout.strip() == "0")
    ok("bad usage: exit 2", subprocess.run(cli + ["nope"], capture_output=True, text=True).returncode == 2)

    print("== parity: queue_refill.py pulls exactly pullable()")
    os.remove(os.path.join(repo, ".queue-hard-banned-files"))
    open(bf, "w").write("# backlog\n" + "\n".join(REAL12 + TAGGED + CLEAN) + "\n")
    want = E.pullable(open(bf).read(), "# progress\n", "")
    qr = os.path.join(ROOT, "queue_refill.py")
    r = subprocess.run([sys.executable, qr, os.path.join(repo, "OVERNIGHT_PROGRESS.md"), bf, "50"], capture_output=True, text=True)
    pulled = [l for l in open(os.path.join(repo, "OVERNIGHT_PROGRESS.md")).read().split("\n") if l.startswith("- [ ] [T")]
    ok("queue_refill pulled all 14 eligible lines (12 formerly-parked + 2 clean)", "REFILL=14" in r.stdout, r.stdout + r.stderr)
    ok("pulled set == pullable() set", sorted(pulled) == sorted(want), (len(pulled), len(want)))
    left = [l for l in open(bf).read().split("\n") if l.startswith("- [ ]")]
    ok("the parked tagged lines stay in the backlog", sorted(left) == sorted(TAGGED), len(left))
    r2 = subprocess.run([sys.executable, qr, os.path.join(repo, "OVERNIGHT_PROGRESS.md"), bf, "50"], capture_output=True, text=True, env=dict(os.environ, OVN_PARKED_BLOCKED_CI="on"))
    ok("(second run: nothing left to pull)", "REFILL=0" in r2.stdout, r2.stdout)

    print("== queue_refill without the module (inline fallback of the two regexes)")
    d2 = os.path.join(d, "nomod")
    os.makedirs(d2)
    shutil.copy(qr, d2)                      # no scripts/ dir beside it: the import fails
    r3 = os.path.join(d2, "repo")
    os.makedirs(r3)
    open(os.path.join(r3, "OVERNIGHT_PROGRESS.md"), "w").write("")
    b3 = os.path.join(d2, "bl.md")
    open(b3, "w").write("\n".join(REAL12[:3] + TAGGED + CLEAN) + "\n")
    out = subprocess.run([sys.executable, os.path.join(d2, "queue_refill.py"), os.path.join(r3, "OVERNIGHT_PROGRESS.md"), b3, "50"], capture_output=True, text=True, env=dict(os.environ, OVN_PARKED_BLOCKED_CI="off"))
    got = [l for l in open(os.path.join(r3, "OVERNIGHT_PROGRESS.md")).read().split("\n") if l.startswith("- [ ] [T")]
    ok("fallback (explicit OVN_PARKED_BLOCKED_CI=off): 3 formerly-parked + 2 clean pulled, tags still parked", len(got) == 5 and not any(E.is_parked(l) for l in got), out.stdout + out.stderr)
    open(os.path.join(r3, "OVERNIGHT_PROGRESS.md"), "w").write("")
    open(b3, "w").write("\n".join(REAL12[:3] + TAGGED + CLEAN) + "\n")
    out = subprocess.run([sys.executable, os.path.join(d2, "queue_refill.py"), os.path.join(r3, "OVERNIGHT_PROGRESS.md"), b3, "50"], capture_output=True, text=True)
    got = [l for l in open(os.path.join(r3, "OVERNIGHT_PROGRESS.md")).read().split("\n") if l.startswith("- [ ] [T")]
    ok("fallback (default): no audit is available, so the 3 lowercase-'blocked' items (and CLEAN[1], 'unblocked') stay parked and only the one clean item is pulled", got == CLEAN[:1], out.stdout + out.stderr)
finally:
    shutil.rmtree(d, ignore_errors=True)

print("== A2: ingest ban filter looks at the TARGET only")
pats = [re.compile("scripts/battle/battle.gd"), re.compile("tests/test_mission_select")]
mk = lambda tgt, ver="`true`": "- [ ] [T2] %s — change it. VERIFY: %s. (cat:python)" % (tgt, ver)  # noqa: E731
ok("addons/ target is banned even with no list", E.is_banned_target(mk("addons/gut/gut.gd"), []))
ok("listed file banned", E.is_banned_target(mk("scripts/battle/battle.gd"), pats))
ok("listed test prefix banned (unanchored ERE like run_overnight)", E.is_banned_target(mk("tests/test_mission_select_extra.gd"), pats))
ok("NEGATIVE: an unlisted file is not banned", not E.is_banned_target(mk("scripts/battle/other.gd"), pats))
ok("NEGATIVE: a banned path only in the VERIFY clause does not count", not E.is_banned_target(mk("scripts/ok.gd", "`grep -q x addons/gut/gut.gd`"), pats))
ok("NEGATIVE: a banned path only in the body does not count", not E.is_banned_target("- [ ] [T2] scripts/ok.gd — mirror addons/gut/gut.gd behaviour. VERIFY: `true`. (cat:python)", pats))
ok("NEGATIVE: docs/ target is not banned", not E.is_banned_target(mk("docs/ARCH.md"), pats))
ok("NEGATIVE: 'myaddons/x' is not an addons/ prefix", not E.is_banned_target(mk("myaddons/x.gd"), pats))
ok("line without a ' — ' separator: never banned", not E.is_banned_target("- [ ] [T2] addons/x.gd no separator VERIFY: `true`", pats))
ok("item_target ignores backticks", E.item_target(mk("`addons/x.gd`")) == "addons/x.gd")
tmpd = tempfile.mkdtemp()
try:
    open(os.path.join(tmpd, ".queue-hard-banned-files"), "w").write("# c\n\nscripts/a.gd\n(unclosed\n")
    ok("load_banned skips comments, blanks and invalid regexes", [p.pattern for p in E.load_banned(tmpd)] == ["scripts/a.gd"])
    ok("load_banned: no file -> []", E.load_banned(os.path.join(tmpd, "nope")) == [])
finally:
    shutil.rmtree(tmpd, ignore_errors=True)

print("== A3: vacuous echo repair")
def sh_rc(cmd, cwd):
    return subprocess.run(["bash", "-c", cmd], cwd=cwd, capture_output=True).returncode


td = tempfile.mkdtemp()
try:
    present = os.path.join(td, "present")
    absent = os.path.join(td, "absent")
    os.makedirs(present)
    os.makedirs(absent)
    open(os.path.join(present, "f.txt"), "w").write("hello old_name\n")
    open(os.path.join(absent, "f.txt"), "w").write("hello new_name\n")
    fp = "- [ ] [T2] f.txt — rename. VERIFY: `grep -q old_name f.txt && echo \"FAIL\" || echo \"PASS\"`. (cat:python)"
    pf = "- [ ] [T2] f.txt — add. VERIFY: `grep -q old_name f.txt && echo \"PASS\" || echo \"FAIL\"`. (cat:python)"
    fp2, n1 = E.normalize_vacuous_echo(fp)
    pf2, n2 = E.normalize_vacuous_echo(pf)
    ok("FAIL/PASS shape rewritten to `! ( cmd )`", n1 == 1 and "VERIFY: `! ( grep -q old_name f.txt )`" in fp2, fp2)
    ok("PASS/FAIL shape rewritten to `cmd`", n2 == 1 and "VERIFY: `grep -q old_name f.txt`" in pf2, pf2)
    c_fp, c_pf = E.extract_verify(fp2), E.extract_verify(pf2)
    ok("BEHAVIOUR: original vacuous shape exits 0 whether or not the thing is there (the defect)", sh_rc(E.extract_verify(fp), present) == 0 and sh_rc(E.extract_verify(fp), absent) == 0)
    ok("BEHAVIOUR: repaired FAIL/PASS is RED while old_name is present, GREEN once it is gone", sh_rc(c_fp, present) != 0 and sh_rc(c_fp, absent) == 0)
    ok("BEHAVIOUR: repaired PASS/FAIL is GREEN while old_name is present, RED when absent", sh_rc(c_pf, present) == 0 and sh_rc(c_pf, absent) != 0)
    ok("idempotent", E.normalize_vacuous_echo(fp2) == (fp2, 0) and E.normalize_vacuous_echo(pf2) == (pf2, 0))
    ok("the repaired VERIFY no longer trips queue_refill's _ALWAYS_TRUE_RE", not re.search(r"\|\|\s*(echo|printf|true)\b", c_fp) and not re.search(r"\|\|\s*(echo|printf|true)\b", c_pf))
    ok("single-quoted / bare echo words are recognised", E.normalize_vacuous_echo(fp.replace('"FAIL"', "'FAIL'").replace('"PASS"', "PASS"))[1] == 1)
    ok("NEGATIVE: awk/pipe shapes are left alone (rule R05 flags them)", E.normalize_vacuous_echo("- [ ] [T2] f — x. VERIFY: `grep old f.txt | awk 'NR>1' && echo \"FAIL\" || echo \"PASS\"`. (cat:python)")[1] == 0)
    ok("NEGATIVE: an ordinary VERIFY is untouched", E.normalize_vacuous_echo("- [ ] [T2] f — x. VERIFY: `grep -q a f.txt`. (cat:python)")[1] == 0)
    ok("NEGATIVE: no VERIFY: untouched", E.normalize_vacuous_echo("- [ ] [T2] f — x.")[1] == 0)
    ok("NEGATIVE: `|| echo` with other words is not the idiom", E.normalize_vacuous_echo("- [ ] [T2] f — x. VERIFY: `grep -q a f && echo ok || echo nope`. (cat:p)")[1] == 0)
    # mutation: swap PASS/FAIL in the FAIL/PASS regex and the polarity assertions above must break
    _s = E._VAC_FAILPASS
    E._VAC_FAILPASS = re.compile(_s.pattern.replace("FAIL", "@@").replace("PASS", "FAIL").replace("@@", "PASS"))
    m_fp, _n = E.normalize_vacuous_echo(fp)
    E._VAC_FAILPASS = _s
    ok("MUTATION (PASS/FAIL swapped in the regex): the repair no longer applies to the real shape, polarity check catches it", _n == 0 or not (sh_rc(E.extract_verify(m_fp), present) != 0 and sh_rc(E.extract_verify(m_fp), absent) == 0))
finally:
    shutil.rmtree(td, ignore_errors=True)

print("== extract_verify parity with queue_refill._extract_verify")
sys.path.insert(0, ROOT)
import importlib.util  # noqa: E402
spec = importlib.util.spec_from_file_location("queue_refill_mod", os.path.join(ROOT, "queue_refill.py"))
QR = importlib.util.module_from_spec(spec)
spec.loader.exec_module(QR)
for l in REAL12 + CLEAN + [fp, pf]:
    if QR._extract_verify(l) != E.extract_verify(l):
        ok("extract parity: " + l[:50], False, (QR._extract_verify(l), E.extract_verify(l)))
        break
else:
    ok("extract_verify == queue_refill._extract_verify on every fixture line", True)
ok("queue_refill.is_parked == module is_parked on every fixture line", all(QR.is_parked(l) == E.is_parked(l) for l in ALL))


# ------------------------------------------------------------------ deploy-order guard (round 3): the other BLOCKED sites cannot silently skip an unlocked item
print("== deploy-order guard: sites that still match BLOCKED case-insensitively")
SITE_LINES = {   # the real shapes (cut from the tree on 2026-10-09): every one MUST be detected
    "scripts/a.sh": "  top=\"$(grep -nE '^- \\[ \\]' \"$prog\" 2>/dev/null | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\\[CLAUDE\\]' | head -1)\"",
    "scripts/b.sh": "_x=\"$(grep -E \"^- \\[ \\]\" P.md | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|BLOCKED|\\[CLAUDE\\]' | head -1)\"",
    "scripts/c.py": "INELIGIBLE = re.compile(r\"HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|BLOCKED|\\(retired-|\\[CLAUDE\\]\", re.I)  # == the pickers' exclusion set",
    "scripts/d.py": "TOP_EXCLUDE_RE = re.compile(r'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\\[CLAUDE\\]', re.IGNORECASE)",
    "qa/e.py": "        if re.search(r\"AUTO-SKIP|HUMAN-ONLY|HARD FILE BAN|BLOCKED|\\[CLAUDE\\]\", ln, re.I):",
    "scripts/f.py": "SKIP_MARK = re.compile(r\"AUTO-SKIP|HUMAN-ONLY|BLOCKED\", re.I)",
    "g.sh": "x=$(grep -nF -- \"$f\" \"$prog\" | grep -viE 'HUMAN-ONLY|AUTO-SKIP|BLOCKED|\\[CLAUDE\\]' | cut -d: -f1)",
}
SAFE_LINES = {   # converted forms and look-alikes: none may be detected
    "scripts/ok1.py": "SKIP = re.compile(r\"HUMAN-ONLY|AUTO-SKIP|(?-i:BLOCKED)|\\[CLAUDE\\]\", re.I)",
    "scripts/ok2.sh": "x=\"$(grep -E '^- \\[ \\]' P | grep -viE 'HUMAN-ONLY|AUTO-SKIP|\\[CLAUDE\\]' | grep -vE 'BLOCKED' | head -1)\"",
    "scripts/ok3.sh": "x=\"$(grep -viE 'HUMAN-ONLY|AUTO-SKIP|BLOCKED ITEM|\\(retired-' P)\"",
    "scripts/ok4.py": "bad = re.compile(r\"AUTO-SKIP|HUMAN-ONLY|human/|\\[CLAUDE\\]|BLOCKED ITEM|\\(retired-\", re.I)",
    "scripts/ok5.sh": "# top=\"$(grep -viE 'HUMAN-ONLY|AUTO-SKIP|BLOCKED|x' P)\"   a comment is not a site",
    "scripts/ok6.sh": "v=\"$(grep -hoiE \"VERDICT:[[:space:]]*(PROCEED|ALREADY-DONE|BLOCKED|NEEDS-DECISION)\" \"$log\" | tail -1)\"",
    "scripts/ok7.sh": "x=\"$(grep -vE 'HUMAN-ONLY|AUTO-SKIP|BLOCKED' P)\"   # case-SENSITIVE grep: not a site",
    "scripts/ok8.py": "SKIP = re.compile(r\"AUTO-SKIP|HUMAN-ONLY|BLOCKED\")   # no re.I: not a site",
    "scripts/test/t.sh": "x=\"$(grep -viE 'HUMAN-ONLY|BLOCKED' P)\"   # test dirs are not scanned",
    "scripts/ok9.sh": "case \"$s\" in *BLOCKED*|*NEEDS-DECISION*) _oc=noop:blocked;; esac",
}


def _tree(files):
    root = tempfile.mkdtemp(prefix="elig-sites-")
    for rel, text in files.items():
        fp = os.path.join(root, rel)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "w").write(text + "\n")
    return root


_t = _tree(SITE_LINES)
found = {x[0] for x in E.unconverted_blocked_sites(_t)}
ok("every real unconverted shape is detected (%d of %d)" % (len(found), len(SITE_LINES)), found == set(SITE_LINES), set(SITE_LINES) - found)
_t2 = _tree(SAFE_LINES)
ok("NEGATIVE: converted forms, tag-only alternations, comments, verdict words, case-sensitive greps and test dirs are not sites", E.unconverted_blocked_sites(_t2) == [], E.unconverted_blocked_sites(_t2))
# the real tree: only files owned by OTHER packages may still hold a site (a NEW unconverted site anywhere else fails this)
_real = {x[0] for x in E.unconverted_blocked_sites(os.path.join(ROOT))}
_OTHER_OWNED = {"run_overnight.sh", "scripts/ovn_churn_guard.py", "scripts/ovn_item_guard.sh", "scripts/ovn_stale_top_item_check.py"}
ok("the real tree has no unconverted BLOCKED site outside the files other packages own", _real <= _OTHER_OWNED, sorted(_real - _OTHER_OWNED))

_saved_env = {k: os.environ.get(k) for k in ("OVN_PARKED_SITES_ROOT", "OVN_PARKED_BLOCKED_CI", "OVN_PARKED_SITES_GUARD")}


def _env(root=None, ci=None, guard=None):
    for k, v in (("OVN_PARKED_SITES_ROOT", root), ("OVN_PARKED_BLOCKED_CI", ci), ("OVN_PARKED_SITES_GUARD", guard)):
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    E._SITES_CACHE.clear()


try:
    _env(root=_t)
    ok("auto (default) with an unconverted site: the 12 lowercase-'blocked' items STAY PARKED (not skipped later in the queue)", all(E.is_parked(l) for l in REAL12))
    ok("... and held_by_sites_guard says so (the 12, none of the clean/tagged lines)", all(E.held_by_sites_guard(l) for l in REAL12) and not any(E.held_by_sites_guard(l) for l in CLEAN[:1] + TAGGED) and E.held_by_sites_guard(CLEAN[1]))
    ok("... and the notice names the first site and the way out", "site(s) still match BLOCKED" in E.sites_guard_notice() and "OVN_PARKED_BLOCKED_CI=off" in E.sites_guard_notice())
    ok("tag parking is unaffected by the guard (AUTO-SKIP / HUMAN-ONLY / BLOCKED tag lines stay parked, clean lines stay pullable)", all(E.is_parked(l) for l in TAGGED) and not E.is_parked(CLEAN[0]))
    _env(root=_t2)
    ok("auto with every site converted: the 12 are pullable (the unlock)", not any(E.is_parked(l) for l in REAL12 + CLEAN))
    _env(root=_t, ci="off")
    ok("OVN_PARKED_BLOCKED_CI=off forces the unlock even with a site left", not any(E.is_parked(l) for l in REAL12))
    _env(root=_t, guard="off")
    ok("OVN_PARKED_SITES_GUARD=off disables the audit", not any(E.is_parked(l) for l in REAL12))
    _env(root=_t2, ci="on")
    ok("OVN_PARKED_BLOCKED_CI=on is still the legacy park-everything switch", all(E.is_parked(l) for l in REAL12))
    # end to end: queue_refill with a site left holds the items back and says why; converting the site pulls them
    d5 = tempfile.mkdtemp(prefix="elig-e2e-")
    try:
        repo5 = os.path.join(d5, "repo")
        os.makedirs(repo5)
        prog5 = os.path.join(repo5, "OVERNIGHT_PROGRESS.md")
        bf5 = os.path.join(d5, "bl.md")
        open(prog5, "w").write("# progress\n")
        open(bf5, "w").write("# backlog\n" + "\n".join(REAL12[:3] + CLEAN[:1]) + "\n")
        env5 = {k: v for k, v in os.environ.items() if not k.startswith("OVN_PARKED")}
        env5["OVN_PARKED_SITES_ROOT"] = _t
        r = subprocess.run([sys.executable, os.path.join(ROOT, "queue_refill.py"), prog5, bf5, "50"], capture_output=True, text=True, env=env5)
        pulled = [l for l in open(prog5).read().split("\n") if l.startswith("- [ ] [T")]
        ok("queue_refill with a site left: only the clean item is pulled, the 3 lowercase-'blocked' items stay in the backlog", pulled == CLEAN[:1] and "REFILL=1" in r.stdout and sum(1 for l in open(bf5) if l.startswith("- [ ]")) == 3, r.stdout + r.stderr)
        ok("... and it says why on stderr (not silent)", "3 lowercase-'blocked' backlog item(s) held back" in r.stderr and "still match BLOCKED" in r.stderr, r.stderr)
        env5["OVN_PARKED_SITES_ROOT"] = _t2
        r = subprocess.run([sys.executable, os.path.join(ROOT, "queue_refill.py"), prog5, bf5, "50"], capture_output=True, text=True, env=env5)
        pulled = [l for l in open(prog5).read().split("\n") if l.startswith("- [ ] [T")]
        ok("queue_refill after the sites are converted: the 3 items are pulled, no hold notice", len(pulled) == 4 and "held back" not in r.stderr and "REFILL=3" in r.stdout, r.stdout + r.stderr)
    finally:
        shutil.rmtree(d5, ignore_errors=True)
    # MUTATION: with the guard neutered (the old behaviour) the held-back assertions above would flip - prove the assertion is load-bearing
    _env(root=_t)
    _g = E.sites_guard_active
    E.sites_guard_active = lambda: False
    ok("MUTATION (guard neutered = the pre-round-3 behaviour): the lowercase items would be pulled while a site still skips them", not any(E.is_parked(l) for l in REAL12))
    E.sites_guard_active = _g
finally:
    for k, v in _saved_env.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    E._SITES_CACHE.clear()

print("== ovn_convert_blocked_sites.py: converts exactly the detected lines, idempotently")
for rel, line in SITE_LINES.items():
    new, done, todo = CV.convert_text(rel, line)
    ok("convert %s: converted, no longer a site, nothing left for a human" % rel, done == [1] and not E._site_in_line(rel, new) and not todo and new != line, new)
    new2, done2, _ = CV.convert_text(rel, new)
    ok("convert %s: idempotent" % rel, new2 == new and done2 == [])
sh_new = CV.convert_text("scripts/a.sh", SITE_LINES["scripts/a.sh"])[0]
ok("shell conversion keeps the picker semantics: two greps, the tag one case-sensitive", "grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|\\[CLAUDE\\]' | grep -vE 'BLOCKED' | head -1" in sh_new, sh_new)
_pipe = "printf '%s\\n' '- [ ] [T2] x blocked_reason y' '- [ ] [T2] x BLOCKED ITEM y' '- [ ] [T2] AUTO-SKIP z' '- [ ] [T2] fine' | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|\\[CLAUDE\\]' | grep -vE 'BLOCKED'"
_old_pipe = _pipe.replace(" | grep -vE 'BLOCKED'", "").replace("\\[CLAUDE\\]'", "\\[CLAUDE\\]|BLOCKED'")
ok("BEHAVIOUR (shell): the converted filter keeps 'blocked_reason' and drops 'BLOCKED ITEM'/AUTO-SKIP; the old filter dropped the lowercase item too",
   subprocess.run(["bash", "-c", _pipe], capture_output=True, text=True).stdout.splitlines() == ["- [ ] [T2] x blocked_reason y", "- [ ] [T2] fine"]
   and subprocess.run(["bash", "-c", _old_pipe], capture_output=True, text=True).stdout.splitlines() == ["- [ ] [T2] fine"])
_re_old = re.compile(r"HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|BLOCKED|\(retired-|\[CLAUDE\]", re.I)
_re_new = re.compile(r"HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|(?-i:BLOCKED)|\(retired-|\[CLAUDE\]", re.I)
ok("BEHAVIOUR (python): (?-i:BLOCKED) keeps the tag case-sensitive inside a re.I pattern while every other tag stays case-insensitive",
   _re_old.search(REAL12[0]) and not _re_new.search(REAL12[0]) and _re_new.search("- [ ] BLOCKED ITEM x") and _re_new.search("- [ ] auto-skip x") and not _re_new.search("- [ ] blocked_reason"))
nv, dn, td = CV.convert_text("scripts/z.sh", "x=$(grep -iE 'HUMAN-ONLY|BLOCKED' P)")
ok("a shell grep that is not an inverted filter is reported for a human and left alone", dn == [] and td == [1] and nv == "x=$(grep -iE 'HUMAN-ONLY|BLOCKED' P)")
_cf = os.path.join(_t, "scripts", "c.py")
r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_convert_blocked_sites.py"), "--dry-run", _cf], capture_output=True, text=True)
ok("CLI --dry-run reports without writing", r.returncode == 0 and "converted 1" in r.stdout and "BLOCKED|" in open(_cf).read() and "(?-i:" not in open(_cf).read(), r.stdout)
r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_convert_blocked_sites.py"), _cf], capture_output=True, text=True)
ok("CLI converts the file in place", r.returncode == 0 and "(?-i:BLOCKED)" in open(_cf).read(), r.stdout + r.stderr)
r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_backlog_eligibility.py"), "sites", _t2], capture_output=True, text=True)
ok("CLI `sites <clean root>`: exit 0, '0 site(s)'", r.returncode == 0 and "0 site(s)" in r.stdout, r.stdout)
r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_backlog_eligibility.py"), "sites", _t], capture_output=True, text=True)
ok("CLI `sites <root with sites>`: exit 1 and lists file:line", r.returncode == 1 and "scripts/a.sh:1:" in r.stdout, r.stdout)
# the shipped patches (only checkable inside the git checkout: the box copy has no docs/)
_pd = os.path.join(ROOT, "..", "..", "docs", "patches")
if os.path.isdir(_pd) and shutil.which("git") and subprocess.run(["git", "-C", ROOT, "rev-parse", "--is-inside-work-tree"], capture_output=True).returncode == 0:
    top = subprocess.run(["git", "-C", ROOT, "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
    for pf in sorted(os.listdir(_pd)):
        if pf.startswith("blocked-sites-") and pf.endswith(".patch") and "run_overnight" not in pf:
            r = subprocess.run(["git", "-C", top, "apply", "--check", "-p1", os.path.abspath(os.path.join(_pd, pf))], capture_output=True, text=True)
            ok("docs/patches/%s applies to the checked-in file (or the file is already converted)" % pf, r.returncode == 0 or "patch does not apply" in r.stderr and not _real, r.stderr)
shutil.rmtree(_t, ignore_errors=True)
shutil.rmtree(_t2, ignore_errors=True)
shutil.rmtree(_CLEAN_ROOT, ignore_errors=True)

print("== sites converted in this package: a lowercase 'blocked' item is no longer skipped (behavioural, per file)")
import ast  # noqa: E402
_CONVERTED = ["ovn_park_unworkable.py", "scripts/ovn_alembic_credit.py", "scripts/ovn_batch_stragglers.py", "scripts/ovn_credit_items.py", "scripts/ovn_fold_migration_items.py", "qa/bug_brief.py"]
_LOWER = "- [ ] [T2] iptv-backend/app/x.py — Add the blocked_reason field. VERIFY: `true`. (cat:python; multifile:no)"
_TAGS = ["- [ ] [T2] x.py — BLOCKED ITEM: read-only", "- [ ] [AUTO-SKIP after 5 cycles] [T2] x.py — y", "- [ ] [auto-skip x] [T2] x.py — y", "- [ ] [T2] x.py — [CLAUDE] z"]
for rel in _CONVERTED:
    src = open(os.path.join(ROOT, rel)).read()
    pats = [n.value for n in ast.walk(ast.parse(src)) if isinstance(n, ast.Constant) and isinstance(n.value, str) and "(?-i:BLOCKED)" in n.value]
    ok("%s: the BLOCKED alternation is now scoped case-sensitive (%d pattern(s))" % (rel, len(pats)), len(pats) >= 1)
    for pat in pats:
        new, old = re.compile(pat, re.I), re.compile(pat.replace("(?-i:BLOCKED)", "BLOCKED"), re.I)
        ok("%s: the lowercase-'blocked' item is NOT matched any more, the tags still are" % rel, not new.search(_LOWER) and new.search(_TAGS[0]) and new.search(_TAGS[1]) and new.search(_TAGS[2]), pat)
        ok("%s: MUTATION (the old case-insensitive form) matches the lowercase item - the assertion above is load-bearing" % rel, bool(old.search(_LOWER)))
_esc = open(os.path.join(ROOT, "scripts", "lib_bug_escalate.sh")).read()
ok("lib_bug_escalate.sh: sibling-step filter uses the two-grep form (case-sensitive BLOCKED)", "grep -viE 'HUMAN-ONLY|AUTO-SKIP|\\[CLAUDE\\]' | grep -vE 'BLOCKED'" in _esc and "|BLOCKED|" not in _esc)

print("\nbacklog eligibility: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
