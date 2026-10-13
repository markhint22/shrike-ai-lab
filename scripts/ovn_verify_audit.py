#!/usr/bin/env python3
"""scripts/ovn_verify_audit.py - READ-ONLY audit of CREDITED ([x]) items whose own VERIFY disagrees with the code (R14 verify package, 2026-10-12, xlite X1).

Before the polarity fix, every credit path ran an item's VERIFY and took exit 0 as "satisfied" - also for items that state an ABSENCE ("`grep -n X f` returns no matches",
"`ls f` fails with No such file"), where exit 0 means the thing is still there. This tool lists the credited items that are affected: it re-runs each credited item's VERIFY on a
fresh `git archive` copy of a ref (default origin/overnight/feature) and compares the exit status with the polarity the item states (ovn_backlog_eligibility.verify_polarity).

  python3 ovn_verify_audit.py --repo xlite=<git dir> --repo iptv_apps=<git dir> [--ref REF] [--scratch DIR] [--tree NAME=DIR] [--godot PATH] [--md FILE] [--json FILE]

Sources: OVERNIGHT_PROGRESS.md and OVERNIGHT_DONE.md at the ref (every `- [x]` line carrying a VERIFY clause; a line present in both files is judged once).
Classes
  FALSE-CREDIT   the item states an absence (neg polarity) and the thing is STILL PRESENT in the tree (exit status says "present"): reopen
  OK             the exit status matches the stated polarity (neg: absent; pos / unknown: exit 0)
  FAILS-NOW      pos / unknown polarity and the VERIFY fails on the ref tree: informational (a later commit may have changed the code; not necessarily a false credit)
  CANNOT-RUN     not executed: a command outside the allow-list (runners, sed/awk, tee, ...), a godot-engine clause without --godot, an indeterminate stage/grep error, a timeout, rc 126/127
SAFETY (R15): VERIFY text is untrusted. Only an ALLOW-LIST of read-only commands is ever executed (ovn_verify_safe.py: grep family, test/[, ls, stat, cat, head, tail, wc, find without
-exec/-delete/-fprint*, diff, cmp, sort without -o, uniq, tr, cut), joined only by | && || ;, with no substitution / redirection / env prefix; each pipeline runs with a minimal env in its own
process group (killed as a group on timeout) in a throwaway copy of the tree. Anything else (tee, touch, sed, awk, python, pytest, git, ssh, nc, ...) is CANNOT-RUN and is never executed.
Stage errors count: `grep X missing | grep -v y` / `cd missing && grep` (an earlier stage failing) are indeterminate, never an absence; grep rc >= 2 on a negative item is CANNOT-RUN.
OVERNIGHT_*.md / CLAUDE_QUEUE*.md are removed from the audited copy (they quote every VERIFY, so a recursive grep would match its own item). The live repo is only READ (git show / git archive).
Exit 0 always (it is a report).
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ovn_backlog_eligibility as E  # noqa: E402
import ovn_verify_safe as V  # noqa: E402

EXCLUDE = re.compile(r"^(?:OVERNIGHT_[^/]*\.md|CLAUDE_QUEUE[^/]*\.md)$")
SOURCES = ("OVERNIGHT_PROGRESS.md", "OVERNIGHT_DONE.md")
CRED = re.compile(r"^\s*- \[[xX]\] ")


def git(gitdir, *args, timeout=120, text=True):
    return subprocess.run(["git", "-C", gitdir] + list(args), capture_output=True, text=text, errors="replace" if text else None, timeout=timeout)


def credited_items(gitdir, ref):
    """[(source, lineno, line)] of credited lines with a VERIFY clause, de-duplicated by the queue's item identity."""
    seen, out = set(), []
    for src in SOURCES:
        r = git(gitdir, "show", "%s:%s" % (ref, src))
        if r.returncode != 0:
            continue
        for n, line in enumerate(r.stdout.split("\n"), 1):
            if not CRED.match(line) or "VERIFY:" not in line:
                continue
            h = E.line_hash(line)
            if h in seen:
                continue
            seen.add(h)
            out.append((src, n, line))
    return out


GUT_OK = re.compile(r"^(?:cd [\w./-]+ && )?godot(?: [\w=./:,%@-]+)*$")


def _group_run(argv, cwd, timeout, env):
    """Run argv in its own process group with a minimal env; kill the whole group on timeout. -> (rc | None on timeout, output text)"""
    p = subprocess.Popen(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=env, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.communicate()
        return None, ""
    finally:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
    return p.returncode, out.decode("utf-8", "replace")


def classify(line, tree, godot=None, timeout=20):
    """-> (class, detail dict). Only allow-listed read-only commands (ovn_verify_safe) are executed; everything else is CANNOT-RUN."""
    cmd, pol = E.verify_clause_and_polarity(line)
    d = {"cmd": cmd, "polarity": pol, "rc": None, "why": ""}
    if not cmd:
        d["why"] = "no runnable clause"
        return "CANNOT-RUN", d
    cls = E.verify_tool_class(cmd)
    if "gut_cmdln" in cmd:
        if not godot:
            d["why"] = "godot-engine clause (no headless engine given)"
            return "CANNOT-RUN", d
        import ovn_gut_clause as G
        run = G.normalize(cmd, G.DirFS(tree))[0]
        if not GUT_OK.match(run.strip()) or ">" in run:
            d["why"] = "godot clause with extra shell syntax (not run)"
            return "CANNOT-RUN", d
        run = re.sub(r"(^|&& )godot ", lambda m: m.group(1) + godot + " ", run)
        if "-gexit" not in run:
            run = run.replace("gut_cmdln.gd", "gut_cmdln.gd -gexit", 1)
        rc, out = _group_run(["bash", "-c", run], tree, 150, {"PATH": "/usr/bin:/bin", "HOME": tree, "CI": "true"})
        if rc is None:
            d["why"] = "timeout"
            return "CANNOT-RUN", d
        d["rc"] = rc
        if rc in (126, 127):
            d["why"] = "rc %d (not runnable)" % rc
            return "CANNOT-RUN", d
        if re.search(r"Could not find script|does not exist|Nothing was run", out):
            d["why"] = "GUT target missing / nothing run"
            return "CANNOT-RUN", d
        if re.search(r"^\s*Failing\s+[1-9]|\[Failed\]", re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out), re.M):
            rc = 1
        return ("OK", d) if E.polarity_verdict(pol, cls, rc) else (("FALSE-CREDIT" if pol == "neg" else "FAILS-NOW"), d)
    res = V.run(cmd, tree, timeout)
    if res["status"] == "UNSAFE":
        d["why"] = "not allow-listed / unsafe shape (not executed): " + res["why"]
        return "CANNOT-RUN", d
    if res["status"] == "TIMEOUT":
        d["why"] = "timeout"
        return "CANNOT-RUN", d
    rc = res["rc"]
    d["rc"] = rc
    if rc in (124, 126, 127):
        d["why"] = "rc %d (not runnable)" % rc
        return "CANNOT-RUN", d
    if pol == "neg" and res["err"]:
        if V.delete_shape_ok(line, cmd, tree):
            d["why"] = "grep on a file the item deletes: satisfied-absent"
            return "OK", d
        d["why"] = "indeterminate (earlier-stage / cd error): " + res["why"]
        return "CANNOT-RUN", d
    if pol == "neg" and cls == "grep" and rc >= 2:
        if V.delete_shape_ok(line, cmd, tree):
            d["why"] = "grep on a file the item deletes: satisfied-absent"
            return "OK", d
        d["why"] = "grep error rc %d (not an absence)" % rc
        return "CANNOT-RUN", d
    if polarity_ok(pol, cls, rc):
        return "OK", d
    if pol == "neg":
        return "FALSE-CREDIT", d
    return "FAILS-NOW", d


def polarity_ok(pol, cls, rc):
    return bool(E.polarity_verdict(pol, cls, rc))


def prune_self_references(tree):
    """The queue files (OVERNIGHT_*.md, CLAUDE_QUEUE*.md) quote every item's own VERIFY text: a `grep -r "elevation.gd" .` would match the queue line that carries it and read as
    'still present'. Remove them from the audited copy."""
    for dp, dn, fn in os.walk(tree):
        dn[:] = [x for x in dn if x != ".git"]
        for f in fn:
            if EXCLUDE.match(f):
                try:
                    os.unlink(os.path.join(dp, f))
                except OSError:
                    pass


def audit_repo(name, gitdir, ref, tree=None, godot=None, scratch=None):
    made = None
    if tree is None:
        base = scratch or tempfile.mkdtemp(prefix="verify-audit-")
        tree = os.path.join(base, name)
        os.makedirs(tree, exist_ok=True)
        ar = subprocess.Popen(["git", "-C", gitdir, "archive", ref], stdout=subprocess.PIPE)
        tr = subprocess.run(["tar", "-x", "-C", tree], stdin=ar.stdout, capture_output=True)
        ar.stdout.close()
        ar.wait()
        if tr.returncode != 0 or ar.returncode != 0:
            raise SystemExit("git archive of %s@%s failed" % (gitdir, ref))
        made = base if scratch is None else None
    else:   # a given checkout is only ever READ: audit a throwaway copy of it (so the self-reference prune below cannot touch it)
        base = scratch or tempfile.mkdtemp(prefix="verify-audit-")
        copy = os.path.join(base, name + "-copy")
        shutil.copytree(tree, copy, symlinks=True, ignore=shutil.ignore_patterns(".git"))
        tree, made = copy, (base if scratch is None else None)
    prune_self_references(tree)
    rows = []
    for src, n, line in credited_items(gitdir, ref):
        c, d = classify(line, tree, godot)
        p = E.verify_clause_and_polarity(line)
        fm = re.search(r"\[feat:([^\]]+)\]", line)
        tm = re.match(r"^\s*- \[[xX]\] (?:\([^)]*\)\s*)?(?:\[(T[1-5])\]\s*)?(.*)$", line)
        rows.append({"repo": name, "class": c, "source": "%s:%d" % (src, n), "feat": fm.group(1) if fm else "", "tier": (tm.group(1) if tm and tm.group(1) else ""),
                     "item": re.sub(r"\s+VERIFY:.*$", "", (tm.group(2) if tm else line))[:160], "verify": d["cmd"][:200], "polarity": p[1], "rc": d["rc"], "why": d["why"],
                     "pre_verified": "pre-verified" in line})
    return rows, made


def render_md(rows, meta):
    by = {}
    for r in rows:
        by.setdefault(r["repo"], []).append(r)
    L = ["# VERIFY audit %s" % meta["date"], "",
         "Read-only audit of CREDITED (`[x]`) items: each item's own VERIFY was re-run on a fresh `git archive` copy of the ref below and compared with the polarity the item states "
         "(`ovn_backlog_eligibility.verify_polarity`). Generated by `scripts/overnight-queue/scripts/ovn_verify_audit.py`.", "",
         "Why: before the R14 polarity fix every credit path took VERIFY exit 0 as 'satisfied', also for items that state an ABSENCE (`grep ... returns no matches`, `ls f fails with No such file`) "
         "where exit 0 means the thing is still there.", "",
         "Refs: " + "; ".join("%s @ `%s`" % (k, v) for k, v in meta["refs"].items()), "",
         "Classes: **FALSE-CREDIT** (absence stated, thing still present: reopen) | OK | **FAILS-NOW** (positive/unknown VERIFY fails on the ref tree; informational, a later commit may have changed the code) | CANNOT-RUN (runner / engine / timeout / denylist).", "",
         "## Counts", "", "| repo | credited with VERIFY | FALSE-CREDIT | OK | FAILS-NOW | CANNOT-RUN |", "|---|---|---|---|---|---|"]
    for repo, rs in by.items():
        cnt = {k: sum(1 for r in rs if r["class"] == k) for k in ("FALSE-CREDIT", "OK", "FAILS-NOW", "CANNOT-RUN")}
        L.append("| %s | %d | %d | %d | %d | %d |" % (repo, len(rs), cnt["FALSE-CREDIT"], cnt["OK"], cnt["FAILS-NOW"], cnt["CANNOT-RUN"]))
    for repo, rs in by.items():
        fc = [r for r in rs if r["class"] == "FALSE-CREDIT"]
        L += ["", "## %s: FALSE-CREDIT (%d) - reopen these" % (repo, len(fc)), ""]
        if fc:
            L += ["| source | feat | item | VERIFY | pre-verified credit |", "|---|---|---|---|---|"]
            for r in fc:
                L.append("| %s | %s | %s | `%s` | %s |" % (r["source"], r["feat"], r["item"].replace("|", "/"), r["verify"].replace("|", "\\|"), "yes" if r["pre_verified"] else "no"))
        else:
            L.append("none")
        why = {}
        for r in rs:
            if r["class"] == "CANNOT-RUN":
                why[r["why"]] = why.get(r["why"], 0) + 1
        L += ["", "### %s: CANNOT-RUN reasons" % repo, ""] + (["- %s: %d" % (k, v) for k, v in sorted(why.items(), key=lambda kv: -kv[1])] or ["none"])
        fn = [r for r in rs if r["class"] == "FAILS-NOW"]
        L += ["", "### %s: FAILS-NOW (%d, informational)" % (repo, len(fn)), ""]
        L += ["- %s | %s | `%s`" % (r["source"], r["item"][:90].replace("|", "/"), r["verify"][:110].replace("|", "\\|")) for r in fn] or ["none"]
    return "\n".join(L) + "\n"


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", action="append", default=[], help="NAME=<git dir> (repeatable)")
    ap.add_argument("--tree", action="append", default=[], help="NAME=<existing checkout of the ref> (skips git archive)")
    ap.add_argument("--ref", default="origin/overnight/feature")
    ap.add_argument("--scratch", default=None, help="directory for the git-archive copies (default: a temp dir, removed afterwards)")
    ap.add_argument("--godot", default=None, help="headless godot binary: GUT clauses are run (normalised) instead of CANNOT-RUN")
    ap.add_argument("--md", default=None)
    ap.add_argument("--json", default=None)
    a = ap.parse_args(argv[1:])
    trees = dict(t.split("=", 1) for t in a.tree)
    rows, meta_refs, cleanup = [], {}, []
    for spec in a.repo:
        name, gd = spec.split("=", 1)
        r = git(gd, "rev-parse", "--short", a.ref)
        meta_refs[name] = (r.stdout.strip() if r.returncode == 0 else "?") + " (%s)" % a.ref
        rs, made = audit_repo(name, gd, a.ref, trees.get(name), a.godot, a.scratch)
        rows += rs
        if made:
            cleanup.append(made)
    import datetime
    meta = {"date": datetime.date.today().isoformat(), "refs": meta_refs}
    md = render_md(rows, meta)
    if a.md:
        with open(a.md, "w", encoding="utf-8") as f:
            f.write(md)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({"meta": meta, "rows": rows}, f, indent=1)
    if not a.md:
        sys.stdout.write(md)
    for c in cleanup:
        shutil.rmtree(c, ignore_errors=True)
    by = {}
    for r in rows:
        by[(r["repo"], r["class"])] = by.get((r["repo"], r["class"]), 0) + 1
    print("audit: " + ", ".join("%s %s=%d" % (k[0], k[1], v) for k, v in sorted(by.items())), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
