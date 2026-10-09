#!/usr/bin/env python3
"""ovn_doc_executor.py - deterministic executor for `supply:gd-missing-doc` queue items (2026-10-09).

Why: a "add a `##` doc-comment above these GDScript functions" item is pure mechanics, but handing it to aider failed in a POSITIONAL way: the model
appended zero-context hunks at the end of the file instead of above the function (17 doc items took 59 cycles, 4,393 s and 2.59M tokens; dot_damage.gd
churned 12 times). Here the position is computed by code and the local model only writes the 1-3 words of prose per function; code lines are never
touched.

usage: ovn_doc_executor.py check <repo_dir> "<item line>"
       ovn_doc_executor.py apply <repo_dir> "<item line>"
stdout (one line, tab separated; exit status is always 0):
  check:  OK\\t<file>                       the item is a gd-missing-doc supply item for a tracked, non-banned .gd file
          SKIP\\t<why>
  apply:  APPLIED\\t<file>\\t<n> docs        working tree edited (NOT committed - the caller verifies, commits, credits)
          FAIL\\t<why>                      working tree left byte-identical
          SKIP\\t<why>
`apply` edits ONLY the working tree: for each named `func`/`static func` with no `##` line directly above it, the local LLM (LiteLLM, same endpoint and
env as scripts/ovn_local_research.py: LITELLM_BASE, LITELLM_MASTER_KEY, OVN_MODEL) gets the function body (<= 80 lines, max_tokens 200, temperature 0) and
returns 1-3 lines; the text is sanitised, every line is prefixed `## ` and inserted directly above the func line with the func's indentation. A `##`
block that is separated from its func by blank lines only gets those blank lines removed (no model call). All edits are computed first and written once;
any failure (model unreachable, rejected output, a function that is not there, `gdparse` failing) leaves the file byte-identical.
Annotations: Godot attaches a doc comment that sits ABOVE the `@annotation` lines of a func, so the block goes above the first annotation and an existing
`##` block above the annotations counts as the func's doc (never documented twice). OVN_DOC_ANNOTATED=above|skip (default: above only when the item's VERIFY is the
annotation-aware form of ovn_work_supply.verify_gd_docs, skip otherwise - legacy or missing VERIFY): skip = an undocumented func that carries annotations makes the whole item SKIP (model path).
env: OVN_DOC_EXECUTOR=off disables both subcommands. OVN_DOC_MAX_LINE (default 100) caps a written line's length including indentation.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

LITELLM = os.environ.get("LITELLM_BASE", "http://localhost:4000")
LITELLM_KEY = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")
MODEL = os.environ.get("OVN_MODEL", "qwen-dflash-27B")
MAX_BODY_LINES = 80
MAX_DOC_LINES = 3
MAX_LINE = int(os.environ.get("OVN_DOC_MAX_LINE", "100"))
FUNC_RE = r"^([ \t]*)(?:static )?func %s\("
# an annotation on a line of its own (@rpc, @warning_ignore("x"), @tool ...), optionally followed by a `# comment`; never `@onready var x`
ANNOT_RE = re.compile(r"^[ \t]*@\w+[ \t]*(\([^\n]*\))?[ \t]*(#[^\n]*)?$")
# ovn_work_supply.verify_gd_docs (2026-10-09 version) accepts a `##` above the func's annotations and carries this token; the earlier version looked only at the
# line directly above the func, so a doc written above an annotation (where Godot attaches it) left that VERIFY red. Default placement: `above` only when the
# item PROVES it carries the new VERIFY; legacy items, and items whose VERIFY text is missing or was stripped, leave annotated funcs to the model path (SKIP).
# OVN_DOC_ANNOTATED=above|skip overrides.
ANNOT_VERIFY_MARK = "docabove=lambda"


# ---------------------------------------------------------------- item parsing
def banned_list(root):
    out = []
    try:
        for ln in open(os.path.join(root, ".queue-hard-banned-files"), encoding="utf-8"):
            ln = ln.strip()
            if ln and not ln.startswith("#"):
                out.append(ln)
    except OSError:
        pass
    return out


def is_banned(path, root):
    """addons/, any battle.gd, and everything on the repo's .queue-hard-banned-files (equal, prefix, or - like run_overnight.sh's `grep -E` - a regex)."""
    if path.startswith("addons/") or "/addons/" in path or os.path.basename(path) == "battle.gd":
        return True
    for b in banned_list(root):
        if path == b or path.startswith(b):
            return True
        try:
            if re.search(b, path):
                return True
        except re.error:
            pass
    return False


def parse_item(item):
    """-> (file, [function names]); file is None when the item does not start with a path."""
    t = re.sub(r"^\s*- \[[ xX]\]\s*", "", item.strip())
    t = re.sub(r"^(\[[^\]]*\]\s*|\([^)]*\)\s*)+", "", t)
    head, _, rest = t.partition(" — ")
    f = head.strip().strip("`")
    if not re.fullmatch(r"[A-Za-z0-9_./@-]+\.gd", f):
        f = None
    desc = rest.split("VERIFY:")[0]
    m = re.search(r"GDScript functions?:(.*?)(?:Comments only|$)", desc, re.S)
    seg = m.group(1) if m else desc
    names = []
    for n in re.findall(r"`([A-Za-z_]\w*)`", seg):
        if n not in names:
            names.append(n)
    return f, names


def decide(repo, item):
    if os.environ.get("OVN_DOC_EXECUTOR", "on") == "off":
        return ("SKIP", "OVN_DOC_EXECUTOR=off")
    if "supply:gd-missing-doc" not in item:
        return ("SKIP", "not a gd-missing-doc supply item")
    f, names = parse_item(item)
    if not f:
        return ("SKIP", "no .gd target path")
    if ".." in f.split("/") or f.startswith("/"):
        return ("SKIP", "unsafe path")
    if subprocess.run(["git", "-C", repo, "--literal-pathspecs", "ls-files", "--error-unmatch", "--", f], capture_output=True).returncode != 0:
        return ("SKIP", "target not tracked")
    if is_banned(f, repo):
        return ("SKIP", "banned file")
    if not names:
        return ("SKIP", "no function names in the item")
    return ("OK", f)


# ---------------------------------------------------------------- the model call (same endpoint/env conventions as ovn_local_research.call_model)
def call_model(prompt):
    body = json.dumps({"model": MODEL, "messages": [{"role": "user", "content": prompt}], "temperature": 0, "max_tokens": 200}).encode()
    req = urllib.request.Request(LITELLM + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + LITELLM_KEY})
    with urllib.request.urlopen(req, timeout=120) as r:
        d = json.load(r)
    return d["choices"][0]["message"]["content"] or ""


def func_body(lines, i):
    """The function starting at lines[i]: header + every following line that is blank or indented deeper than the header; capped at MAX_BODY_LINES."""
    ind = len(re.match(r"[ \t]*", lines[i]).group(0))
    out = [lines[i]]
    for l in lines[i + 1:]:
        if l.strip() and len(re.match(r"[ \t]*", l).group(0)) <= ind:
            break
        out.append(l)
    while len(out) > 1 and not out[-1].strip():
        out.pop()
    return out[:MAX_BODY_LINES]


def make_prompt(path, name, body):
    return ("Write the GDScript doc comment for the function `%s` in %s.\n"
            "Reply with 1 to 3 plain-English lines: what it does, what its arguments mean, and what it returns. "
            "No code, no markdown, no quotes, no leading ##, no blank lines, each line under 90 characters. Reply with ONLY those lines.\n\n%s\n"
            % (name, path, "\n".join(body)))


def sanitise(text, indent):
    """Model reply -> list of `## ...` lines, or (None, why). Fences, blank lines (paragraphs), > 3 lines, over-long lines and empty replies are rejected."""
    t = re.sub(r"<think>.*?</think>", "", text or "", flags=re.S).strip()
    if not t:
        return None, "empty model reply"
    if "```" in t:
        return None, "model reply contains a code fence"
    raw = t.split("\n")
    if any(not l.strip() for l in raw):
        return None, "multi-paragraph model reply"
    out = []
    for l in raw:
        l = l.strip().strip("\"'`").strip()
        l = re.sub(r"^(##|#|//)\s*", "", l).strip()
        l = l.strip("\"'`").strip()
        if not l:
            return None, "empty line after sanitising"
        if re.match(r"^(func |var |const |signal |class )", l):
            return None, "model reply looks like code"
        out.append("## " + l)
    if len(out) > MAX_DOC_LINES:
        return None, "model reply longer than %d lines" % MAX_DOC_LINES
    for l in out:
        if len(indent) + len(l) > MAX_LINE:
            return None, "doc line over %d columns" % MAX_LINE
    return out, None


# ---------------------------------------------------------------- edit planning
def anchor(lines, i):
    """Index of the first line of the declaration whose `func` line is lines[i]: walks up over annotation-only lines (a `##` block belongs above them)."""
    a = i
    while a > 0 and ANNOT_RE.match(lines[a - 1]):
        a -= 1
    return a


def _documented(lines, i):
    """True when a `##` line sits above the declaration of lines[i] (above its annotations, blank lines allowed in between)."""
    j = anchor(lines, i) - 1
    while j >= 0 and not lines[j].strip():
        j -= 1
    return j >= 0 and lines[j].lstrip().startswith("##")


def plan_edits(repo, f, names, lines, annotated="above"):
    """-> (edits, why). edits = list of ('insert', idx, [doc lines]) / ('drop_blank', idx, anchor idx). Pure function of the file text and the model replies.
    annotated='skip': an undocumented func that carries annotations is not touched and the plan fails with a SKIP-worthy reason (see apply)."""
    edits = []
    if annotated == "skip":   # decided before any model call is made
        for name in names:
            idxs = [i for i, l in enumerate(lines) if re.match(FUNC_RE % re.escape(name), l)]
            if idxs and anchor(lines, idxs[0]) < idxs[0] and not _documented(lines, idxs[0]):
                return None, "SKIP:`%s` carries annotations and the item VERIFY wants the doc directly above the func" % name
    for name in names:
        rx = re.compile(FUNC_RE % re.escape(name))
        idxs = [i for i, l in enumerate(lines) if rx.match(l)]
        if not idxs:
            return None, "function `%s` not found in %s" % (name, f)
        i = idxs[0]
        a = anchor(lines, i)
        j = a - 1
        while j >= 0 and not lines[j].strip():
            j -= 1
        if j >= 0 and lines[j].lstrip().startswith("##"):
            if j < a - 1:   # a ## block separated from its declaration by blank lines: remove the blanks, write nothing
                edits.extend(("drop_blank", k, a) for k in range(j + 1, a))
            continue
        indent = rx.match(lines[i]).group(1)
        try:
            reply = call_model(make_prompt(f, name, func_body(lines, i)))
        except Exception as e:
            return None, "model call failed: %s" % str(e)[:120]
        doc, why = sanitise(reply, indent)
        if doc is None:
            return None, "%s for `%s`" % (why, name)
        edits.append(("insert", a, [indent + d for d in doc]))
    return edits, None


def apply_edits(lines, edits):
    drops = {e[1] for e in edits if e[0] == "drop_blank"}
    ins = {e[1]: e[2] for e in edits if e[0] == "insert"}
    out = []
    for i, l in enumerate(lines):
        if i in drops:
            continue
        if i in ins:
            out.extend(ins[i])
        out.append(l)
    return out


def invariant(old, new, names, n_ins_lines, n_drops):
    """Code lines are untouched: ignoring blank lines and `##` lines, new == old; the length changed by exactly the lines added minus the blanks dropped;
    and every named func has a ## directly above it."""
    code = lambda L: [l for l in L if l.strip() and not l.lstrip().startswith("##")]
    if code(new) != code(old):
        return "a code line changed"
    if len(new) != len(old) + n_ins_lines - n_drops:
        return "unexpected line count change"
    for n in names:
        rx = re.compile(FUNC_RE % re.escape(n))
        hit = [i for i, l in enumerate(new) if rx.match(l)]
        a = anchor(new, hit[0]) if hit else 0
        if not hit or not (a and new[a - 1].lstrip().startswith("##")):
            return "no ## directly above `%s` after the edit" % n
    return None


def gdparse_bin():
    for c in (os.path.join(os.path.expanduser("~"), "aider-venv", "bin", "gdparse"), shutil.which("gdparse")):
        if c and os.access(c, os.X_OK):
            return c
    return None


def apply(repo, item):
    act, info = decide(repo, item)
    if act != "OK":
        return (act, info)
    f = info
    _, names = parse_item(item)
    path = os.path.join(repo, f)
    try:
        raw = open(path, "rb").read()
        text = raw.decode("utf-8")
    except (OSError, UnicodeDecodeError) as e:
        return ("FAIL", "cannot read %s: %s" % (f, e))
    eol = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    mode = os.environ.get("OVN_DOC_ANNOTATED") or ("above" if ANNOT_VERIFY_MARK in item else "skip")
    edits, why = plan_edits(repo, f, names, lines, mode)
    if edits is None:
        return ("SKIP", why[5:]) if why.startswith("SKIP:") else ("FAIL", why)
    if not edits:
        return ("SKIP", "every named function already has a ## doc directly above")
    new = apply_edits(lines, edits)
    n_ins = sum(len(e[2]) for e in edits if e[0] == "insert")
    n_drop = sum(1 for e in edits if e[0] == "drop_blank")
    bad = invariant(lines, new, names, n_ins, n_drop)
    if bad:
        return ("FAIL", bad)
    n_docs = len({e[1] for e in edits if e[0] == "insert"}) + len({e[2] for e in edits if e[0] == "drop_blank"})
    try:
        with open(path, "wb") as fh:
            fh.write(eol.join(new).encode("utf-8"))
        gp = gdparse_bin()
        if gp:
            r = subprocess.run([gp, path], capture_output=True, text=True, timeout=60)
            if r.returncode != 0:
                raise RuntimeError("gdparse failed: %s" % (r.stdout + r.stderr).strip()[:160])
    except Exception as e:
        with open(path, "wb") as fh:   # restore the exact original bytes (safer than `git checkout` when the file had uncommitted edits)
            fh.write(raw)
        return ("FAIL", "restored %s: %s" % (f, e))
    return ("APPLIED", "%s\t%d docs" % (f, n_docs))


def main(argv):
    if len(argv) < 4 or argv[1] not in ("check", "apply"):
        print("SKIP\tusage: ovn_doc_executor.py check|apply <repo_dir> \"<item line>\"")
        return 0
    act, info = decide(argv[2], argv[3]) if argv[1] == "check" else apply(argv[2], argv[3])
    print("%s\t%s" % (act, info))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
