#!/usr/bin/env python3
"""VERIFY malformation lint (2026-10-15, fixer A2; reworked by fixer P2 after review).

Four overnight VERIFY clauses were impossible as written, not model failures, and were re-picked
every cycle (GPU burn): wrong cwd (npx tsc with no local compiler, `from app.x` run from the repo
root), a pytest node id that does not exist (exit 4), a grep/open target that does not exist, and a
remove-premise that contradicts live callers. This module detects those shapes deterministically.

Everything here is pure: it reads files under a repo root and returns findings. Nothing is run and
nothing blocks. The only write is shadow_log_verify(), which appends JSON lines to a log file.

Codes emitted by lint_verify():
  pytest-path-missing          pytest path::node names a file that does not exist in the effective cwd
  pytest-node-missing          the file exists but no def/class with the node name is in it
  npx-tsc-no-local-compiler    `npx tsc` run where <cwd>/node_modules/.bin/tsc does not exist
  import-root-missing          `from app.x import ...` (app/src/tests) where <cwd>/<root> is not a dir
  target-path-missing          a literal file path in the VERIFY does not exist, and the item does not say create/add
  whole-project-tsc-unbaselined  `tsc --noEmit` with no file args and no baseline supplied
  tsc-baseline-red             whole-project tsc with a baseline that is already red

Wiring status (documented so nobody assumes more is live than is):
  lint_verify          WIRED, SHADOW ONLY: queue_refill.py calls shadow_log_verify() on every pulled
                       item and appends to state/verify_lint_shadow.log. Findings never change what
                       is queued. Kill switch OVN_VERIFY_LINT=off.
  remove_premise_findings  NOT WIRED into any production path. Reachable only through the
                       `remove-premise` CLI action for manual use.
  verify_park_decision     NOT WIRED. No queue code reads it; parking behaviour is unchanged. Kept as
                       a documented helper for a future decision.
  classify_result      WIRED into ovn_classify_fail.sh with the same signatures, but the bash
                       classifier only emits verify-malformed when OVN_CLASSIFY_MALFORMED=on.
                       Default is off (old behaviour). OVN_CLASSIFY_MALFORMED=shadow only logs.

classify_result() maps a VERIFY run (rc plus output) to the tag verify-malformed, or None.
"""
import json
import os
import re
import sys

MALFORMED_TAG = "verify-malformed"

# The pytest verify-clause shape: "ERROR: not found: <path>::<node> (no match in any of [...])". A bare
# "ERROR: not found: #login-button" (a Playwright/selector failure inside a real test run) does not match.
PYTEST_NODE_NOT_FOUND = re.compile(r"ERROR: not found: \S+::\S+ \(no match in any of")
_OUTPUT_SIGNS = [
    re.compile(r"To get access to the TypeScript compiler"),
    PYTEST_NODE_NOT_FOUND,
    re.compile(r"No module named .?(app|src)[\x27\"]?\s*$", re.M),
]
_SRC_EXT = (".py", ".ts", ".tsx", ".vue", ".js", ".gd", ".sh")
_SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", "build", "dist"}


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


def cwd_before(verify, pos):
    """Relative directory ('' = repo root) a VERIFY command runs in at offset pos, following every `cd D` before it."""
    cur = ""
    for m in re.finditer(r"(?:^|[\s;&|(])cd\s+([^\s;&|()]+)", verify[:pos]):
        d = m.group(1).strip("\x27\"")
        cur = d if os.path.isabs(d) else os.path.normpath(os.path.join(cur, d))
        if cur == ".":
            cur = ""
    return cur


def classify_result(rc, output="", cmd=""):
    """verify-malformed when a VERIFY run failed for a reason that no model edit can fix; None otherwise."""
    output = output or ""
    if rc == 4 and ("pytest" in cmd or PYTEST_NODE_NOT_FOUND.search(output)):
        return MALFORMED_TAG
    for sign in _OUTPUT_SIGNS:
        if sign.search(output):
            return MALFORMED_TAG
    return None


def _dedupe_seen(log_path, key, today):
    """Z5: True when `key` was already journaled today (sidecar <log>.seen = {"day": D, "keys": [...]}); records it otherwise. Fail-open (False)."""
    side = log_path + ".seen"
    try:
        try:
            with open(side, encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            d = {}
        if d.get("day") != today:
            d = {"day": today, "keys": []}
        if key in d["keys"]:
            return True
        d["keys"].append(key)
        tmp = side + ".%d.tmp" % os.getpid()
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(d, fh)
        os.replace(tmp, side)
    except Exception:
        return False
    return False


def shadow_log_verify(verify, repo_root, item_text, log_path, mode="shadow", sibling_texts=None, now=None):
    """SHADOW ONLY. Lint one pulled item's VERIFY and append one JSON line to log_path. Returns the findings,
    or None when mode is off or nothing could be written. Never raises: a lint bug must not stop a refill."""
    if (mode or "").lower() == "off" or not verify:
        return None
    try:
        findings = lint_verify(verify, repo_root, item_text, None, sibling_texts)
        rec = {"verify": verify[:300], "findings": findings}
        d = os.path.dirname(os.path.abspath(log_path))
        os.makedirs(d, exist_ok=True)
        import hashlib
        import time as _t
        today = _t.strftime("%Y-%m-%d", _t.gmtime(now if now is not None else _t.time()))
        # Z5: ONE row per (item, verify, findings) per UTC day - queue_refill re-lints every pulled item on every pass (1620 identical rows/25h)
        k = hashlib.md5(((item_text or "") + "\0" + verify + "\0" + json.dumps(findings, sort_keys=True)).encode("utf-8", "replace")).hexdigest()
        if _dedupe_seen(log_path, k, today):
            return findings
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, sort_keys=True) + "\n")
        return findings
    except Exception:  # shadow lint must never break the refill path
        return None


def verify_park_decision(tag, prior_malformed_attempts):
    """'park' after the first verify-malformed attempt (no retry burns GPU on it); 'retry' otherwise."""
    if tag == MALFORMED_TAG and int(prior_malformed_attempts) >= 1:
        return "park"
    return "retry"


_CREATE_VERB_RE = re.compile(r"\b(add|adds|create|creates|new|write|writes|introduce|introduces|extend|extends|expand)\b", re.I)
_TESTISH_PATH_RE = re.compile(r"(^|/)(tests?|__tests__|spec|specs)/|(^|/)(test_[^/]*|[^/]*_test)\.py$")


def item_creates_path(item_text, rel_path, cwd=""):
    """Z5 (Q1 noise): True when the item text says it creates/adds `rel_path`: a creation verb in the item AND either the path (or its basename) is named in the text, or the item head
    ('<file> - Create a test for ...', i.e. a test-creation item) targets a test-looking path. Used for the item itself and for its queue siblings."""
    t = item_text or ""
    if not _CREATE_VERB_RE.search(t):
        return False
    full = os.path.normpath(os.path.join(cwd or "", rel_path))
    for cand in {rel_path, full, os.path.basename(rel_path)}:
        if cand and re.search(r"(?<![\w./-])" + re.escape(cand) + r"(?![\w])", t.replace("\\", "/")):
            return True
    head = re.split(r"\bVERIFY\b", t, 1)[0]
    # a test-creation item: the head names a test verb/noun and the missing path itself is a test file
    return bool(_TESTISH_PATH_RE.search(rel_path)) and re.search(r"\b(tests?|specs?|unit test|regression test)\b", head, re.I) is not None and \
        re.match(r"^\W*(?:\[\w+\]\s*)*(?:[\w./-]+\s*[-\u2014\u2013:]+\s*)?(?:\[\w+\]\s*)*(create|add|write|extend|expand|new|introduce)\b", head.strip(" -[]x"), re.I) is not None


def lint_verify(verify, repo_root, item_text="", tsc_baseline_green=None, sibling_texts=None):
    """Return a list of {code, detail} dicts for a VERIFY command text. Empty list means no static defect found.
    Z5: pytest-path-missing is silent when the item (or one of `sibling_texts`, the other queued items) creates that test path (the 2026-11-07/08 log had 1620 such false rows in 25h)."""
    findings = []
    verify = verify or ""
    repo_root = os.path.abspath(repo_root)
    item_text = item_text or ""
    creates = re.search(r"\b(add|create|new|write|introduce)\b", item_text, re.I) is not None
    pytest_spans = []

    for m in re.finditer(r"(?<![\w/.-])([\w.-]+(?:/[\w.-]+)*\.py)::([\w:]+)", verify):
        pytest_spans.append((m.start(), m.end()))
        cwd = cwd_before(verify, m.start())
        path = os.path.join(repo_root, cwd, m.group(1))
        if not os.path.isfile(path):
            if item_creates_path(item_text, m.group(1), cwd) or any(item_creates_path(t, m.group(1), cwd) for t in (sibling_texts or [])):
                continue
            findings.append({"code": "pytest-path-missing", "detail": "%s (cwd %s)" % (m.group(1), cwd or ".")})
            continue
        name = m.group(2).split("::")[-1]
        text = _read(path) or ""
        if not re.search(r"^\s*(async\s+)?(def|class)\s+" + re.escape(name) + r"\b", text, re.M):
            findings.append({"code": "pytest-node-missing", "detail": "%s::%s" % (m.group(1), name)})

    for m in re.finditer(r"\bnpx\s+tsc\b", verify):
        cwd = cwd_before(verify, m.start())
        if not os.path.isfile(os.path.join(repo_root, cwd, "node_modules", ".bin", "tsc")):
            findings.append({"code": "npx-tsc-no-local-compiler", "detail": "cwd %s" % (cwd or ".")})

    for m in re.finditer(r"\btsc\b[^&|;]*--noEmit", verify):
        tail = verify[m.end():]
        if re.search(r"\.(ts|tsx|vue)\b", tail[:200]):
            continue  # scoped to named files
        if tsc_baseline_green is None:
            findings.append({"code": "whole-project-tsc-unbaselined", "detail": "no tsc baseline supplied"})
        elif not tsc_baseline_green:
            findings.append({"code": "tsc-baseline-red", "detail": "whole-project tsc already red before the change"})

    for m in re.finditer(r"\bfrom\s+(app|src|tests)\.[\w.]+\s+import\b", verify):
        root = m.group(1)
        cwd = cwd_before(verify, m.start())
        if not os.path.isdir(os.path.join(repo_root, cwd, root)):
            findings.append({"code": "import-root-missing", "detail": "%s/ not under cwd %s" % (root, cwd or ".")})

    seen_targets = set()
    for m in re.finditer(r"(?<![\w/.-])((?:[\w.-]+/)+[\w.-]+\.(?:%s))(?![\w/])(?!::)" % "|".join(e[1:] for e in _SRC_EXT + (".md", ".json")), verify):
        if any(s <= m.start() < e for s, e in pytest_spans):
            continue
        target = m.group(1)
        if target in seen_targets:
            continue
        seen_targets.add(target)
        cwd = cwd_before(verify, m.start())
        if creates:
            continue  # the item itself creates this file
        if not os.path.exists(os.path.join(repo_root, cwd, target)):
            findings.append({"code": "target-path-missing", "detail": "%s (cwd %s)" % (target, cwd or ".")})
    return findings


def remove_premise_findings(symbols, search_root):
    """Symbols the item says to remove that still have non-test call sites under search_root."""
    out = []
    for sym in symbols:
        pat = re.compile(r"\b" + re.escape(sym) + r"\b")
        defn = re.compile(r"^\s*(async\s+)?(def|class|func|function)\s+" + re.escape(sym) + r"\b")
        callers = []
        for dirpath, dirnames, filenames in os.walk(search_root):
            dirnames[:] = [d for d in dirnames if d not in _SKIP_DIRS]
            for fn in filenames:
                if not fn.endswith(_SRC_EXT):
                    continue
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, search_root)
                if "/tests/" in "/" + rel or fn.startswith("test_") or "__tests__" in rel or ".test." in fn or ".spec." in fn:
                    continue
                text = _read(full) or ""
                for line in text.splitlines():
                    if pat.search(line) and not defn.search(line):
                        callers.append(rel)
                        break
        if callers:
            out.append({"code": "remove-premise-live-callers", "detail": "%s called from %s" % (sym, ", ".join(sorted(set(callers))[:5]))})
    return out


def _main(argv):
    import argparse

    ap = argparse.ArgumentParser(description="VERIFY malformation lint (shadow by default)")
    sub = ap.add_subparsers(dest="action", required=True)
    lp = sub.add_parser("lint")
    lp.add_argument("--repo", required=True)
    lp.add_argument("--verify", required=True)
    lp.add_argument("--item", default="")
    lp.add_argument("--tsc-green", choices=["0", "1"], default=None)
    lp.add_argument("--enforce", action="store_true")
    cp = sub.add_parser("classify")
    cp.add_argument("--rc", type=int, required=True)
    cp.add_argument("--command", default="")
    cp.add_argument("--output-file", default="")
    rp = sub.add_parser("remove-premise")
    rp.add_argument("--root", required=True)
    rp.add_argument("--symbols", required=True)
    a = ap.parse_args(argv)
    if a.action == "lint":
        tsc = None if a.tsc_green is None else a.tsc_green == "1"
        f = lint_verify(a.verify, a.repo, a.item, tsc)
        print(json.dumps({"mode": "enforce" if a.enforce else "shadow", "findings": f}))
        return 1 if (a.enforce and f) else 0
    if a.action == "classify":
        out = _read(a.output_file) if a.output_file else ""
        tag = classify_result(a.rc, out or "", a.command)
        print(tag or "none")
        return 0
    f = remove_premise_findings([s for s in a.symbols.split(",") if s], a.root)
    print(json.dumps({"findings": f}))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
