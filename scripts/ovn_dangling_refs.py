#!/usr/bin/env python3
"""ovn_dangling_refs.py - which functions did a commit DELETE that something still CALLS?

Why (2026-10-18, xlite 'reverted(build-break)' x2 at 21:32Z / 22:04Z, the 27B 'delete dead TurnManager helpers' item): the commit removed
get_phase_name() while get_phase_summary() (deleted only by a LATER item) still called it. Godot reports ONE parse error per script, so the BUILD-GATE
fix-up saw 'Function get_phase_name() not found' only, restored that single function, re-verified, hit the NEXT missing name
('Could not resolve class TurnManager'), and the cycle was reverted after ~45 min of GUT runs. Seven helpers were deleted; the model was told one at a time.
This lists EVERY deleted function that is still referenced, with the deleted source, so the fix-up can restore them in one edit.

usage: ovn_dangling_refs.py check <repo_dir> <before_ref> <after_ref> [--source]
stdout: one line per dangling name:  DANGLING <TAB> name <TAB> file:line (first remaining reference) <TAB> n_refs
        with --source, after the DANGLING lines: '### <name> (<file>)' followed by the deleted definition verbatim (from <before_ref>).
exit 0 = nothing dangling, 1 = dangling names found, 2 = could not analyse (callers fail open).
A name is NOT dangling when a definition of it still exists anywhere in <after_ref> (moved / renamed / re-added). Comment-only references do not count.
Languages: GDScript (.gd) and Python (.py). Read-only git."""
import re
import subprocess
import sys

DEF = {
    ".gd": re.compile(r"^-\s*(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\("),
    ".py": re.compile(r"^-\s*(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\("),
}
DEF_ANY = {   # Python-re form; git_pat() derives the POSIX form (`git grep -E` on macOS/BSD has no \s)
    ".gd": r"^\s*(static\s+)?func\s+%s\s*\(",
    ".py": r"^\s*(async\s+)?def\s+%s\s*\(",
}


def git_pat(ext, name):
    return (DEF_ANY[ext] % re.escape(name)).replace(r"\s", "[[:space:]]")
MAX_NAMES = 12
MAX_SRC_LINES = 40


def git(repo, *args, ok=(0,)):
    p = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True, errors="replace")
    if p.returncode not in ok:
        raise RuntimeError("git %s: %s" % (" ".join(args[:2]), p.stderr.strip()[:200]))
    return p.stdout


def removed_defs(repo, before, after):
    """[(ext, name, path)] for every function definition line removed between before..after (.gd / .py)."""
    out = git(repo, "diff", "-U0", "--no-color", "--diff-filter=M", before + ".." + after, "--", "*.gd", "*.py")
    res, path = [], None
    for ln in out.splitlines():
        if ln.startswith("+++ b/"):
            path = ln[6:]
        elif ln.startswith("-") and not ln.startswith("---") and path:
            ext = "." + path.rsplit(".", 1)[-1]
            m = DEF.get(ext) and DEF[ext].match(ln)
            if m:
                res.append((ext, m.group(1), path))
    seen, uniq = set(), []
    for t in res:
        if (t[1], t[2]) not in seen:
            seen.add((t[1], t[2]))
            uniq.append(t)
    return uniq


def still_defined(repo, after, ext, name):
    out = git(repo, "grep", "-n", "-E", git_pat(ext, name), after, "--", "*" + ext, ok=(0, 1))
    return bool(out.strip())


def live_refs(repo, after, name):
    """[(path, line, text)] of non-comment references to `name(` / `.name` / `name` calls in .gd/.py at <after>."""
    out = git(repo, "grep", "-n", "-w", "-I", name, after, "--", "*.gd", "*.py", ok=(0, 1))
    refs = []
    for ln in out.splitlines():
        parts = ln.split(":", 3)   # "<ref>:<path>:<line>:<text>"
        if len(parts) < 4:
            continue
        text = parts[3]
        if text.lstrip().startswith("#"):
            continue
        refs.append((parts[1], parts[2], text.strip()))
    return refs


def deleted_source(repo, before, ext, name, path):
    """The definition of `name` as it was at <before>: from its def line up to (not including) the next def at the same or lower indent."""
    try:
        src = git(repo, "show", "%s:%s" % (before, path)).splitlines()
    except RuntimeError:
        return ""
    pat = re.compile(DEF_ANY[ext] % re.escape(name))
    for i, l in enumerate(src):
        if pat.match(l):
            ind = len(l) - len(l.lstrip())
            start = i
            while start > 0 and src[start - 1].lstrip().startswith(("#", "##", "@")) and (len(src[start - 1]) - len(src[start - 1].lstrip())) == ind:
                start -= 1
            j = i + 1
            while j < len(src):
                s = src[j]
                if s.strip() and (len(s) - len(s.lstrip())) <= ind and not s.lstrip().startswith(")"):
                    break   # next def / doc comment / any statement at the same or lower indent ends this definition
                j += 1
            while j > i + 1 and not src[j - 1].strip():
                j -= 1
            return "\n".join(src[start:j][:MAX_SRC_LINES])
    return ""


def check(repo, before, after):
    dangling = []
    for ext, name, path in removed_defs(repo, before, after):
        if still_defined(repo, after, ext, name):
            continue
        refs = live_refs(repo, after, name)
        if refs:
            dangling.append((ext, name, path, refs))
        if len(dangling) >= MAX_NAMES:
            break
    return dangling


def main(argv):
    if len(argv) < 5 or argv[1] != "check":
        sys.stderr.write(__doc__)
        return 2
    repo, before, after = argv[2], argv[3], argv[4]
    want_src = "--source" in argv[5:]
    try:
        d = check(repo, before, after)
        for ext, name, path, refs in d:
            print("DANGLING\t%s\t%s:%s\t%d" % (name, refs[0][0], refs[0][1], len(refs)))
        if want_src:
            for ext, name, path, refs in d:
                s = deleted_source(repo, before, ext, name, path)
                if s:
                    print("### %s (%s)\n%s" % (name, path, s))
    except Exception as e:   # noqa: BLE001 - fail open by contract
        sys.stderr.write("ovn_dangling_refs: %s\n" % e)
        return 2
    return 1 if d else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
