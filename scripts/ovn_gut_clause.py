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
  0. (intake package, 2026-10-13; xlite night F4 / platform P8) shapes that can never RUN at all, repaired BEFORE the three rewrites above:
     a. `cd /path/to/<repo>[/<sub>] && cmd`   the model copied a placeholder from its prompt; the cd always fails ("No such file or directory", 27+ FAIL rows in one night). The cd is dropped
                                              (`cd <sub> &&` when the placeholder names a sub directory: the first component after /path/to/ is the repo name). Any command, not only GUT.
     b. `[cd D &&] godot [--headless] -s <test>.gd`   a GUT test (extends GutTest) is not a SceneTree script: "Could not find base class GutTest" / "doesn't inherit from SceneTree". The clause becomes
                                              `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://<D>/<test>.gd -gexit`. Only for a TEST path whose file (when it exists) is not a SceneTree/MainLoop script,
                                              in a project that carries addons/gut, when D is not itself a godot project directory, and when the godot call is the last command of the clause.
                                              Left UNCHANGED when anything else rides on the call: `--path`, `||`, a pipe or any flag other than --headless/--quiet/-q (rewriting would change what the clause
                                              tests); `--filter <fn>` (a bare function name) becomes `-gunit_test_name=<fn>`.
     c. `-gexit 0`                            GUT rejects the stray positional ("Unknown arguments: [\"0\"]"): the number is dropped.
  Only a command that calls gut_cmdln (or has one of the shapes above) is touched; the result is idempotent. `fs` is any object with exists(rel) / by_basename(name) -> [rel] / any_basename_contains(sub) / read(rel).

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
    """No repository: only the context-free rewrite (1) can apply (and the shape repairs of step 0, which then ASSUME a GUT project)."""
    def exists(self, rel):
        return False

    def gut_project(self):
        return True

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

    def gut_project(self):
        return self.exists("addons/gut/gut_cmdln.gd")

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

    def gut_project(self):
        return "addons/gut/gut_cmdln.gd" in self.ctx.tree()

    def by_basename(self, name):
        return [t for t in self._tree() if os.path.basename(t) == name]

    def any_basename_contains(self, sub):
        return any(sub in os.path.basename(t) for t in self._tree())

    def read(self, rel):
        return self.ctx.show(rel)


def is_gut(cmd):
    return "gut_cmdln" in cmd


_GODOT_SCRIPT_ANY = re.compile(r"godot[^;&|]*\s(?:-s|--script)[\s=]")


def needs_normalize(cmd):
    """True when `cmd` is a shape normalize() may rewrite: a GUT runner call, a /path/to/ placeholder, or a `godot -s <script>` call (callers use this to skip the work for anything else)."""
    return bool(cmd) and ("gut_cmdln" in cmd or "/path/to/" in cmd or bool(_GODOT_SCRIPT_ANY.search(cmd)))


# ---- step 0: shapes that cannot run at all (intake package, 2026-10-13)
_PLACEHOLDER_CD = re.compile(r"(^|[;&|(]\s*)cd\s+[\"']?/path/to/([^\s&;|\"']*)[\"']?\s*(?:&&|;)\s*")
_TESTPATH = re.compile(r"(^|/)(tests?|__tests__)/|(^|/)test_[^/]*$|_test\.[a-z]+$")
_SCENE_TREE = re.compile(r"^\s*extends\s+(?:SceneTree|MainLoop)\b", re.M)
_SEG_SPLIT = re.compile(r"(\s*&&\s*|\s*;\s*)")
_GODOT_S = re.compile(r"^(?P<bin>\S*godot[\w.-]*)(?P<flags>(?:\s+\S+)*?)\s+(?:-s|--script)(?:=|\s+)(?P<script>[\"']?\S+?\.gd[\"']?)(?P<rest>(?:\s+\S+)*)\s*$")
_GODOT_OK_FLAGS = ("--headless", "--quiet", "-q")
_FILTER_FN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_GEXIT_JUNK = re.compile(r"(?<!\S)(-gexit)\s+\d+(?=\s|$)")


def _strip_placeholder_cd(c, notes):
    def one(m):
        parts = m.group(2).strip("/").split("/", 1)       # the first component after /path/to/ is the repo name, a deeper one is a real sub directory
        sub = parts[1] if len(parts) > 1 else ""
        return m.group(1) + (("cd %s && " % sub) if sub else "")
    new = _PLACEHOLDER_CD.sub(one, c)
    if new != c:
        notes.append("placeholder-cd")
    return new


def _godot_script_to_gut(c, fs, notes):
    """`[cd D &&] godot [flags] -s <test>.gd` -> `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://<D>/<test>.gd -gexit` (see the module docstring, 0b). Unchanged on any doubt."""
    parts = _SEG_SPLIT.split(c)
    segs = parts[0::2]
    m = _GODOT_S.match(segs[-1].strip())
    if not m:
        return c
    # Only a call whose every other argument is understood is rewritten: dropping `--path <dir>`, `|| true` (the very thing that made the clause always pass), a pipe or an unknown flag would
    # silently change what the clause tests. `--filter <fn>` / `--filter=<fn>` (a bare function name) maps onto GUT's -gunit_test_name; anything else leaves the command unchanged.
    if any(f not in _GODOT_OK_FLAGS for f in m.group("flags").split()):
        return c
    unit = None
    rest = m.group("rest").split()
    while rest:
        t = rest.pop(0)
        mf = re.match(r"^--filter=(.+)$", t)
        val = mf.group(1) if mf else (rest.pop(0) if t == "--filter" and rest else None)
        if val is None or unit is not None or not _FILTER_FN.match(val):
            return c
        unit = val
    script = _unq(m.group("script"))
    base = os.path.basename(script)
    rel = _strip_res(script)
    if rel.startswith("./"):
        rel = rel[2:]
    if base in ("gut_cmdln.gd", "gut_cli.gd") or rel.startswith("addons/"):
        return c
    cwd = ""
    for seg in segs[:-1]:                                   # every command before the godot call must be a plain relative `cd`
        mc = re.match(r"^cd\s+(?:--\s+)?[\"']?([^\s\"']+)[\"']?$", seg.strip())
        if not mc or mc.group(1).startswith(("/", "~", "$", "-")):
            return c
        cwd = os.path.normpath(os.path.join(cwd, mc.group(1))) if cwd else os.path.normpath(mc.group(1))
        if cwd.startswith(".."):
            return c
    if cwd == ".":
        cwd = ""
    if cwd and fs.exists(cwd + "/project.godot"):           # the cd target is itself the godot project: the project root is not where the runner lives
        return c
    joined = os.path.normpath(os.path.join(cwd, rel)) if cwd else os.path.normpath(rel)
    chosen = body = None
    for cand in dict.fromkeys((joined, os.path.normpath(rel))):
        if fs.exists(cand):
            chosen, body = cand, fs.read(cand)
            break
    if chosen is None:                                      # the item may create the file: judge by its path alone
        if not _TESTPATH.search(joined) or not fs.gut_project():
            return c
        same = fs.by_basename(base)
        chosen = same[0] if len(same) == 1 else joined
    elif not _TESTPATH.search(chosen) or (body is not None and _SCENE_TREE.search(body)) or not fs.gut_project():
        return c
    notes.append("godot-script->gut")
    return "%s --headless -s addons/gut/gut_cmdln.gd -gtest=res://%s -gexit%s" % (m.group("bin"), chosen, (" -gunit_test_name=" + unit) if unit else "")


def _replace_tok(cmd, m, new):
    """Replace the token matched by m (or drop it when new is empty, taking one preceding space)."""
    if new:
        return cmd[:m.start()] + new + cmd[m.end():]
    s = m.start()
    if s > 0 and cmd[s - 1] == " ":
        s -= 1
    return cmd[:s] + cmd[m.end():]


def normalize(cmd, fs=None, require_exists=True, repair_script=True):
    """require_exists: rewrite 1 only for a file that exists in `fs` (run time: a missing file keeps failing as 'GUT target missing'); False at ingest (R16: the item may create the file).
    repair_script: step 0b (`godot -s <GutTest>.gd` -> the gut_cmdln form). The spec rule R16 passes False: R13 owns that shape at ingest (it QUARANTINES a GUT test run as a script, and a
    repair here would hide it from R13); the run-time normaliser and the recovery lint repair it."""
    fs = fs or NullFS()
    notes = []
    if not cmd or not needs_normalize(cmd):
        return cmd, notes
    c = _strip_placeholder_cd(cmd, notes)
    if repair_script:
        c = _godot_script_to_gut(c, fs, notes)
    if is_gut(c) and _GEXIT_JUNK.search(c):
        c = _GEXIT_JUNK.sub(r"\1", c)
        notes.append("gexit-junk-arg")
    if not is_gut(c):
        return c, notes
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
