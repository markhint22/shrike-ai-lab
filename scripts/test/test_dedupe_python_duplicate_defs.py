#!/usr/bin/env python3
"""Regression tests for dedupe_python_duplicate_defs.py (top-level script,
not under scripts/). Run: python3 test_dedupe_python_duplicate_defs.py
(exit 0 = all pass). No pytest dependency - matches test_helpers.py style.
"""
import os, sys, subprocess, tempfile, shutil

ROOT = os.environ.get("OVN_ROOT", os.path.expanduser("~/overnight-queue"))
SCRIPT = os.path.join(ROOT, "dedupe_python_duplicate_defs.py")

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))

def run(path):
    return subprocess.run([sys.executable, SCRIPT, path], capture_output=True, text=True)


def test_removes_byte_identical_repeated_class():
    """Mirrors the real test-automation-agent incident cited in the script's
    docstring: a whole top-level test class re-added byte-identical two
    cycles later, with unrelated code in between. Only the later duplicate
    is dropped; everything else is preserved verbatim."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "dup_test.py")
        original = (
            "import pytest\n"
            "\n"
            "\n"
            "class TestOrchestratorExecutePhaseIntegration:\n"
            "    def test_one(self):\n"
            "        assert 1 == 1\n"
            "\n"
            "\n"
            "def helper():\n"
            "    return 42\n"
            "\n"
            "\n"
            "class TestOrchestratorExecutePhaseIntegration:\n"
            "    def test_one(self):\n"
            "        assert 1 == 1\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        ok("reports removed duplicate class",
           "removed duplicate(s): TestOrchestratorExecutePhaseIntegration" in res.stdout,
           res.stdout)
        result = open(path).read()
        ok("only one copy of the class remains",
           result.count("class TestOrchestratorExecutePhaseIntegration") == 1, result)
        ok("unrelated helper() preserved", "def helper():\n    return 42" in result, result)
        ok("result parses as valid Python", _parses(result), result)
        expected = (
            "import pytest\n"
            "\n"
            "\n"
            "class TestOrchestratorExecutePhaseIntegration:\n"
            "    def test_one(self):\n"
            "        assert 1 == 1\n"
            "\n"
            "\n"
            "def helper():\n"
            "    return 42\n"
        )
        ok("exact expected output", result == expected, result)
    finally:
        shutil.rmtree(d)


def test_no_duplicates_file_untouched():
    """Regression guard: a file with no duplicate top-level def/class names
    must come out byte-for-byte identical - a false-positive dedup here
    could silently delete real, non-duplicated production code."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "clean.py")
        original = (
            "def fn_a():\n"
            "    return 1\n"
            "\n"
            "\n"
            "def fn_b():\n"
            "    return 2\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        ok("prints unchanged", res.stdout.strip() == "unchanged", res.stdout)
        result = open(path).read()
        ok("file bytes are byte-identical to input", result == original, result)
    finally:
        shutil.rmtree(d)


def test_same_name_different_body_left_alone():
    """A genuine same-name conflict with a DIFFERENT body must never be
    auto-resolved - both occurrences stay untouched."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "conflict.py")
        original = (
            "def fn_a():\n"
            "    return 1\n"
            "\n"
            "\n"
            "def fn_a():\n"
            "    return 2\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        result = open(path).read()
        ok("conflicting bodies both kept (unchanged)", result == original, result)
        ok("prints unchanged for conflict case", res.stdout.strip() == "unchanged", res.stdout)
    finally:
        shutil.rmtree(d)


def test_indented_duplicate_methods_are_out_of_scope():
    """The script only targets column-0 (unindented) class/def lines by
    design (documented limitation). Two duplicate METHODS indented inside a
    single top-level class must be left alone - the whole file has only one
    top-level unit ('class A'), so there is nothing to compare."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "indented.py")
        original = (
            "class A:\n"
            "    def foo(self):\n"
            "        return 1\n"
            "\n"
            "    def foo(self):\n"
            "        return 1\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        result = open(path).read()
        ok("prints unchanged for indented-only dup", res.stdout.strip() == "unchanged", res.stdout)
        ok("file untouched", result == original, result)
    finally:
        shutil.rmtree(d)


def test_decorated_duplicate_does_not_orphan_decorator():
    """Regression guard (2026-09-10 fix): a duplicate def/class preceded by a
    decorator used to leave the decorator behind (orphaned, invalid syntax)
    when the duplicate was dropped, because find_units() didn't attribute the
    decorator line to the unit it modifies - the gap-preservation walk in
    dedupe() always keeps content between units regardless of keep/drop.
    Confirmed live before the fix: this exact input produced a dangling
    `@decorator` and ast.parse raised SyntaxError."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "decorated.py")
        original = (
            "@decorator\n"
            "def foo():\n"
            "    return 1\n"
            "\n"
            "\n"
            "def bar():\n"
            "    return 2\n"
            "\n"
            "\n"
            "@decorator\n"
            "def foo():\n"
            "    return 1\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        result = open(path).read()
        ok("reports removed duplicate", "removed duplicate(s): foo" in res.stdout, res.stdout)
        ok("no orphaned decorator left behind", result.count("@decorator") == 1, result)
        ok("only one copy of foo remains", result.count("def foo():") == 1, result)
        ok("bar() preserved", "def bar():\n    return 2" in result, result)
        ok("result parses as valid Python (was SyntaxError before the fix)", _parses(result), result)
    finally:
        shutil.rmtree(d)


def _parses(src):
    import ast
    try:
        ast.parse(src)
        return True
    except SyntaxError:
        return False


if __name__ == "__main__":
    for t in (test_removes_byte_identical_repeated_class,
              test_no_duplicates_file_untouched,
              test_same_name_different_body_left_alone,
              test_indented_duplicate_methods_are_out_of_scope,
              test_decorated_duplicate_does_not_orphan_decorator):
        print("== %s ==" % t.__name__)
        t()
    print("\ndedupe_python_duplicate_defs: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
