#!/usr/bin/env python3
"""Bugs-first policy (2026-10-02, branch qa/h8-bug-first) - the STATUS VOCABULARY + RETEST LOOP.

  * qa/manual_notes_ingest.py: 'escalated' (the guard's '[CLAUDE] [bug-escalated: ...]' tag), 'fixed (awaiting your retest)' label,
    'closed' / reopen via `retest` (ok closes; still-broken reopens at the top with the note attached and a FRESH [feat:..rN] => fresh attempt counters),
    idempotency, no-match behaviour, sanitizer defusing 'blocked' (a note word that would make its own queue item invisible to every selector).
  * contract: the bug items the REAL ingest writes (add + reopen) are recognised by the loop's selector (lib_item_select.sh ovn_has_bug_line).
  * scripts/qa-retest (Mac side, run from a copy in a temp tree - never the real manual logs), scripts/qa-notes-bridge.sh (stub ssh that runs the
    REAL ingest against a fixture: retest lines end to end, unmatched still-broken -> new bug, status cache) and scripts/qa-status (counts per status).
Real entry points, `env -i` minimal PATH, NTFY_SERVER = a LOCAL stub relay (nothing reaches ntfy.sh), fixture git repos with a bare origin.
Runs on the Mac and on the box (the Mac-side script sections skip when the script is not on this machine):  python3 scripts/test/test_qa_retest.py
"""
import base64
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
OVNQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OVNQ, "qa")
INGEST = os.path.join(QA, "manual_notes_ingest.py")
LIB = os.path.join(OVNQ, "scripts", "lib_item_select.sh")
SCRIPTS = os.path.abspath(os.path.join(OVNQ, ".."))                       # <shared>/scripts (Mac side) - absent on the box
BRIDGE = os.path.join(SCRIPTS, "qa-notes-bridge.sh")
RETEST = os.path.join(SCRIPTS, "qa-retest")
STATUS = os.path.join(SCRIPTS, "qa-status")
sys.path.insert(0, QA)
import manual_notes_ingest as mn  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        x = str(extra)
        print("  FAIL " + name + (("  :: " + (x if len(x) < 900 else x[:300] + " ... " + x[-600:])) if extra else ""))


ROOT = tempfile.mkdtemp(prefix="qa-retest-test-")
MINPATH = "/usr/bin:/bin"


def sh(cmd, cwd=None, env=None, timeout=120, check=False):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=timeout)
    out = (p.stdout + p.stderr).decode("utf-8", "replace")
    if check and p.returncode != 0:
        raise RuntimeError("%s failed: %s" % (cmd, out))
    return p.returncode, out


def git(cwd, *a):
    return sh(["git", "-C", cwd, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a), check=True)[1]


class Recorder(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        self.server.hits.append({"path": self.path, "headers": dict(self.headers), "body": self.rfile.read(n).decode("utf-8", "replace")})
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"{}")


relay = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Recorder)
relay.hits = []
threading.Thread(target=relay.serve_forever, daemon=True).start()
RELAY = "http://127.0.0.1:%d" % relay.server_address[1]

FILES = {
    "OVERNIGHT_PROGRESS.md": "# Progress\n\n## Current Status\nfine\n\n## Next Steps\n- [ ] [T1] backend/app/other.py — a roadmap item. VERIFY: `pytest -q`. (cat:python; multifile:no)\n",
    "backend/app/routers/alerts.py": "def list_alerts():\n    return []\n",
    "backend/app/routers/exports.py": "def export_all():\n    return []\n",
    "backend/tests/test_alerts_router.py": "def test_a():\n    assert True\n",
    "backend/tests/test_exports.py": "def test_e():\n    assert True\n",
}


class Fix:
    def __init__(self, name):
        self.d = os.path.join(ROOT, name)
        self.ovn = os.path.join(self.d, "ovn")
        self.origin = os.path.join(self.d, "origin.git")
        self.work = os.path.join(self.d, "work")
        self.clone = os.path.join(self.ovn, "repos", "fx")
        os.makedirs(os.path.join(self.ovn, "state"))
        os.makedirs(os.path.join(self.ovn, "repos"))
        git(self.d, "init", "-q", "--bare", self.origin)
        git(self.d, "clone", "-q", self.origin, self.work)
        git(self.work, "checkout", "-q", "-b", "overnight/feature")
        for p, c in FILES.items():
            fp = os.path.join(self.work, p)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            open(fp, "w").write(c)
        git(self.work, "add", "--force", ".")
        git(self.work, "commit", "-q", "-m", "init")
        git(self.work, "push", "-q", "origin", "overnight/feature")
        git(self.d, "clone", "-q", "-b", "overnight/feature", self.origin, self.clone)
        self.calls = os.path.join(self.ovn, "state", "calls.log")
        open(os.path.join(self.ovn, "queue.sh"), "w").write('#!/usr/bin/env bash\necho "queue $1 $2" >> "%s"\n' % self.calls)
        open(os.path.join(self.ovn, "qa_mode.sh"), "w").write('#!/usr/bin/env bash\necho "qa_mode $1 $2" >> "%s"\n' % self.calls)

    def env(self, **kw):
        e = {"PATH": MINPATH, "HOME": self.d, "OVN_DIR": self.ovn, "NTFY_SERVER": RELAY, "NTFY_TOPIC": "t-test", "OVN_MANUAL_MODEL": "off"}
        e.update(kw)
        return e

    def cli(self, *args, **kw):
        return sh(["env", "-i"] + ["%s=%s" % kv for kv in self.env(**kw).items()] + [INGEST] + list(args))

    def add(self, note, flow, date="2026-10-02"):
        b64 = base64.b64encode(note.encode()).decode()
        return self.cli("add", "--repo", "fx", "--date", date, "--flow", flow, "--minutes", "5", "--note-b64", b64)

    def retest(self, flow, result, note="", date="2026-10-02", extra=()):
        b64 = base64.b64encode(note.encode()).decode()
        return self.cli("retest", "--repo", "fx", "--date", date, "--flow", flow, "--result", result, "--note-b64", b64, *extra)

    def state(self):
        try:
            return json.load(open(os.path.join(self.ovn, "state", "manual_notes.json")))["entries"]
        except OSError:
            return {}

    def entry(self, flow):
        es = [e for e in self.state().values() if e["flow"] == flow]
        return es[-1] if es else None

    def progress(self):
        return sh(["git", "--git-dir=" + self.origin, "show", "overnight/feature:OVERNIGHT_PROGRESS.md"])[1]

    def origin_edit(self, fn, msg="edit"):
        git(self.work, "pull", "-q", "--rebase", "origin", "overnight/feature")
        p = os.path.join(self.work, "OVERNIGHT_PROGRESS.md")
        new = fn(open(p).read())
        open(p, "w").write(new)
        git(self.work, "add", "OVERNIGHT_PROGRESS.md")
        git(self.work, "commit", "-q", "-m", msg)
        git(self.work, "push", "-q", "origin", "overnight/feature")

    def mark_fixed(self, flow):
        e = self.entry(flow)
        self.land_fix(e)
        self.origin_edit(lambda t: t.replace("- [ ] " + e["item"][len("- [ ] "):], "- [x] " + e["item"][len("- [ ] "):]), "fleet landed")
        return self.cli("sweep")

    def land_fix(self, e):
        """A REAL landed fix (2026-10-03): a source change to the located file + a test with a real assertion that names it. The sweep no longer says
        'fixed' for a bare '[x]' (the closed-captions false credit: a placeholder test, no source change)."""
        git(self.work, "pull", "-q", "--rebase", "origin", "overnight/feature")
        src = e["path"]
        stem = os.path.splitext(os.path.basename(src))[0]
        with open(os.path.join(self.work, src), "a") as f:
            f.write("\n// fixed\n")
        if src.endswith(".py"):
            tp, body = "backend/tests/test_landed_%s.py" % stem, "def test_landed_%s():\n    assert len('%s') > 0\n" % (stem, stem)
        else:
            tp, body = "app-web/src/views/__tests__/Landed%s.test.ts" % stem, "test('%s works', () => { expect(%s).toBeDefined() })\n" % (stem, stem)
        os.makedirs(os.path.dirname(os.path.join(self.work, tp)), exist_ok=True)
        open(os.path.join(self.work, tp), "w").write(body)
        git(self.work, "add", src, tp)
        git(self.work, "commit", "-q", "-m", "fix: land %s" % stem)
        git(self.work, "push", "-q", "origin", "overnight/feature")

    def mark_escalated(self, flow, tag="[CLAUDE] [bug-escalated: 2 failed attempts (cap 2), last: no-op(x)] "):
        e = self.entry(flow)
        self.origin_edit(lambda t: t.replace("- [ ] " + e["item"][len("- [ ] "):], "- [ ] " + tag + e["item"][len("- [ ] "):]), "guard escalated")
        return self.cli("sweep")


def shell_has_bug(line):
    """The loop's own selector: does lib_item_select.sh's ovn_has_bug_line recognise this queue line?"""
    r = subprocess.run(["bash", "-c", 'source "$1"; printf "%s\\n" "$2" | ovn_has_bug_line', "x", LIB, line], capture_output=True)
    return r.returncode == 0


NOTE_A = "backend/app/routers/alerts.py returns an empty list for a brand new account"
NOTE_B = "backend/app/routers/exports.py export_all returns nothing when blocked by a rate limit"

# ============================================================================================================ status vocabulary
print("== classify_lines: escalated")
st, why = mn.classify_lines(["- [ ] [CLAUDE] [bug-escalated: 2 failed attempts (cap 2), last: x] [T3] a.py — Manual-test bug (src:manual) [feat:r-20261002-manual-aaaa1111]"])
ok("a line tagged [CLAUDE] [bug-escalated: ...] classifies as 'escalated'", st == "escalated", (st, why))
st, _ = mn.classify_lines(["- [ ] [CLAUDE] [unworkable: banned file] [T3] a.py — x"])
ok("a plain [CLAUDE] park is still 'needs-human' (unchanged)", st == "needs-human")
st, _ = mn.classify_lines(["- [ ] [AUTO-SKIP after 4 cycles] [T3] a.py — x"])
ok("AUTO-SKIP is still 'needs-human' (unchanged)", st == "needs-human")
st, _ = mn.classify_lines(["- [x] done a.py"])
ok("[x] is still 'fixed' (unchanged)", st == "fixed")
st, _ = mn.classify_lines(["- [ ] [CLAUDE] [bug-escalated: x] a.py", "- [ ] [T3] b.py open step"])
ok("an open sibling step keeps the bug 'open'", st == "open")

print("== sanitizer: words that would hide the item from every selector")
s = mn.sanitize_note("playback is BLOCKED after login, see human/ops and the HARD FILE BAN list")
ok("'blocked' / 'human/' / 'hard file ban' defused (selectors drop lines containing them)", "blocked" not in s.lower() and "human/" not in s.lower() and "hard file ban" not in s.lower(), s)
ok("...the note stays readable", "playback is" in s and "after login" in s, s)

# ============================================================================================================ ingest retest
print("== retest: the loop's selector recognises what the ingest writes")
A = Fix("a")
rc, out = A.add(NOTE_A, "alerts-empty")
ok("fixture: add enqueued the bug", rc == 0 and "status=open" in out, out)
item = A.entry("alerts-empty")["item"]
ok("contract: the REAL ingest's item is recognised by ovn_has_bug_line", shell_has_bug(item), item)
ok("contract: a roadmap line is not", not shell_has_bug(FILES["OVERNIGHT_PROGRESS.md"].split("\n")[-2]))
ok("contract: the item survives the loop's own park filters (no BLOCKED / HUMAN-ONLY / AUTO-SKIP / [CLAUDE])", not any(w in item.upper() for w in ("BLOCKED", "HUMAN-ONLY", "AUTO-SKIP", "[CLAUDE]")))
rc, out = A.add(NOTE_B, "exports-empty")
e_b = A.entry("exports-empty")
ok("a note containing 'blocked' still yields a selectable item (the word was defused)", "BLOCKED" not in e_b["item"].upper() and shell_has_bug(e_b["item"]), e_b["item"])

print("== retest: fixed -> awaiting retest -> ok closes")
relay.hits.clear()
rc, out = A.mark_fixed("alerts-empty")
ok("sweep: the checked-off bug is 'fixed'", A.entry("alerts-empty")["status"] == "fixed", out)
ok("fixed note tells him how to retest", any("qa-retest" in h["body"] for h in relay.hits), [h["body"] for h in relay.hits])
rc, out = A.cli("list")
ok("list: status key spells out 'fixed (awaiting your retest)'", "fixed (awaiting your retest)" in out and "status key:" in out, out)
rc, out = A.retest("alerts-empty", "ok", "works now")
e = A.entry("alerts-empty")
ok("retest ok: RETESTED, status closed, closed_at recorded", rc == 0 and out.startswith("RETESTED") and e["status"] == "closed" and e.get("closed_at"), (rc, out, e["status"]))
ok("retest ok: the retest is stored with its note", e["retests"][-1]["result"] == "ok" and e["retests"][-1]["note"] == "works now", e.get("retests"))
rc, out = A.retest("alerts-empty", "ok", "works now")
ok("retest ok again (bridge re-send after a lost ack): DUPLICATE, rc 0, nothing changes", rc == 0 and out.startswith("DUPLICATE") and len(A.entry("alerts-empty")["retests"]) == 1, (rc, out))
rc, out = A.retest("alerts-empty", "ok", "different note")
ok("retest ok on an already closed flow with a new note: permanent reject rc 2 (nothing awaiting a retest)", rc == 2 and out.startswith("NOMATCH"), (rc, out))
rc, out = A.cli("list")
ok("list shows closed with its label", "closed (retest ok)" in out, out)
rc, out = A.retest("no-such-flow", "ok")
ok("retest ok for an unknown flow: rc 2 NOMATCH", rc == 2 and out.startswith("NOMATCH"), (rc, out))

print("== retest: still-broken reopens at the top with the note and fresh counters")
B = Fix("b")
B.add(NOTE_A, "alerts-empty")
before = B.entry("alerts-empty")
old_feat = before["feat"]
B.mark_fixed("alerts-empty")
rc, out = B.retest("alerts-empty", "still-broken", "Still empty for new accounts on the second login")
e = B.entry("alerts-empty")
ok("still-broken: REOPENED, status open, retest_count 1", rc == 0 and out.startswith("REOPENED") and e["status"] == "open" and e["retest_count"] == 1, (rc, out, e["status"]))
ok("new feat tag is <old>.r1 (=> new item hash => the loop's counters start at zero)", e["feat"] == old_feat + ".r1" and e["feat_history"] == [old_feat], e["feat"])
prog = B.progress()
first = [l for l in prog.split("\n") if l.startswith("- [")][0]
ok("the reopened item is the FIRST line under '## Next Steps' (top priority)", "[feat:%s]" % e["feat"] in first and first.startswith("- [ ]"), first[:200])
ok("the retest note is attached to the item", "RETEST FAILED 2026-10-02" in first and "Still empty for new accounts on the second login" in first, first)
ok("the item still carries the original bug report, VERIFY and src:manual", "Manual-test bug (reported by Mark" in first and "VERIFY:" in first and "src:manual" in first, first)
ok("the item tells the fleet not to repeat the earlier change and names the original feat tag", "do NOT repeat the same change" in first and ("under feat tag %s " % old_feat) in first and first.count("[feat:") == 1, first)
ok("the old (checked-off) line is still in the file, untouched", "- [x] " in prog and ("[feat:%s]" % old_feat) in prog)
ok("contract: the reopened item is recognised by the loop's selector", shell_has_bug(first), first)
shell = subprocess.run(["bash", "-c", 'source "$1"; tmp=$(mktemp -d); printf "%s\\n" "$2" > "$tmp/OVERNIGHT_PROGRESS.md"; ovn_resolve_top_item "$tmp"; rm -rf "$tmp"', "x", LIB, prog], capture_output=True)
ok("contract: ovn_resolve_top_item over the real file after reopening returns the reopened bug, ahead of the roadmap item", b"RETEST FAILED" in shell.stdout, shell.stdout[:300])
h_old = subprocess.run(["bash", "-c", 'source "$1"; ovn_item_hash "$2"', "x", LIB, item], capture_output=True).stdout
h_new = subprocess.run(["bash", "-c", 'source "$1"; ovn_item_hash "$2"', "x", LIB, first], capture_output=True).stdout
ok("the loop's item hash of the reopened item DIFFERS from the original (fresh attempt counter by construction)", h_old and h_new and h_old != h_new, (h_old, h_new))
rc, out = B.retest("alerts-empty", "still-broken", "Still empty for new accounts on the second login")
ok("the same verdict re-sent: DUPLICATE (no second reopen)", out.startswith("DUPLICATE") and B.entry("alerts-empty")["retest_count"] == 1 and B.progress().count("RETEST FAILED") == 1, out)
rc, out = B.cli("sweep")
ok("sweep after the reopen tracks the NEW tag (open) and does not mark the old [x] line as a fix", B.entry("alerts-empty")["status"] == "open", (out, B.entry("alerts-empty")["status"]))
# second round: escalated by the guard -> still-broken again -> .r2
B.mark_escalated("alerts-empty")
ok("sweep: the guard's escalation tag => status 'escalated'", B.entry("alerts-empty")["status"] == "escalated", B.entry("alerts-empty")["status"])
relay.hits.clear()
B.cli("sweep")
ok("sweep sends NO relay note for 'escalated' (the guard already sent the single note)", not relay.hits, relay.hits)
rc, out = B.retest("alerts-empty", "still-broken", "Claude's fix did not work either", date="2026-10-03")
e = B.entry("alerts-empty")
ok("a retest of an ESCALATED bug reopens it too (.r2)", out.startswith("REOPENED") and e["feat"] == old_feat + ".r2" and e["retest_count"] == 2, (out, e["feat"]))
ok("only the latest feat suffix: .r2 not .r1.r2", ".r1.r2" not in e["feat"] and ".r1.r2" not in B.progress())
rc, out = B.retest("alerts-empty", "still-broken", "x", date="2026-10-04")
ok("still-broken on a bug that is already OPEN again: rc 3 (the bridge files it as a new bug)", rc == 3 and out.startswith("NOMATCH"), (rc, out))

print("== retest: needs-human + several bugs on one flow")
C = Fix("c")
C.add(NOTE_A, "shared-flow", date="2026-10-01")
C.add(NOTE_B, "shared-flow", date="2026-10-02")
ea, eb = [e for e in C.state().values() if "alerts.py" in e["note"]][0], [e for e in C.state().values() if "exports.py" in e["note"]][0]
C.land_fix(ea)
C.origin_edit(lambda t: t.replace("- [ ] " + ea["item"][6:], "- [x] " + ea["item"][6:]).replace("- [ ] " + eb["item"][6:], "- [ ] [AUTO-SKIP after 4 cycles] " + eb["item"][6:]))
C.cli("sweep")
sts = sorted(e["status"] for e in C.state().values())
ok("fixture: one fixed, one needs-human on the same flow", sts == ["fixed", "needs-human"], sts)
rc, out = C.retest("shared-flow", "ok")
ok("ok closes EVERY awaiting bug of the flow (you retested the flow)", out.startswith("RETESTED") and "closed=2" in out and all(e["status"] == "closed" for e in C.state().values()), (out, [e["status"] for e in C.state().values()]))
D = Fix("d")
D.add(NOTE_A, "shared-flow", date="2026-10-01")
D.add(NOTE_B, "shared-flow", date="2026-10-02")
ea, eb = [e for e in D.state().values() if "alerts.py" in e["note"]][0], [e for e in D.state().values() if "exports.py" in e["note"]][0]
D.land_fix(ea)
D.origin_edit(lambda t: t.replace("- [ ] " + ea["item"][6:], "- [x] " + ea["item"][6:]).replace("- [ ] " + eb["item"][6:], "- [ ] [AUTO-SKIP after 4 cycles] " + eb["item"][6:]))
D.cli("sweep")
rc, out = D.retest("shared-flow", "still-broken", "alerts still broken")
ok("still-broken reopens ONE bug (the 'fixed' one first), the other stays as it was", out.startswith("REOPENED") and sorted(e["status"] for e in D.state().values()) == ["needs-human", "open"], (out, [e["status"] for e in D.state().values()]))
rc, out = D.retest("shared-flow", "still-broken", "x", extra=("--id", "zzzz"))
ok("--id that matches nothing: NOMATCH rc 3", rc == 3, (rc, out))

print("== retest: argument handling")
rc, out = A.cli("retest", "--repo", "nope", "--date", "2026-10-02", "--flow", "f", "--result", "ok")
ok("unknown repo: rc 2", rc == 2, (rc, out))
rc, out = A.cli("retest", "--repo", "fx", "--date", "10/02/2026", "--flow", "f", "--result", "ok")
ok("bad date: rc 2", rc == 2, (rc, out))
rc, out = A.cli("retest", "--repo", "fx", "--date", "2026-10-02", "--flow", "f", "--result", "maybe")
ok("bad verdict rejected by the CLI", rc != 0, (rc, out))
rc, out = A.cli("retest", "--repo", "fx", "--date", "2026-10-02", "--flow", "Alerts Empty", "--result", "ok")
ok("flow names are normalised like the bridge does (spaces/case)", "NOMATCH" in out or "DUPLICATE" in out or "RETESTED" in out, (rc, out))
rc, out = B.cli("retest", "--repo", "fx", "--date", "2026-10-09", "--flow", "alerts-empty", "--result", "still-broken", "--dry-run")
ok("--dry-run on an open bug changes nothing and does not crash", rc in (0, 3), (rc, out))

# ============================================================================================================ qa-retest (Mac side)
print("== scripts/qa-retest")
if not os.path.exists(RETEST):
    print("  SKIP: %s is a Mac-side script and is not present on this machine" % RETEST)
else:
    TREE = os.path.join(ROOT, "tree")
    os.makedirs(os.path.join(TREE, "scripts"))
    os.makedirs(os.path.join(TREE, "qa", "manual_logs"))
    shutil.copy(RETEST, os.path.join(TREE, "scripts", "qa-retest"))
    fxlog = os.path.join(TREE, "qa", "manual_logs", "fx.txt")
    open(fxlog, "w").write("# log\n2026-10-01 | android | home-countries-filter | 5 | bug | Qatar missing\n")
    open(os.path.join(TREE, "qa", "manual_logs", "iptv_apps.txt"), "w").write("# log\n")
    RT = os.path.join(TREE, "scripts", "qa-retest")

    def rt(*a):
        return sh(["env", "-i", "PATH=/usr/bin:/bin:/usr/local/bin", "HOME=" + TREE, "bash", RT] + list(a))

    rc, out = rt("fx", "home-countries-filter", "ok")
    line = open(fxlog).read().strip().split("\n")[-1]
    parts = [x.strip() for x in line.split("|", 5)]
    ok("ok: one 6-column line, platform 'other', minutes 0, result ok, note starts with the retest marker", rc == 0 and len(parts) == 6 and parts[1] == "other" and parts[2] == "home-countries-filter" and parts[3] == "0" and parts[4] == "ok" and parts[5].startswith("[retest:ok "), (rc, out, line))
    rc, out = rt("fx", "Home Countries Filter", "still-broken", "Qatar still | missing")
    line = open(fxlog).read().strip().split("\n")[-1]
    parts = [x.strip() for x in line.split("|", 5)]
    ok("still-broken: result bug, note carries the marker + the text, the pipe in the note is defused, flow slugged", rc == 0 and parts[4] == "bug" and parts[2] == "home-countries-filter" and parts[5].startswith("[retest:still-broken ") and "Qatar still / missing" in parts[5], (rc, line))
    n = len(open(fxlog).read().strip().split("\n"))
    rc, out = rt("fx", "home-countries-filter", "perhaps")
    ok("bad verdict: exit 2, nothing appended", rc == 2 and len(open(fxlog).read().strip().split("\n")) == n, (rc, out))
    rc, out = rt("nosuchrepo", "f", "ok")
    ok("unknown repo: exit 2 and the known repos are listed", rc == 2 and "known:" in out and len(open(fxlog).read().strip().split("\n")) == n, (rc, out))
    rc, out = rt("fx")
    ok("too few args: usage, exit 2", rc == 2 and "usage" in out, (rc, out))
    rc, out = rt("chickadee", "paywall", "ok")
    ok("alias chickadee -> iptv_apps", rc == 0 and "logged to iptv_apps" in out, (rc, out))
    rc, out = rt("fx", "never-logged-flow", "ok")
    ok("a flow with no earlier line only warns (the box decides), still logs", rc == 0 and "no earlier line for flow" in out, (rc, out))

# ============================================================================================================ bridge end to end (stub ssh -> REAL ingest)
print("== bridge: retest lines end to end")
if not os.path.exists(BRIDGE) or not os.path.exists(RETEST):
    print("  SKIP: Mac-side scripts are not present on this machine")
else:
    E = Fix("e")
    BR = os.path.join(ROOT, "bridge")
    logs, state = os.path.join(BR, "logs"), os.path.join(BR, "state")
    os.makedirs(logs)
    calls = os.path.join(BR, "ssh_calls.log")
    os.symlink(E.ovn, os.path.join(E.d, "overnight-queue"))
    shutil.copytree(QA, os.path.join(E.ovn, "qa"), ignore=shutil.ignore_patterns("__pycache__"))
    stub = os.path.join(BR, "ssh")
    open(stub, "w").write("""#!/usr/bin/env bash
cmd="${@: -1}"
printf '%%s\\n' "$cmd" >> "%s"
HOME="%s" PATH="/opt/homebrew/bin:/usr/bin:/bin" OVN_MANUAL_MODEL=off OVN_DIR="%s" bash -c "$cmd"
""" % (calls, E.d, E.ovn))
    os.chmod(stub, 0o755)
    benv = {"PATH": MINPATH, "HOME": E.d, "QA_NOTES_LOGS_DIR": logs, "QA_NOTES_STATE": state, "QA_NOTES_SSH": stub, "OVN_SSH": "u@box",
            "QA_NOTES_NTFY": RELAY, "OVN_REMOTE_DIR": "overnight-queue", "NTFY_TOPIC": "t-test"}

    def bridge():
        return sh(["env", "-i"] + ["%s=%s" % kv for kv in benv.items()] + ["bash", BRIDGE])

    def remote_cmds():
        try:
            return open(calls).read().splitlines()
        except OSError:
            return []
    # a copy of qa-retest writing into the bridge's log dir
    tree = os.path.join(BR, "tree")
    os.makedirs(os.path.join(tree, "scripts"))
    os.symlink(logs, os.path.join(tree, "qa_logs_unused"))
    os.makedirs(os.path.join(tree, "qa"))
    os.symlink(logs, os.path.join(tree, "qa", "manual_logs"))
    shutil.copy(RETEST, os.path.join(tree, "scripts", "qa-retest"))
    open(os.path.join(logs, "fx.txt"), "w").write("# log\n2026-10-02 | backend | alerts-empty | 5 | bug | %s\n" % NOTE_A)

    def qr(*a):
        return sh(["env", "-i", "PATH=/usr/bin:/bin:/usr/local/bin", "HOME=" + tree, "bash", os.path.join(tree, "scripts", "qa-retest")] + list(a))
    rc, out = bridge()
    ok("bridge: the bug line is added through the real ingest", rc == 0 and "bridged=1" in out and E.entry("alerts-empty") is not None, out)
    ok("bridge makes NO extra ssh call for statuses (exactly one remote call per bug line)", len(remote_cmds()) == 1 and "list --json" not in remote_cmds()[0], remote_cmds())
    E.mark_fixed("alerts-empty")
    qr("fx", "alerts-empty", "still-broken", "Still empty on the second login")
    rc, out = bridge()
    ok("bridge: the still-broken line is sent as a RETEST (not as a new bug) and reopens the bug", rc == 0 and "retest 'still-broken' sent (reopened)" in out and E.entry("alerts-empty")["status"] == "open" and E.entry("alerts-empty")["retest_count"] == 1, (out, E.entry("alerts-empty")["status"]))
    rcmds = [c for c in remote_cmds() if "manual_notes_ingest.py retest" in c]
    ok("remote retest command: --result still-broken, base64 note only (no raw text), validated tokens", len(rcmds) == 1 and "--result 'still-broken'" in rcmds[0] and "--note-b64 '" in rcmds[0] and "Still empty" not in rcmds[0], rcmds)
    ok("reopened item is on top of the box's queue", "RETEST FAILED" in [l for l in E.progress().split("\n") if l.startswith("- [")][0], E.progress())
    E.mark_fixed("alerts-empty")
    qr("fx", "alerts-empty", "ok")
    n0 = len(remote_cmds())
    rc, out = bridge()
    ok("bridge: an 'ok' retest line (result ok) is sent and closes the bug", rc == 0 and "retest 'ok' sent (retested)" in out and E.entry("alerts-empty")["status"] == "closed", (out, E.entry("alerts-empty")["status"]))
    n1 = len(remote_cmds())
    rc, out = bridge()
    ok("idempotent: nothing is re-sent on the next run (zero ssh calls)", len(remote_cmds()) == n1 and "already-done=" in out, out)
    # an unmatched still-broken is filed as an ordinary new bug (nothing lost)
    qr("fx", "never-seen-flow", "still-broken", "backend/app/routers/exports.py export_all is wrong")
    rc, out = bridge()
    ok("an unmatched still-broken becomes a normal new bug (rc 3 fallback)", rc == 0 and "filing it as a new bug" in out and E.entry("never-seen-flow") is not None and E.entry("never-seen-flow")["status"] == "open", (out, E.entry("never-seen-flow")))
    # an 'ok' retest that matches nothing is rejected permanently, not retried forever
    qr("fx", "another-flow", "ok")
    rc, out = bridge()
    c1 = len(remote_cmds())
    rc, out = bridge()
    ok("an unmatched 'ok' is rejected once (recorded) and not retried", "box rejected the retest" in open(os.path.join(state, "bridge.log")).read() and len([c for c in remote_cmds()[c1:] if "retest" in c]) == 0, out)
    # old-bridge compatibility of the log format: the retest lines are plain 6-column lines
    ok("log lines stay in the 6-column format an older bridge reads", all(len(l.split("|")) >= 6 for l in open(os.path.join(logs, "fx.txt")).read().split("\n") if l and not l.startswith("#")))

    # ======================================================================================================== qa-status
    print("== scripts/qa-status: counts per status per repo")
    if not os.path.exists(STATUS):
        print("  SKIP: qa-status not present")
    else:
        sdir = os.path.join(ROOT, "statusstate")
        os.makedirs(sdir)
        import time as _t
        ents = [{"id": "1", "repo": "iptv_apps", "date": "2026-10-02", "flow": "home-countries-filter", "status": "fixed", "note": "Qatar missing", "updated": 1},
                {"id": "2", "repo": "iptv_apps", "date": "2026-10-02", "flow": "discover-add", "status": "escalated", "note": "plus does nothing", "updated": 1},
                {"id": "3", "repo": "iptv_apps", "date": "2026-10-02", "flow": "00s-replay", "status": "open", "note": "misclassified", "updated": 1},
                {"id": "4", "repo": "iptv_apps", "date": "2026-10-01", "flow": "x", "status": "closed", "note": "old", "updated": 1},
                {"id": "5", "repo": "xlite", "date": "2026-10-02", "flow": "combat", "status": "fixed", "note": "dmg wrong", "updated": 1}]
        json.dump({"fetched": int(_t.time()), "entries": ents}, open(os.path.join(sdir, "status.json"), "w"))
        env = {"PATH": MINPATH, "HOME": ROOT, "QA_NOTES_STATE": sdir, "QA_STATUS_LIVE": "off"}
        rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["python3", STATUS])
        ok("summary (cache only): iptv_apps line counts per status with human labels", rc == 0 and "iptv_apps" in out and "fixed (awaiting your retest) 1" in out and "escalated (Claude session) 1" in out and "open 1" in out and "closed (retest ok) 1" in out, out)
        ok("summary: xlite listed separately", any(l.strip().startswith("xlite") and "fixed (awaiting your retest) 1" in l for l in out.split("\n")), out)
        ok("summary: says it is the cached view", "CACHED as of" in out and "STALE" not in out, out)
        rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["python3", STATUS, "chickadee"])
        if "unknown plan" in out:
            print("  SKIP detail view: the chickadee plan doc is not in this checkout")
        else:
            ok("detail: lists what needs a retest with the exact command to run", "home-countries-filter" in out and "scripts/qa-retest iptv_apps home-countries-filter ok|still-broken" in out and "escalated" in out, out)
            ok("detail: other repos' bugs are not shown", "dmg wrong" not in out, out)
        old = {"fetched": int(_t.time()) - 5 * 3600, "entries": ents}
        json.dump(old, open(os.path.join(sdir, "status.json"), "w"))
        rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["python3", STATUS])
        ok("a stale cache is flagged", "STALE" in out, out)
        env2 = {"PATH": MINPATH, "HOME": ROOT, "QA_NOTES_STATE": os.path.join(ROOT, "nonexistent"), "QA_STATUS_LIVE": "off"}
        rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env2.items()] + ["python3", STATUS])
        ok("no cache + no box: the old summary output only, exit 0 (default-safe)", rc == 0 and "manual bugs" not in out, out)
        # live: a stub ssh that answers like the box (list --json)
        live = [dict(id="9", repo="iptv_apps", date="2026-10-02", flow="live-flow", status="fixed", note="live note", updated=1, retest_count=0, status_reason="", feat="f")]
        lstub = os.path.join(ROOT, "stub_ssh_ok")
        open(lstub, "w").write("#!/bin/bash\necho \"$*\" >> %s/stub_ssh_args\ncat <<'EOF'\n%s\nEOF\n" % (ROOT, json.dumps(live)))
        os.chmod(lstub, 0o755)
        ldir = os.path.join(ROOT, "livestate")
        env3 = {"PATH": MINPATH, "HOME": ROOT, "QA_NOTES_STATE": ldir, "QA_NOTES_SSH": lstub, "OVN_SSH": "u@box"}
        rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env3.items()] + ["python3", STATUS])
        ok("live: asks the box with 'manual_notes_ingest.py list --json' over BatchMode ssh and shows it as live", rc == 0 and "live from the box" in out and "fixed (awaiting your retest) 1" in out and "python3.12 ~/overnight-queue/qa/manual_notes_ingest.py list --json" in open(os.path.join(ROOT, "stub_ssh_args")).read() and "BatchMode=yes" in open(os.path.join(ROOT, "stub_ssh_args")).read(), (out, open(os.path.join(ROOT, "stub_ssh_args")).read()))
        ok("live: the answer refreshes the cache (offline fallback)", json.load(open(os.path.join(ldir, "status.json")))["entries"][0]["flow"] == "live-flow")
        fstub = os.path.join(ROOT, "stub_ssh_fail")
        open(fstub, "w").write("#!/bin/bash\necho 'ssh: connect timed out' >&2\nexit 255\n")
        os.chmod(fstub, 0o755)
        env4 = dict(env3, QA_NOTES_SSH=fstub)
        rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env4.items()] + ["python3", STATUS])
        ok("box unreachable: falls back to the cache and says so, exit 0", rc == 0 and "CACHED as of" in out and "fixed (awaiting your retest) 1" in out, out)
        gstub = os.path.join(ROOT, "stub_ssh_garbage")
        open(gstub, "w").write("#!/bin/bash\necho 'not json'\nexit 0\n")
        os.chmod(gstub, 0o755)
        rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in dict(env3, QA_NOTES_SSH=gstub).items()] + ["python3", STATUS])
        ok("garbage from the box: falls back to the cache, no crash", rc == 0 and "CACHED as of" in out, out)
        rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in dict(env3, OVN_REMOTE_DIR="x; rm -rf /").items()] + ["python3", STATUS])
        ok("a hostile OVN_REMOTE_DIR is refused (never reaches the remote shell)", rc == 0 and "live from the box" not in out, out)

shutil.rmtree(ROOT, ignore_errors=True)
print("\nqa retest/status vocabulary: %d passed, %d failed" % (P, F))
sys.exit(0 if F == 0 else 1)
