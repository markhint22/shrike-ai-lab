#!/usr/bin/env python3
"""scripts/ovn_verify_safe.py - safe, stage-aware evaluation of exit-code VERIFY clauses (R15 verify package, 2026-10-12).

Used by
  * ovn_verify_audit.py (EXECUTES credited items' VERIFY text on a scratch copy: untrusted, so every command must be on an ALLOW-LIST),
  * lib_verify_clause.sh shadow_check for NEGATIVE-polarity items (`neg-check`: the clause there is trusted and is run by the caller anyway; this only decides whether the
    caller's exit status can be believed as an "absent").

Why stage-aware: a pipeline's exit status is the LAST stage's, so `grep X missing_dir | grep -v y` (stage 1 rc 2, stage 2 rc 1) and `cd missing && grep ...` (rc 1) read as
"absent" - the unsafe direction for an absence check. Here a clause is split into pipelines (`&&` `||` `;`), each pipeline runs on its own with its per-stage statuses (bash
PIPESTATUS), `cd` is handled here (a failing cd is an error, never an absence), and any grep-family stage that exits >= 2 anywhere in the chain makes the whole result INDETERMINATE.

Allow-list (audit mode): grep egrep fgrep, test, [, ls, stat, cat, head, tail, wc, find (no -exec/-execdir/-ok/-okdir/-delete/-fprint*/-fls), diff, cmp, sort (no -o/--output/
--compress-program), uniq (at most one operand), tr, cut, cd (relative, no `..`). Operators: `|` `&&` `||` `;` only, between allow-listed commands. Rejected anywhere: backticks, `$(`,
process substitution, unquoted ( ) < > & newline, redirections (except 2>/dev/null, >/dev/null, 2>&1), env-assignment prefixes, commands given with a path. sed / awk / python / pytest /
git / ssh / nc / tee / touch / ... are NOT allow-listed: such a clause is never executed. Execution: env -i style minimal environment, own process group (killed as a group on timeout).

CLI: ovn_verify_safe.py neg-check <progress_file> <line> <cmd>   (cwd = repo)  prints INDETERMINATE:<why> | ABSENT-DELETED | OK
"""
import os
import re
import shlex
import signal
import subprocess
import sys

ALLOW = {"grep", "egrep", "fgrep", "test", "[", "ls", "stat", "cat", "head", "tail", "wc", "find", "diff", "cmp", "sort", "uniq", "tr", "cut", "cd"}
GREP = {"grep", "egrep", "fgrep", "rg", "ag", "zgrep"}
FIND_BAD = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"}
_REDIR_OK = re.compile(r"(?:>/dev/null|>&1)(?![\w/.&>-])")
SAFE_ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "CI": "true"}


class Unsafe(Exception):
    pass


def split_pipelines(cmd, strict=True):
    """-> [(connector_before, [stage strings])]; connector is '' for the first, else '&&' '||' ';'. strict: raise Unsafe on any construct that can run something unlisted."""
    pipes, stages, cur, q, i, conn = [], [], "", "", 0, ""
    n = len(cmd)
    while i < n:
        ch = cmd[i]
        if q:
            cur += ch
            if q == '"' and (ch == "`" or cmd.startswith("$(", i)) and strict:
                raise Unsafe("command substitution")
            if ch == "\\" and q == '"' and i + 1 < n:
                cur += cmd[i + 1]
                i += 1
            elif ch == q:
                q = ""
        elif ch in "'\"":
            q = ch
            cur += ch
        elif ch == "\\":
            if i + 1 < n and cmd[i + 1] == "\n":
                raise Unsafe("line continuation")
            cur += cmd[i:i + 2]
            i += 1
        elif ch in "`\n" or cmd.startswith("$(", i) or cmd.startswith("<(", i) or cmd.startswith(">(", i):
            if strict:
                raise Unsafe("substitution / newline")
            cur += ch
        elif ch in "<>&" and not (cmd.startswith("&&", i)):
            m = _REDIR_OK.match(cmd, i) if ch == ">" else None
            if m:
                cur += m.group(0)
                i = m.end() - 1
            elif strict:
                raise Unsafe("redirection / background")
            else:
                cur += ch
        elif ch in "()" and strict:
            raise Unsafe("subshell")
        elif cmd.startswith("&&", i) or cmd.startswith("||", i) or ch == ";":
            stages.append(cur)
            pipes.append((conn, stages))
            conn = "&&" if ch == "&" else ("||" if ch == "|" else ";")
            stages, cur = [], ""
            i += 1 if ch != ";" else 0
        elif ch == "|":
            stages.append(cur)
            cur = ""
        else:
            cur += ch
        i += 1
    if q:
        raise Unsafe("unbalanced quote")
    stages.append(cur)
    pipes.append((conn, stages))
    for _, st in pipes:
        if any(not s.strip() for s in st):
            if strict:
                raise Unsafe("empty stage")
    return [(c, [s.strip() for s in st if s.strip()]) for c, st in pipes]


def words(stage):
    try:
        w = shlex.split(stage, posix=True)
    except ValueError as e:
        raise Unsafe("unparsable: %s" % e)
    w = [x for x in w if not re.fullmatch(r"(?:2>/dev/null|>/dev/null|2>&1)", x)]
    while w and w[0] == "!":
        w = w[1:]
    return w


def check_stage(w):
    """Raise Unsafe unless the (redirect-stripped, !-stripped) argv is an allow-listed read-only command."""
    if not w:
        raise Unsafe("empty command")
    c = w[0]
    if "/" in c or re.match(r"^\w+=", c):
        raise Unsafe("command with path / env prefix: %s" % c)
    if c not in ALLOW:
        raise Unsafe("not allow-listed: %s" % c)
    a = w[1:]
    if c == "find" and any(x in FIND_BAD or x.startswith("-fprint") for x in a):
        raise Unsafe("find with an action that executes or writes")
    if c == "sort" and any(x.startswith("--o") or x.startswith("--compress") or (x.startswith("-") and not x.startswith("--") and "o" in x) for x in a):
        raise Unsafe("sort with -o")
    if c == "uniq" and len([x for x in a if not x.startswith("-")]) > 1:
        raise Unsafe("uniq writes its 2nd operand")
    if c == "cd" and (len(a) != 1 or a[0].startswith("/") or ".." in a[0].split("/") or a[0].startswith("-") or a[0].startswith("~")):
        raise Unsafe("cd outside the tree")
    if c == "[" and a[-1:] != ["]"]:
        raise Unsafe("[ without ]")


def parse(cmd, allowlist=True):
    """-> pipelines [(conn, [argv...])] (raises Unsafe). With allowlist=False only structural parsing (trusted caller)."""
    out = []
    for conn, stages in split_pipelines(cmd, strict=allowlist):
        ws = []
        for s in stages:
            w = words(s)
            if allowlist:
                check_stage(w)
            ws.append((s, w))
        out.append((conn, ws))
    return out


def _run_pipeline(stage_text, cwd, timeout, env):
    script = stage_text + '\n__ps="${PIPESTATUS[*]}"\nprintf \'\\n@@PS %s\\n\' "$__ps"\n'
    p = subprocess.Popen(["bash", "-c", script], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=env, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.communicate()
        return None, "", True
    finally:
        try:
            os.killpg(p.pid, signal.SIGKILL)   # stragglers of a finished pipeline
        except OSError:
            pass
    txt = out.decode("utf-8", "replace")
    m = re.search(r"@@PS ([0-9 ]*)\n?\s*$", txt)
    ps = [int(x) for x in m.group(1).split()] if m else []
    return ps, txt[:m.start()] if m else txt, False


def run(cmd, cwd, timeout=20, allowlist=True, home=None):
    """Execute a clause stage-aware. -> dict(status=OK|UNSAFE|TIMEOUT, rc, err (bool: an earlier-stage / cd error makes an absence reading unsafe), why, out)."""
    try:
        pipes = parse(cmd, allowlist)
    except Unsafe as e:
        return {"status": "UNSAFE", "rc": None, "err": False, "why": str(e), "out": ""}
    env = dict(SAFE_ENV, HOME=home or cwd) if allowlist else dict(os.environ, CI="true")
    cur, rc, err, why, out_all = cwd, 0, False, "", ""
    for conn, stages in pipes:
        if conn == "&&" and rc != 0:
            continue
        if conn == "||" and rc == 0:
            continue
        if len(stages) == 1 and stages[0][1][:1] == ["cd"]:
            tgt = os.path.normpath(os.path.join(cur, stages[0][1][1])) if len(stages[0][1]) > 1 else ""
            if tgt and os.path.isdir(tgt):
                cur, rc = tgt, 0
            else:
                rc, err, why = 1, True, "cd target missing"
            continue
        if any(w[:1] == ["cd"] for _, w in stages):
            return {"status": "UNSAFE", "rc": None, "err": False, "why": "cd inside a pipeline", "out": ""}
        text = " | ".join(s for s, _ in stages)
        ps, o, to = _run_pipeline(text, cur, timeout, env)
        if to:
            return {"status": "TIMEOUT", "rc": 124, "err": False, "why": "timeout", "out": ""}
        out_all += o
        if not ps:
            return {"status": "UNSAFE", "rc": None, "err": False, "why": "no pipeline status", "out": o}
        rc = ps[-1]
        if re.match(r"^\s*!\s", stages[0][0] + " "):   # `! cmd` negates the pipeline status (PIPESTATUS keeps the raw ones)
            rc = 0 if rc != 0 else 1
        for (s, w), r in zip(stages, ps):
            tool = os.path.basename(w[0]) if w else ""
            if tool in GREP and r >= 2:
                err, why = True, "%s exited %d (an error, not an absence)" % (tool, r)
            if r in (126, 127):
                err, why = True, "stage not runnable (rc %d)" % r
    return {"status": "OK", "rc": rc, "err": err, "why": why, "out": out_all}


# the item's DESCRIPTION (text after the leading "<path> - ") must itself BEGIN with the delete verb applied to a file: "Delete the file entirely", "Delete the test file for the removed X",
# "Remove scripts/x.gd". NOT "Verify that no test calls the removed function" / "Remove the unused import" (a verb somewhere in the sentence is not enough: 3 xlite rows
# addons/gut/test_aoe*.gd mention "the removed function" but name a path that never existed -> rc 2 stays an error).
_DELETE_LEAD = re.compile(r"^\s*(?:delete|remove|git\s+rm|rm)\s+(?:(?:the|this|entire|whole|dead|obsolete|stale|old|test|unused)\s+)*(?:file\b|\S*{BASE}\S*)", re.I)


def delete_shape_ok(line, cmd, cwd):
    """Item 4 (livelock): a grep whose target file the ITEM ITSELF deletes exits 2 (no such file) forever, so an absence check could never be credited.
    Conservative: the item DESCRIPTION begins with delete/remove applied to a file (see _DELETE_LEAD), the clause is ONE plain grep-family command with no pipe/&&/||/;, it has at least one file operand, every file
    operand is missing in `cwd`, and each missing operand (or its basename) is named in the item text. Anything else -> False (rc 2 stays an error)."""
    try:
        pipes = parse(cmd, allowlist=False)
    except Unsafe:
        return False
    if len(pipes) != 1 or len(pipes[0][1]) != 1:
        return False
    w = pipes[0][1][0][1]
    if not w or w[0] not in GREP - {"rg", "ag", "zgrep"}:
        return False
    head = re.split(r"\bVERIFY:", line, 1)[0]
    desc = re.split(r"\s[\u2014\u2013-]+\s", head, 1)
    desc = desc[1] if len(desc) > 1 else ""
    args, ops, pat_done, i = w[1:], [], False, 0
    while i < len(args):
        x = args[i]
        if x == "--":
            ops += args[i + 1:]
            break
        if x.startswith("-") and len(x) > 1:
            if x in ("-e", "-f") or x in ("--regexp", "--file"):
                pat_done = True
                i += 1
            i += 1
            continue
        ops.append(x)
        i += 1
    if not pat_done and ops:
        ops = ops[1:]   # first non-option is the pattern
    ops = [o for o in ops if o]
    if not ops or any(re.search(r"[*?\[]", o) for o in ops):
        return False
    for o in ops:
        if os.path.exists(os.path.join(cwd, o)):
            return False
        if o not in head and os.path.basename(o) not in head:
            return False
    pat = re.compile(_DELETE_LEAD.pattern.replace("{BASE}", "(?:%s)" % "|".join(re.escape(os.path.basename(o)) for o in ops)), re.I)
    return bool(pat.match(desc))


def neg_check(prog, ln, cmd, cwd="."):
    """-> 'INDETERMINATE:<why>' | 'ABSENT-DELETED' | 'OK' for a NEGATIVE-polarity clause the caller has already run (trusted: not allow-listed, only stage-analysed)."""
    try:
        with open(prog, errors="surrogateescape") as f:
            line = f.read().split("\n")[ln - 1]
    except (OSError, IndexError):
        line = ""
    res = run(cmd, cwd, timeout=30, allowlist=False)
    if res["status"] != "OK":
        return "OK"   # could not analyse: caller keeps its own reading
    if res["err"]:
        if delete_shape_ok(line, cmd, cwd):
            return "ABSENT-DELETED"
        return "INDETERMINATE:" + res["why"]
    return "OK"


def main(argv):
    if len(argv) >= 5 and argv[1] == "neg-check":
        try:
            print(neg_check(argv[2], int(argv[3]), argv[4]))
        except Exception as e:  # noqa: BLE001
            print("OK")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
