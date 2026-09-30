#!/usr/bin/env python3
"""Aggregate line coverage of the overnight pipeline from an instrumented test run.

bash:   every line seen in the xtrace files written by cov_env.sh (OVN_COV_DIR/bash.*.x) vs the file's EXECUTABLE lines
        (approximation: non-blank, not comment-only, not a bare fi/done/esac/else/then/do/{/}/;; line, not inside a
        heredoc body, not a backslash-continuation of the previous line).
python: coverage.py data written with COVERAGE_PROCESS_START (OVN_COV_DIR/py/.coverage.*), via `coverage json`.

usage: ovn_cov_report.py <cov_dir> <pipeline_root> [--min PCT] [--json out.json] [--only-live live.txt] [--show-missing N]
Exit 1 when total (bash+python) line coverage of the scoped scripts is below --min.
"""
import json
import os
import re
import subprocess
import sys

BARE = re.compile(r"^\s*(fi|done|esac|else|then|do|\{|\}|;;|\)|in|\(|\|\|.*true)\s*(#.*)?$")


def bash_executable_lines(path):
    try:
        lines = open(path, errors="replace").read().split("\n")
    except OSError:
        return set()
    out, heredoc, cont = set(), None, False
    for i, raw in enumerate(lines, 1):
        s = raw.strip()
        if heredoc is not None:
            if s == heredoc or raw.rstrip("\n") == heredoc:
                heredoc = None
            continue
        was_cont, cont = cont, raw.rstrip().endswith("\\")
        if not s or s.startswith("#") or BARE.match(raw) or was_cont:
            continue
        m = re.search(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", raw)
        if m:
            heredoc = m.group(2)
        if i == 1 and s.startswith("#!"):
            continue
        out.add(i)
    return out


def collect_bash(cov_dir):
    seen = {}
    pat = re.compile(rb"@@([^@\n]+):(\d+)@@")
    for fn in os.listdir(cov_dir):
        if not (fn.startswith("bash.") and fn.endswith(".x")):
            continue
        with open(os.path.join(cov_dir, fn), "rb") as f:
            for chunk in f:
                for m in pat.finditer(chunk):
                    seen.setdefault(m.group(1).decode("utf-8", "replace"), set()).add(int(m.group(2)))
    return seen


def main():
    cov_dir, root = sys.argv[1], os.path.abspath(sys.argv[2])
    a = sys.argv[3:]
    minp = float(a[a.index("--min") + 1]) if "--min" in a else None
    outj = a[a.index("--json") + 1] if "--json" in a else None
    only = None
    if "--only-live" in a:
        only = set(open(a[a.index("--only-live") + 1]).read().split())
    show = int(a[a.index("--show-missing") + 1]) if "--show-missing" in a else 0
    seen = collect_bash(cov_dir)
    # Tests often COPY a script into a temp tree (or run it by relative path) before executing it, so attribute every traced
    # file to the pipeline script with the same BASENAME (basenames of pipeline scripts are unique; attic/.bak are excluded).
    by_base = {}
    norm = {}
    for f, ls in seen.items():
        by_base.setdefault(os.path.basename(f), set()).update(ls)
    rows = []
    for dp, dn, fns in os.walk(root):
        dn[:] = [d for d in dn if d not in (".git", "test", "attic", "cov", "proposals-2026-09-29", "__pycache__", "state", "logs", "repos", "backlog", "roadmap", "prework", "art", "assets", "systemd", "tests") and not d.startswith(".bak")]
        for fn in fns:
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, root)
            if only is not None and rel not in only:
                continue
            if fn.endswith(".sh"):
                ex = bash_executable_lines(p)
                hit = by_base.get(fn, set()) & ex
                rows.append((rel, "bash", len(hit), len(ex), sorted(ex - hit)))
    pydata = os.path.join(cov_dir, "py")
    pyjson = os.path.join(cov_dir, "py.json")
    if os.path.isdir(pydata):
        comb = os.path.join(cov_dir, "py.combined")
        for stale in (comb, pyjson):
            if os.path.exists(stale):
                os.remove(stale)
        env = {k: v for k, v in os.environ.items() if k != "COVERAGE_FILE"}
        subprocess.run(["python3", "-m", "coverage", "combine", "--keep", "--data-file=" + comb, pydata], env=env, capture_output=True)
        subprocess.run(["python3", "-m", "coverage", "json", "--data-file=" + comb, "-o", pyjson, "--ignore-errors"], env=env, capture_output=True)
        if os.path.exists(pyjson):
            d = json.load(open(pyjson))
            for f, v in d.get("files", {}).items():
                ap = os.path.normpath(f)
                if not ap.startswith(root) or "/scripts/test/" in ap or "/scripts/cov/" in ap:
                    continue
                rel = os.path.relpath(ap, root)
                if only is not None and rel not in only:
                    continue
                s = v["summary"]
                rows.append((rel, "python", s["covered_lines"], s["num_statements"], v.get("missing_lines", [])))
    rows.sort(key=lambda r: (r[2] / r[3] if r[3] else 1.0))
    tc = sum(r[2] for r in rows)
    tt = sum(r[3] for r in rows)
    print("%-46s %-7s %7s %7s %6s" % ("script", "lang", "hit", "lines", "pct"))
    for rel, lang, h, t, miss in rows:
        print("%-46s %-7s %7d %7d %5.1f%%" % (rel[:46], lang, h, t, 100.0 * h / t if t else 100.0))
        if show and miss:
            print("      missing: " + ",".join(str(x) for x in miss[:show]) + (" ..." if len(miss) > show else ""))
    pct = 100.0 * tc / tt if tt else 100.0
    zero = [r[0] for r in rows if r[3] and r[2] == 0]
    print("\nTOTAL: %d/%d lines = %.1f%%   scripts=%d   never executed at all=%d" % (tc, tt, pct, len(rows), len(zero)))
    if outj:
        json.dump({"total_pct": pct, "covered": tc, "lines": tt, "scripts": [{"file": r[0], "lang": r[1], "hit": r[2], "lines": r[3]} for r in rows]}, open(outj, "w"), indent=1)
    if minp is not None and pct < minp:
        print("BELOW --min %.1f" % minp)
        sys.exit(1)


if __name__ == "__main__":
    main()
