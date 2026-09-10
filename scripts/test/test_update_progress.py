#!/usr/bin/env python3
"""Regression tests for update_progress.py (top-level script, not under
scripts/). It doesn't dedupe an existing file's content the way the other
three dedupe_*.py scripts do - it applies commit-message trailers
(DONE/DECISION/NEW) to OVERNIGHT_PROGRESS.md, and its OWN dedup guard is
"don't re-add an item whose normalized text already exists". These tests
exercise that guard plus the base no-op/idempotent guarantees.
Run: python3 test_update_progress.py   (exit 0 = all pass). No pytest dep -
matches test_helpers.py style.
"""
import datetime, os, sys, subprocess, tempfile, shutil

ROOT = os.environ.get("OVN_ROOT", os.path.expanduser("~/overnight-queue"))
SCRIPT = os.path.join(ROOT, "update_progress.py")
TODAY = datetime.date.today().isoformat()

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))

def run(path, commit_text):
    return subprocess.run([sys.executable, SCRIPT, path], input=commit_text,
                           capture_output=True, text=True)


def test_marks_matching_checkbox_item_done():
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "P.md")
        original = (
            "# Progress\n\n"
            "## Next Steps\n"
            "- [ ] Add input validation to the login form\n"
            "- [ ] Fix the flaky CI job\n\n"
            "## Completed\n"
            "- [x] initial scaffold\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path, "DONE: Add input validation to the login form\n")
        ok("reports marked done", "marked done:" in res.stdout, res.stdout)
        result = open(path).read()
        ok("checkbox flipped to [x] in place",
           "- [x] Add input validation to the login form" in result, result)
        ok("sibling open item untouched",
           "- [ ] Fix the flaky CI job" in result, result)
        ok("unrelated Completed section untouched",
           "- [x] initial scaffold" in result, result)
    finally:
        shutil.rmtree(d)


def test_marks_matching_numbered_item_done_with_strikethrough():
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "P.md")
        original = (
            "# Progress\n\n"
            "## Next Steps\n"
            "1. Add rate limiting to the API\n"
            "2. Fix the flaky CI job\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path, "DONE: Add rate limiting to the API\n")
        result = open(path).read()
        expected_line = "1. ~~Add rate limiting to the API~~ ✅ Done %s" % TODAY
        ok("numbered item gets strikethrough + date (preserving numbering style)",
           expected_line in result, result)
        ok("sibling numbered item untouched", "2. Fix the flaky CI job" in result, result)
    finally:
        shutil.rmtree(d)


def test_rerunning_same_done_trailer_is_idempotent():
    """Regression guard against double-marking: re-running the SAME DONE
    trailer against an already-marked-done doc must be a true no-op."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "P.md")
        original = (
            "# Progress\n\n"
            "## Next Steps\n"
            "- [ ] Add input validation to the login form\n"
        )
        with open(path, "w") as f:
            f.write(original)
        run(path, "DONE: Add input validation to the login form\n")
        after_first = open(path).read()
        res2 = run(path, "DONE: Add input validation to the login form\n")
        ok("second run reports unchanged", res2.stdout.strip() == "unchanged", res2.stdout)
        after_second = open(path).read()
        ok("file identical after re-running the same DONE trailer",
           after_first == after_second, after_second)
    finally:
        shutil.rmtree(d)


def test_new_item_dedup_skips_existing():
    """A NEW trailer whose normalized text already matches an existing Next
    Steps item must NOT be appended again (the script's own dedup guard)."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "P.md")
        original = (
            "# Progress\n\n"
            "## Next Steps\n"
            "- [ ] Fix the flaky CI job\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path, "NEW: Fix the flaky CI job\n")
        ok("prints unchanged for duplicate NEW item", res.stdout.strip() == "unchanged", res.stdout)
        result = open(path).read()
        ok("item is not duplicated", result.count("Fix the flaky CI job") == 1, result)
        ok("file byte-identical", result == original, result)
    finally:
        shutil.rmtree(d)


def test_decision_dedup_skips_existing():
    """A DECISION trailer whose normalized text already matches an existing
    Decisions Made entry must NOT be appended again."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "P.md")
        original = (
            "# Progress\n\n"
            "## Next Steps\n"
            "- [ ] todo A\n\n"
            "## Decisions Made\n"
            "- 2026-09-01: use FastAPI\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path, "DECISION: use FastAPI\n")
        ok("prints unchanged for duplicate DECISION", res.stdout.strip() == "unchanged", res.stdout)
        result = open(path).read()
        ok("decision is not duplicated", result.count("use FastAPI") == 1, result)
        ok("file byte-identical", result == original, result)
    finally:
        shutil.rmtree(d)


def test_no_trailers_leaves_file_untouched():
    """Regression guard: a commit message with no DONE/DECISION/NEW trailers
    at all must never touch the doc, however it's worded."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "P.md")
        original = (
            "# Progress\n\n"
            "## Next Steps\n"
            "- [ ] todo A\n\n"
            "## Completed\n"
            "- [x] did B\n\n"
            "## Decisions Made\n"
            "- 2026-09-01: use FastAPI\n"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path, "fix(app): unrelated bug fix, nothing to declare here\n")
        ok("prints unchanged", res.stdout.strip() == "unchanged", res.stdout)
        result = open(path).read()
        ok("file bytes are byte-identical to input", result == original, result)
    finally:
        shutil.rmtree(d)


def test_genuinely_new_item_is_appended_without_disturbing_other_content():
    """Complement to the dedup-guard tests: a truly NEW item (no normalized
    match anywhere in Next Steps) must still be appended, and every other
    line in the doc must survive untouched - a dedup guard that's too eager
    would silently drop real new work."""
    d = tempfile.mkdtemp()
    try:
        path = os.path.join(d, "P.md")
        # No trailing newline after the last Next Steps item, and Next Steps
        # is the last section - avoids an unrelated blank-line-placement
        # quirk in the insert-position logic (reported separately) so this
        # test isolates just the dedup-guard behavior under test.
        original = (
            "# Progress\n\n"
            "## Completed\n"
            "- [x] did A\n\n"
            "## Next Steps\n"
            "- [ ] todo A"
        )
        with open(path, "w") as f:
            f.write(original)
        res = run(path, "NEW: Add rate limiting to the API\n")
        ok("reports added item", "added item: Add rate limiting to the API" in res.stdout, res.stdout)
        result = open(path).read()
        ok("new item present", "- [ ] Add rate limiting to the API" in result, result)
        ok("old item preserved", "- [ ] todo A" in result, result)
        ok("Completed section untouched", "- [x] did A" in result, result)
        expected = original + "\n- [ ] Add rate limiting to the API"
        ok("exact expected output", result == expected, result)
    finally:
        shutil.rmtree(d)


if __name__ == "__main__":
    for t in (test_marks_matching_checkbox_item_done,
              test_marks_matching_numbered_item_done_with_strikethrough,
              test_rerunning_same_done_trailer_is_idempotent,
              test_new_item_dedup_skips_existing,
              test_decision_dedup_skips_existing,
              test_no_trailers_leaves_file_untouched,
              test_genuinely_new_item_is_appended_without_disturbing_other_content):
        print("== %s ==" % t.__name__)
        t()
    print("\nupdate_progress: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
