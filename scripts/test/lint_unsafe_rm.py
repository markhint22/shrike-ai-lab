#!/usr/bin/env python3
"""Unsafe-deletion lint v3 (2026-10-17; v2 2026-10-16, HOME-deletion incident). usage: lint_unsafe_rm.py <root|file> [...]   exit 1 + one line per finding.

Incident: `tmp="$(mktemp -d)"` printed nothing, tmp was empty, HOME became /home and `rm -rf "$HOME"` deleted a real home. v1 was a per-line regex and was bypassable. v2 TOKENISES the shell
(quotes, escapes, continuations, $(..), `..`, ${..}, heredocs, here-strings, ;|&& lists, (( )) arithmetic) and judges every destructive call by whether its target is PROVABLY anchored.
v3 (round-2 review) makes the proofs flow-sensitive and closes the indirection / non-rm / non-shell holes.

  A target word is "anchored" (OK) when its leading component is
    - a static literal that is not root-ish (/, /*, ., .., *, an absolute path of < 2 components, /Users/<x>, /home/<x> and their ssh/Library/... children), or a literal prefix with >= 2 path
      components before any variable
    - "${V:?...}" (aborts when empty), or a variable V that is non-empty by construction:
        every assignment of V in the file is  V="$(safe_mktemp_dir)" || exit  (|| return/continue/.., or `if ! V=...`)  or is built on an anchored word
        (V="$T/x", V=/abs/lit/path, V="${X:?}/y"),  or V was tested by an enclosing/earlier guard: [ -n "$V" ] && .., [ -z "$V" ] || .., if [ -n "$V" ]; then .., [ -n "$V" ] || exit, : "${V:?}"
  A guard is only valid until V changes: ANY later assignment with an unanchored value (V=$2, V="", V=$(f), V=${1:-}, V=$V$Y), unset V, read V, `local V`, declare -n, for V in, printf -v V, let,
  (( V=.. )), ${V:=..} ends it; a loop head forgets every guard on a variable the loop body reassigns. A variable proof by construction is dropped when V is also assigned, unset or read anywhere
  else in the file. "$V$W" / "$V$(..)" are never anchored (the proof covers $V alone).
  A target is NEVER anchored when it has a '..' component (e.g. "$T"/.., /tmp/a/"$X"/../..), a `.*` glob component (matches '..' in bash < 5.2) or a brace group around an expansion ({"$X"/,}).
  Rules (finding id):
  R1  rm -r / xargs rm / "$RM" -rf whose target is not anchored (variable- or $(..)-led, "$A$B", "/$x", "${x:-}/y", unproven alias, ...), an unresolvable command variable that looks like a delete,
      rm of a glob whose FIRST component after an unanchored expansion is the glob ("$X"/*). Command aliasing is resolved: RM="rm -rf"; $RM x, alias zap="rm -rf", busybox/env -S/sudo/timeout/command
      wrappers, "${x}m" with x=r, "$(command -v rm)", xargs [-I..] sh -c "rm ..".  Fix: safe_rm_rf, or "${V:?}/..".
  R2  rm -r of HOME itself / a tilde path / a variable that aliases HOME (h="$HOME"; rm -rf "$h").  Fix: safe_rm_rf (refuses HOME, /home, /, shallow paths, non-sandbox paths).
  R3  rm -r of an UNQUOTED variable expansion (word splitting / vanishing) unless "${V:?}".
  R4  find ... -delete / -exec rm|shred|truncate whose search root is not anchored (an empty root walks the current directory).
  R5  python shutil.rmtree / os.removedirs / distutils remove_tree (also `from shutil import rmtree as r`) of a HOME-derived, root, argv/environ/stdin-derived, or unanchored f-string/concat/%/format
      path (python -c with shell-interpolated "$X" included; subprocess/os.system rm strings), and perl/ruby/node/php -e code that deletes files.
  R6  a persistent HOME assignment (HOME=.., export HOME=..) that is not safe_set_sandbox_home (the incident turned HOME into /home).
  R7  mktemp -d whose result is used without an abort guard (production scripts): needs `|| exit` AND a non-empty/dir check, `|| V=""`, or V="$(safe_mktemp_dir)" || exit.
  R8  tests / test libs: raw `mktemp -d` assigned to a variable without the abort + non-empty/dir check - use safe_mktemp_dir (rc 0 with empty output is otherwise undetected).
  R9  other destructive tools: shred/truncate/unlink/rsync --delete|--remove-source-files operands that are not anchored; mv/cp/ln onto /dev/null.
The tokenizer also lints the text of bash -c / sh -c / eval / trap / ssh arguments, heredoc bodies, here-strings, `echo "rm .." | sh`, and command substitutions.
Exempt: scripts/test/lib_safe_tmp.sh (the guarded helper itself, reviewed by hand), markdown/json/patch/log text, fixtures dirs.
Known limits (document, do not rely on): eval "$var" / sh -c "$var" of an unknown variable, functions that reassign a global behind the guard, rm reached through a script file written at run time.
"""
import ast, os, re, sys, warnings

warnings.simplefilter("ignore")   # parsing arbitrary text as python must not spray SyntaxWarnings

SKIP_DIRS = {".git", "__pycache__", "fixtures", "fixtures_qagate", "fixtures_qa_migrations", "assets", "node_modules", ".venv"}
EXEMPT_SUFFIX = ("scripts/test/lib_safe_tmp.sh",)
ROOT_DATA_DIRS = {"repos", "state", "logs"}   # runtime data at the queue root (not source); top level only
TEXT_SKIP_EXT = (".md", ".json", ".patch", ".txt", ".log", ".yaml", ".yml", ".plist", ".service", ".gd", ".kt", ".swift", ".diff", ".csv", ".toml", ".cfg", ".ini", ".html", ".js", ".ts")
KEYWORDS = {"if", "then", "elif", "else", "do", "while", "until", "!", "{", "}", "fi", "done", "esac", "time"}
ABORT = {"exit", "return", "continue", "break", "die", "fail", "abort", "fatal", "bail"}
WRAPPERS = {"command", "env", "sudo", "doas", "exec", "nohup", "nice", "timeout", "gtimeout", "stdbuf", "builtin", "ionice", "caffeinate", "setsid", "busybox", "toybox", "chronic", "unbuffer"}
WRAP_OPT_ARG = {"sudo": {"-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"}, "timeout": {"-s", "-k"}, "gtimeout": {"-s", "-k"},
                "nice": {"-n"}, "ionice": {"-c", "-n", "-p"}, "env": {"-u", "-C", "-S"}}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
PYNAMES = {"python", "python2", "python3", "python3.8", "python3.9", "python3.10", "python3.11", "python3.12", "python3.13", "python3.14"}
FOREIGN = {"perl", "ruby", "node", "nodejs", "deno", "bun", "php", "lua", "osascript"}
FOREIGN_DEL = re.compile(r"rmtree|remove_tree|rmSync|rmdirSync|rimraf|rm_rf|rm_r\b|rm_f\b|remove_entry|FileUtils|unlink|File::Path|fs\.rm|\.rm\(|\brm\b|rmdir|removeSync|emptyDir|shutil|\bdelete\b", re.I)
DANGEROUS = {"/", "/home", "/tmp", "/private", "/private/tmp", "/var", "/private/var", "/Users", "/root", "/etc", "/usr", "/bin", "/sbin", "/opt", "/mnt", "/media", "/srv",
             "/Volumes", "/System", "/Library", "/var/tmp", "/var/folders", "/private/var/folders", "/lib", "/boot", "/dev", "/proc", "/sys", "/run"}
DECLS = {"local", "export", "declare", "typeset", "readonly"}
HOME_SUBDIRS = {".ssh", ".gnupg", ".aws", ".kube", ".config", ".local", "Library", "Documents", "Desktop", "Downloads", "LocalProjects", "Projects", "src", "work"}
SAFE_MK = (["safe_mktemp_dir"], ["safe_mktemp_dir_in"])
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(\+?)=")
unparse = getattr(ast, "unparse", lambda n: "")


# ---------------------------------------------------------------- lexer
class Word:
    __slots__ = ("parts", "line")

    def __init__(self, parts, line):
        self.parts = parts
        self.line = line


# part = (kind, a, b, quoted):  lit/q: a=text   var: a=name b=modifier ('' | ':?msg' | ':-x' ...)   cmd: a=source text
def static_text(w):
    if all(p[0] in ("lit", "q") for p in w.parts):
        return "".join(p[1] for p in w.parts)
    return None


def scan_paren(t, i):
    """t[i] is just after '$(' ; returns the index of the matching ')' (or len(t))."""
    d, n = 1, len(t)
    while i < n:
        c = t[i]
        if c == "\\":
            i += 2; continue
        if c == "'":
            j = t.find("'", i + 1); i = (j if j >= 0 else n) + 1; continue
        if c == '"':
            i = scan_dq(t, i + 1); continue
        if c == "`":
            j = i + 1
            while j < n and t[j] != "`":
                j += 2 if t[j] == "\\" else 1
            i = j + 1; continue
        if c == "#" and (i == 0 or t[i - 1] in " \t\n;|&("):
            j = t.find("\n", i); i = j if j >= 0 else n; continue
        if c == "$" and i + 1 < n and t[i + 1] == "(":
            i = scan_paren(t, i + 2) + 1; continue
        if c == "(":
            d += 1
        elif c == ")":
            d -= 1
            if d == 0:
                return i
        i += 1
    return n


def scan_dq(t, i):
    """t[i] is just after an opening quote; returns the index just after the closing quote."""
    n = len(t)
    while i < n:
        c = t[i]
        if c == "\\":
            i += 2; continue
        if c == '"':
            return i + 1
        if c == "$" and i + 1 < n and t[i + 1] == "(":
            i = scan_paren(t, i + 2) + 1; continue
        if c == "$" and i + 1 < n and t[i + 1] == "{":
            i = scan_brace(t, i + 2) + 1; continue
        if c == "`":
            j = i + 1
            while j < n and t[j] != "`":
                j += 2 if t[j] == "\\" else 1
            i = j + 1; continue
        i += 1
    return n


def scan_brace(t, i):
    """t[i] is just after '${' ; returns the index of the matching '}'."""
    d, n = 1, len(t)
    while i < n:
        c = t[i]
        if c == "\\":
            i += 2; continue
        if c == "'":
            j = t.find("'", i + 1); i = (j if j >= 0 else n) + 1; continue
        if c == '"':
            i = scan_dq(t, i + 1); continue
        if c == "$" and i + 1 < n and t[i + 1] == "{":
            d += 1; i += 2; continue
        if c == "$" and i + 1 < n and t[i + 1] == "(":
            i = scan_paren(t, i + 2) + 1; continue
        if c == "}":
            d -= 1
            if d == 0:
                return i
        i += 1
    return n


def parse_brace(body):
    if body[:1] in ("#", "!") and len(body) > 1:
        return "?" + body[0], ""
    m = NAME_RE.match(body)
    if m:
        return m.group(0), body[m.end():]
    if body[:1].isdigit():
        k = 1
        while k < len(body) and body[k].isdigit():
            k += 1
        return body[:k], body[k:]
    if body[:1] and body[0] in "@*?$!#-":
        return body[0], body[1:]
    return "?", body


ARITH_RE = re.compile(r"(?:\+\+|--)\s*([A-Za-z_]\w*)|([A-Za-z_]\w*)\s*(?:\+\+|--|(?:<<|>>|[-+*/%&|^])?=(?!=))")


def arith_names(body):
    out = []
    for m in ARITH_RE.finditer(body):
        out.append(m.group(1) or m.group(2))
    return out


class Lexer:
    def __init__(self, text, base_line=1):
        self.t = text
        self.i = 0
        self.line = base_line
        self.toks = []          # ("w", Word) | ("rw", Word) | ("op", str, line) | ("hd", body, line)
        self.pending_hd = []
        self.next_redir = False
        self.herestr = False

    def emit_word(self, parts, line):
        self.toks.append(("hs" if self.herestr else "rw" if self.next_redir else "w", Word(parts, line)))
        self.next_redir = False
        self.herestr = False

    def read_heredocs(self):
        t = self.t
        for delim, strip in self.pending_hd:
            start_line = self.line
            lines = []
            while self.i < len(t):
                j = t.find("\n", self.i)
                ln = t[self.i:j] if j >= 0 else t[self.i:]
                self.i = (j + 1) if j >= 0 else len(t)
                self.line += 1
                if (ln.lstrip("\t") if strip else ln) == delim:
                    break
                lines.append(ln)
            self.toks.append(("hd", "\n".join(lines), start_line))
        self.pending_hd = []

    def run(self):
        t, n = self.t, len(self.t)
        parts, buf, wline = [], [], None

        def flush_lit():
            if buf:
                parts.append(("lit", "".join(buf), None, False))
                del buf[:]

        def end_word():
            nonlocal parts, wline
            flush_lit()
            if parts:
                self.emit_word(parts, wline)
            parts, wline = [], None

        while self.i < n:
            c = t[self.i]
            if c == "\\":
                if self.i + 1 < n and t[self.i + 1] == "\n":
                    self.i += 2; self.line += 1; continue
                wline = self.line if wline is None else wline
                flush_lit()
                if self.i + 1 < n:
                    parts.append(("q", t[self.i + 1], None, True))
                self.i += 2; continue
            if c in " \t\r":
                end_word(); self.i += 1; continue
            if c == "\n":
                end_word()
                self.toks.append(("op", "\n", self.line))
                self.i += 1; self.line += 1
                if self.pending_hd:
                    self.read_heredocs()
                continue
            if c == "#" and not parts and not buf:
                j = t.find("\n", self.i); self.i = j if j >= 0 else n; continue
            wline = self.line if wline is None else wline
            if c == "'":
                flush_lit()
                j = t.find("'", self.i + 1)
                j = j if j >= 0 else n
                s = t[self.i + 1:j]
                parts.append(("q", s, None, True)); self.line += s.count("\n"); self.i = j + 1; continue
            if c == '"':
                flush_lit(); self.read_dq(parts); continue
            if c == "`":
                flush_lit()
                j = self.i + 1
                while j < n and t[j] != "`":
                    j += 2 if t[j] == "\\" else 1
                s = t[self.i + 1:j].replace("\\`", "`").replace("\\\\", "\\")
                parts.append(("cmd", s, None, False)); self.line += s.count("\n"); self.i = j + 1; continue
            if c == "$":
                flush_lit(); self.read_dollar(parts, False); continue
            if c in ";|&()<>":
                if parts or buf:
                    end_word()
                wline = None
                self.read_op(); continue
            buf.append(c); self.i += 1
        end_word()
        return self.toks

    def read_dq(self, parts):
        t, n = self.t, len(self.t)
        i = self.i + 1
        buf = []
        start = len(parts)

        def fl():
            if buf:
                parts.append(("q", "".join(buf), None, True)); del buf[:]
        while i < n:
            c = t[i]
            if c == "\\":
                if i + 1 < n and t[i + 1] in '"\\$`\n':
                    if t[i + 1] == "\n":
                        self.line += 1
                    else:
                        buf.append(t[i + 1])
                    i += 2; continue
                buf.append(c); i += 1; continue
            if c == '"':
                i += 1; break
            if c == "$":
                fl(); self.i = i; self.read_dollar(parts, True); i = self.i; continue
            if c == "`":
                fl()
                j = i + 1
                while j < n and t[j] != "`":
                    j += 2 if t[j] == "\\" else 1
                parts.append(("cmd", t[i + 1:j], None, True)); i = j + 1; continue
            if c == "\n":
                self.line += 1
            buf.append(c); i += 1
        fl()
        if len(parts) == start:
            parts.append(("q", "", None, True))
        self.i = i

    def read_dollar(self, parts, quoted):
        t, n = self.t, len(self.t)
        i = self.i
        nx = t[i + 1] if i + 1 < n else ""
        if nx == "(":
            if t[i + 2:i + 3] == "(":
                j = t.find("))", i + 3)
                j = j if j >= 0 else n
                self.toks.append(("arith", arith_names(t[i + 3:j])))
                parts.append(("q", "0", None, quoted)); self.i = j + 2; return
            j = scan_paren(t, i + 2)
            s = t[i + 2:j]
            parts.append(("cmd", s, None, quoted)); self.line += s.count("\n"); self.i = j + 1; return
        if nx == "{":
            j = scan_brace(t, i + 2)
            name, mod = parse_brace(t[i + 2:j])
            parts.append(("var", name, mod, quoted)); self.i = j + 1; return
        if nx == "'" and not quoted:
            j = i + 2
            while j < n and t[j] != "'":
                j += 2 if t[j] == "\\" else 1
            parts.append(("q", t[i + 2:j], None, True)); self.i = j + 1; return
        if nx == '"' and not quoted:
            self.i = i + 1; self.read_dq(parts); return
        m = NAME_RE.match(t, i + 1)
        if m:
            parts.append(("var", m.group(0), "", quoted)); self.i = m.end(); return
        if nx and nx in "$?!#*@-0123456789":
            parts.append(("var", nx, "", quoted)); self.i = i + 2; return
        parts.append(("lit", "$", None, False)); self.i = i + 1

    def read_op(self):
        t, n = self.t, len(self.t)
        i = self.i
        c = t[i]
        two = t[i:i + 2]
        ln = self.line
        if c in "<>":
            # an fd number glued to the redirect (2>file) is not an argument
            if self.toks and self.toks[-1][0] == "w":
                w = self.toks[-1][1]
                if len(w.parts) == 1 and w.parts[0][0] == "lit" and w.parts[0][1].isdigit() and t[max(0, i - len(w.parts[0][1])):i] == w.parts[0][1]:
                    self.toks.pop()
            if t[i:i + 3] == "<<<":
                self.i = i + 3; self.next_redir = True; self.herestr = True; return
            if two == "<<":
                j = i + 2
                strip = False
                if j < n and t[j] == "-":
                    strip = True; j += 1
                while j < n and t[j] in " \t":
                    j += 1
                k, delim = j, []
                while k < n and t[k] not in " \t\n;|&()<>":
                    if t[k] in "'\"":
                        q = t[k]; e = t.find(q, k + 1); e = e if e >= 0 else n
                        delim.append(t[k + 1:e]); k = e + 1
                    elif t[k] == "\\" and k + 1 < n:
                        delim.append(t[k + 1]); k += 2
                    else:
                        delim.append(t[k]); k += 1
                self.pending_hd.append(("".join(delim), strip)); self.i = k; return
            if t[i + 1:i + 2] == "(":
                j = scan_paren(t, i + 2)
                self.toks.append(("w", Word([("cmd", t[i + 2:j], None, False)], ln))); self.i = j + 1; return
            j = i + 1
            while j < n and t[j] in "<>&|":
                if t[j] == "&" and j + 1 < n and t[j + 1] in "0123456789-":
                    self.i = j + 2; return          # >&2  2>&1  >&-  : no target word
                j += 1
            self.i = j; self.next_redir = True; return
        if two == "((" and (not self.toks or self.toks[-1][0] in ("op", "arith")):
            j = t.find("))", i + 2)
            if j >= 0:                               # (( expr )) as a command: assignments inside it change variables
                self.toks.append(("arith", arith_names(t[i + 2:j]))); self.line += t[i:j].count("\n"); self.i = j + 2; return
        if two in ("&&", "||", ";;"):
            self.toks.append(("op", two, ln)); self.i = i + 2; return
        if two == "&>":
            self.i = i + 2; self.next_redir = True; return
        self.toks.append(("op", c, ln)); self.i = i + 1


# ---------------------------------------------------------------- command model
class Cmd:
    def __init__(self):
        self.words, self.heredocs, self.arith, self.herestrs = [], [], [], []
        self.op_after = self.op_before = None
        self.line = 0


def build_cmds(toks):
    cmds, cur, prev_op = [], Cmd(), None
    for tk in toks:
        k = tk[0]
        if k == "w":
            if not cur.words:
                cur.line = tk[1].line
            cur.words.append(tk[1])
        elif k == "hd":
            cur.heredocs.append((tk[1], tk[2]))
        elif k == "arith":
            cur.arith.extend(tk[1])
        elif k == "hs":
            cur.herestrs.append(tk[1])
        elif k == "op":
            if cur.words or cur.heredocs or cur.arith:
                cur.op_after, cur.op_before = tk[1], prev_op
                cmds.append(cur)
            prev_op = tk[1]
            cur = Cmd()
    if cur.words or cur.heredocs or cur.arith:
        cur.op_before = prev_op
        cmds.append(cur)
    return cmds


def as_assign(w):
    if not w.parts or w.parts[0][0] != "lit":
        return None
    m = ASSIGN_RE.match(w.parts[0][1])
    if not m:
        return None
    rest = w.parts[0][1][m.end():]
    parts = ([("lit", rest, None, False)] if rest else []) + list(w.parts[1:])
    return m.group(1), m.group(2), Word(parts, w.line)


def split_cmd(cmd):
    words, i, kws = cmd.words, 0, []
    while i < len(words):
        s = static_text(words[i])
        if s in KEYWORDS:
            kws.append(s); i += 1; continue
        break
    assigns = []
    while i < len(words):
        a = as_assign(words[i])
        if not a:
            break
        assigns.append(a); i += 1
    return kws, assigns, words[i:]


def base_name(w):
    s = static_text(w)
    return os.path.basename(s) if s is not None else None


# ---------------------------------------------------------------- analysis
class FileCtx:
    def __init__(self, path, is_test):
        self.path = path
        self.is_test = is_test
        self.assigns = {}       # name -> [(rhs Word, abort_ok, plain)]
        self.unknown = set()
        self.proven = set()
        self.home_alias = {"HOME"}
        self.static_vars = {}
        self.aliases = {}
        self.lenient = False


def abort_follows(cmds, idx):
    if cmds[idx].op_after != "||" or idx + 1 >= len(cmds):
        return False
    nk, na, nr = split_cmd(cmds[idx + 1])
    if nr:
        b = base_name(nr[0])
        if b in ABORT or static_text(nr[0]) == "{":
            return True
    return bool(nk) and nk[0] == "{"


def empty_fallback_follows(cmds, idx, name):
    """V="$(mktemp -d ..)" || V=""  : a failed mktemp leaves V empty, which every later use must (and, per the rm rules, does) tolerate."""
    if cmds[idx].op_after != "||" or idx + 1 >= len(cmds):
        return False
    nk, na, nr = split_cmd(cmds[idx + 1])
    return not nr and len(na) == 1 and na[0][0] == name and not na[0][1] and not norm_parts(na[0][2])


def home_like(comps):
    """/Users/<x>, /home/<x> (a user's home) or one of its crown-jewel children: never a delete target, with or without a variable suffix."""
    if len(comps) >= 2 and comps[0] in ("Users", "home"):
        return len(comps) == 2 or (len(comps) == 3 and comps[2] in HOME_SUBDIRS)
    return False


def anchored_prefix_ok(pre):
    """static literal prefix that precedes a variable: survives the variable being empty."""
    if not pre or pre.startswith("~"):
        return False
    if pre[0] != "/":
        return bool(pre.strip("./")) and pre not in (".", "..") and ".." not in pre.split("/")
    comps = [c for c in pre.split("/") if c]
    if len(comps) < 2 or ".." in comps:
        return False
    if "/" + "/".join(comps) in DANGEROUS or home_like(comps):
        return False
    return True


def brace_expand(s, depth=0):
    """bash brace expansion of {a,b} / {1..3} lists (bounded) - used to see what a braced literal really names."""
    if depth > 6:
        return [s]
    m = re.search(r"\{([^{}]*)\}", s)
    if not m:
        return [s]
    pre, post, body = s[:m.start()], s[m.end():], m.group(1)
    if "," in body:
        alts = body.split(",")
    else:
        mm = re.fullmatch(r"(-?\d+)\.\.(-?\d+)", body)
        if mm and abs(int(mm.group(2)) - int(mm.group(1))) < 50:
            a, b = int(mm.group(1)), int(mm.group(2))
            alts = [str(x) for x in (range(a, b + 1) if a <= b else range(a, b - 1, -1))]
        else:
            return [pre + "{" + body + "}" + x for x in brace_expand(post, depth + 1)] if post else [s]
    out = []
    for a in alts:
        for r in brace_expand(pre + a + post, depth + 1):
            out.append(r)
        if len(out) > 200:
            break
    return out


def static_bad(s):
    if s == "":
        return False
    if re.fullmatch(r"[./*]+", s) or s.startswith("~"):
        return True
    comps_all = s.split("/")
    if ".." in comps_all:
        return True          # '..' after any prefix can climb out of it (and the prefix may be empty)
    if s.startswith("/"):
        comps = [c for c in comps_all if c and c != "*"]
        if len(comps) < 2 or "/" + "/".join(comps) in DANGEROUS or home_like(comps):
            return True
    return False


def masked_text(ps):
    """the word as one string: unquoted literal text as is, quoted text masked with \x02, expansions with \x00 - for structural checks (.. components, braces, globs)."""
    out = []
    for p in ps:
        if p[0] == "lit":
            out.append(p[1])
        elif p[0] == "q":
            out.append("\x02" * len(p[1]) if p[1] else "")
        else:
            out.append("\x00")
    return "".join(out)


def raw_text(ps):
    return "".join(p[1] if p[0] in ("lit", "q") else "\x00" for p in ps)


def path_hazard(ps):
    """structural hazards that defeat an otherwise-anchored target: '..' components, the bash<5.2 `.*` glob (matches ..), brace expansion of an expansion."""
    raw, msk = raw_text(ps), masked_text(ps)
    if ".." in raw.split("/"):
        return "a '..' path component can climb out of the anchored prefix"
    if ".*" in msk.split("/"):
        return "the `.*` glob matches '..' (bash < 5.2, e.g. the macOS /bin/bash 3.2)"
    if re.search(r"\{[^{}]*(,|\.\.)[^{}]*\}", msk) and "\x00" in raw:
        return "brace expansion around an expansion hides the real target"
    return None


def norm_parts(w):
    return [p for p in w.parts if not (p[0] in ("lit", "q") and p[1] == "")]


def word_status(w, ctx, guarded, assignment=False):
    """None when the word is anchored; else (rule, message)."""
    ps = norm_parts(w)
    if not ps:
        return None
    st = static_text(Word(ps, 0))
    if st is not None:
        if assignment:
            return None if not static_bad(st) else ("R1", "root-ish value " + repr(st))
        if re.search(r"\{[^{}]*(,|\.\.)[^{}]*\}", masked_text(ps)):
            for ex in brace_expand(st):
                if static_bad(ex):
                    return ("R1", "root-ish literal target after brace expansion: " + ex)
            return None
        return ("R1", "root-ish literal target: " + st) if static_bad(st) else None
    hz = path_hazard(ps)
    if hz:
        return ("R1", hz)
    k, pre = 0, ""
    while k < len(ps) and ps[k][0] in ("lit", "q"):
        pre += ps[k][1]; k += 1
    if k > 0:
        if pre.startswith("~"):
            return ("R2", "tilde path")
        if anchored_prefix_ok(pre):
            return None
        return ("R1", "target prefix %r is not anchored (an empty variable would leave just %r)" % (pre, pre))
    lead = ps[0]
    if lead[0] == "cmd":
        return ("R1", "target begins with a command substitution (its output is unprovable)")
    name, mod, quoted = lead[1], lead[2] or "", lead[3]
    quoted = quoted or assignment or ctx.lenient
    if name == "$":
        return None
    if name in ctx.home_alias:
        rs = static_text(Word(ps[1:], 0)) if ps[1:] else ""
        if rs in ("", "/", "/*", "*", "/."):
            return ("R2", "rm -r of HOME (or an alias of it): $" + name)
    if mod.startswith(":?") or mod.startswith("?"):
        return None if quoted else ("R3", "unquoted ${%s:?}" % name)
    if name in ctx.proven or name in guarded:
        if len(ps) > 1 and ps[1][0] in ("var", "cmd"):
            return ("R1", "$%s is concatenated with another expansion (%s): the proof covers $%s alone" % (name, "$" + ps[1][1] if ps[1][0] == "var" else "$(..)", name))
        return None if quoted else ("R3", "unquoted variable $%s" % name)
    if mod[:2] == ":-" or mod[:1] == "-":
        d = mod[2:] if mod[:2] == ":-" else mod[1:]
        if d and "$" not in d and len(ps) > 1 and ps[1][0] in ("lit", "q") and ps[1][1].startswith("/") and anchored_prefix_ok(d):
            return None
    if not quoted:
        return ("R3", "unquoted variable $%s" % name)
    return ("R1", 'target "$%s..." is not provably non-empty (use "${%s:?}", safe_rm_rf, or %s="$(safe_mktemp_dir)" || exit 1)' % (name, name, name))


def rhs_ok(a, ctx, proven_now):
    rhs, abort_ok, plain = a
    ps = norm_parts(rhs)
    if not ps:
        return False
    if len(ps) == 1 and ps[0][0] == "cmd":
        return ps[0][1].strip().split()[:1] in SAFE_MK and abort_ok and plain
    saved = ctx.proven
    ctx.proven = proven_now
    try:
        return word_status(rhs, ctx, set(), assignment=True) is None
    finally:
        ctx.proven = saved


def cmd_mutations(c, kws, assigns, rest):
    """every variable this command may (re)assign -> [(name, rhs Word | None, plus)]; rhs None = value unknown (read, unset, nameref, local x, arithmetic, ${x:=..}, for ...)."""
    out = []
    if not rest:
        out += [(n, rhs, bool(plus)) for (n, plus, rhs) in assigns]
    n0 = base_name(rest[0]) if rest else None
    if n0 in ("for", "select") and len(rest) > 1:
        v = static_text(rest[1])
        if v:
            out.append((v, None, False))
    elif n0 in DECLS:
        flags = [static_text(w) or "" for w in rest[1:] if (static_text(w) or "").startswith("-")]
        nameref = any(f.startswith("-") and not f.startswith("--") and "n" in f for f in flags)
        skip = any(f.startswith("-") and not f.startswith("--") and re.search(r"[fFp]", f) for f in flags)
        for w in rest[1:]:
            a = as_assign(w)
            if a:
                out.append((a[0], None if nameref else a[2], bool(a[1])))
            elif not skip:
                sv = static_text(w)
                if sv and NAME_RE.fullmatch(sv) and (n0 in ("local", "declare", "typeset") or nameref):
                    out.append((sv, None, "nameref" if nameref else "decl"))   # `local x` empties x (kills a guard; harmless to the by-construction proof) / `declare -n x` makes it a reference
    elif n0 == "printf":
        for k, w in enumerate(rest[1:-1]):
            if static_text(w) == "-v" and static_text(rest[k + 2]) and NAME_RE.match(static_text(rest[k + 2])):
                out.append((re.match(r"[A-Za-z_]\w*", static_text(rest[k + 2])).group(0), None, False))
    elif n0 in ("read", "mapfile", "readarray", "getopts", "unset", "let", "wait", "coproc"):
        for w in rest[1:]:
            sv = static_text(w)
            a = as_assign(w) if n0 == "let" else None
            if a:
                out.append((a[0], None, False))
            elif sv and NAME_RE.fullmatch(sv):
                out.append((sv, None, False))
    for nm in c.arith:
        out.append((nm, None, False))
    for w in c.words:
        for p in w.parts:
            if p[0] == "var" and ((p[2] or "")[:2] == ":=" or (p[2] or "")[:1] == "="):
                out.append((p[1], None, False))          # ${V:=x} assigns V
    return out


def collect_vars(cmds, ctx):
    for idx, c in enumerate(cmds):
        kws, assigns, rest = split_cmd(c)
        n0 = base_name(rest[0]) if rest else None
        if n0 == "alias":
            for w in rest[1:]:
                a = as_assign(w)
                if a and static_text(a[2]) is not None:
                    ctx.aliases[a[0]] = static_text(a[2])
        ok = bool(not rest and (abort_follows(cmds, idx) or "!" in kws))
        for (name, rhs, plus) in cmd_mutations(c, kws, assigns, rest):
            if plus == "decl":
                continue
            if rhs is None or plus:
                ctx.unknown.add(name)
            elif not rest:
                ctx.assigns.setdefault(name, []).append((rhs, ok, True))
            else:
                ctx.assigns.setdefault(name, []).append((rhs, False, False))
    changed = True
    while changed:                       # HOME aliases
        changed = False
        for name, lst in ctx.assigns.items():
            if name in ctx.home_alias:
                continue
            for (rhs, _, _) in lst:
                ps = norm_parts(rhs)
                if not ps:
                    continue
                if ps[0][0] == "var" and ps[0][1] in ctx.home_alias:
                    rs = static_text(Word(ps[1:], 0)) if ps[1:] else ""
                    al = rs in ("", "/")
                else:
                    al = ps[0][0] == "lit" and ps[0][1] == "~" and len(ps) == 1
                if al:
                    ctx.home_alias.add(name); changed = True; break
    changed = True
    while changed:                       # proven non-empty variables
        changed = False
        for name, lst in ctx.assigns.items():
            if name in ctx.proven or name in ctx.unknown or name in ctx.home_alias:
                continue
            # optimistic about self-reference (R="$R/x"): emptiness only ever comes from a base assignment
            if all(rhs_ok(a, ctx, ctx.proven | {name}) for a in lst):
                ctx.proven.add(name); changed = True
    for name, lst in ctx.assigns.items():
        vals = [static_text(r) for (r, _, _) in lst]
        if name not in ctx.unknown and vals and None not in vals and len(set(vals)) == 1:
            ctx.static_vars[name] = vals[0]


def is_rec_flag(s):
    if s is None:
        return False
    return s == "--recursive" or (re.fullmatch(r"-[A-Za-z]+", s) is not None and bool(re.search(r"[rR]", s)))


def lex_words(text, line=1):
    out = []
    for tk in Lexer(text, line).run():
        if tk[0] == "w":
            out.append(tk[1])
    return out


CMD_RM_RE = re.compile(r"(^|[\s/;&|(])rm(\s|$|\))")


def resolve_name(w, ctx):
    """-> (name, known). known False means the command word is a variable we cannot resolve."""
    s = static_text(w)
    if s is not None:
        return os.path.basename(s), True
    ps = norm_parts(w)
    if len(ps) == 1 and ps[0][0] == "cmd" and CMD_RM_RE.search(ps[0][1]):
        return "rm", True                       # "$(command -v rm)" / $(which rm): the command IS rm
    if ps and all(p[0] in ("lit", "q") or (p[0] == "var" and not (p[2] or "") and p[1] in ctx.static_vars) for p in ps):
        txt = "".join(p[1] if p[0] in ("lit", "q") else ctx.static_vars[p[1]] for p in ps)   # "${x}m" with x=r
        return os.path.basename(txt), True
    if len(ps) == 1 and ps[0][0] == "var":
        v = ctx.static_vars.get(ps[0][1])
        if v is not None:
            return os.path.basename(v), True
        return ps[0][1], False
    return None, False


def strip_wrappers(rest, ctx):
    i = 0
    while i < len(rest):
        name, ok = resolve_name(rest[i], ctx)
        if not (ok and name in WRAPPERS):
            break
        w = name
        i += 1
        optarg = WRAP_OPT_ARG.get(w, set())
        while i < len(rest):
            s = static_text(rest[i])
            if w == "env" and s is not None and (s in ("-S", "--split-string") or s.startswith("--split-string=") or (s.startswith("-S") and len(s) > 2)):
                if s in ("-S", "--split-string"):
                    txt = static_text(rest[i + 1]) if i + 1 < len(rest) else None
                    drop = 2
                else:
                    txt = s.split("=", 1)[1] if s.startswith("--") else s[2:]
                    drop = 1
                if txt is not None:           # env -S "rm -rf": the string IS the command line
                    rest = rest[:i] + lex_words(txt, rest[i].line) + rest[i + drop:]
                    continue
            if s is not None and s.startswith("-") and s != "-":
                i += 1
                if s in optarg and i < len(rest):
                    i += 1
                continue
            if as_assign(rest[i]):
                i += 1; continue
            if w in ("timeout", "gtimeout") and s is not None and re.fullmatch(r"[0-9.]+[smhd]?", s):
                i += 1; w = "x"; continue
            if w == "nice" and s is not None and s.isdigit():
                i += 1; continue
            break
    return rest[i:]


def expand_cmd(rest, ctx):
    """wrappers + aliases + variables holding a whole command line (RM="rm -rf"; $RM x) -> the real command words."""
    seen = set()
    for _ in range(8):
        rest = strip_wrappers(rest, ctx)
        if not rest:
            return rest
        st = static_text(rest[0])
        if st is not None and st in ctx.aliases and st not in seen:
            seen.add(st); rest = lex_words(ctx.aliases[st], rest[0].line) + rest[1:]; continue
        ps = norm_parts(rest[0])
        if len(ps) == 1 and ps[0][0] == "var" and not ps[0][3] and not (ps[0][2] or ""):
            v = ctx.static_vars.get(ps[0][1])
            if v is not None and len(v.split()) > 1:
                rest = lex_words(v, rest[0].line) + rest[1:]; continue
        break
    return rest


def word_to_text(w):
    out = []
    for p in w.parts:
        if p[0] in ("lit", "q"):
            out.append(p[1])
        elif p[0] == "var":
            out.append("${%s%s}" % (p[1], ":?" if (p[2] or "").startswith((":?", "?")) else ""))
        else:
            out.append("$(" + p[1] + ")")
    return "".join(out)


def var_only(w):
    vs = [p for p in w.parts if p[0] == "var"]
    if len(vs) == 1 and all(p[0] == "var" or (p[0] == "q" and p[1] == "") for p in w.parts):
        return vs[0][1]
    return None


def test_guards(words):
    """[ / [[ / test command -> (pos, neg): variables known non-empty when the test is true / false."""
    pos, neg = set(), set()
    if not words or static_text(words[0]) not in ("[", "[[", "test"):
        return pos, neg
    items = list(words[1:])
    if items and static_text(items[-1]) in ("]", "]]"):
        items = items[:-1]
    negate = bool(items) and static_text(items[0]) == "!"
    if negate:
        items = items[1:]
    if len(items) == 2:
        op, v = static_text(items[0]), var_only(items[1])
        if v and op in ("-n", "-d", "-e", "-f", "-s", "-L", "-h", "-r", "-x", "-w"):
            (neg if negate else pos).add(v)
        elif v and op == "-z":
            (pos if negate else neg).add(v)
    elif len(items) == 1 and var_only(items[0]):
        (neg if negate else pos).add(var_only(items[0]))
    elif len(items) == 3 and var_only(items[0]) and static_text(items[2]) == "":
        op = static_text(items[1])
        if op in ("!=", "-ne"):
            (neg if negate else pos).add(var_only(items[0]))
        elif op in ("=", "==", "-eq"):
            (pos if negate else neg).add(var_only(items[0]))
    return pos, neg


def has_colon_q(words):
    return {p[1] for w in words for p in w.parts if p[0] == "var" and (p[2] or "").startswith((":?", "?"))}


def mktemp_d(text):
    cs = build_cmds(Lexer(text).run())
    dummy = FileCtx("", False)
    for c in cs:
        k, a, r = split_cmd(c)
        r = strip_wrappers(r, dummy) if r else r
        if r and base_name(r[0]) in ("mktemp", "gmktemp"):
            for w in r[1:]:
                s = static_text(w)
                if s is not None and re.fullmatch(r"-[A-Za-z]*d[A-Za-z]*|--directory", s):
                    return True
    return False


def loop_ranges(cmds, ctx):
    """{index of a loop's first command: variables (re)assigned inside that loop and not proven by construction}"""
    out, stack = {}, []
    for idx, c in enumerate(cmds):
        kws, assigns, rest = split_cmd(c)
        if any(k in ("while", "until") for k in kws) or (rest and base_name(rest[0]) in ("for", "select")):
            stack.append(idx)
        if "done" in kws and stack:
            st = stack.pop()
            names = set()
            for j in range(st, idx + 1):
                kk, aa, rr = split_cmd(cmds[j])
                names |= {n for (n, _, _) in cmd_mutations(cmds[j], kk, aa, rr)}
            names -= ctx.proven
            if names:
                out.setdefault(st, set()).update(names)
    return out


def aborts_here(cmds, idx, kws, rest):
    """the command at idx is (or opens a { ...; } group containing) exit/return/continue/break/die/fail."""
    if rest and base_name(rest[0]) in ABORT:
        return True
    if kws and kws[0] == "{":
        for j in range(idx, min(idx + 12, len(cmds))):
            kk, aa, rr = split_cmd(cmds[j])
            if rr and base_name(rr[0]) in ABORT:
                return True
            if "}" in kk:
                break
    return False


def guarded_soon(cmds, idx, var):
    for j in range(idx, min(idx + 9, len(cmds))):
        rr = split_cmd(cmds[j])[2]
        if var in has_colon_q(rr):
            return True
        p, n = test_guards(rr)
        if (var in p or var in n) and cmds[j].op_after in ("||", "&&") and j + 1 < len(cmds):
            return True
    return False


def lint_shell(text, path, base_line=1, is_test=False, depth=0, lenient=False, shared=None, inherit_guard=None):
    """-> list of (line, rule, msg, snippet)"""
    cmds = build_cmds(Lexer(text, base_line).run())
    ctx = FileCtx(path, is_test)
    ctx.lenient = lenient
    if shared is not None:
        ctx.proven |= shared.proven
        ctx.home_alias |= shared.home_alias
        ctx.static_vars.update(shared.static_vars)
    collect_vars(cmds, ctx)
    res = []
    src = text.split("\n")

    def snip(line):
        li = line - base_line
        return src[li].strip()[:140] if 0 <= li < len(src) else ""

    def add(line, rule, msg):
        res.append((line, rule, msg, snip(line)))

    def addraw(t):
        res.append(t)

    global_guard, frames, chain_pos, raw_mk = set(inherit_guard or ()), [], set(), []
    loop_kill = loop_ranges(cmds, ctx)
    for idx, c in enumerate(cmds):
        kws, assigns, rest = split_cmd(c)
        for nm in loop_kill.get(idx, ()):                  # loop head: a variable reassigned anywhere in the body is not proven by a guard that ran before the loop
            global_guard.discard(nm); chain_pos.discard(nm)
            for f in frames:
                f["guards"].discard(nm)
        for kw in kws:
            if kw in ("if", "while", "until"):
                frames.append({"guards": set(), "cond": True})
            elif kw == "elif" and frames:
                frames[-1]["guards"] = set(); frames[-1]["cond"] = True
            elif kw == "else" and frames:
                frames[-1]["guards"] = set()
            elif kw in ("then", "do") and frames:
                frames[-1]["cond"] = False
        if rest and base_name(rest[0]) in ("for", "select"):
            frames.append({"guards": set(), "cond": False})
        local = set(global_guard) | chain_pos
        for f in frames:
            if not f["cond"]:
                local |= f["guards"]
        pos, neg = test_guards(rest)
        if frames and frames[-1]["cond"]:
            frames[-1]["guards"] |= pos
        inspect_cmd(c, kws, assigns, rest, cmds, idx, ctx, local, add, addraw, depth, lenient, raw_mk)
        for (nm, rhs, plus) in cmd_mutations(c, kws, assigns, rest):
            # any later assignment / unset / read / nameref ... of a guarded variable ends the guard's proof, unless the new value is itself anchored
            if rhs is not None and not plus and norm_parts(rhs) and word_status(rhs, ctx, local, assignment=True) is None:
                continue
            global_guard.discard(nm); chain_pos.discard(nm)
            for f in frames:
                f["guards"].discard(nm)
        if c.op_after == "&&":
            chain_pos = chain_pos | pos
        elif c.op_after == "||":
            chain_pos = chain_pos | neg
        else:
            chain_pos = set()
        if c.op_before in ("||", "&&") and aborts_here(cmds, idx, kws, rest):
            j = idx - 1
            while j >= 0 and cmds[j].op_after == c.op_before:
                p, n = test_guards(split_cmd(cmds[j])[2])
                global_guard |= (p if c.op_before == "||" else n)
                j -= 1
        global_guard |= has_colon_q(rest)
        for kw in kws:
            if kw in ("fi", "done") and frames:
                frames.pop()
    for (idx, var, line, abort_ok, fallback) in raw_mk:
        if is_test and not fallback and not (abort_ok and guarded_soon(cmds, idx, var)):
            add(line, "R8", "raw `mktemp -d` assigned to $%s in a test with no abort + non-empty check: use %s=\"$(safe_mktemp_dir)\" || exit 1 (source lib_safe_tmp.sh)" % (var, var))
        elif not is_test and not fallback and not (abort_ok and guarded_soon(cmds, idx, var)):
            add(line, "R7", "mktemp -d assigned to $%s without `|| exit` plus a non-empty/dir check (use safe_mktemp_dir, or: %s=\"$(mktemp -d)\" || exit 1; [ -n \"$%s\" ] && [ -d \"$%s\" ] || exit 1)" % (var, var, var, var))
    return res


def inspect_cmd(c, kws, assigns, rest, cmds, idx, ctx, guarded, add, addraw, depth, lenient, raw_mk):
    line = c.line
    if depth < 6:
        for w in c.words:
            for p in w.parts:
                if p[0] == "cmd":
                    for t in lint_shell(p[1], ctx.path, w.line, ctx.is_test, depth + 1, lenient, ctx, guarded):
                        addraw(t)
        for body, hl in c.heredocs:
            for t in lint_heredoc(body, ctx.path, hl, ctx.is_test, depth + 1, ctx):
                addraw(t)
    n0 = base_name(rest[0]) if rest else None
    decl = []
    if n0 in DECLS:
        decl += [(a[0], a[1], a[2], False) for a in (as_assign(w) for w in rest[1:]) if a]
    if not rest:
        decl += [(n, plus, rhs, True) for (n, plus, rhs) in assigns]
    for (n, plus, rhs, plain) in decl:
        if n == "HOME" and not ctx.path.endswith(EXEMPT_SUFFIX):
            rp = norm_parts(rhs)
            st = static_text(Word(rp, 0))
            restoring = len(rp) == 1 and rp[0][0] == "var" and rp[0][1] in ("HOME", "OVN_SAFE_REAL_HOME") and not (rp[0][2] or "")   # re-export / restore the real home
            if not restoring and not (st and st.startswith("/") and not static_bad(st)):
                add(line, "R6", 'persistent HOME assignment: use safe_set_sandbox_home "$tmp" || exit 1 (HOME="$tmp/home" with $tmp empty is /home)')
        for p in rhs.parts:
            if p[0] == "cmd" and mktemp_d(p[1]):
                raw_mk.append((idx, n, line, plain and (abort_follows(cmds, idx) or "!" in kws), plain and empty_fallback_follows(cmds, idx, n)))
    for w in c.words:
        if as_assign(w):
            continue
        for p in w.parts:
            if p[0] == "cmd" and mktemp_d(p[1]) and n0 != "rm":
                add(line, "R7", "mktemp -d used inline (its result cannot be checked): assign it to a variable and guard it")
    if not rest:
        return
    rest = expand_cmd(rest, ctx)
    if not rest:
        return
    name, known = resolve_name(rest[0], ctx)
    args = rest[1:]
    if name is None:
        return
    if not known:
        flags = [static_text(a) for a in args if static_text(a) is not None]
        if re.search(r"(^|_)(rm|remove|delete|del|wipe|nuke|zap|rmdir|unlink|shred)(_|$)", name, re.I):
            add(line, "R1", 'command "$%s" looks like a delete whose flags/targets cannot be seen: use safe_rm_rf or a literal rm with anchored targets' % name)
        elif any(f in ("-rf", "-fr", "-Rf", "-fR") for f in flags) and not any(f in ("-m", "pytest", "python", "python3") for f in flags):
            add(line, "R1", 'command "$%s" with -rf: use safe_rm_rf or a literal rm with anchored targets' % name)
        return
    if name == "rm":
        check_rm(args, line, ctx, guarded, add)
    elif name == "find":
        check_find(args, line, ctx, guarded, add)
    elif name in ("xargs", "parallel"):
        sub = expand_cmd(args_skip_opts(args), ctx)
        sn = resolve_name(sub[0], ctx) if sub else (None, False)
        if sn[0] in ("rm", "rmdir", "unlink", "shred", "truncate") and sn[1]:
            add(line, "R1", "xargs %s: its targets come from stdin and are unprovable (a find rooted at an empty variable feeds it /): use find -delete with an anchored root or safe_rm_rf per path" % sn[0])
        elif sn[1] and sn[0] in SHELLS and any(re.search(r"\b(rm|rmdir|unlink|shred|truncate)\b|-delete", word_to_text(x)) for x in sub[1:]):
            add(line, "R1", "xargs sh -c with a delete: its targets come from stdin and are unprovable")
        elif sub and not sn[1]:
            add(line, "R1", "xargs with an unresolvable command word: cannot prove it is not a delete")
    elif name in ("shred", "truncate", "unlink", "srm", "wipe"):
        check_destroy(name, args, line, ctx, guarded, add)
    elif name == "rsync":
        fl = [static_text(a) or "" for a in args]
        if any(f.startswith(("--delete", "--del", "--remove-source", "--remove-sent")) for f in fl):
            check_destroy("rsync --delete", [a for a in args if not (static_text(a) or "").startswith("-")], line, ctx, guarded, add)
    elif name in ("mv", "cp", "ln", "install"):
        for a in args:
            st = static_text(a)
            if st is not None and (st == "/dev/null" or st.startswith("/dev/null/")):
                add(line, "R9", "%s onto /dev/null destroys its source" % name)
    elif name in FOREIGN:
        for k, a in enumerate(args):
            st = static_text(a)
            if st is not None and re.fullmatch(r"-[A-Za-z]*[ecErpn][A-Za-z]*|--eval|--execute|--print", st) and k + 1 < len(args):
                code = word_to_text(args[k + 1])
                if FOREIGN_DEL.search(code):
                    add(line, "R5", "%s -e/-c code that deletes files (its targets cannot be proven): use safe_rm_rf from the shell" % name)
    elif name in SHELLS:
        for hw in c.herestrs:                       # bash <<< "rm -rf $X/"
            snippet(hw, line, ctx, add, depth, guarded)
        if c.op_before == "|" and idx > 0 and not any(static_text(a) == "-c" for a in args):
            ps_, pa_, pr_ = split_cmd(cmds[idx - 1])          # echo "rm -rf $X/" | sh   /   printf 'rm -rf %s/\n' "$X" | bash
            pr_ = expand_cmd(pr_, ctx) if pr_ else pr_
            pn = resolve_name(pr_[0], ctx)[0] if pr_ else None
            if pn in ("echo", "printf") and len(pr_) > 1:
                ws = [word_to_text(a) for a in pr_[1:] if not (static_text(a) or "").startswith("-")]
                if pn == "printf" and ws:
                    it = iter(ws[1:])
                    txt = re.sub(r"%[sdq]", lambda m_: next(it, ""), ws[0])
                else:
                    txt = " ".join(ws)
                snippet_text(txt, line, ctx, add, depth, True, guarded)
        for k, a in enumerate(args):
            s = static_text(a)
            if s is not None and s.startswith("-") and not s.startswith("--") and "c" in s[1:] and k + 1 < len(args):
                snippet(args[k + 1], line, ctx, add, depth, guarded)
                break
    elif name == "eval" and args:
        snippet_text(" ".join(word_to_text(a) for a in args), line, ctx, add, depth, True, guarded)
    elif name == "trap" and args and static_text(args[0]) != "-":
        snippet(args[0], line, ctx, add, depth, guarded)
    elif name == "ssh":
        i, hostseen, texts = 0, False, []
        while i < len(args):
            s = static_text(args[i])
            if not hostseen and s is not None and s.startswith("-"):
                i += 2 if s in ("-i", "-p", "-o", "-l", "-F", "-J", "-L", "-R", "-D", "-b", "-c", "-m", "-E") else 1
                continue
            if not hostseen:
                hostseen = True
            else:
                texts.append(word_to_text(args[i]))
            i += 1
        if texts:
            snippet_text(" ".join(texts), line, ctx, add, depth, True, guarded)
    elif name in PYNAMES:
        for k, a in enumerate(args):
            if static_text(a) == "-c" and k + 1 < len(args):
                tree = parse_py(word_to_text(args[k + 1]))
                interp = any(p[0] in ("var", "cmd") for p in args[k + 1].parts)
                if tree is not None:
                    for (l2, r2, m2) in lint_py_tree(tree, ctx.path, interp):
                        add(line, r2, m2 + "  [python -c]")
                elif re.search(r"rmtree|removedirs|remove_tree|\brm\b", word_to_text(args[k + 1])):
                    add(line, "R5", "python -c code that deletes files does not parse: cannot prove its target is safe")


def args_skip_opts(args):
    i = 0
    while i < len(args):
        s = static_text(args[i])
        if s is not None and s.startswith("-"):
            i += 2 if s in ("-I", "-L", "-n", "-P", "-s", "-d", "-E", "-a") else 1
            continue
        break
    return args[i:]


def snippet(w, line, ctx, add, depth, guarded=()):
    snippet_text(word_to_text(w), line, ctx, add, depth, any(p[0] == "var" for p in w.parts), guarded)


def snippet_text(text, line, ctx, add, depth, lenient, guarded=()):
    if depth >= 6 or not text.strip():
        return
    for (l2, r2, m2, s2) in lint_shell(text, ctx.path, line, ctx.is_test, depth + 1, lenient, ctx, guarded):
        add(line, r2, m2 + "  [inside a -c/trap/eval/ssh string]")


def check_rm(args, line, ctx, guarded, add):
    rec, targets, dd = False, [], False
    for a in args:
        s = static_text(a)
        if not dd and s == "--":
            dd = True; continue
        if not dd and s is not None and s.startswith("-") and len(s) > 1:
            rec = rec or is_rec_flag(s)
            continue
        ps = norm_parts(a)
        if not dd and ps and ps[0][0] == "var" and not ps[0][3] and re.search(r"(FLAGS|OPTS)", ps[0][1]):
            continue
        targets.append(a)
    if rec:
        for w in targets:
            st = word_status(w, ctx, guarded)
            if st:
                add(line, st[0], "rm -r target %s: %s" % (word_to_text(w)[:80], st[1]))
    else:
        for w in targets:           # rm -f "$X"/* with X empty is rm -f /* (every file in /): the glob needs an anchored prefix too
            if glob_after_expansion(w):
                st = word_status(w, ctx, guarded)
                if st:
                    add(line, "R1", "rm of a glob %s under an unanchored expansion: %s" % (word_to_text(w)[:80], st[1]))


DESTROY_OPT_ARG = {"truncate": {"-s", "--size", "-r", "--reference"}, "shred": {"-n", "--iterations", "-s", "--size", "--random-source"}}


def glob_after_expansion(w):
    """True for "$X"/* "$X"* "$X"/.* "$X"/*.log: an unquoted glob as the FIRST path component after the expansion (X empty -> a glob over /).
    "$X"/tree/reports/* or "$X"/llm/body.* name a literal component first and cannot reach the root."""
    ps = norm_parts(w)
    for k, p in enumerate(ps):
        if p[0] in ("var", "cmd"):
            tail = masked_text(ps[k + 1:])
            if "\x00" in tail:
                tail = tail[:tail.index("\x00")]
            first = tail.lstrip("/").split("/")[0] if tail.startswith("/") or tail else ""
            if not tail:
                return False
            first = tail[1:].split("/")[0] if tail.startswith("/") else tail.split("/")[0]
            return bool(re.search(r"[*?\[]", first)) and not re.search(r"[A-Za-z0-9_\x02]", first.replace(".*", "*"))
    return False


def check_destroy(name, args, line, ctx, guarded, add):
    """shred / truncate / unlink / rsync --delete: every non-option operand must be anchored like an rm -r target."""
    skip, dd = False, False
    opt = DESTROY_OPT_ARG.get(name, set())
    for a in args:
        st = static_text(a)
        if skip:
            skip = False; continue
        if not dd and st == "--":
            dd = True; continue
        if not dd and st is not None and st.startswith("-") and len(st) > 1:
            skip = st in opt
            continue
        stt = word_status(a, ctx, guarded)
        if stt:
            add(line, "R9", "%s target %s: %s" % (name, word_to_text(a)[:80], stt[1]))


FIND_STOP = re.compile(r"^(-.*|\(|!|\))$")


def check_find(args, line, ctx, guarded, add):
    roots, i = [], 0
    while i < len(args) and static_text(args[i]) in ("-H", "-L", "-P", "-O0", "-O1", "-O2", "-O3"):
        i += 1
    while i < len(args):
        s = static_text(args[i])
        if s is not None and FIND_STOP.match(s):
            break
        roots.append(args[i]); i += 1
    rest, danger = args[i:], False
    for k, a in enumerate(rest):
        s = static_text(a)
        if s == "-delete":
            danger = True
        if s in ("-exec", "-execdir", "-ok", "-okdir"):
            sub = strip_wrappers(rest[k + 1:], ctx)
            if sub:
                n2, ok2 = resolve_name(sub[0], ctx)
                txt = " ".join(word_to_text(x) for x in sub)
                if not ok2 or n2 in ("rm", "rmdir", "unlink", "shred", "truncate", "srm", "wipe") or (n2 in SHELLS and re.search(r"\b(rm|shred|truncate|unlink)\b", txt)):
                    danger = True
    if not danger:
        return
    if not roots:
        add(line, "R4", "find with -delete / -exec rm and no explicit search root (walks the current directory)")
    for w in roots:
        st = word_status(w, ctx, guarded)
        if st:
            add(line, "R4", "find root %s with -delete / -exec rm: %s" % (word_to_text(w)[:80], st[1]))


# ---------------------------------------------------------------- python
def parse_py(text):
    try:
        return ast.parse(text)
    except (SyntaxError, ValueError):
        return None


PLACEHOLDER_RE = re.compile(r"%[-#0 +]*\d*(?:\.\d+)?[sdrfx]|%\([A-Za-z_]\w*\)[sdrfx]|\{[^{}]*\}")
SHELL_INTERP_RE = re.compile(r"\$\{|\$\(|\$[A-Za-z_0-9@*#?!$]|`")
PY_RMFUNCS = ("rmtree", "removedirs", "remove_tree")


def dotdot_const(e):
    for n in ast.walk(e):
        if isinstance(n, ast.Constant) and isinstance(n.value, str) and ".." in n.value.split("/"):
            return True
    return False


def lint_py_tree(tree, path, interp=False):
    out, proven, assigns = [], set(), {}
    rm_alias = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            for al in node.names:
                if al.name in PY_RMFUNCS and al.asname:
                    rm_alias.add(al.asname)
        elif isinstance(node, ast.Assign) and isinstance(node.value, (ast.Attribute, ast.Name)) and unparse(node.value).split(".")[-1] in PY_RMFUNCS:
            for tgt in node.targets:
                if isinstance(tgt, ast.Name):
                    rm_alias.add(tgt.id)
    scope_of = {}                                  # id(node) -> innermost enclosing function (None = module)

    def walk_scopes(n, sc):
        scope_of[id(n)] = sc
        nsc = n if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)) else sc
        for ch in ast.iter_child_nodes(n):
            walk_scopes(ch, nsc)
    walk_scopes(tree, None)
    cur = [None]                                   # scope of the call being judged

    class _Assigns(dict):
        """name -> assigned values visible from the call being judged: those of its own function, else the module's"""
        def get(self, name, default=None):
            lst = dict.get(self, name, [])
            mine = [v for (v, sc) in lst if sc is cur[0]]
            if mine:
                return mine
            return [v for (v, sc) in lst if sc is None] or (default if default is not None else [])

        def setdefault(self, name, default=None):
            return dict.setdefault(self, name, [])
    assigns = _Assigns()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for tgt in node.targets:
                if isinstance(tgt, ast.Name):
                    dict.setdefault(assigns, tgt.id, []).append((node.value, scope_of.get(id(node))))
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.value is not None:
            dict.setdefault(assigns, node.target.id, []).append((node.value, scope_of.get(id(node))))
        elif isinstance(node, ast.arguments):
            for a in node.args + node.kwonlyargs:
                if re.fullmatch(r"(tmp_path|tmpdir|tmp_path_factory|tmpdir_factory)", a.arg):
                    proven.add(a.arg)
        elif isinstance(node, ast.Assert):
            # `assert NAME ...` / `assert os.path.isabs(NAME)`: the value was checked before it is used as a delete prefix
            for sub_n in ast.walk(node.test):
                if isinstance(sub_n, ast.Name):
                    proven.add(sub_n.id)
        elif isinstance(node, (ast.With, ast.AsyncWith)):
            for it in node.items:
                if isinstance(it.optional_vars, ast.Name):
                    dict.setdefault(assigns, it.optional_vars.id, []).append((it.context_expr, scope_of.get(id(node))))

    def home(e, seen=()):
        if isinstance(e, ast.Constant):
            return isinstance(e.value, str) and e.value.startswith("~")
        if isinstance(e, ast.Call):
            f = unparse(e.func)
            if f.endswith(("expanduser", "Path.home", ".home")) or f == "home":
                return True
            if f.endswith(("getenv", "environ.get")) and e.args and isinstance(e.args[0], ast.Constant) and e.args[0].value == "HOME":
                return True
            if f in ("str", "Path", "pathlib.Path", "os.path.abspath", "os.path.realpath", "os.fspath", "os.path.normpath") and e.args:
                return home(e.args[0], seen)
            return False
        if isinstance(e, ast.Subscript):
            t = unparse(e)
            return "environ" in t and "HOME" in t
        if isinstance(e, ast.Name):
            return e.id not in seen and any(home(v, seen + (e.id,)) for v in assigns.get(e.id, []))
        if isinstance(e, ast.BinOp):
            return home(e.left, seen) and isinstance(e.right, ast.Constant) and e.right.value in ("", "/")
        return False

    def rootlit(e):
        return isinstance(e, ast.Constant) and isinstance(e.value, str) and e.value in ("/", "/home", "/Users", "~")

    def const_anchored(v):
        """a string literal used as (the start of) a path: the text before the first placeholder / shell interpolation must itself be an anchored prefix"""
        cut = len(v)
        for rx in ((PLACEHOLDER_RE, SHELL_INTERP_RE) if interp else (PLACEHOLDER_RE,)):
            m = rx.search(v)
            if m:
                cut = min(cut, m.start())
        if cut < len(v):
            return anchored_prefix_ok(v[:cut]) and v[:cut].startswith("/")
        return bool(v) and v not in ("/", "/home", "/Users", "~", ".", "..") and not static_bad(v) and not v.startswith("~")

    def anchored(e, seen=()):
        if dotdot_const(e):
            return False
        if isinstance(e, ast.Constant):
            return isinstance(e.value, str) and const_anchored(e.value)
        if isinstance(e, ast.JoinedStr):
            if not e.values:
                return False
            f = e.values[0]
            return anchored(f.value, seen) if isinstance(f, ast.FormattedValue) else anchored(f, seen)
        if isinstance(e, ast.BinOp):
            return anchored(e.left, seen)
        if isinstance(e, ast.Call):
            fn = unparse(e.func)
            if fn in ("tempfile.mkdtemp", "mkdtemp", "tempfile.gettempdir", "tempfile.TemporaryDirectory", "TemporaryDirectory", "tempfile.mkstemp"):
                return True
            if fn.endswith(".format") and isinstance(e.func, ast.Attribute):
                return anchored(e.func.value, seen)
            if fn.endswith("path.join") and len(e.args) >= 2:
                # join("", "x") is the RELATIVE "x": an empty first component can never produce an absolute path; only a later absolute component (join(a, "/x") == "/x") or '..' can
                return not any(isinstance(a, ast.Constant) and isinstance(a.value, str) and a.value.startswith("/") for a in e.args[1:])
            if fn.endswith(("path.join", "Path", "PurePath", "str", "os.fspath", "abspath", "realpath", "resolve")) and e.args:
                return anchored(e.args[0], seen)
            return False
        if isinstance(e, ast.Attribute):
            return e.attr not in ("parent", "parents", "root", "anchor", "drive") and anchored(e.value, seen)
        if isinstance(e, ast.Name):
            if e.id in proven:
                return True
            vals = assigns.get(e.id)
            if e.id in seen or not vals:
                return False
            return all(anchored(v, seen + (e.id,)) for v in vals)
        return False

    TAINT_RE = re.compile(r"^(sys\.argv|os\.environ|environ|os\.getenv|getenv|input|raw_input)\b")

    def tainted(e, seen=()):
        """the WHOLE value comes from argv / the environment / stdin (directly, through str()/abspath()/Path(), `x or y`, or through a variable): the caller controls it, so it is not provably a sandbox path.
        (A taint source used as one component of os.path.join(a, "x") cannot make the result root.)"""
        if isinstance(e, ast.Name):
            return e.id not in seen and any(tainted(v, seen + (e.id,)) for v in assigns.get(e.id, []))
        if isinstance(e, ast.BoolOp):
            return any(tainted(v, seen) for v in e.values)
        if isinstance(e, ast.IfExp):
            return tainted(e.body, seen) or tainted(e.orelse, seen)
        if isinstance(e, ast.Call):
            fn = unparse(e.func)
            if TAINT_RE.match(fn):
                return True
            if fn.endswith(("str", "Path", "abspath", "realpath", "normpath", "fspath", "expanduser", "resolve", "get", "strip", "rstrip")) and e.args and not fn.endswith("get"):
                return tainted(e.args[0], seen)
            if fn.endswith("get") and isinstance(e.func, ast.Attribute):
                return tainted(e.func.value, seen)
            return False
        if isinstance(e, (ast.Subscript, ast.Attribute)):
            return bool(TAINT_RE.match(unparse(e))) or tainted(e.value, seen)
        return False

    def bare_ok(e, seen=()):
        """a bare variable / attribute / subscript (no concatenation): an EMPTY value makes rmtree raise, so only its origin matters - composite or external origins are not accepted"""
        if isinstance(e, ast.Name):
            if e.id in proven:
                return True
            if e.id in seen:
                return True
            return all(value_ok(v, seen + (e.id,)) for v in assigns.get(e.id, []))
        if isinstance(e, ast.Attribute):
            return e.attr not in ("parent", "parents", "root", "anchor", "drive") and bare_ok(e.value, seen)
        if isinstance(e, ast.Subscript):
            return bare_ok(e.value, seen)
        return False

    def value_ok(v, seen):
        if isinstance(v, (ast.Name, ast.Attribute, ast.Subscript)):
            return bare_ok(v, seen)
        if isinstance(v, ast.Constant) and not isinstance(v.value, str):
            return True
        if isinstance(v, ast.Call) and unparse(v.func).endswith(("str", "Path", "PurePath", "abspath", "realpath", "normpath", "fspath", "resolve")) and v.args:
            return value_ok(v.args[0], seen)          # a wrapper that keeps the value's nature: judge what is inside
        if isinstance(v, (ast.JoinedStr, ast.BinOp, ast.Constant)) or (isinstance(v, ast.Call) and (unparse(v.func).endswith(("path.join", ".format", "Path", "PurePath", "abspath", "realpath", "dirname", "resolve")))):
            return anchored(v, seen)
        return True           # an opaque call result: empty makes rmtree raise; composite / external origins are the ones that matter

    def target(e, node, what):
        if home(e):
            out.append((node.lineno, "R5", what + " of a HOME-derived path: " + unparse(e)[:80]))
        elif rootlit(e):
            out.append((node.lineno, "R5", what + " of a root literal: " + unparse(e)[:80]))
        elif tainted(e):
            out.append((node.lineno, "R5", what + " of a value taken from argv/the environment/stdin (not provably a sandbox path): " + unparse(e)[:80]))
        elif isinstance(e, (ast.Name, ast.Attribute, ast.Subscript)):
            if dotdot_const(e) or not bare_ok(e):
                out.append((node.lineno, "R5", what + " of a variable whose value is built from an unanchored expression: " + unparse(e)[:80]))
        elif not anchored(e):
            out.append((node.lineno, "R5", what + " of a path that is not provably under a temp/sandbox dir (an empty prefix gives an absolute path; use a mkdtemp-derived path, or shell safe_rm_rf): " + unparse(e)[:80]))

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        cur[0] = scope_of.get(id(node))
        fn = unparse(node.func)
        if (fn.endswith(PY_RMFUNCS) or fn in rm_alias) and node.args:
            target(node.args[0], node, "recursive delete")
        elif fn.endswith(".callback") and len(node.args) >= 2 and unparse(node.args[0]).endswith("rmtree"):
            target(node.args[1], node, "recursive delete")
        elif fn in ("subprocess.run", "subprocess.call", "subprocess.check_call", "subprocess.check_output", "subprocess.Popen") and node.args and not isinstance(node.args[0], (ast.List, ast.Tuple)):
            a0 = node.args[0]
            if isinstance(a0, ast.Constant) and isinstance(a0.value, str):
                for (l2, r2, m2, s2) in lint_shell(a0.value, "<subprocess>", node.lineno):
                    out.append((node.lineno, r2, m2))
            elif isinstance(a0, ast.BinOp) and isinstance(a0.left, (ast.List, ast.Tuple)):
                pass                                   # an argv list built by concatenation: no shell involved
            elif re.search(r"\brm\b|-delete|rmtree|\bshred\b|\btruncate\b", unparse(a0)):
                out.append((node.lineno, "R5", "subprocess of a dynamically built rm/find command string"))
        elif fn in ("subprocess.run", "subprocess.call", "subprocess.check_call", "subprocess.check_output", "subprocess.Popen") and node.args and isinstance(node.args[0], (ast.List, ast.Tuple)):
            els = node.args[0].elts
            if els and isinstance(els[0], ast.Constant) and isinstance(els[0].value, str) and os.path.basename(els[0].value) in ("rm", "busybox"):
                if any(isinstance(x, ast.Constant) and is_rec_flag(x.value) for x in els):
                    for t in els[1:]:
                        if not (isinstance(t, ast.Constant) and isinstance(t.value, str) and t.value.startswith("-")):
                            target(t, node, "rm -r via subprocess")
        elif fn in ("os.system", "os.popen") and node.args:
            a0 = node.args[0]
            if isinstance(a0, ast.Constant) and isinstance(a0.value, str):
                for (l2, r2, m2, s2) in lint_shell(a0.value, "<os.system>", node.lineno):
                    out.append((node.lineno, r2, m2))
            elif re.search(r"\brm\b|-delete|\bshred\b|\btruncate\b", unparse(a0)):
                out.append((node.lineno, "R5", "os.system of a dynamically built rm/find command"))
    return out


def lint_py(text, path):
    tree = parse_py(text)
    if tree is None:
        return [(1, "R5", "python file does not parse; cannot prove its deletes are safe")]
    return lint_py_tree(tree, path)


# ---------------------------------------------------------------- driver
def is_shell(path, head):
    if path.endswith((".sh", ".bash")):
        return True
    first = head.split("\n")[0]
    return "." not in os.path.basename(path) and first.startswith("#!") and any(x in first for x in ("bash", "/sh", "zsh"))


def lint_heredoc(body, path, base_line, is_test, depth, ctx=None):
    tree = parse_py(body)
    if tree is not None and re.search(r"^\s*(import|from|def|print|class)\b", body, re.M):
        return [(base_line + l, r, m, "") for (l, r, m) in lint_py_tree(tree, path, True)]
    return lint_shell(body, path, base_line, is_test, depth, False, ctx)


def lint_text(path, text):
    if path.endswith(EXEMPT_SUFFIX):
        return []
    is_test = bool(re.search(r"(^|/)(test_[^/]*|lib_ro_[^/]*|lib_test[^/]*|[^/]*_test\.sh)$", path) or "/scripts/test/" in path or "/test/" in path)
    res = []
    if path.endswith(".py"):
        res = [(l, r, m, "") for (l, r, m) in lint_py(text, path)]
    elif is_shell(path, text[:200]):
        res = lint_shell(text, path, 1, is_test)
    lines = text.split("\n")
    out, seen = [], set()
    for (l, r, m, s) in sorted(res, key=lambda x: (x[0], x[1])):
        key = (l, r, m[:70])
        if key in seen:
            continue
        seen.add(key)
        sn = s or (lines[l - 1].strip()[:140] if 0 < l <= len(lines) else "")
        out.append("%s:%d: %s: %s   | %s" % (path, l, r, m, sn))
    return out


def lint_file(p):
    try:
        text = open(p, errors="replace").read()
    except OSError:
        return []
    return lint_text(p, text)


def lint_root(root):
    if os.path.isfile(root):
        return lint_file(root)
    res = []
    # The queue ROOT also holds runtime data that is not queue source: repos/ (the live fleet clones of the app repos) and state/ (snapshots/work copies of them). A suite run from a copy of the
    # whole queue dir (the GPU box) would otherwise lint third-party app code. Skipped at the top level only: a nested repos/ or state/ inside the source tree is still linted.
    for d, ds, fs in os.walk(root):
        ds[:] = sorted(x for x in ds if x not in SKIP_DIRS and not (d == root and x in ROOT_DATA_DIRS))
        for f in sorted(fs):
            p = os.path.join(d, f)
            if f.endswith(TEXT_SKIP_EXT) or os.path.islink(p):
                continue
            res += lint_file(p)
    return res


if __name__ == "__main__":
    allf = []
    for r in (sys.argv[1:] or ["."]):
        allf += lint_root(r)
    for x in allf:
        print(x)
    print("unsafe-rm lint: %d finding(s)" % len(allf))
    sys.exit(1 if allf else 0)
