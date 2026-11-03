#!/usr/bin/env python3
"""scripts/ovn_pingpong_guard.py (package K3 item 1): the literal ping-pong guard, replayed against the REAL gitlark case.

Fixture: fixtures_k3/gitlark_status_pingpong.patchlog is the verbatim `git log -p -U0 --format=@@%H|%ct|%s` of the three real fleet commits
10c57462 / ffc43510 / 9e8b5919 (status_code 201 -> 200 -> 201 on one line of backend/app/routers/workspaces.py, 2026-10-31).
Every check also runs against a MUTANT of the module (the source with exactly one piece of logic broken) and must FAIL there (mutation proof);
the integration checks drive the real script against real git repos (bare origin + fleet clone + live clone), never the network."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

import tmp_track  # noqa: E402
tmp_track.install()

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
SRC = open(os.path.join(SCRIPTS, "ovn_pingpong_guard.py"), encoding="utf-8").read()
CHURN_SRC = os.path.join(SCRIPTS, "ovn_churn_guard.py")
FIXTURE = open(os.path.join(HERE, "fixtures_k3", "gitlark_status_pingpong.patchlog"), encoding="utf-8").read()
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


_n = [0]


def modroot(src):
    """A scratch scripts dir holding the (possibly mutated) guard + the real churn guard it imports."""
    d = os.path.realpath(tempfile.mkdtemp(prefix="ppmod-"))
    with open(os.path.join(d, "ovn_pingpong_guard.py"), "w", encoding="utf-8") as f:
        f.write(src)
    shutil.copy(CHURN_SRC, d)
    return d


def load(src, tag):
    _n[0] += 1
    d = modroot(src)
    for k in [k for k in sys.modules if k in ("ovn_churn_guard",)]:
        del sys.modules[k]
    sys.path.insert(0, d)
    try:
        spec = importlib.util.spec_from_file_location("ovn_pingpong_guard_%s_%d" % (tag, _n[0]), os.path.join(d, "ovn_pingpong_guard.py"))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
    finally:
        sys.path.remove(d)
    m._root = d
    return m


REAL = load(SRC, "real")
NOW = 1793491616 + 3600     # one hour after the third real commit


def mutant_src(old, new):
    c = SRC.count(old)
    if c != 1:
        ok("mutation anchor exists exactly once: %r" % old[:60], False, "found %d" % c)
        return None
    return SRC.replace(old, new)


# ---------------------------------------------------------------- synthetic patch logs
def plog(commits):
    """commits: [(sha, t, subject, path, old_line|None, new_line)] -> a `git log -p -U0` style dump."""
    out = []
    for sha, t, subj, path, old, new in commits:
        out.append("@@%s|%d|%s\n\ndiff --git a/%s b/%s\nindex 1..2 100644\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@" % (sha, t, subj, path, path, path, path))
        if old is not None:
            out.append("-" + old)
        out.append("+" + new)
    return "\n".join(out) + "\n"


def detect(M, text, now=NOW, **kw):
    return M.detect(M.parse_patches(text), now, **kw)


def chk_real_case(M):
    f = detect(M, FIXTURE)
    return (len(f) == 1 and f[0]["file"] == "backend/app/routers/workspaces.py" and f[0]["n"] == 3 and f[0]["revisits"] == 1
            and [c[0] for c in f[0]["commits"]] == ["10c57462", "ffc43510", "9e8b5919"]
            and [v.split("/")[-1] for v in f[0]["values"]] == ["201", "200", "201"])


def forward_only():
    rows = [("a1", NOW - 5000, "fix: raise cap", "app/limits.py", "MAX_ITEMS = 10", "MAX_ITEMS = 20"),
            ("a2", NOW - 4000, "fix: raise cap again", "app/limits.py", "MAX_ITEMS = 20", "MAX_ITEMS = 30"),
            ("a3", NOW - 3000, "fix: raise cap more", "app/limits.py", "MAX_ITEMS = 30", "MAX_ITEMS = 40")]
    return plog(rows)


def chk_forward_only_not_flagged(M):
    return detect(M, forward_only()) == []


def chk_two_flips_not_flagged(M):
    rows = [("c1", NOW - 5000, "fix: a", "backend/app/r.py", "STRICT = False", "STRICT = True"),
            ("c2", NOW - 4000, "fix: b", "backend/app/r.py", "STRICT = True", "STRICT = False")]   # A -> B -> A is a revisit, but only TWO commits
    return detect(M, plog(rows)) == []


def chk_distinct_tests_not_collapsed(M):
    """K3 review fix: the SAME masked line shape in two different functions of one file is two keys (hunk-header context), not one ping-pong."""
    line = "    assert resp.status_code == %d"
    rows = [("d1", NOW - 6000, "fix: a", "tests/test_x.py", "test_a", line % 200, line % 201),
            ("d2", NOW - 5000, "fix: b", "tests/test_x.py", "test_b", line % 201, line % 200),
            ("d3", NOW - 4000, "fix: c", "tests/test_x.py", "test_b", line % 200, line % 201)]
    out = []
    for sha, t, subj, path, ctx, old, new in rows:
        out.append("@@%s|%d|%s\n\ndiff --git a/%s b/%s\nindex 1..2 100644\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@ def %s():\n-%s\n+%s" % (sha, t, subj, path, path, path, path, ctx, old, new))
    return detect(M, "\n".join(out) + "\n") == []


def chk_bool_flip_seeded(M):
    rows = [("b1", NOW - 6000, "fix: x", "app/cfg.py", "STRICT = True", "STRICT = False"),
            ("b2", NOW - 5000, "fix: y", "app/cfg.py", "STRICT = False", "STRICT = True"),
            ("b3", NOW - 4000, "fix: z", "app/cfg.py", "STRICT = True", "STRICT = False")]
    f = detect(M, plog(rows))
    return len(f) == 1 and f[0]["n"] == 3 and f[0]["revisits"] == 2


def chk_bookkeeping_ignored(M):
    rows = [("d1", NOW - 6000, "chore(queue): park", "app/cfg.py", "STRICT = True", "STRICT = False"),
            ("d2", NOW - 5000, "chore(queue): park", "app/cfg.py", "STRICT = False", "STRICT = True"),
            ("d3", NOW - 4000, "chore(queue): park", "app/cfg.py", "STRICT = True", "STRICT = False")]
    rows2 = [("e1", NOW - 6000, "fix: a", "docs/NOTES.md", "level = 1", "level = 2"),
             ("e2", NOW - 5000, "fix: b", "docs/NOTES.md", "level = 2", "level = 1"),
             ("e3", NOW - 4000, "fix: c", "docs/NOTES.md", "level = 1", "level = 2")]
    return detect(M, plog(rows)) == [] and detect(M, plog(rows2)) == []


def chk_window(M):
    return detect(M, FIXTURE, now=NOW + 3 * 86400) == [] and len(detect(M, FIXTURE)) == 1


OPEN_TEXT = """# Progress
- [ ] [T3] backend/app/routers/workspaces.py — tidy the conversation route. VERIFY: `true`.
- [ ] [T2] backend/app/routers/other.py — unrelated item. VERIFY: `true`.
- [ ] [CLAUDE] [T3] backend/app/routers/workspaces.py — already escalated.
- [ ] EMERGENCY [T5] backend/app/routers/workspaces.py — manual fire.
- [x] [T1] backend/app/routers/workspaces.py — finished.
"""


def findings_for(M):
    f = detect(M, FIXTURE)
    f[0]["tests"] = ["backend/tests/test_workspaces_conversations.py"]
    f[0]["aliases"] = []
    return f


def chk_plan(M):
    f = findings_for(M)
    new, parked, protected, follow = M.plan(OPEN_TEXT, f, None, 10)
    L = new.split("\n")
    return (parked["backend/app/routers/workspaces.py"] == 1 and len(follow) == 1
            and L[1].startswith("- [ ] [AUTO-SKIP pingpong: backend/app/routers/workspaces.py line literal flipped 3 times in 24h") and "recovery:none]" in L[1]
            and L[2].startswith("- [ ] [CLAUDE] [AUTO-SKIP pingpong-followup:") and "test_workspaces_conversations.py" in L[2] and "10c57462" in L[2] and "9e8b5919" in L[2]
            and L[3] == "- [ ] [T2] backend/app/routers/other.py — unrelated item. VERIFY: `true`."
            and "already escalated" in new and any(x == "- [ ] [CLAUDE] [T3] backend/app/routers/workspaces.py — already escalated." for x in L)
            and "- [ ] EMERGENCY [T5] backend/app/routers/workspaces.py — manual fire." in L and len(protected) == 1
            and M.only_expected_edits(OPEN_TEXT, new, 1, 1))


def chk_followup_once(M):
    f = findings_for(M)
    new, _, _, _ = M.plan(OPEN_TEXT, f, None, 10)
    new2, parked2, _, follow2 = M.plan(new, f, None, 10)
    return follow2 == [] and new2.count("pingpong-followup:") == 1


def chk_post_check_rejects_tamper(M):
    f = findings_for(M)
    new, _, _, _ = M.plan(OPEN_TEXT, f, None, 10)
    return M.only_expected_edits(OPEN_TEXT, new.replace("tidy the conversation route", "tidy the ROUTE"), 1, 1) is False


def chk_tag_is_recoverable_safe(M):
    f = findings_for(M)
    return "recovery:none]" in M.tag_text(f[0]) and "recovery:none]" in M.follow_text(f[0]) and "[CLAUDE]" in M.follow_text(f[0])


# ---------------------------------------------------------------- integration (real git)
GENV = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_AUTHOR_NAME="fleet", GIT_AUTHOR_EMAIL="f@f",
            GIT_COMMITTER_NAME="fleet", GIT_COMMITTER_EMAIL="f@f", NTFY_SERVER="http://127.0.0.1:9/x")


def g(args, cwd, when=None, check=True):
    env = dict(GENV)
    if when:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = "%d +0000" % when
    p = subprocess.run(["git"] + args, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and p.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (args, p.stderr.decode()[:200]))
    return p.stdout.decode()


ROUTE_OLD = '@router.post("/{workspace_id}/conversations", response_model=ConversationResponse)'
ROUTE_201 = '@router.post("/{workspace_id}/conversations", response_model=ConversationResponse, status_code=201)'
ROUTE_200 = '@router.post("/{workspace_id}/conversations", response_model=ConversationResponse, status_code=200)'
TEST_BODY = 'def test_owner_can_create_conversation(client):\n    response = client.post("/api/workspaces/w1/conversations", json={})\n    assert response.status_code == 201\n'


def make_env(flips):
    """-> dict(ovn, origin, work, live). flips = status codes the three fleet commits set, oldest first (None entry = first commit adds the arg)."""
    d = os.path.realpath(tempfile.mkdtemp(prefix="ppint-"))
    ovn = os.path.join(d, "ovn")
    origin, work, live = os.path.join(d, "origin.git"), os.path.join(d, "work"), os.path.join(ovn, "repos", "gitlark")
    os.makedirs(os.path.join(ovn, "repos"))
    os.makedirs(os.path.join(ovn, "state"))
    os.makedirs(os.path.join(ovn, "logs"))
    g(["init", "-q", "--bare", origin], d)
    g(["symbolic-ref", "HEAD", "refs/heads/overnight/feature"], origin)
    g(["clone", "-q", origin, work], d, check=False)
    g(["checkout", "-q", "-b", "overnight/feature"], work)
    os.makedirs(os.path.join(work, "backend/app/routers"))
    os.makedirs(os.path.join(work, "backend/tests"))
    with open(os.path.join(work, "backend/app/routers/workspaces.py"), "w") as fh:
        fh.write("import x\n\n\n%s\nasync def create_workspace_conversation():\n    return 1\n" % ROUTE_OLD)
    with open(os.path.join(work, "backend/tests/test_workspaces_conversations.py"), "w") as fh:
        fh.write(TEST_BODY)
    with open(os.path.join(work, "OVERNIGHT_PROGRESS.md"), "w") as fh:
        fh.write(OPEN_TEXT)
    g(["add", "-A"], work)
    now = int(time.time())
    g(["commit", "-q", "-m", "chore: init"], work, when=now - 40 * 3600)
    g(["push", "-q", "origin", "overnight/feature"], work)
    subj = ["fix: set %s status code for workspace conversation creation", "fix: change conversation creation endpoint status code to %s", "fix: change conversation creation endpoint status code to %s"]
    for i, code in enumerate(flips):
        line = ROUTE_OLD if code is None else '@router.post("/{workspace_id}/conversations", response_model=ConversationResponse, status_code=%s)' % code
        p = os.path.join(work, "backend/app/routers/workspaces.py")
        body = open(p).read().split("\n")
        body[3] = line
        with open(p, "w") as fh:
            fh.write("\n".join(body))
        g(["add", "-A"], work)
        g(["commit", "-q", "-m", subj[min(i, 2)] % code], work, when=now - (20 - 7 * i) * 3600)
    g(["push", "-q", "origin", "overnight/feature"], work)
    g(["clone", "-q", origin, live], d, check=False)
    g(["checkout", "-q", "overnight/feature"], live)
    return {"d": d, "ovn": ovn, "origin": origin, "work": work, "live": live}


def run_guard(root, E, **env):
    e = dict(GENV, OVN_DIR=E["ovn"], OVN_REPOS_DIR=os.path.join(E["ovn"], "repos"), OVN_STATE_DIR=os.path.join(E["ovn"], "state"), OVN_PINGPONG_REPOS="gitlark")
    e.update(env)
    p = subprocess.run([sys.executable, os.path.join(root, "ovn_pingpong_guard.py")], env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    return p.returncode, p.stdout.decode()


def tip(E):
    return g(["rev-parse", "overnight/feature"], E["origin"]).strip()


def prog(E):
    return g(["show", "overnight/feature:OVERNIGHT_PROGRESS.md"], E["origin"])


def read(path):
    try:
        return open(path).read()
    except OSError:
        return ""


def live_sig(E):
    return (g(["rev-parse", "HEAD"], E["live"]) + g(["status", "--porcelain"], E["live"])).strip()


def integ_shadow(root):
    """default mode: nothing is written to the branch; one shadow-log line + one alerts.log info line, deduped."""
    E = make_env([201, 200, 201])
    ovn = E["ovn"]
    before, lsig = tip(E), live_sig(E)
    rc, _ = run_guard(root, E)
    rc2, _ = run_guard(root, E)
    shadow = read(os.path.join(ovn, "state", "pingpong_shadow.log"))
    alerts = read(os.path.join(ovn, "state", "alerts.log"))
    res = (rc == 0 and rc2 == 0 and tip(E) == before and live_sig(E) == lsig and shadow.count("\n") == 1
           and "backend/app/routers/workspaces.py" in shadow and "would-park=1" in shadow and "test_workspaces_conversations.py" in shadow
           and alerts.count("pingpong-guard:gitlark") == 1 and "] info |" in alerts and "SHADOW" in alerts and "pingpong-followup" not in prog(E))
    return res, ("shadow=%r alerts=%r" % (shadow[:200], alerts[:200]))


def integ_enforce(root):
    E = make_env([201, 200, 201])
    ovn = E["ovn"]
    before, lsig = tip(E), live_sig(E)
    rc, out = run_guard(root, E, OVN_PINGPONG_MODE="enforce")
    after = tip(E)
    txt = prog(E)
    files = g(["diff", "--name-only", before, after], E["origin"]).split()
    alerts = read(os.path.join(ovn, "state", "alerts.log"))
    rc2, _ = run_guard(root, E, OVN_PINGPONG_MODE="enforce")
    L = txt.split("\n")
    res = (rc == 0 and after != before and files == ["OVERNIGHT_PROGRESS.md"] and rc2 == 0 and tip(E) == after
           and L[1].startswith("- [ ] [AUTO-SKIP pingpong: backend/app/routers/workspaces.py line literal flipped 3 times in 24h")
           and L[2].startswith("- [ ] [CLAUDE] [AUTO-SKIP pingpong-followup:") and "test_workspaces_conversations.py" in L[2] and txt.count("pingpong-followup:") == 1
           and "- [ ] EMERGENCY [T5] backend/app/routers/workspaces.py — manual fire." in L
           and "- [ ] [T2] backend/app/routers/other.py — unrelated item. VERIFY: `true`." in L
           and live_sig(E) == lsig and alerts.count("] warn | pingpong-guard:gitlark") == 1 and "parked 1 queue item(s)" in alerts
           and g(["log", "-1", "--format=%an", "overnight/feature"], E["origin"]).strip() == "shrike-fleet")
    return res, ("tip=%s txt=%r alerts=%r out=%r" % (after[:8], txt[:300], alerts[:200], out[-200:]))


def integ_benign(root):
    """forward-only (no revisit) and only-two-flips repos: nothing logged, nothing written, in BOTH modes."""
    E = make_env([201, 200, 202])
    before = tip(E)
    a = run_guard(root, E, OVN_PINGPONG_MODE="enforce")
    b = run_guard(root, E)
    E2 = make_env([201, 200])
    before2 = tip(E2)
    run_guard(root, E2, OVN_PINGPONG_MODE="enforce")
    return (a[0] == 0 and b[0] == 0 and tip(E) == before and tip(E2) == before2 and read(os.path.join(E["ovn"], "state", "pingpong_shadow.log")) == ""
            and not os.path.exists(os.path.join(E["ovn"], "state", "alerts.log"))), ""


def main():
    print("== pingpong guard: replay of the real gitlark case (10c57462 / ffc43510 / 9e8b5919) ==")
    unit = [("real gitlark case flagged (3 commits, 201/200/201, one revisit, commit order)", chk_real_case, r'|(?<![\w.])(-?\d+(?:\.\d+)?)(?![\w.])', r'|(?<![\w.])(NEVERMATCH\d+(?:\.\d+)?)(?![\w.])'),
            ("forward-only edits (10->20->30->40) are NOT a ping-pong", chk_forward_only_not_flagged, 'if kind == "literal" and revisits < 1:', 'if False:'),
            ("only two commits on the line are NOT enough", chk_two_flips_not_flagged, 'min_n = MIN_N if min_n is None else min_n', 'min_n = 2'),
            ("same line shape in two different test functions is NOT one ping-pong", chk_distinct_tests_not_collapsed, 'state.setdefault((path, nk, ctx), {', 'state.setdefault((path, nk, ""), {'),
            ("seeded True/False flips (3 commits, 2 revisits) flagged", chk_bool_flip_seeded, 'walk = {st["seed"]} if st["seed"] is not None else set()', 'walk = set()'),
            ("bookkeeping subjects/files never count", chk_bookkeeping_ignored, 'if cg.BOOKKEEP_FILE.search(path):', 'if False:'),
            ("the 24h window bounds the detection", chk_window, 'lo = now - window_h * 3600', 'lo = 0'),
            ("plan(): parks only the matching eligible item, leaves [CLAUDE]/EMERGENCY/unrelated/checked lines, adds ONE follow-up citing test + commits", chk_plan,
             'if kind == "protected":', 'if False:'),
            ("plan(): the follow-up is added once per line family", chk_followup_once, 'if ("pingpong-followup:%s" % f["fid"]) in text:', 'if False:'),
            ("post-check rejects any edit beyond tags + follow-ups", chk_post_check_rejects_tamper,
             'return len(diff) == n_tags and all(x.startswith("- [ ] ") and y.startswith("- [ ] " + TAG_PREFIX) and y.endswith(x[len("- [ ] "):]) for x, y in diff)', 'return len(diff) == n_tags'),
            ("tag + follow-up carry recovery:none and the [CLAUDE] marker", chk_tag_is_recoverable_safe, 'needs Claude; recovery:none] " % (TAG_PREFIX', 'needs Claude] " % (TAG_PREFIX')]
    for label, chk, old, new in unit:
        ok(label + ": passes on the real module", bool(chk(REAL)))
        msrc = mutant_src(old, new)
        if msrc is not None:
            m = load(msrc, "mut")
            try:
                bad = bool(chk(m))
            except Exception as e:
                bad = False
                label += " [mutant raised %s]" % type(e).__name__
            ok("MUTATION caught: %s" % label, not bad)
    print("== pingpong guard: real git integration (shadow default / enforce / benign controls) ==")
    root = REAL._root
    res, extra = integ_shadow(root)
    ok("shadow default: branch + live clone untouched, ONE shadow-log line + ONE info alert, deduped on re-run", res, extra)
    res, extra = integ_enforce(root)
    ok("enforce: one chore(queue) commit touching only OVERNIGHT_PROGRESS.md; item parked, Claude follow-up cites test + commits; bug/EMERGENCY left; idempotent", res, extra)
    res, extra = integ_benign(root)
    ok("benign controls (forward-only; two flips) leave everything untouched", res, extra)
    # mutation proofs for the integration behaviour
    m = mutant_src('if DRY or MODE != "enforce":', 'if DRY:')
    if m is not None:
        mr = modroot(m)
        res, _ = integ_shadow(mr)
        ok("MUTATION caught: shadow mode that writes to the branch fails the shadow check", not res)
    print("pingpong guard: %d passed, %d failed" % (P, F))
    return 0 if F == 0 else 1


if __name__ == "__main__":
    rc = main()
    tmp_track.sweep()
    sys.exit(rc)
