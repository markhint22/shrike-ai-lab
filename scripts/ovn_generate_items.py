#!/usr/bin/env python3
"""Deterministic overnight-queue item generator (Option C, self-generation).

Scans a repo for a CURATED set of high-precision, deterministically-SAFE
mechanical patterns and appends single-file items to OVERNIGHT_PROGRESS.md —
ONE item per file per pass (respecting the runner's per-file auto-credit). $0,
no LLM, no hallucination. Deliberately conservative: only patterns whose fix is
mechanical and cannot break behavior (so the no-new-red gate never trips):

  1. bare `except:`            -> `except Exception:`        (correctness, HIGH)
  2. `target="_blank"` no rel  -> add `rel="noopener"`        (security,   HIGH)
  3. `def __repr__(self):`     -> `def __repr__(self) -> str:` (typing,     LOW)
  4. single-line `def __init__(self...):` no `->` -> add `-> None` (typing, LOW)

It SKIPS anything needing judgment (utcnow, Query bounds, aria-*, Array.isArray,
lazy-img) — those are Option B (Claude) territory. Files already referenced by
an unchecked item are skipped to avoid duplicates.

Usage: ovn_generate_items.py <repo_root> [max_items]   (appends + prints GENERATED=n)
"""
import os, re, sys

SKIP_DIRS = {'.git', 'node_modules', 'venv', '.venv', 'dist', 'build', 'htmlcov',
             '__pycache__', '.pytest_cache', 'coverage', '.next', '.nuxt', 'ios',
             'android', 'Pods', '.dart_tool'}

def walk(root, exts):
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            if os.path.splitext(fn)[1] in exts:
                yield os.path.join(dp, fn)

def read(p):
    try:
        return open(p, encoding='utf-8', errors='ignore').read().splitlines()
    except Exception:
        return None

def scan(root):
    """Return {relpath: (priority, text)} — one entry per file (first hit wins)."""
    found = {}
    def add(rp, pri, text):
        if rp not in found:
            found[rp] = (pri, text)

    py = list(walk(root, {'.py'}))
    web = list(walk(root, {'.vue', '.html'}))

    # 1) bare except: (HIGH)
    for p in py:
        rp = os.path.relpath(p, root)
        if 'test' in rp.lower():
            continue
        lines = read(p)
        if lines is None:
            continue
        for i, ln in enumerate(lines):
            if re.match(r'^\s*except\s*:\s*(#.*)?$', ln):
                add(rp, 'HIGH', "`%s` (line %d): change the bare `except:` to `except Exception:` so it no longer swallows KeyboardInterrupt/SystemExit. Keep the body unchanged. One file." % (rp, i + 1))
                break

    # 2) target="_blank" without rel (HIGH, security)
    for p in web:
        rp = os.path.relpath(p, root)
        if rp in found:
            continue
        lines = read(p)
        if lines is None:
            continue
        for i, ln in enumerate(lines):
            if 'target="_blank"' not in ln:
                continue
            # 2026-09-10 fix: Vue/HTML tags are routinely formatted one-attribute-per-line
            # (Prettier's default style), so `rel="noopener noreferrer"` often sits on a
            # DIFFERENT line than `target="_blank"` within the same tag - checking only
            # `ln` produced false positives that regenerated the same non-issue every time
            # the low-water-mark fired (confirmed live: one file had this "fixed" 10
            # separate times, each one a no-op against code that was already correct).
            # Scan out to the tag's actual boundaries (nearest enclosing `<` .. `>`)
            # instead of just the one line.
            start = i
            while start > 0 and '<' not in lines[start]:
                start -= 1
            end = i
            while end < len(lines) - 1 and '>' not in lines[end]:
                end += 1
            tag_text = '\n'.join(lines[start:end + 1])
            if 'rel=' not in tag_text:
                add(rp, 'HIGH', "`%s` (line %d): the `target=\"_blank\"` link has no `rel`, a reverse-tabnabbing risk. Add `rel=\"noopener\"` to that tag. Change only that line. One file." % (rp, i + 1))
            break

    # 3) def __repr__(self): without -> str (LOW)
    for p in py:
        rp = os.path.relpath(p, root)
        if rp in found or 'test' in rp.lower():
            continue
        lines = read(p)
        if lines is None:
            continue
        for i, ln in enumerate(lines):
            if re.match(r'^\s*def __repr__\(self\):\s*$', ln):
                add(rp, 'LOW', "`%s` (line %d): add a return type hint to `__repr__` — change `def __repr__(self):` to `def __repr__(self) -> str:`. One file." % (rp, i + 1))
                break

    # 4) single-line def __init__(self...): without -> (LOW)
    for p in py:
        rp = os.path.relpath(p, root)
        if rp in found or 'test' in rp.lower():
            continue
        lines = read(p)
        if lines is None:
            continue
        for i, ln in enumerate(lines):
            if re.match(r'^\s*def __init__\(self[^)]*\)\s*:\s*$', ln) and '->' not in ln:
                sig = ln.strip().rstrip(':')
                add(rp, 'LOW', "`%s` (line %d): add a return type hint to the constructor — change `%s:` to `%s -> None:`. Change only that line. One file." % (rp, i + 1, sig, sig))
                break

    return found

def main():
    if len(sys.argv) < 2:
        print("usage: ovn_generate_items.py <repo_root> [max_items]"); sys.exit(2)
    root = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 15
    prog = os.path.join(root, 'OVERNIGHT_PROGRESS.md')
    existing = open(prog, encoding='utf-8').read() if os.path.exists(prog) else "# Overnight Progress\n\n## Next Steps\n"
    found = scan(root)
    # Only skip files that currently have an ACTIVE (unchecked) item. A file whose
    # prior items are all done (- [x]) is eligible for a NEW pattern — otherwise the
    # scanner goes permanently dry once every file has been touched once, and the
    # fleet no-ops forever even though fixable patterns remain (2026-08-31 fix).
    active = "\n".join(l for l in existing.splitlines() if l.lstrip().startswith("- [ ]"))
    order = {'HIGH': 0, 'MED': 1, 'LOW': 2}
    new = [(rp, pri, txt) for rp, (pri, txt) in found.items() if ('`%s`' % rp) not in active]
    new.sort(key=lambda x: order.get(x[1], 3))
    new = new[:limit]
    if not new:
        print("GENERATED=0"); return
    block = "\n### Auto-generated (deterministic scanner) — safe mechanical fixes\n"
    for rp, pri, txt in new:
        # 2026-09-10 fix: every pattern here is single-line/single-file/zero-judgment by
        # construction (see module docstring) — unambiguously the simplest tier. Untagged
        # items were showing up as tier="?" in outcome stats/ntfy digests, masking real
        # tier-capability signal (this was ~66% of all outcomes fleet-wide).
        block += "- [ ] [T1] [%s] %s\n" % (pri, txt)
    if "## Needs human" in existing:
        out = existing.replace("\n## Needs human", "\n" + block + "\n## Needs human", 1)
    else:
        out = existing.rstrip() + "\n" + block
    open(prog, 'w', encoding='utf-8').write(out)
    print("GENERATED=%d" % len(new))

if __name__ == '__main__':
    main()
