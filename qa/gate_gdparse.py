#!/usr/bin/env python3
"""gate_gdparse.py - GATE gdparse (S5 companion, analysis F12 2026-10-10): the GDScript cells the scanner gate never had.

    python3 qa/gate_gdparse.py check --repo <name|path> --base <ref> --head <ref> [--no-record] [--enforce-exit] [--timeout S]

Why: gate_scanners has no GDScript tool, so xlite (the highest-escape repo: 11.8 strong / 35.3 any per 100) read 'scanners PASS' while effectively
only gitleaks ran. And GUT SILENTLY SKIPS a test script it cannot parse and still exits green ('gut-skips:xlite' alerts), so a parse error in a
tests/*.gd means tests that are not running. Two cells, both over the net diff merge-base(base,head)..head (never a live clone or a checkout:
blobs come out of `git archive`, nothing is executed, gdtoolkit only PARSES text):

  gdparse  every changed/added *.gd (vendored `addons/` and `.godot/` excluded, counted in details.skipped) is parsed with gdtoolkit.
           A parse error is a finding. Verdict: FLAG while the gate's mode is shadow (the shipped default), FAIL once enforced
           (`qa_enforce.sh gdparse enforce`); details.would_be_verdict always says FAIL. details.parse_errors lists file, line, short message and
           whether the file ALREADY failed at the merge-base ("preexisting") or is new damage. A changed file that is still unparseable counts either way
           (the author touched it and left GUT skipping it).
  gdlint   ADVISORY, baseline-relative: gdtoolkit's default lint rules over the same files at head and at the merge-base (rename-aware); only findings
           in EXCESS of the base count per (file, rule, description-with-digits-masked) are 'new'. Never changes the verdict (PASS stays PASS);
           details.gdlint carries the counts and the first 40 new findings. gdlint `# gdlint: ignore` comments are honoured by the tool (advisory cell).

Verdicts: NA (gate off / no changed .gd / only vendored .gd / gdtoolkit not installed while SHADOW), UNVERIFIED (gdtoolkit not installed while ENFORCED, or crashed, git failed, a changed .gd could not be read or is too
large: never PASS), FLAG|FAIL (parse errors), PASS (all changed .gd parsed clean). Exit 0 always except --enforce-exit in enforce mode on FAIL.
gdtoolkit is found through, in order: $QA_GDTOOLKIT_PYTHON (a python that can `import gdtoolkit`), the python beside the `gdparse` binary
($QA_TOOL_GDPARSE > ~/qa-venv/bin > ~/qa-tools/bin > PATH), the running interpreter. Install on the box (NOT done by this change):
`~/qa-venv/bin/pip install gdtoolkit` (4.5.0 verified on python3.12). Helper: qa/gdtoolkit_run.py (stdlib+gdtoolkit only)."""
import json
import os
import re
import shutil
import sys
import tempfile
import time
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "gdparse"
HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "gdtoolkit_run.py")
MAX_BYTES = 1000000
MAX_FILES = int(os.environ.get("QA_GDPARSE_MAX_FILES", "1500"))
EXCLUDE_DIRS = {"addons", ".godot", "node_modules", ".git"}
MAX_LIST = 40


# ------------------------------------------------------------------------------------------------ tool discovery
def find_tool(name):
    """env QA_TOOL_<NAME> > ~/qa-venv/bin > ~/qa-tools/bin > PATH. None when missing (same order as gate_scanners)."""
    ov = os.environ.get("QA_TOOL_" + name.upper().replace("-", "_"))
    if ov:
        return ov if os.path.exists(ov) else None
    for d in (os.path.expanduser("~/qa-venv/bin"), os.path.expanduser("~/qa-tools/bin")):
        p = os.path.join(d, name)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return shutil.which(name)


def _py_has_gdtoolkit(py):
    rc, _, _ = qc.run([py, "-I", "-c", "import gdtoolkit, lark"], timeout=30, polite=False)
    return rc == 0


def find_python():
    """A python able to import gdtoolkit, or None."""
    ov = os.environ.get("QA_GDTOOLKIT_PYTHON")
    if ov:
        return ov if os.path.exists(ov) and _py_has_gdtoolkit(ov) else None
    gp = find_tool("gdparse")
    if gp:
        for d in dict.fromkeys((os.path.dirname(gp), os.path.dirname(os.path.realpath(gp)))):
            for n in ("python3", "python"):
                c = os.path.join(d, n)
                if os.path.exists(c) and _py_has_gdtoolkit(c):
                    return c
    if _py_has_gdtoolkit(sys.executable):
        return sys.executable
    return None


# ------------------------------------------------------------------------------------------------ git helpers
def name_status(rd, base, head):
    """-> (changed new paths [ACMR], rename map new->old) over base..head. NUL separated: odd names are never quoted or lost."""
    rc, out, _ = qc.git(rd, "-c", "core.quotepath=off", "diff", "-z", "--name-status", "-M", "--diff-filter=ACMR", "%s..%s" % (base, head), timeout=120)
    if rc != 0:
        return None, {}
    files, ren, tok, i = [], {}, out.split("\0"), 0
    while i < len(tok):
        st = tok[i]
        if not st:
            i += 1
        elif st[0] in "RC" and i + 2 < len(tok):
            files.append(tok[i + 2])
            if st[0] == "R":
                ren[tok[i + 2]] = tok[i + 1]
            i += 3
        elif i + 1 < len(tok):
            files.append(tok[i + 1])
            i += 2
        else:
            i += 1
    return files, ren


def is_vendored(path):
    return any(p in EXCLUDE_DIRS for p in path.split("/")[:-1])


def extract(rd, ref, paths, dest, chunk=300):
    """git archive the given paths of `ref` into dest. Returns the set of paths that exist there afterwards."""
    got = set()
    for i in range(0, len(paths), chunk):
        part = paths[i:i + chunk]
        tar = os.path.join(dest, ".chunk.tar")
        rc, _, _ = qc.git(rd, "--literal-pathspecs", "archive", "--format=tar", "-o", tar, ref, "--", *part, timeout=180)
        if rc != 0:      # a path missing at this ref makes git archive fail for the whole chunk: retry one by one, the missing ones are just absent
            for p in part:
                rc1, _, _ = qc.git(rd, "--literal-pathspecs", "archive", "--format=tar", "-o", tar, ref, "--", p, timeout=60)
                if rc1 == 0:
                    qc.run(["tar", "-xf", tar, "-C", dest], polite=False, timeout=60)
        else:
            qc.run(["tar", "-xf", tar, "-C", dest], polite=False, timeout=180)
        try:
            os.unlink(tar)
        except OSError:
            pass
    for p in paths:
        fp = os.path.join(dest, p)
        if os.path.isfile(fp) and not os.path.islink(fp):
            got.add(p)
    return got


def run_helper(py, mode, root, files, timeout):
    """-> (status, results, note). status: OK | UNVERIFIED."""
    if not files:
        return "OK", {}, ""
    rc, out, err = qc.run([py, "-I", HELPER, mode, root], timeout=timeout, input_text=json.dumps(files))
    if rc == 124:
        return "UNVERIFIED", {}, "gdtoolkit %s timed out after %ss" % (mode, timeout)
    try:
        d = json.loads(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return "UNVERIFIED", {}, "gdtoolkit helper gave no result (rc=%s): %s" % (rc, (err or out).strip()[-120:])
    if d.get("import_error"):
        return "UNVERIFIED", {}, "gdtoolkit import failed: %s" % d["import_error"][:120]
    return "OK", d.get("results", {}), ""


def mask(desc):
    return re.sub(r"\d+", "N", desc or "")


# ------------------------------------------------------------------------------------------------ the gate
def parse_args(argv):
    o = {"repo": None, "base": None, "head": None, "timeout": os.environ.get("QA_GDPARSE_TIMEOUT", "180")}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and a[2:] in o and i + 1 < len(argv):
            o[a[2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    try:
        o["timeout"] = int(o["timeout"])
        if o["timeout"] < 1:
            raise ValueError
    except ValueError:
        o["error"] = "invalid --timeout %r (need a positive integer of seconds)" % (o["timeout"],)
        o["timeout"] = 180
    return o


def do_check(argv):
    o = parse_args(argv)
    repo, base, head = o["repo"], o["base"], o["head"]
    if not (repo and base and head):
        return qc.verdict("UNVERIFIED", GATE, repo or "?", head or "?", "check needs --repo --base --head")
    if o.get("error"):
        return qc.verdict("UNVERIFIED", GATE, repo, head, o["error"])
    mode = qc.mode(GATE)
    if mode == "off":
        return qc.verdict("NA", GATE, repo, head, "gate is off")
    rd = qc.repo_dir(repo)
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, repo, head, "no clone for repo")
    qc.ensure_commits(rd, (base, head), wait=float(os.environ.get("QA_FETCH_WAIT", "15")))
    for r in (base, head):
        if qc.git(rd, "rev-parse", "--verify", "-q", r + "^{commit}")[0] != 0:
            return qc.verdict("UNVERIFIED", GATE, repo, head, "ref %s not found" % r)
    rc, mbo, _ = qc.git(rd, "merge-base", base, head)
    mb = mbo.strip().splitlines()[0] if rc == 0 and mbo.strip() else ""
    if not mb:
        return qc.verdict("UNVERIFIED", GATE, repo, head, "no merge-base between %s and %s" % (base, head))
    allfiles, ren = name_status(rd, mb, head)
    if allfiles is None:
        return qc.verdict("UNVERIFIED", GATE, repo, head, "git diff failed")
    gd = [f for f in allfiles if f.endswith(".gd")]
    skipped = Counter()
    files = []
    for f in gd:
        if is_vendored(f):
            skipped["vendored_dir"] += 1
        else:
            files.append(f)
    if not gd:
        return qc.verdict("NA", GATE, repo, head, "no changed .gd files", {"files": len(allfiles)})
    if not files:
        return qc.verdict("NA", GATE, repo, head, "only vendored .gd changed (%d in addons/ or .godot/)" % len(gd), {"skipped": dict(skipped), "merge_base": mb})
    if len(files) > MAX_FILES:
        skipped["over_file_cap"] += len(files) - MAX_FILES
        files = files[:MAX_FILES]
    py = find_python()
    if not py:
        why = "gdtoolkit is not installed for this gate (QA_GDTOOLKIT_PYTHON / ~/qa-venv: pip install gdtoolkit): %d changed .gd NOT parsed" % len(files)
        det = {"files": len(files), "skipped": dict(skipped), "merge_base": mb, "gdtoolkit_missing": True, "mode": mode}
        if mode == "enforce":      # an enforced gate that could not check must never read as clean
            return qc.verdict("UNVERIFIED", GATE, repo, head, why, det)
        # shadow: the tool is simply not deployed (nothing here installs it). One NA row per xlite range, and release_candidate --run-gates (which globs
        # gate_*.py) is not turned UNVERIFIED by a tool that was never part of the box. The row says what was skipped; enforce still refuses to guess.
        return qc.verdict("NA", GATE, repo, head, why + " (shadow: not checked, not a verdict)", det)
    t0 = time.time()
    budget = o["timeout"]
    tmp = tempfile.mkdtemp(prefix="qa-gdparse-")
    try:
        hd, bd = os.path.join(tmp, "head"), os.path.join(tmp, "base")
        os.makedirs(hd)
        os.makedirs(bd)
        have_h = extract(rd, head, files, hd)
        unscannable = {}
        for f in files:
            if f not in have_h:
                unscannable[f] = "missing_at_head"
            else:
                try:
                    if os.path.getsize(os.path.join(hd, f)) > MAX_BYTES:
                        unscannable[f] = "too_large"
                except OSError:
                    unscannable[f] = "unreadable"
        scan = [f for f in files if f not in unscannable]
        left = lambda: max(5, int(budget - (time.time() - t0)))  # noqa: E731
        st, hp, note = run_helper(py, "parse", hd, scan, left())
        cells = {"gdparse": {"status": st, "note": note}, "gdlint": {"status": "NA", "note": ""}}
        if st != "OK":
            return qc.verdict("UNVERIFIED", GATE, repo, head, "gdparse could not run: %s" % note, {"files": len(files), "cells": cells, "merge_base": mb})
        bad = {f: r for f, r in hp.items() if r["kind"] == "parse_error"}
        tool_err = {f: r for f, r in hp.items() if r["kind"] == "tool_error"}
        # which broken files were ALREADY broken at the merge-base (rename-aware)? informational, never lowers the finding count
        base_paths = {f: ren.get(f, f) for f in bad}
        have_b = extract(rd, mb, sorted(set(base_paths.values())), bd) if bad else set()
        pre = set()
        if bad and have_b:
            rel_b = sorted(set(base_paths[f] for f in bad if base_paths[f] in have_b))
            st_b, bp, _ = run_helper(py, "parse", bd, rel_b, left())
            if st_b == "OK":
                pre = set(f for f in bad if base_paths[f] in bp and bp[base_paths[f]]["kind"] == "parse_error")
        perrs = [{"file": f, "err": r["err"], "preexisting": f in pre} for f, r in sorted(bad.items())]
        # ---- gdlint: advisory, baseline-relative
        lint_note = ""
        lint = {"status": "NA", "head_total": 0, "base_total": 0, "new": 0, "new_list": []}
        if time.time() - t0 < budget - 10 and os.environ.get("QA_GDLINT", "on") != "off":
            lscan = [f for f in scan if f not in bad and f not in tool_err]
            st_l, hl, nl = run_helper(py, "lint", hd, lscan, left())
            if st_l != "OK":
                lint.update(status="UNVERIFIED")
                lint_note = nl
            else:
                have_b2 = extract(rd, mb, sorted(set(ren.get(f, f) for f in lscan)), bd)
                st_b2, bl, nb = run_helper(py, "lint", bd, sorted(p for p in set(ren.get(f, f) for f in lscan) if p in have_b2), left())
                if st_b2 != "OK":
                    lint.update(status="UNVERIFIED")
                    lint_note = "base lint: " + nb
                else:
                    new_list, htot, btot = [], 0, 0
                    for f in lscan:
                        hc = Counter((p[0], mask(p[2])) for p in hl.get(f, {}).get("problems", []))
                        bc = Counter((p[0], mask(p[2])) for p in bl.get(ren.get(f, f), {}).get("problems", []))
                        htot += sum(hc.values())
                        btot += sum(bc.values())
                        extra = hc - bc
                        if extra:
                            shown = Counter()
                            for p in hl.get(f, {}).get("problems", []):
                                key = (p[0], mask(p[2]))
                                if shown[key] < extra[key]:
                                    shown[key] += 1
                                    new_list.append({"at": "%s:%d" % (f, p[1]), "rule": p[0], "msg": p[2][:140]})
                    lint.update(status="OK", head_total=htot, base_total=btot, new=len(new_list), new_list=new_list[:MAX_LIST],
                                by_rule=dict(Counter(x["rule"] for x in new_list).most_common(8)))
        cells["gdlint"] = {"status": lint["status"], "note": lint_note}
        details = {"files": len(files), "gd_changed": len(gd), "skipped": dict(skipped), "merge_base": mb, "cells": cells, "parse_errors": perrs[:MAX_LIST],
                   "n_parse_errors": len(perrs), "n_preexisting": len(pre), "tool_errors": {f: r["err"] for f, r in list(tool_err.items())[:5]},
                   "unscannable": dict(list(unscannable.items())[:10]), "gdlint": lint, "mode": mode, "would_be_verdict": "FAIL" if perrs else None}
        lt = " gdlint: %d new advisory finding(s) (%d at head, %d at base)." % (lint["new"], lint["head_total"], lint["base_total"]) if lint["status"] == "OK" else ""
        if perrs:
            first = "; ".join("%s: %s" % (p["file"], p["err"]) for p in perrs[:2])[:200]
            v = "FAIL" if mode == "enforce" else "FLAG"
            return qc.verdict(v, GATE, repo, head, "%d changed .gd file(s) do not parse (%d new, %d already broken at base) - GUT would silently skip them: %s.%s" % (
                len(perrs), len(perrs) - len(pre), len(pre), first, lt), details)
        if tool_err or unscannable:
            return qc.verdict("UNVERIFIED", GATE, repo, head, "no parse errors but %d changed .gd file(s) could not be checked (%s)" % (
                len(tool_err) + len(unscannable), "; ".join("%s: %s" % kv for kv in list({**{f: r["err"] for f, r in tool_err.items()}, **unscannable}.items())[:2])[:160]), details)
        return qc.verdict("PASS", GATE, repo, head, "%d changed .gd file(s) parsed clean.%s%s" % (len(files), lt, " Skipped: %s." % dict(skipped) if skipped else ""), details)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    if argv and argv[0] == "check":
        return qc.main_guard(GATE, do_check, argv[1:])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
