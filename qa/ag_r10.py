#!/usr/bin/env python3
"""ag_r10.py - 2026-10-10 audit-driven rules for gate_antigaming.py (package qagate). Imported by gate_antigaming.check(); never executes repo code,
only `git grep/show` on refs. Every rule is isolated: an internal error or a deadline becomes a note, never a finding and never a crash.

  E_GD_TEST_NOT_GUT   FLAG  a changed/new GDScript test file (test_*.gd / *_test.gd / has `func test_`) that GUT would silently ignore: no
                            `extends GutTest` (directly or through a project base class) or no `func test_*`. GUT logs 'Ignoring script ... does not
                            extend GutTest' and still exits 0, so the tests never run (xlite carried 4 such files 10-04..10-10).
  A_TESTFILE_EMPTIED  FLAG  (FAIL only when the gate mode `antigaming_testfiles` = enforce) a changed/new gd/py test file that ends with ZERO test
                            functions although it had some before (an aider 'remove duplicate' / 'revert to placeholder' emptied it), or a NEW test
                            file with none (harness stub that was never filled). Would have blocked xlite df1de23 and iptv 2dbbc4b2.
  D_UNREFERENCED_FUNC FLAG  a NEW `func` / `static func` in non-test GDScript (private ones too) whose name appears nowhere else in the repo at head
                            (tests, scenes, docs, other files, the same commit all count as references). xlite damage.gd carried two such helpers
                            (coerce_to_array, simulate_single_load) invented by the 27B decomposer.

The FAIL severities (A_TESTFILE_EMPTIED here, E_TEST_NOT_COLLECTED for NEW files in ag_h13) are armed by the SEPARATE gate mode
`antigaming_testfiles` (qa/qa_enforce.sh antigaming_testfiles enforce | env OVN_QA_ANTIGAMING_TESTFILES). Default shadow => FLAG. Like
`antigaming_frozen` this is a second key: a FAIL blocks a merge prefix only when BOTH `antigaming` and `antigaming_testfiles` are enforce.
"""
import ast
import os
import re
import time

import qa_common as qc

TESTFILES_MODE_GATE = "antigaming_testfiles"
GD_VIRTUALS = {"_ready", "_process", "_physics_process", "_input", "_unhandled_input", "_unhandled_key_input", "_gui_input", "_draw",
               "_enter_tree", "_exit_tree", "_notification", "_init", "_to_string", "_get", "_set", "_get_property_list", "_validate_property",
               "_property_can_revert", "_property_get_revert", "_get_configuration_warnings", "_shortcut_input", "_integrate_forces",
               "_can_drop_data", "_drop_data", "_get_drag_data", "_make_custom_tooltip", "_has_point", "_get_minimum_size", "_run",
               "_get_tooltip", "_clips_input", "_structured_text_parser", "_input_event", "_mouse_enter", "_mouse_exit", "_static_init",
               "_get_allowed_size_flags_horizontal", "_get_allowed_size_flags_vertical", "_physics_process", "_update_pixels", "_get_import_options"}
DEF_GD_FUNC = re.compile(r"^[ \t]*(?:static[ \t]+)?func[ \t]+([A-Za-z_]\w*)[ \t]*\(")
GUT_EXTENDS_PATH = re.compile(r"""^["']res://addons/gut/test\.gd["']$""")
CAP_UNREF = 10


def testfiles_mode():
    """off | shadow | enforce for the NEW FAIL severities of the test-file rules (a second key on top of the shared `antigaming` flip)."""
    return qc.mode(TESTFILES_MODE_GATE)


def testfiles_sev(status):
    """E_TEST_NOT_COLLECTED: FAIL only for a NEW file (status A) and only when `antigaming_testfiles` is enforce; everything else is FLAG."""
    return "FAIL" if (status == "A" and testfiles_mode() == "enforce") else "FLAG"


def emptied_sev():
    """A_TESTFILE_EMPTIED: FAIL (new, edited or renamed file alike) only when `antigaming_testfiles` is enforce, else FLAG."""
    return "FAIL" if testfiles_mode() == "enforce" else "FLAG"


def _ga():
    import gate_antigaming as ga
    return ga


def _F(rule, sev, path, line, msg, text=""):
    return _ga().F(rule, sev, path, line, msg, text)


def _is_gd_testy(path, txt):
    """A GDScript file that is (meant to be) a test: GUT prefix/suffix name, or it declares func test_*. Helpers under tests/ are not."""
    base = os.path.basename(path)
    return base.startswith("test_") or base.endswith("_test.gd") or re.search(r"^[ \t]*func[ \t]+test_\w*[ \t]*\(", txt or "", re.M) is not None


def _gd_masked(txt):
    return _ga().mask_text(txt, "gd")


def count_gd_tests(txt):
    return len(re.findall(r"^[ \t]*func[ \t]+test_\w*[ \t]*\(", _gd_masked(txt), re.M))


def count_py_tests(txt):
    """Test functions in a python module (any nesting: methods of Test* classes count). None when the module does not parse."""
    try:
        tree = ast.parse(txt)
    except (SyntaxError, ValueError, RecursionError):
        return None
    return sum(1 for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test"))


def _extends_target(txt):
    """The first top-level `extends X` target of a GDScript file (X without a trailing comment), or None when there is none."""
    for ln in _gd_masked(txt).split("\n"):
        m = re.match(r"^extends[ \t]+(.+?)[ \t]*$", ln)
        if m:
            # masked text blanked string contents: re-read the same line from the original to see the path
            orig = [l for l in txt.split("\n") if re.match(r"^extends[ \t]+", l)]
            raw = orig[0] if orig else ln
            raw = re.sub(r"[ \t]*#.*$", "", raw)
            return re.sub(r"^extends[ \t]+", "", raw).strip()
    return None


def extends_gut(repo, txt, depth=0, seen=None):
    """True when the script extends GutTest directly or through a project base class (res:// path or class_name), resolved at head."""
    tgt = _extends_target(txt)
    if tgt is None:
        return False
    if tgt == "GutTest" or GUT_EXTENDS_PATH.match(tgt):
        return True
    if depth >= 4:
        return True   # unresolvable depth: do not guess a defect
    seen = seen if seen is not None else set()
    if tgt in seen:
        return False
    seen.add(tgt)
    m = re.match(r"""^["']res://(.+?)["']$""", tgt)
    if m:
        base_txt = repo.blob(repo.head, m.group(1))
        return extends_gut(repo, base_txt, depth + 1, seen) if base_txt is not None else True   # a missing/oversize file: unknown, no flag
    ident = tgt.split(".")[0]
    if not re.match(r"^[A-Za-z_]\w*$", ident):
        return True
    rc, out, _ = qc.git(repo.rd, "grep", "-I", "-l", "-E", "-e", r"^class_name[[:space:]]+%s([^A-Za-z0-9_]|$)" % ident, repo.head, "--", "*.gd", timeout=30)
    if rc == 0 and out.strip():
        path = out.strip().splitlines()[0].split(":", 1)[-1]
        base_txt = repo.blob(repo.head, path)
        return extends_gut(repo, base_txt, depth + 1, seen) if base_txt is not None else True
    return False   # an engine class (Node, RefCounted ...) or an unknown name: GUT will not run it


# ---------------------------------------------------------------------------------------------------------------- A_TESTFILE_EMPTIED / E_GD_TEST_NOT_GUT
def rule_test_files(repo, status, diffs, out, notes):
    ga = _ga()
    emptied = set()
    for path, st in sorted(status.items()):
        if st not in ("A", "M", "R"):
            continue
        lang = ga.lang_of(path)
        if lang not in ("gd", "py") or not ga.is_test_path(path) or ga.ignorable(path) or "addons/" in path:
            continue
        base = os.path.basename(path)
        if lang == "py" and (base == "conftest.py" or not (base.startswith("test_") or base.endswith("_test.py"))):
            continue
        txt = repo.blob(repo.head, path)
        if txt is None:
            continue
        if lang == "gd" and not _is_gd_testy(path, txt) and st != "A":
            # an edited helper file under tests/: only a file that WAS a test can be emptied (handled below via the old text)
            old_txt = repo.blob(repo.base, (diffs.get(path).old if diffs.get(path) and diffs[path].old else path)) or ""
            if not _is_gd_testy(path, old_txt):
                continue
        n_new = count_gd_tests(txt) if lang == "gd" else count_py_tests(txt)
        if n_new is None:
            notes.append("test-file rule: %s unparsable, skipped" % path)
            continue
        if n_new == 0:
            old_n = 0
            if st in ("M", "R"):
                oldp = (diffs.get(path).old if diffs.get(path) and diffs[path].old else path)
                otxt = repo.blob(repo.base, oldp)
                if otxt is None:
                    continue
                old_n = count_gd_tests(otxt) if lang == "gd" else (count_py_tests(otxt) or 0)
                if old_n == 0:
                    continue   # already had no tests: pre-existing, not caused by this diff
            why = ("test file had %d test function(s) and now has none (emptied instead of deleted or fixed)" % old_n) if old_n else \
                  "new test file contains no test function (placeholder / stub that was never filled in)"
            out.append(_F("A_TESTFILE_EMPTIED", emptied_sev(), path, 1, why, os.path.basename(path)))
            emptied.add(path)
            continue
        if lang == "gd" and path not in emptied and not extends_gut(repo, txt):
            # the new-file case is already E_TEST_NOT_COLLECTED ('does not extend GutTest'); do not report the same file twice
            if any(f["file"] == path and f["rule"] == "E_TEST_NOT_COLLECTED" for f in out):
                continue
            out.append(_F("E_GD_TEST_NOT_GUT", "FLAG", path, 1, "GDScript test has %d `func test_` but does not extend GutTest: GUT ignores the whole file "
                          "('Ignoring script ... does not extend GutTest') and exits 0, so it never runs" % n_new, os.path.basename(path)))
    # a changed test file whose `func test_` exist but that does not extend GutTest is covered above; a file with no `func test_` and no extends is
    # the A_TESTFILE_EMPTIED branch (n_new == 0). Files that are non-test helpers (no test_ name, no func test_) are never looked at.


# ---------------------------------------------------------------------------------------------------------------- D_UNREFERENCED_FUNC
def _added_funcs(txt, added_lines):
    out = []
    for i, ln in enumerate(txt.split("\n"), 1):
        m = DEF_GD_FUNC.match(ln)
        if m and i in added_lines:
            out.append((m.group(1), i))
    return out


def rule_unreferenced_func(repo, status, diffs, out, deadline):
    ga = _ga()
    cands = []
    for path, st in sorted(status.items()):
        if st not in ("A", "M", "R") or ga.lang_of(path) != "gd" or ga.is_test_path(path) or ga.ignorable(path) or path not in diffs:
            continue
        if "addons" in path.split("/"):
            continue
        txt = repo.blob(repo.head, path)
        if txt is None:
            continue
        lines = txt.split("\n")
        old = repo.blob(repo.base, diffs[path].old or path) if st in ("M", "R") else None
        old_names = {m.group(1) for ln in (old or "").split("\n") for m in [DEF_GD_FUNC.match(ln)] if m}
        added = {n for n, _ in diffs[path].added}
        for name, ln in _added_funcs(txt, added):
            if name in old_names or name.startswith("test_") or name in GD_VIRTUALS or (name.startswith("__") and name.endswith("__")):
                continue
            if ln >= 2 and lines[ln - 2].lstrip().startswith("@"):
                continue   # annotated (@rpc, @warning_ignore ...): reachable by a mechanism other than a plain call
            cands.append((path, name, ln))
    if not cands:
        return
    n_flag = 0
    seen = set()
    for path, name, ln in cands:
        if n_flag >= CAP_UNREF or time.time() > deadline:
            break
        if name in seen:
            continue
        seen.add(name)
        if any(f["rule"] == "D_DEAD_SYMBOL" and f["file"] == path and f["snip"].endswith(" " + name) for f in out):
            continue   # already reported as a public symbol with no production caller
        rc, hits, _ = qc.git(repo.rd, "grep", "-I", "-n", "-w", "-e", name, repo.head, "--", timeout=40)
        if rc not in (0, 1):
            continue   # git grep could not run: unknown, never flag
        referenced = False
        pre = repo.head + ":"
        for h in hits.splitlines():
            h = h[len(pre):] if h.startswith(pre) else h
            parts = h.split(":", 2)
            if len(parts) < 3 or not parts[1].isdigit():
                continue
            hp, hl, ht = parts[0], int(parts[1]), parts[2]
            if hp == path and hl == ln:
                continue   # its own definition line
            if hp.endswith(".gd") and re.match(r"\s*#", ht):
                continue   # a comment is not a use
            referenced = True
            break
        if not referenced:
            out.append(_F("D_UNREFERENCED_FUNC", "FLAG", path, ln, "new func %s is referenced nowhere in the repo (no caller, test, scene or string use): "
                          "dead helper - put helpers in the file that uses them, or wire it in the same change" % name, "func %s" % name))
            n_flag += 1


def run_all(repo, repo_name, status, st_raw, diffs, findings, notes, deadline, no_record):
    steps = [("test_files", lambda: rule_test_files(repo, status, diffs, findings, notes)),
             ("unreferenced_func", lambda: rule_unreferenced_func(repo, status, diffs, findings, deadline))]
    for name, fn in steps:
        if time.time() > deadline:
            notes.append("r10 rules skipped from %s (deadline)" % name)
            break
        try:
            fn()
        except Exception as ex:  # noqa: BLE001 - a rule bug must never change the verdict
            notes.append("r10 rule %s errored: %s: %s" % (name, type(ex).__name__, str(ex)[:80]))
