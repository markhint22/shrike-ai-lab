#!/usr/bin/env python3
"""Regression tests for dedupe_gd_duplicate_functions.py (top-level script,
not under scripts/). Run: python3 test_dedupe_gd_duplicate_functions.py
(exit 0 = all pass). No pytest dependency - matches test_helpers.py style.
"""
import os, sys, subprocess, tempfile, shutil

ROOT = os.environ.get("OVN_ROOT", os.path.expanduser("~/overnight-queue"))
SCRIPT = os.path.join(ROOT, "dedupe_gd_duplicate_functions.py")

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


def test_removes_interleaved_byte_identical_duplicates():
    """Mirrors the real xlite TurnManager incident cited in the script's
    docstring: fn_a, fn_b, fn_a-again, fn_b-again (interleaved, not
    back-to-back) - both duplicates must be dropped, first occurrences and
    everything else preserved verbatim."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "turn_manager.gd")
        original = (
            "extends Node\n"
            "class_name TurnManager\n"
            "\n"
            "func get_phase_display_name():\n"
            "\treturn \"Setup\"\n"
            "\n"
            "func advance_turn():\n"
            "\tturn += 1\n"
            "\n"
            "func get_phase_display_name():\n"
            "\treturn \"Setup\"\n"
            "\n"
            "func advance_turn():\n"
            "\tturn += 1\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        ok("reports removed dup names", "removed duplicate(s):" in res.stdout, res.stdout)
        ok("reports get_phase_display_name removed",
           "get_phase_display_name" in res.stdout, res.stdout)
        ok("reports advance_turn removed", "advance_turn" in res.stdout, res.stdout)
        result = open(path).read()
        ok("only one get_phase_display_name remains",
           result.count("func get_phase_display_name()") == 1, result)
        ok("only one advance_turn remains",
           result.count("func advance_turn()") == 1, result)
        ok("preamble (extends/class_name) preserved",
           result.startswith("extends Node\nclass_name TurnManager\n"), result)
        ok("kept body text intact",
           'return "Setup"' in result and "turn += 1" in result, result)
        expected = (
            "extends Node\n"
            "class_name TurnManager\n"
            "\n"
            "func get_phase_display_name():\n"
            "\treturn \"Setup\"\n"
            "\n"
            "func advance_turn():\n"
            "\tturn += 1\n"
        )
        ok("exact expected output", result == expected, result)
    finally:
        shutil.rmtree(d)


def test_no_duplicates_file_untouched():
    """Regression guard: a file with no duplicate function names at all must
    come out byte-for-byte identical - a false-positive dedup here would
    silently corrupt someone's real, non-duplicated code."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "clean.gd")
        original = (
            "extends Node\n"
            "\n"
            "func fn_a():\n"
            "\treturn 1\n"
            "\n"
            "func fn_b():\n"
            "\treturn 2\n"
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
    """A real semantic conflict (same name, different body) must never be
    auto-resolved - both occurrences stay untouched, unlike a byte-identical
    duplicate."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "conflict.gd")
        original = (
            "func fn_a():\n"
            "\treturn 1\n"
            "\n"
            "func fn_a():\n"
            "\treturn 2\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        result = open(path).read()
        ok("conflicting bodies both kept (unchanged)", result == original, result)
        ok("prints unchanged for conflict case", res.stdout.strip() == "unchanged", res.stdout)
    finally:
        shutil.rmtree(d)


def test_annotation_preceded_duplicate_does_not_orphan_annotation():
    """Regression guard (2026-09-10 fix): DOC_RE only recognized `##`
    doc-comments as belonging to the following func, not GDScript annotations
    like `@rpc(...)`. A duplicate func preceded by an annotation used to leave
    the annotation behind (orphaned, invalid GDScript) when the duplicate was
    dropped - the annotation line was attributed to the PRECEDING kept unit's
    trailing gap instead of the unit it actually decorates. Confirmed live
    before the fix with this exact interleaved input."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "annotated.gd")
        original = (
            '@rpc("any_peer")\n'
            "func foo():\n"
            "\tpass\n"
            "func bar():\n"
            "\tpass\n"
            '@rpc("any_peer")\n'
            "func foo():\n"
            "\tpass\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        result = open(path).read()
        ok("reports removed duplicate", "removed duplicate(s): foo" in res.stdout, res.stdout)
        ok("no orphaned annotation left behind", result.count('@rpc("any_peer")') == 1, result)
        ok("only one copy of foo remains", result.count("func foo():") == 1, result)
        ok("bar() preserved", "func bar():\n\tpass" in result, result)
        ok("annotation stays paired with foo, not dangling",
           result == '@rpc("any_peer")\nfunc foo():\n\tpass\nfunc bar():\n\tpass\n', result)
    finally:
        shutil.rmtree(d)


if __name__ == "__main__":
    for t in (test_removes_interleaved_byte_identical_duplicates,
              test_no_duplicates_file_untouched,
              test_same_name_different_body_left_alone,
              test_annotation_preceded_duplicate_does_not_orphan_annotation):
        print("== %s ==" % t.__name__)
        t()
    print("\ndedupe_gd_duplicate_functions: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
