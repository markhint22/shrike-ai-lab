#!/usr/bin/env python3
"""Z8a (2026-11-10): every test file NAMED in run_all.sh must exist next to it, or be registered through `run_if_present` (a clear SKIP line when the file is absent).

Incident: the 2026-11-09 box deploy tar omitted the Mac-only test_z6_notify_guard.sh; run_all.sh named it unconditionally, so `bash test_z6_notify_guard.sh` -> 'No such file' -> rc=1 and the
box suite was red for two cron runs. This lint is the guard; it also (optionally) checks a deploy tar listing.

usage: lint_run_all_registration.py RUN_ALL TEST_DIR [--tar-list FILE]
  exit 0 = clean; exit 1 = problems (printed one per line). --tar-list FILE: a `tar -tf` listing; every registered file that is neither guarded by run_if_present nor inside an
  `if [[ "$(uname)" == "Darwin" ]]` block must be in the listing (the deploy-tar completeness check).
"""
import os, re, sys

TOK = re.compile(r'(?<![A-Za-z0-9_])(bash|python3|run_or_notrun|run_if_present)\s+"?([A-Za-z0-9_.-]*test_[A-Za-z0-9_]+\.(?:sh|py))\b')
DARWIN = re.compile(r'^\s*if\s+\[\[?\s+"?\$\(uname\)"?\s*==\s*"?Darwin"?')


def registrations(path):
    """-> list of (lineno, interpreter, name, in_darwin_block)"""
    out, in_darwin = [], False
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        s = line.strip()
        if s.startswith("#"):
            continue
        if DARWIN.match(line):
            in_darwin = True
            continue
        if in_darwin and re.match(r'^(else|fi)\b', line):
            in_darwin = False
            continue
        for m in TOK.finditer(line):
            out.append((n, m.group(1), m.group(2), in_darwin))
    return out


def lint(run_all, test_dir, tar_list=None):
    problems = []
    tarnames = None
    if tar_list:
        tarnames = {os.path.basename(l.strip()) for l in open(tar_list, encoding="utf-8", errors="replace") if l.strip()}
    for n, interp, name, in_darwin in registrations(run_all):
        exists = os.path.isfile(os.path.join(test_dir, name))
        if not exists and interp != "run_if_present":
            problems.append(f"{run_all}:{n}: {name} is registered unconditionally but does not exist in {test_dir} (register Mac-only/optional files with `run_if_present {name}`)")
        if tarnames is not None and interp != "run_if_present" and not in_darwin and name not in tarnames:
            problems.append(f"{run_all}:{n}: {name} is registered unconditionally but is NOT in the deploy tar (add it to the tar, or register it with `run_if_present`)")
    return problems


if __name__ == "__main__":
    a = sys.argv[1:]
    tl = None
    if "--tar-list" in a:
        i = a.index("--tar-list"); tl = a[i + 1]; del a[i:i + 2]
    if len(a) != 2:
        print(__doc__); sys.exit(2)
    ps = lint(a[0], a[1], tl)
    for p in ps:
        print(p)
    sys.exit(1 if ps else 0)
