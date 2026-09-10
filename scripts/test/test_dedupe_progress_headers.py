#!/usr/bin/env python3
"""Regression tests for dedupe_progress_headers.py (top-level script, not
under scripts/). Run: python3 test_dedupe_progress_headers.py (exit 0 = all
pass). No pytest dependency - matches test_helpers.py style.
"""
import os, sys, subprocess, tempfile, shutil

ROOT = os.environ.get("OVN_ROOT", os.path.expanduser("~/overnight-queue"))
SCRIPT = os.path.join(ROOT, "dedupe_progress_headers.py")

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


def test_merges_duplicate_header_sections():
    """The cited real-world case: xlite's OVERNIGHT_PROGRESS.md accumulates
    a second '## Decisions Made' header lower in the file. Both sections'
    content must be merged into ONE section, in first-seen order, with
    unrelated sections left in place."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "OVERNIGHT_PROGRESS.md")
        original = (
            "# Progress\n"
            "\n"
            "## Decisions Made\n"
            "- Decided X\n"
            "\n"
            "## Completed\n"
            "- did A\n"
            "\n"
            "## Decisions Made\n"
            "- Decided Y\n"
            "\n"
            "## Next Steps\n"
            "- [ ] todo 1\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        ok("reports merged headers", "merged headers: Decisions Made" in res.stdout, res.stdout)
        result = open(path).read()
        ok("only one Decisions Made header remains",
           result.count("## Decisions Made") == 1, result)
        ok("both decisions' content present and merged in order",
           "- Decided X\n- Decided Y" in result, result)
        ok("Completed section preserved", "## Completed\n- did A" in result, result)
        ok("Next Steps section preserved", "## Next Steps\n- [ ] todo 1" in result, result)
    finally:
        shutil.rmtree(d)


def test_collapses_non_adjacent_duplicate_bullets():
    """dedupe_bullets() explicitly compares every bullet block to every
    EARLIER one in the file (its own docstring: 'not just the immediately
    adjacent one'), so a duplicate separated by unrelated bullets must still
    be collapsed. (Note: the top-of-file module docstring claims bullets are
    only collapsed when 'directly ADJACENT' - that description is stale;
    this test locks in the actual, non-adjacent behavior implemented in
    dedupe_bullets().)"""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "prog.md")
        original = (
            "# P\n"
            "\n"
            "## Completed\n"
            "- did A\n"
            "- did B\n"
            "- did C\n"
            "- did A\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        ok("reports collapsed bullet count",
           "collapsed 1 duplicate bullet line(s)" in res.stdout, res.stdout)
        result = open(path).read()
        expected = (
            "# P\n"
            "\n"
            "## Completed\n"
            "- did A\n"
            "- did B\n"
            "- did C\n"
        )
        ok("exact expected output (later dup dropped, others intact)",
           result == expected, result)
    finally:
        shutil.rmtree(d)


def test_no_duplicates_file_untouched():
    """Regression guard: a doc with unique headers and unique bullets must
    come out byte-for-byte identical - false-positive merging/collapsing
    here would corrupt a human-curated progress doc."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "clean.md")
        original = (
            "# Progress\n"
            "\n"
            "## Decisions Made\n"
            "- Decided X\n"
            "\n"
            "## Completed\n"
            "- did A\n"
            "- did B\n"
            "\n"
            "## Next Steps\n"
            "- [ ] todo 1\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        ok("prints unchanged", res.stdout.strip() == "unchanged", res.stdout)
        result = open(path).read()
        ok("file bytes are byte-identical to input", result == original, result)
    finally:
        shutil.rmtree(d)


def test_similar_but_not_identical_bullets_not_collapsed():
    """Two bullets that are merely similar (not byte-identical) must NOT be
    treated as duplicates - matching is strict byte-equality per the
    script's own docstring."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "similar.md")
        original = (
            "# P\n"
            "\n"
            "## Completed\n"
            "- did A (part 1)\n"
            "- did A (part 2)\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path)
        result = open(path).read()
        ok("prints unchanged for merely-similar bullets",
           res.stdout.strip() == "unchanged", res.stdout)
        ok("file untouched for merely-similar bullets", result == original, result)
    finally:
        shutil.rmtree(d)


if __name__ == "__main__":
    for t in (test_merges_duplicate_header_sections,
              test_collapses_non_adjacent_duplicate_bullets,
              test_no_duplicates_file_untouched,
              test_similar_but_not_identical_bullets_not_collapsed):
        print("== %s ==" % t.__name__)
        t()
    print("\ndedupe_progress_headers: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
