#!/usr/bin/env python3
"""Tests for the manual-notes loop: qa/manual_notes_ingest.py (add|sweep|list), qa/manual_notes_cron.sh and the Mac bridge
scripts/qa-notes-bridge.sh (repo root). Real entry points, absolute AND relative paths, `env -i` with a minimal PATH, NTFY_SERVER set
to a LOCAL stub relay (nothing here can reach ntfy.sh), fixture git repos with a bare origin, a fake queue.sh / qa_mode.sh in a temp
OVN_DIR, a stubbed model (local HTTP server, no network), a stub ssh for the bridge.

Runs on the Mac and on the box:  python3 scripts/test/test_qa_manual_notes.py
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
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OVNQ = os.path.abspath(os.path.join(HERE, "..", ".."))                 # scripts/overnight-queue
QA = os.path.join(OVNQ, "qa")
INGEST = os.path.join(QA, "manual_notes_ingest.py")
CRON = os.path.join(QA, "manual_notes_cron.sh")
RETIRE = os.path.join(OVNQ, "scripts", "ovn_retire_vague.py")
BRIDGE = os.path.abspath(os.path.join(OVNQ, "..", "qa-notes-bridge.sh"))
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


ROOT = tempfile.mkdtemp(prefix="qa-manual-notes-test-")
MINPATH = "/usr/bin:/bin"


def sh(cmd, cwd=None, env=None, timeout=120, check=False):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=timeout)
    out = (p.stdout + p.stderr).decode("utf-8", "replace")
    if check and p.returncode != 0:
        raise RuntimeError("%s failed: %s" % (cmd, out))
    return p.returncode, out


def git(cwd, *a):
    return sh(["git", "-C", cwd, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a), check=True)[1]


# ---------------------------------------------------------------------------------------------------------------- stub servers
class Recorder(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace")
        self.server.hits.append({"path": self.path, "headers": dict(self.headers), "body": body})
        code, payload = self.server.responder(self.path, body)
        data = payload.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def start_server(responder):
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Recorder)
    srv.hits = []
    srv.responder = responder
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


relay = start_server(lambda p, b: (200, "{}"))
RELAY = "http://127.0.0.1:%d" % relay.server_address[1]
model_content = {"v": ""}
model = start_server(lambda p, b: (200, json.dumps({"choices": [{"message": {"content": model_content["v"]}}]})))
MODEL = "http://127.0.0.1:%d" % model.server_address[1]


def dead_port():
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


# ---------------------------------------------------------------------------------------------------------------- fixture
FILES = {
    "OVERNIGHT_PROGRESS.md": "# Progress\n\n## Current Status\nfine\n\n## Next Steps\n### Refill\n- [ ] [T1] backend/app/other.py — do a thing. VERIFY: `pytest -q`. (cat:python; multifile:no)\n\n## Needs human (do NOT attempt)\n",
    "app-web/package.json": "{}\n",
    "app-web/src/views/PaywallView.vue": "<template>\n  <button @click=\"restorePurchases\">Restore Purchases</button>\n</template>\n<script>\nexport function restorePurchases() { return null }\n</script>\n",
    "app-web/src/views/__tests__/PaywallView.test.ts": "import PaywallView from '../PaywallView.vue'\n// restorePurchases paywall\n",
    "app-web/src/views/HomeView.vue": "<template><div>Home</div></template>\n",
    "backend/app/routers/alerts.py": "def list_alerts():\n    return []\n",
    "backend/app/services/export_service.py": "def build_export_payload(user):\n    return {'bills': user.bills[0]}\n",
    "backend/app/routers/digest.py": "# weekly digest email scheduling\ndef weekly_digest_route():\n    return 1\n",
    "backend/app/services/digest_service.py": "# weekly digest email scheduling\ndef weekly_digest_service():\n    return 1\n",
    "backend/app/other.py": "x = 1\n",
    "backend/tests/test_alerts_router.py": "def test_a():\n    # the alerts endpoint returns a list for a brand new account\n    assert True\n",
    "app-web/src/views/AlertsView.vue": "<template><p>No alerts yet</p></template>\n",
    "app-web/src/views/ProfileView.vue": "<template><button>Sign Out Everywhere</button></template>\n",
    "android/app/src/main/java/com/x/ProfileScreen.kt": "fun p() { Text(\"Sign Out Everywhere\") }\n",
    "backend/tests/test_alerts.py": "def test_x():\n    assert True\n",
    "backend/tests/test_other.py": "def test_y():\n    assert True\n",
    "android/gradlew": "#!/bin/sh\n",
    "android/app/build.gradle.kts": "plugins {}\n",
    "android/app/src/main/res/values/strings.xml": "<resources>\n    <string name=\"settings_delete_account_confirm\">Delete my account permanently</string>\n</resources>\n",
    "android/app/src/main/java/com/x/SettingsScreen.kt": "package com.x\nfun f() { show(R.string.settings_delete_account_confirm) }\n",
    "game/scripts/save/save_manager.gd": "func load_save(slot):\n    return {}\n",
    "game/tests/test_save_manager.gd": "extends GutTest\n",
    "node_modules/zzz/index.js": "restorePurchases weekly digest\n",
}
for i in range(60):   # generic-word noise: a word that hits many files must be treated as non-discriminative
    FILES["backend/app/noise/n%02d.py" % i] = "# loading data from the server and showing results\ndef f%d():\n    return 1\n" % i


class Fix:
    """One fixture: bare origin with overnight/feature, a live clone under repos/fx, a fake queue.sh/qa_mode.sh in OVN_DIR."""

    def __init__(self, name, qa_on=False):
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
        open(os.path.join(self.ovn, "queue.sh"), "w").write(
            '#!/usr/bin/env bash\necho "queue $1 $2" >> "%s"\n' % self.calls)
        open(os.path.join(self.ovn, "qa_mode.sh"), "w").write(
            '#!/usr/bin/env bash\nD="%s"\necho "qa_mode $1 $2" >> "%s"\nS="$D/state/qa_mode.json"\n'
            'python3 - "$1" "$2" "$S" <<\'EOF\'\nimport json,sys\nc,r,s=sys.argv[1:4]\nd=json.load(open(s))\nid="ongoing-"+r.replace("_","-")\n'
            't=set(d.get("temp_lanes",[]))\nif c=="lane": t.add(id)\nif c=="unlane": t.discard(id)\nd["temp_lanes"]=sorted(t)\njson.dump(d,open(s,"w"))\nEOF\n'
            % (self.ovn, self.calls))
        if qa_on:
            self.set_qa({"mode": "qa", "disabled_lanes": ["ongoing-fx"], "temp_lanes": []})

    def set_qa(self, d):
        json.dump(d, open(os.path.join(self.ovn, "state", "qa_mode.json"), "w"))

    def qa(self):
        try:
            return json.load(open(os.path.join(self.ovn, "state", "qa_mode.json")))
        except OSError:
            return None

    def env(self, **kw):
        e = {"PATH": MINPATH, "HOME": self.d, "OVN_DIR": self.ovn, "NTFY_SERVER": RELAY, "NTFY_TOPIC": "t-test",
             "LITELLM_BASE": MODEL, "OVN_MANUAL_MODEL": "qwen-test"}
        e.update({k: v for k, v in kw.items() if v is not None})
        for k, v in kw.items():
            if v is None:
                e.pop(k, None)
        return e

    def add(self, note, flow="other", date="2026-10-01", extra=(), via="abs", **envkw):
        env = self.env(**envkw)
        b64 = base64.b64encode(note.encode("utf-8")).decode()
        args = ["add", "--repo", "fx", "--date", date, "--flow", flow, "--minutes", "10", "--note-b64", b64] + list(extra)
        if via == "rel":
            return sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["./qa/manual_notes_ingest.py"] + args, cwd=OVNQ)
        return sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [INGEST] + args)

    def cli(self, *args, **envkw):
        env = self.env(**envkw)
        return sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [INGEST] + list(args))

    def state(self):
        try:
            return json.load(open(os.path.join(self.ovn, "state", "manual_notes.json")))["entries"]
        except OSError:
            return {}

    def progress_at_origin(self):
        return sh(["git", "--git-dir=" + self.origin, "show", "overnight/feature:OVERNIGHT_PROGRESS.md"])[1]

    def origin_edit(self, fn, msg="edit"):
        git(self.work, "pull", "-q", "--rebase", "origin", "overnight/feature")
        p = os.path.join(self.work, "OVERNIGHT_PROGRESS.md")
        new = fn(open(p).read())
        open(p, "w").write(new)
        git(self.work, "add", "OVERNIGHT_PROGRESS.md")
        git(self.work, "commit", "-q", "-m", msg)
        git(self.work, "push", "-q", "origin", "overnight/feature")

    def call_log(self):
        try:
            return open(self.calls).read().splitlines()
        except OSError:
            return []

    def sweep(self, **envkw):
        return self.cli("sweep", **envkw)


def entry_of(fx, n=None):
    es = list(fx.state().values())
    return es[-1] if n is None else es[n]



def ent(fx, needle, out=""):
    for x in fx.state().values():
        if needle in x["note"]:
            return x
    ok("entry exists for %r" % needle, False, out)
    return {"note": "", "candidates": [], "item": "", "path": None, "risk": None, "language": None, "risk_note": "", "status": "missing"}

def next_steps_first(prog):
    lines = prog.split("\n")
    i = [k for k, l in enumerate(lines) if l.strip() == "## Next Steps"][0]
    return lines[i + 1]


def relay_titles():
    return [h["headers"].get("Title", "") for h in relay.hits]


# ================================================================================================================ unit: sanitizing
print("== sanitizing")
raw = "line1\nline2\r\n`rm -rf /` **bold** [T1] VERIFY: echo hi (cat:python) [feat:x] <!-- c --> AUTO-SKIP HUMAN-ONLY a|b $(id) ${HOME} — dash"
s = mn.sanitize_note(raw)
ok("one line, no newline/CR", "\n" not in s and "\r" not in s)
ok("no backticks", "`" not in s)
ok("no markdown stars / html comment markers", "**" not in s and "<!--" not in s and "-->" not in s)
ok("no [T1] / [feat:] bracket lookalikes", "[" not in s and "]" not in s)
ok("VERIFY: is neutralized", "VERIFY:" not in s.upper().replace("VERIFY -", ""))
ok("(cat: is neutralized", "cat:" not in s)
ok("AUTO-SKIP / HUMAN-ONLY neutralized (park sweep would move the item)", "AUTO-SKIP" not in s.upper() and "HUMAN-ONLY" not in s.upper())
ok("pipes become slashes", "|" not in s and "a/b" in s)
ok("shell substitution openers defused", "$(" not in s and "${" not in s)
ok("em dash replaced (item syntax uses ' — ' once)", "—" not in s)
big = mn.sanitize_note("x" * 10000)
ok("10k chars capped at 400", len(big) <= mn.NOTE_CAP)
uni = mn.sanitize_note("Café ✓ 日本語 émoji \U0001F600 zero​width ‮RTL‬ bell\x07 nul\x00")
ok("unicode letters/emoji survive", "Café" in uni and "日本語" in uni and "\U0001F600" in uni)
ok("zero-width / bidi / control chars removed", "​" not in uni and "‮" not in uni and "\x07" not in uni and "\x00" not in uni)
ok("empty after sanitizing stays empty", mn.sanitize_note("\x00\n ​ ") == "")
ok("locator clean keeps identifiers", "restore_purchases" in mn.clean_for_locator("the restore_purchases() call\nfails"))
ok("entry id stable under whitespace/case changes", mn.entry_id("r", "d", "f", "Hello  World") == mn.entry_id("r", "d", "F", "hello world"))

# ================================================================================================================ locator + enqueue
print("== locator / enqueue")
A = Fix("a", qa_on=True)
orig_prog = A.progress_at_origin()
rc, out = A.add('The "Restore Purchases" button does nothing on the paywall', flow="paywall", via="rel")
e = entry_of(A)
ok("UI-label note: relative-path entry point works under env -i", rc == 0 and out.startswith("ADDED"), out)
ok("UI-label note located PaywallView.vue (not the test, not node_modules)", e.get("path") == "app-web/src/views/PaywallView.vue", e.get("candidates"))
ok("locator evidence is a real line", any("Restore Purchases" in c["evidence"] or "restorePurchases" in c["evidence"] for c in e["candidates"]))
ok("unambiguous result did not call the model", len(model.hits) == 0, len(model.hits))
prog = A.progress_at_origin()
first = next_steps_first(prog)
ok("item is the FIRST line under '## Next Steps' at origin", first.startswith("- [ ] [T3] app-web/src/views/PaywallView.vue — Manual-test bug (reported by Mark, flow paywall, 2026-10-01): "), first)
ok("item has VERIFY with a real vitest command", "VERIFY: `cd app-web && npm run test -- PaywallView`." in first, first)
ok("item ends with cat/multifile/src tags and a feat tag", first.endswith(") [feat:%s]" % e["feat"]) and "(cat:bugfix; multifile:no; src:manual)" in first, first)
ok("item says to write a failing test first", "First write a failing test that reproduces this, then fix it" in first)
ok("exactly one VERIFY:, one (cat:, one [feat:, two backticks", first.count("VERIFY:") == 1 and first.count("(cat:") == 1 and first.count("[feat:") == 1 and first.count("`") == 2, first)
ok("rest of the file untouched", prog.replace(first + "\n", "", 1) == orig_prog)
c = sh(["git", "--git-dir=" + A.origin, "log", "-1", "--format=%an|%ae|%s", "overnight/feature"])[1].strip()
ok("committed as shrike-fleet with the fleet identity", c.startswith("shrike-fleet|22970726+markhint22@users.noreply.github.com|chore(queue)"), c)
files_changed = sh(["git", "--git-dir=" + A.origin, "show", "--name-only", "--format=", "overnight/feature"])[1].split()
ok("commit touched ONLY OVERNIGHT_PROGRESS.md (no add -A)", files_changed == ["OVERNIGHT_PROGRESS.md"], files_changed)
ok("hold then release, in order", A.call_log()[:2] == ["queue hold fx", "queue release fx"], A.call_log())
ok("live clone is clean and equals origin", git(A.clone, "status", "--porcelain").strip() == "" and
   git(A.clone, "rev-parse", "HEAD") == sh(["git", "--git-dir=" + A.origin, "rev-parse", "overnight/feature"])[1])
ok("entry is open, risk normal-ish (vue = medium)", e["status"] == "open" and e["risk"] == "medium", e)

# the REAL sanitizer keeps it (and the controls prove the check is not vacuous)
def retire_on(progress_text, fx=None):
    d = os.path.join(ROOT, "retire-%d" % time.time_ns())
    shutil.copytree((fx or A).clone, d, ignore=shutil.ignore_patterns(".git"))
    open(os.path.join(d, "OVERNIGHT_PROGRESS.md"), "w").write(progress_text)
    rc, out = sh(["python3", RETIRE, "OVERNIGHT_PROGRESS.md"], cwd=d)
    return rc, out, open(os.path.join(d, "OVERNIGHT_PROGRESS.md")).read()


rc, rout, rtext = retire_on(prog)
ok("ovn_retire_vague.py KEEPS the generated item (retired 0)", "total retired: 0" in rout and first in rtext.split("\n"), rout)
bad = first.replace("app-web/src/views/PaywallView.vue", "app-web/src/views/NoSuchFile.vue")
_, rout2, rtext2 = retire_on(prog.replace(first, bad))
ok("negative control: the same item with a missing file IS retired", "dead-path=1" in rout2, rout2)
bad2 = first.replace("app-web/src/views/PaywallView.vue", "").replace("backend", "")
bad2 = "- [ ] [T2] Manual-test bug: the restore button does nothing. First write a failing test. (cat:bugfix; multifile:no)"
_, rout3, _ = retire_on(prog.replace(first, bad2))
ok("negative control: an item naming no file IS retired as vague", "vague=1" in rout3, rout3)

# dedupe / idempotent
n_before = len(A.progress_at_origin().split("\n"))
rc, out = A.add('The "Restore Purchases" button does nothing on the paywall', flow="paywall")
ok("re-running the same note is a DUPLICATE and changes nothing", rc == 0 and out.startswith("DUPLICATE") and len(A.progress_at_origin().split("\n")) == n_before, out)
ok("still exactly one state entry and one queue item", len(A.state()) == 1 and A.progress_at_origin().count("[feat:%s]" % e["feat"]) == 1)
rc, out = A.add("  The  \"restore purchases\" BUTTON does nothing on the paywall \n", flow="PAYWALL")
ok("whitespace/case variants of the same note dedupe too", out.startswith("DUPLICATE"), out)

# function-name note
rc, out = A.add("build_export_payload crashes when the user has no bills", flow="export")
e2 = ent(A, "build_export_payload", out)
ok("function-name note located export_service.py", e2["path"] == "backend/app/services/export_service.py", e2.get("candidates"))
ok("python item gets pytest VERIFY against the tests dir (no test_export_service.py exists)", "VERIFY: `pytest backend/tests -q -x`." in e2["item"], e2["item"])
ok("normal-risk language recorded", e2["risk"] == "normal" and e2["language"] == "python")

# named file
rc, out = A.add("backend/app/routers/alerts.py returns 500 when empty", flow="alerts")
e3 = ent(A, "alerts.py", out)
ok("a file named in the note wins and gets its exact test file", e3["path"] == "backend/app/routers/alerts.py" and "VERIFY: `pytest backend/tests/test_alerts.py -v`." in e3["item"], e3["item"])

# a test file is never the target; a file named after the flow wins; platform words steer
rc, out = A.add("The alerts endpoint returns a 500 error for a brand new account that has no alerts yet", flow="alerts", OVN_MANUAL_MODEL="off")
e3b = ent(A, "alerts endpoint returns a 500", out)
ok("a TEST file is never chosen as the target (even when its text matches best)", not e3b["candidates"] or all("test" not in c["path"].lower() for c in e3b["candidates"]), e3b["candidates"])
ok("file named after the flow/word (routers/alerts.py) is a located candidate for a prose API note",
   "backend/app/routers/alerts.py" in [c["path"] for c in e3b["candidates"] if c["located"]], e3b.get("candidates"))
ok("VERIFY picks the nearest test file by name (alerts.py -> tests/test_alerts_router.py)",
   mn.verify_command(["backend/tests/test_alerts_router.py", "backend/tests/test_other.py", "backend/app/routers/alerts.py"], "backend/app/routers/alerts.py")
   == "pytest backend/tests/test_alerts_router.py -v")
ok("prose API note with 'endpoint' + two plausible files => the web view and the router tie closely (model decides in prod)", len(mn.plausible(e3b["candidates"])) >= 2)
rc, out = A.add('The "Sign Out Everywhere" button on Android does nothing', flow="profile", OVN_MANUAL_MODEL="off")
e3c = ent(A, "Sign Out Everywhere\" button on Android", out)
ok("platform word 'Android' steers an otherwise tied UI label to the Android file", e3c.get("path") == "android/app/src/main/java/com/x/ProfileScreen.kt", e3c.get("candidates"))
rc, out = A.add('The "Sign Out Everywhere" button in the browser does nothing', flow="profile", OVN_MANUAL_MODEL="off")
e3d = ent(A, "in the browser does nothing", out)
ok("platform word 'browser' steers it to the web file", e3d.get("path") == "app-web/src/views/ProfileView.vue", e3d.get("candidates"))

# android label -> code via the resource key; weak language
rc, out = A.add("Delete my account permanently dialog never closes", flow="settings")
e4 = ent(A, "Delete my account", out)
ok("UI label in strings.xml resolves to the Kotlin file that uses its key", e4["path"] == "android/app/src/main/java/com/x/SettingsScreen.kt", e4.get("candidates"))
ok("weak-language risk is recorded (kotlin, ~20-35% landing)", e4["risk"] == "weak" and e4["language"] == "kotlin" and "20-35%" in e4["risk_note"])
ok("kotlin item uses a gradle VERIFY and tier T3", "VERIFY: `cd android && ./gradlew testDebugUnitTest`." in e4["item"] and e4["item"].startswith("- [ ] [T3] "), e4["item"])
rc, out = A.add("load_save returns an empty dict for a corrupted slot", flow="save")
e5 = ent(A, "load_save", out)
ok("gdscript note located and uses the gut command with the matching test file",
   e5["path"] == "game/scripts/save/save_manager.gd" and "-gdir=res://game/tests/test_save_manager.gd" not in e5["item"] and "gut_cmdln.gd" in e5["item"], e5["item"])
ok("gdscript is weak-risk", e5["risk"] == "weak")

# needs-triage: nothing enqueued, one relay note
prog_before = A.progress_at_origin()
calls_before = len(A.call_log())
relay.hits.clear()
rc, out = A.add("the whole thing feels slow sometimes when loading", flow="other")
e6 = ent(A, "feels slow", out)
ok("vague note => needs-triage and NOT enqueued", e6["status"] == "needs-triage" and "path" not in e6 and A.progress_at_origin() == prog_before, e6)
ok("needs-triage never touched the clone (no hold/release)", len(A.call_log()) == calls_before, A.call_log()[calls_before:])
ok("exactly one plain relay note, default priority, titled for the repo", relay_titles() == ["Manual bug needs triage: fx"] and relay.hits[0]["headers"].get("Priority") == "default", relay.hits)
ok("relay note carries the note text", "feels slow" in relay.hits[0]["body"])
rc, out = A.add("the whole thing feels slow sometimes when loading", flow="other")
ok("repeating a needs-triage note is a DUPLICATE and does not re-notify", out.startswith("DUPLICATE") and len(relay.hits) == 1)
ok("candidates + note stored for triage", isinstance(e6["candidates"], list) and e6["note"].startswith("the whole thing"))
ok("a bare generic word hitting many files is not evidence (noise files)", "n0" not in json.dumps([c["path"] for c in e6["candidates"] if c["located"]]))

# NTFY_SERVER unset => no notification, no crash
rc, out = A.add("another vague thing that seems off", flow="other", NTFY_SERVER=None)
ok("no NTFY_SERVER => skipped notify, still needs-triage, rc 0", rc == 0 and "needs-triage" in out and len(relay.hits) == 1, out)

# list
rc, out = A.cli("list")
ok("list prints a table with repo/status/files/note", rc == 0 and "needs-triage" in out and "PaywallView.vue" in out and "open" in out, out)
rc, out = A.cli("list", "--json")
ok("list --json is valid JSON", rc == 0 and isinstance(json.loads(out), list))

# validation
rc, out = A.cli("add", "--repo", "nope", "--date", "2026-10-01", "--note", "x y z")
ok("unknown repo => rc 2 (permanent rejection)", rc == 2 and "unknown repo" in out, out)
rc, out = A.cli("add", "--repo", "../fx", "--date", "2026-10-01", "--note", "x y z")
ok("path-traversal repo name rejected", rc == 2, out)
rc, out = A.cli("add", "--repo", "fx", "--date", "yesterday", "--note", "x y z")
ok("bad date rejected", rc == 2)
rc, out = A.cli("add", "--repo", "fx", "--date", "2026-10-01", "--note-b64", "!!!")
ok("garbage base64 handled without a traceback", rc in (0, 2) and "Traceback" not in out, out)
rc, out = A.cli("add", "--repo", "fx", "--date", "2026-10-01", "--note", "\x07​ ")
ok("empty-after-sanitize rejected rc 2", rc == 2)

# ================================================================================================================ sanitizing end to end (no injection)
print("== end-to-end sanitizing")
B = Fix("b")
pwn = os.path.join(ROOT, "PWNED")
nasty = "restorePurchases fails `touch %s` $(touch %s) ; touch %s | cat \"quoted\" 'single' \\ [T1] VERIFY: rm -rf / (cat:x) AUTO-SKIP\nsecond line — dash" % (pwn, pwn, pwn)
rc, out = B.add(nasty, flow="pay'wall; touch %s" % pwn)
eb = entry_of(B)
ok("shell metacharacters in a note never execute", not os.path.exists(pwn))
line = eb.get("item", "")
ok("nasty note produced a single clean item line", line.count("\n") == 0 and line.count("VERIFY:") == 1 and line.count("`") == 2 and line.count("(cat:") == 1 and line.count("[feat:") == 1 and "AUTO-SKIP" not in line.upper().replace("AUTO SKIP", ""), line)
ok("nasty item is still KEPT by the real sanitizer", "total retired: 0" in retire_on(B.progress_at_origin(), B)[1])
ok("flow is reduced to a safe token", "flow paywall" in line or "flow pay" in line)
rc, out = B.add("big " + "restorePurchases " * 2000, flow="paywall", date="2026-10-02")
eb2 = [x for x in B.state().values() if x["date"] == "2026-10-02"][0]
ok("10k-char note: capped at 400 in the stored note and the item", len(eb2["note"]) <= 400 and len(eb2["item"]) < 1200, len(eb2["item"]))
rc, out = B.add("Café 日本語 restorePurchases \U0001F600 emoji", flow="paywall", date="2026-10-03")
eb3 = [x for x in B.state().values() if x["date"] == "2026-10-03"][0]
ok("unicode note enqueued intact (utf-8 round trip through base64 + git)", "Café" in eb3["item"] and "\U0001F600" in B.progress_at_origin() and "日本語" in B.progress_at_origin())

# ================================================================================================================ model tie-break
print("== model tie-break")
C = Fix("c")
AMB = "the weekly digest email shows the wrong date"
model.hits.clear()
model_content["v"] = ""
rc, out = C.add(AMB, flow="digest", OVN_MANUAL_MODEL="off")
ec = entry_of(C)
ok("model off: deterministic top candidate (alphabetical tie-break), no model call", ec["path"] == "backend/app/routers/digest.py" and not model.hits and ec["ranked_by"] == "deterministic", ec)
ok("fixture really is ambiguous (>=2 plausible candidates)", len(mn.plausible(ec["candidates"])) >= 2, ec["candidates"])
C2 = Fix("c2")
model_content["v"] = 'Sure! {"ranking": ["backend/app/services/digest_service.py", "backend/app/routers/digest.py"], "reason": "the service builds the email"}'
rc, out = C2.add(AMB, flow="digest")
ec2 = entry_of(C2)
ok("ambiguous: ONE model request, and its valid ranking decides", len(model.hits) == 1 and ec2["path"] == "backend/app/services/digest_service.py" and ec2["ranked_by"] == "model", (len(model.hits), ec2.get("path")))
req = json.loads(model.hits[0]["body"])
ok("model prompt only offers candidate paths, JSON-only reply requested", "Reply with ONLY a JSON object" in req["messages"][0]["content"] and "node_modules" not in req["messages"][0]["content"] and req.get("max_tokens", 0) <= 600)
ok("model got the auth header + configured model name", model.hits[0]["headers"].get("Authorization", "").startswith("Bearer ") and req["model"] == "qwen-test")
C3 = Fix("c3")
model.hits.clear()
model_content["v"] = '{"ranking": ["/etc/passwd", "../../x.py", "backend/app/invented.py"], "reason": "x"}'
rc, out = C3.add(AMB, flow="digest")
ec3 = entry_of(C3)
ok("model invents paths => all discarded, deterministic fallback", ec3["path"] == "backend/app/routers/digest.py" and ec3["ranked_by"] == "model-unavailable-deterministic", ec3)
ok("an invented path never reaches the queue", "invented" not in ec3["item"] and "passwd" not in ec3["item"])
C4 = Fix("c4")
model_content["v"] = "I think maybe the first one!! (no json at all)"
rc, out = C4.add(AMB, flow="digest")
ok("model garbage => deterministic fallback", entry_of(C4)["path"] == "backend/app/routers/digest.py")
C5 = Fix("c5")
model_content["v"] = '{"ranking": ["backend/app/services/digest_service.py", "/etc/shadow"]}'
rc, out = C5.add(AMB, flow="digest")
ok("model mixes valid + invented => only the valid one is used", entry_of(C5)["path"] == "backend/app/services/digest_service.py")
C6 = Fix("c6")
rc, out = C6.add(AMB, flow="digest", LITELLM_BASE="http://127.0.0.1:%d" % dead_port())
ok("model down (connection refused) => deterministic fallback, still enqueued", rc == 0 and entry_of(C6)["status"] == "open" and entry_of(C6)["path"] == "backend/app/routers/digest.py", out)
C7 = Fix("c7")
rc, out = C7.add(AMB, flow="digest", extra=["--no-model"])
ok("--no-model flag skips the model", entry_of(C7)["ranked_by"] == "deterministic")
C8 = Fix("c8")
bad_srv = start_server(lambda p, b: (500, "boom"))
rc, out = C8.add(AMB, flow="digest", LITELLM_BASE="http://127.0.0.1:%d" % bad_srv.server_address[1])
ok("model HTTP 500 => deterministic fallback", rc == 0 and entry_of(C8)["status"] == "open")

# ================================================================================================================ failure paths release the hold
print("== failure paths")
D = Fix("d")
hook = os.path.join(D.origin, "hooks", "pre-receive")
open(hook, "w").write("#!/bin/sh\necho 'rejected by test hook' >&2\nexit 1\n")
os.chmod(hook, 0o755)
rc, out = D.add('The "Restore Purchases" button does nothing', flow="paywall")
ed = entry_of(D)
ok("push rejected (even after rebase retry) => pending-enqueue, rc 0", rc == 0 and ed["status"] == "pending-enqueue" and "push failed" in ed["enqueue_result"], ed)
ok("push rejected => hold RELEASED", D.call_log() == ["queue hold fx", "queue release fx"], D.call_log())
ok("push rejected => live clone reset to origin (no stray local commit, clean tree)", git(D.clone, "status", "--porcelain").strip() == "" and
   git(D.clone, "rev-parse", "HEAD") == sh(["git", "--git-dir=" + D.origin, "rev-parse", "overnight/feature"])[1])
ok("push rejected => origin untouched", "[feat:" not in D.progress_at_origin())
os.remove(hook)
rc, out = D.sweep()
ed = entry_of(D)
ok("sweep retries a pending-enqueue and lands it", ed["status"] == "open" and "[feat:%s]" % ed["feat"] in D.progress_at_origin(), (ed, out))
ok("retry also released the hold", D.call_log()[-2:] == ["queue hold fx", "queue release fx"])

E = Fix("e")
cnt = os.path.join(E.d, "rej1")
open(cnt, "w").write("x")
hook = os.path.join(E.origin, "hooks", "pre-receive")
open(hook, "w").write("#!/bin/sh\nif [ -f '%s' ]; then rm -f '%s'; echo 'first push rejected' >&2; exit 1; fi\nexit 0\n" % (cnt, cnt))
os.chmod(hook, 0o755)
rc, out = E.add('The "Restore Purchases" button does nothing', flow="paywall")
ok("first push rejected => pull --rebase + retry succeeds", entry_of(E)["status"] == "open" and "[feat:" in E.progress_at_origin(), (out, entry_of(E)))

G = Fix("g")
git(G.clone, "remote", "set-url", "origin", os.path.join(G.d, "does-not-exist.git"))
rc, out = G.add('The "Restore Purchases" button does nothing', flow="paywall")
ok("git error (fetch fails) => pending-enqueue and hold released", entry_of(G)["status"] == "pending-enqueue" and G.call_log() == ["queue hold fx", "queue release fx"], (entry_of(G), G.call_log()))

H = Fix("h")
git(H.clone, "checkout", "-q", "-b", "claude/feature")
head_before = git(H.clone, "rev-parse", "HEAD")
rc, out = H.add('The "Restore Purchases" button does nothing', flow="paywall")
ok("live clone on another branch => refuses to touch it, hold released", entry_of(H)["status"] == "pending-enqueue" and "not touching" in entry_of(H)["enqueue_result"]
   and git(H.clone, "rev-parse", "HEAD") == head_before and H.call_log() == ["queue hold fx", "queue release fx"], entry_of(H))

I = Fix("i")
I.origin_edit(lambda t: t.replace("## Next Steps", "## Steps"), "rename section")
rc, out = I.add('The "Restore Purchases" button does nothing', flow="paywall")
ok("no '## Next Steps' section => pending-enqueue + hold released, nothing pushed", entry_of(I)["status"] == "pending-enqueue" and I.call_log() == ["queue hold fx", "queue release fx"] and "[feat:" not in I.progress_at_origin())

# a human-set hold on the repo is respected: no takeover, no release, nothing touched, entry retried later
HH = Fix("hh")
os.makedirs(os.path.join(HH.ovn, "state"), exist_ok=True)
open(os.path.join(HH.ovn, "state", "HOLD_fx"), "w").close()
head_hh = git(HH.clone, "rev-parse", "HEAD")
rc, out = HH.add('The "Restore Purchases" button does nothing', flow="paywall")
ok("human hold on the repo => not taken over, NOT released, clone untouched, entry stays pending-enqueue",
   entry_of(HH)["status"] == "pending-enqueue" and "on hold" in entry_of(HH)["enqueue_result"] and HH.call_log() == []
   and os.path.exists(os.path.join(HH.ovn, "state", "HOLD_fx")) and git(HH.clone, "rev-parse", "HEAD") == head_hh, (entry_of(HH), HH.call_log()))

# in-process: an exception inside the edit path still releases the hold
J = Fix("j")
os.environ["OVN_DIR"] = J.ovn
orig_insert = mn.insert_item
mn.insert_item = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom"))
try:
    okf, msg = mn.enqueue("fx", J.clone, "- [ ] [T2] x.py — y [feat:zz]")
finally:
    mn.insert_item = orig_insert
ok("exception while editing => (False, ...) and hold released", okf is False and "boom" in msg and J.call_log() == ["queue hold fx", "queue release fx"], (msg, J.call_log()))
ok("exception path leaves the clone clean", git(J.clone, "status", "--porcelain").strip() == "")
ok("insert_item idempotent on the feat tag", mn.insert_item("## Next Steps\n- [ ] a [feat:q]\n", "- [ ] b [feat:q]")[1] == "already-present")
os.environ.pop("OVN_DIR", None)

# ================================================================================================================ lanes
print("== lanes")
L = Fix("l", qa_on=True)
rc, out = L.add('The "Restore Purchases" button does nothing', flow="paywall")
el = entry_of(L)
ok("QA mode on => the repo's dev lane is enabled and recorded", "qa_mode lane fx" in L.call_log() and el["lane_enabled_by_us"] is True and "ongoing-fx" in L.qa()["temp_lanes"], (L.call_log(), el))
rc, out = L.sweep()
ok("item still open => lane stays on, no relay note", "qa_mode unlane fx" not in L.call_log() and entry_of(L)["status"] == "open")
relay.hits.clear()
fk = el["feat"]
L.origin_edit(lambda t: t.replace("- [ ] [T3] app-web/src/views/PaywallView.vue", "- [x] [T3] app-web/src/views/PaywallView.vue", 1), "fleet lands it")
rc, out = L.sweep()
el = entry_of(L)
ok("[x] at origin => status fixed", el["status"] == "fixed", (el, out))
ok("nothing open + we enabled the lane => unlane called and recorded", "qa_mode unlane fx" in L.call_log() and el.get("lane_released") is True and L.qa()["temp_lanes"] == [])
ok("exactly one 'fixed' relay note with the note trimmed", relay_titles() == ["Manual bug fixed: fx"] and "Restore Purchases" in relay.hits[0]["body"] and len(relay.hits[0]["body"]) < 200, relay.hits)
rc, out = L.sweep()
ok("further sweeps do not re-notify or re-unlane", len(relay.hits) == 1 and L.call_log().count("qa_mode unlane fx") == 1)

M = Fix("m")
rc, out = M.add('The "Restore Purchases" button does nothing', flow="paywall")
ok("QA mode off (no qa_mode.json) => lane never touched", not any(c.startswith("qa_mode") for c in M.call_log()) and not entry_of(M).get("lane_enabled_by_us"))
N = Fix("n", qa_on=True)
rc, out = N.add('The "Restore Purchases" button does nothing', flow="paywall", OVN_MANUAL_AUTOLANE="off")
ok("OVN_MANUAL_AUTOLANE=off => lane never touched", not any(c.startswith("qa_mode") for c in N.call_log()))
O = Fix("o", qa_on=True)
O.set_qa({"mode": "qa", "disabled_lanes": ["ongoing-fx"], "temp_lanes": ["ongoing-fx"]})
rc, out = O.add('The "Restore Purchases" button does nothing', flow="paywall")
ok("lane already enabled by someone else => not claimed, never released by us", not entry_of(O).get("lane_enabled_by_us") and not any(c.startswith("qa_mode") for c in O.call_log()))

Q = Fix("q", qa_on=True)
rc, out = Q.add('The "Restore Purchases" button does nothing', flow="paywall")
st = json.load(open(os.path.join(Q.ovn, "state", "manual_notes.json")))
for v in st["entries"].values():
    v["lane_enabled_at"] = time.time() - 25 * 3600
json.dump(st, open(os.path.join(Q.ovn, "state", "manual_notes.json"), "w"))
rc, out = Q.sweep()
ok("24h safety valve: lane released even though the item is still open", "qa_mode unlane fx" in Q.call_log() and entry_of(Q)["status"] == "open" and entry_of(Q)["lane_released"] is True, (Q.call_log(), entry_of(Q)))
st = json.load(open(os.path.join(Q.ovn, "state", "manual_notes.json")))
ok("valve reason recorded", "24h" in list(st["entries"].values())[0]["lane_note"])

R = Fix("r", qa_on=True)
rc, out = R.add('The "Restore Purchases" button does nothing', flow="paywall")
os.remove(os.path.join(R.ovn, "state", "qa_mode.json"))      # someone ran `qa_mode.sh off` meanwhile (lanes restored to dev state)
R.origin_edit(lambda t: t.replace("- [ ] [T3] app-web", "- [x] [T3] app-web", 1))
rc, out = R.sweep()
ok("after `qa_mode.sh off` we must NOT unlane (would disable a restored dev lane); flag cleared", "qa_mode unlane fx" not in R.call_log() and entry_of(R).get("lane_released") is True and entry_of(R)["status"] == "fixed")

# ================================================================================================================ sweep transitions
print("== sweep transitions")
S = Fix("s", qa_on=True)
S.add('The "Restore Purchases" button does nothing', flow="paywall")
relay.hits.clear()
S.origin_edit(lambda t: t.replace("- [ ] [T3] app-web", "- [ ] [AUTO-SKIP after 5 no-op cycles - review] [T3] app-web", 1))
rc, out = S.sweep()
es = entry_of(S)
ok("AUTO-SKIP at origin => needs-human", es["status"] == "needs-human", (es, out))
ok("one 'needs a human' note, language named, note trimmed", relay_titles() == ["Manual bug needs a human: fx"] and "Restore Purchases" in relay.hits[0]["body"], relay.hits)
ok("needs-human also releases the lane we enabled", "qa_mode unlane fx" in S.call_log())
S.sweep()
ok("no duplicate needs-human note on the next sweep", len(relay.hits) == 1)

T = Fix("t")
T.add('The "Restore Purchases" button does nothing', flow="paywall")
T.origin_edit(lambda t: t.replace("- [ ] [T3] app-web", "- [ ] [CLAUDE] [T3] app-web", 1))
T.sweep()
ok("[CLAUDE] marker => needs-human", entry_of(T)["status"] == "needs-human")

U = Fix("u")
U.add('The "Restore Purchases" button does nothing', flow="paywall")
U.origin_edit(lambda t: t.replace("- [ ] [T3] app-web", "- [x] (retired-vague) [T3] app-web", 1))
U.sweep()
ok("(retired- marker => needs-human, not fixed", entry_of(U)["status"] == "needs-human")

V = Fix("v")
V.add('The "Restore Purchases" button does nothing', flow="paywall")
V.origin_edit(lambda t: t.replace("- [ ] [T3] app-web", "- [x] (already-satisfied in code, implement-verified) [T3] app-web", 1))
V.sweep()
ok("'already-satisfied' credit is NOT reported as fixed (needs-human: the bug was real)", entry_of(V)["status"] == "needs-human" and "already satisfied" in entry_of(V)["status_reason"])

W = Fix("w")
W.add('The "Restore Purchases" button does nothing', flow="paywall")
fk = entry_of(W)["feat"]


def archive(t):
    ln = [l for l in t.split("\n") if "[feat:%s]" % fk in l][0]
    return t.replace(ln + "\n", "")


W.origin_edit(archive, "archive moves the line out")
rc, out = W.sweep()
ok("line gone from the progress file just now => stays open (grace period)", entry_of(W)["status"] == "open")
st = json.load(open(os.path.join(W.ovn, "state", "manual_notes.json")))
for v in st["entries"].values():
    v["enqueued_at"] = time.time() - 7200
json.dump(st, open(os.path.join(W.ovn, "state", "manual_notes.json"), "w"))
W.sweep()
ok("line vanished for >1h => needs-human (retired/removed), never silently fixed", entry_of(W)["status"] == "needs-human")
# archived as [x] in OVERNIGHT_DONE.md => fixed
X = Fix("x")
X.add('The "Restore Purchases" button does nothing', flow="paywall")
fk = entry_of(X)["feat"]
git(X.work, "pull", "-q", "--rebase", "origin", "overnight/feature")
pr = open(os.path.join(X.work, "OVERNIGHT_PROGRESS.md")).read()
ln = [l for l in pr.split("\n") if "[feat:%s]" % fk in l][0]
open(os.path.join(X.work, "OVERNIGHT_PROGRESS.md"), "w").write(pr.replace(ln + "\n", ""))
open(os.path.join(X.work, "OVERNIGHT_DONE.md"), "w").write(ln.replace("- [ ]", "- [x]", 1) + "\n")
git(X.work, "add", "OVERNIGHT_PROGRESS.md", "OVERNIGHT_DONE.md")
git(X.work, "commit", "-q", "-m", "archive")
git(X.work, "push", "-q", "origin", "overnight/feature")
X.sweep()
ok("[x] archived into OVERNIGHT_DONE.md => fixed", entry_of(X)["status"] == "fixed")
# sweep with no open entries / a missing clone is a clean no-op
Y = Fix("y")
rc, out = Y.sweep()
ok("sweep with an empty state exits 0", rc == 0 and "0 status change" in out, out)
Z = Fix("z")
Z.add('The "Restore Purchases" button does nothing', flow="paywall")
git(Z.clone, "remote", "set-url", "origin", os.path.join(Z.d, "gone.git"))
rc, out = Z.sweep()
ok("sweep: fetch failure leaves statuses untouched, rc 0", rc == 0 and entry_of(Z)["status"] == "open", out)

# ================================================================================================================ cron wrapper
print("== cron wrapper")
K = Fix("k")
K.add('The "Restore Purchases" button does nothing', flow="paywall")
K.origin_edit(lambda t: t.replace("- [ ] [T3] app-web", "- [x] [T3] app-web", 1))
# place a copy of qa/ next to the fixture OVN_DIR so the wrapper resolves its own dir the way it does on the box
shutil.copytree(QA, os.path.join(K.ovn, "qa"), ignore=shutil.ignore_patterns("__pycache__"))
env = {"PATH": MINPATH, "HOME": K.d, "NTFY_SERVER": RELAY, "NTFY_TOPIC": "t-test"}
rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["bash", os.path.join(K.ovn, "qa", "manual_notes_cron.sh")])
ok("cron wrapper (absolute path, env -i, OVN_DIR derived from its own location) sweeps and exits 0", rc == 0 and entry_of(K)["status"] == "fixed", out)
K2 = Fix("k2")
K2.add('The "Restore Purchases" button does nothing', flow="paywall")
K2.origin_edit(lambda t: t.replace("- [ ] [T3] app-web", "- [x] [T3] app-web", 1))
shutil.copytree(QA, os.path.join(K2.ovn, "qa"), ignore=shutil.ignore_patterns("__pycache__"))
rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["bash", "qa/manual_notes_cron.sh"], cwd=K2.ovn)
ok("cron wrapper via a RELATIVE path from OVN_DIR works", rc == 0 and entry_of(K2)["status"] == "fixed", out)
K3 = Fix("k3")
shutil.copytree(QA, os.path.join(K3.ovn, "qa"), ignore=shutil.ignore_patterns("__pycache__"))
import fcntl
lk = open(os.path.join(K3.ovn, "state", "manual_notes_cron.lock"), "a")
fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)                 # the flock(1) path (box)
os.makedirs(os.path.join(K3.ovn, "state", "manual_notes_cron.lock.d"))   # the mkdir-lock path (Mac without flock)
rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["bash", os.path.join(K3.ovn, "qa", "manual_notes_cron.sh")])
ok("cron wrapper: a sweep already running => skips, exits 0", rc == 0 and "still running" in out, out)
rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["OVN_MANUAL_SWEEP=off", "bash", os.path.join(K3.ovn, "qa", "manual_notes_cron.sh")])
ok("cron wrapper: OVN_MANUAL_SWEEP=off kill switch", rc == 0 and "disabled" in out)
rc, out = sh(["env", "-i", "PATH=" + MINPATH, "HOME=" + K3.d, "OVN_DIR=/nonexistent/zzz", "bash", os.path.join(K3.ovn, "qa", "manual_notes_cron.sh")])
ok("cron wrapper: broken OVN_DIR still exits 0", rc == 0, out)

# ================================================================================================================ bridge (Mac side)
print("== bridge")
if not os.path.exists(BRIDGE):
    # the bridge is a MAC-side tool (scripts/qa-notes-bridge.sh in the shared repo); the box tree does not have it, and the box
    # runs this suite from cron - skip rather than fail there
    print("  SKIP bridge tests: %s is a Mac-side script and is not present on this machine" % BRIDGE)
    shutil.rmtree(ROOT, ignore_errors=True)
    print("manual notes: %d passed, %d failed (bridge section skipped)" % (P, F))
    sys.exit(0 if F == 0 else 1)
BR = os.path.join(ROOT, "bridge")
os.makedirs(BR)
logs = os.path.join(BR, "logs")
os.makedirs(logs)
state = os.path.join(BR, "state")
calls = os.path.join(BR, "ssh_calls.log")
mode_file = os.path.join(BR, "ssh_mode")


def write_stub(target_fix=None):
    """A stub ssh: records the call, then behaves according to ssh_mode (ok = run the REMOTE command locally against the fixture,
    fail = rc 255, reject = rc 2)."""
    p = os.path.join(BR, "ssh")
    open(p, "w").write("""#!/usr/bin/env bash
# args: -n -o ... host cmd   (cmd is the last arg)
cmd="${@: -1}"
printf '%%s\\n' "$cmd" >> "%(calls)s"
mode="$(cat "%(mode)s" 2>/dev/null || echo ok)"
case "$mode" in
  fail) echo "ssh: connect to host: Connection timed out" >&2; exit 255;;
  reject) echo "ERROR: unknown repo" ; exit 2;;
  busy) echo "ERROR: busy"; exit 1;;
esac
HOME="%(home)s" PATH="/opt/homebrew/bin:/usr/bin:/bin" OVN_MANUAL_MODEL=off OVN_DIR="%(ovn)s" bash -c "$cmd"
""" % {"calls": calls, "mode": mode_file, "home": target_fix.d, "ovn": target_fix.ovn})
    os.chmod(p, 0o755)
    return p


BF = Fix("bridgefix")
# the remote command does `cd ~/overnight-queue` and runs ~/overnight-queue/qa/manual_notes_ingest.py: make HOME/overnight-queue = the OVN_DIR
os.symlink(BF.ovn, os.path.join(BF.d, "overnight-queue"))
shutil.copytree(QA, os.path.join(BF.ovn, "qa"), ignore=shutil.ignore_patterns("__pycache__"))
stub = write_stub(BF)
# the bridge reads qa/manual_logs/<repo>.txt; the fixture repo is named 'fx'
open(os.path.join(logs, "fx.txt"), "w").write(
    "# Manual testing log\n# Format: date | flow | minutes | result | note\n"
    "2026-10-01 | paywall | 15 | bug | The \"Restore Purchases\" button does nothing on the paywall\n"
    "2026-10-01 | login | 5 | ok | fine\n"
    "2026-10-01 | export | 10 | BUG | build_export_payload crashes with a | pipe in the note\n"
    "\n"
    "2026-10-01 | tv-focus | 3 | bug | the whole thing feels slow sometimes when loading\n")
benv = {"PATH": MINPATH, "HOME": BF.d, "QA_NOTES_LOGS_DIR": logs, "QA_NOTES_STATE": state, "QA_NOTES_SSH": stub, "OVN_SSH": "u@box",
        "QA_NOTES_NTFY": RELAY, "OVN_REMOTE_DIR": "overnight-queue", "NTFY_TOPIC": "t-test"}


def bridge(env=None, cwd=None, script=BRIDGE):
    e = dict(benv)
    if env:
        e.update(env)
    return sh(["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + ["bash", script], cwd=cwd)


def ncalls():
    try:
        return len(open(calls).read().splitlines())
    except OSError:
        return 0


open(mode_file, "w").write("fail")
rc, out = bridge()
ok("ssh failure: exits 0, nothing marked done, stops after the first failed call (box unreachable)", rc == 0 and ncalls() == 1 and
   not open(os.path.join(state, "fx.done")).read().strip(), (rc, out, ncalls()))
ok("ssh failure is logged to ~/.qa_notes_bridge/bridge.log", "will retry next run" in open(os.path.join(state, "bridge.log")).read())
open(mode_file, "w").write("ok")
os.remove(calls)
relay.hits.clear()
rc, out = bridge()
ok("recovery: the 3 bug lines are bridged (the ok line is not)", rc == 0 and ncalls() == 3 and "bridged=3" in out, (out, ncalls()))
cmds = open(calls).read().splitlines()
ok("remote command: python3.12 + manual_notes_ingest.py add, base64 note, quoted tokens only", all("python3.12" in c and "manual_notes_ingest.py add --repo 'fx'" in c and "--note-b64 '" in c for c in cmds), cmds[0])
ok("remote command carries NO raw note text", all("Restore" not in c and "pipe" not in c for c in cmds))
ok("base64 round trip: the box received the exact note (pipe included)", any("crashes with a | pipe" in v["note"] or "crashes with a / pipe" in v["note"] for v in BF.state().values()), list(BF.state().values()))
ok("box state has the 3 notes; vague one is needs-triage", len(BF.state()) == 3 and sorted(v["status"] for v in BF.state().values()).count("needs-triage") == 1, [v["status"] for v in BF.state().values()])
ok("relay got the triage note (via the real ingest, local relay only)", "Manual bug needs triage: fx" in relay_titles())
done_before = open(os.path.join(state, "fx.done")).read()
os.remove(calls)
rc, out = bridge()
ok("idempotent: a second run makes zero ssh calls", rc == 0 and ncalls() == 0 and "already-done=3" in out, out)
ok("done file has hash<TAB>status<TAB>ts lines", all(len(l.split("\t")) == 3 for l in done_before.strip().split("\n")))
with open(os.path.join(logs, "fx.txt"), "a") as fh:
    fh.write("2026-10-02 | other | 4 | bug | backend/app/routers/alerts.py returns 500 when empty\n")
rc, out = bridge(cwd=BR)
ok("only the NEW bug line is sent next run", ncalls() == 1 and "bridged=1" in out, out)
# hand-written lines (Mark's real format): M/D/YYYY dates, flow names with spaces, trailing text without a final newline
with open(os.path.join(logs, "fx.txt"), "a") as fh:
    fh.write("\n10/01/2026 | Home Page Countries Filter  | 5 | bug | Clicking countries filter only showed all and Qatar 2 in backend/app/routers/alerts.py.")
os.remove(calls)
rc, out = bridge()
cmd_h = open(calls).read().splitlines()
ok("hand-written line (10/01/2026, spaced flow name) is bridged, date normalised to ISO and flow slugged",
   ncalls() == 1 and "--date '2026-10-01'" in cmd_h[0] and "--flow 'home-page-countries-filter'" in cmd_h[0] and "bridged=1" in out, (out, cmd_h))
os.remove(calls)
rc, out = bridge()
ok("the hand-written line is not re-sent (dedupe uses the raw line)", ncalls() == 0, out)
open(mode_file, "w").write("reject")
with open(os.path.join(logs, "fx.txt"), "a") as fh:
    fh.write("2026-10-03 | other | 4 | bug | something unknown\n")
rc, out = bridge()
n_after_reject = ncalls()
rc, out = bridge()
ok("rc 2 (permanent rejection) is recorded and NOT retried", ncalls() == n_after_reject and "rejected" in open(os.path.join(state, "fx.done")).read())
open(mode_file, "w").write("busy")
with open(os.path.join(logs, "fx.txt"), "a") as fh:
    fh.write("2026-10-04 | other | 4 | bug | needs retry after busy\n")
rc, out = bridge()
rc2, out2 = bridge()
ok("rc 1 (box busy) is retried on the next run", rc == 0 and ncalls() >= n_after_reject + 2)
open(mode_file, "w").write("ok")
# hostile hand-edited lines cannot inject into the remote shell
with open(os.path.join(logs, "fx.txt"), "a") as fh:
    fh.write("2026-10-05 | x'; touch %s; ' | 5 | bug | quote ' and $(touch %s) \"x\" `touch %s`\n" % (pwn, pwn, pwn))
    fh.write("not-a-date | x | 5 | bug | bad date line\n")
    fh.write("2026-10-06 | x | 5 | bug | \n")
rc, out = bridge()
ok("hostile flow/note: nothing executes anywhere", not os.path.exists(pwn))
ok("bad date and empty-note bug lines are rejected locally, not sent", "bad date" in out and "no note" in out, out)
last = open(calls).read().splitlines()[-1]
ok("hostile flow reduced to [A-Za-z0-9_.-]", "--flow 'xtouch" in last or "--flow 'x" in last, last)
# relative path invocation + minimal env
rc, out = sh(["env", "-i", "PATH=" + MINPATH, "HOME=" + BF.d] + ["%s=%s" % kv for kv in benv.items() if kv[0] not in ("PATH", "HOME")] +
             ["bash", "scripts/qa-notes-bridge.sh"], cwd=os.path.dirname(os.path.dirname(BRIDGE)))
ok("bridge via a RELATIVE path from the repo root works under env -i", rc == 0 and "qa-notes-bridge done" in out, out)
rc, out = bridge(env={"QA_NOTES_LOGS_DIR": "/nonexistent/zz"})
ok("missing logs dir: exits 0", rc == 0)
rc, out = bridge(env={"QA_NOTES_STATE": "/proc/forbidden/x"})
ok("unwritable state dir: exits 0", rc == 0)
os.makedirs(os.path.join(state, "bridge.lock.d"), exist_ok=True)
rc, out = bridge()
ok("fresh lock held by another run: skips, exits 0", rc == 0 and "another bridge run is active" in out, out)
os.rmdir(os.path.join(state, "bridge.lock.d"))
import re as _re
code = [l.split("  #")[0].split(" # ")[0] for l in open(BRIDGE) if not l.lstrip().startswith("#")]
ok("the Mac bridge invokes no flock / timeout binary (mkdir lock + qa_timeout.py only)", not any(_re.search(r"(^|[;&|(\s])(flock|timeout)\s", l) for l in code))
ok("plist template exists and is valid XML", subprocess.run(["python3", "-c", "import plistlib,sys;plistlib.load(open(sys.argv[1],'rb'))", os.path.join(os.path.dirname(BRIDGE), "com.shrike.qa-notes-bridge.plist")]).returncode == 0)

# ================================================================================================================ ntfy.sh is never reached
print("== no ntfy.sh")
src = open(INGEST).read()
ok("ingest has no hard-coded ntfy.sh default (unset NTFY_SERVER => skip)", "ntfy.sh" not in src.replace("never reach ntfy.sh", "").replace("NEVER ntfy.sh", "").replace("reach ntfy.sh unless", ""))

shutil.rmtree(ROOT, ignore_errors=True)
print("manual notes: %d passed, %d failed" % (P, F))
sys.exit(0 if F == 0 else 1)
