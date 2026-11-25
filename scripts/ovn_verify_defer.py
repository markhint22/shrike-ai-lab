#!/usr/bin/env python3
"""scripts/ovn_verify_defer.py - DEFERRED verdict for a GUT VERIFY clause whose test file a LATER sibling step creates (package q-order, 2026-11-24).

THE DEFECT (box logs 2026-11-23..24): xlite feature groups are emitted as  T1 `static func wasted_text` in scripts/battle/overkill_text.gd  then  T2 "create tests/test_overkill_text_wasted.gd".
T1's VERIFY is  grep -q 'static func wasted_text' scripts/battle/overkill_text.gd && godot ... -gtest=res://tests/test_overkill_text_wasted.gd -gexit.  The test file is the LATER step's
deliverable, so GUT prints "Could not find script ... Nothing was run", shadow_check says FAIL (GUT-target-missing), auto-credit REFUSES ("the item's own VERIFY: clause FAILED") and the green push is
landed-uncredited (3 rows) / the post-deploy verify log fills with FAIL rows (15 in the window; 48 GUT-target-missing rows over 29 files since 10-18).

RULE. A clause is DEFERRABLE only when EVERY -gtest target that is missing from the tree is the LEAD path of a LATER, still OPEN (not parked) line of the SAME [feat:] group in the progress file.
A target nobody plans to create (a hallucinated path such as xlite/tests/x.gd) is never deferrable: it stays a FAIL. The step's own line is never a creator (the verify runs after the step: a file the
step itself should have made and did not is a real failure).
  DEFER-ARTIFACT <t>  the clause is `<artifact probe> && godot ... -gtest=<t>`: godot only ran because the probe (the step's own artifact: grep -q 'static func x' file) passed -> credit may proceed
  DEFER-ONLY <t>      the clause has no probe: nothing proves the step's artifact exists -> indeterminate (UNRUNNABLE, never FAIL, never credited)
  NO <reason>         not deferrable: FAIL stays FAIL

MODE OVN_VERIFY_DEFER = off | shadow | enforce (default shadow: would-defer rows go to state/verify_defer_shadow.log, the verdict is unchanged). Fail-safe: any error prints `NO error` rc 0.

  ovn_verify_defer.py check PROG LINE --tree DIR [--cmd CLAUSE]   one clause, prints the verdict
"""
import os
import re
import shlex
import sys

FEAT = re.compile(r"\[feat:([^\]\s]+)\]")
PATH = re.compile(r"[\w@./-]+\.(?:py|ts|tsx|js|jsx|vue|mjs|gd|kt|swift)\b")
PARKED = re.compile(r"AUTO-SKIP|HUMAN-ONLY|BLOCKED|\[CLAUDE\]|\(retired")
OPEN = re.compile(r"^\s*- \[ \]")
GTEST = re.compile(r"-gtest=(\S+)")


def mode(m=None):
    v = (m or os.environ.get("OVN_VERIFY_DEFER", "shadow") or "shadow").strip().lower()
    return v if v in ("off", "shadow", "enforce") else "shadow"


def _head(line):
    h = re.sub(r"VERIFY:.*$", "", line or "", flags=re.S)
    h = re.sub(r"^\s*- \[[ xX]\]\s*", "", h)
    return re.sub(r"\[[^\]]*\]", " ", h)


def lead_path(line):
    m = PATH.search(_head(line))
    return m.group(0).lstrip("./") if m else ""


def targets(cmd):
    out = []
    for m in GTEST.finditer(cmd or ""):
        for part in m.group(1).strip("'\"").split(","):
            part = part.strip("'\"")
            if part.startswith("res://"):
                part = part[6:]
            if part.endswith(".gd"):
                out.append(part)
    return out


_NULL_REDIR = re.compile(r"\s+(?:\d?>>?\s*/dev/null|2>&1)(?=\s|$)")


def _split_and(text):
    """split on `&&` that sits outside quotes; None when a `;` / `|` / `||` / single `&` / newline / command substitution appears outside single quotes."""
    segs, cur, q, i = [], [], "", 0
    while i < len(text):
        c = text[i]
        if q == "'":
            cur.append(c)
            if c == "'":
                q = ""
        elif c == "\\" and i + 1 < len(text):
            cur.append(text[i:i + 2])
            i += 1
        elif c == "`" or (c == "$" and text[i + 1:i + 2] == "("):
            return None
        elif q == '"':
            cur.append(c)
            if c == '"':
                q = ""
        elif c in "'\"":
            q = c
            cur.append(c)
        elif c == "&" and text[i + 1:i + 2] == "&":
            segs.append("".join(cur))
            cur = []
            i += 1
        elif c in ";|&\n\r":
            return None
        else:
            cur.append(c)
        i += 1
    segs.append("".join(cur))
    return segs


def _simple_probe(seg):
    """ONE simple artifact probe: `grep -q ... F` | `test -f F` | `[ -f F ]`. No pipe, no list, no substitution, no other redirect than to /dev/null."""
    seg = _NULL_REDIR.sub("", seg.strip())
    if not seg or re.search(r"[<>(){}]", re.sub(r"'[^']*'|\"[^\"]*\"", "", seg)):
        return False
    try:
        w = shlex.split(seg)
    except ValueError:
        return False
    if not w:
        return False
    if w[0] == "grep":
        flags = [a for a in w[1:] if re.fullmatch(r"-[A-Za-z]+|--[a-z-]+", a)]
        rest = [a for a in w[1:] if a not in flags]
        quiet = any(re.fullmatch(r"-[A-Za-z]*q[A-Za-z]*", a) or a in ("--quiet", "--silent") for a in flags)
        return quiet and len(rest) >= 2
    if w[0] == "test":
        return len(w) == 3 and w[1] == "-f"
    if w[0] == "[":
        return len(w) == 4 and w[1] == "-f" and w[3] == "]"
    return False


def _has_artifact_probe(pre):
    """`pre` = the clause text before the godot launcher. The LAST `&&` piece is the launcher (or its stand-in); every piece before it must be ONE simple probe."""
    segs = _split_and(pre)
    if not segs or len(segs) < 2:
        return False
    return all(_simple_probe(s) for s in segs[:-1])


def check(prog_lines, ln, cmd, tree):
    """-> 'DEFER-ARTIFACT <t,..>' | 'DEFER-ONLY <t,..>' | 'NO <reason>'"""
    if ln < 1 or ln > len(prog_lines):
        return "NO line-out-of-range"
    line = prog_lines[ln - 1]
    if "gut_cmdln" not in (cmd or ""):
        return "NO not-gut"
    tg = targets(cmd)
    if not tg:
        return "NO no-gtest-target"
    missing = [t for t in tg if not os.path.isfile(os.path.join(tree, t))]
    if not missing:
        return "NO target-exists"
    m = FEAT.search(line)
    if not m:
        return "NO no-feat-group"
    feat = m.group(1)
    later = [l for l in prog_lines[ln:] if OPEN.match(l) and not PARKED.search(l) and ("[feat:%s]" % feat) in l]
    leads = set(lead_path(l) for l in later)
    for t in missing:
        if t not in leads:
            return "NO no-later-open-sibling-creates %s" % t
    pre = cmd[:cmd.index("gut_cmdln")]
    pre = pre.rsplit("godot", 1)[0] if "godot" in pre else pre
    artifact = _has_artifact_probe(pre)
    return "%s %s" % ("DEFER-ARTIFACT" if artifact else "DEFER-ONLY", ",".join(missing))


def main(argv):
    try:
        if len(argv) >= 4 and argv[1] == "check":
            prog, ln = argv[2], int(argv[3])
            tree = argv[argv.index("--tree") + 1] if "--tree" in argv else "."
            cmd = argv[argv.index("--cmd") + 1] if "--cmd" in argv else ""
            with open(prog, encoding="utf-8", errors="replace") as f:
                lines = f.read().split("\n")
            if not cmd:
                m = re.search(r"VERIFY:\s*`([^`]+)`", lines[ln - 1] if 0 < ln <= len(lines) else "")
                cmd = m.group(1) if m else ""
            print(check(lines, ln, cmd, tree))
            return 0
    except Exception as e:  # fail-safe
        print("NO error %s" % type(e).__name__)
        return 0
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
