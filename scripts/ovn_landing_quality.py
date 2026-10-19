#!/usr/bin/env python3
"""ovn_landing_quality.py - static false-credit detector for a fleet change (base..head), used by the stage runner's final QUALITY gate.

Why (2026-10-18 landing audit, every 'pushed(tests:pass)' of the last 6h): the full suite stayed green while the change was NOT a real
deliverable. Four shapes were found, each of which a green suite cannot see:
  TAUTOLOGY       a changed test line that can never fail: `assert <x> or True`, `assert True`, `assert_true(true)`
                  (billwatch test_legislators_refactor.py: `assert ...__module__ == "builtins" or True`).
  DISCARDED_CALL  `_ = some_call(...)` in production code: the model "used" an import only to satisfy the item's VERIFY
                  (test-automation-agent test_runs.py: `_ = is_terminal_status(test_run.status.value)`, a no-op with a comment claiming the opposite).
  DUP_DEF         a function/class defined twice in one scope: the second silently shadows the first, and in a test module a whole test never runs
                  (shrike-notify broker.py: two `async def topics_from_store`).
  UNWIRED_HELPER  a NEW private helper (`_name`) that nothing but tests ever references = dead code the item was supposed to wire in
                  (iptv engagement.py `_to_utc`, only imported by its own new test).

  TAUTOLOGY_STATUS  a test asserting `<resp>.status_code in [200, 401, 403]`: a list that spans success AND error classes accepts every outcome, so the test cannot fail on the thing it names.

2026-10-18 adversarial-review repairs (each replayed over ~3200 real fleet commits of 7 repos, see ovn_lq_replay.py):
  * a decorated function (@app.exception_handler, @app.get, @pytest.fixture, @router.*, @click.command, signal registries ...) is registered by its decorator, never UNWIRED; nested functions are not candidates;
  * a file whose BASE (or head) does not parse is skipped by DUP_DEF / UNWIRED_HELPER (a repair that closes a broken docstring made every pre-existing helper look new);
  * `@<name>.expression/.comparator/.setter/...` (hybrid_property, property) is a legitimate same-name definition, not a shadow; route/registry-decorated defs outside tests are all registered;
  * DISCARDED_CALL only fires for calls that are provably meaningless (predicates is_/has_/can_/should_*, or a bare-name function defined in the repo whose body is pure), never `_ = session.exec(..)` / `_ = os.environ.get(..)`;
  * every rule is enforced or shadow-only per OVN_LQ_RULES_ENFORCE (comma list; default = DEFAULT_ENFORCE, the rules with 0 false positives in the replay); a shadow finding prints as `~RULE<TAB>path<TAB>detail` and never makes the exit code 1.

usage: ovn_landing_quality.py check <repo_dir> <base_ref> [<head_ref>]      (head defaults to HEAD)
stdout: one finding per line, tab separated: RULE <TAB> path <TAB> detail (shadow-only rules: `~RULE`).   exit 0 = clean (or shadow-only findings), 1 = enforced findings, 2 = could not analyse (git error / bad refs).
Callers must treat rc 2 as 'no verdict' (fail open): this gate only ever REJECTS on positive evidence.
Pure stdlib, read-only (git diff / show / grep only; never writes in the repo)."""
import ast
import os
import re
import subprocess
import sys

TEST_DIR = re.compile(r"(^|/)(tests?|__tests__|spec|e2e)/", re.I)
TEST_NAME = re.compile(r"(^|/)test_[^/]*$|_test\.(py|gd|ts|tsx|js)$|(^|/)conftest\.py$|\.(spec|test)\.(ts|tsx|js)$", re.I)
# a production module can be NAMED test_*.py (test-automation-agent: app/routers/test_runs.py): outside a tests dir, a test_-prefixed file under an app-code directory is source
APP_DIR = re.compile(r"(^|/)(app|src|routers|services|api|lib|models|core|utils)/", re.I)


class _TestPath:
    @staticmethod
    def search(path):
        if TEST_DIR.search(path):
            return True
        return bool(TEST_NAME.search(path)) and not APP_DIR.search(path)


TEST_PATH = _TestPath()
PY_TAUT = [
    re.compile(r"^\s*assert\b[^#\n]*\bor\s+True\b"),
    re.compile(r"^\s*assert\s+True\s*(,|$|#)"),
    re.compile(r"^\s*assert\s+not\s+False\s*(,|$|#)"),
    re.compile(r"^\s*assert\s+1\s*==\s*1\s*(,|$|#)"),
]
GD_TAUT = [re.compile(r"^\s*assert_true\(\s*true\s*[,)]"), re.compile(r"^\s*assert_false\(\s*false\s*[,)]")]
DISCARD = re.compile(r"^\s*_\s*=\s*[A-Za-z_][\w.]*\(.*\)\s*$")
SHADOW_OK = re.compile(r"\.(setter|getter|deleter|expression|comparator|update_expression|inplace)\b|\boverload\b|\.register\b|\bsingledispatch|\bhybrid_property\b|\bproperty\b")
ALL_RULES = ("TAUTOLOGY", "TAUTOLOGY_STATUS", "DISCARDED_CALL", "DUP_DEF", "UNWIRED_HELPER")
# Replay (2026-10-18, 3159 fleet commits / 7 repos / 10 days, see test_ovn_landing_quality.sh header for the numbers): rules with zero false positives. UNWIRED_HELPER stays shadow: 3 of its 5
# residual hits were helpers a later commit legitimately wired (an item's "add helper" landing before its "wire it in" landing).
DEFAULT_ENFORCE = ("DUP_DEF",)   # 2026-10-18 review: only DUP_DEF is proven 0-FP (~150 hand-read hits over 45 days); TAUTOLOGY (string-literal samples, GD branch asserts) and DISCARDED_CALL (raise-validators) had real false positives -> shadow until the replay shows 0 FP
TRIVIAL_DECOS = {"staticmethod", "classmethod", "property", "cached_property", "cache", "lru_cache", "abstractmethod", "functools.cache", "functools.lru_cache", "functools.cached_property"}
PREDICATE = re.compile(r"^(is|has|can|should)_\w+$")
SAFE_BUILTINS = {"len", "str", "int", "float", "bool", "isinstance", "tuple", "list", "dict", "set", "sorted", "min", "max", "abs", "any", "all", "repr"}


def enforced_rules():
    raw = os.environ.get("OVN_LQ_RULES_ENFORCE")
    if raw is None:
        return set(DEFAULT_ENFORCE)
    return {r.strip() for r in raw.split(",") if r.strip() in ALL_RULES}


def git(repo, *args, ok=(0,)):
    p = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True, errors="replace")
    if p.returncode not in ok:
        raise RuntimeError("git %s: %s" % (" ".join(args[:2]), p.stderr.strip()[:200]))
    return p.stdout


def added_lines(repo, base, head, path):
    out = git(repo, "diff", "-U0", "--no-color", base + ".." + head, "--", path)
    return [l[1:] for l in out.splitlines() if l.startswith("+") and not l.startswith("+++")]


def show(repo, ref, path):
    try:
        return git(repo, "show", "%s:%s" % (ref, path))
    except RuntimeError:
        return None


def parse(src):
    """ast tree, or None when src is None / does not parse (callers skip the structural rules then: positive evidence only)."""
    if src is None:
        return None
    try:
        return ast.parse(src)
    except (SyntaxError, ValueError, RecursionError):
        return None


def _deco_texts(node):
    return [ast.unparse(d) for d in getattr(node, "decorator_list", [])]


def scope_dups(tree, is_test=False):
    """{(scope, name): n} for names defined more than once in the same scope (module or class body). tree = parsed module."""
    res = {}

    def walk(body, scope):
        seen = {}
        for node in body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                decos = _deco_texts(node)
                joined = " ".join(decos)
                if SHADOW_OK.search(joined):
                    continue
                if any(d.startswith(node.name + ".") for d in decos):   # @name.anything: part of one descriptor / hybrid definition
                    continue
                if not is_test and any(re.match(r"[A-Za-z_][\w.]*\.[A-Za-z_]\w*(\(|$)", d) for d in decos):   # @app.get(..), @router.x: every copy is registered
                    continue
                seen[node.name] = seen.get(node.name, 0) + 1
                if isinstance(node, ast.ClassDef):
                    walk(node.body, scope + "." + node.name)
        for n, c in seen.items():
            if c > 1:
                res[(scope, n)] = c

    walk(tree.body, "<module>")
    return res


def private_defs(tree):
    """Names of PRIVATE functions defined at module or class level (not nested in a function) that no decorator registers elsewhere."""
    out = set()

    def walk(body):
        for n in body:
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
                if n.name.startswith("_") and not n.name.startswith("__"):
                    if all(d in TRIVIAL_DECOS for d in _deco_texts(n)):
                        out.add(n.name)
            elif isinstance(n, ast.ClassDef):
                walk(n.body)
    walk(tree.body)
    return out


def _assert_nodes(line):
    try:
        t = ast.parse(line.strip())
    except (SyntaxError, ValueError):
        return None
    return t.body[0] if len(t.body) == 1 and isinstance(t.body[0], ast.Assert) else None


def _truthy_const(n):
    return isinstance(n, ast.Constant) and bool(n.value) and not isinstance(n.value, str)


def _status_vacuous(test):
    """`<x>.status_code in [<2xx>, <4xx|5xx>, ...]` with >= 3 members: success and error both accepted."""
    if not (isinstance(test, ast.Compare) and len(test.ops) == 1 and isinstance(test.ops[0], ast.In)):
        return False
    left = test.left
    nm = left.attr if isinstance(left, ast.Attribute) else getattr(left, "id", "")
    if nm not in ("status_code", "status", "status_int"):
        return False
    comp = test.comparators[0]
    if not isinstance(comp, (ast.List, ast.Tuple, ast.Set)):
        return False
    codes = [e.value for e in comp.elts if isinstance(e, ast.Constant) and isinstance(e.value, int)]
    return len(codes) >= 3 and len(codes) == len(comp.elts) and any(200 <= c < 300 for c in codes) and any(c >= 400 for c in codes)


def py_tautology(line):
    """-> (rule, why) or None for one added line of a python test."""
    a = _assert_nodes(line)
    if a is not None:
        t = a.test
        if _truthy_const(t):
            return ("TAUTOLOGY", "assertion can never fail")
        if isinstance(t, ast.UnaryOp) and isinstance(t.op, ast.Not) and isinstance(t.operand, ast.Constant) and not t.operand.value:
            return ("TAUTOLOGY", "assertion can never fail")
        if isinstance(t, ast.BoolOp) and isinstance(t.op, ast.Or):
            for v in t.values:
                if _truthy_const(v) or (isinstance(v, ast.UnaryOp) and isinstance(v.op, ast.Not) and isinstance(v.operand, ast.Constant) and not v.operand.value):
                    return ("TAUTOLOGY", "assertion can never fail (`or` with a constant true operand)")
        if _status_vacuous(t):
            return ("TAUTOLOGY_STATUS", "status_code accepted from both the success and the error classes")
        return None
    if any(p.search(line) for p in PY_TAUT):
        return ("TAUTOLOGY", "assertion can never fail")
    return None


def _pure_function(repo, head, name):
    """True when a non-test .py at head defines exactly one top-level `name` whose body provably has no side effect and no dependence on anything but its arguments' values."""
    try:
        out = git(repo, "grep", "-l", "-I", "-E", r"^(async )?def +%s[ (]" % re.escape(name), head, "--", "*.py", ok=(0, 1))
    except RuntimeError:
        return False
    paths = [l.split(":", 1)[1] for l in out.splitlines() if ":" in l]
    paths = [p for p in paths if not TEST_PATH.search(p)]
    if len(paths) != 1:
        return False
    tree = parse(show(repo, head, paths[0]))
    if tree is None:
        return False
    fn = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name]
    if len(fn) != 1:
        return False
    for n in ast.walk(fn[0]):
        if isinstance(n, (ast.Await, ast.Yield, ast.YieldFrom, ast.Global, ast.Nonlocal, ast.Delete, ast.AsyncFor, ast.AsyncWith)):
            return False
        if isinstance(n, ast.Call) and not (isinstance(n.func, ast.Name) and n.func.id in SAFE_BUILTINS):
            return False
        if isinstance(n, (ast.Assign, ast.AugAssign, ast.AnnAssign)):
            tg = n.targets if isinstance(n, ast.Assign) else [n.target]
            if any(isinstance(x, (ast.Attribute, ast.Subscript)) for t in tg for x in ast.walk(t)):
                return False
    return True


def discarded_call(repo, head, line):
    """-> detail when `line` is `_ = call(...)` whose result is provably meaningless, else None."""
    if not DISCARD.match(line):
        return None
    try:
        node = ast.parse(line.strip()).body[0]
    except (SyntaxError, ValueError, IndexError):
        return None
    if not (isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) and node.targets[0].id == "_" and isinstance(node.value, ast.Call)):
        return None
    f = node.value.func
    nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
    if PREDICATE.match(nm) or (isinstance(f, ast.Name) and _pure_function(repo, head, nm)):
        return "result of a pure call thrown away (`_ = %s(...)`): %s" % (nm, line.strip()[:100])
    return None


def referenced_outside_tests(repo, head, name):
    """True when a tracked non-test .py file at <head> mentions `name` anywhere other than its own `def name` line.
    Unknown (git error) counts as referenced: positive evidence only."""
    try:
        out = git(repo, "grep", "-n", "-w", "-I", name, head, "--", "*.py", ok=(0, 1))
    except RuntimeError:
        return True
    for ln in out.splitlines():
        parts = ln.split(":", 3)   # "<ref>:<path>:<line>:<text>"
        if len(parts) < 4:
            continue
        path, text = parts[1], parts[3]
        if TEST_PATH.search(path):
            continue
        if re.match(r"\s*(async\s+)?def\s+%s\b" % re.escape(name), text):
            continue
        if text.lstrip().startswith("#"):
            continue
        return True
    return False


def check(repo, base, head):
    """[(rule, path, detail)] for every finding, enforced or not (the caller / main() splits by enforced_rules()). A file that cannot be analysed is skipped (fail open)."""
    findings = []
    names = git(repo, "diff", "--name-only", "--diff-filter=AM", base + ".." + head).splitlines()
    for path in names:
        ext = os.path.splitext(path)[1]
        if ext not in (".py", ".gd"):
            continue
        try:
            findings.extend(check_file(repo, base, head, path, ext))
        except Exception:   # noqa: BLE001 - one unanalysable file never blocks or crashes the gate
            continue
    return findings


def check_file(repo, base, head, path, ext):
    findings = []
    is_test = bool(TEST_PATH.search(path))
    added = added_lines(repo, base, head, path)
    if is_test:
        for l in added:
            if l.lstrip().startswith("#"):
                continue
            if ext == ".py":
                hit = py_tautology(l)
            else:
                hit = ("TAUTOLOGY", "assertion can never fail") if any(p.search(l) for p in GD_TAUT) else None
            if hit:
                findings.append((hit[0], path, "%s: %s" % (hit[1], l.strip()[:120])))
    elif ext == ".py":
        for l in added:
            d = discarded_call(repo, head, l)
            if d:
                findings.append(("DISCARDED_CALL", path, d))
                break
    if ext == ".py":
        head_src = show(repo, head, path)
        base_src = show(repo, base, path)
        head_tree = parse(head_src)
        base_tree = parse(base_src)
        if head_tree is None or (base_src is not None and base_tree is None):
            return findings   # base or head does not parse: no structural verdict (a repair of a broken file must not inherit its whole history as 'new')
        hd = scope_dups(head_tree, is_test)
        bd = scope_dups(base_tree, is_test) if base_tree else {}
        for (scope, name), n in sorted(hd.items()):
            if n > bd.get((scope, name), 1):
                findings.append(("DUP_DEF", path, "%s defined %d times in %s (the later one shadows the earlier)" % (name, n, scope)))
        if not is_test:
            new = private_defs(head_tree) - (private_defs(base_tree) if base_tree else set())
            for name in sorted(new):
                if not referenced_outside_tests(repo, head, name):
                    findings.append(("UNWIRED_HELPER", path, "new private helper %s is referenced by nothing but tests / its own definition" % name))
    return findings


def main(argv):
    if len(argv) < 4 or argv[1] != "check":
        sys.stderr.write(__doc__)
        return 2
    repo, base = argv[2], argv[3]
    head = argv[4] if len(argv) > 4 else "HEAD"
    try:
        f = check(repo, base, head)
    except Exception as e:   # noqa: BLE001 - fail open by contract
        sys.stderr.write("ovn_landing_quality: %s\n" % e)
        return 2
    enf = enforced_rules()
    hard = 0
    for r in f:
        if r[0] in enf:
            hard += 1
            print("\t".join(r))
        else:
            print("\t".join(("~" + r[0],) + tuple(r[1:])))
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
