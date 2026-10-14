#!/usr/bin/env python3
"""Static check (n5, 2026-10-14): in scripts/test/*.sh a `( cd X && first; git add -A; git commit ...)` subshell only protects its FIRST statement
from a failed cd - everything after the first `;`/newline runs in the CALLER's cwd.  When that cwd is the live overnight-queue repo, the bare
git add/commit sweeps logs/ and state/ into live history (see 934906a6e).  Prints `file:line:statement` for every such subshell and exits 1.
Safe forms: `( cd X || exit 1; ...)`, `( cd X && ...chain... )`, `git -C X ...`.
Usage: lib_subshell_cd_lint.py [--fix] file...   (--fix rewrites the flagged `( cd X &&` to `( cd X || exit 1;`)"""
import re, sys

GIT = re.compile(r'(^|[;&|(]\s*|\s)git\s+(?!-C\b)(add|commit|reset|checkout|rm|clean|stash|merge|rebase|push|cherry-pick|update-ref|restore|switch|branch|tag)\b')
CD = re.compile(r'\(\s*cd\s+("[^"]*"|\'[^\']*\'|[^\s&|;)]+)\s*&&')


def logical_lines(text):
    """(lineno, text) with heredoc bodies blanked and backslash / trailing &&,||,| continuations joined"""
    raw = text.split('\n')
    out, i, end = [], 0, None
    blank = []
    for l in raw:
        if end is not None:
            if l.strip() == end:
                end = None
            blank.append('')
            continue
        blank.append(l)
        m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", l)
        if m:
            end = m.group(1)
    cur, start = '', None
    for n, l in enumerate(blank, 1):
        if start is None:
            start = n
        s = re.sub(r'\s#.*$', '', l) if re.match(r'^\s*#', l) is None else ''
        if s.rstrip().endswith('\\'):
            cur += s.rstrip()[:-1] + ' '
            continue
        cur += s
        if re.search(r'(&&|\|\||\|)\s*$', cur):
            cur += ' '
            continue
        out.append((start, cur))
        cur, start = '', None
    return out


def scan(path):
    text = open(path, errors='replace').read()
    L = logical_lines(text)
    hits = []
    for idx, (ln, l) in enumerate(L):
        for m in CD.finditer(l):
            if l[:m.start()].rstrip().endswith('$'):
                continue  # $( cd ... ) command substitution used for a path
            txt, depth, j, started = '', 0, idx, False
            while j < len(L):
                seg = L[j][1][m.start():] if j == idx else L[j][1]
                for ch in seg:
                    if ch == '(':
                        depth += 1; started = True
                    elif ch == ')':
                        depth -= 1
                txt += seg + '\n'
                if started and depth <= 0:
                    break
                j += 1
            body = txt[txt.index('&&') + 2:]
            stmts = re.split(r';|\n', body)
            for s in stmts[1:]:
                if GIT.search(' ' + s):
                    hits.append((ln, m.group(0), s.strip()[:80]))
                    break
    return hits


def main(argv):
    fix = '--fix' in argv
    files = [a for a in argv if a != '--fix']
    bad = 0
    for f in files:
        hits = scan(f)
        for ln, tok, stmt in hits:
            print('%s:%d:%s' % (f, ln, stmt))
            bad += 1
        if fix and hits:
            toks = {t for _, t, _ in hits}
            src = open(f, errors='replace').read()
            for t in toks:
                src = src.replace(t, t[:-2].rstrip() + ' || exit 1;')
            open(f, 'w').write(src)
    return 1 if bad and not fix else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
