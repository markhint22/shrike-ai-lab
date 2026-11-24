#!/usr/bin/env python3
"""scripts/overnight-queue/ovn_test_first_source.py - TEST-FIRST-MISSING-SOURCE guard (package q-oracle-park, 2026-11-24). SHADOW ONLY.

Evidence: iptv_apps 'add the now-playing text loader' (hash 59de97) burned 7 cycles (5 ts-regression + 1 build-break reverts, TS2307 Cannot find module 'src/api/nowPlayingTexts.ts') before
landing on attempt 7. The feature group's T1 steps (create src/api/nowPlayingTexts.ts) had been retired as dead-path, so the test steps (T2) imported a module that no open step creates.

A TEST step (an open queue line whose lead path is a test file) is flagged when a source module it needs
  imports   the test file already exists and imports it (python `from app.x import` / relative; ts/js relative './x' '../x' and the '@/' alias under the nearest src/), or
  item-path the item text (outside VERIFY) names a non-test source path, or
  sibling   the conventional sibling of the test (`d/__tests__/N.test.ts` -> `d/N.ts`, `tests/test_N.py` -> `**/N.py`) is the lead path of ANOTHER line of the same [feat:] group
            (evidence that the group planned that file)
does not exist in the tree AND no earlier OPEN (unparked) line of the same [feat:] group creates it (lead path == the missing file). Nothing is ever changed: one row per NEW
(repo, line, missing) goes to state/test_first_source_shadow.log (OVN_TFMS_LOG overrides) and the literal text TEST-FIRST-MISSING-SOURCE is printed.

Mode: OVN_TEST_FIRST_SOURCE = off | shadow (default; there is no enforce: any other value is shadow).
Fast and safe: reads only the item's test file (<= 200 KB) and `git ls-files` (timeout 10 s); a wall-clock budget (OVN_TFMS_BUDGET_S, default 5) stops the scan; every error is swallowed (rc 0).

CLI
  ovn_test_first_source.py scan FILE --root DIR [--repo NAME] [--state DIR]   hook: honours the mode; prints one TEST-FIRST-MISSING-SOURCE line per NEW row; never raises (rc 0)
  ovn_test_first_source.py check '<item line>' --root DIR [--group-file FILE]  one item, JSON
"""
import collections
import hashlib
import json
import os
import re
import subprocess
import sys
import time

TESTY = re.compile(r"(?:^|/)(?:tests?|__tests__|spec|specs|e2e)/|(?:^|/)test_[^/\s]*$|[._]tests?\.[A-Za-z]+$|[._]spec\.[A-Za-z]+$|_test\.py$|(?:^|/)conftest\.py$")
PATH = re.compile(r"[\w@./-]+\.(?:py|ts|tsx|js|jsx|vue|mjs|gd|kt|swift)\b")
FEAT = re.compile(r"\[feat:([^\]\s]+)\]")
PARKED = re.compile(r"AUTO-SKIP|HUMAN-ONLY|BLOCKED|\[CLAUDE\]|\(retired")
TS_EXT = ("", ".ts", ".tsx", ".js", ".jsx", ".vue", ".mjs", ".json")
MAX_TEST_BYTES = 200000
RULE = "TEST-FIRST-MISSING-SOURCE"


def mode():
    m = (os.environ.get("OVN_TEST_FIRST_SOURCE", "shadow") or "shadow").strip().lower()
    return m if m in ("off", "shadow") else "shadow"


def _h(s):
    return hashlib.sha1(s.encode("utf-8", "replace")).hexdigest()[:12]


def _head(line):
    h = re.sub(r"VERIFY:.*$", "", line or "", flags=re.S)
    h = re.sub(r"^- \[[ xX]\]\s*", "", h)
    return re.sub(r"\[[^\]]*\]", " ", h)


def lead_path(line):
    m = PATH.search(_head(line))
    return m.group(0).lstrip("./") if m else ""


def _norm(p):
    return os.path.normpath(p).replace("\\", "/")


def _tracked(root):
    try:
        out = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, timeout=10).stdout
        return set(x for x in out.split("\n") if x)
    except Exception:
        return set()


def _exists(root, rel, tracked):
    return rel in tracked or os.path.isfile(os.path.join(root, rel))


def _ts_found(root, base, tracked):
    for ext in TS_EXT:
        if _exists(root, base + ext, tracked):
            return True
    for idx in ("index.ts", "index.tsx", "index.js", "index.jsx", "index.vue"):
        if _exists(root, base + "/" + idx, tracked):
            return True
    return False


def _src_root(testfile):
    parts = testfile.split("/")
    for i in range(len(parts) - 1, -1, -1):
        if parts[i] == "src":
            return "/".join(parts[:i + 1])
    return ""


def test_imports(root, testfile, tracked):
    """[(spec, missing_path)] for imports of the (existing) test file that resolve to nothing. First-party only (relative / '@/' alias / python package present in the tree)."""
    out = []
    full = os.path.join(root, testfile)
    try:
        if os.path.getsize(full) > MAX_TEST_BYTES:
            return out
        txt = open(full, encoding="utf-8", errors="replace").read()
    except OSError:
        return out
    d = os.path.dirname(testfile)
    if testfile.endswith(".py"):
        for m in re.finditer(r"^[ \t]*from[ \t]+(\.*)([A-Za-z_][\w.]*)?[ \t]+import\b", txt, re.M):
            dots, mod = m.group(1), m.group(2) or ""
            if dots:
                base = d.split("/")
                base = base[:max(0, len(base) - (len(dots) - 1))]
                rel = _norm("/".join([x for x in base if x] + (mod.split(".") if mod else [])))
                if mod and not (_exists(root, rel + ".py", tracked) or _exists(root, rel + "/__init__.py", tracked)):
                    out.append((dots + mod, rel + ".py"))
            else:
                parts = mod.split(".")
                tail = "/".join(parts)
                top = parts[0]
                top_present = any(f.startswith(top + "/") or ("/" + top + "/") in f or f == top + ".py" or f.endswith("/" + top + ".py") for f in tracked)
                if not top_present or len(parts) < 2:
                    continue   # stdlib / third-party / a bare top-level name: not decidable here
                found = any(f == tail + ".py" or f.endswith("/" + tail + ".py") or f == tail + "/__init__.py" or f.endswith("/" + tail + "/__init__.py") for f in tracked)
                if not found:
                    cands = sorted(f for f in tracked if ("/" + top + "/") in ("/" + f) and f.endswith("/__init__.py"))
                    pre = cands[0][:-len(top + "/__init__.py")] if cands else ""
                    out.append((mod, pre + tail + ".py"))
    else:
        for m in re.finditer(r"""(?:\bfrom|\bimport|\brequire\()\s*['"]([^'"]+)['"]""", txt):
            spec = m.group(1)
            if spec.startswith("."):
                base = _norm(d + "/" + spec)
            elif spec.startswith("@/"):
                sr = _src_root(testfile)
                if not sr:
                    continue
                base = _norm(sr + "/" + spec[2:])
            else:
                continue
            if base.startswith("..") or _ts_found(root, base, tracked):
                continue
            out.append((spec, base + ("" if os.path.splitext(base)[1] else ".ts")))
    return out


def sibling_source(testfile, tracked_or_group_leads):
    """Conventional source path for a test file, or ''."""
    d, b = os.path.split(testfile)
    m = re.match(r"^(.*)\.(?:test|spec)(\.[A-Za-z]+)$", b)
    if m:
        pd = d[:-len("/__tests__")] if d.endswith("/__tests__") else d
        return _norm((pd + "/" if pd else "") + m.group(1) + m.group(2))
    return ""


def _created_by_open_earlier(missing, earlier_open_leads):
    mn = missing.lstrip("./")
    for lp in earlier_open_leads:
        if lp and (lp == mn or lp.endswith("/" + mn) or mn.endswith("/" + lp)):
            return True
    return False


def check_item(line, root, group, tracked=None):
    """-> list of {"kind","spec","missing"} for one open test item. `group` = [(lineno, text)] of the SAME [feat:] group in file order INCLUDING this item (matched by identity of text)."""
    tracked = tracked if tracked is not None else _tracked(root)
    lp = lead_path(line)
    if not lp or not TESTY.search(lp) or PARKED.search(line) or not re.match(r"^- \[ \]", line.strip()):
        return []
    earlier = []
    for _ln, t in group:
        if t == line:
            break
        if re.match(r"^- \[ \]", t.strip()) and not PARKED.search(t):
            earlier.append(lead_path(t))
    cands = []
    if _exists(root, lp, tracked):
        for spec, miss in test_imports(root, lp, tracked):
            cands.append({"kind": "imports", "spec": spec, "missing": miss})
    head = _head(line)
    for m in PATH.finditer(head):
        p = m.group(0).lstrip("./")
        if p != lp and not TESTY.search(p) and not _exists(root, p, tracked) and "/" in p:
            cands.append({"kind": "item-path", "spec": p, "missing": p})
    sib = sibling_source(lp, None)
    if sib and not _exists(root, sib, tracked):
        sibn = sib.lstrip("./")
        if any(t != line and (lead_path(t) == sibn or lead_path(t).endswith("/" + sibn) or sibn.endswith("/" + lead_path(t))) and lead_path(t) for _ln, t in group):
            cands.append({"kind": "sibling", "spec": sibn, "missing": sibn})
    out, seen = [], set()
    for c in cands:
        if c["missing"] in seen:
            continue
        seen.add(c["missing"])
        if not _created_by_open_earlier(c["missing"], earlier):
            out.append(c)
    return out


def _groups(lines):
    g = {}
    for i, ln in enumerate(lines):
        m = FEAT.search(ln)
        if m and re.match(r"^- \[[ xX]\]", ln.strip()):
            g.setdefault(m.group(1), []).append((i + 1, ln))
    return g


def _state(state_dir):
    sd = state_dir or os.environ.get("OVN_STATE_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "state")
    return sd


LOG_KEEP = 4000
LOG_TRIM_AT = 5000


def _trim_log(log):
    """Keep the dedupe log bounded: when it exceeds LOG_TRIM_AT lines, atomically (tmp + mv) rewrite it as its last LOG_KEEP lines. Never raises."""
    try:
        with open(log, encoding="utf-8", errors="replace") as fh:
            n = 0
            for n, _ in enumerate(fh, 1):
                pass
        if n <= LOG_TRIM_AT:
            return False
        with open(log, encoding="utf-8", errors="replace") as fh:
            keep = list(collections.deque(fh, maxlen=LOG_KEEP))
        tmp = "%s.tmp.%d" % (log, os.getpid())
        with open(tmp, "w", encoding="utf-8") as out:
            out.writelines(keep)
        os.replace(tmp, log)
        return True
    except OSError:
        return False


def scan(path, root, repo=None, state_dir=None):
    """Hook body. -> list of new rows (also logged). Never raises."""
    rows = []
    try:
        if mode() == "off":
            return rows
        budget = float(os.environ.get("OVN_TFMS_BUDGET_S", "5") or 5)
        t0 = time.time()
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
        groups = _groups(lines)
        tracked = _tracked(root)
        log = os.environ.get("OVN_TFMS_LOG") or os.path.join(_state(state_dir), "test_first_source_shadow.log")
        seen = set()
        try:
            with open(log, encoding="utf-8", errors="replace") as fh:
                tail_lines = collections.deque(fh, maxlen=LOG_KEEP)   # bounded read: the last LOG_KEEP lines only
            for ln in tail_lines:
                ln = ln.rstrip("\n")
                if ln.startswith("{"):
                    try:
                        j = json.loads(ln)
                        seen.add((j.get("repo"), j.get("line_hash"), j.get("missing")))
                    except ValueError:
                        continue
            _trim_log(log)
        except (OSError, ValueError):
            pass
        for i, ln in enumerate(lines):
            if time.time() - t0 > budget:
                break
            if not re.match(r"^- \[ \]", ln.strip()) or not FEAT.search(ln):
                continue
            lp = lead_path(ln)
            if not lp or not TESTY.search(lp):
                continue
            grp = groups.get(FEAT.search(ln).group(1), [])
            for c in check_item(ln, root, grp, tracked):
                key = (repo or "", _h(ln), c["missing"])
                if key in seen:
                    continue
                seen.add(key)
                rows.append({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "rule": RULE, "mode": "shadow", "repo": repo or "", "line_hash": _h(ln), "line": i + 1,
                             "feat": FEAT.search(ln).group(1), "test": lp, "missing": c["missing"], "kind": c["kind"], "spec": c["spec"], "item": _head(ln).strip()[:160]})
        if rows:
            os.makedirs(os.path.dirname(log), exist_ok=True)
            with open(log, "a", encoding="utf-8") as fh:
                for r in rows:
                    fh.write(json.dumps(r, sort_keys=True) + "\n")
            for r in rows:
                print("%s %s %s -> %s (%s)" % (RULE, repo or "-", r["test"], r["missing"], r["kind"]))
    except Exception:
        pass
    return rows


def main(argv):
    try:
        if len(argv) < 2:
            print(__doc__)
            return 0

        def opt(name, default=None):
            return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default
        cmd = argv[1]
        root = opt("--root", ".")
        if cmd == "scan" and len(argv) >= 3:
            scan(argv[2], root, opt("--repo"), opt("--state"))
        elif cmd == "check" and len(argv) >= 3:
            gf = opt("--group-file")
            grp = [(0, argv[2])]
            if gf:
                lines = open(gf, encoding="utf-8", errors="replace").read().split("\n")
                m = FEAT.search(argv[2])
                grp = _groups(lines).get(m.group(1), [(0, argv[2])]) if m else grp
            print(json.dumps(check_item(argv[2], root, grp), sort_keys=True))
    except Exception as e:  # never raise into a cycle
        sys.stderr.write("ovn_test_first_source: %s: %s\n" % (type(e).__name__, e))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
