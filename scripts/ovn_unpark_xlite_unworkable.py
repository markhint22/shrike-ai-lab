#!/usr/bin/env python3
"""ovn_unpark_xlite_unworkable.py - lists the lines parked `[CLAUDE] [unworkable: ...]` that the FIXED unworkable rule would NOT park, and prints the retag diff (intake package, 2026-10-13).

Why: why_unworkable() scanned the whole item line, so the GUT runner named in a VERIFY (addons/gut/gut_cmdln.gd) matched the vendored-code ban `addons/` and 9 xlite 'Create test X'
items were parked [unworkable: hard-banned file addons/gut/gut_cmdln.gd] (the lane then had no supply). ovn_park_unworkable.py now scans only the text before `VERIFY:`. The parked lines stay
parked until someone retags them; this is that retag, as a reviewable diff.

  ovn_unpark_xlite_unworkable.py --progress <OVERNIGHT_PROGRESS.md> --repo-root <checkout> [--max-bytes 120000] [--json-out FILE]        DRY RUN (default): nothing is written
  ovn_unpark_xlite_unworkable.py ... --apply                                                                                            write the retags into --progress (and only there)

For each OPEN line of the form `... [CLAUDE] [unworkable: <why>] <original item text>` the original text is rescanned with the current why_unworkable():
  RETAG    still no reason to park AND no other parking tag is left on the line -> the `[CLAUDE] [unworkable: <why>] ` tag is dropped; the item is doable again
  KEEP     the rule still parks it (a REAL banned / oversize target, e.g. addons/gut/strutils.gd): untouched
  HELD     no longer unworkable, but another parking tag (AUTO-SKIP / HUMAN-ONLY / BLOCKED ...) stays on the line: dropping ours would not make it doable, so it is only reported
Applying follows tick_lines.py (tools/claude-queue-triage): decisions are TEXT-ANCHORED (never by line number: the fleet edits the file constantly), a decision must match exactly one OPEN line,
a miss or an ambiguity is reported and skipped (the match is on the EXACT parked line text), and nothing is pushed or committed here: the caller owns the worktree / commit / push (non-force). The script never touches git, the live queue
dir or any file other than --progress (with --apply) and --json-out.
--json-out writes the decisions: {"retag": [{"anchor": <unique substring of the open line or null>, "line_text": <the exact parked line>, "line": <1-based line at read time, informational>, "old": <tag removed>, "why": <old reason>}]}
Exit 0 always (2 on a bad argument).
"""
import json
import os
import re
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))     # ovn_park_unworkable.py lives next to scripts/, in the queue dir
import ovn_park_unworkable as P  # noqa: E402

TAG_RE = re.compile(r"\[CLAUDE\] \[unworkable: ([^\]]*)\]\s?")
OPEN_PREFIX = "- [ ] "


def _anchor(line, open_lines):
    """A substring of `line` that occurs in exactly one open line: the item text from its tier tag on (clipped), widened to the rest of the line when that is not unique."""
    m = re.search(r"\[T[1-5]\]\s", line)
    start = m.start() if m else 0
    tail = line[start:]
    cut = re.split(r"\sVERIFY:", tail, maxsplit=1)[0]
    for cand in (cut[:140], cut, tail):
        if cand and sum(1 for l in open_lines if cand in l) == 1:
            return cand
    return None


def plan(text, root, max_bytes=120000):
    """-> (retags, keeps, held): lists of dicts {line, why, text, ...} (1-based line numbers of `text`). Pure: reads only `root`'s tree."""
    lines = text.split("\n")
    open_lines = [l for l in lines if l.startswith(OPEN_PREFIX)]
    banned = P.banned_list(root)
    retags, keeps, held = [], [], []
    for n, l in enumerate(lines, 1):
        if not l.startswith(OPEN_PREFIX):
            continue
        m = TAG_RE.search(l)
        if not m:
            continue
        orig = (OPEN_PREFIX + (l[len(OPEN_PREFIX):m.start()] + l[m.end():])).rstrip()    # the line as it was before the park tag was prepended
        still = P.why_unworkable(orig, root, banned, max_bytes)
        rec = {"line": n, "old": m.group(0).rstrip(), "why": m.group(1), "text": l[len(OPEN_PREFIX):][:160], "orig_line": l}
        if still:
            rec["still"] = still
            keeps.append(rec)
            continue
        rest = l[:m.start()] + l[m.end():]
        if P.PARKED_RE.search(rest):
            rec["other"] = P.PARKED_RE.search(rest).group(0)
            held.append(rec)
            continue
        rec["new_line"] = rest
        rec["anchor"] = _anchor(l, open_lines)
        retags.append(rec)
    return retags, keeps, held


def apply_retags(text, retags):
    """-> (new_text, report [str], changed): TEXT-anchored (never by line number), one OPEN line per decision, tick_lines.py semantics. A decision is matched by the EXACT text of the parked line it
    was planned from (stricter than a substring anchor: line N's text can be a prefix of line M's); a line the fleet edited since, a miss, or two identical lines are reported and skipped."""
    lines = text.split("\n")
    report, changed = [], 0
    for r in retags:
        want = r["orig_line"]
        idx = [i for i, l in enumerate(lines) if l == want]
        if not idx:
            report.append("SKIP (the parked line changed or is gone) %s" % want[:70])
        elif len(idx) > 1:
            report.append("REFUSED (%d identical lines) %s" % (len(idx), want[:70]))
        else:
            m = TAG_RE.search(want)
            lines[idx[0]] = want[:m.start()] + want[m.end():]
            changed += 1
            report.append("retagged %s" % (r.get("anchor") or want)[:70])
    return "\n".join(lines), report, changed


def main(argv):
    prog = root = jout = None
    max_bytes, do_apply = 120000, False
    try:
        i = 0
        while i < len(argv):
            a = argv[i]
            if a == "--progress":
                prog = argv[i + 1]; i += 2
            elif a == "--repo-root":
                root = argv[i + 1]; i += 2
            elif a == "--max-bytes":
                max_bytes = int(argv[i + 1]); i += 2
            elif a == "--json-out":
                jout = argv[i + 1]; i += 2
            elif a == "--apply":
                do_apply = True; i += 1
            elif a == "--dry-run":
                i += 1
            else:
                raise ValueError("unknown argument %r" % a)
        if not prog or not root:
            raise ValueError("--progress and --repo-root are required")
    except (ValueError, IndexError) as e:
        sys.stderr.write("ovn_unpark_xlite_unworkable: %s\nusage: ovn_unpark_xlite_unworkable.py --progress FILE --repo-root DIR [--max-bytes N] [--json-out FILE] [--apply]\n" % e)
        return 2
    try:
        with open(prog, encoding="utf-8", errors="surrogateescape") as f:
            text = f.read()
    except OSError as e:
        sys.stderr.write("ovn_unpark_xlite_unworkable: cannot read %s: %s\n" % (prog, e))
        return 2
    retags, keeps, held = plan(text, root, max_bytes)
    print("%s: %d parked-unworkable line(s): %d to RETAG (workable now), %d still unworkable (KEEP), %d held by another parking tag (HELD)" % (
        prog, len(retags) + len(keeps) + len(held), len(retags), len(keeps), len(held)))
    for r in retags:
        print("\nRETAG line %d  (was: %s)" % (r["line"], r["old"]))
        print("  - %s" % r["orig_line"][:220])
        print("  + %s" % r["new_line"][:220])
    for r in keeps:
        print("\nKEEP   line %d  still unworkable: %s" % (r["line"], r["still"]))
    for r in held:
        print("\nHELD   line %d  not unworkable any more, but still parked by %r" % (r["line"], r["other"]))
    if jout:
        with open(jout, "w", encoding="utf-8") as f:
            json.dump({"retag": [{"anchor": r["anchor"], "line_text": r["orig_line"], "line": r["line"], "old": r["old"], "why": r["why"]} for r in retags]}, f, indent=1)
        print("\ndecisions written to %s" % jout)
    if do_apply:
        new, report, changed = apply_retags(text, retags)
        print("\n" + "\n".join(report))
        if changed:
            # the temp file lives OUTSIDE the checkout (a sibling file would show up untracked in a live tree while the write is in flight); the final move is one os.replace, or a copy when the
            # temp dir is on another filesystem (EXDEV). The original file mode is kept.
            fd, tmp = tempfile.mkstemp(prefix="unpark-", suffix=".tmp")
            try:
                with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape") as f:
                    f.write(new)
                shutil.copymode(prog, tmp)
                try:
                    os.replace(tmp, prog)
                except OSError:
                    shutil.copyfile(tmp, prog)
            finally:
                if os.path.exists(tmp):
                    os.unlink(tmp)
        print("%d line(s) written to %s" % (changed, prog))
    else:
        print("\nDRY RUN: nothing written (re-run with --apply to retag %s; the caller commits and pushes)" % prog)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
