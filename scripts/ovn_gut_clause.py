#!/usr/bin/env python3
"""scripts/ovn_gut_clause.py - make a Godot GUT VERIFY clause RUNNABLE (R14 verify package, 2026-10-12, xlite X2 / platform P3).

The planner / decomposer writes GUT clauses in shapes GUT 9.4 cannot execute (all reproduced on the box with a scratch project):
  `-gdir=tests/test_x.gd`                a FILE passed to -gdir: "[ERROR]: The path [tests/test_x.gd] does not exist."
  `-gdir=tests -gtest=test_x.gd`         a bare file name: "Could not find script: test_x.gd", then the WHOLE suite runs (rc 0)
  `-gselect=<function name>`             -gselect matches script FILE names only: "Could not find script matching <name>"
The harness refused to credit (correct) but never repaired the clause, so landed work was re-attempted every cycle (~64% of xlite cycle time).

  normalize(cmd, fs) -> (new_cmd, [note, ...])
      1. `-gdir=<p>.gd`            -> `-gtest=res://<p>.gd` (the file entry leaves -gdir; a -gdir that also names real directories keeps them; run time: only when the file exists)
      2. `-gtest=<bare>.gd`        -> `-gtest=res://<d>/<bare>.gd` when `-gdir=<d>` holds it, else the UNIQUE tracked file with that basename; ambiguous / missing: left as is
         (a -gdir naming the directory of a resolved file is dropped: -gtest narrows the run)
      3. `-gselect=<X>`            -> `-gunit_test_name=<X>` when -gtest names one existing file, X is not part of any test script's basename and the file defines X
  Only a command that calls gut_cmdln is touched; the result is idempotent. `fs` is any object with exists(rel) / by_basename(name) -> [rel] / any_basename_contains(sub) / read(rel).

CLI (used by lib_verify_clause.sh _verify_normalize_gut):  python3 ovn_gut_clause.py normalize <dir>   (command on stdin, normalised command on stdout; any error: input unchanged)
"""
import os
import re
import subprocess
import sys

_SKIP_DIRS = {"addons", ".git", ".godot", "node_modules", ".venv", "__pycache__"}
_GDIR = re.compile(r"(?<!\S)-gdir=(\S+)")
_GTEST = re.compile(r"(?<!\S)-gtest=(\S+)")
_GSELECT = re.compile(r"(?<!\S)-gselect=(\S+)")


def _unq(v):
    return v.strip().strip("\"'")


def _strip_res(p):
    p = _unq(p)
    return p[len("res://"):] if p.startswith("res://") else p


class NullFS:
    """No repository: only the context-free rewrite (1) can apply."""
    def exists(self, rel):
        return False

    def by_basename(self, name):
        return []

    def any_basename_contains(self, sub):
        return False

    def read(self, rel):
        return None


class DirFS:
    """A checked-out tree. `base` is the project root the clause runs from."""
    def __init__(self, base="."):
        self.base = base
        self._files = None

    def _all(self):
        if self._files is None:
            out = []
            for dp, dns, fns in os.walk(self.base, followlinks=False):
                dns[:] = [d for d in dns if d not in _SKIP_DIRS]
                rel = os.path.relpath(dp, self.base)
                if rel.count(os.sep) > 6:
                    dns[:] = []
                for n in fns:
                    if n.endswith(".gd"):
                        out.append(n if rel == "." else os.path.join(rel, n))
            self._files = out
        return self._files

    def exists(self, rel):
        return os.path.isfile(os.path.join(self.base, rel))

    def by_basename(self, name):
        return [f for f in self._all() if os.path.basename(f) == name]

    def any_basename_contains(self, sub):
        return any(sub in os.path.basename(f) for f in self._all())

    def read(self, rel):
        try:
            with open(os.path.join(self.base, rel), encoding="utf-8", errors="replace") as f:
                return f.read()
        except OSError:
            return None


class CtxFS:
    """A spec_rules.Ctx (repo at a ref)."""
    def __init__(self, ctx):
        self.ctx = ctx

    def _tree(self):
        return [t for t in self.ctx.tree() if t.endswith(".gd") and t.split("/")[0] not in _SKIP_DIRS]

    def exists(self, rel):
        return rel in self.ctx.tree()

    def by_basename(self, name):
        return [t for t in self._tree() if os.path.basename(t) == name]

    def any_basename_contains(self, sub):
        return any(sub in os.path.basename(t) for t in self._tree())

    def read(self, rel):
        return self.ctx.show(rel)


def is_gut(cmd):
    return "gut_cmdln" in cmd


def _replace_tok(cmd, m, new):
    """Replace the token matched by m (or drop it when new is empty, taking one preceding space)."""
    if new:
        return cmd[:m.start()] + new + cmd[m.end():]
    s = m.start()
    if s > 0 and cmd[s - 1] == " ":
        s -= 1
    return cmd[:s] + cmd[m.end():]


def normalize(cmd, fs=None, require_exists=True):
    """require_exists: rewrite 1 only for a file that exists in `fs` (run time: a missing file keeps failing as 'GUT target missing'); False at ingest (R16: the item may create the file)."""
    fs = fs or NullFS()
    notes = []
    if not cmd or not is_gut(cmd):
        return cmd, notes
    c = cmd
    # ---- 1. -gdir=<file>.gd -> -gtest=res://<file>.gd
    md = _GDIR.search(c)
    moved = []
    if md:
        ents = [e for e in _unq(md.group(1)).split(",") if e]
        isf = [e for e in ents if _strip_res(e).endswith(".gd") and (fs.exists(_strip_res(e)) or not require_exists)]
        keep = [e for e in ents if e not in isf]
        moved = ["res://" + _strip_res(e) for e in isf]
        if moved:
            c = _replace_tok(c, md, ("-gdir=" + ",".join(keep)) if keep else "")
            notes.append("gdir-file->gtest")
    mt = _GTEST.search(c)
    gtests = [e for e in _unq(mt.group(1)).split(",") if e] if mt else []
    for p in moved:
        if p not in gtests:
            gtests.append(p)
    # ---- 2. bare -gtest=<name>.gd -> res://<path>
    md2 = _GDIR.search(c)
    dirs = [_strip_res(e).rstrip("/") for e in _unq(md2.group(1)).split(",") if e] if md2 else []
    resolved_dirs = set()
    new_gtests = []
    for e in gtests:
        s = _strip_res(e)
        if s.endswith(".gd") and "/" not in s:
            hit = None
            for d in dirs:
                if fs.exists(d + "/" + s):
                    hit = d + "/" + s
                    break
            if hit is None:
                cands = fs.by_basename(s)
                if len(cands) == 1:
                    hit = cands[0]
            if hit:
                new_gtests.append("res://" + hit)
                resolved_dirs.add(os.path.dirname(hit))
                notes.append("gtest-bare->path")
                continue
            notes.append("gtest-bare-unresolved")
        new_gtests.append(e)
    if new_gtests != [e for e in (_unq(mt.group(1)).split(",") if mt else []) if e] or moved:
        val = ",".join(new_gtests)
        if mt:
            c = _replace_tok(c, mt, "-gtest=" + val)
        elif val:
            c = re.sub(r"(gut_cmdln\.gd)", r"\1 -gtest=" + val.replace("\\", "\\\\"), c, count=1)
        # a -gdir naming the directory of a resolved file is dropped: -gtest narrows the run
        md3 = _GDIR.search(c)
        if md3 and resolved_dirs:
            ents = [e for e in _unq(md3.group(1)).split(",") if e]
            keep = [e for e in ents if _strip_res(e).rstrip("/") not in resolved_dirs]
            if len(keep) != len(ents):
                c = _replace_tok(c, md3, ("-gdir=" + ",".join(keep)) if keep else "")
    # ---- 3. -gselect=<function> -> -gunit_test_name=<function>
    ms = _GSELECT.search(c)
    mt = _GTEST.search(c)
    if ms and mt:
        files = [e for e in _unq(mt.group(1)).split(",") if e]
        x = _unq(ms.group(1))
        if len(files) == 1 and x and not fs.any_basename_contains(x):
            body = fs.read(_strip_res(files[0]))
            if body is not None and x in body and "-gunit_test_name" not in c:
                c = _replace_tok(c, ms, "-gunit_test_name=" + x)
                notes.append("gselect-function->gunit_test_name")
    return c, notes


def main(argv):
    if len(argv) == 3 and argv[1] == "normalize":
        cmd = sys.stdin.read().rstrip("\n")
        try:
            out, _ = normalize(cmd, DirFS(argv[2]))
        except Exception:  # noqa: BLE001 - any failure: the command unchanged
            out = cmd
        sys.stdout.write(out)
        return 0
    sys.stderr.write("usage: ovn_gut_clause.py normalize <project_dir>   (command on stdin)\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
