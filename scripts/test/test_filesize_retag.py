#!/usr/bin/env python3
"""Regression tests for ovn_filesize_retag.py (lives at the overnight-queue repo root,
not under scripts/ — matches the real script's own location).
Run: python3 test_filesize_retag.py (exit 0 = all pass). No pytest dependency.

ovn_filesize_retag.py bumps a doable [T1]/[T2] item's tier to [T3] when its target file
is "large" (line count over a threshold), so it routes into the staged/architect pipeline
instead of the basic scout+implement flow (see the script's own docstring for the "why").
This file had ZERO test coverage before (flagged by ovn_pipeline_audit.sh's untested-active-
script check) despite being wired into cron (40 */4 * * *) and mutating OVERNIGHT_PROGRESS.md
in every active repo.
"""
import os, sys, subprocess, tempfile, shutil

ROOT = os.environ.get("OVN_ROOT", os.path.expanduser("~/overnight-queue"))
SCRIPT = os.path.join(ROOT, "ovn_filesize_retag.py")

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))


def _mk_repo(files):
    """files: dict of relative-path -> content. Returns the repo root dir."""
    d = tempfile.mkdtemp()
    for rel, content in files.items():
        full = os.path.join(d, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as f:
            f.write(content)
    return d


def run(prog_path, repo_root, threshold=None, max_retags=None):
    args = [sys.executable, SCRIPT, prog_path, repo_root]
    if threshold is not None:
        args.append(str(threshold))
    if max_retags is not None:
        args.append(str(max_retags))
    return subprocess.run(args, capture_output=True, text=True)


def test_t1_item_targeting_a_large_file_gets_retagged_to_t3():
    d = _mk_repo({"big.py": "\n".join(str(i) for i in range(600))})
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    with open(prog, "w") as f:
        f.write("- [ ] [T1] big.py — add a function.\n")
    try:
        res = run(prog, d)
        ok("reports RETAGGED=1", "RETAGGED=1" in res.stdout, res.stdout)
        new_content = open(prog).read()
        ok("line is now tagged T3", "[T3]" in new_content, new_content)
        ok("original T1 tag no longer present", "[T1]" not in new_content, new_content)
        ok("leaves an explanatory HTML comment", "retagged T1->T3" in new_content, new_content)
    finally:
        shutil.rmtree(d)


def test_t2_item_targeting_a_large_file_also_gets_retagged():
    d = _mk_repo({"big.py": "\n".join(str(i) for i in range(600))})
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    with open(prog, "w") as f:
        f.write("- [ ] [T2] big.py — refactor a function.\n")
    try:
        res = run(prog, d)
        ok("T2 also retags", "RETAGGED=1" in res.stdout, res.stdout)
        ok("T2 becomes T3", "[T3]" in open(prog).read())
    finally:
        shutil.rmtree(d)


def test_item_targeting_a_small_file_is_left_alone():
    d = _mk_repo({"small.py": "print('hi')\n"})
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    with open(prog, "w") as f:
        f.write("- [ ] [T1] small.py — add a function.\n")
    try:
        res = run(prog, d)
        ok("small file is not retagged", "RETAGGED=0" in res.stdout, res.stdout)
        ok("T1 tag is unchanged", "[T1]" in open(prog).read())
    finally:
        shutil.rmtree(d)


def test_already_t3_item_is_untouched():
    d = _mk_repo({"big.py": "\n".join(str(i) for i in range(600))})
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    original = "- [ ] [T3] big.py — add a function.\n"
    with open(prog, "w") as f:
        f.write(original)
    try:
        res = run(prog, d)
        ok("already-T3 item is never touched", "RETAGGED=0" in res.stdout, res.stdout)
        ok("file content is byte-identical", open(prog).read() == original)
    finally:
        shutil.rmtree(d)


def test_parked_item_is_skipped_even_if_it_targets_a_large_file():
    d = _mk_repo({"big.py": "\n".join(str(i) for i in range(600))})
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    with open(prog, "w") as f:
        f.write("- [ ] [AUTO-SKIP recovery:none] [T1] big.py — add a function.\n")
    try:
        res = run(prog, d)
        ok("AUTO-SKIP item is not retagged", "RETAGGED=0" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(d)


def test_gd_target_is_excluded_even_if_large():
    d = _mk_repo({"big.gd": "\n".join(str(i) for i in range(600))})
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    with open(prog, "w") as f:
        f.write("- [ ] [T1] big.gd — add a function.\n")
    try:
        res = run(prog, d)
        ok("godot files are never retagged (staged picker hard-excludes .gd)", "RETAGGED=0" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(d)


def test_max_retags_cap_is_respected():
    files = {"a.py": "\n".join(str(i) for i in range(600))}
    for name in ("a", "b", "c"):
        files[f"{name}.py"] = "\n".join(str(i) for i in range(600))
    d = _mk_repo(files)
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    with open(prog, "w") as f:
        f.write(
            "- [ ] [T1] a.py — item a.\n"
            "- [ ] [T1] b.py — item b.\n"
            "- [ ] [T1] c.py — item c.\n"
        )
    try:
        res = run(prog, d, threshold=500, max_retags=2)
        ok("stops at the max_retags cap", "RETAGGED=2" in res.stdout, res.stdout)
        content = open(prog).read()
        ok("exactly two lines retagged, not three", content.count("[T3]") == 2, content)
    finally:
        shutil.rmtree(d)


def test_md_path_tokens_are_never_treated_as_the_target_file():
    # The item names a .md doc alongside the real target; the .md must be skipped as a
    # candidate (module docstring / PATH_TOKEN_RE comment) even though it exists on disk.
    d = _mk_repo({
        "NOTES.md": "\n".join(str(i) for i in range(600)),  # large, but must be ignored
        "small.py": "print('hi')\n",
    })
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    with open(prog, "w") as f:
        f.write("- [ ] [T1] small.py — see NOTES.md for context.\n")
    try:
        res = run(prog, d)
        ok("a large .md mention does not trigger a retag via the real (small) target", "RETAGGED=0" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(d)


def test_nonexistent_target_file_is_skipped_without_crashing():
    d = _mk_repo({})
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    with open(prog, "w") as f:
        f.write("- [ ] [T1] does_not_exist.py — add a function.\n")
    try:
        res = run(prog, d)
        ok("missing target file does not crash", res.returncode == 0, res.stderr)
        ok("missing target file is not retagged", "RETAGGED=0" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(d)


def test_no_qualifying_items_leaves_the_file_byte_identical():
    d = _mk_repo({"small.py": "print('hi')\n"})
    prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
    original = "- [ ] [T1] small.py — add a function.\n## Some other section\n- done stuff\n"
    with open(prog, "w") as f:
        f.write(original)
    try:
        run(prog, d)
        ok("file is never rewritten when nothing qualifies", open(prog).read() == original)
    finally:
        shutil.rmtree(d)


if __name__ == "__main__":
    if not os.path.isfile(SCRIPT):
        print("  (skip: %s not present on this host)" % SCRIPT)
        print("filesize_retag: 0 passed, 0 failed")
        sys.exit(0)
    for t in (test_t1_item_targeting_a_large_file_gets_retagged_to_t3,
              test_t2_item_targeting_a_large_file_also_gets_retagged,
              test_item_targeting_a_small_file_is_left_alone,
              test_already_t3_item_is_untouched,
              test_parked_item_is_skipped_even_if_it_targets_a_large_file,
              test_gd_target_is_excluded_even_if_large,
              test_max_retags_cap_is_respected,
              test_md_path_tokens_are_never_treated_as_the_target_file,
              test_nonexistent_target_file_is_skipped_without_crashing,
              test_no_qualifying_items_leaves_the_file_byte_identical):
        print("== %s ==" % t.__name__)
        t()
    print("\nfilesize_retag: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
