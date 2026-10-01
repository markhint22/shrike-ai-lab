#!/usr/bin/env python3
"""card_lint.py - DETERMINISTIC linter for an acceptance card (gate S0). No model, no network, no repo mutation.

A card is {bullets:[3-7 checkable statements], verify_cmd:str, files:[str], risk_class:"A|B|C", needs_human_review:bool}.
Qwen drafts it; this module decides whether it is *usable*. Everything here is a pure function of (card, item, repo_root), so it is
unit-testable without the model. Findings carry a severity:

  error  - the card is unusable (a check that cannot fail, unsafe command, wrong direction, path that does not exist, vague bullets)
  flag   - the card is usable but suspicious (alternation, weak assertion on a structural item, risk understated, off-topic bullet)

Each finding is {"rule": str, "severity": "error"|"flag", "msg": str}. `lint_card` returns {"errors":[...], "flags":[...], "info":{...}}.

CLI:  python3 card_lint.py --card card.json [--item "text"] [--item-path rel/path.py] [--repo-root DIR]
      python3 card_lint.py --verify 'grep -q foo a.py' ...   (lints a bare VERIFY command, e.g. one already in the backlog)
Prints one JSON object. Exit 0 always (it is a library first).
"""
import ast
import glob
import json
import os
import re
import shlex
import sys

RISK_ORDER = {"A": 3, "B": 2, "C": 1}  # A = highest risk (Mark approves class A cards)
MAX_VERIFY_LEN = 600

# ---------------------------------------------------------------------------------------------------------------- shell scanner
_OPS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
_REDIR_PREFIX = (">", "<")


def _newlines_to_semicolons(cmd):
    """Replace UNQUOTED newlines with ' ; ' (shlex treats newline as plain whitespace)."""
    out, q, esc = [], None, False
    for ch in cmd:
        if esc:
            out.append(ch)
            esc = False
            continue
        if ch == "\\" and q != "'":
            esc = True
            out.append(ch)
            continue
        if q:
            if ch == q:
                q = None
            out.append(ch)
            continue
        if ch in ("'", '"'):
            q = ch
            out.append(ch)
        elif ch == "\n":
            out.append(" ; ")
        else:
            out.append(ch)
    return "".join(out)


def _extract_substitutions(cmd):
    """Replace each balanced, quote-aware $( ... ) by a placeholder word; return (new_cmd, [inner_text])."""
    out, inner, i, n = [], [], 0, len(cmd)
    q = None
    while i < n:
        ch = cmd[i]
        if ch == "\\" and q != "'" and i + 1 < n:
            out.append(cmd[i:i + 2])
            i += 2
            continue
        if q:
            if ch == q:
                q = None
            elif ch == "$" and q == '"' and cmd[i + 1:i + 2] == "(":
                pass
            else:
                out.append(ch)
                i += 1
                continue
        elif ch in ("'", '"'):
            q = ch
            out.append(ch)
            i += 1
            continue
        if ch == "$" and cmd[i + 1:i + 2] == "(" and cmd[i + 2:i + 3] != "(" and q != "'":
            depth, j, iq = 1, i + 2, None
            while j < n and depth:
                c = cmd[j]
                if iq:
                    if c == iq:
                        iq = None
                elif c in ("'", '"'):
                    iq = c
                elif c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                j += 1
            inner.append(cmd[i + 2:j - 1])
            out.append("__SUBST%d__" % (len(inner) - 1))
            i = j
            continue
        out.append(ch)
        i += 1
    return "".join(out), inner


def parse_shell(cmd):
    """Parse a simple shell command line into statements.
    Returns (segments, problems, substitutions[list of inner command strings]). segments = [{"words":[...], "op":<operator that FOLLOWS this segment or None>, "redirs":[(op,target)],
    "neg":bool, "raw_first":str}]. problems = [str] (unparseable / unsupported constructs)."""
    problems = []
    cmd, substs = _extract_substitutions(cmd)
    if "`" in cmd:
        problems.append("backtick command substitution is not allowed")
    if "<<" in cmd:
        problems.append("heredocs are not allowed")
    try:
        lex = shlex.shlex(_newlines_to_semicolons(cmd), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError as ex:
        return [], ["unparseable shell (%s)" % ex], substs
    segs, cur, redirs = [], [], []
    i = 0

    def close(op):
        nonlocal cur, redirs
        if cur or redirs:
            words = list(cur)
            neg = False
            while words and words[0] == "!":
                neg = not neg
                words.pop(0)
            segs.append({"words": words, "op": op, "redirs": redirs, "neg": neg})
        elif op and segs and segs[-1]["op"] is None:
            segs[-1]["op"] = op
        cur, redirs = [], []

    while i < len(toks):
        t = toks[i]
        if t in _OPS:
            close(t)
        elif t and (t[0] in _REDIR_PREFIX or t in ("&>", "&>>")) and set(t) <= set("<>&|"):
            # redirect operator; the next token is its target. Drop a preceding bare fd number (2>/dev/null).
            if cur and cur[-1].isdigit():
                cur.pop()
            tgt = toks[i + 1] if i + 1 < len(toks) else ""
            if t.endswith("&") and t.startswith(">") and (tgt.isdigit() or tgt == "-"):
                tgt = "&" + tgt  # >&2 / 2>&1: fd duplication, not a file
            redirs.append((t, tgt))
            i += 1
        else:
            cur.append(t)
        i += 1
    close(None)
    return segs, problems, substs


_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_WRAPPERS = {"time", "nice", "command", "env", "exec", "builtin"}


def _strip_prefix(words):
    """Drop leading VAR=val, and wrappers (time/nice/env/timeout N). Returns (words, env_assigns)."""
    w = list(words)
    envs = []
    while w:
        if _ASSIGN.match(w[0]):
            envs.append(w.pop(0))
        elif w[0] in _WRAPPERS:
            w.pop(0)
            while w and (w[0].startswith("-") or _ASSIGN.match(w[0])):
                w.pop(0)
        elif w[0] == "timeout":
            w.pop(0)
            while w and w[0].startswith("-"):
                w.pop(0)
            if w and re.match(r"^\d+[smh]?$", w[0]):
                w.pop(0)
        else:
            break
    return w, envs


def head_of(words):
    w, _ = _strip_prefix(words)
    if not w:
        return ""
    h = os.path.basename(w[0]) if "/" in w[0] else w[0]
    h = re.sub(r"^(python|pip)[0-9.]*$", r"\1", h)
    if h == "py.test":
        h = "pytest"
    return h


# ---------------------------------------------------------------------------------------------------------------- command policy
ALLOWED = {
    "grep", "egrep", "fgrep", "rg", "test", "[", "[[", "python", "pytest", "npx", "vitest", "npm", "node", "diff", "cmp", "jq", "ruff",
    "mypy", "alembic", "ls", "cat", "wc", "head", "tail", "sort", "uniq", "cut", "tr", "sed", "awk", "echo", "printf", "true", "false",
    ":", "cd", "set", "export", "pwd", "find", "stat", "file", "basename", "dirname", "git", "tsc", "eslint", "exit", "sh_never",
}
FORBIDDEN_HINT = {
    "rm": "destructive", "mv": "destructive", "cp": "writes files", "curl": "network", "wget": "network", "ssh": "network", "scp": "network",
    "sudo": "privileged", "docker": "container", "kill": "process control", "pkill": "process control", "chmod": "mutates files",
    "chown": "mutates files", "dd": "destructive", "tee": "writes files", "xargs": "runs arbitrary commands", "eval": "arbitrary code",
    "bash": "nested shell", "sh": "nested shell", "zsh": "nested shell", "source": "arbitrary code", ".": "arbitrary code", "pip": "network install",
    "make": "arbitrary targets", "touch": "writes files", "mkdir": "writes files", "ln": "writes files", "nc": "network", "ping": "network",
    "uvicorn": "starts a server", "gunicorn": "starts a server", "flask": "starts a server", "railway": "network", "vercel": "network",
    "fly": "network", "flyctl": "network", "gh": "network", "open": "side effects", "osascript": "side effects",
}
GIT_READONLY = {"diff", "grep", "ls-files", "show", "log", "status", "cat-file", "rev-parse"}
NPM_OK = {"test", "t", "run"}
NPM_RUN_OK = re.compile(r"^(test|test:\w+|lint|typecheck|type-check|check)$")
NPX_OK = {"vitest", "tsc", "eslint", "jest", "prettier"}
UNSAFE_PY = re.compile(r"\b(os\.system|os\.popen|os\.remove|os\.unlink|os\.rmdir|os\.rename|shutil\.|subprocess|socket|urllib|requests\.|httpx\.(get|post|put|delete|request)|"
                       r"__import__|eval\(|exec\(|rmtree|unlink\(|\.write_text|\.write_bytes|\.unlink|\.rmdir|\.mkdir|ftplib|smtplib)\b")
PY_WRITE_OPEN = re.compile(r"open\([^)]*['\"][wax+][b+]?['\"]")

FILTERS = {"wc", "head", "tail", "cat", "sort", "uniq", "cut", "tr", "awk", "sed", "echo", "printf", "true", "false", ":", "tee", "ls", "nl", "column"}
NONASSERT = {"cd", "set", "export", "pwd", "echo", "printf", "true", "false", ":", "basename", "dirname", "exit"}

# ---- sandbox-escape policy for commands that ARE on the allowlist (reviewer repro 2026-10-01: awk system(), process substitution
# <(...) / >(...), sed e/w/r commands, and file-writing flags all reached the exec check, which then RAN them).
AWK_UNSAFE = re.compile(r"system\s*\(|getline|\|\s*&?\s*[\"']?\s*[A-Za-z/]|print[f]?\b[^;}]*>|ENVIRON|@include|@load|\bfflush\s*\(|-f\b")
_SED_S = re.compile(r"s(?P<d>[^\w\s\\])(?:(?!(?P=d))[^\\]|\\.)*(?P=d)(?:(?!(?P=d))[^\\]|\\.)*(?P=d)(?P<f>[0-9a-zA-Z]*)")


def _sed_unsafe(args):
    """Why this sed invocation is not a plain s///, address, print/delete script (or None). Rejects -f, e/w/r/W/R/a/i/c/y/... commands and the s///e|w flags."""
    scripts, i, a = [], 0, list(args)
    while i < len(a):
        x = a[i]
        if x in ("-e", "--expression"):
            scripts.append(a[i + 1] if i + 1 < len(a) else ""); i += 2; continue
        if x.startswith("--expression="):
            scripts.append(x.split("=", 1)[1]); i += 1; continue
        if x in ("-f", "--file") or x.startswith("--file="):
            return "-f reads a script file"
        if x.startswith("-") and x != "-":
            i += 1; continue
        if not scripts:
            scripts.append(x)
        i += 1
    for sc in scripts:
        rem = sc
        bad = []
        def _r(m):
            if re.search(r"[ew]", m.group("f")):
                bad.append("s///%s" % m.group("f"))
            return ""
        rem = _SED_S.sub(_r, rem)
        if bad:
            return bad[0]
        rem = re.sub(r"/(?:[^/\\]|\\.)*/[IM]*", "", rem)          # /regex/ addresses
        left = re.sub(r"[pPdDnNq=]", "", rem)
        if re.search(r"[A-Za-z]", left):
            return "command letter in script %r" % rem[:40]
    return None


def extra_unsafe(h, args):
    """List of reasons the allowlisted command `h` with `args` can run other commands or write files."""
    why = []
    j = " ".join(args)
    if h == "awk" and AWK_UNSAFE.search(j):
        why.append("awk program can run commands or write files (system/getline/pipe/redirect/ENVIRON/-f)")
    if h == "sed":
        r = _sed_unsafe(args)
        if r:
            why.append("sed script is not a plain s///, address, or print/delete (%s)" % r)
    if h == "sort" and any(x in ("-o", "--output") or x.startswith("--output=") or (x.startswith("-o") and not x.startswith("--")) for x in args):
        why.append("sort -o writes a file")
    if h == "git" and any(x.startswith("--output") for x in args):
        why.append("git --output writes a file")
    if h in ("rg",) and any(x.startswith("--pre") for x in args):
        why.append("rg --pre runs a command")
    if h in ("ruff", "eslint") and any(x.startswith("--fix") or x == "--unsafe-fixes" for x in args):
        why.append("%s --fix modifies files" % h)
    if h == "find" and any(x in ("-fls", "-fprint0", "-fprintf") for x in args):
        why.append("find -fls/-fprintf writes a file")
    return why


def _parse_py(code):
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return ast.parse(code)


def _py_code_arg(words):
    w, _ = _strip_prefix(words)
    if "-c" in w:
        i = w.index("-c")
        return w[i + 1] if i + 1 < len(w) else ""
    return None


def _py_module_arg(words):
    w, _ = _strip_prefix(words)
    if "-m" in w:
        i = w.index("-m")
        return w[i + 1] if i + 1 < len(w) else ""
    return None


def classify_segment(seg):
    """Return (kind, strength, detail) for a segment. kind: assert|filter|nonassert|other.
    strength (assert only): strong | weak | exists. exists = the thing is merely there / importable / compiles (cannot distinguish done from not-done
    in any meaningful way); weak = source-text grep (self-referential for a symbol the item adds); strong = executes behaviour."""
    words, _ = _strip_prefix(seg["words"])
    h = head_of(seg["words"])
    if not h:
        return "nonassert", None, ""
    if h in ("grep", "egrep", "fgrep", "rg"):
        return "assert", "weak", "grep"
    if h in ("test", "[", "[[", "stat", "file"):
        toks = [x for x in words[1:] if x not in ("]", "]]")]
        # existence-only unless a comparison / count / emptiness test is present
        compar = any(x in ("=", "==", "!=", "-eq", "-ne", "-gt", "-ge", "-lt", "-le", "-z", "-n", "-nt", "-ot") for x in toks)
        return "assert", ("strong" if compar else "exists"), "test"
    if h == "python":
        code = _py_code_arg(seg["words"])
        mod = _py_module_arg(seg["words"])
        if mod in ("pytest", "unittest"):
            return "assert", "strong", "pytest"
        if mod in ("py_compile", "compileall"):
            return "assert", "exists", "syntax"
        if code is not None:
            has_assert = bool(re.search(r"\bassert\b|sys\.exit|raise\b", code))
            body = re.sub(r"\b(import|from)\b[^;\n]*", "", code)
            body = re.sub(r"os\.path\.(exists|isfile|isdir)\s*\(", "EXISTS_CHECK(", body)
            calls = [c for c in re.findall(r"\b[A-Za-z_][\w.]*\s*\(", re.sub(r"\bassert\b|\bprint\s*\(", "", body)) if not c.startswith("EXISTS_CHECK")]
            if re.search(r"ast\.parse|compile\(|py_compile", code) and not has_assert:
                return "assert", "exists", "syntax"
            if re.search(r"getsource|\.read\(|read_text|ast\.parse|\bopen\(", code):
                return "assert", ("weak" if has_assert else "exists"), "py-c-source-text"
            compares = bool(re.search(r"assert\b[^;]*(==|!=|\bnot in\b|\bin\b|\bis\b|<=|>=|<|>)", code))
            if has_assert and (calls or compares):
                return "assert", "strong", "py-c"
            return "assert", "exists", "py-c-import-or-exists-only"
        return "assert", "strong", "python-script"
    if h in ("pytest", "vitest", "jest"):
        return "assert", "strong", "tests"
    if h == "npx" and len(words) > 1 and os.path.basename(words[1]) in ("vitest", "jest"):
        return "assert", "strong", "tests"
    if h == "npm":
        return "assert", "strong", "tests"
    if h in ("mypy", "ruff", "tsc", "eslint") or (h == "npx"):
        return "assert", "weak", "static"
    if h in ("diff", "cmp"):
        return "assert", "strong", "diff"
    if h == "jq":
        return ("assert", "strong", "jq-e") if any(x in ("-e", "--exit-status") or re.match(r"^-[a-zA-Z]*e[a-zA-Z]*$", x) for x in words[1:]) else ("filter", None, "jq")
    if h == "alembic":
        sub = [x for x in words[1:] if not x.startswith("-")]
        return "assert", ("exists" if (sub and sub[0] in ("heads", "current", "history")) else "strong"), "alembic"
    if h == "ls":
        return "assert", "exists", "ls"
    if h == "find":
        return "assert", "exists", "find"
    if h == "git":
        sub = [x for x in words[1:] if not x.startswith("-")]
        if sub and sub[0] == "grep":
            return "assert", "weak", "grep"
        if sub and sub[0] == "diff":
            return "assert", "strong", "git-diff"
        return "filter", None, "git"
    if h == "node":
        return "assert", "strong", "node"
    if h in FILTERS:
        return "filter", None, h
    if h in NONASSERT:
        return "nonassert", None, h
    return "other", None, h


# ---------------------------------------------------------------------------------------------------------------- item model
_VERIFY_SPLIT = re.compile(r"\s+VERIFY:\s*", re.I)
_TAG = re.compile(r"^\s*\[[^\]]*\]\s*")
_PATH_RE = re.compile(r"[\w./-]+\.(?:py|ts|tsx|js|jsx|json|md|ya?ml|toml|ini|cfg|txt|sh|vue|gd|swift|kt|css|html)\b")

EXCLUDED_EXT = {".gd": "GDScript", ".swift": "Swift", ".kt": "Kotlin", ".kts": "Kotlin", ".vue": "UI (Vue)", ".tsx": "UI (TSX)", ".jsx": "UI (JSX)",
                ".css": "UI (CSS)", ".html": "UI (HTML)", ".xml": "UI/XML", ".storyboard": "UI", ".xib": "UI", ".scss": "UI (CSS)"}
NONCODE_EXT = {".md", ".txt", ".json", ".yml", ".yaml", ".toml", ".ini", ".cfg", ".env", ".lock", ".png", ".svg", ".sh"}


def parse_item_line(line):
    """Parse one backlog/progress line ("- [ ] [T3] path.py — description. VERIFY: cmd. (cat:x; multifile:no) [feat:...]").
    Returns dict {raw, tier, path, desc, verify, cat, status_tags} or None if it is not a recognizable item."""
    s = line.strip()
    s = re.sub(r"^-\s*\[[ xX]\]\s*", "", s)
    tags = []
    while True:
        m = _TAG.match(s)
        if not m:
            break
        tags.append(m.group(0).strip()[1:-1])
        s = s[m.end():]
    tier = next((t for t in tags if re.match(r"^T\d$", t)), None)
    cat = None
    changed = True
    while changed:  # peel trailing annotations in any order: <!-- ... -->, [feat:...], (cat:..; multifile:..), (roadmap:..), (retired ...)
        changed = False
        for pat in (r"\s*<!--.*?-->\s*$", r"\s*\[feat:[^\]]*\]\s*$", r"\s*\((?:cat|roadmap|recovery|multifile|retired)[^)]*\)\s*$"):
            m = re.search(pat, s, re.S)
            if m:
                mc = re.search(r"cat:\s*([\w-]+)", m.group(0))
                if mc and not cat:
                    cat = mc.group(1)
                s = s[:m.start()].rstrip()
                changed = True
    parts = _VERIFY_SPLIT.split(s, maxsplit=1)
    head, verify = parts[0], (parts[1] if len(parts) > 1 else None)
    if verify is not None:
        verify = verify.strip()
        mspan = re.match(r"^`([^`]+)`", verify)  # "`cmd` passes" / "`cmd` returns non-zero": the command is the first backtick span
        if mspan:
            verify = mspan.group(1).strip()
        else:
            verify = verify.rstrip(".").strip().strip("`").strip()
    mm = re.match(r"^(\S+?)\s+[—–-]{1,2}\s+(.*)$", head, re.S)
    if not mm:
        return None
    path, desc = mm.group(1).strip("`"), mm.group(2).strip()
    if "/" not in path and not _PATH_RE.fullmatch(path):
        return None
    return {"raw": line.strip(), "tier": tier, "path": path, "desc": desc, "verify": verify, "cat": cat, "tags": tags}


def eligibility(item):
    """(eligible:bool, reason:str). Pilot scope: python + vitest unit/API items only; UI/GDScript/Swift/Kotlin and non-code are excluded."""
    path = item.get("path", "")
    ext = os.path.splitext(path)[1].lower()
    if ext in EXCLUDED_EXT:
        return False, "excluded language/UI: %s" % EXCLUDED_EXT[ext]
    if ext in NONCODE_EXT:
        return False, "non-code target (%s)" % ext
    if ext in (".ts", ".js", ".mjs") and re.search(r"(^|/)(frontend|web|ui|src/components|src/pages|src/views)/", path) and not re.search(r"\.(test|spec)\.", path) \
            and not re.search(r"(^|/)(utils?|lib|stores?|api|services?)/", path):
        return False, "UI-adjacent TS/JS"
    if ext not in (".py", ".ts", ".js", ".mjs"):
        return False, "unsupported target type (%s)" % (ext or "none")
    if re.search(r"\b(css|tailwind|stylesheet|template|\.vue|component|render|button|modal|dropdown|badge|chart|layout|color|colour|sparkline|page)\b", item.get("desc", ""), re.I) \
            and ext != ".py":
        return False, "UI-flavoured item"
    return True, ""


_NOCHANGE = re.compile(r"\bno (code |further |additional )?changes? (are |is )?(needed|required|necessary)|nothing to (change|do|add)|already (done|implemented|in place)|ensure .* is clean|no-?op\b"
                       r"|^\s*(confirm|verify|audit|investigate|review|check whether)\b", re.I)
_REMOVE = re.compile(r"^(delete|remove|drop|unlink|strip|eliminate|deprecate and remove|get rid of)\b", re.I)
_REPLACE = re.compile(r"\b(replace|rename|swap|migrate)\b.*\b(with|to|by|for)\b|^\s*rename\b|^\s*replace\b", re.I)
_STRUCT = re.compile(r"\b(rename|replace|hard-?coded|constants?|import(s|ing)?|columns?|fields?|attributes?|type hints?|annotations?|docstrings?|re-?exports?|aliases|alias|"
                     r"dependenc(y|ies)|version|settings?|env(ironment)? var(iable)?s?|default values?|migration)\b", re.I)
_BEHAVIOUR_HINT = re.compile(r"\b(return|returns|raise|raises|handle|handles|validate|validates|implement|compute|calculate|logic|endpoint|route|redirect|call|calls|reject|"
                             r"increment|decrement|check|enforce|filter|sort|parse|format|retry|fetch|store|persist|emit|send|post|get|put|patch|status|401|403|404|429|500)\b", re.I)


def classify_item(item):
    """Infer the item kind and direction deterministically. kind: nochange|delete|test|structural|behaviour. direction: negative|replace|positive."""
    desc, path = item.get("desc", ""), item.get("path", "")
    if _NOCHANGE.search(desc):
        return {"kind": "nochange", "direction": "positive"}
    is_test_path = bool(re.search(r"(^|/)(tests?|__tests__)/|\.(test|spec)\.[jt]sx?$|_test\.py$", path)) or (item.get("cat") == "test")
    direction = "positive"
    if _REMOVE.search(desc):
        direction = "negative"
    elif _REPLACE.search(desc):
        direction = "replace"
    if direction == "negative" and re.match(r"^(delete|remove|drop|unlink)\s+(the\s+)?(dead\s+|stub\s+|leftover\s+|unused\s+|obsolete\s+)*(file|module|router|script|stub)", desc, re.I):
        return {"kind": "delete", "direction": "negative"}
    if is_test_path and re.match(r"^(create|add|write|extend|append|update)\b", desc, re.I):
        return {"kind": "test", "direction": "positive"}
    if direction == "negative":
        return {"kind": "structural", "direction": "negative"}
    if _STRUCT.search(desc) and not _BEHAVIOUR_HINT.search(desc):
        return {"kind": "structural", "direction": direction}
    if direction == "replace" and not _BEHAVIOUR_HINT.search(desc):
        return {"kind": "structural", "direction": direction}
    return {"kind": "behaviour", "direction": direction}


_RISK_A = re.compile(r"auth|login|password|passwd|token|jwt|billing|payment|stripe|subscri|entitle|paywall|quota|tier|role|permission|migration|alembic|secret|webhook|signature|"
                     r"encrypt|revenuecat|credential|api[_-]?key|session|csrf|cors|rate[_-]?limit|tenant|customer_id|delete.*account|pii", re.I)
_RISK_B = re.compile(r"routers?/|models?/|schemas?/|services?/|endpoint|api/|database|db\b|sql|worker|queue|scheduler|websocket|middleware|main\.py", re.I)


def risk_floor(item, card_files=()):
    blob = " ".join([item.get("path", ""), item.get("desc", "")] + list(card_files or []))
    if _RISK_A.search(blob):
        return "A"
    if _RISK_B.search(blob):
        return "B"
    return "C"


# ---------------------------------------------------------------------------------------------------------------- rules
def _f(rule, sev, msg):
    return {"rule": rule, "severity": sev, "msg": msg}


_VAGUE = re.compile(r"\b(works? (correctly|properly|well|as expected|fine)|(is|are|be) (handled|working) (correctly|properly)|(correctly|properly|appropriately|gracefully|"
                    r"as expected|robustly|efficiently|cleanly|successfully)\b|should work|functions? (correctly|properly)|behaves? (correctly|properly|as expected)|"
                    r"is (correct|good|fine|clean|robust|efficient)\b|looks? (good|right|correct)|no (issues|problems|bugs|errors)\b|well[- ]tested|production[- ]ready)", re.I)
_OBSERVABLE = re.compile(r"`[^`]+`|\"[^\"]+\"|'[^']+'|\b[1-5]\d\d\b|\b\d+(\.\d+)?\b|==|!=|\bexit(s)? (code )?\d|\bstatus\b.*\b\d{3}\b|\w+_\w+|\b[a-z]+[A-Z]\w+|\w+\.\w+\(|\w+/\w+")
_STOP = set("the a an and or of to in on for with from by is are be as at it its this that these those into when if then else not no any all each per via using use "
            "add create implement update modify make ensure new existing file function method class module test tests unit should must will can may one two".split())


def _tokens(s):
    return {t for t in re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", s.lower()) if t not in _STOP}


def lint_schema(card):
    errs = []
    if not isinstance(card, dict):
        return [_f("schema", "error", "card is not a JSON object")]
    b = card.get("bullets")
    if not isinstance(b, list) or not all(isinstance(x, str) for x in b):
        errs.append(_f("schema", "error", "bullets must be a list of strings"))
    elif not (3 <= len(b) <= 7):
        errs.append(_f("bullet-count", "error", "need 3-7 bullets, got %d" % len(b)))
    v = card.get("verify_cmd")
    if not isinstance(v, str) or not v.strip():
        errs.append(_f("verify-missing", "error", "verify_cmd is missing or empty"))
    elif len(v) > MAX_VERIFY_LEN:
        errs.append(_f("verify-too-long", "error", "verify_cmd longer than %d chars" % MAX_VERIFY_LEN))
    fl = card.get("files")
    if not isinstance(fl, list) or not all(isinstance(x, str) and x for x in fl) or not (1 <= len(fl) <= 8):
        errs.append(_f("schema", "error", "files must be a list of 1-8 non-empty strings"))
    else:
        for x in fl:
            if os.path.isabs(x) or ".." in x.split("/"):
                errs.append(_f("files-unsafe", "error", "files entry %r is absolute or escapes the repo" % x))
    if card.get("risk_class") not in RISK_ORDER:
        errs.append(_f("schema", "error", "risk_class must be one of A|B|C"))
    if not isinstance(card.get("needs_human_review"), bool):
        errs.append(_f("schema", "error", "needs_human_review must be a boolean"))
    return errs


def lint_bullets(card, item):
    out = []
    bullets = [x for x in (card.get("bullets") or []) if isinstance(x, str)]
    seen = set()
    item_toks = _tokens(item.get("desc", "") + " " + item.get("path", "") + " " + (card.get("verify_cmd") or ""))
    for i, b in enumerate(bullets, 1):
        t = b.strip()
        if len(t) < 12:
            out.append(_f("bullet-short", "error", "bullet %d is too short to be checkable: %r" % (i, t[:40])))
            continue
        if len(t) > 320:
            out.append(_f("bullet-long", "flag", "bullet %d is over 320 chars" % i))
        v = _VAGUE.search(t)
        if v and not _OBSERVABLE.search(t[:v.start()] + " " + t[v.end():]):
            out.append(_f("bullet-vague", "error", "bullet %d is vague (%r) with no concrete observable (value, status code, identifier, path)" % (i, v.group(0))))
        elif not _OBSERVABLE.search(t):
            out.append(_f("bullet-unspecific", "flag", "bullet %d names no concrete identifier/value/path: %r" % (i, t[:60])))
        key = re.sub(r"\W+", " ", t.lower()).strip()
        if key in seen:
            out.append(_f("bullet-duplicate", "flag", "bullet %d duplicates an earlier bullet" % i))
        seen.add(key)
        if item_toks and not (_tokens(t) & item_toks):
            out.append(_f("bullet-offtopic", "flag", "bullet %d shares no vocabulary with the item or the verify command" % i))
    return out


def _is_pathlike(w):
    if not w or w.startswith("-") or "://" in w or any(c in w for c in "$<>{}|;&!\n") or "=" in w:
        return False
    if w.startswith("/dev/"):
        return False
    base = w.split("::")[0]
    return "/" in base or bool(_PATH_RE.fullmatch(base))


def _skip_values(words, opts):
    """Return words with the value that follows each option in `opts` removed."""
    out, skip = [], False
    for w in words:
        if skip:
            skip = False
            continue
        if w in opts:
            skip = True
            continue
        out.append(w)
    return out


_PYTEST_VAL_OPTS = {"-k", "-m", "-p", "-c", "-o", "-W", "--deselect", "--ignore", "--junitxml", "--rootdir", "--cov", "--cov-report", "--maxfail", "-n", "--tb", "--durations"}
_GREP_VAL_OPTS = {"-e", "-f", "-m", "-A", "-B", "-C", "--include", "--exclude", "--exclude-dir", "-d", "-D"}


def extract_paths(segs):
    """Collect (path, negated_existence_ok) referenced as FILES by the command (grep patterns / -c code / option values excluded).
    Honors `cd`. Returns (paths:[(rel_to_repo_path, skip_existence)], cd_targets:[str])."""
    paths, cds = [], []
    cwd = ""
    for s in segs:
        words, _ = _strip_prefix(s["words"])
        if not words:
            continue
        h = head_of(s["words"])
        args = words[1:]
        if h == "cd":
            if args:
                tgt = args[0]
                cds.append(os.path.normpath(os.path.join(cwd, tgt)))
                cwd = os.path.normpath(os.path.join(cwd, tgt))
            continue
        cand = []
        skip_exist = bool(s["neg"])
        if h in ("grep", "egrep", "fgrep", "rg"):
            a = [x for x in args]
            has_e = any(x in ("-e", "-f") or x.startswith("--regexp") for x in a)
            a = _skip_values(a, _GREP_VAL_OPTS)
            pos = [x for x in a if not x.startswith("-")]
            cand = pos if has_e else pos[1:]
        elif h in ("test", "[", "[["):
            toks = [x for x in args if x not in ("]", "]]")]
            negated = "!" in toks
            for j, x in enumerate(toks):
                if x in ("-e", "-f", "-d", "-s", "-r", "-x", "-w", "-L", "-h") and j + 1 < len(toks):
                    if not (negated or s["neg"]):
                        cand.append(toks[j + 1])
        elif h == "python":
            if _py_code_arg(s["words"]) is not None:
                cand = []
            elif _py_module_arg(s["words"]):
                m = _py_module_arg(s["words"])
                i = args.index("-m")
                cand = _skip_values(args[i + 2:], _PYTEST_VAL_OPTS) if m in ("pytest", "unittest") else []
            else:
                cand = [x for x in args if not x.startswith("-")][:1]
        elif h == "pytest":
            cand = _skip_values(args, _PYTEST_VAL_OPTS)
        elif h in ("vitest",) or (h == "npx" and args and os.path.basename(args[0]) in ("vitest", "jest")):
            cand = [x for x in (args[1:] if h == "npx" else args) if x not in ("run", "watch")]
        elif h in ("ls", "cat", "wc", "head", "tail", "stat", "file", "diff", "cmp", "sort", "uniq", "cut", "jq", "mypy", "ruff", "node"):
            cand = list(args)
            if h == "jq":
                cand = cand[1:]
            if h in ("ruff",):
                cand = [x for x in cand if x not in ("check", "format")]
        for w in cand:
            if w.startswith("-"):
                continue
            if _is_pathlike(w):
                paths.append((os.path.normpath(os.path.join(cwd, w.split("::")[0])), skip_exist))
    return paths, cds


def _exists(repo_root, rel):
    p = os.path.join(repo_root, rel)
    if any(c in rel for c in "*?["):
        return bool(glob.glob(p))
    return os.path.exists(p)


def _repo_has_word(repo_root, tok, word=True):
    """True if `tok` occurs (as a whole word unless word=False) in any .py/.ts/.js/.json file of the checkout (node_modules/.venv/.git excluded)."""
    import subprocess
    try:
        r = subprocess.run(["grep", "-rqwF" if word else "-rqF", "--include=*.py", "--include=*.ts", "--include=*.js", "--include=*.json", "--exclude-dir=.git",
                            "--exclude-dir=node_modules", "--exclude-dir=.venv", "--exclude-dir=venv", "-e", tok, repo_root],
                           capture_output=True, timeout=20)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return True  # cannot tell -> do not flag


_IDENT_LIT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{3,}$")


def _unknown_literals(segs, inner_all, repo_root, item):
    """FLAG string literals inside `python -c` that look like identifiers (CamelCase / snake_case) and appear in neither the item text nor the repo:
    a hallucinated name asserted on will fail before AND after the change (e.g. `'RateLimiter' in str(type(dep))` when the repo uses slowapi's limiter)."""
    out, seen = [], set()
    desc = item.get("desc", "") + " " + item.get("path", "")
    for sg in list(segs) + [x for isegs in inner_all for x in isegs]:
        if head_of(sg["words"]) != "python":
            continue
        code = _py_code_arg(sg["words"])
        if not code:
            continue
        try:
            tree = _parse_py(code)
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and _IDENT_LIT.match(node.value) \
                    and (("_" in node.value) or (node.value != node.value.lower() and node.value != node.value.upper())):
                tok = node.value
                if tok in seen or tok.lower() in desc.lower():
                    continue
                seen.add(tok)
                if len(seen) > 8:
                    return out
                if not _repo_has_word(repo_root, tok):
                    out.append(_f("literal-not-in-repo", "flag", "the check asserts on the name %r which appears in neither the item nor the repo (hallucinated identifier?)" % tok))
    return out


def _cwd_segments(segs):
    """Yield (cwd_relative_to_repo, segment), tracking `cd X` as it appears in the chain."""
    cwd = ""
    for sg in segs:
        words, _ = _strip_prefix(sg["words"])
        if words and head_of(sg["words"]) == "cd" and len(words) > 1:
            cwd = os.path.normpath(os.path.join(cwd, words[1]))
            continue
        yield cwd, sg


def _read(repo_root, rel, limit=400000):
    try:
        with open(os.path.join(repo_root, rel), errors="replace") as f:
            return f.read(limit)
    except OSError:
        return None


def _is_target(rel, item, mentioned):
    """True if `rel` (repo-relative) is the file the item creates/modifies, or a path the item names."""
    rel = os.path.normpath(rel)
    for m in set(mentioned) | {item.get("path", "")}:
        if m and (rel == os.path.normpath(m) or rel.endswith("/" + os.path.normpath(m)) or os.path.normpath(m).endswith("/" + rel)):
            return True
    return False


def _resolve_python_refs(sg, cwd, repo_root, item, mentioned):
    """Static checks that catch hallucinated references INSIDE a verify: (1) `python -c` imports of repo-local modules/names that do not exist at the
    base ref and that the item does not create; (2) pytest node ids (file::test_name) whose test function does not exist and is not added by the item."""
    out = []
    words, _ = _strip_prefix(sg["words"])
    h = head_of(sg["words"])
    desc = item.get("desc", "")
    cands = []
    if h == "pytest":
        cands = words[1:]
    elif h == "python" and _py_module_arg(sg["words"]) == "pytest" and "-m" in words:
        cands = words[words.index("-m") + 2:]
    for w in cands:
        if "::" not in w or w.startswith("-"):
            continue
        parts = w.split("::")
        rel = os.path.normpath(os.path.join(cwd, parts[0]))
        if _is_target(rel, item, mentioned):
            continue
        txt = _read(repo_root, rel)
        if txt is None:
            continue  # a missing file is reported by the path rule
        for nm in parts[1:]:
            nm = re.sub(r"\[.*\]$", "", nm)
            if nm and not re.search(r"(def|class)\s+%s\b" % re.escape(nm), txt) and nm not in desc:
                out.append(_f("test-id-missing", "error", "pytest id %s::%s does not exist at the base ref and the item does not add it (it would fail before AND after)" % (parts[0], nm)))
    if "-k" in cands:
        i = cands.index("-k")
        expr = cands[i + 1] if i + 1 < len(cands) else ""
        files = [os.path.normpath(os.path.join(cwd, w.split("::")[0])) for w in cands if not w.startswith("-") and w != expr and _PATH_RE.fullmatch(w.split("::")[0])]
        texts = [_read(repo_root, f) for f in files]
        terms = [t for t in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", expr) if t not in ("and", "or", "not")]
        if files and all(t is not None for t in texts) and not any(_is_target(f, item, mentioned) for f in files):
            blob = "\n".join(texts).lower()
            for t in terms:
                if t.lower() not in blob and t.lower() not in desc.lower():
                    out.append(_f("test-selector-missing", "error", "pytest -k %r selects no test: %r appears in none of the named test files and the item adds no test" % (expr, t)))
        elif not files:
            for t in terms:
                if t.lower() not in desc.lower() and not _repo_has_word(repo_root, t, word=False):
                    out.append(_f("test-selector-missing", "error", "pytest -k term %r matches nothing in the repo and the item adds no test" % t))
    if h == "python":
        code = _py_code_arg(sg["words"])
        if code:
            try:
                tree = _parse_py(code)
            except SyntaxError:
                return out
            for node in ast.walk(tree):
                mods = []
                if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                    mods.append((node.module, [a.name for a in node.names]))
                elif isinstance(node, ast.Import):
                    mods += [(a.name, []) for a in node.names]
                for mod, names in mods:
                    parts = mod.split(".")
                    top = parts[0]
                    local = os.path.isdir(os.path.join(repo_root, cwd, top)) or os.path.isfile(os.path.join(repo_root, cwd, top + ".py"))
                    if not local:
                        try:
                            subs = [d for d in sorted(os.listdir(os.path.join(repo_root, cwd))) if not d.startswith(".")]
                        except OSError:
                            subs = []
                        for d in subs:
                            if os.path.isfile(os.path.join(repo_root, cwd, d, top, "__init__.py")):
                                out.append(_f("import-wrong-cwd", "error", "verify imports %s but package %r lives in %s/ - run it from there (cd %s && ...)" % (mod, top, os.path.join(cwd, d), d)))
                                break
                        continue
                    base = os.path.join(cwd, *parts)
                    cand = [base + ".py", os.path.join(base, "__init__.py")]
                    found = next((c for c in cand if os.path.isfile(os.path.join(repo_root, c))), None)
                    if found is None:
                        if not any(_is_target(c, item, mentioned) for c in cand) and not os.path.isdir(os.path.join(repo_root, base)):
                            out.append(_f("import-missing-module", "error", "verify imports %s but %s does not exist at the base ref and the item does not create it" % (mod, cand[0])))
                        continue
                    if _is_target(found, item, mentioned):
                        continue
                    txt = _read(repo_root, found) or ""
                    for nm in names:
                        if nm == "*" or re.search(r"\b%s\b" % re.escape(nm), txt) or nm in desc:
                            continue
                        sub = os.path.join(os.path.dirname(found), nm + ".py")
                        if os.path.isfile(os.path.join(repo_root, sub)):
                            continue
                        out.append(_f("import-name-missing", "error", "verify imports %s from %s but that name is not defined there and the item does not add it" % (nm, mod)))
    return out


def lint_verify(verify, item, repo_root=None, card_files=(), kind_info=None):
    """Lint a VERIFY command against its item. Returns (findings, info)."""
    out = []
    info = {"strength": None, "assertions": [], "kind": None}
    if not isinstance(verify, str) or not verify.strip():
        return [_f("verify-missing", "error", "verify command is missing or empty")], info
    ki = kind_info or classify_item(item)
    info["kind"], info["direction"] = ki["kind"], ki["direction"]
    segs, problems, substs = parse_shell(verify)
    for p in problems:
        out.append(_f("shell-unparseable", "error", p))
    if not segs:
        return out or [_f("verify-missing", "error", "verify command has no statements")], info
    if any(head_of(sg["words"]) in ("if", "for", "while", "until", "case", "function", "select", "then", "fi", "done", "esac", "do", "{", "}") for sg in segs):
        out.append(_f("shell-compound", "error", "compound shell constructs (if/for/while/case) are not allowed; write a single && chain"))
    full_text = verify
    if re.search(r"[<>]\(", full_text):
        out.append(_f("unsafe-command", "error", "process substitution <(...) / >(...) runs a command outside the allowlist"))
    # ---- command policy
    pipefail = bool(re.search(r"set\s+(-[a-z]*e[a-z]*\s+)?-o\s+pipefail|set\s+-[a-z]*o\s+pipefail", full_text))
    errexit = bool(re.search(r"(^|[;&\s])set\s+-[a-z]*e", full_text))
    for s in segs:
        words, _ = _strip_prefix(s["words"])
        if not words:
            continue
        h = head_of(s["words"])
        if h in FORBIDDEN_HINT:
            out.append(_f("unsafe-command", "error", "command %r is not allowed in a verify (%s)" % (h, FORBIDDEN_HINT[h])))
        elif h not in ALLOWED and h not in ("sh_never",):
            out.append(_f("unknown-command", "error", "command %r is not on the verify allowlist" % h))
        args = words[1:]
        if h == "git" and args:
            sub = [x for x in args if not x.startswith("-")]
            if sub and sub[0] not in GIT_READONLY:
                out.append(_f("unsafe-command", "error", "git %s is not read-only" % sub[0]))
        if h == "npm":
            sub = [x for x in args if not x.startswith("-")]
            if not sub or sub[0] not in NPM_OK or (sub[0] == "run" and not (len(sub) > 1 and NPM_RUN_OK.match(sub[1]))):
                out.append(_f("unsafe-command", "error", "npm %s is not allowed (only test/lint scripts; installs touch the network)" % (sub[0] if sub else "")))
        if h == "npx":
            sub = [x for x in args if not x.startswith("-")]
            if not sub or os.path.basename(sub[0]) not in NPX_OK:
                out.append(_f("unsafe-command", "error", "npx %s is not allowed" % (sub[0] if sub else "")))
        if h == "find" and any(x in ("-delete", "-exec", "-execdir", "-ok", "-fprint") for x in args):
            out.append(_f("unsafe-command", "error", "find with -delete/-exec is not allowed"))
        if h == "sed" and any(x.startswith("-i") or x == "--in-place" for x in args):
            out.append(_f("unsafe-command", "error", "sed -i modifies files"))
        for w_ in extra_unsafe(h, args):
            out.append(_f("unsafe-command", "error", w_))
        if h == "python":
            code = _py_code_arg(s["words"])
            if code is not None and (UNSAFE_PY.search(code) or PY_WRITE_OPEN.search(code)):
                out.append(_f("unsafe-command", "error", "python -c code touches network/subprocess/filesystem writes"))
            if code is not None and re.search(r"\bor\s+True\b|\bassert\s+True\b|\bassert\s+1\s*(==\s*1\s*)?(;|$)|\bassert\s+not\s+False\b", code):
                out.append(_f("py-tautology", "error", "the python -c code contains an assertion that can never fail (or True / assert True / assert 1)"))
            if code is not None:
                try:
                    _parse_py(code)
                except SyntaxError as ex:
                    out.append(_f("py-syntax", "error", "the python -c code is not valid Python (%s) - it would fail before AND after the change" % (ex.msg,)))
            w2, _ = _strip_prefix(s["words"])
            if any(x == "-m" for x in w2) and _py_module_arg(s["words"]) in ("pip", "http.server", "venv", "ensurepip"):
                out.append(_f("unsafe-command", "error", "python -m %s is not allowed" % _py_module_arg(s["words"])))
        if h == "node" and "-e" in args and UNSAFE_PY.search(" ".join(args)):
            out.append(_f("unsafe-command", "error", "node -e code touches network/subprocess"))
        for op, tgt in s["redirs"]:
            if op.startswith(">") and tgt not in ("/dev/null", "/dev/stderr", "/dev/stdout") and not tgt.startswith("&"):
                out.append(_f("unsafe-redirect", "error", "redirect %s %s writes a file" % (op, tgt)))
            if op in ("&>", "&>>") and tgt not in ("/dev/null",):
                out.append(_f("unsafe-redirect", "error", "redirect %s %s writes a file" % (op, tgt)))
    inner_all = []
    for inner_cmd in substs:
        isegs, iprob, isub = parse_shell(inner_cmd)
        for p in iprob:
            out.append(_f("shell-unparseable", "error", "in $(...): " + p))
        inner_all.append(isegs)
        for sg in isegs:
            ih = head_of(sg["words"])
            if ih and ih in FORBIDDEN_HINT:
                out.append(_f("unsafe-command", "error", "command substitution runs %r (%s)" % (ih, FORBIDDEN_HINT[ih])))
            elif ih and ih not in ALLOWED:
                out.append(_f("unknown-command", "error", "command substitution runs %r which is not on the allowlist" % ih))
            if ih in ALLOWED:
                _iw, _ = _strip_prefix(sg["words"])
                for w_ in extra_unsafe(ih, _iw[1:]):
                    out.append(_f("unsafe-command", "error", "in $(...): " + w_))
            for op, tgt in sg["redirs"]:
                if op.startswith(">") and tgt not in ("/dev/null", "/dev/stderr", "/dev/stdout") and not tgt.startswith("&"):
                    out.append(_f("unsafe-redirect", "error", "redirect inside $(...) writes a file"))
    # ---- status-swallowing structure (the incident class: '|| echo', '; true', trailing pipes)
    for s in segs:
        words, _ = _strip_prefix(s["words"])
        h = head_of(s["words"])
        op_after = s["op"]
        if h == "exit" and words[1:2] in (["0"], []):
            out.append(_f("swallow-exit0", "error", "'exit 0' forces success"))
        if op_after == "&":
            out.append(_f("swallow-background", "error", "'&' backgrounds a command so its failure is ignored"))
    # statements as chains separated by ';' (a later statement hides earlier failures)
    stmts, cur = [], []
    for s in segs:
        cur.append(s)
        if s["op"] in (";", None, ";;"):
            stmts.append(cur)
            cur = []
    if cur:
        stmts.append(cur)
    classified = []
    for stmt in stmts:
        cl = [(sg, classify_segment(sg)) for sg in stmt]
        classified.append(cl)
    for si, cl in enumerate(classified):
        is_last = si == len(classified) - 1
        # walk operators within a statement
        for ci, (sg, (kind, strength, detail)) in enumerate(cl):
            nxt = cl[ci + 1][0] if ci + 1 < len(cl) else None
            # '||' handler that succeeds
            if sg["op"] in ("||",) and nxt is not None:
                nh = head_of(nxt["words"])
                nwords, _ = _strip_prefix(nxt["words"])
                exit_arg = nwords[1:2]
                handler_fails = nh == "false" or (nh == "exit" and exit_arg not in (["0"],))
                handler_succeeds = nh in ("echo", "printf", "true", ":", "cd", "set", "export") or (nh == "exit" and exit_arg == ["0"])
                if handler_succeeds:
                    out.append(_f("swallow-or-handler", "error", "'|| %s' swallows the failure of the previous command" % nh))
                elif not handler_fails:
                    out.append(_f("alternation", "flag", "'a || b' passes if EITHER branch passes; use && so every check must hold"))
        # earlier statements (before the last) are ignored unless errexit
        if not is_last:
            has_assert = any(k == "assert" for _sg, (k, _s, _d) in cl)
            if has_assert and not errexit:
                out.append(_f("swallow-semicolon", "error", "a ';'-separated assertion is ignored when a later statement runs (use && or 'set -e')"))
    # last statement: its status is the verdict. Pipeline handling.
    last_cl = classified[-1]
    # split last statement into && / || chain items, and pipelines inside
    # build pipeline groups: consecutive segments joined by '|'
    pipelines, cur = [], []
    for sg, c in last_cl:
        cur.append((sg, c))
        if sg["op"] not in ("|", "|&"):
            pipelines.append(cur)
            cur = []
    if cur:
        pipelines.append(cur)
    assertions = []
    for pl in pipelines:
        final_sg, (fk, fs, fd) = pl[-1]
        if len(pl) > 1:
            if fk != "assert" and not pipefail:
                out.append(_f("swallow-pipe", "error", "trailing pipe into %r swallows the exit status of %r (add 'set -o pipefail' or end with an asserting command)" % (fd, head_of(pl[0][0]["words"]))))
            for sg, c in pl:
                if c[0] == "assert" and (fk == "assert" or pipefail):
                    # `! a | b` negates the whole pipeline, so the negation applies to the asserting segment(s) too
                    assertions.append((dict(sg, neg=True) if pl[0][0]["neg"] else sg, c))
        else:
            if fk == "assert":
                assertions.append((final_sg, (fk, fs, fd)))
    # all earlier-statement assertions under errexit also count
    for cl in classified[:-1]:
        for sg, c in cl:
            if c[0] == "assert" and errexit:
                assertions.append((sg, c))
    # also assertions in the chain portion before '&&'/'||' within pipelines already collected via pipelines loop
    # trailing nonassert after && (e.g. '&& echo ok') is fine; trailing nonassert after ';' is not
    if not assertions and not any(f["rule"] in ("swallow-pipe", "no-assertion", "swallow-or-handler", "swallow-semicolon") for f in out):
        out.append(_f("no-assertion", "error", "the command contains no assertion that can fail (grep/test/pytest/python assert ...)"))
    info["assertions"] = ["%s:%s" % (c[2], c[1]) for _sg, c in assertions]
    if assertions:
        sts = [c[1] for _sg, c in assertions]
        info["strength"] = "strong" if "strong" in sts else ("weak" if "weak" in sts else "exists")
    # ---- direction
    heads = [(sg, c) for sg, c in assertions]
    neg_present = False
    pos_present = False
    for sg, c in heads:
        h = head_of(sg["words"])
        words, _ = _strip_prefix(sg["words"])
        args = words[1:]
        negated = bool(sg["neg"])
        if h in ("test", "[", "[[") and "!" in args:
            negated = not negated if sg["neg"] else True
        if h in ("grep", "egrep", "fgrep") and any(re.match(r"^-[a-zA-Z]*L[a-zA-Z]*$", x) for x in args):
            negated = True
        if h == "python" and _py_code_arg(sg["words"]) is not None:
            # inside `python -c`, classify each assert statement as negative (not / not in / != / is None / == 0|False|None|[]) or positive
            for stmt in re.split(r";|\n", _py_code_arg(sg["words"]) or ""):
                if re.match(r"\s*assert\b", stmt):
                    if re.match(r"\s*assert\s+not\b", stmt) or re.search(r"\bnot in\b|!=|\bis None\b|==\s*(0|False|None|\[\]|\"\"|'')\s*$", stmt):
                        neg_present = True
                    else:
                        pos_present = True
            continue
        if negated:
            neg_present = True
        else:
            pos_present = True
    # a pipeline like `grep -c X f | grep -q '^0$'` is a negative assertion expressed positively
    if re.search(r"grep\s+-[a-zA-Z]*c[a-zA-Z]*[^|;&]*\|\s*(grep|test)[^|;&]*\b0\b", verify) or re.search(r"\"\$\(grep\s+-[a-zA-Z]*c[^)]*\)\"\s*(=|==|-eq)\s*\"?0\"?", verify):
        neg_present = True
    direction = ki["direction"]
    if assertions:
        if direction == "negative" and not neg_present and not (info["strength"] == "strong" and any(c[2] in ("tests", "pytest") for _sg, c in assertions)):
            out.append(_f("direction-mismatch", "error", "the item REMOVES something but the check has no negative assertion (test ! -e / ! grep -q / grep -L); a positive check passes either way"))
        if direction in ("positive", "replace") and ki["kind"] != "delete" and neg_present and not pos_present:
            adds = bool(re.match(r"^(add|create|implement|register|introduce|insert|write|define|expose|wire)\b", item.get("desc", ""), re.I))
            out.append(_f("direction-mismatch", "error" if adds else "flag",
                          "the item ADDS something but every assertion is negative - it passes before the change" if adds
                          else "the item CHANGES something and every assertion is negative (removal only); confirm a positive check for the new behaviour exists"))
        if direction == "replace" and not (neg_present and pos_present) and info["strength"] != "strong":
            out.append(_f("direction-partial", "flag", "a replace/rename needs both a positive check (new value present) and a negative one (old value gone)"))
    # ---- weakness vs item kind
    if assertions and info["strength"] in ("weak", "exists"):
        k = ki["kind"]
        kinds = ",".join(sorted(set(c[2] for _sg, c in assertions)))
        absence_only = neg_present and not pos_present  # a removal verified by absence is the right check, not a weak one
        import_ok = k == "structural" and all(c[2] in ("py-c-import-or-exists-only",) for _sg, c in assertions)  # export/re-export items: the import IS the check
        if info["strength"] == "exists" and not neg_present and not import_ok:
            out.append(_f("existence-only", "error", "the only assertions are existence/importability/compiles (%s): they cannot tell 'done' from 'not done' in any meaningful way; assert a value, behaviour or content" % kinds))
        elif k == "behaviour" and neg_present and pos_present and not absence_only:
            out.append(_f("weak-existence", "flag", "source-text checks only (%s): new value present AND old value gone is adequate for a mechanical edit, but nothing executes the code" % kinds))
        elif k == "behaviour" and not absence_only and not (ki["direction"] == "negative" and neg_present):
            out.append(_f("weak-existence", "error", "behaviour item verified by source-text/grep-only checks (%s); run a test or an asserting python -c that CALLS the code" % kinds))
        elif k == "test":
            out.append(_f("weak-existence", "error", "a test-writing item must be verified by RUNNING the test (pytest/vitest), not by grepping for it"))
        elif k == "structural" and not (neg_present or pos_present):
            out.append(_f("weak-existence", "flag", "structural item with only weak assertions"))
    # ---- paths
    if repo_root:
        mentioned = set(_PATH_RE.findall(item.get("desc", ""))) | {item.get("path", "")}
        mention_base = {os.path.basename(m) for m in mentioned if m}
        paths, cds = extract_paths(segs)
        for isegs in inner_all:
            p2, c2 = extract_paths(isegs)
            paths += p2
            cds += c2
        for d in cds:
            if not os.path.isdir(os.path.join(repo_root, d)):
                out.append(_f("path-missing", "error", "cd target %r does not exist at the base ref" % d))
        seen = set()
        for p, skip in paths:
            if p in seen:
                continue
            seen.add(p)
            if os.path.isabs(p):
                out.append(_f("path-absolute", "error", "absolute path %r in verify" % p))
                continue
            if p.startswith(".."):
                out.append(_f("path-escape", "error", "path %r escapes the repo" % p))
                continue
            if skip or _exists(repo_root, p):
                continue
            created = p in mentioned or os.path.basename(p) in mention_base or any(p.endswith(m) or m.endswith(p) for m in mentioned if m)
            if created:
                continue
            out.append(_f("path-missing", "error", "verify references %r which does not exist at the base ref and is not created by the item" % p))
        out.extend(_unknown_literals(segs, inner_all, repo_root, item))
        for cwd, sg in _cwd_segments(segs):
            out.extend(_resolve_python_refs(sg, cwd, repo_root, item, mentioned))
        for isegs in inner_all:
            for cwd, sg in _cwd_segments(isegs):
                out.extend(_resolve_python_refs(sg, cwd, repo_root, item, mentioned))
        # relevance: the verify must touch the item (target file, its stem, a backticked identifier, or a path the item mentions)
        ipath = item.get("path", "")
        stem = os.path.splitext(os.path.basename(ipath))[0]
        comps = os.path.splitext(ipath)[0].split("/")
        dotted2 = ".".join(comps[-2:]) if len(comps) >= 2 else stem
        idents = set(re.findall(r"`([A-Za-z_][\w.]*)`", item.get("desc", "")))
        rel_blob = verify
        is_testfile = ki["kind"] == "test"
        relevant = (ipath and ipath in rel_blob) or (dotted2 and dotted2 in rel_blob) or (is_testfile and stem in rel_blob) \
            or any(len(i) > 3 and i.split(".")[-1] in rel_blob for i in idents) \
            or any(m in rel_blob for m in mentioned if m and "/" in m) \
            or bool(re.search(r"test_[\w]*%s" % re.escape(stem.replace("test_", "")), rel_blob) and stem.replace("test_", "") and not is_testfile)
        if not relevant:
            out.append(_f("verify-unrelated", "flag", "the verify command does not mention the item's file, module or any identifier from the item"))
    return out, info


def lint_card(card, item, repo_root=None):
    """Full lint of a card. item = {path, desc, verify?, cat?, tier?}. Returns {"errors":[...], "flags":[...], "info":{...}}."""
    fs = lint_schema(card)
    info = {}
    ki = classify_item(item)
    info.update(ki)
    if not any(f["rule"] in ("schema",) for f in fs) or isinstance(card, dict):
        if isinstance(card, dict):
            fs += lint_bullets(card, item) if isinstance(card.get("bullets"), list) else []
            if isinstance(card.get("verify_cmd"), str) and card["verify_cmd"].strip():
                vf, vinfo = lint_verify(card["verify_cmd"], item, repo_root, card.get("files") or (), ki)
                fs += vf
                info.update({"verify_strength": vinfo["strength"], "assertions": vinfo["assertions"]})
            if repo_root and isinstance(card.get("files"), list):
                mentioned = set(_PATH_RE.findall(item.get("desc", ""))) | {item.get("path", "")}
                for p in card["files"]:
                    if isinstance(p, str) and not os.path.isabs(p) and ".." not in p.split("/") and not _exists(repo_root, p) \
                            and p not in mentioned and os.path.basename(p) not in {os.path.basename(m) for m in mentioned}:
                        fs.append(_f("files-missing", "error", "files lists %r which does not exist at the base ref and is not created by the item" % p))
                if item.get("path") and item["path"] not in card["files"] and not any(os.path.basename(item["path"]) == os.path.basename(x) for x in card["files"] if isinstance(x, str)):
                    fs.append(_f("files-omits-target", "flag", "files does not include the item's own target %s" % item["path"]))
            floor = risk_floor(item, card.get("files") if isinstance(card.get("files"), list) else ())
            mc = card.get("risk_class")
            info["risk_understated"] = bool(mc in RISK_ORDER and RISK_ORDER[mc] < RISK_ORDER[floor])  # informational: the final class is max(model, floor)
            info["risk_floor"] = floor
            info["risk_class_final"] = max([x for x in (mc, floor) if x in RISK_ORDER], key=lambda r: RISK_ORDER[r])
            info["needs_human_review_final"] = bool(card.get("needs_human_review")) or info["risk_class_final"] == "A" or ki["kind"] == "nochange"
    if ki["kind"] == "nochange":
        fs.append(_f("item-nochange", "flag", "the item is an audit/no-change item - there is nothing to verify"))
    return {"errors": [f for f in fs if f["severity"] == "error"], "flags": [f for f in fs if f["severity"] == "flag"], "info": info}


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--card")
    ap.add_argument("--verify")
    ap.add_argument("--item", default="")
    ap.add_argument("--item-path", default="")
    ap.add_argument("--repo-root")
    a = ap.parse_args(argv)
    item = {"path": a.item_path, "desc": a.item}
    if a.item and not a.item_path:
        pi = parse_item_line("- [ ] " + a.item)
        if pi:
            item = pi
    if a.card:
        with open(a.card) as f:
            card = json.load(f)
        res = lint_card(card, item, a.repo_root)
    else:
        f, info = lint_verify(a.verify or "", item, a.repo_root)
        res = {"errors": [x for x in f if x["severity"] == "error"], "flags": [x for x in f if x["severity"] == "flag"], "info": info}
    print(json.dumps(res, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
