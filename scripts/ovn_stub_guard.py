#!/usr/bin/env python3
"""ovn_stub_guard.py - guards for run_overnight.sh's pre-scout "stub new source file" step (r11 package stub).

The step writes a one-line placeholder for the first source path named by the item and commits it, so aider only has to EDIT a file (a brand-new
file's udiff is unreliable on this model). 2026-10-11 showed four defects, all fixed here (deterministic, no model call):

  pick    <repo> [--text-file F]   choose the path to stub (item text on stdin or F). Prints ONE line:
              PICK<TAB><path>               stub this path
              SKIP<TAB><reason><TAB><path>  a guard refused the path (reason below); the caller stubs nothing
              NONE                          nothing to stub (no source path in the text, or it already exists)
          Guards, in order (first hit wins):
              unsafe-path            absolute path or a '..' component (never create files outside the repo)
              sibling-longer-ext     a file in the same directory differs only by a longer trailing extension (build.gradle.kts vs the
                                     truncated build.gradle.kt)
              deleted-in-history     `git log --diff-filter=D -1 -- <path>` is non-empty and the path is absent at HEAD: an earlier commit
                                     deleted it on purpose, re-creating it made HEAD red (xlite scripts/battle/save_manager.gd, 6 cycles)
              out-of-scope:<dir>     the repo's AGENTS.md declares <dir>/ out of scope (iptv-android/, iptv-ios/ ...); an unparsable or
                                     missing AGENTS.md declares nothing
              bare-basename          the path has no directory ('in_range.gd' from prose) and a tracked file of that name exists in a subdirectory:
                                     stubbing would create a junk copy at the repo root (xlite in_range.gd / scatter.gd)
              new-dir-lookalike      (2026-10-13, SHADOW by default: OVN_STUB_NEWDIR_GUARD=enforce|shadow|off) the path's first directory that does not exist yet
                                     repeats its parent's name (exactly or within edit distance 2) while the collapsed path exists (`iptv-backend/iptv-backend/tests/` with
                                     `iptv-backend/tests/` present; `app/routers/outers/`), or is within edit distance 2 of an existing sibling directory (`servces/` vs
                                     `services/`): a mis-resolved / typo'd path. Stubbing it created 3 stray tests nothing collected (iptv 10-09). In shadow the
                                     would-be refusal is only written to logs/stub_guard.log. Logic shared with qa/ag_n2.py (judge); the guard is skipped when that file is absent.
              asserts-absent         the path ITSELF is said to be absent: "does not exist"/"is deleted" directly after it (a test asserting the
                                     file is gone). A create item that only mentions a missing thing further on in its description is NOT refused.
          The extraction itself has a RIGHT boundary: '.kts' no longer truncates to '.kt' (the junk iptv-android/app/build.gradle.kt that
          reached prod main), '.pyi' to '.py', '.gdshader' to '.gd'. The full token (letters, digits, _ . / -) must END in the extension.

  undo    <repo> <pre_sha> <stub_sha> <path> [branch] [task_log]
          Called from the cycle subshell's EXIT trap, i.e. on EVERY exit path (scout BLOCKED, no-op, revert, push...). If this cycle's stub is
          still in HEAD and still only the placeholder (the implement step never filled it) it is removed: `git reset --hard <pre_sha>` when
          the stub commit is the unpushed tip and the tree is clean, else a `git rm` + one small commit (pushed fast-forward only when the
          stub already reached origin). Never touches a file the implement step wrote, and never removes a stub that a source file ADDED this
          cycle (pre_sha..HEAD) references (preload/import/class name: removing the placeholder would turn the gated HEAD red). A tracked
          <path>.uid sidecar (Godot) is removed with the stub, an untracked one is deleted. OVN_STUB_UNDO=off disables.

  scan    <repo> [--rev REV]       list leaked placeholder-only source files (whole content = the placeholder marker, nothing else).
              SOURCE<TAB><path>   non-test source file (the branch_hygiene FLAG)
              TEST<TAB><path>     test file (informational: needs a human/Claude decision)
          Read-only. Exit 0 always (a flag is not a failure); `--rev` reads the tree of a git rev instead of the working tree.

Fail-safe everywhere: any internal error = print nothing / change nothing and exit 0 (the caller then stubs nothing / flags nothing).
"""
import os
import re
import subprocess
import sys

EXTS = ("tsx", "ts", "gd", "py", "vue", "kt", "swift")
MARKER_RE = re.compile(r"Placeholder - the implement step fills (?:this )?in")
# boilerplate lines of the generated stubs (run_overnight.sh stub case statement) besides the marker line itself
_BOILER = {
    "export {}",
    "import { describe, it } from 'vitest'",
    "describe.skip('placeholder until the implement step fills it in', () => {",
    "it('placeholder', () => {})",
    "})",
    "<template><div /></template>",
    '"""',
}
_COMMENT_ONLY = re.compile(r"^(?:#|//|/\*|\*|<!--|\"\"\")?\s*$")
_ABSENT_RE = re.compile(
    r"(?:(?:now|still|already|really|actually|currently)\s+)?(?:\bdo(?:es)?\s*n[o']t\s+exist|\bdo(?:es)?\s+not\s+exist|\bshould\s+not\s+exist|\bmust\s+not\s+exist|\bwill\s+not\s+exist"
    r"|\bno\s+longer\s+exists?|\bnot\s+exist|\bis\s+(?:absent|deleted|removed|gone)\b|\bbeen\s+(?:deleted|removed)\b"
    r"|\bwas\s+(?:deleted|removed)\b|\bshould\s+be\s+(?:absent|gone)\b)(?!\s+yet)",
    re.I,
)


def _git(repo, *args, timeout=30):
    try:
        r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except Exception:
        return 99, ""


# ---------------------------------------------------------------------------------------------------------------- pick
def candidates(text):
    """[(path, start, end)] for every whitespace/punctuation-delimited token whose WHOLE text ends in a source extension."""
    out = []
    for m in re.finditer(r"[A-Za-z0-9_./-]+", text):
        tok = m.group(0)
        end = m.end()
        stripped = tok.rstrip(".-/")           # sentence punctuation glued to the token ("foo.py." / "foo.py-")
        end -= len(tok) - len(stripped)
        tok = stripped
        for ext in EXTS:
            if tok.endswith("." + ext):
                stem = tok[: -(len(ext) + 1)]
                if re.search(r"[A-Za-z0-9]", stem.rsplit("/", 1)[-1]):
                    out.append((tok, m.start(), end))
                break
    return out


def _sibling_longer(repo, path):
    d, base = os.path.split(path)
    full = os.path.join(repo, d) if d else repo
    try:
        names = os.listdir(full)
    except OSError:
        return None
    for n in names:
        if n != base and n.startswith(base) and re.fullmatch(r"[A-Za-z]+", n[len(base):] or "-"):
            return n
    return None


def _bare_basename_elsewhere(repo, path):
    """A path with NO directory component whose basename is already tracked in a subdirectory: prose like 'in_range.gd' is a reference to that
       existing file, not a request for a new repo-root file. Returns the existing path, '' when none / not a bare name / git unavailable."""
    if "/" in path or not re.fullmatch(r"[A-Za-z0-9_.-]+", path):
        return ""
    rc, out = _git(repo, "ls-files", "--", ":(glob)**/" + path, timeout=30)
    if rc != 0:
        return ""
    for ln in out.splitlines():
        if ln.strip() and ln.strip() != path:
            return ln.strip()
    return ""


def _load_ag_n2():
    """qa/ag_n2.py (the gate's lookalike logic) by file path; None when it is not deployed next to scripts/ (the guard is then simply skipped)."""
    try:
        import importlib.util
        here = os.path.dirname(os.path.abspath(__file__))
        fp = os.path.join(here, "..", "qa", "ag_n2.py")
        if not os.path.isfile(fp):
            return None
        sys.path.insert(0, os.path.dirname(fp))
        spec = importlib.util.spec_from_file_location("ag_n2_stubguard", fp)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception:
        return None


def new_dir_lookalike(repo, path):
    """'' or a reason string 'doubled:<existing dir>' / 'lookalike:<existing dir>' for the first directory of `path` that does not exist in the working tree."""
    n2 = _load_ag_n2()
    if n2 is None:
        return ""
    norm = path[2:] if path.startswith("./") else path
    comps = norm.split("/")[:-1]
    for i, name in enumerate(comps):
        if os.path.isdir(os.path.join(repo, *comps[:i + 1])):
            continue
        if i > 0 and (name == comps[i - 1] or n2.lookalike(name, comps[i - 1])):
            collapsed = comps[:i] + comps[i + 1:]
            if not collapsed or os.path.isdir(os.path.join(repo, *collapsed)):
                return "doubled:" + "/".join(collapsed)
        parent = os.path.join(repo, *comps[:i])
        try:
            sibs = sorted(d for d in os.listdir(parent) if os.path.isdir(os.path.join(parent, d)))
        except OSError:
            return ""
        for sib in sibs:
            if n2.lookalike(name, sib):
                return "lookalike:" + "/".join(comps[:i] + [sib])
        return ""
    return ""


def _shadow_log(msg):
    try:
        lp = os.environ.get("OVN_STUB_GUARD_LOG") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logs", "stub_guard.log")
        os.makedirs(os.path.dirname(lp), exist_ok=True)
        import time
        with open(lp, "a") as f:
            f.write("[%s] %s\n" % (time.strftime("%F %T"), msg))
    except Exception:
        pass


def deleted_in_history(repo, path):
    rc, out = _git(repo, "log", "--diff-filter=D", "--format=%h", "-1", "--", ":(literal)" + path, timeout=30)
    return rc == 0 and out.strip() != ""


def out_of_scope_dirs(repo):
    """Directories AGENTS.md declares out of scope. Only two explicit shapes are understood; anything else declares nothing:
         `<dir>/` ... out of scope        (backticked dir(s) with a trailing slash BEFORE the phrase on the same line)
         never edit `<dir>/`              (backticked dir right after the phrase)
       A line whose clause before 'out of scope' also says 'in scope' / 'scope =' / 'only' is ambiguous and ignored."""
    try:
        with open(os.path.join(repo, "AGENTS.md"), encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return []
    dirs = []
    tok = re.compile(r"`([A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)*)/`")
    for ln in lines:
        flat = ln.replace("*", "")
        m = re.search(r"out[ -]of[ -]scope", flat, re.I)
        if m:
            before = flat[: m.start()]
            if not re.search(r"\bin scope\b|scope\s*=|\bonly\b", before, re.I):
                dirs += tok.findall(before)
        for m2 in re.finditer(r"never\s+edit\s+((?:`[^`]+`(?:\s*(?:,|and|or|\+)\s*)?)+)", flat, re.I):
            dirs += tok.findall(m2.group(1))
    out = []
    for d in dirs:
        d = d.strip("/")
        if d and d != "." and ".." not in d.split("/") and d not in out:
            out.append(d)
    return out


def pick(repo, text):
    cands = candidates(text)
    if not cands:
        return "NONE"
    path, s, e = cands[0]                      # FIRST path only (unchanged): a refused first path stubs nothing, never a later one
    if path.startswith("/") or ".." in path.split("/"):
        return "SKIP\tunsafe-path\t" + path
    if os.path.isfile(os.path.join(repo, path)):
        return "NONE"
    norm0 = path[2:] if path.startswith("./") else path
    elsewhere = _bare_basename_elsewhere(repo, norm0)
    if elsewhere:
        return "SKIP\tbare-basename:" + elsewhere + "\t" + path
    sib = _sibling_longer(repo, path)
    if sib:
        return "SKIP\tsibling-longer-ext:" + sib + "\t" + path
    if deleted_in_history(repo, path):
        return "SKIP\tdeleted-in-history\t" + path
    norm = path[2:] if path.startswith("./") else path
    ndg = os.environ.get("OVN_STUB_NEWDIR_GUARD", "shadow")
    if ndg in ("shadow", "enforce"):
        why = new_dir_lookalike(repo, path)
        if why and ndg == "enforce":
            return "SKIP\tnew-dir-" + why + "\t" + path
        if why:
            _shadow_log("%s: stub-guard SHADOW new-dir-lookalike (would refuse, stubbing anyway): %s [%s]" % (os.path.basename(os.path.abspath(repo)), path, why))
    for d in out_of_scope_dirs(repo):
        if norm == d or norm.startswith(d + "/"):
            return "SKIP\tout-of-scope:" + d + "\t" + path
    line_end = text.find("\n", e)
    after = text[e: line_end if line_end != -1 else len(text)][:120]
    after = re.split(r"[.;](?:\s|$)", after, maxsplit=1)[0]
    # the absence phrase must be ABOUT THE PATH: it has to start right after it (past closing backtick/quote/paren, an optional dash/colon/comma).
    # A create item that merely mentions a missing thing later in its description ("... returns error if the save file does not exist") stubs normally.
    after = re.sub(r"^[\s`'\")\]]*(?:[-\u2014\u2013:,]\s*)?", "", after)
    if _ABSENT_RE.match(after):
        return "SKIP\tasserts-absent\t" + path
    return "PICK\t" + path


# ---------------------------------------------------------------------------------------------------------------- placeholder detection
def is_placeholder_only(text):
    """True when the file is nothing but a generated stub: the marker plus only comment delimiters / the stub boilerplate lines."""
    if not MARKER_RE.search(text):
        return False
    for ln in text.splitlines():
        s = ln.strip()
        if not s or MARKER_RE.search(s):
            # a marker line may carry ONLY comment delimiters around the marker (never real code next to it)
            rest = MARKER_RE.sub("", s).replace(".", "")
            rest = re.sub(r'^(?:#|//|<!--|""")\s*|\s*(?:-->|""")$', "", rest).strip()
            if rest:
                # alembic variant: """Placeholder - the implement step fills in revision/down_revision/upgrade/downgrade."""
                if not re.fullmatch(r"revision/down_revision/upgrade/downgrade", rest):
                    return False
            continue
        if s in _BOILER or _COMMENT_ONLY.match(s):
            continue
        return False
    return True


def is_test_path(path):
    p = path.replace("\\", "/")
    parts = p.split("/")
    base = parts[-1]
    if any(x in ("tests", "test", "__tests__", "spec", "specs", "androidTest", "UITests") for x in parts[:-1]):
        return True
    return bool(re.search(r"(^test_|_test\.|\.test\.|\.spec\.|Tests?\.(?:kt|swift)$|Tests?\.[A-Za-z]+$)", base))


def scan(repo, rev=None):
    rows = []
    if rev:
        rc, out = _git(repo, "ls-tree", "-r", "-l", rev, timeout=60)
        if rc != 0:
            return rows
        for ln in out.splitlines():
            m = re.match(r"^\d+ blob ([0-9a-f]+)\s+(\d+)\t(.+)$", ln)
            if not m or int(m.group(2)) > 1500:
                continue
            path = m.group(3)
            if not path.endswith(tuple("." + e for e in EXTS)):
                continue
            rc2, body = _git(repo, "cat-file", "blob", m.group(1))
            if rc2 == 0 and is_placeholder_only(body):
                rows.append(("TEST" if is_test_path(path) else "SOURCE", path))
        return rows
    rc, out = _git(repo, "ls-files", "-z", timeout=60)
    if rc != 0:
        return rows
    for path in out.split("\0"):
        if not path or not path.endswith(tuple("." + e for e in EXTS)):
            continue
        fp = os.path.join(repo, path)
        try:
            if not os.path.isfile(fp) or os.path.islink(fp) or os.path.getsize(fp) > 1500:
                continue
            with open(fp, encoding="utf-8", errors="replace") as f:
                body = f.read()
        except OSError:
            continue
        if is_placeholder_only(body):
            rows.append(("TEST" if is_test_path(path) else "SOURCE", path))
    return rows


# ---------------------------------------------------------------------------------------------------------------- undo
_REF_PATHSPECS = ["*.py", "*.ts", "*.tsx", "*.js", "*.jsx", "*.mjs", "*.vue", "*.kt", "*.kts", "*.gradle", "*.swift", "*.gd", "*.tscn", "*.tres", "*.godot"]


def _added_references(repo, pre, path):
    """True when a SOURCE file touched between <pre> and HEAD adds a line that references the stub (path/basename, a python/ts import of its stem,
       a kt/swift class name). Docs (progress file, logs) are not scanned: crediting an item always mentions its path there. None = could not tell."""
    rc, out = _git(repo, "diff", "--unified=0", "--no-color", "--no-ext-diff", pre, "HEAD", "--", *_REF_PATHSPECS,
                   ":(exclude,literal)" + path, ":(exclude,literal)" + path + ".uid", timeout=60)
    if rc != 0:
        return None
    base = os.path.basename(path)
    stem, ext = os.path.splitext(base)
    q = lambda x: r"(?<![A-Za-z0-9_])" + re.escape(x) + r"(?![A-Za-z0-9_])"
    pats = [re.compile(q(base))]
    if ext == ".py":
        pats.append(re.compile(r"\b(?:from|import)\b[^\n]*" + q(stem)))
    elif ext in (".ts", ".tsx", ".vue"):
        pats.append(re.compile(r"""(?:from|import|require)\s*\(?\s*['"][^'"\n]*/""" + re.escape(stem) + r"""(?:\.[A-Za-z]+)?['"]"""))
    elif ext in (".kt", ".swift"):
        pats.append(re.compile(q(stem)))
    for ln in out.splitlines():
        if ln.startswith("+") and not ln.startswith("+++") and any(p.search(ln) for p in pats):
            return True
    return False


def _drop_uid_sidecar(repo, path):
    """Godot writes <script>.gd.uid next to a script it has seen: an untracked one is deleted with the removed stub."""
    uid = os.path.join(repo, path + ".uid")
    try:
        if os.path.isfile(uid) and _git(repo, "ls-files", "--error-unmatch", "--", ":(literal)" + path + ".uid")[0] != 0:
            os.remove(uid)
    except OSError:
        pass


def undo(repo, pre, stub, path, branch="", task_log=""):
    if os.environ.get("OVN_STUB_UNDO", "on") == "off" or not (repo and pre and stub and path):
        return "off"

    def note(msg):
        if task_log:
            try:
                with open(task_log, "a") as f:
                    f.write("--- stub-guard: %s ---\n" % msg)
            except OSError:
                pass

    if _git(repo, "merge-base", "--is-ancestor", stub, "HEAD")[0] != 0:
        # a `git pull --rebase` inside the cycle (credit/park push) rewrites the stub commit's sha: find its rebased copy by subject + path
        rc0, out0 = _git(repo, "log", "-n", "80", "--diff-filter=A", "--format=%H",
                         "--grep=^chore: stub new source file before implement", "--", ":(literal)" + path)
        stub = out0.split()[0] if rc0 == 0 and out0.split() else ""
        if not stub:
            return "stub-not-in-head"
    rc, body = _git(repo, "show", "HEAD:" + path)
    if rc != 0 or not is_placeholder_only(body):
        return "filled-or-gone"
    if _git(repo, "status", "--porcelain", "-uno", "--", path)[1].strip():
        return "dirty"
    head = _git(repo, "rev-parse", "HEAD")[1].strip()
    on_remote = bool(_git(repo, "branch", "-r", "--contains", stub)[1].strip())
    if head == stub and not on_remote and _git(repo, "rev-parse", stub + "^")[1].strip() == pre \
            and not _git(repo, "status", "--porcelain", "-uno")[1].strip():
        if _git(repo, "reset", "--hard", "-q", pre)[0] == 0:
            _drop_uid_sidecar(repo, path)
            note("unfilled stub %s dropped (reset to %s)" % (path, pre[:8]))
            return "reset"
        return "reset-failed"
    refs = _added_references(repo, pre, path)
    if refs is not False:         # True = a file committed this cycle references the placeholder; None = could not tell: keep it (it is flagged by scan)
        note("unfilled stub %s KEPT (%s)" % (path, "a source file added this cycle references it" if refs else "diff unavailable"))
        return "referenced" if refs else "refs-unknown"
    paths = [":(literal)" + path]
    if _git(repo, "ls-files", "--error-unmatch", "--", ":(literal)" + path + ".uid")[0] == 0:
        paths.append(":(literal)" + path + ".uid")
    if _git(repo, "rm", "-q", "--", *paths)[0] != 0:
        return "rm-failed"
    _drop_uid_sidecar(repo, path)
    if _git(repo, "commit", "-q", "-m", "chore: drop unfilled stub %s (the implement step never filled it)" % path,
            "--", *paths)[0] != 0:
        _git(repo, "reset", "-q", "HEAD", "--", *paths)
        _git(repo, "checkout", "-q", "--", *paths)
        return "commit-failed"
    pushed = ""
    if on_remote and branch:
        if _git(repo, "push", "-q", "origin", "HEAD:" + branch, timeout=40)[0] == 0:
            pushed = ", pushed"
    note("unfilled stub %s removed in a follow-up commit%s" % (path, pushed))
    return "removed"


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 0
    cmd, repo = argv[1], argv[2]
    try:
        if cmd == "pick":
            text = ""
            if "--text-file" in argv:
                with open(argv[argv.index("--text-file") + 1], encoding="utf-8", errors="replace") as f:
                    text = f.read()
            else:
                text = sys.stdin.read()
            print(pick(repo, text))
        elif cmd == "scan":
            rev = argv[argv.index("--rev") + 1] if "--rev" in argv else None
            for kind, p in scan(repo, rev):
                print("%s\t%s" % (kind, p))
        elif cmd == "undo":
            a = argv[3:] + [""] * 6
            print(undo(repo, a[0], a[1], a[2], a[3], a[4]))
    except Exception as exc:                  # fail-safe: never break the cycle
        print("ERROR\t%s" % exc, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
