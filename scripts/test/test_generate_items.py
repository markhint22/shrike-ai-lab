#!/usr/bin/env python3
"""Regression tests for scripts/ovn_generate_items.py.
Run: python3 test_generate_items.py (exit 0 = all pass). No pytest dependency.

Verifies:
 - each of the 4 deterministic mechanical patterns (bare except, missing rel=noopener,
   __repr__ missing -> str, single-line __init__ missing -> None) is detected and appended.
 - FIXED BUG (2026-09-10): every generated item must carry a [T1] tier tag. All 4 patterns
   are single-line/single-file/zero-judgment by construction (the module's own docstring),
   unambiguously the simplest tier - but the generator never tagged them, so they showed up
   as tier="?" in outcome stats/ntfy digests (~66% of all fleet outcomes, fleet-wide, were
   untagged because of this one gap).
 - a file with none of the patterns generates nothing (no false positives).
 - a file already covered by an active (unchecked) item is not duplicated.
"""
import os, sys, subprocess, tempfile, shutil

ROOT = os.environ.get("OVN_ROOT", os.path.expanduser("~/overnight-queue"))
SCRIPT = os.path.join(ROOT, "scripts", "ovn_generate_items.py")

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))

def run(repo_dir, limit=15):
    return subprocess.run([sys.executable, SCRIPT, repo_dir, str(limit)], capture_output=True, text=True)


def test_bare_except_gets_t1_tag():
    d = tempfile.mkdtemp()
    try:
        with open(os.path.join(d, "foo.py"), "w") as f:
            f.write("def foo():\n    try:\n        pass\n    except:\n        pass\n")
        res = run(d)
        ok("reports GENERATED=1", "GENERATED=1" in res.stdout, res.stdout)
        prog = open(os.path.join(d, "OVERNIGHT_PROGRESS.md")).read()
        ok("item carries the [T1] tag", "[T1] [HIGH]" in prog, prog)
        ok("item still describes the bare except fix", "bare `except:`" in prog, prog)
    finally:
        shutil.rmtree(d)


def test_missing_rel_noopener_gets_t1_tag():
    d = tempfile.mkdtemp()
    try:
        with open(os.path.join(d, "page.vue"), "w") as f:
            f.write('<a href="x" target="_blank">link</a>\n')
        res = run(d)
        ok("reports GENERATED=1", "GENERATED=1" in res.stdout, res.stdout)
        prog = open(os.path.join(d, "OVERNIGHT_PROGRESS.md")).read()
        ok("item carries the [T1] tag", "[T1] [HIGH]" in prog, prog)
        ok("item describes the reverse-tabnabbing fix", "reverse-tabnabbing" in prog, prog)
    finally:
        shutil.rmtree(d)


def test_multiline_tag_with_rel_on_a_different_line_is_not_a_false_positive():
    """FIXED BUG (2026-09-10): Vue/HTML tags are routinely formatted one-attribute-
    per-line (Prettier's default style), so `rel="noopener noreferrer"` often sits on
    a DIFFERENT line than `target="_blank"` within the same tag. The old single-line
    check flagged this as missing `rel` every time, and since the item gets checked
    off (the file was already correct, so aider's edit was a no-op that still passed
    the gate) then re-detected next low-water-mark cycle, this produced the exact same
    non-issue over and over - confirmed live: one real file had this "fixed" 10
    separate times. A multi-line tag that DOES have `rel=` anywhere in its span must
    generate nothing."""
    d = tempfile.mkdtemp()
    try:
        with open(os.path.join(d, "link.vue"), "w") as f:
            f.write(
                "<template>\n"
                "  <a\n"
                "    :href=\"url\"\n"
                "    target=\"_blank\"\n"
                "    rel=\"noopener noreferrer\"\n"
                "  >\n"
                "    link\n"
                "  </a>\n"
                "</template>\n"
            )
        res = run(d)
        ok("a multi-line tag with rel= elsewhere in the tag generates nothing", "GENERATED=0" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(d)


def test_multiline_tag_genuinely_missing_rel_is_still_caught():
    """The fix for the false-positive above must not blind the detector to a REAL
    multi-line miss - a tag spanning several lines with target="_blank" and no rel=
    anywhere in it must still be flagged."""
    d = tempfile.mkdtemp()
    try:
        with open(os.path.join(d, "link.vue"), "w") as f:
            f.write(
                "<template>\n"
                "  <a\n"
                "    :href=\"url\"\n"
                "    target=\"_blank\"\n"
                "  >\n"
                "    link\n"
                "  </a>\n"
                "</template>\n"
            )
        res = run(d)
        ok("a genuinely rel-less multi-line tag is still caught", "GENERATED=1" in res.stdout, res.stdout)
        prog = open(os.path.join(d, "OVERNIGHT_PROGRESS.md")).read()
        ok("item carries the [T1] tag", "[T1] [HIGH]" in prog, prog)
    finally:
        shutil.rmtree(d)


def test_repr_missing_return_type_gets_t1_tag():
    d = tempfile.mkdtemp()
    try:
        with open(os.path.join(d, "model.py"), "w") as f:
            f.write("class X:\n    def __repr__(self):\n        return 'x'\n")
        res = run(d)
        ok("reports GENERATED=1", "GENERATED=1" in res.stdout, res.stdout)
        prog = open(os.path.join(d, "OVERNIGHT_PROGRESS.md")).read()
        ok("item carries the [T1] tag", "[T1] [LOW]" in prog, prog)
    finally:
        shutil.rmtree(d)


def test_init_missing_return_type_gets_t1_tag():
    d = tempfile.mkdtemp()
    try:
        with open(os.path.join(d, "model.py"), "w") as f:
            f.write("class X:\n    def __init__(self, a):\n        self.a = a\n")
        res = run(d)
        ok("reports GENERATED=1", "GENERATED=1" in res.stdout, res.stdout)
        prog = open(os.path.join(d, "OVERNIGHT_PROGRESS.md")).read()
        ok("item carries the [T1] tag", "[T1] [LOW]" in prog, prog)
    finally:
        shutil.rmtree(d)


def test_clean_file_generates_nothing():
    d = tempfile.mkdtemp()
    try:
        with open(os.path.join(d, "clean.py"), "w") as f:
            f.write("def foo() -> None:\n    try:\n        pass\n    except Exception:\n        pass\n")
        res = run(d)
        ok("reports GENERATED=0 for a clean file", "GENERATED=0" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(d)


def test_file_with_active_item_is_not_duplicated():
    d = tempfile.mkdtemp()
    try:
        with open(os.path.join(d, "foo.py"), "w") as f:
            f.write("def foo():\n    try:\n        pass\n    except:\n        pass\n")
        with open(os.path.join(d, "OVERNIGHT_PROGRESS.md"), "w") as f:
            f.write("# Overnight Progress\n\n## Next Steps\n- [ ] [T1] [HIGH] `foo.py` (line 4): already queued.\n")
        res = run(d)
        ok("does not re-generate a second item for an already-active file", "GENERATED=0" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(d)


if __name__ == "__main__":
    for t in (test_bare_except_gets_t1_tag,
              test_missing_rel_noopener_gets_t1_tag,
              test_multiline_tag_with_rel_on_a_different_line_is_not_a_false_positive,
              test_multiline_tag_genuinely_missing_rel_is_still_caught,
              test_repr_missing_return_type_gets_t1_tag,
              test_init_missing_return_type_gets_t1_tag,
              test_clean_file_generates_nothing,
              test_file_with_active_item_is_not_duplicated):
        print("== %s ==" % t.__name__)
        t()
    print("\ngenerate_items: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
