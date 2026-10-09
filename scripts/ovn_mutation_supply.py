#!/usr/bin/env python3
"""scripts/ovn_mutation_supply.py - mutation-survivor supply for GDScript: items that add a GUT test killing a surviving mutant (2026-10-09).

Why: a "write a test for X" item is only worth a cycle if the test pins behaviour the existing suite does NOT. A mutation survivor is exactly that gap:
flip one operator in the source, run the file's own GUT test, and it still passes. Pilot on xlite (150 non-battle mutants): 17% survived (25), ~190
candidates extrapolated, about half of them equivalent mutants (parked later by the existing fail-cap mechanisms, not filtered here). The VERIFY of such an
item cannot be vacuous: it is RED while the mutant survives and GREEN only when a test passes on the real code AND fails by assertion on the mutant.

usage:
  ovn_mutation_supply.py scan   <repo_dir> [--max-mutants N] [--json]    nightly (cron, nice): run up to N mutants (default 40), write the survivors file
  ovn_mutation_supply.py verify <repo_dir> <test_file> <src_file> <line> <orig_token> <mutated_token> [<occurrence>]
                                exit 0 iff the test file PASSES on the real code and FAILS BY ASSERTION on the mutant (applied to a temp copy)
  ovn_mutation_supply.py sites  <gd_file>                                list the mutation sites of one file (debug)
  import ovn_mutation_supply; ovn_mutation_supply.collect(root)         spec dicts for ovn_work_supply (reads the survivors file ONLY, never runs a mutant)
Tokens may be given literally or by name (lt le gt ge eq ne plus minus pluseq minuseq): the VERIFY runner refuses any redirect-looking `>` in a clause.

Mutants: comparison (< <= > >= == !=) and arithmetic (+ - += -=) operators at CODE positions of scripts/**/*.gd (never comments, strings, `->`, shifts,
unary signs, exponent signs), only for source files that have a referencing tests/test_<stem>.gd; never addons/, tests/, scripts/battle/battle.gd, any
battle.gd or a path on .queue-hard-banned-files. Each mutant runs in a scratch copy of a `git archive` of origin/overnight/feature (NEVER the live clone):
GUT `-gtest=res://tests/<f>.gd -gexit`, 30 s timeout. survived = the test passes under the mutant; killed = at least one assertion failure and NO
'Parse Error'/'SCRIPT ERROR' text (a mutant that breaks parsing or raises at run time is NOT a kill and NOT a survivor: status 'error').
Cache: state/mutation_scan_<repo>.json keyed by (source sha, test sha); survivors: state/mutation_survivors_<repo>.json.
env: OVN_DIR (default ~/overnight-queue), OVN_GODOT_BIN (default ~/godot/godot4), OVN_MUT_REF (default origin/overnight/feature, falls back to HEAD),
     OVN_MUT_TIMEOUT (default 30), OVN_MUT_MAX (default 40), OVN_MUTATION_SCAN=off (scan kill switch), OVN_SUPPLY_MUTATION=1 (collect() is off unless set).
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

OVN_DIR = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", ".godot", "addons", "build"}
MUTATE = {"<": "<=", "<=": "<", ">": ">=", ">=": ">", "==": "!=", "!=": "==", "+": "-", "-": "+", "+=": "-=", "-=": "+="}
NAMES = {"lt": "<", "le": "<=", "gt": ">", "ge": ">=", "eq": "==", "ne": "!=", "plus": "+", "minus": "-", "pluseq": "+=", "minuseq": "-="}
TOKNAME = {v: k for k, v in NAMES.items()}
UNARY_AFTER = {"return", "and", "or", "not", "in", "is", "if", "elif", "while", "match", "await", "assert", "yield", "when", "else", "var", "const", "as"}
SKIP_LINE = re.compile(r"^\s*(signal|extends|class_name|enum|@(?!onready)\w+(?!.*\b(var|func|const)\b))\b|\b(print|printerr|prints|push_error|push_warning|preload|load)\s*\(")
NUM = re.compile(r"(?:\d[\d_]*(?:\.[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?\d+)?|0[xX][0-9a-fA-F_]+|0[bB][01_]+")
IDENT = re.compile(r"[A-Za-z_]\w*")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
BAD_OUTPUT = re.compile(r"Parse Error|SCRIPT ERROR|Ignoring script|Failed to load script")


def godot_bin():
    return os.environ.get("OVN_GODOT_BIN") or os.path.join(os.path.expanduser("~"), "godot", "godot4")


def sha(data):
    return hashlib.sha1(data if isinstance(data, bytes) else data.encode()).hexdigest()


def sha_file(p):
    try:
        with open(p, "rb") as f:
            return hashlib.sha1(f.read()).hexdigest()
    except OSError:
        return ""


def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


# ---------------------------------------------------------------- banned / eligible files
def banned_list(root):
    out = []
    for ln in read(os.path.join(root, ".queue-hard-banned-files")).split("\n"):
        ln = ln.strip()
        if ln and not ln.startswith("#"):
            out.append(ln)
    return out


def list_banned(path, root):
    """True when the path is on the repo's .queue-hard-banned-files (equal, prefix, or - like run_overnight.sh's unanchored `grep -E` - a regex)."""
    for b in banned_list(root):
        if path == b or path.startswith(b):
            return True
        try:
            if re.search(b, path):
                return True
        except re.error:
            pass
    return False


def is_banned(path, root):
    """SOURCE paths: addons/, tests/, any battle.gd, plus the hard-ban list."""
    if path.startswith(("addons/", "tests/", "test/")) or "/addons/" in path or path == "scripts/battle/battle.gd" or os.path.basename(path) == "battle.gd":
        return True
    return list_banned(path, root)


def test_for(root, src_rel):
    """tests/test_<stem>.gd when it exists AND references the source (stem, class_name or the preload path); else None."""
    stem = os.path.splitext(os.path.basename(src_rel))[0]
    tp = "tests/test_%s.gd" % stem
    if list_banned(tp, root):   # the item's edit target is the TEST file: run_overnight.sh discards any change to a hard-banned path every cycle
        return None
    t = read(os.path.join(root, tp))
    if not t:
        return None
    m = re.search(r"^class_name\s+(\w+)", read(os.path.join(root, src_rel)), re.M)
    if re.search(r"\b%s\b" % re.escape(stem), t) or (m and re.search(r"\b%s\b" % re.escape(m.group(1)), t)):
        return tp
    return None


def other_tests(root, src_rel, tp, cap=None):
    """Other test files (tests/ and test/, any depth) that reference the source (stem, class_name or the res:// path), best name match first:
    -> (candidates capped at OVN_MUT_OTHERS_MAX (default 6), sha over exactly those capped candidates). A mutant the paired test misses may already be
    killed by one of these (damage.gd:42 is killed by tests/test_damage_mitigation.gd, not test_damage.gd), and an item that asks for a redundant test is wasted
    work. Order: tests named test_<stem>* first, then the most references to the source first (a broadly named source such as unit.gd is referenced by dozens of
    tests: the ones that talk about it most are the likeliest killers), then path. The sha covers only the candidates that are actually run, so an edit to a test
    that merely mentions a common word and ranks below the cap does not reset the file's scan cache; a mutant killed only by a test below the cap stays a
    survivor (raise OVN_MUT_OTHERS_MAX for the files where that matters)."""
    cap = int(os.environ.get("OVN_MUT_OTHERS_MAX", "6")) if cap is None else cap
    stem = os.path.splitext(os.path.basename(src_rel))[0]
    m = re.search(r"^class_name\s+(\w+)", read(os.path.join(root, src_rel)), re.M)
    pats = [r"\b%s\b" % re.escape(stem), re.escape("res://" + src_rel)] + ([r"\b%s\b" % re.escape(m.group(1))] if m else [])
    rx = re.compile("|".join(pats))
    found, refs = [], {}
    for d in ("tests", "test"):
        for dp, dns, fns in os.walk(os.path.join(root, d)):
            dns[:] = sorted(x for x in dns if x not in SKIP_DIRS)
            for fn in sorted(fns):
                if not fn.endswith(".gd"):
                    continue
                rp = os.path.relpath(os.path.join(dp, fn), root)
                if rp != tp:
                    n = len(rx.findall(read(os.path.join(root, rp))))
                    if n:
                        found.append(rp)
                        refs[rp] = n
    found.sort(key=lambda r: (not os.path.basename(r).startswith("test_%s" % stem), -refs[r], r))
    found = found[:cap]
    digest = sha("\n".join("%s:%s" % (r, sha_file(os.path.join(root, r))) for r in found))
    return found, digest


# ---------------------------------------------------------------- mutation sites
def mutation_sites(text):
    """[{line (1-based), col (0-based), orig, mut, occ (1-based among same-orig sites on the line)}] at code positions only."""
    sites = []
    n = len(text)
    i = 0
    line = 1
    line_start = 0
    depth = 0
    prev = None            # 'operand' | 'op' | None  (what the last significant token was)
    lines = text.split("\n")
    seen = {}
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            line_start = i + 1
            if depth == 0 and not text[max(0, i - 1):i] == "\\":
                prev = None
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if c == "\\" and i + 1 < n and text[i + 1] == "\n":
            i += 1
            continue
        if c == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        # strings (incl. r"", &"", ^"", triple quotes)
        if c in "\"'" or (c in "rR&^" and i + 1 < n and text[i + 1] in "\"'" and not (i and (text[i - 1].isalnum() or text[i - 1] == "_"))):
            if c not in "\"'":
                i += 1
                c = text[i]
            q = text[i:i + 3] if text[i:i + 3] in ('"""', "'''") else c
            i += len(q)
            while i < n:
                if text[i] == "\\" and len(q) == 1:
                    i += 2
                    continue
                if text.startswith(q, i):
                    i += len(q)
                    break
                if text[i] == "\n":
                    if len(q) == 1:      # unterminated single-line string: leave the newline to the main loop
                        break
                    line += 1
                    line_start = i + 1
                i += 1
            prev = "operand"
            continue
        if c.isdigit() or (c == "." and i + 1 < n and text[i + 1].isdigit() and prev != "operand"):
            m = NUM.match(text, i)
            i = m.end() if m else i + 1
            prev = "operand"
            continue
        if c.isalpha() or c == "_":
            m = IDENT.match(text, i)
            w = m.group(0)
            i = m.end()
            prev = "op" if w in UNARY_AFTER else "operand"
            continue
        if c in "([{":
            depth += 1
            prev = "op"
            i += 1
            continue
        if c in ")]}":
            depth = max(0, depth - 1)
            prev = "operand"
            i += 1
            continue
        two = text[i:i + 2]
        three = text[i:i + 3]
        tok = None
        if three in ("<<=", ">>=", "**="):
            i += 3
            prev = "op"
            continue
        if two in ("<<", ">>", "->", "**", ":=", "*=", "/=", "%=", "&=", "|=", "^=", "&&", "||", ".."):
            i += 2
            prev = "op"
            continue
        if two in ("<=", ">=", "==", "!=", "+=", "-="):
            tok = two
        elif c in "<>":
            tok = c
        elif c in "+-" and prev == "operand":
            tok = c
        if tok is not None:
            ls = lines[line - 1] if line - 1 < len(lines) else ""
            if not SKIP_LINE.search(ls) and tok in MUTATE:
                col = i - line_start
                k = (line, tok)
                seen[k] = seen.get(k, 0) + 1
                sites.append({"line": line, "col": col, "orig": tok, "mut": MUTATE[tok], "occ": seen[k]})
            i += len(tok)
            prev = "op"
            continue
        i += 1
        prev = "op"
    return sites


def apply_mutant(text, line, orig, mut, occ=1):
    """The source text with the occ-th `orig` code-site on `line` replaced by `mut`; None when there is no such site."""
    for s in mutation_sites(text):
        if s["line"] == line and s["orig"] == orig and s["occ"] == occ:
            L = text.split("\n")
            ln = L[line - 1]
            L[line - 1] = ln[:s["col"]] + mut + ln[s["col"] + len(orig):]
            return "\n".join(L)
    return None


# ---------------------------------------------------------------- running GUT
def classify_gut(rc, out):
    """-> (status, detail). status: pass | fail | error | timeout.  pass = rc 0, tests ran, none failed, no parse/script error text.
    fail = an assertion failure and NO parse/script error text (a real kill candidate). error = parse/script error, no tests ran, or anything else."""
    if rc == "timeout":
        return "timeout", "timeout"
    t = ANSI.sub("", out or "")
    bad = BAD_OUTPUT.search(t)
    failing = bool(re.search(r"\[Failed\]:|^\s*Failing\s+[1-9]\d*|Failing Tests\s+[1-9]|-+\s*[1-9]\d* failing tests?", t, re.M))
    m = re.search(r"^\s*Tests\s+(\d+)", t, re.M)
    tests = int(m.group(1)) if m else 0
    if bad:
        return "error", bad.group(0)
    if failing:
        return "fail", "assertion failure"
    if rc == 0 and tests > 0:
        return "pass", "%d tests" % tests
    return "error", "no tests ran (rc=%s)" % rc


def run_gut(work, test_rel, timeout=None):
    timeout = timeout or int(os.environ.get("OVN_MUT_TIMEOUT", "30"))
    cmd = [godot_bin(), "--headless", "--path", ".", "-s", "addons/gut/gut_cmdln.gd", "-gtest=res://%s" % test_rel, "-gexit"]
    try:
        p = subprocess.Popen(cmd, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace", start_new_session=True)
    except OSError as e:
        return classify_gut(127, str(e))
    try:
        out, _ = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, 9)
        except OSError:
            pass
        p.communicate()
        return classify_gut("timeout", "")
    return classify_gut(p.returncode, out)


def ensure_import(work, seed_from=None):
    """A fresh tree has no .godot (gitignored): seed it from a live clone's cache when one exists, then `--import` (incremental) when the class cache is missing."""
    gd = os.path.join(work, ".godot")
    if not os.path.isdir(gd):
        for src in seed_candidates(work, seed_from):
            if os.path.isdir(os.path.join(src, ".godot")):
                _copy_cache(src, work)
                break
    if not os.path.exists(os.path.join(work, ".godot", "global_script_class_cache.cfg")) and os.path.exists(godot_bin()):
        try:
            subprocess.run([godot_bin(), "--headless", "--path", ".", "--import"], cwd=work, capture_output=True, timeout=300)
        except (subprocess.TimeoutExpired, OSError):
            pass


def seed_candidates(work, seed_from):
    out = [seed_from] if seed_from else []
    env = os.environ.get("OVN_MUT_SEED")
    if env:
        out.append(env)
    name = re.search(r'config/name="([^"]*)"', read(os.path.join(work, "project.godot")))
    for d in sorted(_listdir(os.path.join(OVN_DIR, "repos"))):
        p = os.path.join(OVN_DIR, "repos", d)
        if name and re.search(r'config/name="%s"' % re.escape(name.group(1)), read(os.path.join(p, "project.godot"))):
            out.append(p)
    return [o for o in out if o]


def _listdir(p):
    try:
        return os.listdir(p)
    except OSError:
        return []


def _copy_cache(src, work):
    if shutil.which("rsync"):
        subprocess.run(["rsync", "-a", "--include=.godot/***", "--include=*/", "--include=*.import", "--exclude=*", "--prune-empty-dirs", src + "/", work + "/"],
                       capture_output=True)
        return
    shutil.copytree(os.path.join(src, ".godot"), os.path.join(work, ".godot"), dirs_exist_ok=True, symlinks=True)


def copy_tree(repo_dir, dest):
    """A throw-away copy of the working tree (no .git) so a mutant never touches the live clone."""
    if shutil.which("rsync"):
        r = subprocess.run(["rsync", "-a", "--exclude=.git", "--exclude=node_modules", "--exclude=.venv", repo_dir.rstrip("/") + "/", dest + "/"], capture_output=True)
        if r.returncode == 0:
            return
    shutil.copytree(repo_dir, dest, dirs_exist_ok=True, symlinks=True, ignore=shutil.ignore_patterns(".git", "node_modules", ".venv"))


# ---------------------------------------------------------------- verify
def resolve_tok(t):
    return NAMES.get(t, t)


def verify(repo_dir, test_rel, src_rel, line, orig, mut, occ=1):
    """-> (exit_code, message)."""
    orig, mut = resolve_tok(orig), resolve_tok(mut)
    if MUTATE.get(orig) != mut:
        return 1, "bad mutation %s -> %s" % (orig, mut)
    src_path = os.path.join(repo_dir, src_rel)
    test_path = os.path.join(repo_dir, test_rel)
    if not os.path.isfile(src_path):
        return 1, "source %s missing" % src_rel
    if not os.path.isfile(test_path):
        return 1, "test file %s does not exist yet (red)" % test_rel
    src_text = read(src_path)
    mutated = apply_mutant(src_text, line, orig, mut, occ)
    if mutated is None:
        return 1, "no `%s` code site at line %d of %s (occurrence %d): the source moved, this item is stale" % (orig, line, src_rel, occ)
    ttext = read(test_path)
    if "source_code" in ttext or ("FileAccess" in ttext and os.path.basename(src_rel) in ttext):
        return 1, "the test reads the source text instead of asserting behaviour (not a kill)"
    work = tempfile.mkdtemp(prefix="mutverify-")
    try:
        copy_tree(repo_dir, work)
        ensure_import(work, repo_dir)
        st, why = run_gut(work, test_rel)
        if st != "pass":
            return 1, "the test does not pass on the real code (%s: %s)" % (st, why)
        with open(os.path.join(work, src_rel), "w", encoding="utf-8") as f:
            f.write(mutated)
        st, why = run_gut(work, test_rel)
        if st == "fail":
            return 0, "killed: the test fails by assertion with line %d `%s` -> `%s`" % (line, orig, mut)
        if st == "pass":
            return 1, "survived: the test still passes with line %d `%s` -> `%s`" % (line, orig, mut)
        return 1, "not a kill: mutant run was %s (%s)" % (st, why)
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ---------------------------------------------------------------- scan
def state_paths(repo_dir):
    name = os.path.basename(os.path.abspath(repo_dir))
    sd = os.path.join(OVN_DIR, "state")
    return os.path.join(sd, "mutation_scan_%s.json" % name), os.path.join(sd, "mutation_survivors_%s.json" % name)


def archive_tree(repo_dir, dest):
    ref = os.environ.get("OVN_MUT_REF", "origin/overnight/feature")
    if subprocess.run(["git", "-C", repo_dir, "rev-parse", "-q", "--verify", ref + "^{commit}"], capture_output=True).returncode != 0:
        ref = "HEAD"
    p1 = subprocess.Popen(["git", "-C", repo_dir, "archive", ref], stdout=subprocess.PIPE)
    subprocess.run(["tar", "-x", "-C", dest], stdin=p1.stdout, check=True)
    p1.stdout.close()
    if p1.wait() != 0 or not os.path.exists(os.path.join(dest, "project.godot")):
        raise RuntimeError("git archive of %s failed or has no project.godot" % ref)
    return ref


def eligible_sources(root):
    out = []
    base = os.path.join(root, "scripts")
    for dp, dns, fns in os.walk(base):
        dns[:] = sorted(d for d in dns if d not in SKIP_DIRS)
        for fn in sorted(fns):
            if fn.endswith(".gd"):
                rp = os.path.relpath(os.path.join(dp, fn), root)
                if not is_banned(rp, root):
                    out.append(rp)
    return out


def mkey(s):
    return "%d:%d:%s:%s" % (s["line"], s["col"], s["orig"], s["mut"])


def killed_elsewhere(scratch, src, tp, ent, orig_text, mutated):
    """The mutant survived its paired test: does another test that references the source kill it? -> that test's path, or None. Called with the ORIGINAL source
    in place; each candidate must pass on the real code first (a test that is red anyway proves nothing), then the mutant is written and the candidates run
    (a parse/script error or a timeout is not a kill). The source is restored before returning."""
    base = ent.setdefault("others_base", {})
    cands = ent.get("others") or []
    for ot in cands:
        if ot not in base:
            base[ot] = run_gut(scratch, ot)[0]
    good = [ot for ot in cands if base.get(ot) == "pass"]
    if not good:
        return None
    path = os.path.join(scratch, src)
    with open(path, "w", encoding="utf-8") as f:
        f.write(mutated)
    try:
        for ot in good:
            if run_gut(scratch, ot)[0] == "fail":
                return ot
    finally:
        with open(path, "w", encoding="utf-8") as f:
            f.write(orig_text)
    return None


def scan(repo_dir, max_mutants, as_json=False):
    cache_path, surv_path = state_paths(repo_dir)
    scratch = tempfile.mkdtemp(prefix="mutscan-")
    summary = {"repo": os.path.basename(os.path.abspath(repo_dir)), "ran": 0, "killed": 0, "survived": 0, "error": 0, "files": 0, "skipped_unclean": 0, "killed_elsewhere": 0}
    try:
        ref = archive_tree(repo_dir, scratch)
        ensure_import(scratch, repo_dir)
        try:
            cache = json.load(open(cache_path))
        except (OSError, ValueError):
            cache = {}
        files = cache.setdefault("files", {})
        pending = []                                     # (src, [sites not yet evaluated])
        live_keys = set()
        for src in eligible_sources(scratch):
            tp = test_for(scratch, src)
            if not tp:
                continue
            st = read(os.path.join(scratch, src))
            others, osha = other_tests(scratch, src, tp)
            key = (sha_file(os.path.join(scratch, src)), sha_file(os.path.join(scratch, tp)), osha)
            ent = files.get(src)
            if not ent or (ent.get("src_sha"), ent.get("test_sha"), ent.get("others_sha")) != key:
                ent = files[src] = {"src_sha": key[0], "test_sha": key[1], "others_sha": key[2], "others": others, "others_base": {}, "test": tp, "baseline": None, "mutants": {}}
            live_keys.add(src)
            todo = [s for s in mutation_sites(st) if mkey(s) not in ent["mutants"]]
            if todo and ent["baseline"] != "unclean":
                pending.append((src, todo))
        for gone in [k for k in files if k not in live_keys]:
            del files[gone]
        budget = max_mutants
        while budget > 0 and any(t for _, t in pending):
            for src, todo in pending:
                if budget <= 0 or not todo:
                    continue
                ent = files[src]
                tp = ent["test"]
                if ent["baseline"] is None:
                    st_, why = run_gut(scratch, tp)
                    ent["baseline"] = "ok" if st_ == "pass" else "unclean"
                    ent["baseline_detail"] = why
                    if ent["baseline"] == "unclean":
                        summary["skipped_unclean"] += 1
                        del todo[:]
                        continue
                s = todo.pop(0)
                path = os.path.join(scratch, src)
                orig_text = read(path)
                mutated = apply_mutant(orig_text, s["line"], s["orig"], s["mut"], s["occ"])
                if mutated is None:
                    continue
                with open(path, "w", encoding="utf-8") as f:
                    f.write(mutated)
                try:
                    st_, why = run_gut(scratch, tp)
                finally:
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(orig_text)
                status = {"pass": "survived", "fail": "killed", "timeout": "timeout"}.get(st_, "error")
                killer = None
                if status == "survived":
                    killer = killed_elsewhere(scratch, src, tp, ent, orig_text, mutated)
                    if killer:
                        status = "killed_elsewhere"
                ent["mutants"][mkey(s)] = {"status": status, "line": s["line"], "col": s["col"], "orig": s["orig"], "mut": s["mut"], "occ": s["occ"], "ts": int(time.time())}
                if killer:
                    ent["mutants"][mkey(s)]["killed_by"] = killer
                summary["ran"] += 1
                summary["killed" if status in ("killed", "killed_elsewhere") else "survived" if status == "survived" else "error"] += 1
                if killer:
                    summary["killed_elsewhere"] += 1
                budget -= 1
                _save(cache_path, cache)
        survivors = []
        for src, ent in sorted(files.items()):
            st = read(os.path.join(scratch, src))
            lines = st.split("\n")
            for m in sorted(ent["mutants"].values(), key=lambda x: (x["line"], x["col"])):
                if m["status"] == "survived":
                    survivors.append({"file": src, "test": ent["test"], "line": m["line"], "col": m["col"], "occ": m["occ"], "orig": m["orig"], "mut": m["mut"],
                                      "snippet": lines[m["line"] - 1].strip()[:120] if m["line"] - 1 < len(lines) else "",
                                      "src_sha": ent["src_sha"], "test_sha": ent["test_sha"], "others_sha": ent.get("others_sha", "")})
        summary["files"] = len({s["file"] for s in survivors})
        summary["survivors"] = len(survivors)
        summary["ref"] = ref
        _save(cache_path, cache)
        _save(surv_path, {"generated": int(time.time()), "ref": ref, "survivors": survivors})
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    if as_json:
        print(json.dumps(summary, sort_keys=True))
    else:
        print("mutation scan %(repo)s: ran %(ran)d mutants (killed %(killed)d [%(killed_elsewhere)d by a sibling test], survived %(survived)d, error/timeout %(error)d); %(survivors)d survivor(s) in %(files)d file(s); "
              "%(skipped_unclean)d file(s) skipped (baseline not green); ref %(ref)s" % summary)
    return 0


def _save(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w") as f:
        json.dump(obj, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


# ---------------------------------------------------------------- supply hook
def verify_command(test_rel, src_rel, s):
    """ONE physical line; no redirect characters, no backticks (the item is rendered `VERIFY: `<cmd>``). $OVN_DIR is not exported to the runner's shell
    in every caller (ovn_spec_check.sh assigns it), so the default is spelled out."""
    occ = (" %d" % s["occ"]) if s.get("occ", 1) > 1 else ""
    return "python3 ${OVN_DIR:-$HOME/overnight-queue}/scripts/ovn_mutation_supply.py verify . %s %s %d %s %s%s" % (
        test_rel, src_rel, s["line"], TOKNAME[s["orig"]], TOKNAME[s["mut"]], occ)


def collect(root):
    """Spec dicts for ovn_work_supply.collect_all: ONE item per source file (the earliest still-valid survivor). Reads the survivors file only; a survivor
    is dropped when its source/test changed since the scan (the fleet already moved the file) or the file is now banned. Off unless OVN_SUPPLY_MUTATION=1."""
    if os.environ.get("OVN_SUPPLY_MUTATION", "0") != "1":
        return
    _, surv_path = state_paths(root)
    try:
        data = json.load(open(surv_path))
    except (OSError, ValueError):
        return
    seen = set()
    for s in data.get("survivors", []):
        src, tp = s["file"], s["test"]
        if src in seen or is_banned(src, root) or list_banned(tp, root):   # the edit target is the TEST file: a hard-banned one would be discarded every cycle
            continue
        sp, tpp = os.path.join(root, src), os.path.join(root, tp)
        if not os.path.isfile(sp) or not os.path.isfile(tpp):
            continue
        if sha_file(sp) != s["src_sha"] or sha_file(tpp) != s["test_sha"]:
            continue
        if s["orig"] not in TOKNAME or s["mut"] not in TOKNAME:
            continue
        if other_tests(root, src, tp)[1] != s.get("others_sha", sha("")):
            continue   # a sibling test that references the source changed since the scan: it may kill this mutant now
        seen.add(src)
        yield {"kind": "gd-mutation-survivor", "file": tp, "tier": "T2", "cat": "test",
               "text": "Add a GUT test in %s that fails when line %d of %s (`%s`) is mutated to `%s` (e.g. assert the exact boundary/arithmetic result; no mocks); change nothing else."
                       % (tp, s["line"], src, s["orig"], s["mut"]),
               "verify": verify_command(tp, src, s)}


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 0
    cmd = argv[1]
    if cmd == "scan":
        if len(argv) < 3:
            print("usage: scan <repo_dir> [--max-mutants N] [--json]")
            return 0
        if os.environ.get("OVN_MUTATION_SCAN", "on") == "off":
            print("mutation scan: OVN_MUTATION_SCAN=off - skip")
            return 0
        mx = int(os.environ.get("OVN_MUT_MAX", "40"))
        if "--max-mutants" in argv:
            mx = int(argv[argv.index("--max-mutants") + 1])
        if not os.path.exists(godot_bin()):
            print("mutation scan: godot binary %s not found - skip" % godot_bin())
            return 0
        return scan(argv[2], mx, "--json" in argv)
    if cmd == "verify":
        if len(argv) < 8:
            print("usage: verify <repo_dir> <test_file> <src_file> <line> <orig_token> <mutated_token> [<occurrence>]")
            return 1
        occ = int(argv[8]) if len(argv) > 8 else 1
        rc, msg = verify(argv[2], argv[3], argv[4], int(argv[5]), argv[6], argv[7], occ)
        print("verify: " + msg)
        return rc
    if cmd == "sites":
        for s in mutation_sites(read(argv[2])):
            print("%d:%d\t%s -> %s\t(occ %d)" % (s["line"], s["col"], s["orig"], s["mut"], s["occ"]))
        return 0
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
