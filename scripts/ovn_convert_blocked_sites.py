#!/usr/bin/env python3
"""scripts/ovn_convert_blocked_sites.py - convert the sites that still match BLOCKED case-insensitively (spec-compiler-v2, deploy-order fix, 2026-10-09).

Why. `BLOCKED` is a TAG (`BLOCKED ITEM`) and is matched case-sensitively by queue_refill / lib_parked_pattern.sh / ovn_backlog_eligibility.py. Pickers elsewhere still list it in a
CASE-INSENSITIVE alternation, so a lowercase-"blocked" item that queue_refill now pulls (all 10 open iptv_apps and 2 xlite items on 2026-10-09) would sit in the queue and be
skipped by them. `ovn_backlog_eligibility.py sites` lists them; queue_refill keeps those items held back while any remain (the deploy-order guard).

This tool rewrites exactly the lines `ovn_backlog_eligibility.unconverted_blocked_sites` reports, content-based (no line numbers, so it applies to any branch's copy of a file):
  python   re.compile(r"A|BLOCKED|B", re.I)          ->  re.compile(r"A|(?-i:BLOCKED)|B", re.I)          (scoped inline flag, Python >= 3.6)
  shell    ... | grep -viE 'A|BLOCKED|B' | ...       ->  ... | grep -viE 'A|B' | grep -vE 'BLOCKED' | ...
A shell grep that is not an inverted filter (-v) is reported and left alone. Idempotent (a converted line no longer matches). Exit 0 when nothing is left to convert.

Usage:  python3 scripts/ovn_convert_blocked_sites.py [--dry-run] FILE...
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ovn_backlog_eligibility as E  # noqa: E402


def _convert_py(line):
    new = line.replace("|BLOCKED|", "|(?-i:BLOCKED)|").replace("|BLOCKED\"", "|(?-i:BLOCKED)\"").replace("|BLOCKED'", "|(?-i:BLOCKED)'")
    new = new.replace("\"BLOCKED|", "\"(?-i:BLOCKED)|").replace("'BLOCKED|", "'(?-i:BLOCKED)|")
    return new


def _convert_sh(line):
    def one(m):
        pat = m.group(1) if m.group(1) is not None else m.group(2)
        q = "'" if m.group(1) is not None else '"'
        flags = re.search(r"grep\s+((?:-[A-Za-z]+\s+)*-[A-Za-z]*i[A-Za-z]*)", m.group(0)).group(1)
        if not E._ALT_MEMBER.search(pat) or E._VERDICT_ALT.search(pat) or "v" not in "".join(re.findall(r"-([A-Za-z]+)", flags)):
            return m.group(0)
        rest = [t for t in pat.split("|") if t != "BLOCKED"]
        if not rest or len(rest) == len(pat.split("|")):
            return m.group(0)
        return m.group(0).replace(q + pat + q, q + "|".join(rest) + q) + " | grep -vE 'BLOCKED'"
    return E._SH_GREP_I.sub(one, line)


def convert_text(path, text):
    """-> (new_text, [converted line numbers], [lines that need a human])"""
    out, done, todo = [], [], []
    for i, line in enumerate(text.split("\n"), 1):
        if "BLOCKED" in line and E._site_in_line(path, line):
            new = _convert_py(line) if path.endswith(".py") else _convert_sh(line)
            if new != line and not E._site_in_line(path, new):
                done.append(i)
                line = new
            else:
                todo.append(i)
        out.append(line)
    return "\n".join(out), done, todo


def main(argv):
    dry = "--dry-run" in argv
    files = [a for a in argv[1:] if not a.startswith("--")]
    if not files:
        sys.stderr.write(__doc__)
        return 2
    left = 0
    for p in files:
        with open(p, encoding="utf-8") as f:
            text = f.read()
        new, done, todo = convert_text(p, text)
        if done and not dry:
            tmp = p + ".convert.tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(new)
            os.chmod(tmp, os.stat(p).st_mode)
            os.replace(tmp, p)
        print("%s: converted %d line(s)%s%s" % (p, len(done), " " + str(done) if done else "", ("; NEEDS A HUMAN: lines %s" % todo) if todo else ""))
        left += len(todo)
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
