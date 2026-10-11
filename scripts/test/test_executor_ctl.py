#!/usr/bin/env python3
"""scripts/ovn_executor_ctl.py (2026-10-10, package docexec): summary / readiness / enable|disable|reset|status / rehearse for the deterministic doc executor.

Everything runs in a temp OVN_DIR (state/executor_shadow.log, state/executor_mode). `rehearse` uses the REAL ovn_doc_executor.py against a stub LiteLLM and a throwaway git repo,
and must leave the source repo byte-identical. The same battery is then run against MUTATED copies of the tool: every mutant must make it fail."""
import datetime
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import atexit

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPTS = os.path.join(ROOT, "scripts")
TOOL = os.path.join(SCRIPTS, "ovn_executor_ctl.py")
sys.path.insert(0, SCRIPTS)
import ovn_work_supply as W  # noqa: E402

P = F = 0
QUIET = False
_TMPDIRS = []   # every Env's temp OVN_DIR: removed at exit (they leaked one dir per Env, thousands per run, on a nearly full disk)
atexit.register(lambda: [shutil.rmtree(d, ignore_errors=True) for d in _TMPDIRS])


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        if not QUIET:
            print("  ok   " + name)
    else:
        F += 1
        if not QUIET:
            print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


def ts(hours_ago=0):
    return (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours_ago)).strftime("%Y-%m-%dT%H:%M:%SZ")


def row(kind="doc", mode="shadow", verdict="would-apply", h="h1", detail="scripts/a.gd", repo="xlite", hours_ago=0, cycle="20261010-010101"):
    return "\t".join([ts(hours_ago), repo, kind, mode, verdict, h, detail, cycle])


class Env:
    def __init__(self, rows=(), mode_text=None):
        self.d = tempfile.mkdtemp(prefix="ctl-")
        _TMPDIRS.append(self.d)
        os.makedirs(os.path.join(self.d, "state"))
        self.log = os.path.join(self.d, "state", "executor_shadow.log")
        self.mf = os.path.join(self.d, "state", "executor_mode")
        if rows:
            open(self.log, "w").write("\n".join(rows) + "\n")
        if mode_text is not None:
            open(self.mf, "w").write(mode_text)

    def run(self, tool, *args, env=None, timeout=300):
        e = dict(os.environ)
        for k in ("OVN_DOC_EXECUTOR", "OVN_RUFF_EXECUTOR", "OVN_EXECUTOR_LOG", "OVN_EXEC_READY_MIN_ITEMS", "OVN_EXEC_READY_MIN_REHEARSALS", "OVN_EXEC_READY_MIN_RATE"):
            e.pop(k, None)
        e["OVN_DIR"] = self.d
        e["HOME"] = self.d
        e.update(env or {})
        r = subprocess.run([sys.executable, tool] + list(args), capture_output=True, text=True, env=e, timeout=timeout)
        return r.returncode, r.stdout, r.stderr

    def mode_lines(self):
        try:
            return [l for l in open(self.mf).read().split("\n") if l.strip() and not l.startswith("#")]
        except OSError:
            return None


GOOD = "Applies damage to the unit.\nArgs: amount and kind.\nReturns the remaining hp."


class Stub:
    def __init__(self):
        self.reply = GOOD
        self.n = 0
        outer = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_POST(self):
                self.rfile.read(int(self.headers.get("Content-Length", "0")))
                outer.n += 1
                out = json.dumps({"choices": [{"message": {"content": outer.reply}}], "usage": {}}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

        self.srv = http.server.HTTPServer(("127.0.0.1", 0), H)
        self.url = "http://127.0.0.1:%d" % self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()


def git(d, *a):
    return subprocess.run(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t"] + list(a), capture_output=True, text=True, check=True).stdout.strip()


FIXTURE = ("extends Node\n\nfunc take_damage(amount, kind):\n\tvar x = amount * 2\n\thp -= x\n\tif hp < 0:\n\t\thp = 0\n\treturn hp\n\n"
           "func heal(amount):\n\tvar a = amount\n\tvar b = a * 2\n\tvar c = b + 1\n\tprint(c)\n\treturn c\n")
TEXT_T = ("Add a `##` doc-comment (one to three lines: what it does, key arguments, return value) on the line directly above each of these GDScript functions: %s. "
          "Comments only - change no code, no signatures.")


def item_for(path, names, parked=False, verify=None):
    spec = {"kind": "gd-missing-doc", "file": path, "tier": "T2", "cat": "godot", "text": TEXT_T % ", ".join("`%s`" % n for n in names), "verify": verify or W.verify_gd_docs(path, names)}
    line = W.render(spec, "xlite")
    if parked:
        line = line.replace("- [ ] ", "- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] ", 1)
    return line


def mk_source_repo(parent, items=None, name="xlite"):
    """a throwaway 'xlite' checkout: two gd files with undocumented funcs, a parked gap (take_damage) and a fresh one (heal)"""
    d = os.path.join(parent, name)
    os.makedirs(os.path.join(d, "scripts"))
    git(d, "init", "-q", ".")
    open(os.path.join(d, "scripts", "a.gd"), "w").write(FIXTURE)
    open(os.path.join(d, "scripts", "b.gd"), "w").write(FIXTURE)
    items = items or [item_for("scripts/a.gd", ["take_damage"], parked=True), item_for("scripts/b.gd", ["heal"])]
    open(os.path.join(d, "OVERNIGHT_PROGRESS.md"), "w").write("## Next Steps\n%s\n" % "\n".join(items))
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "base")
    return d


def tree_digest(d):
    import hashlib
    h = hashlib.md5()
    h.update(subprocess.run(["git", "-C", d, "status", "--porcelain", "--ignored"], capture_output=True, text=True).stdout.encode())
    h.update(git(d, "rev-parse", "HEAD").encode())
    for f in ("scripts/a.gd", "scripts/b.gd", "OVERNIGHT_PROGRESS.md"):
        h.update(open(os.path.join(d, f), "rb").read())
    return h.hexdigest()


def reh_rows(e):
    """rehearsal verdict rows only (rehearse also logs the check verdict row for every item it looks at)"""
    if not os.path.exists(e.log):
        return []
    return [l.split("\t") for l in open(e.log).read().strip().split("\n") if l.split("\t")[4].startswith("rehearsal-")]


def all_rows(e):
    return [l.split("\t") for l in open(e.log).read().strip().split("\n")] if os.path.exists(e.log) else []


STUB = Stub()


def battery(tool, tag):
    global F
    f0 = F
    # ---- item_hash parity with lib_item_select.sh ovn_item_hash
    texts = ["- [ ] [T2] scripts/a.gd — plain item without a feat tag", "- [x] [T2] x [feat:xlite-20261009-supply-gd-missing-doc-a]", "- [ ] [T1] y [feat:repo-261009-thing] more",
             "[T1] bare text no checkbox [feat:r-20261009-20261010-z]", "- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] p [feat:xlite-20261009-supply-gd-missing-doc-q]"]
    src_lib = os.path.join(SCRIPTS, "lib_item_select.sh")
    bad = []
    for t in texts:
        want = subprocess.run(["bash", "-c", '. "$1"; ovn_item_hash "$2"', "x", src_lib, t], capture_output=True, text=True).stdout.strip()
        got = subprocess.run([sys.executable, "-c", "import sys,runpy; m=runpy.run_path(sys.argv[1], run_name='ctl'); print(m['item_hash'](sys.argv[2]))", tool, t], capture_output=True, text=True,
                             cwd=os.path.dirname(tool)).stdout.strip()
        if want != got:
            bad.append((t, want, got))
    ok("%s: item_hash is identical to lib_item_select.sh ovn_item_hash for 5 shapes (checkbox, feat tag with 8/6-digit date, none, parked prefix)" % tag, not bad, bad)

    # ---- summary
    rows = [row(h="a", verdict="would-apply"), row(h="b", verdict="would-apply"), row(h="b", verdict="would-apply"), row(h="c", verdict="skip", detail="carries annotations `x`"),
            row(h="d", verdict="skip", detail="carries annotations `y`"), row(h="e", mode="on", verdict="applied"), row(h="f", mode="on", verdict="fail", detail="verification=fail"),
            row(h="g", mode="rehearsal", verdict="rehearsal-pass"), row(h="i", mode="rehearsal", verdict="rehearsal-fail", detail="post-check orphan"),
            row(kind="doc-postcheck", mode="shadow", verdict="flag", h="j", detail="no-net-doc,orphan: x.gd: ..."), row(kind="doc-postcheck", mode="shadow", verdict="ok", h="k"),
            row(verdict="parked-idle", h="-", detail="19 parked gd-missing-doc gap(s) idle; ..."), row(verdict="no-candidate", h="-"),
            row(h="z", verdict="would-apply", hours_ago=100), row(h="y", verdict="skip", repo="billwatch")]
    e = Env(rows)
    rc, out, _ = e.run(tool, "summary", "--json")
    j = json.loads(out) if out.strip().startswith("{") else {}
    ok("%s: summary --json: distinct shadow items 6 (a,b,c,d,z + billwatch y), would-apply 3 (a,b,z) => 50%%" % tag, j.get("shadow_items") == 6 and j.get("would_apply_items") == 3 and abs(j.get("would_apply_rate", 0) - 0.5) < 1e-9, j)
    ok("%s: summary: on mode 2 tried / 1 applied; rehearsal pass 1 fail 1; post-check ok 1 flag 1 (codes no-net-doc, orphan); parked-idle 1; no-candidate 1" % tag,
       j.get("on_items") == 2 and j.get("applied_items") == 1 and j.get("rehearsal_pass") == 1 and j.get("rehearsal_fail") == 1 and j.get("postcheck_ok") == 1 and j.get("postcheck_flag") == 1
       and dict(j.get("postcheck_codes", [])) == {"no-net-doc": 1, "orphan": 1} and j.get("parked_idle_rows") == 1 and j.get("no_candidate") == 1, j)
    ok("%s: skip reasons are bucketed (the backticked names collapse: 'carries annotations X' x2)" % tag, j.get("skip_reasons") and j["skip_reasons"][0][1] >= 2 and "carries annotations X" in j["skip_reasons"][0][0], j.get("skip_reasons"))
    rc, out, _ = e.run(tool, "summary", "--json", "--hours", "24")
    j24 = json.loads(out)
    ok("%s: --hours 24 drops the 100h-old row (5 shadow items, would-apply 2)" % tag, j24.get("shadow_items") == 5 and j24.get("would_apply_items") == 2, j24)
    rc, out, _ = e.run(tool, "summary", "--json", "--repo", "billwatch")
    jb = json.loads(out)
    ok("%s: --repo billwatch sees only its row (1 item, would-apply 0)" % tag, jb.get("shadow_items") == 1 and jb.get("would_apply_items") == 0, jb)
    rc, out, _ = e.run(tool, "summary")
    ok("%s: the text summary names the log, the would-apply rate and the idle breadcrumb" % tag, rc == 0 and "would-apply 3 (50%)" in out and "parked-idle rows 1" in out and "executor_shadow.log" in out, out)
    rc, out, _ = Env().run(tool, "summary")
    ok("%s: an empty/missing log summarises to zeros without crashing (n/a rate)" % tag, rc == 0 and "0 rows" in out and "n/a" in out, out)

    # ---- round 3: the would-apply share counts only doc-gap verdicts
    # every ongoing-* cycle offers the hook the top open item of ANY kind; old logs carry one 'not a gd-missing-doc supply item' skip row per non-doc item: they must not dilute the share
    mixed = [row(h="d%d" % i) for i in range(10)] + [row(h="n%d" % i, verdict="skip", detail="not a gd-missing-doc supply item") for i in range(60)] + [row(h="x1", verdict="skip", detail="target not tracked")]
    em = Env(mixed + [row(h="e1", verdict="check-empty", detail="check printed nothing (timeout or crash)")])
    rc, out, _ = em.run(tool, "summary", "--json")
    jm = json.loads(out)
    ok("%s: non-doc 'not a gd-missing-doc supply item' skips are not counted: 11 conclusive items, 10 would-apply (91%%), the skip reasons carry only the real one" % tag,
       jm.get("shadow_items") == 11 and jm.get("would_apply_items") == 10 and abs(jm.get("would_apply_rate", 0) - 10 / 11.0) < 1e-9 and [r[0] for r in jm.get("skip_reasons", [])] == ["target not tracked"], jm)
    ok("%s: a 'check-empty' row (inconclusive check) is counted separately and is neither would-apply nor skip" % tag, jm.get("check_empty") == 1 and jm.get("shadow_rows") == 11, jm)
    rc, out, _ = em.run(tool, "readiness", "--check", env={"OVN_EXEC_READY_MIN_REHEARSALS": "0"})
    ok("%s: the readiness would-apply gate sees 91%% (>= 80%%) on a mixed lane, not 14%%" % tag, "[ok] would-apply share" in out and "(91%)" in out, out)
    rc, out, _ = em.run(tool, "summary")
    ok("%s: the text summary mentions the inconclusive check row" % tag, "1 inconclusive `check` row" in out, out)

    # ---- readiness
    rc, out, _ = Env().run(tool, "readiness", "--check")
    ok("%s: readiness with no evidence => READY: no, exit 3 with --check, exit 0 without" % tag, rc == 3 and "READY: no" in out and Env().run(tool, "readiness")[0] == 0, (rc, out))
    good_rows = [row(h="w%d" % i) for i in range(5)] + [row(h="r%d" % i, mode="rehearsal", verdict="rehearsal-pass") for i in range(3)]
    e2 = Env(good_rows)
    rc, out, _ = e2.run(tool, "readiness", "--check")
    ok("%s: 5 would-apply items + 3 passing rehearsals => READY: yes, exit 0" % tag, rc == 0 and "READY: yes" in out, (rc, out))
    e2b = Env([row(h="w%d" % i, mode="rehearsal") for i in range(5)] + [row(h="r%d" % i, mode="rehearsal", verdict="rehearsal-pass") for i in range(3)])
    rc, out, _ = e2b.run(tool, "readiness", "--check")
    ok("%s: check evidence may come from rehearsals alone (a lane with only parked gaps produces no shadow rows): 5 + 3 passes => READY" % tag, rc == 0 and "READY: yes" in out, (rc, out))
    e3 = Env([row(h="w%d" % i) for i in range(5)])
    rc, out, _ = e3.run(tool, "readiness", "--check")
    ok("%s: shadow evidence but NO rehearsal (the apply step is unproven) => not ready" % tag, rc == 3 and "[NO] rehearsals" in out, (rc, out))
    e4 = Env([row(h="w%d" % i, verdict="would-apply" if i < 3 else "skip") for i in range(6)] + [row(h="r%d" % i, mode="rehearsal", verdict="rehearsal-pass") for i in range(3)])
    rc, out, _ = e4.run(tool, "readiness", "--check")
    ok("%s: would-apply share 50%% (< 80%%) => not ready even with rehearsals" % tag, rc == 3 and "[NO] would-apply share" in out, (rc, out))
    e5 = Env([row(h="w%d" % i) for i in range(5)] + [row(h="r%d" % i, mode="rehearsal", verdict="rehearsal-pass" if i < 2 else "rehearsal-fail") for i in range(4)])
    rc, out, _ = e5.run(tool, "readiness", "--check")
    ok("%s: rehearsal pass share 50%% => not ready" % tag, rc == 3, (rc, out))
    rc, out, _ = e3.run(tool, "readiness", "--check", env={"OVN_EXEC_READY_MIN_REHEARSALS": "0"})
    ok("%s: thresholds are env-tunable (MIN_REHEARSALS=0 still needs a rate: no rehearsal rate => not ready)" % tag, rc == 3, (rc, out))
    # ---- enable / disable / reset / status
    e = Env(mode_text="# keep me\ndoc:billwatch=off\n")
    rc, out, err = e.run(tool, "enable", "doc")
    ok("%s: enable without --repo/--all refuses to guess the scope (nonzero, nothing written)" % tag, rc != 0 and e.mode_lines() == ["doc:billwatch=off"], (rc, out, err))
    rc, out, err = e.run(tool, "enable", "doc", "--repo", "xlite")
    ok("%s: enable doc --repo xlite writes 'doc:xlite=on', keeps the other line and the comment, prints the readiness report and a WARNING when not READY" % tag,
       rc == 0 and e.mode_lines() == ["doc:billwatch=off", "doc:xlite=on"] and "# keep me" in open(e.mf).read() and "READY: no" in out and "WARNING" in out and "effective for xlite now: on" in out, (rc, out, e.mode_lines()))
    rc, out, _ = e.run(tool, "enable", "doc", "--repo", "xlite")
    ok("%s: enable twice does not duplicate the line" % tag, e.mode_lines().count("doc:xlite=on") == 1, e.mode_lines())
    # the file is what the bash hook reads: identical answer
    sh = subprocess.run(["bash", "-c", '. "$1/lib_item_select.sh"; . "$1/lib_fixup.sh"; ovn_executor_mode doc "$2" "$3"', "x", SCRIPTS, e.d, os.path.join(e.d, "xlite")], capture_output=True, text=True,
                        env={k: v for k, v in os.environ.items() if k != "OVN_DOC_EXECUTOR"}).stdout
    ok("%s: the bash hook's ovn_executor_mode reads exactly that file: xlite => on" % tag, sh == "on", sh)
    rc, out, _ = e.run(tool, "disable", "doc", "--repo", "xlite")
    ok("%s: disable => shadow (the safe default), not off" % tag, "doc:xlite=shadow" in e.mode_lines() and "doc:xlite=on" not in e.mode_lines(), e.mode_lines())
    rc, out, _ = e.run(tool, "disable", "doc", "--repo", "xlite", "--off")
    ok("%s: disable --off => off" % tag, "doc:xlite=off" in e.mode_lines(), e.mode_lines())
    rc, out, _ = e.run(tool, "reset", "doc", "--repo", "xlite")
    ok("%s: reset drops the line (the other repo's line stays)" % tag, e.mode_lines() == ["doc:billwatch=off"], e.mode_lines())
    rc, out, _ = e.run(tool, "enable", "doc", "--all")
    ok("%s: --all writes the repo-less line 'doc=on'" % tag, "doc=on" in e.mode_lines(), e.mode_lines())
    rc, out, _ = e.run(tool, "enable", "ruff", "--repo", "xlite")
    ok("%s: ruff is a separate kind (ruff:xlite=on, no readiness gate for it)" % tag, rc == 0 and "ruff:xlite=on" in e.mode_lines(), (rc, out))
    rc, out, _ = e.run(tool, "enable", "docs", "--repo", "x")
    ok("%s: an unknown kind is refused" % tag, rc != 0, (rc, out))
    e = Env(good_rows)
    rc, out, _ = e.run(tool, "enable", "doc", "--repo", "xlite", "--require-ready")
    ok("%s: READY evidence + --require-ready: enabled, no WARNING" % tag, rc == 0 and e.mode_lines() == ["doc:xlite=on"] and "WARNING" not in out, (rc, out))
    e = Env()
    rc, out, _ = e.run(tool, "enable", "doc", "--repo", "xlite", "--require-ready")
    ok("%s: no evidence + --require-ready: refused (exit 3), nothing written" % tag, rc == 3 and not e.mode_lines() and "refused" in out, (rc, out, e.mode_lines()))
    rc, out, _ = e.run(tool, "enable", "doc", "--repo", "xlite", env={"OVN_DOC_EXECUTOR": "shadow"})
    ok("%s: an env override in the invoking shell is called out (NOTE ... overrides the file)" % tag, "NOTE: OVN_DOC_EXECUTOR=shadow" in out and "effective for xlite now: shadow" in out, out)
    rc, out, _ = e.run(tool, "status", "--repo", "xlite")
    ok("%s: status lists the file lines and the effective mode per kind" % tag, rc == 0 and "doc:xlite=on" in out and "doc: effective on" in out and "ruff: effective shadow" in out, out)

    # ---- round 3: mode precedence is visible: effective mode + source, and a warning when OVN_DOC_EXECUTOR (env) contradicts state/executor_mode
    e = Env(mode_text="doc:xlite=on\n")
    rc, out, _ = e.run(tool, "status", "--repo", "xlite", env={"OVN_DOC_EXECUTOR": "shadow"})
    ok("%s: status with the env var contradicting the file: effective shadow, source named, WARNING that the file line has no effect" % tag,
       "doc: effective shadow  [source: env OVN_DOC_EXECUTOR=shadow]" in out and "WARNING: OVN_DOC_EXECUTOR=shadow overrides state file line doc:xlite=on" in out and "NO effect" in out, out)
    rc, out, _ = e.run(tool, "status", "--repo", "xlite")
    ok("%s: status without env: source is the state-file line, no WARNING" % tag, "doc: effective on  [source: state file line doc:xlite=on]" in out and "WARNING" not in out, out)
    rc, out, _ = e.run(tool, "status", "--repo", "xlite", env={"OVN_DOC_EXECUTOR": "on"})
    ok("%s: env agreeing with the file: source env, no WARNING (no conflict)" % tag, "doc: effective on  [source: env OVN_DOC_EXECUTOR=on]" in out and "WARNING" not in out, out)
    rc, out, _ = Env().run(tool, "status", "--repo", "xlite")
    ok("%s: nothing set: source is the default (shadow)" % tag, "doc: effective shadow  [source: default" in out and "ruff: effective shadow  [source: default" in out, out)
    rc, out, _ = e.run(tool, "status", "--repo", "xlite", env={"OVN_DOC_EXECUTOR": "bogus"})
    ok("%s: an invalid env value is named as such (treated as shadow, never enables) and conflicts with the file's 'on'" % tag, "effective shadow  [source: env OVN_DOC_EXECUTOR=bogus (invalid value: treated as shadow)]" in out and "WARNING" in out, out)
    e = Env(mode_text="doc:xlite=on\ndoc:billwatch=off\ndoc=shadow\n")
    rc, out, _ = e.run(tool, "status", env={"OVN_DOC_EXECUTOR": "on"})
    warns = [l for l in out.split("\n") if "WARNING" in l]
    ok("%s: status without --repo shows the '*' scope and every repo named in the file, each with its own source; WARNING only for the two that contradict env=on (doc=shadow, doc:billwatch=off), not doc:xlite=on" % tag,
       "doc: effective on  [source: env OVN_DOC_EXECUTOR=on]" in out and "doc (xlite): effective on" in out and "doc (billwatch): effective on" in out and len(warns) == 2
       and any("line doc:billwatch=off" in l for l in warns) and any("line doc=shadow" in l for l in warns) and not any("doc:xlite" in l for l in warns), out)
    rc, out, _ = Env(mode_text="doc:xlite=on\n").run(tool, "enable", "doc", "--repo", "xlite", env={"OVN_DOC_EXECUTOR": "shadow"})
    ok("%s: enable under a contradicting env var warns that the file change will not take effect (and still reports the effective mode + source)" % tag,
       "WARNING: OVN_DOC_EXECUTOR=shadow overrides" in out and "effective for xlite now: shadow  [source: env OVN_DOC_EXECUTOR=shadow]" in out, out)
    rc, out, _ = Env(mode_text="doc:xlite=on\n").run(tool, "disable", "doc", "--repo", "xlite", env={"OVN_DOC_EXECUTOR": "on"})
    ok("%s: disable (no readiness report involved) under a contradicting env var warns too: the shadow line is not what runs" % tag,
       "WARNING: OVN_DOC_EXECUTOR=on overrides state file line doc:xlite=shadow" in out and "effective for xlite now: on  [source: env OVN_DOC_EXECUTOR=on]" in out, out)
    rc, out, _ = Env().run(tool, "enable", "doc", "--repo", "xlite")
    ok("%s: enable without env: reports source 'state file line doc:xlite=on' and no WARNING" % tag, "[source: state file line doc:xlite=on]" in out and "WARNING: OVN_DOC_EXECUTOR" not in out, out)
    rc, out, _ = Env(mode_text="doc:xlite=on\n").run(tool, "readiness", "--repo", "xlite", env={"OVN_DOC_EXECUTOR": "shadow"})
    ok("%s: readiness info names the source and warns on the conflict too" % tag, "effective doc mode for xlite: shadow  [source: env OVN_DOC_EXECUTOR=shadow]" in out and "WARNING: OVN_DOC_EXECUTOR=shadow overrides" in out, out)

    # ---- rehearse (real doc executor, stub LiteLLM, throwaway repo)
    tmp = tempfile.mkdtemp(prefix="reh-")
    src = mk_source_repo(tmp)
    before = tree_digest(src)
    e = Env()
    env = {"LITELLM_BASE": STUB.url}
    STUB.reply, STUB.n = GOOD, 0
    rc, out, err = e.run(tool, "rehearse", src, "--max", "2", env=env)
    rows_ = reh_rows(e)
    ok("%s: rehearse: both open gaps (the parked one included) pass: apply + the item's own VERIFY + the post-check => 2 rehearsal-pass rows" % tag,
       rc == 0 and len(rows_) == 2 and all(r[4] == "rehearsal-pass" and r[3] == "rehearsal" and r[2] == "doc" and r[1] == "xlite" for r in rows_), (rc, out[-400:], err[-300:], rows_))
    ok("%s: rehearse never touches the source repo (HEAD, tree and ignored files byte-identical) and removes its temp clone" % tag, tree_digest(src) == before and not [x for x in os.listdir(tempfile.gettempdir()) if x.startswith("ovn-rehearse-") and os.path.exists(os.path.join(tempfile.gettempdir(), x, "xlite"))], "")
    rc, out, _ = e.run(tool, "summary", "--json")
    jr = json.loads(out)
    ok("%s: the rehearsal count is the number of rehearsals (2), not 2 + their per-item check rows; those check rows feed the would-apply share (2 of 2)" % tag,
       jr.get("rehearsals") == 2 and jr.get("rehearsal_pass") == 2 and jr.get("shadow_items") == 2 and jr.get("would_apply_items") == 2, jr)
    rc, out, _ = e.run(tool, "rehearse", src, "--max", "1", env=env)
    ok("%s: --max 1 rehearses one item (3 rehearsal rows in total)" % tag, len(reh_rows(e)) == 3, out)
    ar = all_rows(e)
    ok("%s: rehearse also logs the executor's check verdict per item it looked at (mode rehearsal, verdict would-apply) - the evidence a parked-only lane never produces in shadow" % tag,
       sum(1 for r in ar if r[3] == "rehearsal" and r[4] == "would-apply") == 3, ar)
    rc, out, _ = e.run(tool, "readiness", "--repo", "xlite", "--repo-dir", src)
    ok("%s: readiness --repo-dir reports the open gaps (2, 1 parked) and the orphan/duplicate baseline" % tag, "open gd-missing-doc items" in out and ": 2 (1 parked" in out and "orphans=0 dups=0" in out, out)
    e = Env()
    STUB.reply = "```\nfunc x\n```"
    rc, out, _ = e.run(tool, "rehearse", src, "--max", "1", env=env)
    rows_ = reh_rows(e)
    ok("%s: a rejected model reply (code fence) => rehearsal-fail with the executor's reason, source untouched" % tag, len(rows_) == 1 and rows_[0][4] == "rehearsal-fail" and "code fence" in rows_[0][6] and tree_digest(src) == before, (out, rows_))
    STUB.reply = GOOD
    e = Env()
    rc, out, _ = e.run(tool, "rehearse", src, "--max", "1", env={"LITELLM_BASE": "http://127.0.0.1:9"})
    rows_ = reh_rows(e)
    ok("%s: model unreachable => rehearsal-fail 'model call failed' (and still no change to the source)" % tag, len(rows_) == 1 and rows_[0][4] == "rehearsal-fail" and "model call failed" in rows_[0][6] and tree_digest(src) == before, (out, rows_))
    # an item the executor refuses is evidence too: it lowers the would-apply share instead of being silently skipped
    t4 = tempfile.mkdtemp(prefix="reh4-")
    src4 = mk_source_repo(t4, [item_for("scripts/ghost.gd", ["nothing"]), item_for("scripts/b.gd", ["heal"])], name="vy")
    e = Env()
    rc, out, _ = e.run(tool, "rehearse", src4, "--max", "1", env=env)
    ar = all_rows(e)
    sk = [r for r in ar if r[3] == "rehearsal" and r[4] == "skip"]
    rc2, out2, _ = e.run(tool, "summary", "--json")
    j4 = json.loads(out2)
    ok("%s: an item the executor's check refuses (untracked target) is logged as a rehearsal 'skip' row and the next item is rehearsed; would-apply share 1/2" % tag,
       len(sk) == 1 and "not tracked" in sk[0][6] and len(reh_rows(e)) == 1 and j4.get("shadow_items") == 2 and abs(j4.get("would_apply_rate", 0) - 0.5) < 1e-9, (ar, j4))
    shutil.rmtree(t4, ignore_errors=True)
    # apply succeeds but the item's OWN verify is red => the rehearsal must fail on it
    t2 = tempfile.mkdtemp(prefix="reh2-")
    src2 = mk_source_repo(t2, [item_for("scripts/a.gd", ["take_damage"], verify='python3 -c "import sys;sys.exit(1)"')], name="vx")
    e = Env()
    rc, out, _ = e.run(tool, "rehearse", src2, "--max", "1", env=env)
    rows_ = reh_rows(e)
    ok("%s: apply fine but the item's own VERIFY is red => rehearsal-fail 'own VERIFY did not pass'" % tag, len(rows_) == 1 and rows_[0][4] == "rehearsal-fail" and "own VERIFY did not pass" in rows_[0][6], (out, rows_))
    # apply + VERIFY fine but the post-check flags the result (the model repeats a line => duplicated ## text)
    t3 = tempfile.mkdtemp(prefix="reh3-")
    src3 = mk_source_repo(t3)
    STUB.reply = "Repeated line here.\nRepeated line here."
    e = Env()
    rc, out, _ = e.run(tool, "rehearse", src3, "--max", "1", env=env)
    rows_ = reh_rows(e)
    ok("%s: apply + VERIFY fine but the post-check flags a repeated line => rehearsal-fail 'post-check duplicate'" % tag, len(rows_) == 1 and rows_[0][4] == "rehearsal-fail" and "post-check duplicate" in rows_[0][6], (out, rows_))
    STUB.reply = GOOD
    shutil.rmtree(t2, ignore_errors=True)
    shutil.rmtree(t3, ignore_errors=True)
    rc, out, _ = e.run(tool, "rehearse", os.path.join(tmp, "nope"), env=env)
    ok("%s: rehearse on a non-checkout is refused" % tag, rc != 0, (rc, out))
    shutil.rmtree(tmp, ignore_errors=True)
    return F - f0


real_fail = battery(TOOL, "real")
ok("real tool passes the whole battery", real_fail == 0, "failed=%d" % real_fail)

src_text = open(TOOL).read()
MUTANTS = [
    ("readiness would-apply share not enforced", 's["would_apply_rate"] is not None and s["would_apply_rate"] >= MIN_RATE', "True"),
    ("readiness rehearsal evidence not enforced", 's["rehearsals"] >= MIN_REHEARSALS and s["rehearsal_rate"] is not None and s["rehearsal_rate"] >= MIN_RATE', "True"),
    ("enable guesses the scope", 'if not a.repo and not a.all:\n        sys.exit("refusing to guess the scope: pass --repo <name> (e.g. xlite) or --all")', "pass"),
    ("--require-ready ignored", 'if not ready and getattr(a, "require_ready", False):', "if False:"),
    ("enable duplicates lines", "kept = [l for l in lines if re.sub(r\"\\s\", \"\", l).partition(\"=\")[0] != key or l.lstrip().startswith(\"#\")]", "kept = list(lines)"),
    ("disable writes off instead of shadow", 'return cmd_set(a, "off" if a.off else "shadow")', 'return cmd_set(a, "off")'),
    ("item_hash keeps the date stamp", 'k = re.sub(r"-[0-9]{8}-", "-", k, count=1)', "pass"),
    ("--hours filter ignored", "if cutoff and ts < cutoff:", "if False:"),
    ("--repo filter ignored", "if repo and r[\"repo\"] != repo:", "if False:"),
    ("rehearse skips the item's own VERIFY", 'if v.returncode != 0:', "if False:"),
    ("rehearse skips the post-check", 'if res[0] == "OK":', "if True:"),
    ("env override ignored in resolve_mode", 'ev = (env.get(ENV_VAR.get(kind, ""), "") or "").strip()', 'ev = ""'),
    ("non-doc skips dilute the would-apply share", 'return not (r["verdict"] == "skip" and r["detail"].startswith(NOT_DOC_ITEM))', "return True"),
    ("mode conflict never flagged", '"conflict": bool(ev and fmode and mode != fmode)}', '"conflict": False}'),
    ("enable does not warn on conflict", '    w = conflict_warning(a.kind, repo or "*")\n    if w:\n        print(w)\n    return 0', "    return 0"),
    ("status hides the source", 'print("%s%s: effective %s  [source: %s]" % (k, (" (%s)" % sc) if sc != "*" and not a.repo else "", i["mode"], i["source"]))', 'print("%s%s: effective %s" % (k, (" (%s)" % sc) if sc != "*" and not a.repo else "", i["mode"]))'),
    ("status ignores repos named in the file", 'scopes = [a.repo] if a.repo else ["*"] + sorted({key.split(":", 1)[1] for key in f if key.startswith(k + ":")})', 'scopes = [a.repo] if a.repo else ["*"]'),
]
tmpd = tempfile.mkdtemp(prefix="ctl-mut-")
for name, old, new in MUTANTS:
    if src_text.count(old) != 1:
        ok("mutation '%s' applies (source drifted)" % name, False, "count=%d" % src_text.count(old))
        continue
    mdir = os.path.join(tmpd, "m")
    shutil.rmtree(mdir, ignore_errors=True)
    os.makedirs(mdir)
    for f_ in ("ovn_doc_executor.py", "ovn_doc_postcheck.py", "ovn_work_supply.py"):
        shutil.copy(os.path.join(SCRIPTS, f_), mdir)
    mp = os.path.join(mdir, "ovn_executor_ctl.py")
    open(mp, "w").write(src_text.replace(old, new))
    p_, f_ = P, F
    QUIET = True
    bad = battery(mp, "mutant")
    QUIET = False
    F = f_
    P = p_
    ok("mutation '%s' is caught (%d assertion(s) bite)" % (name, bad), bad > 0)
shutil.rmtree(tmpd, ignore_errors=True)
print("executor_ctl: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
