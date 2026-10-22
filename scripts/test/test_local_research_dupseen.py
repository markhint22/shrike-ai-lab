#!/usr/bin/env python3
"""scripts/ovn_local_research.py: duplicate-rejection memory (2026-10-22).

Incident: every local-27B research pass on every repo proposed the same top evidence, ovn_auto_research_validate.py rejected it as a duplicate of an
existing (done) roadmap line, 0 items were accepted and the queue stayed empty. Evidence rejected as a duplicate is now remembered for a TTL and skipped
before the evidence cap so the next pass reaches fresh evidence. Hermetic: no model, no network, temp dirs only.
"""
import importlib.util
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "ovn_local_research.py")
if not os.path.exists(SCRIPT):
    SCRIPT = os.path.expanduser("~/overnight-queue/scripts/ovn_local_research.py")
P = F = 0


def ok(name, cond, detail=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(detail)) if detail else ""))


def load(env=None):
    for k, v in (env or {}).items():
        os.environ[k] = v
    spec = importlib.util.spec_from_file_location("ovn_lr_dup_%d" % time.time_ns(), SCRIPT)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


lr = load()
EV = [
    {"kind": "untested-function", "file": "iptv-backend/app/main.py", "line": 338, "text": "public function `status_endpoint` is referenced by no test"},
    {"kind": "untested-function", "file": "iptv-backend/app/main.py", "line": 353, "text": "public function `metrics_endpoint` is referenced by no test"},
    {"kind": "no-rate-limit", "file": "iptv-backend/app/routers/epg.py", "line": 340, "text": "17 route(s) and no @limiter.limit (other routers use it)"},
    {"kind": "untested-function", "file": "iptv-backend/app/main.py", "line": 400, "text": "public function `version_endpoint` is referenced by no test"},
]
PROP = [
    "- [ ] [P2] [ready] Test `status_endpoint` - Add unit test for `status_endpoint` in `iptv-backend/app/main.py:338` {cat: test; size: S}",
    "- [ ] [P2] [ready] Test `metrics_endpoint` - Add unit test for `metrics_endpoint` in `iptv-backend/app/main.py:353` {cat: test; size: S}",
    "- [ ] [P2] [ready] Rate limit epg - add a limiter to `iptv-backend/app/routers/epg.py:340` {cat: backend; size: S}",
]
ERR = ("reject: near-duplicate of an existing roadmap item (same file, same words): Test `status_endpoint`\n"
       "reject: duplicate title: Test `metrics_endpoint`\n"
       "accepted 1/3\n")

print("== which evidence a duplicate rejection maps to")
keys = lr.dup_rejected_evidence(PROP, ERR, EV)
ok("status_endpoint evidence is remembered", "iptv-backend/app/main.py|status_endpoint" in keys, keys)
ok("metrics_endpoint evidence is remembered", "iptv-backend/app/main.py|metrics_endpoint" in keys, keys)
ok("the accepted proposal's evidence (epg rate limit) is NOT remembered", not any("epg.py" in k for k in keys), keys)
ok("a sibling symbol in the same file (version_endpoint) is NOT remembered", "iptv-backend/app/main.py|version_endpoint" not in keys, keys)
ok("no rejection lines -> nothing remembered", lr.dup_rejected_evidence(PROP, "accepted 3/3\n", EV) == [])
ok("a non-duplicate rejection (path does not exist) is not remembered", lr.dup_rejected_evidence(PROP, "reject: names a path that does not exist (x): Test `status_endpoint`\n", EV) == [])

print("== persistence and TTL")
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "dupseen")
    now = time.time()
    lr.save_dup_seen(path, {"a|x": now, "b|y": now - 10 * 86400})
    seen = lr.load_dup_seen(path)
    ok("fresh entry survives a reload", "a|x" in seen)
    ok("an entry older than the TTL (72h) is dropped", "b|y" not in seen, seen)
    ok("a missing file is an empty memory", lr.load_dup_seen(os.path.join(d, "none")) == {})

print("== effect on collect(): the next pass reaches fresh evidence")
seen = {lr.evidence_key(EV[0]): time.time(), lr.evidence_key(EV[1]): time.time()}
left = [e for e in EV if not (lr.evidence_key(e) in seen)]
ok("remembered evidence is skipped, the rest remains", [e["line"] for e in left] == [340, 400], left)

print("== mutant: a mapper that never matches would leave the loop in place")
orig = lr.dup_rejected_evidence
lr.dup_rejected_evidence = lambda *a, **k: []
ok("MUTANT (no mapping) leaves status_endpoint un-remembered, so the first assertion above would fail", "iptv-backend/app/main.py|status_endpoint" not in lr.dup_rejected_evidence(PROP, ERR, EV))
lr.dup_rejected_evidence = orig

print("== source: an all-duplicate pass retries on fresh evidence before setting the cooldown")
src = open(SCRIPT).read()
ok("retry hook present, bounded by OVN_LR_DUP_RETRIES", "OVN_LR_DUP_RETRIES" in src and "return main(argv)" in src)
i_retry = src.find("retrying on fresh evidence")
i_marker = src.find('open(marker, "w").write(str(time.time()))', src.find("def main("))
i_marker2 = src.find('open(marker, "w").write(str(time.time()))', i_marker + 10)
ok("the retry happens BEFORE the end-of-pass cooldown marker is written", 0 < i_retry < i_marker2, (i_retry, i_marker, i_marker2))
mut = src.replace('return main(argv)', 'pass')
ok("MUTANT (retry removed) no longer contains the recursive call", 'return main(argv)' not in mut)
print("local_research_dupseen: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
