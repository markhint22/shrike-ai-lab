#!/usr/bin/env python3
"""scripts/ovn_doc_executor.py: deterministic executor for supply:gd-missing-doc items (2026-10-09).

A stub LiteLLM (http.server) returns fixed text, so nothing here needs a model. Covers: check() OK/SKIP matrix (non-supply, banned, addons, battle.gd,
untracked, non-.gd, no names, kill switch), apply() placement (above the func, the func's indentation, `static func`, nested class, blank line between an
existing ## block and its func removed), the diff contains ONLY `##` lines and removed blank lines, the item's real VERIFY (ovn_work_supply.verify_gd_docs)
goes red -> green, the request shape (temperature 0, max_tokens 200, body capped at 80 lines), all-or-nothing rejection of fenced / empty /
multi-paragraph / over-100-column / too-long / code-looking output and an unreachable model (file byte-identical), gdparse failure restores the file.
The same battery is then run against MUTATED copies of the tool: each mutant must make it fail."""
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOL = os.path.join(ROOT, "scripts", "ovn_doc_executor.py")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import os as _os
_os.environ["OVN_SUPPLY_GD_DOCS"] = "on"   # supply-v2 ships the gd-doc family OFF by default; this module exercises the collector explicitly
import ovn_work_supply as W  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


# the verify_gd_docs of before 2026-10-09: only the line directly above the func counts
LEGACY_VERIFY = ("python3 -c \"import re,sys;L=open('%s').read().split(chr(10));names=%r;"
                 "bad=[n for n in names if not any(re.match(r'(static )?func '+n+r'[(]',l) and i and L[i-1].lstrip().startswith('##') for i,l in enumerate(L))];"
                 "sys.exit(1 if bad else 0)\"")

GOOD = "Applies damage to the unit.\nArgs: amount and kind.\nReturns the remaining hp."

FIXTURE = (
    "extends Node\n"
    "class_name Fx\n"
    "\n"
    "var hp = 10\n"
    "\n"
    "func take_damage(amount, kind):\n"
    "\tvar x = amount * 2\n"
    "\thp -= x\n"
    "\tif hp < 0:\n"
    "\t\thp = 0\n"
    "\treturn hp\n"
    "\n"
    "static func clamp_hp(v):\n"
    "\tvar lo = 0\n"
    "\tvar hi = 100\n"
    "\tvar r = clamp(v, lo, hi)\n"
    "\tprint(r)\n"
    "\treturn r\n"
    "\n"
    "## Already has a doc.\n"
    "func documented(a):\n"
    "\treturn a\n"
    "\n"
    "## A block separated from its func by blank lines.\n"
    "\n"
    "\n"
    "func separated(a):\n"
    "\treturn a\n"
    "\n"
    "class Inner:\n"
    "\tfunc nested(a, b):\n"
    "\t\tvar s = a + b\n"
    "\t\tvar t = s * 2\n"
    "\t\tprint(t)\n"
    "\t\tprint(s)\n"
    "\t\treturn t\n"
)

TEXT_T = ("Add a `##` doc-comment (one to three lines: what it does, key arguments, return value) on the line directly above each of these GDScript functions: %s. "
          "Comments only - change no code, no signatures.")


def item_for(path, names):
    spec = {"kind": "gd-missing-doc", "file": path, "tier": "T2", "cat": "godot", "text": TEXT_T % ", ".join("`%s`" % n for n in names),
            "verify": W.verify_gd_docs(path, names)}
    return W.render(spec, "xlite"), spec


class Stub:
    def __init__(self):
        self.replies = {}
        self.default = GOOD
        self.requests = []
        self.status = 200
        outer = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_POST(self):
                n = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(n))
                outer.requests.append(body)
                if outer.status != 200:
                    self.send_response(outer.status)
                    self.end_headers()
                    return
                prompt = body["messages"][0]["content"]
                m = re.search(r"function `(\w+)`", prompt)
                text = outer.replies.get(m.group(1) if m else "", outer.default)
                out = json.dumps({"choices": [{"message": {"content": text}}], "usage": {}}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

        self.srv = http.server.HTTPServer(("127.0.0.1", 0), H)
        self.url = "http://127.0.0.1:%d" % self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def reset(self):
        self.replies, self.default, self.requests, self.status = {}, GOOD, [], 200


def sh(*a, cwd=None, env=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True, env=env)


def make_repo(files, banned=None, untracked=None):
    d = tempfile.mkdtemp(prefix="docx-")
    sh("git", "init", "-q", cwd=d)
    for rp, body in files.items():
        fp = os.path.join(d, rp)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "w").write(body)
    if banned is not None:
        open(os.path.join(d, ".queue-hard-banned-files"), "w").write(banned)
    sh("git", "add", "-A", cwd=d)
    sh("git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init", cwd=d)
    for rp, body in (untracked or {}).items():
        fp = os.path.join(d, rp)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "w").write(body)
    return d


def run(tool, mode, repo, item, stub, home, extra_env=None):
    env = dict(os.environ, LITELLM_BASE=stub.url if stub else "http://127.0.0.1:9", HOME=home)
    env.pop("OVN_DOC_EXECUTOR", None)
    env.update(extra_env or {})
    r = subprocess.run([sys.executable, tool, mode, repo, item], capture_output=True, text=True, env=env, timeout=120)
    return r.stdout.strip().split("\t"), r


def verify_rc(repo, verify_cmd):
    return subprocess.run(["bash", "-c", verify_cmd], cwd=repo, capture_output=True, text=True).returncode


def battery(tool, stub, tag):
    """Every behaviour assertion against the given tool script. Returns the number of failed assertions (printed only for tag == 'real')."""
    bad = 0

    def chk(name, cond, extra=""):
        nonlocal bad
        if not cond:
            bad += 1
            if tag == "real":
                ok(name, False, extra)

    home = tempfile.mkdtemp(prefix="docx-home-")
    rd = make_repo({"scripts/mission/fx.gd": FIXTURE, "scripts/battle/battle.gd": FIXTURE, "addons/gut/lib.gd": FIXTURE, "scripts/mission/banned_one.gd": FIXTURE,
                    "scripts/notes.md": "x\n"}, banned="# banned\nscripts/mission/banned_one.gd\n", untracked={"scripts/mission/loose.gd": FIXTURE})
    item, spec = item_for("scripts/mission/fx.gd", ["take_damage", "clamp_hp"])

    # ---------------- check()
    r, _ = run(tool, "check", rd, item, stub, home)
    chk("check: real-shaped supply item -> OK<TAB>file", r == ["OK", "scripts/mission/fx.gd"], r)
    r, _ = run(tool, "check", rd, item.replace("supply:gd-missing-doc", "supply:missing-docstring"), stub, home)
    chk("check: other supply kind -> SKIP", r[0] == "SKIP", r)
    r, _ = run(tool, "check", rd, "- [ ] [T2] scripts/mission/fx.gd — refactor take_damage. VERIFY: `true`.", stub, home)
    chk("check: non-supply item -> SKIP", r[0] == "SKIP", r)
    for p in ("scripts/battle/battle.gd", "addons/gut/lib.gd", "scripts/mission/banned_one.gd", "scripts/mission/loose.gd"):
        it, _ = item_for(p, ["take_damage"])
        r, _ = run(tool, "check", rd, it, stub, home)
        chk("check: %s -> SKIP (%s)" % (p, "untracked" if "loose" in p else "banned"), r[0] == "SKIP", r)
    it, _ = item_for("scripts/notes.md", ["take_damage"])
    r, _ = run(tool, "check", rd, it, stub, home)
    chk("check: non-.gd target -> SKIP", r[0] == "SKIP", r)
    r, _ = run(tool, "check", rd, item.replace("`take_damage`, `clamp_hp`", "none"), stub, home)
    chk("check: no function names -> SKIP", r[0] == "SKIP", r)
    r, _ = run(tool, "check", rd, item, stub, home, {"OVN_DOC_EXECUTOR": "off"})
    chk("check: OVN_DOC_EXECUTOR=off -> SKIP", r[0] == "SKIP", r)
    chk("check never calls the model", len(stub.requests) == 0, stub.requests)

    # ---------------- apply(): placement
    stub.reset()
    path = os.path.join(rd, "scripts/mission/fx.gd")
    before = open(path).read()
    stub.replies = {"take_damage": GOOD, "clamp_hp": "Clamps a value into 0..100.", "nested": "Adds and doubles.\nReturns the doubled sum."}
    it2, spec2 = item_for("scripts/mission/fx.gd", ["take_damage", "clamp_hp", "separated", "nested", "documented"])
    # the real collector only emits top-level funcs, so its VERIFY (`re.match` at column 0) cannot see the nested one: verify the top-level names only
    spec2 = dict(spec2, verify=W.verify_gd_docs("scripts/mission/fx.gd", ["take_damage", "clamp_hp", "separated", "documented"]))
    chk("VERIFY is red before apply", verify_rc(rd, spec2["verify"]) == 1)
    r, _ = run(tool, "apply", rd, it2, stub, home)
    chk("apply: APPLIED<TAB>file<TAB>n docs (3 inserted + 1 blank-fix = 4)", r == ["APPLIED", "scripts/mission/fx.gd", "4 docs"], r)
    after = open(path).read()
    L = after.split("\n")
    i = L.index("func take_damage(amount, kind):")
    chk("take_damage: 3 ## lines directly above, no indentation", L[i - 3:i] == ["## " + x for x in GOOD.split("\n")], L[i - 4:i + 1])
    i = L.index("static func clamp_hp(v):")
    chk("static func: ## line directly above", L[i - 1] == "## Clamps a value into 0..100.", L[i - 2:i + 1])
    i = L.index("\tfunc nested(a, b):")
    chk("nested class func: doc lines carry the func's tab indentation", L[i - 2:i] == ["\t## Adds and doubles.", "\t## Returns the doubled sum."], L[i - 3:i + 1])
    i = L.index("func separated(a):")
    chk("separated: blank lines between the ## block and the func removed", L[i - 1] == "## A block separated from its func by blank lines.", L[i - 3:i + 1])
    chk("separated: no model call was made for it (only 3 requests: take_damage, clamp_hp, nested)", len(stub.requests) == 3, len(stub.requests))
    chk("documented: no extra ## inserted above it", L[L.index("func documented(a):") - 1] == "## Already has a doc." and L[L.index("func documented(a):") - 2] == "")
    d = subprocess.run(["diff", "-u", "/dev/stdin", path], input=before, capture_output=True, text=True).stdout.split("\n")
    added = [l[1:] for l in d if l.startswith("+") and not l.startswith("+++")]
    removed = [l[1:] for l in d if l.startswith("-") and not l.startswith("---")]
    chk("diff: every added line is a ## line", added and all(l.lstrip().startswith("##") for l in added), added)
    chk("diff: every removed line is blank", all(not l.strip() for l in removed), removed)
    chk("diff: exactly the expected counts (3+1+2 added, 2 removed)", len(added) == 6 and len(removed) == 2, (len(added), len(removed)))
    chk("VERIFY is green after apply", verify_rc(rd, spec2["verify"]) == 0)
    # request shape
    q = stub.requests[0]
    chk("request: temperature 0, max_tokens 200", q.get("temperature") == 0 and q.get("max_tokens") == 200, q)
    # idempotence: nothing left to do
    stub.reset()
    r, _ = run(tool, "apply", rd, it2, stub, home)
    chk("apply twice: second run is SKIP and writes nothing", r[0] == "SKIP" and open(path).read() == after and len(stub.requests) == 0, r)

    # ---------------- body capped at 80 lines
    big = "func huge(a):\n" + "".join("\tprint(%d)\n" % k for k in range(200)) + "\treturn a\n"
    rd2 = make_repo({"scripts/big.gd": "extends Node\n" + big})
    it3, _ = item_for("scripts/big.gd", ["huge"])
    stub.reset()
    r, _ = run(tool, "apply", rd2, it3, stub, home)
    prompt = stub.requests[0]["messages"][0]["content"] if stub.requests else ""
    body_lines = [l for l in prompt.split("\n") if l.startswith("func huge") or l.startswith("\tprint") or l.startswith("\treturn")]
    chk("body sent to the model is capped at 80 lines", r[0] == "APPLIED" and len(body_lines) == 80, (r, len(body_lines)))

    # ---------------- rejections: FAIL, file byte-identical, nothing partially written
    long_line = "x" * 120
    bad_replies = {
        "fenced": "```gdscript\nfunc x(): pass\n```",
        "empty": "   \n  ",
        "paragraphs": "First paragraph.\n\nSecond paragraph.",
        "over-100-col": long_line,
        "too-many-lines": "a\nb\nc\nd",
        "looks-like-code": "func take_damage(amount, kind):",
    }
    for label, reply in bad_replies.items():
        rd3 = make_repo({"scripts/mission/fx.gd": FIXTURE})
        p3 = os.path.join(rd3, "scripts/mission/fx.gd")
        stub.reset()
        stub.replies = {"clamp_hp": reply}   # take_damage (processed first) is fine, clamp_hp is bad -> all-or-nothing
        itx, _ = item_for("scripts/mission/fx.gd", ["take_damage", "clamp_hp"])
        r, _ = run(tool, "apply", rd3, itx, stub, home)
        chk("reject %s: FAIL" % label, r[0] == "FAIL", r)
        chk("reject %s: file byte-identical (take_damage's good doc not written either)" % label, open(p3).read() == FIXTURE)
    rd3 = make_repo({"scripts/mission/fx.gd": FIXTURE})
    p3 = os.path.join(rd3, "scripts/mission/fx.gd")
    itx, _ = item_for("scripts/mission/fx.gd", ["take_damage", "no_such_func"])
    stub.reset()
    r, _ = run(tool, "apply", rd3, itx, stub, home)
    chk("a named function that is not in the file: FAIL, byte-identical", r[0] == "FAIL" and open(p3).read() == FIXTURE, r)
    stub.reset()
    stub.status = 500
    itx, _ = item_for("scripts/mission/fx.gd", ["take_damage"])
    r, _ = run(tool, "apply", rd3, itx, stub, home)
    chk("model returns HTTP 500: FAIL, byte-identical", r[0] == "FAIL" and open(p3).read() == FIXTURE, r)
    r, _ = run(tool, "apply", rd3, itx, None, home)
    chk("model unreachable: FAIL, byte-identical", r[0] == "FAIL" and open(p3).read() == FIXTURE, r)
    # quotes/markers are sanitised, not rejected
    stub.reset()
    stub.default = "\"## Returns the hp.\""
    r, _ = run(tool, "apply", rd3, itx, stub, home)
    chk("sanitise: surrounding quotes and a leading ## are stripped (one ## prefix only)", r[0] == "APPLIED" and "\n## Returns the hp.\nfunc take_damage" in open(p3).read(), r)

    # ---------------- banned/untracked are never applied
    stub.reset()
    p4 = os.path.join(rd, "scripts/battle/battle.gd")
    it4, _ = item_for("scripts/battle/battle.gd", ["take_damage"])
    r, _ = run(tool, "apply", rd, it4, stub, home)
    chk("apply on battle.gd: SKIP, no model call, file untouched", r[0] == "SKIP" and open(p4).read() == FIXTURE and not stub.requests, r)

    # ---------------- gdparse
    gh = tempfile.mkdtemp(prefix="docx-gp-")
    os.makedirs(os.path.join(gh, "aider-venv", "bin"))
    gp = os.path.join(gh, "aider-venv", "bin", "gdparse")
    log = os.path.join(gh, "gdparse.log")
    open(gp, "w").write("#!/usr/bin/env bash\necho \"$1\" >> %s\nexit ${GDPARSE_RC:-0}\n" % log)
    os.chmod(gp, 0o755)
    rd5 = make_repo({"scripts/mission/fx.gd": FIXTURE})
    p5 = os.path.join(rd5, "scripts/mission/fx.gd")
    stub.reset()
    itg, _ = item_for("scripts/mission/fx.gd", ["take_damage"])
    r, _ = run(tool, "apply", rd5, itg, stub, gh, {"GDPARSE_RC": "1"})
    chk("gdparse failing: FAIL and the file is restored byte-identical", r[0] == "FAIL" and open(p5).read() == FIXTURE, r)
    chk("gdparse was invoked on the edited file", os.path.exists(log) and p5 in open(log).read(), r)
    r, _ = run(tool, "apply", rd5, itg, stub, gh, {"GDPARSE_RC": "0"})
    chk("gdparse passing: APPLIED", r[0] == "APPLIED", r)

    # ---------------- annotations (reviewer finding): the doc goes ABOVE the @annotation lines, an existing doc above them counts, nothing documented twice
    ANN = ("extends Node\n\n"
           "@warning_ignore(\"unused_parameter\")\n"
           "func annotated(a):\n\tvar x = a\n\tvar y = x\n\tprint(y)\n\tprint(x)\n\treturn y\n\n"
           "## Already documented above its annotations.\n"
           "@rpc(\"any\")\n@warning_ignore(\"unused_parameter\")\n"
           "func documented_annotated(a):\n\tvar x = a\n\tvar y = x\n\tprint(y)\n\tprint(x)\n\treturn y\n\n"
           "@onready var z = 1\n"
           "func after_onready(a):\n\tvar x = a\n\tvar y = x\n\tprint(y)\n\tprint(x)\n\treturn y\n")
    rd7 = make_repo({"scripts/mission/ann.gd": ANN})
    p7 = os.path.join(rd7, "scripts/mission/ann.gd")
    it7, _ = item_for("scripts/mission/ann.gd", ["annotated", "documented_annotated", "after_onready"])
    stub.reset()
    r, _ = run(tool, "apply", rd7, it7, stub, home, {"OVN_DOC_ANNOTATED": "above"})
    L7 = open(p7).read().split("\n")
    i7 = L7.index("func annotated(a):")
    chk("annotated func: APPLIED (annotated + after_onready; the already-documented one is left alone)", r == ["APPLIED", "scripts/mission/ann.gd", "2 docs"], r)
    chk("annotated func: the ## block sits ABOVE the @warning_ignore line, the annotation stays directly above the func",
        L7[i7 - 1] == '@warning_ignore("unused_parameter")' and L7[i7 - 4:i7 - 1] == ["## " + x for x in GOOD.split("\n")], L7[i7 - 5:i7 + 1])
    j7 = L7.index("func documented_annotated(a):")
    chk("documented above its annotations: no second doc, annotations/func untouched",
        L7[j7 - 3] == "## Already documented above its annotations." and L7[j7 - 2] == '@rpc("any")' and L7[j7 - 1] == '@warning_ignore("unused_parameter")', L7[j7 - 4:j7 + 1])
    k7 = L7.index("func after_onready(a):")
    chk("`@onready var` above a func is NOT an annotation of that func: the doc goes directly above the func", L7[k7 - 1].startswith("## ") and L7[k7 - 5].startswith("@onready") is False, L7[k7 - 5:k7 + 1])
    chk("only 2 model calls (annotated, after_onready)", len(stub.requests) == 2, len(stub.requests))
    d7 = subprocess.run(["diff", "-u", "/dev/stdin", p7], input=ANN, capture_output=True, text=True).stdout.split("\n")
    chk("annotation diff: only ## lines added, nothing removed", all(l.lstrip("+").lstrip().startswith("##") for l in d7 if l.startswith("+") and not l.startswith("+++"))
        and not [l for l in d7 if l.startswith("-") and not l.startswith("---")], d7)
    r, _ = run(tool, "apply", rd7, it7, stub, home, {"OVN_DOC_ANNOTATED": "above"})
    chk("annotated: second apply is a SKIP (nothing documented twice)", r[0] == "SKIP", r)
    # default mode while the item VERIFY is the legacy 'directly above the func' form: an undocumented annotated func is left to the model path
    rd8 = make_repo({"scripts/mission/ann.gd": ANN})
    p8 = os.path.join(rd8, "scripts/mission/ann.gd")
    stub.reset()
    names7 = ["annotated", "documented_annotated", "after_onready"]
    itl = it7.replace(W.verify_gd_docs("scripts/mission/ann.gd", names7), LEGACY_VERIFY % ("scripts/mission/ann.gd", names7))
    chk("fixture: the legacy VERIFY text replaced the new one", itl != it7 and "docabove" not in itl and "docabove" in it7)
    r, _ = run(tool, "apply", rd8, itl, stub, home)
    chk("legacy VERIFY + annotated undocumented func: SKIP (no model call, file byte-identical)", r[0] == "SKIP" and "annotation" in r[1] and open(p8).read() == ANN and not stub.requests, r)
    it8 = it7.replace(W.verify_gd_docs("scripts/mission/ann.gd", names7), "`true`")
    r, _ = run(tool, "apply", rd8, it8, stub, home)
    chk("VERIFY text missing/stripped: default mode is SKIP (cannot prove the VERIFY accepts a doc above the annotation), file byte-identical",
        r[0] == "SKIP" and open(p8).read() == ANN and not stub.requests, r)
    r, _ = run(tool, "apply", rd8, it7, stub, home)
    chk("annotation-aware VERIFY (the real verify_gd_docs): default mode places the doc above the annotation",
        r[0] == "APPLIED" and open(p8).read().split("\n")[2].startswith("## "), r)
    chk("...and that VERIFY is green on the result", verify_rc(rd8, W.verify_gd_docs("scripts/mission/ann.gd", names7)) == 0)
    rd8b = make_repo({"scripts/mission/ann.gd": ANN})
    stub.reset()
    r, _ = run(tool, "apply", rd8b, itl, stub, home, {"OVN_DOC_ANNOTATED": "above"})
    chk("OVN_DOC_ANNOTATED=above overrides the legacy-VERIFY skip", r[0] == "APPLIED", r)
    shutil.rmtree(rd8b, ignore_errors=True)

    # ---------------- (reviewer round 2) an annotation line with a trailing comment is still an annotation; a `##` above it is the func's doc, in the executor, in the
    # item VERIFY and in the collector (the three must agree)
    ANN2 = ("extends Node\n\n"
            "@rpc(\"any_peer\", \"call_local\") # net\n"
            "func rp(a):\n\tvar x = a\n\tvar y = x\n\tprint(y)\n\tprint(x)\n\treturn y\n\n"
            "## Documented above a commented annotation.\n"
            "@rpc(\"any\") # net\n"
            "func rp_doc(a):\n\tvar x = a\n\tvar y = x\n\tprint(y)\n\tprint(x)\n\treturn y\n\n"
            "## Separated from its func by a blank line: not directly above.\n\n"
            "func blanky(a):\n\tvar x = a\n\tvar y = x\n\tprint(y)\n\tprint(x)\n\treturn y\n")
    rd9 = make_repo({"scripts/mission/ann2.gd": ANN2})
    p9 = os.path.join(rd9, "scripts/mission/ann2.gd")
    specs9 = list(W.c_gd_docs(rd9))
    chk("collector: a func documented above its (commented) annotation is NOT emitted; the undocumented annotated one and the blank-separated one are",
        len(specs9) == 1 and "`rp`" in specs9[0]["text"] and "`blanky`" in specs9[0]["text"] and "`rp_doc`" not in specs9[0]["text"], [x["text"][-40:] for x in specs9])
    vrc = lambda names: verify_rc(rd9, W.verify_gd_docs("scripts/mission/ann2.gd", names))
    chk("VERIFY: green for the func documented above its commented annotation, red for the undocumented one and for the blank-separated one",
        vrc(["rp_doc"]) == 0 and vrc(["rp"]) == 1 and vrc(["blanky"]) == 1, (vrc(["rp_doc"]), vrc(["rp"]), vrc(["blanky"])))
    it9, _ = item_for("scripts/mission/ann2.gd", ["rp", "rp_doc"])
    stub.reset()
    r, _ = run(tool, "apply", rd9, it9, stub, home)   # default mode: the item carries the annotation-aware VERIFY
    L9 = open(p9).read().split("\n")
    i9 = L9.index("func rp(a):")
    chk("trailing-comment annotation: APPLIED 1 doc (rp_doc already documented above its annotation)", r == ["APPLIED", "scripts/mission/ann2.gd", "1 docs"], r)
    chk("trailing-comment annotation: the ## block sits ABOVE the annotation line, the annotation stays directly above the func",
        L9[i9 - 1].startswith("@rpc(") and L9[i9 - 1].endswith("# net") and L9[i9 - 4:i9 - 1] == ["## " + x for x in GOOD.split("\n")], L9[i9 - 5:i9 + 1])
    chk("trailing-comment annotation: the item's real VERIFY is green after apply", vrc(["rp", "rp_doc"]) == 0)
    chk("collector, same file after apply: only the blank-separated func is still emitted", [("`blanky`" in x["text"]) and ("`rp`" not in x["text"]) for x in W.c_gd_docs(rd9)] == [True])
    shutil.rmtree(rd9, ignore_errors=True)
    for d_ in (rd7, rd8):
        shutil.rmtree(d_, ignore_errors=True)

    # ---------------- the real collector output is accepted end to end
    rd6 = make_repo({"scripts/mission/fx.gd": FIXTURE.replace("\nstatic func clamp_hp", "\nstatic func clamp_hp")})
    specs = [s for s in W.c_gd_docs(rd6)]
    if specs:
        real_item = W.render(specs[0], "xlite")
        stub.reset()
        r, _ = run(tool, "check", rd6, real_item, stub, home)
        chk("real ovn_work_supply item shape: check -> OK", r[0] == "OK", r)
        rcode = verify_rc(rd6, specs[0]["verify"])
        r, _ = run(tool, "apply", rd6, real_item, stub, home)
        chk("real ovn_work_supply item: VERIFY red -> apply -> green", rcode == 1 and r[0] == "APPLIED" and verify_rc(rd6, specs[0]["verify"]) == 0, (rcode, r))
    else:
        chk("collector produced a spec for the fixture", False)
    for d_ in (rd, rd2, rd3, rd5, rd6, gh, home):
        shutil.rmtree(d_, ignore_errors=True)
    return bad


stub = Stub()
bad = battery(TOOL, stub, "real")
ok("real tool passes the whole battery", bad == 0, "failed=%d" % bad)

# ---------------- mutation checks of the tool itself
src = open(TOOL).read()
MUTANTS = [
    ("fence check removed", 'if "```" in t:', "if False:"),
    ("column cap removed", "if len(indent) + len(l) > MAX_LINE:", "if False:"),
    ("paragraph check removed", "if any(not l.strip() for l in raw):", "if False:"),
    ("line-count cap removed", "if len(out) > MAX_DOC_LINES:", "if False:"),
    ("code-looking reply accepted", 'if re.match(r"^(func |var |const |signal |class )", l):', "if False:"),
    ("restore on failure removed", "fh.write(raw)", "fh.write(eol.join(new).encode('utf-8'))"),
    ("blank-line removal removed", 'edits.extend(("drop_blank", k, a) for k in range(j + 1, a))', "pass"),
    ("ban check removed", "if is_banned(f, repo):", "if False:"),
    ("annotation walk removed", "while a > 0 and ANNOT_RE.match(lines[a - 1]):", "while False:"),
    ("trailing-comment annotations not recognised", r'[ \t]*(#[^\n]*)?$")', r'[ \t]*$")'),
    ("stripped/missing VERIFY defaults to above", '("above" if ANNOT_VERIFY_MARK in item else "skip")', '"above"'),
    ("annotation skip-mode removed", 'if annotated == "skip":   # decided', 'if False:   # decided'),
    ("already-documented check removed", 'if j >= 0 and lines[j].lstrip().startswith("##"):', "if False:"),
    ("indentation dropped", "indent = rx.match(lines[i]).group(1)", 'indent = ""'),
    ("max_tokens changed", '"max_tokens": 200', '"max_tokens": 900'),
    ("temperature changed", '"temperature": 0,', '"temperature": 0.7,'),
    ("body cap removed", "return out[:MAX_BODY_LINES]", "return out"),
    ("gdparse result ignored", "if r.returncode != 0:", "if False:"),
    ("kill switch removed", 'if os.environ.get("OVN_DOC_EXECUTOR", "on") == "off":', "if False:"),
]
tmpd = tempfile.mkdtemp(prefix="docx-mut-")
for name, old, new in MUTANTS:
    if src.count(old) != 1:
        ok("mutation '%s' applies (source drifted)" % name, False, "count=%d" % src.count(old))
        continue
    mp = os.path.join(tmpd, "mut.py")
    open(mp, "w").write(src.replace(old, new))
    mb = battery(mp, stub, "mutant")
    ok("mutation '%s' is caught (%d assertion(s) bite)" % (name, mb), mb > 0)
shutil.rmtree(tmpd, ignore_errors=True)

print("ovn_doc_executor: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
