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

BARE = re.compile(r"^\s*(fi|done\b.*|esac|else|then|do|\{|\}|;;|\)|in|\(|elif\b.*;\s*then)\s*(#.*)?$")
LABEL = re.compile(r"^\s*[A-Za-z0-9_*?|\\\"'\[\]\-.: /${}@]+\)\s*(#.*)?$")      # bare `pattern)` case label
FUNC_HEADER = re.compile(r"^\s*(function\s+)?[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{?\s*(#.*)?$")      # `name() {` with nothing after


CLOSE_REDIR = re.compile(r"^\s*(done|fi|esac|\})\s*(<|>|\|)")             # `done < <(...)`, `} >> log`: the closer is never traced


def _scan(line, stack):
    """Advance a tiny shell-lexer state machine across one line. `stack` holds open contexts: "dq" (inside "..."), "sq" (inside '...'),
    "cmd" (inside $( ... )). Comments, escapes and nested $(..)/quotes are handled well enough to know whether a statement is still
    open at end of line."""
    st = list(stack)
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        top = st[-1] if st else None
        if top == "sq":
            if c == "'":
                st.pop()
        elif top == "dq":
            if c == "\\":
                i += 1
            elif c == '"':
                st.pop()
            elif c == "$" and line[i + 1:i + 2] == "(":
                st.append("cmd")
                i += 1
        else:  # top level or inside $( )
            if c == "#" and (i == 0 or line[i - 1] in " \t;("):
                break
            if c == "\\":
                i += 1
            elif c == "'":
                st.append("sq")
            elif c == '"':
                st.append("dq")
            elif c == "$" and line[i + 1:i + 2] == "(":
                st.append("cmd")
                i += 1
            elif c == ")" and top == "cmd":
                st.pop()
        i += 1
    return st


def bash_executable_lines(path):
    """Executable lines = lines xtrace CAN report. xtrace reports a multi-line command at its LAST line (verified against real trace
    data), so for a statement spanning several lines (backslash continuation, an open quote or an open $( ... )) only the final line
    counts. Also excluded: blank/comment/bare closers, heredoc bodies, function-definition headers and bare case labels."""
    try:
        lines = open(path, errors="replace").read().split("\n")
    except OSError:
        return set()
    out, heredoc, stack = set(), None, []
    for i, raw in enumerate(lines, 1):
        s = raw.strip()
        if heredoc is not None:
            if s == heredoc or raw.rstrip("\n") == heredoc:
                heredoc = None
            continue
        was_open = bool(stack)
        stack = _scan(raw, stack)
        cont = raw.rstrip().endswith("\\") and not stack
        if stack or cont:
            continue
        if was_open:
            out.add(i)
            continue
        if not s or s.startswith("#") or BARE.match(raw) or LABEL.match(raw) or FUNC_HEADER.match(raw) or CLOSE_REDIR.match(raw):
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


QA = os.environ.get("OVN_COV_QA", "0") == "1"      # qa/ is measured (and reported as bash-qa / python-qa, outside the nightly floors) only for an OVN_COV_QA=1 run
PY_SKIP_DIRS = (".git", "test", "attic", "cov", "proposals-2026-09-29", "__pycache__", "state", "logs", "repos", "backlog", "roadmap", "prework", "art", "assets", "systemd", "tests")


# Generic basenames that every project has (conftest.py, __init__.py, ...): attributing ANY file with such a name from outside the tree to a pipeline script of the same name would add an unrelated file's
# executed lines to it. They are never folded by basename (run_coverage.sh leaves them out of the include list too).
GENERIC_BASENAMES = ("conftest.py", "__init__.py", "__main__.py", "setup.py")


def py_by_basename(root):
    """basename -> relative path of the pipeline's own python scripts (a basename that occurs twice is ambiguous and left out: attributing a copy to the wrong file is worse than not attributing it)."""
    seen, dup = {}, set()
    for dp, dn, fns in os.walk(root):
        dn[:] = [d for d in dn if d not in PY_SKIP_DIRS and not d.startswith(".bak") and not d.startswith("proposals") and (d != "qa" or QA)]
        for fn in fns:
            if fn.endswith(".py") and not fn.startswith("._") and fn not in GENERIC_BASENAMES:
                if fn in seen:
                    dup.add(fn)
                seen[fn] = os.path.relpath(os.path.join(dp, fn), root)
    return {k: v for k, v in seen.items() if k not in dup}


def data_lines(comb):
    """{path: set(executed line numbers)} for EVERY file in the combined coverage data, read straight from the data file. `coverage json --ignore-errors` silently drops a measured file whose source is
    gone, and a test's temp copy of a tool is deleted by that test's own cleanup long before the report runs (test_ovn_spec_gate_scan.sh: 11 copies, none in the json) - the executed lines survive in the data."""
    try:
        import coverage
        cd = coverage.CoverageData(basename=comb)
        cd.read()
        return {f: set(cd.lines(f) or []) for f in cd.measured_files()}
    except Exception:
        return {}


def real_statements(path):
    """The executable statements of a python source file (coverage.py's own parser), or None."""
    try:
        from coverage.python import PythonParser
        pp = PythonParser(filename=path)
        pp.parse_source()
        return set(pp.statements)
    except Exception:
        return None


def fold_python(files, root, only=None, lines=None):
    """coverage.py json `files` (+ `lines`: data_lines() of the combined data) -> [(rel, lang, covered, statements, missing)]. A file under `root` is reported as itself; a file OUTSIDE it (a temp
    copy a test made of a pipeline script, usually already deleted) is attributed to the pipeline script with the same basename and its executed lines are unioned onto that script's (restricted to the
    script's own statements, so a mutant copy with one changed line can never add statements). Files under scripts/test and scripts/cov are not counted."""
    roots = {root, os.path.realpath(root)}
    by_base = py_by_basename(root)
    inroot, extra, extra_st = {}, {}, {}
    for f, v in files.items():
        ap = os.path.normpath(f if os.path.isabs(f) else os.path.join(root, f))
        under = next((r for r in roots if ap == r or ap.startswith(r + os.sep)), None)
        if os.path.basename(ap).startswith("._"):
            continue
        if under:
            if "/scripts/test/" in ap or "/scripts/cov/" in ap:
                continue
            rel = os.path.relpath(ap, under)
            inroot[rel] = (set(v.get("executed_lines", [])), set(v.get("missing_lines", [])))
        else:
            rel = by_base.get(os.path.basename(ap))
            if rel:
                extra.setdefault(rel, set()).update(v.get("executed_lines", []))
                extra_st.setdefault(rel, set()).update(set(v.get("executed_lines", [])) | set(v.get("missing_lines", [])))
    for f, ex in (lines or {}).items():                  # copies whose source is gone: only the data file still has their executed lines
        ap = os.path.normpath(f if os.path.isabs(f) else os.path.join(root, f))
        if os.path.basename(ap).startswith("._") or any(ap == r or ap.startswith(r + os.sep) for r in roots) or "/scripts/test/" in ap or "/scripts/cov/" in ap:
            continue
        rel = by_base.get(os.path.basename(ap))
        if rel:
            extra.setdefault(rel, set()).update(ex)
    for rel in extra:                                   # a script that ONLY ever ran as a temp copy: its statements come from the real file (parser), else the copy's
        if rel not in inroot:
            st = real_statements(os.path.join(root, rel)) or extra_st.get(rel) or set(extra[rel])
            inroot[rel] = (set(), st)
    out = []
    for rel, (ex, mi) in inroot.items():
        if only is not None and rel not in only:
            continue
        stmts = ex | mi
        cov = (ex | extra.get(rel, set())) & stmts
        out.append((rel, "python-qa" if rel.startswith("qa" + os.sep) else "python", len(cov), len(stmts), sorted(stmts - cov)))
    return out


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
    # 2026-10-02: "qa" excluded - the QA gates' entry-point tests run under `env -i`, which strips BASH_ENV/COVERAGE_PROCESS_START, so their
    # shell/python subprocess runs are unmeasurable (tests pass; qa_ledger_cron.sh shows 0/26). Re-include once those tests pass the cov vars through.
    for dp, dn, fns in os.walk(root):
        dn[:] = [d for d in dn if d not in (".git", "test", "attic", "cov", "proposals-2026-09-29", "__pycache__", "state", "logs", "repos", "backlog", "roadmap", "prework", "art", "assets", "systemd", "tests") and not d.startswith(".bak")
                 and (d != "qa" or QA)]
        for fn in fns:
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, root)
            if only is not None and rel not in only:
                continue
            if fn.startswith("._"):      # 2026-10-10: macOS AppleDouble files that a Mac tar/rsync deploy leaves on the box (./._run_overnight.sh, scripts/._lib_dep_import_check.py): not scripts, they showed as 0 % rows
                continue
            if fn.endswith(".sh"):
                ex = bash_executable_lines(p)
                hit = by_base.get(fn, set()) & ex
                rows.append((rel, "bash-qa" if rel.startswith("qa" + os.sep) else "bash", len(hit), len(ex), sorted(ex - hit)))
    pydata = os.path.join(cov_dir, "py")
    pyjson = os.path.join(cov_dir, "py.json")
    if os.path.isdir(pydata):
        # coverage.py's combine scans <dir> for files named "<data-file basename>.*", so the combined file must share the raw files'
        # prefix (".coverage"); --keep leaves the raw per-process files so re-running this report is idempotent.
        comb = os.path.join(pydata, ".coverage")
        if os.path.exists(pyjson):
            os.remove(pyjson)
        env = {k: v for k, v in os.environ.items() if k != "COVERAGE_FILE"}
        subprocess.run(["python3", "-m", "coverage", "combine", "--keep", "--data-file=" + comb, pydata], env=env, capture_output=True)
        noopdir = os.path.join(cov_dir, "py_noop")           # the no-op `source` run (never-imported top-level files as 0 %): kept apart, see run_coverage.sh
        if os.path.isdir(noopdir):
            subprocess.run(["python3", "-m", "coverage", "combine", "--append", "--keep", "--data-file=" + comb, noopdir], env=env, capture_output=True)
        # 2026-10-02: honour the run's covrc so its `omit` (e.g. */qa/*, unmeasurable under env -i) also applies at report time
        _rc = os.path.join(cov_dir, "covrc")
        _rcarg = ["--rcfile=" + _rc] if os.path.isfile(_rc) else []
        subprocess.run(["python3", "-m", "coverage", "json", *_rcarg, "--data-file=" + comb, "-o", pyjson, "--ignore-errors"], env=env, capture_output=True)
        if os.path.exists(pyjson):
            d = json.load(open(pyjson))
            rows.extend(fold_python(d.get("files", {}), root, only, data_lines(comb)))
    rows.sort(key=lambda r: (r[2] / r[3] if r[3] else 1.0))
    core = [r for r in rows if r[1] in ("bash", "python")]
    qa_rows = [r for r in rows if r[1] in ("bash-qa", "python-qa")]
    tc = sum(r[2] for r in core)
    tt = sum(r[3] for r in core)
    print("%-46s %-7s %7s %7s %6s" % ("script", "lang", "hit", "lines", "pct"))
    for rel, lang, h, t, miss in rows:
        print("%-46s %-7s %7d %7d %5.1f%%" % (rel[:46], lang, h, t, 100.0 * h / t if t else 100.0))
        if show and miss:
            print("      missing: " + ",".join(str(x) for x in miss[:show]) + (" ..." if len(miss) > show else ""))
    pct = 100.0 * tc / tt if tt else 100.0
    seen_py = {r[0] for r in rows if r[1].startswith("python")}
    never_py = sorted(rel for rel in py_by_basename(root).values() if rel not in seen_py and (only is None or rel in only))
    zero = [r[0] for r in core if r[3] and r[2] == 0]
    print("\nTOTAL: %d/%d lines = %.1f%%   scripts=%d   never executed at all=%d" % (tc, tt, pct, len(core), len(zero)))
    if never_py:
        print("python scripts no test ever imported or ran (NOT in the totals - coverage.py only reports never-imported files at the top level; listed so the gap is visible): %d: %s%s"
              % (len(never_py), ", ".join(never_py[:12]), " ..." if len(never_py) > 12 else ""))
    if qa_rows:
        qc, qt = sum(r[2] for r in qa_rows), sum(r[3] for r in qa_rows)
        print("TOTAL (qa/, informational - NOT part of the nightly floors): %d/%d lines = %.1f%%   scripts=%d" % (qc, qt, 100.0 * qc / qt if qt else 100.0, len(qa_rows)))
    if outj:
        json.dump({"total_pct": pct, "covered": tc, "lines": tt, "scripts": [{"file": r[0], "lang": r[1], "hit": r[2], "lines": r[3]} for r in rows]}, open(outj, "w"), indent=1)
    if minp is not None and pct < minp:
        print("BELOW --min %.1f" % minp)
        sys.exit(1)


if __name__ == "__main__":
    main()
