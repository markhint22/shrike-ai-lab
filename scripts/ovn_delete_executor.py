#!/usr/bin/env python3
"""ovn_delete_executor.py - decide whether a queue item is a SAFE whole-file deletion the fleet can do with `git rm`.

Why: udiff cannot express a deletion here ("'/dev/null' is not in the subpath of ..."), so every 'Delete/Remove <file>'
item is an LLM job that can never succeed (measured 2026-09-29: ~43 min/day; one gitlark delete item was attempted 57
times). The caller (run_overnight.sh DELETE-EXECUTOR block) does the git rm + the repo's full verification + credit; this
only DECIDES, conservatively, from the item text and the working tree. Anything doubtful is a SKIP and the item goes down
the normal path exactly as before.

usage: ovn_delete_executor.py check <repo_dir> "<item line>"
       ovn_delete_executor.py intent "<item text>"      exit 0 = the leading instruction is a whole-file delete, 1 = not (see delete_intent)
       ovn_delete_executor.py plan <repo_dir> "<roadmap feature text>"   (2026-10-11, delplan X5) the planner's deterministic bypass: see plan_feature
stdout: "OK\t<path> [<path>...]"   (paths to git rm; the item's file + its dedicated test ONLY if the item names that test)
        "ALREADY-GONE\t<path>"        (h13: the target is absent AND was tracked then deleted in git history, or the item's own
                                       `VERIFY: test ! -f <path>` already passes - nothing left to delete; caller credits the item)
        "SKIP\t<reason>"
plan:  "SKIP\t<reason>"  |  "DONE\t<paths>" (every named path is already gone)  |  "OK\t<n>" followed by n item lines (one per path, ready for backlog/<repo>.md)
"""
import os
import re
import subprocess
import sys

CODE_EXT = {".py", ".ts", ".tsx", ".js", ".jsx", ".vue", ".kt", ".gd"}
PATH = re.compile(r"[A-Za-z0-9_.@-]+(?:/[A-Za-z0-9_.@\[\]-]+)*\.[A-Za-z0-9]{1,8}")
# whole-FILE deletion phrasing only ("Delete the dead X.py module/file"); identical shape to the agent-validated R1 rule
DELFILE = re.compile(r"^\s*(delete|remove)\b[^.`]{0,40}\b(file|module|class file|test file)\b", re.I)
DELFILE_PATH_FIRST = re.compile(r"^\s*(delete|remove)\s+(the\s+)?(dead\s+|unused\s+|orphan(ed)?\s+|stub\s+|empty\s+)*`?[A-Za-z0-9_./@-]+\.[A-Za-z0-9]{1,8}`?\s*(\(|[,;:.]|$|—|-|because|it |which |as |since )", re.I)
PARTIAL = re.compile(r"\b(function|method|constant|import|field|column|line|lines|block|entry|route|endpoint|export|variable|key|param|parameter|case|branch|dependency)\b", re.I)
PROTECTED_NAMES = {"__init__.py", "conftest.py", "main.py", "app.py", "index.ts", "index.tsx", "index.js", "app.vue", "main.ts", "main.js",
                   "settings.py", "config.py", "package.json", "manage.py", "wsgi.py", "asgi.py", "env.py", "build.gradle", "build.gradle.kts"}
PROTECTED_PARTS = ("alembic/", "migrations/", "/versions/", ".github/", "node_modules/", "/.venv/", "android/app/src/main/AndroidManifest", "project.godot")
GENERIC_STEMS = {"index", "main", "utils", "util", "types", "type", "constants", "config", "models", "model", "helpers", "helper", "common",
                 "base", "core", "app", "api", "store", "test", "tests", "data", "schema", "schemas", "service", "services", "router", "routes"}
IGNORE_REF = re.compile(r"(\.md$|\.rst$|\.txt$|\.lock$|-lock\.json$|^OVERNIGHT_|^docs/|^htmlcov/|^coverage/|\.snap$|\.uid$|(^|/)(README|AGENTS|CLAUDE)[^/]*$)")


# --- delete INTENT (2026-10-09, harness-credit-integrity item 2) -------------------------------------------------------------------------------
# `intent "<item text>"` answers one question for the runner's "this task deletes a file: use the DELETE: trailer" injection and for ovn_path_gate.py's
# STILL_EXISTS rule: is the item's LEADING instruction a whole-FILE delete? Both used to key off a bare "delete/remove ... file" regex or a leading-verb test
# and so treated "Remove the unused import(s) in this file: `a`, `b` (ruff F401)" as a file delete (the injection told the model to write a DELETE: trailer
# instead of editing the file; the path gate called an already-edited file STILL_EXISTS). Rules (all must hold for one candidate sentence):
#   1. the sentence STARTS with a delete verb (delete/remove/drop/prune/retire) - not "this task ... delete" mid-sentence;
#   2. its object is a file noun (file/module/script/test file/class file) or a path token, found BEFORE any partial-removal noun and not behind an
#      "in/from/of/inside/within" preposition (then the path/file is the container of what is removed, not the thing removed);
#   3. no partial-removal noun (import, function, method, line, decorator, key, entry, symbol, stub body, ...) precedes that object;
#   4. an item line whose head is the item's own path ("path - Delete the dead module") has an IMPLICIT object: it only needs rule 1 and no partial noun.
# Exit 0 = whole-file delete intent, 1 = not (unparseable input is 'not').
INTENT_VERB = re.compile(r"^\s*(?:delete|remove|drop|prune|retire)\b", re.I)
INTENT_PARTIAL = re.compile(
    r"\b(?:function|method|constant|import|field|column|line|block|entry|entries|route|endpoint|export|variable|key|param|parameter|case|branch|dependency|"
    r"decorator|symbol|statement|class|code|logic|handling|handler|docstring|comment|todo|attribute|property|argument|arg|usage|reference|call|section|"
    r"stub\s+bod(?:y|ies)|bod(?:y|ies)|test\s+case|assert(?:ion)?|fixture|listener|hook|option|flag|setting|member|prop|signal)(?:s|es)?\b", re.I)
INTENT_PARTIAL_MODIFIER = re.compile(INTENT_PARTIAL.pattern + r"(?=\s+(?:file|module|script)\b)", re.I)   # "route file", "class file" name the FILE kind, not a part of a file
INTENT_COUNT_MOD = re.compile(r"\b\d+-(?:lines?|loc)\b", re.I)   # "58-line CacheService module": a size modifier of the file, not the partial noun 'line'
INTENT_CLAUSE_CUT = re.compile(r"\b(?:covered by|containing|contains|that|which|whose|because|since|as (?:it|its|this|they)|now that|so that|where|with)\b", re.I)   # what follows describes the file, it is not the object
INTENT_IMPLICIT_CUT = re.compile(r"\s\(|;|,\s")   # an implicit-object item: only the opening noun phrase counts ("Delete this orphaned 58-line X stub (calls `y`, ...)")
INTENT_FILE_NOUN = re.compile(r"\b(?:files?|modules?|scripts?)\b", re.I)
INTENT_CONTAINER_PREP = re.compile(r"\b(?:in|from|of|inside|within|at|on)\b", re.I)


def _intent_candidate(c, implicit):
    """True when the single candidate sentence c (already stripped of checkbox/tags) is a whole-file delete instruction."""
    m = INTENT_VERB.match(c)
    if not m:
        return False
    raw_phrase = re.split(r"[:\n]| \u2014 | -- ", c[m.end():], maxsplit=1)[0][:120]
    cm = INTENT_CLAUSE_CUT.search(raw_phrase)
    if cm and raw_phrase[:cm.start()].strip():
        raw_phrase = raw_phrase[:cm.start()]   # "Delete duplicate stub covered by `tests/t.py`", "Delete the stale test file that is not matched ...": the clause describes the file
    phrase = raw_phrase.replace("`", "")
    phrase_n = INTENT_COUNT_MOD.sub(lambda mm: "X" * len(mm.group(0)), INTENT_PARTIAL_MODIFIER.sub(lambda mm: "X" * len(mm.group(0)), phrase))   # keep offsets, neutralise "route file" / "58-line" modifiers
    pm = INTENT_PARTIAL.search(phrase_n)
    cands = []
    fm = INTENT_FILE_NOUN.search(phrase)
    if fm:
        cands.append(fm.start())
    pt = PATH.search(phrase)
    if pt:
        cands.append(pt.start())
    if not cands:
        # no explicit object: only an item whose own leading path is the (implicit) object qualifies, and only when nothing partial is named
        # (a backticked identifier or a long phrase names a THING inside the file: "Delete `foo_helper`", "Remove the duplicated helper from the tail")
        if not implicit:
            return False
        head_raw = INTENT_IMPLICIT_CUT.split(raw_phrase, maxsplit=1)[0]
        if "`" in head_raw:
            return False
        head_n = INTENT_COUNT_MOD.sub(lambda mm: "X" * len(mm.group(0)), head_raw)
        return INTENT_PARTIAL.search(head_n) is None and len(head_n.split()) <= 6 and not INTENT_CONTAINER_PREP.search(head_n)
    obj = min(cands)
    if pm is not None and pm.start() < obj:
        return False
    if INTENT_CONTAINER_PREP.search(phrase[:obj]):
        return False
    # the file noun / path must be the thing removed, not a possessor or a modifier of a partial-removal noun (harness-credit-integrity fix): reject
    # "Remove this file's unused helper functions", "Remove the file `a/b.py`'s unused import", "Remove unused file references", "... scripts directory reference"
    end = fm.end() if (fm and fm.start() == obj) else (pt.end() if pt else obj)
    if not _file_object_ok(phrase, end):
        return False
    return True


def _file_object_ok(phrase, end):
    """False when the text right after the file noun/path makes it a possessor ('s) or the modifier of a partial-removal noun within the next 3 tokens."""
    tail = re.split(r"[;,(]|\.(?:\s|$)|\s-\s", phrase[end:], maxsplit=1)[0]   # the clause only: "Delete the dead file; nothing imports it" is a plain file delete
    if re.match(r"\s*['\u2019]s\b", tail):
        return False
    for tok in tail.split()[:3]:
        if re.search(r"['\u2019]s$", tok):
            return False
        t2 = tok.strip("`.,;:()'\"")
        if re.fullmatch(r"[A-Za-z]+", t2) and INTENT_PARTIAL.fullmatch(t2):
            return False
    return True


def delete_intent(text):
    """True when any line of text is a whole-file delete instruction (see the rules above). Lines are item lines or free sentences."""
    for raw in (text or "").splitlines():
        if not raw.strip():
            continue
        head, desc, full = parse(raw)
        implicit = bool(desc) and primary_path(head, desc) is not None
        if implicit:
            if _intent_candidate(desc, True):
                return True
            # BACK-STOP (round-3 fix): a leading delete verb on an item that is its OWN path's delete - its VERIFY is `test ! -f <that path>` - is a whole-file delete whatever
            # the noun phrase looks like ("Delete duplicate stub covered by ...", "Delete dead stub containing ..."): the VERIFY states the intent in machine form
            pp = primary_path(head, desc)
            if INTENT_VERB.match(desc) and re.search(r"(?:\btest|\[)\s+!\s+-[fe]\s+[`'\"]?" + re.escape(pp) + r"(?![A-Za-z0-9_./-])", full):
                return True
            continue
        if _intent_candidate(full, False) or (desc and _intent_candidate(desc, False)):
            return True
    return False


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def parse(item):
    t = re.sub(r"^- \[[ xX]\]\s*", "", item.strip())
    t = re.sub(r"^(\[[^\]]*\]\s*|\([^)]*\)\s*)+", "", t)
    head, _, desc = t.partition(" — ")
    return head.strip(), desc.strip(), t


def primary_path(head, desc):
    m = PATH.search(head.replace("`", ""))
    if m and head.replace("`", "").strip().startswith(m.group(0)):
        return m.group(0)
    return None


def _name_elsewhere(repo, prim):
    """True when prim has no directory part and a tracked file with that basename exists somewhere else (the item's path is then ambiguous)."""
    if "/" in prim:
        return False
    out = git(repo, "ls-files").stdout.splitlines()
    return any(os.path.basename(f) == prim for f in out)


# --- importer scan (2026-10-11, delplan X6) ---------------------------------------------------------------------------------------------------------
# The old scan was `git grep -lIw <stem>` over every tracked non-doc file: comment/prose hits ("# Miss roll: scatter the landing ...") and ANY same-named file in
# another directory (`SaveManager="*res://scripts/save/save_manager.gd"` while deleting the orphan scripts/battle/save_manager.gd) counted as importers, so the typical
# "orphan duplicate" case always SKIPped and went down the LLM udiff path that can never delete ("'/dev/null' is not in the subpath"). A hit now counts only when:
#   (a) a path token in a non-comment line RESOLVES to the target (`res://scripts/x.gd`, a repo-relative path, a suffix path, or a ./ ../ bare name relative to the
#       referencing file - a different directory with the same basename does NOT resolve);
#   (b) .gd: the target declares `class_name X` and X appears as a word in a non-comment line of another file;
#   .py and the other code files (.kt .ts .tsx .js .jsx .vue): the old stem-word match, minus comment-only lines and minus lines whose only stem mentions sit in an explicit
#       path token that POSITIVELY resolves to a different tracked file (round-2 review: multi-line / backslash imports, `s.stem.f()` alias use, importlib strings and
#       alias-prefixed imports `@/components/X.vue` are all real references that a statement-shaped regexp cannot see, so nothing but comments and proven other-file path
#       tokens is excluded).
# Comment-only lines ('#', '//', '/*', '*', ';', '--') and docs / OVERNIGHT_*.md / AGENTS.md / README are never references. Every doubt (unreadable file) stays a ref.
COMMENT_ONLY = re.compile(r"^\s*(?:#|//|/\*|\*(?:\s|$)|;|--(?:\s|$))")
_PY_IMPORT = re.compile(r"^\s*(?:from|import)\b")
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_CLASS_NAME = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)


def _grep_lines(repo, word):
    """[(path, text)] for every line of a tracked, non-binary file containing `word` as a whole word (git grep -nIw -F)."""
    r = git(repo, "grep", "-nIw", "-F", "-e", word)
    out = []
    for l in r.stdout.splitlines():
        parts = l.split(":", 2)
        if len(parts) == 3:
            out.append((parts[0], parts[2]))
    return out


def _token_re(base):
    return re.compile(r"(?<![\w@./-])((?:res://)?(?:[\w@.\[\]-]+/)*)" + re.escape(base) + r"(?![\w]|\.uid\b|\.import\b)")


def _token_resolves(prefix, ref_file, prim):
    base = os.path.basename(prim)
    if prefix.startswith("res://"):
        rel = os.path.normpath(prefix[len("res://"):] + base)
        return rel == prim or prim.endswith("/" + rel)
    cands = []
    if "/" in prefix:
        rel = os.path.normpath(prefix + base)
        cands.append(rel)
        if prim.endswith("/" + rel):
            return True
    cands.append(os.path.normpath(os.path.join(os.path.dirname(ref_file), prefix + base)))
    return prim in cands


def _py_needles(prim):
    parts = prim[:-3].split("/")
    out = []
    for i in range(len(parts)):
        sub = parts[i:]
        if len(sub) >= 2 and all(_IDENT.match(x) for x in sub):
            out.append(".".join(sub))
    return out


def other_path_stripper(repo, prim, stem):
    """-> f(text, ref_file) that blanks every explicit path token `dir/<stem>.<ext>` that POSITIVELY resolves to a different tracked file than `prim`.
    Review fix (2026-10-11, delplan round 2): a token is only blanked when it resolves (repo-relative, relative to the referencing file, a res:// path or a suffix of a tracked
    path) to at least one existing tracked file and `prim` is not among the candidates. An alias prefix (`@/components/X.vue`, `~/x`, a baseUrl path) resolves to nothing, so it
    stays a reference - the old scan blocked those and a lazy `import('@/...')` must keep blocking."""
    files = set(git(repo, "ls-files").stdout.splitlines())
    pat = re.compile(r"(?<![\w@./-])((?:res://)?(?:[\w@.\[\]-]+/)+)" + re.escape(stem) + r"(\.[A-Za-z0-9]{1,8})\b")

    def cands(prefix, ext, ref_file):
        name = stem + ext
        rel = prefix[len("res://"):] if prefix.startswith("res://") else prefix
        p = os.path.normpath(rel + name)
        out = set()
        if p in files:
            out.add(p)
        if not prefix.startswith("res://"):
            q = os.path.normpath(os.path.join(os.path.dirname(ref_file), rel + name))
            if q in files:
                out.add(q)
        if not p.startswith(".."):
            out.update(f for f in files if f.endswith("/" + p))
        return out

    def strip(text, ref_file):
        def sub(m):
            c = cands(m.group(1), m.group(2), ref_file)
            return " " if c and prim not in c else m.group(0)
        return pat.sub(sub, text)
    return strip


def _importers(repo, prim, targets):
    """Set of tracked files (other than `targets`, docs excluded) that genuinely reference `prim` - see the block comment above."""
    base = os.path.basename(prim)
    stem, ext = os.path.splitext(base)
    tok = _token_re(base)
    refs = set()
    skip = set(targets)

    def _live(path, text):
        return path not in skip and not IGNORE_REF.search(path) and not COMMENT_ONLY.match(text)

    if ext == ".gd":
        hits = _grep_lines(repo, stem)
        for path, text in hits:
            if not _live(path, text):
                continue
            for m in tok.finditer(text):
                if _token_resolves(m.group(1), path, prim):
                    refs.add(path)
                    break
        try:
            src = open(os.path.join(repo, prim), encoding="utf-8", errors="replace").read()
        except OSError:
            src = ""
        for cn in set(_CLASS_NAME.findall(src)):
            for path, text in _grep_lines(repo, cn):
                if _live(path, text):
                    refs.add(path)
    else:
        # .py and every other code file: ANY live (non-comment) line naming the stem as a word is a reference - multi-line `from x import (\n  stem,\n)` blocks,
        # backslash continuations, `s.stem.f()` alias use and importlib strings all land on lines that no import-statement regexp can classify. The only mentions that do not
        # count are explicit path tokens that positively resolve to a DIFFERENT tracked file (other_path_stripper).
        strip = other_path_stripper(repo, prim, stem)
        word = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(stem) + r"(?![A-Za-z0-9_])")
        for path, text in _grep_lines(repo, stem):
            if _live(path, text) and word.search(strip(text, path)):
                refs.add(path)
    return refs


def decide(repo, item, ignore_refs=(), refs_out=None):
    head, desc, full = parse(item)
    if not (DELFILE.match(desc) or DELFILE_PATH_FIRST.match(desc) or re.search(r"VERIFY:\s*`?\s*test\s+!\s+-f\s+", full)):
        return ("SKIP", "not a whole-file delete item")
    lead = desc[:80]
    # "Remove dead function foo() from x.py" / "Delete unused import" etc. are edits, not file deletions
    if PARTIAL.search(lead) and not re.search(r"\b(file|module|class file|test file)\b", lead, re.I):
        return ("SKIP", "partial edit, not a file delete")
    prim = primary_path(head, desc)
    if not prim:
        m = PATH.search(desc.replace("`", ""))
        prim = m.group(0) if m else None
    if not prim:
        return ("SKIP", "no target path")
    if ".." in prim.split("/") or prim.startswith("/"):
        return ("SKIP", "unsafe path")
    if os.path.splitext(prim)[1] not in CODE_EXT:
        return ("SKIP", "not a code file")
    base = os.path.basename(prim)
    if base.lower() in PROTECTED_NAMES or any(p in prim for p in PROTECTED_PARTS):
        return ("SKIP", "protected file")
    if git(repo, "ls-files", "--error-unmatch", "--", prim).returncode != 0:
        # h13 (2026-10-04): an item whose file an EARLIER commit already deleted flailed 6 cycles (xlite elevation.gd): the DELETE handler only acts on an
        # existing file and the item was never credited. Absent now + (deleted in history OR the item's own VERIFY `test ! -f <path>`) = done.
        # Review hardening: lexists (a dangling symlink is still there), literal pathspecs (a `[id].ts` path is not a glob), the VERIFY must be the
        # item's WHOLE check (no `&& <more>` tail that would go unevaluated), and a bare file name (no directory) is ambiguous when a tracked file
        # of that name lives elsewhere - then the named target may simply be mis-pathed, never credit.
        if not os.path.lexists(os.path.join(repo, prim)) and not _name_elsewhere(repo, prim):
            hist = git(repo, "--literal-pathspecs", "log", "--diff-filter=D", "--format=%h", "-1", "--", prim).stdout.strip()
            _pe = re.escape(prim)
            own_verify = re.search(r"VERIFY:\s*(?:`\s*test\s+!\s+-[fe]\s+" + _pe + r"\s*`|test\s+!\s+-[fe]\s+" + _pe + r"\s*(?:\)|\.|,|\[feat:[^\]]*\]|\{[^}]*\}|$))", full)
            if hist or own_verify:
                return ("ALREADY-GONE", prim)
        return ("SKIP", "target not tracked (already gone or wrong path)")
    stem = os.path.splitext(base)[0]
    if stem.lower() in GENERIC_STEMS or len(stem) < 4:
        return ("SKIP", "generic file name - importer search would be unreliable")
    targets = [prim]
    # a dedicated test is deleted too ONLY if the item itself names it
    for p in PATH.findall(full.replace("`", "")):
        if p == prim or p in targets:
            continue
        pb = os.path.basename(p)
        if stem in pb and re.search(r"(^|/)(tests?|__tests__)/|\.test\.|\.spec\.|_test\.|^test_", p) and \
                git(repo, "ls-files", "--error-unmatch", "--", p).returncode == 0:
            targets.append(p)
    # importer search (2026-10-11, X6): any OTHER tracked non-doc file that REALLY references the module blocks the automatic delete - see _importers
    raw = _importers(repo, prim, targets)
    if refs_out is not None:
        refs_out.update(raw)
    refs = {f for f in raw if f not in ignore_refs}
    if refs:
        return ("SKIP", "referenced by: " + ", ".join(sorted(refs)[:3]))
    return ("OK", " ".join(targets))


# --- planner bypass (2026-10-11, delplan X5) -----------------------------------------------------------------------------------------------------------
# ovn_planner.sh always asked the 27B for 6-10 items, so a one-line roadmap deletion ("Delete orphan `scripts/battle/save_manager.gd` ... VERIFY: `test ! -f <path>`") became
# ceremonial items with conflicting VERIFYs ('verify the file exists' x4, a 'test asserts absence' item ordered BEFORE the delete), none of which this executor could take.
# plan_feature recognises the two shapes of a pure file-delete feature and emits ONE item per path, in the format this executor's `decide` accepts, without any model call:
#   (1) the feature's VERIFY clause is exactly `test ! -f <path>[ && test ! -f <path2> ...]` (backticks optional) and the text carries a delete verb;
#   (2) the feature carries `{cat: dead-code|infra; size: S ...}` and its title (the text before ' — ') is a whole-file delete instruction (delete_intent) naming the path(s).
# Safety is `decide` itself, applied to every path: all-or-nothing - ANY path that is not a clean OK (referenced, protected, generic name, untracked, ...) makes the whole plan
# a SKIP and the planner decomposes the feature with the model exactly as before. A path that is already gone (ALREADY-GONE) is dropped; if every path is gone the feature is DONE.
# References from OTHER paths of the same batch do not block (a test and the module it tests go together); the items are ordered referrers-first, and a reference cycle inside
# the batch is a SKIP (deleting either one first would leave the other importing a missing file).
_PLAN_ABS_T = r"test\s+!\s+-[fe]\s+[\"']?([A-Za-z0-9_.@/\[\]-]+)[\"']?"
_PLAN_ABS = re.compile(r"^" + _PLAN_ABS_T + r"(?:\s+(?:exits|returns|passes|succeeds)\b.*)?$")
# commands that may trail the `test ! -f` conjunction without making the feature more than a delete: the repo's full verification (run_repo_verification) runs after the delete
# anyway, and `echo PASS` asserts nothing. Anything else (a grep, a rewrite of other files, ...) means the feature is not a pure file delete.
_PLAN_TAIL_OK = re.compile(r"^(?:echo\s+\S+|pytest\b.*|python3?\s+-m\s+pytest\b.*|npx\s+vitest\b.*|npm\s+(?:run\s+)?test\b.*|godot\b.*gut_cmdln.*|\./gradlew\b.*)$")
_PLAN_TAG = re.compile(r"\{[^{}]*\}")
_PLAN_LABEL = re.compile(r"^\s*[A-Za-z][\w \-/]{0,30}:\s+")
_PLAN_TRAIL_TAGS = re.compile(r"\s*(?:\([^()]*\)|\{[^{}]*\}|\[[^\[\]]*\])\s*$")


def _plan_title(feat):
    t = feat.split(" \u2014 ", 1)[0]
    t = _PLAN_TAG.sub("", t)
    return _PLAN_LABEL.sub("", t, count=1).strip()


def _plan_title_ok(title, strict):
    """The title is a delete of FILES, not of something inside a file: leads with a delete verb, names no backticked symbol / call, no partial-removal noun (strict: delete_intent)."""
    if not INTENT_VERB.match(title):
        return False
    for bt in re.findall(r"`([^`]*)`", title):
        if not PATH.fullmatch(bt) or "(" in bt:
            return False
    if "(" in title.replace("`", " "):
        return False
    neutral = INTENT_PARTIAL_MODIFIER.sub(lambda mm: "X" * len(mm.group(0)), title.replace("`", ""))
    if INTENT_PARTIAL.search(neutral):
        return False
    return delete_intent(title) if strict else True


def _plan_paths(feat):
    """(paths, shape) of a pure file-delete feature, or ([], reason)."""
    title = _plan_title(feat)
    vm = re.search(r"\bVERIFY:\s*(.*)$", feat)
    if vm:
        clause = vm.group(1)
        for _ in range(3):
            clause = _PLAN_TRAIL_TAGS.sub("", clause)
        parts = [x.strip() for x in re.split(r"\s*(?:&&|;)\s*", clause.replace("`", "").strip().rstrip(".")) if x.strip()]
        paths = []
        i = 0
        while i < len(parts):
            m = _PLAN_ABS.match(parts[i].rstrip("."))
            if not m:
                break
            if m.group(1) not in paths:
                paths.append(m.group(1))
            i += 1
        if paths and all(_PLAN_TAIL_OK.match(x.rstrip(".")) or re.match(r"^(?:still\s+)?(?:passes|exits|returns)\b", x) for x in parts[i:]):
            if not _plan_title_ok(title, False):
                return [], "title is not a whole-file delete"
            return paths, "verify"
    if any(re.search(r"\bcat:\s*(?:dead-code|infra)\b", t) and re.search(r"\bsize:\s*S\b", t) for t in _PLAN_TAG.findall(feat)):
        if not _plan_title_ok(title, True):
            return [], "tagged feature is not a whole-file delete title"
        paths = []
        for pm in PATH.finditer(title.replace("`", "")):
            if pm.group(0) not in paths:
                paths.append(pm.group(0))
        if paths:
            return paths, "tag"
        return [], "tagged delete title names no path"
    return [], "not a pure file-delete feature"


def _plan_item(path):
    return "- [ ] [T1] %s \u2014 Delete the file. VERIFY: `test ! -f %s`. (cat:refactor; multifile:no)" % (path, path)


def plan_feature(repo, feat):
    """-> ("SKIP", reason) | ("DONE", [paths]) | ("OK", [item lines]); see the block comment above."""
    paths, shape = _plan_paths(feat or "")
    if not paths:
        return ("SKIP", shape)
    if len(paths) > 6:
        return ("SKIP", "too many paths (%d) for a deterministic plan" % len(paths))
    live, gone, refs_of = [], [], {}
    batch = set(paths)
    for p in paths:
        refs = set()
        act, info = decide(repo, _plan_item(p), ignore_refs=batch - {p}, refs_out=refs)
        if act == "ALREADY-GONE":
            # a path that never existed is a typo'd roadmap entry, not a finished deletion: only a path git history shows deleted counts as gone
            if not git(repo, "--literal-pathspecs", "log", "--diff-filter=D", "--format=%h", "-1", "--", p).stdout.strip():
                return ("SKIP", "%s: not tracked and never deleted in history (wrong path?)" % p)
            gone.append(p)
        elif act == "OK":
            live.append(p)
            refs_of[p] = refs
        else:
            return ("SKIP", "%s: %s" % (p, info))
    if not live:
        return ("DONE", gone)
    # referrers first: p must wait for every other batch path that references it
    referrers = {p: refs_of[p] & set(live) for p in live}
    order, left = [], list(live)
    while left:
        ready = [p for p in left if not (referrers[p] & set(left))]
        if not ready:
            return ("SKIP", "reference cycle between %s" % ", ".join(left))
        order.append(ready[0])
        left.remove(ready[0])
    return ("OK", [_plan_item(p) for p in order])


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "intent":
        sys.exit(0 if len(sys.argv) >= 3 and delete_intent(sys.argv[2]) else 1)
    if len(sys.argv) >= 4 and sys.argv[1] == "plan":
        act, info = plan_feature(sys.argv[2], sys.argv[3])
        if act == "OK":
            print("OK\t%d" % len(info))
            print("\n".join(info))
        else:
            print("%s\t%s" % (act, " ".join(info) if isinstance(info, list) else info))
        return
    if len(sys.argv) < 4 or sys.argv[1] != "check":
        print("SKIP\tusage")
        return
    act, info = decide(sys.argv[2], sys.argv[3])
    print("%s\t%s" % (act, info))


if __name__ == "__main__":
    main()
