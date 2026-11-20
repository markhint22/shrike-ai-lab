#!/usr/bin/env python3
"""scripts/overnight-queue/ovn_item_hazards.py - item HAZARD guard (package q-verify-shapes, 2026-11-18). SHADOW by default.

DELETE_ALL_TESTS: an item whose text tells the worker to REPLACE the entire test file / delete ALL existing tests would delete real coverage. The recovery decomposer produced
'Replace the entire file content with only the `_mk` fixture and a single trivial test ... removing all other imports and tests' for billwatch test_auth_refresh_success.py (163 lines of
real refresh tests), and every other guard (placeholder detector, tone lint) would have judged the resulting one-test file green.

Detection (item text before VERIFY, bracket tags like [T1] / [AUTO-SKIP ...] / [CLAUDE] repo/ ignored; a TEST path must be named in that text):
  REPLACE_ALL   replace/rewrite/overwrite/empty/wipe the entire|whole|full file|contents|suite, or 'replace the file content with ...'
  REMOVE_ALL    remove/delete/drop/discard/clear/replace ALL|every [existing|other|real|...] tests|test cases|assertions, UNLESS the sentence names the scope (a `symbol`, 'that call X', 'referencing Y') or says the code is dead/removed
  DELETE_FILE   delete the entire|whole [test] file, UNLESS the item says why that is safe (the subject is removed/orphaned/dead/obsolete/duplicate/superseded/has zero callers ...)

Mode: OVN_ITEM_HAZARD = off | shadow (default; also any unknown value) | enforce.
  shadow : append one row per NEW (repo, line hash) to state/item_hazards.log:  '<ts> <repo> would-refuse delete-all-tests kind=<K> parked=<0|1> line=<hash> :: <item head>'
  enforce: open, NOT already parked lines are retired like dead-path ones: moved to a '### Retired (hazard ...)' section as '- [x] (retired-hazard-delete-all-tests) <line>'. Parked
           (AUTO-SKIP / [CLAUDE] / HUMAN-ONLY) lines are only logged: they are routed to a human/Claude anyway and must stay visible there.

CLI
  ovn_item_hazards.py scan FILE [--repo NAME] [--state DIR]   hook: honours the mode, prints 'retired N hazard item(s)' in enforce when it retired any; never raises (rc 0)
  ovn_item_hazards.py check '<item line>'                      one item, JSON
  ovn_item_hazards.py replay FILE... [--all]                   read-only corpus replay (no writes): rows per kind; --all includes closed [x] lines
"""
import hashlib
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RULE = "delete-all-tests"
_TESTY = re.compile(r"(?:^|/)(?:tests?|__tests__|spec|specs|e2e)/|(?:^|/)test_[^/\s]*$|[._]tests?\.[A-Za-z]+$|[._]spec\.[A-Za-z]+$|_test\.py$|(?:^|/)conftest\.py$")
_PATH = re.compile(r"[\w@./-]+\.[A-Za-z]{1,5}\b")
_REPLACE_ALL = re.compile(r"\b(?:replace|rewrite|overwrite|empty|wipe)\w*\b[^.;]{0,40}?\b(?:entire|whole|full|complete)\s+(?:test\s+)?(?:file|contents?|suite|module)\b|\breplace\s+the\s+file\s+contents?\s+with\b", re.I)
_REMOVE_ALL = re.compile(r"\b(?:remov\w+|delet\w+|drop\w*|discard\w*|clear\w*|replac\w+)\b[^.;]{0,30}?\b(?:all|every)\b[^.;]{0,25}?\b(?:test\s*cases?|tests?|assertions?)\b", re.I)
_SCOPED_ANY = re.compile(r"\b(?:that|which|referenc\w+|call\w*|instantiat\w+|related to|specifically|target\w*|cover\w*|testing|import\w*|depend\w+|touch\w+|using|for the)\b", re.I)
_DEAD = re.compile(r"\b(?:dead|orphan\w*|obsolete|no longer|zero callers?|no callers?|deleted|already (?:been )?removed|removed (?:code|function|class|module|helper)s?|migrated)\b", re.I)
_DELETE_FILE = re.compile(r"\bdelet\w+\s+(?:the\s+)?(?:entire|whole)\s+(?:test\s+)?file\b", re.I)
_JUSTIFIED = re.compile(r"\b(?:remov\w*|orphan\w*|dead|no longer|obsolete|deleted|zero callers?|no callers?|superseded|duplicat\w*|stale|unused|no production|retired|replaced by|moved to|merged into|already (?:covered|exists))\b", re.I)


def mode():
    m = (os.environ.get("OVN_ITEM_HAZARD", "shadow") or "shadow").strip().lower()
    return m if m in ("off", "shadow", "enforce") else "shadow"


def _head(line):
    h = re.sub(r"VERIFY:.*$", "", line or "", flags=re.S)
    h = re.sub(r"^- \[[ xX]\]\s*", "", h)
    return re.sub(r"\[[^\]]*\]", " ", h)


def _h(s):
    return hashlib.sha1(s.encode("utf-8", "replace")).hexdigest()[:12]


def detect(line):
    """-> (kind, why) or None. Pure; never raises."""
    try:
        head = _head(line)
        if len(head) > 4000:
            head = head[:4000]
        paths = _PATH.findall(head)
        if not any(_TESTY.search(p) for p in paths):
            return None
        m = _REPLACE_ALL.search(head)
        if m:
            return "REPLACE_ALL", m.group(0)[:80]
        for m in _REMOVE_ALL.finditer(head):
            rest = re.split(r"(?<=[a-z\)])\.\s", head[m.end():m.end() + 200], 1)[0]
            if "`" in rest or _SCOPED_ANY.search(rest) or _DEAD.search(head):
                continue                    # scoped to named symbols / explained by removed code: ordinary orphan-test cleanup
            return "REMOVE_ALL", m.group(0)[:80]
        m = _DELETE_FILE.search(head)
        if m and not _JUSTIFIED.search(head):
            return "DELETE_FILE", m.group(0)[:80]
    except Exception:
        return None
    return None


PARKED = re.compile(r"AUTO-SKIP|HUMAN-ONLY|human/|HARD FILE BAN|\[CLAUDE\]|BLOCKED")


def _state(state_dir):
    return state_dir or os.environ.get("OVN_STATE_DIR") or os.path.join(HERE, "state")


def scan(path, repo=None, state_dir=None):
    """hook body. Returns the number of retired lines (enforce) or 0. Never raises."""
    md = mode()
    if md == "off" or not os.path.isfile(path):
        return 0
    try:
        lines = open(path, errors="replace").read().split("\n")
        hits = []
        for i, ln in enumerate(lines):
            if ln.startswith("- [ ] ") and "(retired-" not in ln:
                d = detect(ln)
                if d:
                    hits.append((i, d))
        if not hits:
            return 0
        sd = _state(state_dir)
        os.makedirs(sd, exist_ok=True)
        repo = repo or os.path.basename(os.path.dirname(os.path.abspath(path)))
        seen_p = os.path.join(sd, "item_hazards.seen")
        try:
            seen = set(open(seen_p).read().split("\n"))
        except OSError:
            seen = set()
        log = os.environ.get("OVN_ITEM_HAZARD_LOG") or os.path.join(sd, "item_hazards.log")
        for i, (kind, why) in hits:
            key = "%s %s" % (repo, _h(lines[i]))
            if key in seen:
                continue
            seen.add(key)
            with open(seen_p, "a") as f:
                f.write(key + "\n")
            with open(log, "a") as f:
                f.write("%s %s would-refuse %s kind=%s parked=%d mode=%s line=%s :: %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()), repo, RULE, kind, 1 if PARKED.search(lines[i]) else 0, md, _h(lines[i]), _head(lines[i]).strip()[:200]))
        if md != "enforce":
            return 0
        retire = [i for i, _ in hits if not PARKED.search(lines[i])]
        if not retire:
            return 0
        rs = set(retire)
        out = [l for j, l in enumerate(lines) if j not in rs]
        while out and out[-1] == "":
            out.pop()
        out += ["", "### Retired (hazard: item would delete all existing tests / replace the entire test file; refused by ovn_item_hazards) auto-2026-11-18"]
        out += ["- [x] (retired-hazard-%s) %s" % (RULE, lines[j][len("- [ ] "):]) for j in retire]
        tmp = "%s.hz.%d" % (path, os.getpid())
        with open(tmp, "w") as f:
            f.write("\n".join(out) + "\n")
        os.replace(tmp, path)
        return len(retire)
    except Exception:
        return 0


def main(argv):
    a = argv[1:]
    if not a:
        print(__doc__)
        return 2

    def opt(name, default=None):
        if name in a:
            i = a.index(name)
            v = a[i + 1] if i + 1 < len(a) else default
            del a[i:i + 2]
            return v
        return default
    cmd = a.pop(0)
    repo, state = opt("--repo"), opt("--state")
    if cmd == "check":
        d = detect(a[0])
        print(json.dumps({"hazard": bool(d), "kind": d[0] if d else "", "why": d[1] if d else ""}))
        return 0
    if cmd == "scan":
        n = scan(a[0], repo, state)
        if n:
            print("  retired %d hazard item(s) (%s)" % (n, RULE))
        return 0
    if cmd == "replay":
        allf = "--all" in a
        a = [x for x in a if x != "--all"]
        by = {}
        n_lines = 0
        for f in a:
            rn = os.path.basename(os.path.dirname(os.path.abspath(f)))
            for ln in open(f, errors="replace"):
                if not (ln.startswith("- [ ] ") or (allf and ln.startswith("- [x] "))):
                    continue
                n_lines += 1
                d = detect(ln)
                if d:
                    by.setdefault(d[0], []).append((rn, "open" if ln.startswith("- [ ]") else "closed", _h(_head(ln)), _head(ln).strip()[:150]))
        print(json.dumps({"lines": n_lines, "hits": {k: len(v) for k, v in by.items()}}))
        for k, v in by.items():
            for x in v:
                print(k, *x, sep=" | ")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
