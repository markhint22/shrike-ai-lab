#!/usr/bin/env python3
"""qa/manual_notes_ingest.py, the bug-pipeline hygiene half (2026-10-03, A7-2/A7-4/A7-5, branch qa/h11-bug-pipeline). Real entry points (add / sweep / close /
reopen / list under `env -i`), fixture git repos with a bare origin, a fake queue.sh / qa_mode.sh, NO model (OVN_MANUAL_MODEL=off), NO relay (NTFY_SERVER unset).

Real failures reproduced (Chickadee, 10-03 diagnosis):
  * BUG-1: the closed-captions bug was reported 'fixed' to Mark because the queue line was '[x]'. The only landed commits were a 0-byte test file and then
    `assert(true)` ("Placeholder test to ensure the file is not empty"); no commit touched the located source file.
  * BUG-5: three bugs were fixed by interactive Claude sessions and merged to develop; nothing closed the notes entries or their progress lines, so the
    fleet re-attempted them overnight.
Negative controls: placeholder-only landing, tautology-only test, source change without any test, a trailer naming another bug, a trailer commit OLDER than
the entry. Benign controls: real source change + real test => fixed; a trailer commit => closed; OVN_MANUAL_FIX_EVIDENCE=off => the old behaviour.

Runs on the Mac and on the box:  python3 scripts/test/test_manual_notes_h11.py
"""
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OVNQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OVNQ, "qa")
INGEST = os.path.join(QA, "manual_notes_ingest.py")
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
        print("  FAIL " + name + (("  :: " + (x if len(x) < 700 else x[:300] + " ... " + x[-300:])) if extra else ""))


ROOT = tempfile.mkdtemp(prefix="manual-notes-h11-")
MINPATH = "/usr/bin:/bin:/usr/local/bin"


def sh(cmd, cwd=None, env=None, timeout=120):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")


def git(cwd, *a, env=None):
    rc, out = sh(["git", "-C", cwd, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a), env=env)
    assert rc == 0, (a, out)
    return out.strip()


SRC = "android/app/src/main/java/com/x/SubtitleTrackLabel.kt"
FILES = {
    "OVERNIGHT_PROGRESS.md": "# Progress\n\n## Current Status\nfine\n\n## Next Steps\n\n## Needs human (do NOT attempt)\n",
    SRC: "package com.x\nfun subtitleTrackLabel(lang: String) = \"Closed Captions \" + lang\n",
    "android/app/src/main/java/com/x/Other.kt": "package com.x\nfun other() = 1\n",
    "android/gradlew": "#!/bin/sh\n",
    "android/app/build.gradle.kts": "plugins {}\ndependencies {\n  testImplementation(\"junit:junit:4.13.2\")\n}\n",
}
NOTE = 'The "Closed Captions" label shows the wrong subtitle track name when two tracks share a language'


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
        old = "2020-01-01T00:00:00"                 # the seed commit predates every entry (the evidence check only looks at commits since the bug was enqueued)
        git(self.work, "commit", "-q", "-m", "init", env=dict(os.environ, GIT_COMMITTER_DATE=old, GIT_AUTHOR_DATE=old))
        git(self.work, "push", "-q", "origin", "overnight/feature")
        git(self.work, "checkout", "-q", "-b", "develop")
        git(self.work, "push", "-q", "origin", "develop")
        git(self.work, "checkout", "-q", "overnight/feature")
        git(self.d, "clone", "-q", "-b", "overnight/feature", self.origin, self.clone)
        self.calls = os.path.join(self.ovn, "state", "calls.log")
        open(os.path.join(self.ovn, "queue.sh"), "w").write('#!/usr/bin/env bash\necho "queue $1 $2" >> "%s"\n' % self.calls)
        open(os.path.join(self.ovn, "qa_mode.sh"), "w").write('#!/usr/bin/env bash\necho "qa_mode $1 $2" >> "%s"\n' % self.calls)

    def env(self, **kw):
        e = {"PATH": MINPATH, "HOME": self.d, "OVN_DIR": self.ovn, "OVN_MANUAL_MODEL": "off", "OVN_BUG_BRIEF": "off"}
        e.update({k: v for k, v in kw.items() if v is not None})
        return e

    def cli(self, *args, **kw):
        return sh(["env", "-i"] + ["%s=%s" % kv for kv in self.env(**kw).items()] + [INGEST] + list(args))

    def add(self, note=NOTE, flow="closed-captions", date="2026-10-01"):
        b64 = base64.b64encode(note.encode()).decode()
        return self.cli("add", "--repo", "fx", "--date", date, "--flow", flow, "--minutes", "5", "--platform", "android", "--note-b64", b64)

    def entries(self):
        try:
            return list(json.load(open(os.path.join(self.ovn, "state", "manual_notes.json")))["entries"].values())
        except OSError:
            return []

    def entry(self, n=-1):
        return sorted(self.entries(), key=lambda e: e["created"])[n]

    def progress(self, ref="overnight/feature"):
        return sh(["git", "--git-dir=" + self.origin, "show", ref + ":OVERNIGHT_PROGRESS.md"])[1]

    def commit(self, files, msg, branch="overnight/feature", date=None):
        git(self.work, "fetch", "-q", "origin")
        git(self.work, "checkout", "-q", branch)
        git(self.work, "reset", "-q", "--hard", "origin/" + branch)
        for p, c in files.items():
            fp = os.path.join(self.work, p)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "a" if p == SRC else "w") as f:
                f.write(c)
        git(self.work, "add", "--force", *files.keys())
        env = dict(os.environ, GIT_COMMITTER_DATE=date, GIT_AUTHOR_DATE=date) if date else None
        git(self.work, "commit", "-q", "-m", msg, env=env)
        git(self.work, "push", "-q", "origin", branch)
        return git(self.work, "rev-parse", "HEAD")

    def check_off(self):
        e = self.entry()
        git(self.work, "fetch", "-q", "origin")
        git(self.work, "checkout", "-q", "overnight/feature")
        git(self.work, "reset", "-q", "--hard", "origin/overnight/feature")
        p = os.path.join(self.work, "OVERNIGHT_PROGRESS.md")
        t = open(p).read().replace("- [ ] " + e["item"][len("- [ ] "):], "- [x] " + e["item"][len("- [ ] "):])
        open(p, "w").write(t)
        git(self.work, "add", "OVERNIGHT_PROGRESS.md")
        git(self.work, "commit", "-q", "-m", "fleet checks the item off")
        git(self.work, "push", "-q", "origin", "overnight/feature")


# ===================================================================================================== unit: real_test_lines
print("== real_test_lines (unit)")
RT = mn.real_test_lines
ok("placeholder test (the 64d2b2bc shape) => no real assertion", RT("@Test fun testPlaceholder() {\n // Placeholder test to ensure the file is not empty and compiles.\n assert(true)\n}") == [])
for tauto in ("assert(true)", "assertTrue(true)", "assertTrue(true, \"ok\")", "assert True", "assertEquals(1, 1)", "assertEquals(x, x)", "expect(true).toBe(true)",
              "assertTrue(\"msg\", true)", "assertEquals(\"a\", \"a\")", "assertEquals(\"m\", 2, 2)", "assertFalse(false)", "assertNull(null)", "check(true)", "require(true)"):
    ok("tautology %r is not a real assertion" % tauto, RT("fun t() {\n  %s\n}" % tauto) == [], RT(tauto))
for real in ("assertEquals(\"Closed Captions en\", subtitleTrackLabel(\"en\"))", "assertTrue(label.contains(\"2\"))", "assert foo() == 1", "expect(label).toBe('CC')",
             "assertThat(result).isEqualTo(3)", "XCTAssertEqual(a, b)", "assertEquals(\"a\", \"b\")", "assertFalse(isEmpty())", "check(x == 1)", "assertTrue(\"label\", x)"):
    ok("real assertion %r counts" % real, len(RT(real)) == 1, RT(real))
ok("a 0-byte / assertion-free test body is not real", RT("") == [] and RT("@Test fun t() { val x = 1 }") == [])
ok("a real assertion in a file that ALSO says placeholder is rejected as a whole", RT("// placeholder\nassertEquals(1, f())") == [])

# ===================================================================================================== A7-2: 'fixed' needs evidence
print("== fixed needs a landed commit on the located file AND a real test")
A = Fix("a")
rc, out = A.add()
ok("fixture: bug enqueued, located the source file", rc == 0 and A.entry().get("path") == SRC, (out, A.entry()))
TEST_KT = "android/app/src/test/java/com/x/ui/mobile/SubtitleTrackLabelTest.kt"
A.commit({TEST_KT: "package com.x\nclass SubtitleTrackLabelTest {\n  @Test fun testPlaceholder() {\n    // Placeholder test to ensure the file is not empty and compiles.\n    assert(true)\n  }\n}\n"}, "feat(fx): staged step 1 - placeholder")
A.check_off()
rc, out = A.cli("sweep", "--no-brief")
e = A.entry()
ok("NEGATIVE: '[x]' + only a placeholder test landed => NOT fixed (needs-human, 'no landed commit touched the file')", e["status"] == "needs-human" and "no landed commit touched" in e["status_reason"], (e["status"], e["status_reason"], out))

B = Fix("b")
B.add()
B.commit({SRC: "// touched\n", TEST_KT: "package com.x\nclass T {\n  @Test fun t() {\n    assertTrue(true)\n  }\n}\n"}, "feat(fx): source touched + tautology test")
B.check_off()
B.cli("sweep", "--no-brief")
e = B.entry()
ok("NEGATIVE: source touched but the only test is a tautology => needs-human 'no landed test with a real assertion'", e["status"] == "needs-human" and "real assertion" in e["status_reason"], (e["status"], e["status_reason"]))

C = Fix("c")
C.add()
C.commit({SRC: "// touched\n"}, "fix(fx): source only, no test")
C.check_off()
C.cli("sweep", "--no-brief")
e = C.entry()
ok("NEGATIVE: a source change with no test at all => needs-human", e["status"] == "needs-human" and "real assertion" in e["status_reason"], (e["status"], e["status_reason"]))

D = Fix("d")
D.add()
D.commit({SRC: "// real fix\n"}, "fix(fx): staged step 2 - the fix")
sha = D.commit({TEST_KT: "package com.x\nclass SubtitleTrackLabelTest {\n  @Test fun labelDisambiguates() {\n    assertEquals(\"Closed Captions en\", subtitleTrackLabel(\"en\"))\n  }\n}\n"},
               "test(fx): staged step 1 - label test")
D.check_off()
rc, out = D.cli("sweep", "--no-brief")
e = D.entry()
ok("BENIGN: real source change + a real test that names the file => fixed", e["status"] == "fixed" and "asserts it" in e["status_reason"], (e["status"], e["status_reason"], out))

E = Fix("e")
E.add()
E.commit({TEST_KT: "package com.x\nclass SubtitleTrackLabelTest {\n  @Test fun testPlaceholder() {\n    // Placeholder test\n    assert(true)\n  }\n}\n"}, "feat(fx): placeholder")
E.check_off()
E.cli("sweep", "--no-brief", OVN_MANUAL_FIX_EVIDENCE="off")
ok("OVN_MANUAL_FIX_EVIDENCE=off restores the old '[x] => fixed' verdict", E.entry()["status"] == "fixed", E.entry()["status"])

# ===================================================================================================== A7-4: close
print("== close --id --by (interactive Claude fix)")
G = Fix("g")
G.add()
e = G.entry()
fixsha = G.commit({SRC: "// the real fix by a Claude session\n"}, "fix(fx): disambiguate subtitle labels\n\nFixes-manual-bug: %s" % e["feat"], branch="develop")
rc, out = G.cli("close", "--id", e["id"][:8], "--by", fixsha)
e2 = G.entry()
ok("close: CLOSED line, entry => fixed (awaiting retest) with closed_by", rc == 0 and out.startswith("CLOSED") and e2["status"] == "fixed" and e2["closed_by"] == fixsha, (rc, out, e2["status"]))
prog = G.progress()
line = [l for l in prog.split("\n") if "[feat:%s]" % e["feat"] in l][0]
ok("close: the progress line is '[x]' with a pointer to the fixing commit (the fleet stops re-attempting it)", line.startswith("- [x] ") and fixsha[:12] in line, line)
ok("close: no open line carries the tag any more", not [l for l in prog.split("\n") if "[feat:%s]" % e["feat"] in l and l.startswith("- [ ]")])
ok("close: committed as the fleet identity touching only OVERNIGHT_PROGRESS.md", git(G.origin, "show", "--name-only", "--format=%an", "overnight/feature").split("\n")[0] == "shrike-fleet"
   and git(G.origin, "show", "--name-only", "--format=", "overnight/feature").strip() == "OVERNIGHT_PROGRESS.md")
rc, out = G.cli("close", "--id", e["id"][:8], "--by", fixsha)
ok("close is idempotent (second call changes nothing, rc 0)", rc == 0 and G.progress() == prog, out)
rc, out = G.cli("close", "--id", "nomatchzz", "--by", fixsha)
ok("NEGATIVE: an id that matches nothing => rc 2, nothing changed", rc == 2 and G.progress() == prog, (rc, out))
rc, out = G.cli("sweep", "--no-brief")
ok("sweep leaves a closed-by-Claude entry as fixed (not reopened, not downgraded by the evidence check)", G.entry()["status"] == "fixed", (G.entry()["status"], out))

# ===================================================================================================== trailer
print("== 'Fixes-manual-bug:' commit trailer reachable from develop")
H = Fix("h")
H.add()
e = H.entry()
H.commit({SRC: "// unrelated change\n"}, "fix(fx): a trailer naming ANOTHER bug\n\nFixes-manual-bug: iptv-20261001-manual-deadbeef", branch="develop")
H.cli("sweep", "--no-brief")
ok("NEGATIVE: a trailer naming another bug does not close this one", H.entry()["status"] == "open", H.entry()["status"])
H.commit({"android/app/src/main/java/com/x/Other.kt": "// no trailer here\n"}, "fix(fx): mentions Fixes-manual-bug in prose only", branch="develop")
H.cli("sweep", "--no-brief")
ok("NEGATIVE: a commit with no real trailer line does not close it", H.entry()["status"] == "open", H.entry()["status"])
old = H.commit({SRC: "// old fix\n"}, "fix(fx): trailer commit that PREDATES the entry\n\nFixes-manual-bug: %s" % e["feat"], branch="develop", date="2020-01-01T00:00:00")
H.cli("sweep", "--no-brief")
ok("NEGATIVE: a trailer commit older than the entry (an earlier round) does not close it", H.entry()["status"] == "open", H.entry()["status"])
sha = H.commit({SRC: "// the real fix\n"}, "fix(fx): the real fix\n\nFixes-manual-bug: %s" % e["feat"], branch="develop")
rc, out = H.cli("sweep", "--no-brief")
e2 = H.entry()
ok("BENIGN: a trailer commit (feat id) on develop => the sweep closes the entry", e2["status"] == "fixed" and e2.get("closed_by") == sha and "Claude" in e2["status_reason"], (e2["status"], e2.get("closed_by"), out))
ok("... and retires its progress line", [l for l in H.progress().split("\n") if "[feat:%s]" % e["feat"] in l][0].startswith("- [x] "))
# the trailer also closes an ESCALATED entry (the bug-first hand-off) and accepts the entry id
I = Fix("i")
I.add()
e = I.entry()
git(I.work, "pull", "-q", "--rebase", "origin", "overnight/feature")
pp = os.path.join(I.work, "OVERNIGHT_PROGRESS.md")
txt = open(pp).read().replace("- [ ] " + e["item"][6:], "- [ ] [CLAUDE] [bug-escalated: 2 failed attempts (cap 2), last: x] " + e["item"][6:])
open(pp, "w").write(txt)
git(I.work, "add", "OVERNIGHT_PROGRESS.md")
git(I.work, "commit", "-q", "-m", "escalate")
git(I.work, "push", "-q", "origin", "overnight/feature")
I.cli("sweep", "--no-brief")
ok("fixture: entry is escalated", I.entry()["status"] == "escalated", I.entry()["status"])
sha = I.commit({SRC: "// the real fix\n"}, "fix(fx): label\n\nFixes-manual-bug: %s" % e["id"][:10], branch="develop")
I.cli("sweep", "--no-brief")
ok("BENIGN: a trailer closes an ESCALATED entry too (matched by entry id prefix)", I.entry()["status"] == "fixed" and I.entry().get("closed_by") == sha, (I.entry()["status"],))

# ===================================================================================================== A7-5: reopen
print("== reopen --id")
J = Fix("j")
J.add()
e = J.entry()
J.commit({SRC: "// fix\n"}, "fix(fx): x", branch="develop")
rc, out = J.cli("close", "--id", e["id"][:8], "--by", "HEAD~0")
rc, out = J.cli("reopen", "--id", e["id"][:8], "--dry-run")
ok("reopen --dry-run prints the new tagged item and changes nothing", rc == 0 and out.startswith("DRY-RUN reopen") and ".r1" in out and J.entry()["status"] == "fixed", out)
rc, out = J.cli("reopen", "--id", e["id"][:8], "--reason", "credit was not backed by a real fix")
e2 = J.entry()
ok("reopen: status open, fresh feat tag .r1 (=> fresh attempt counters), retest_count 1", rc == 0 and out.startswith("REOPENED") and e2["status"] == "open" and e2["feat"].endswith(".r1") and e2["retest_count"] == 1, (rc, out, e2["status"]))
prog = J.progress()
first = [l for l in prog.split("\n") if l.startswith("- [ ] ")][0]
ok("reopen: the new item is the FIRST open line under Next Steps, carries REOPENED + the earlier tag, still a manual bug", "REOPENED" in first and "[feat:%s]" % e2["feat"] in first and "src:manual" in first and e["feat"] in first.split("REOPENED")[1], first)
ok("reopen: the earlier '[x]' line is untouched", any(l.startswith("- [x] ") and "[feat:%s]" % e["feat"] in l for l in prog.split("\n")))
rc, out = J.cli("reopen", "--id", "nomatchzz")
ok("NEGATIVE: reopen with an id that matches nothing => rc 2", rc == 2, (rc, out))

shutil.rmtree(ROOT, ignore_errors=True)
print("manual notes h11: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
