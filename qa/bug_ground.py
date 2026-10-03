#!/usr/bin/env python3
"""bug_ground.py - grounding helpers for the staged runner on MANUAL-TEST BUG items (2026-10-03, A8; branch qa/h11-bug-pipeline).

Why: of 6 staged bug runs after the bug-first deploy, none landed. Every one died at the independent full-verify on a Kotlin compile/KSP error the
model introduced: a NEW file re-declaring a type that already exists (GroupedCategories.kt vs CategoryModels.kt, DiscoverModels.kt vs ChickadeeApi.kt),
invented members (Stream(sourceId=...)), and a test library that is not a dependency (mockito-kotlin). The model never saw the real definitions.

Subcommands (all read-only on the repo; stdout is what the runner appends to a prompt; EVERY failure is silent + empty => the old behaviour):
  dupes        --wt W                  new/added .kt files in worktree W whose top-level type already exists elsewhere in the same package
                                       -> a re-prompt text with the REAL definition ('' when nothing is duplicated)
  kotlin-ctx   --wt W --files "a b" --text T [--desc D]   real data/enum/sealed class definitions of the types the step names + the module's
                                       testImplementation lines, for a step that edits a Kotlin test ('' otherwise)
  filter-steps [--drop-file F]         stdin: JSON array of steps -> stdout: the same without vacuous steps ('no change required', 'nothing to change').
                                       The number dropped is written to F.
  brief-id     --ovn D --feat F        the manual_notes entry id when the bug is still OPEN and has never been briefed ('' otherwise)
  plan-save    --file P --plan-json J  persist the first plan (atomic);  plan-load --file P [--max-age-h N]  -> the saved plan or ''
Kill switch: the runner only calls this when OVN_BUG_FIRST != off.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

CAP_CHARS = 5200
MAX_DEFS = 6
MAX_DEF_LINES = 32
VACUOUS_STEP_RE = re.compile(
    r"\bno\s+(?:code\s+|source\s+|further\s+|additional\s+|other\s+|production\s+)?(?:change|changes|modification|modifications|edit|edits|update|updates)\b[^.]{0,40}"
    r"\b(?:required|needed|necessary)\b|\bnothing\s+(?:to\s+(?:change|do|fix|modify)|needs?\s+to\s+change)\b|"
    r"\bno\s+changes?\s+(?:is|are)\s+(?:required|needed)\b",
    re.I)
KT_DECL_RE = re.compile(
    r"^(?P<mods>(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|protected|data|sealed|enum|open|abstract|annotation|inline|value|fun)\s+)*)"
    r"(?P<kind>class|object|interface|typealias)\s+(?P<name>[A-Za-z_]\w*)")
KT_PKG_RE = re.compile(r"^\s*package\s+([\w.]+)", re.M)
TEST_DEP_RE = re.compile(r"(?:^|\s)(?:testImplementation|androidTestImplementation|testRuntimeOnly|testCompileOnly|kaptTest|kspTest|debugImplementation)\b")


def _git(wt, *args, timeout=40):
    try:
        p = subprocess.run(["git", "-C", wt] + list(args), capture_output=True, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except Exception:  # noqa: BLE001
        return 1, ""


def kt_decls(text):
    """-> [(name, kind, mods, line_no)] of the TOP-LEVEL (column 0) declarations of a Kotlin source."""
    out = []
    for i, ln in enumerate(text.split("\n"), 1):
        if not ln or ln[0] in " \t/*":
            continue
        m = KT_DECL_RE.match(ln)
        if m:
            out.append((m.group("name"), m.group("kind"), m.group("mods") or "", i))
    return out


def pkg_of(text):
    m = KT_PKG_RE.search(text or "")
    return m.group(1) if m else ""


def definition_block(text, line_no, max_lines=MAX_DEF_LINES):
    """The declaration starting at 1-based line_no up to its closing paren / brace (bounded)."""
    lines = text.split("\n")
    start = line_no - 1
    depth, seen, out = 0, False, []
    for ln in lines[start:start + max_lines]:
        out.append(ln)
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', ln.split("//")[0])
        for ch in code:
            if ch in "({":
                depth += 1
                seen = True
            elif ch in ")}":
                depth -= 1
        if seen and depth <= 0:
            # a data class `(...)` may be followed by a `{` body or `: Parent` - stop at the closing of the primary constructor
            if ln.rstrip().endswith("{"):
                continue
            break
        if not seen and not ln.rstrip().endswith(("(", ",", "{")):
            break
    return "\n".join(out).rstrip()


def _new_kt_files(wt):
    rc, out = _git(wt, "status", "--porcelain", "-uall")
    if rc != 0:
        return []
    files = []
    for ln in out.split("\n"):
        if len(ln) > 3 and (ln.startswith("??") or ln[0] == "A") and ln[3:].strip().endswith(".kt"):
            files.append(ln[3:].strip().strip('"'))
    return files


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def _src_root(path):
    """module + source set prefix, e.g. app/src/main/ (everything before the package dirs)."""
    m = re.match(r"(.*?/src/[^/]+/)", path)
    return m.group(1) if m else ""


def cmd_dupes(args):
    wt = args.wt
    msgs = []
    for nf in _new_kt_files(wt):
        text = _read(os.path.join(wt, nf))
        pkg = pkg_of(text)
        dups = []
        for name, kind, mods, _ln in kt_decls(text):
            if "private" in mods.split():
                continue
            rc, out = _git(wt, "grep", "-n", "-E", r"^[^/*]*\b(class|object|interface|typealias)[[:space:]]+%s\b" % re.escape(name), "HEAD", "--", "*.kt")
            for hit in out.split("\n"):
                m = re.match(r"HEAD:(.+?):(\d+):(.*)$", hit)
                if not m or m.group(1) == nf:
                    continue
                if _src_root(m.group(1)) != _src_root(nf):
                    continue          # other module / source set (main vs test): not a redeclaration
                other = _git(wt, "show", "HEAD:%s" % m.group(1))[1]
                if pkg_of(other) != pkg:
                    continue          # same simple name in another package is legal Kotlin
                if not any(n == name and ln == int(m.group(2)) for n, _k, _m, ln in kt_decls(other)):
                    continue          # indented/nested declaration (Outer.Name) is legal
                dups.append((name, m.group(1), int(m.group(2)), other))
                break
        if not dups:
            continue
        lines = ["REJECTED: the new file %s declares type(s) that ALREADY EXIST in package %s (Kotlin 'Redeclaration' - the build breaks):" % (nf, pkg or "(default)")]
        for name, path, ln, other in dups:
            lines.append("- %s is already declared in %s:%d. Its REAL definition:\n%s" % (name, path, ln, definition_block(other, ln)))
        lines.append("Do NOT create %s. Edit the EXISTING file(s) above (add members there if truly needed) and use the types exactly as defined." % nf)
        msgs.append("\n".join(lines))
    sys.stdout.write("\n\n".join(msgs)[:CAP_CHARS * 2])
    return 0


def _is_kt_test(path):
    return path.endswith(".kt") and bool(re.search(r"(^|/)src/(test|androidTest)/|Tests?\.kt$", path))


def _data_class_index(wt):
    """name -> (path, line) of the data / enum / sealed class declarations of the tree (HEAD)."""
    rc, out = _git(wt, "grep", "-n", "-E", r"^[[:space:]]*(data|enum|sealed)[[:space:]]+class[[:space:]]+[A-Z][A-Za-z0-9_]*", "HEAD", "--", "*.kt", timeout=60)
    idx = {}
    if rc != 0:
        return idx
    for hit in out.split("\n"):
        m = re.match(r"HEAD:(.+?):(\d+):\s*(?:\w+\s+)*?(?:data|enum|sealed)\s+class\s+([A-Z]\w*)", hit)
        if m and "/src/test/" not in m.group(1) and "/src/androidTest/" not in m.group(1):
            idx.setdefault(m.group(3), (m.group(1), int(m.group(2))))
    return idx


def gradle_test_lines(wt, path):
    d = os.path.dirname(os.path.join(wt, path))
    wt_abs = os.path.abspath(wt)
    while True:
        for n in ("build.gradle.kts", "build.gradle"):
            f = os.path.join(d, n)
            if os.path.isfile(f):
                lines = [l.strip() for l in _read(f).split("\n") if TEST_DEP_RE.search(l) and not l.strip().startswith("//")]
                return os.path.relpath(f, wt_abs), lines
        if os.path.abspath(d) == wt_abs or not d.startswith(wt_abs):
            return "", []
        d = os.path.dirname(d)


def cmd_kotlin_ctx(args):
    wt = args.wt
    files = [f for f in (args.files or "").split() if f]
    kt = [f for f in files if f.endswith(".kt")]
    # is it a TEST step? a test file among the step's files, or the step's own desc says so (the ITEM text always says 'write a failing test', so it must not count)
    if not kt or not any(_is_kt_test(f) or re.search(r"\btests?\b", args.desc or "", re.I) for f in kt):
        return 0
    idx = _data_class_index(wt)
    if not idx:
        return 0
    names = []
    for n in re.findall(r"\b[A-Z][A-Za-z0-9]{3,}\b", args.text or ""):
        if n in idx and n not in names:
            names.append(n)
    for f in kt:                                    # types the named SOURCE file(s) use (the test will construct / compare them)
        if _is_kt_test(f):
            continue
        body = _read(os.path.join(wt, f))
        for n in re.findall(r"\b[A-Z][A-Za-z0-9]{3,}\b", body):
            if n in idx and n not in names:
                names.append(n)
    parts, total = [], 0
    for n in names[:MAX_DEFS]:
        path, ln = idx[n]
        blk = definition_block(_git(wt, "show", "HEAD:%s" % path)[1], ln)
        part = "// %s:%d\n%s" % (path, ln, blk)
        if total + len(part) > CAP_CHARS:
            break
        parts.append(part)
        total += len(part)
    out = []
    if parts:
        out.append("REAL definitions of the types this test touches - use EXACTLY these constructors / members / enum entries, never invent a parameter or a constant:\n" + "\n\n".join(parts))
    tf = next((f for f in kt if _is_kt_test(f)), kt[0])
    gf, deps = gradle_test_lines(wt, tf)
    if deps:
        out.append("Test dependencies this module really has (%s): use ONLY these libraries in the test (anything else, e.g. mockito-kotlin or io.mockk, does not resolve and breaks the build unless listed):\n%s"
                   % (gf, "\n".join(deps[:16])))
    sys.stdout.write("\n\n".join(out)[:CAP_CHARS + 1200])
    return 0


def is_vacuous_step(step):
    """Vacuous only when the 'no change required' phrase IS the step (short desc, phrase at its start);
    a real step that merely mentions 'no production change needed' is kept."""
    d = re.sub(r"^\W*(?:step\s*\d*\W*)?(?:(?:ok|note|done|n/a)\W+)?", "", str(step.get("desc", "")).strip(), flags=re.I)
    if len(d) > 100:
        return False
    m = VACUOUS_STEP_RE.search(d)
    return bool(m) and m.start() <= 3


def cmd_filter_steps(args):
    raw = sys.stdin.buffer.read().decode("utf-8", "replace")
    try:
        steps = json.loads(raw)
        if not isinstance(steps, list):
            raise ValueError
    except Exception:  # noqa: BLE001
        sys.stdout.write(raw)
        return 0
    keep = [s for s in steps if not (isinstance(s, dict) and is_vacuous_step(s))]
    if args.drop_file:
        try:
            with open(args.drop_file, "w") as fh:
                fh.write(str(len(steps) - len(keep)))
        except OSError:
            pass
    sys.stdout.write(json.dumps(keep))
    return 0


def cmd_brief_id(args):
    try:
        st = json.load(open(os.path.join(args.ovn, "state", "manual_notes.json")))
    except Exception:  # noqa: BLE001
        return 0
    for k, e in (st.get("entries") or {}).items():
        if e.get("feat") == args.feat and e.get("status") == "open":
            if (e.get("brief") or {}).get("status") in ("done", "fallback", "skipped", "running"):
                return 0
            sys.stdout.write(k)
            return 0
    return 0


def cmd_plan_save(args):
    try:
        plan = json.loads(args.plan_json)
        if not isinstance(plan, list) or not plan:
            return 0
        os.makedirs(os.path.dirname(os.path.abspath(args.file)), exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".plan.", dir=os.path.dirname(os.path.abspath(args.file)))
        with os.fdopen(fd, "w") as fh:
            json.dump({"saved": time.time(), "plan": plan}, fh)
        os.replace(tmp, args.file)
    except Exception:  # noqa: BLE001
        pass
    return 0


def cmd_plan_load(args):
    try:
        d = json.load(open(args.file))
        if time.time() - float(d.get("saved", 0)) > args.max_age_h * 3600:
            return 0
        plan = d.get("plan")
        if isinstance(plan, list) and plan and all(isinstance(s, dict) and s.get("desc") for s in plan):
            sys.stdout.write(json.dumps(plan))
    except Exception:  # noqa: BLE001
        pass
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("dupes")
    d.add_argument("--wt", required=True)
    k = sub.add_parser("kotlin-ctx")
    k.add_argument("--wt", required=True)
    k.add_argument("--files", default="")
    k.add_argument("--text", default="")
    k.add_argument("--desc", default="")
    f = sub.add_parser("filter-steps")
    f.add_argument("--drop-file", default="")
    b = sub.add_parser("brief-id")
    b.add_argument("--ovn", required=True)
    b.add_argument("--feat", required=True)
    ps = sub.add_parser("plan-save")
    ps.add_argument("--file", required=True)
    ps.add_argument("--plan-json", required=True)
    pl = sub.add_parser("plan-load")
    pl.add_argument("--file", required=True)
    pl.add_argument("--max-age-h", type=float, default=36.0)
    a = ap.parse_args(argv)
    try:
        return {"dupes": cmd_dupes, "kotlin-ctx": cmd_kotlin_ctx, "filter-steps": cmd_filter_steps, "brief-id": cmd_brief_id,
                "plan-save": cmd_plan_save, "plan-load": cmd_plan_load}[a.cmd](a)
    except Exception as ex:  # noqa: BLE001 - grounding is advisory: never break the runner
        sys.stderr.write("bug_ground: %s: %s\n" % (type(ex).__name__, ex))
        return 0


if __name__ == "__main__":
    sys.exit(main())
