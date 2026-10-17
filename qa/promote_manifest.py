#!/usr/bin/env python3
"""promote_manifest.py - Phase 5 per-promote MANIFEST (docs/QA_PLAN_2026-10-01.md section 7: "Promote becomes the SHA-based, manifest-driven one"). SHADOW.

    promote_manifest.py generate --repo R [--candidate SHA] [--prior-tag TAG] [--out-dir D] [--no-write]
    promote_manifest.py history  --repo R [--n 1]          manifests for the last N REAL promotes, rebuilt from the prod-<ts>-<repo> tags (read-only)
    promote_manifest.py show     --repo R                  the newest manifest file for R

A manifest says, for ONE promote of ONE repo, exactly what was (or would be) shipped and what the evidence was:
  repo, candidate_sha, release_branch (a release/* branch pointing at the candidate, else null), main_sha, prior_prod_tag {tag, sha, ts} (the rollback anchor; null + a note
  on a repo's first promote), batch {commits, merges, features, fixes} (prior tag -> candidate), gates {gate: {verdict, rows, fail_rows, latest_ts}} = the QA shadow verdicts whose
  head commit lies in prior_tag..candidate, staging {verdict, relation, staging_sha, match} + soak_hours (LIVE only: the exported staging deploy list is evidence of NOW, a history
  manifest says staging.evidence="history: not reconstructible"), decision HOLD | PROCEED | PROCEED-UNVERIFIED, summary (starts with the decision), rollback command.
  decision: HOLD when any code-facing gate has a FAIL in the range, or an environment gate (staging_check / release_candidate / staging_smoke / staging_e2e) FAILed on the candidate itself,
  or staging is a known MISMATCH; PROCEED-UNVERIFIED when no HOLD but a gate is UNVERIFIED / a FAIL row cannot be resolved to a commit / staging could not be matched / NO code-facing gate evidence lies in the range (vacuous pass) / gate coverage is below OVN_QA_MANIFEST_COVERAGE_PCT of the batch commits (default 0 = off); else PROCEED.
  Rows of operator drills / Phase 5 observers (release_candidate.NON_CODE_GATES minus the environment gates) are not evidence and are ignored here.
  The decision is ADVISORY: nothing reads it (daily_promote.sh is NOT edited; the documented patch is qa/patches/promote_manifest.md).

Output: state/promote_manifests/<repo>-<YYYYMMDD-HHMMSS>.json (atomic) and ONE ledger event {kind:event, type:promote_manifest, key:promote_manifest|<repo>|<sha12>|<ts>} appended to
state/qa_ledger.jsonl (readers that only know landed/escape event types ignore it; qa_scorecard does not count it as an escape).
Flag OVN_QA_PROMOTE_MANIFEST=off|shadow (default shadow; any other value, including 'enforce', behaves as shadow - no enforcement exists here). off: nothing is read or written.
Read-only on the clone, no fetch, no network, never takes run.lock, always exits 0.
"""
import calendar
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import qa_ledger as ql  # noqa: E402
import phase5_common as p5  # noqa: E402

ENV = "OVN_QA_PROMOTE_MANIFEST"
MODES = ("off", "shadow")
SCHEMA = "promote_manifest/1"
NO_PRIOR = "-"          # build(prior_tag=NO_PRIOR): the repo's FIRST promote (history mode), do not guess a prior
ENV_GATES = ("release_candidate", "staging_check", "staging_smoke", "staging_e2e")
SHA_RE = re.compile(r"\b[0-9a-f]{7,40}\b")
COVERAGE_MIN_PCT = int(os.environ.get("OVN_QA_MANIFEST_COVERAGE_PCT", "") or 0) if (os.environ.get("OVN_QA_MANIFEST_COVERAGE_PCT", "") or "0").isdigit() else 0   # 0 = only the empty-evidence rule applies (shadow default)
SEVERITY = {"FAIL": 4, "UNVERIFIED": 3, "FLAG": 2, "PASS": 1, "NA": 0}


def mode():
    return p5.flag(ENV, MODES, "shadow")[0]


def _g(rd, *a, timeout=60):
    rc, out, err = qc.git(rd, *a, timeout=timeout)
    return rc, out.strip(), err.strip()


def tag_re(repo):
    return re.compile(r"^prod-(\d{8}-\d{4,6})-" + re.escape(repo) + r"$")


def prod_tags(rd, repo):
    """[(ts_string, tag, commit_sha)] oldest -> newest (sorted by the timestamp in the tag name). Tags that do not resolve to a commit are dropped."""
    rx = tag_re(repo)
    rc, out, _ = _g(rd, "tag", "-l", "prod-*-" + repo)
    items = []
    for t in out.splitlines():
        m = rx.match(t.strip())
        if not m:
            continue
        rc2, sha, _ = _g(rd, "rev-parse", "--verify", "-q", t.strip() + "^{commit}")
        if rc2 == 0 and sha:
            items.append((m.group(1), t.strip(), sha))
    items.sort()
    return items


def tag_epoch(ts):
    for fmt in ("%Y%m%d-%H%M%S", "%Y%m%d-%H%M"):
        try:
            return calendar.timegm(time.strptime(ts, fmt))
        except ValueError:
            continue
    return 0


def row_tokens(r):
    """Hex tokens naming the HEAD commit a shadow row judged (the base of a 'base..head' ref is never the judged commit)."""
    cand = []
    for f in ("ref", "commit", "head", "head_sha"):
        if isinstance(r.get(f), str):
            cand.append(r[f])
    d = r.get("details")
    if isinstance(d, dict):
        for f in ("head", "head_sha", "commit", "sha"):
            if isinstance(d.get(f), str):
                cand.append(d[f])
    toks = []
    for c in cand:
        toks += SHA_RE.findall(c.split("..")[-1])
    return toks


def gate_verdicts(rd, repo, rows, rng, cand, covered_out=None):
    """-> (gates dict, unresolved_fail_rows list). rows = every qa_shadow row; rng = set of full SHAs in prior_tag..candidate (the candidate included)."""
    import release_candidate as rcand
    cache = {}

    def resolve(tok):
        if tok not in cache:
            rc, full, _ = _g(rd, "rev-parse", "--verify", "-q", tok + "^{commit}")
            cache[tok] = full if rc == 0 and full else None
        return cache[tok]

    per = {}
    unresolved = []
    for r in rows:
        if r.get("repo") not in (repo, None, "?", ""):
            continue
        gate = r.get("gate")
        if not isinstance(gate, str):
            continue
        if gate in rcand.NON_CODE_GATES and gate not in ENV_GATES:
            continue                     # operator drills / Phase 5 observers: not evidence about this batch (a drill FAIL must never become an unresolved FAIL here)
        shas = set(filter(None, (resolve(t) for t in row_tokens(r))))
        in_range = bool(shas & rng)
        on_cand = cand in shas
        is_env = gate in ENV_GATES
        if not (on_cand if is_env else in_range):
            if r.get("verdict") == "FAIL" and not shas and not is_env and rcand.counts_as_fail(r):
                unresolved.append("%s@%s" % (gate, str(r.get("ref", ""))[:30]))
            continue
        if covered_out is not None and not is_env:
            covered_out.update(shas & rng)
        v = r.get("verdict") if r.get("verdict") in SEVERITY else "UNVERIFIED"
        g = per.setdefault(gate, {"verdict": "NA", "rows": 0, "fail_rows": 0, "latest_ts": "", "env": is_env, "_ts": "", "_latest_v": "NA"})
        g["rows"] += 1
        failing = (v == "FAIL") if is_env else rcand.counts_as_fail(r)
        if failing:
            g["fail_rows"] += 1          # a counted FAIL decides the gate's verdict by itself (HOLD); it never competes with "latest"
        else:
            if v == "FAIL":
                v = "NA"                 # a FAIL the release planner excludes (staged_shadow baseline, environment noise) says nothing about this commit
            ts = str(r.get("ts", ""))
            if ts >= g["_ts"]:
                g["_ts"], g["_latest_v"] = ts, v
        g["latest_ts"] = max(g["latest_ts"], str(r.get("ts", "")))
    out = {}
    for gate, g in sorted(per.items()):
        out[gate] = {"verdict": "FAIL" if g["fail_rows"] else g["_latest_v"], "rows": g["rows"], "fail_rows": g["fail_rows"], "latest_ts": g["latest_ts"], "env": g["env"]}
    return out, sorted(set(unresolved))[:20]


def staging_block(repo, cand, rd, live, now):
    """-> (staging dict, soak_hours | None). history: not reconstructible (the deploy list is evidence of now)."""
    if not live:
        return {"verdict": "NA", "relation": "", "staging_sha": "", "match": None, "evidence": "history: not reconstructible"}, None
    try:
        import staging_check as sc
        res = sc.cmd_check(["--repo", repo, "--sha", cand, "--provider", "file"])     # NOT recorded: the manifest is not a gate row
        det = res.get("details") or {}
        rel = det.get("relation", "")
        st = {"verdict": res.get("verdict", "UNVERIFIED"), "relation": rel, "staging_sha": det.get("staging_commit") or "",
              "match": True if rel in ("MATCH", "MATCH_SUPERSET") else (False if rel.startswith("MISMATCH") else None), "evidence": res.get("summary", "")[:160]}
        soak = None
        try:
            with open(sc.deploys_file(repo)) as f:
                deploys = sc.normalize(json.load(f).get("deployments"))
            ok = []
            for d in deploys:
                if d["status"] != "SUCCESS" or not d["commit"]:
                    continue
                if d["commit"].startswith(cand[:10]) or cand.startswith(d["commit"][:10]) or _g(rd, "merge-base", "--is-ancestor", cand, d["commit"])[0] == 0:
                    ok.append(d["created"])
            ep = [ql.epoch(c[:19]) for c in ok if ql.epoch(c[:19])]
            if ep and st["match"]:
                soak = round(max(0.0, (now - min(ep))) / 3600.0, 2)
        except (OSError, ValueError, TypeError, AttributeError):
            soak = None
        return st, soak
    except Exception as ex:  # noqa: BLE001
        return {"verdict": "UNVERIFIED", "relation": "", "staging_sha": "", "match": None, "evidence": "staging_check crashed: %s" % type(ex).__name__}, None


def decide(gates, staging, unresolved, prior, commits=None, covered=None):
    """Pure. -> (decision, reasons list)."""
    hold = ["%s FAIL (%d row%s)" % (g, v["fail_rows"], "" if v["fail_rows"] == 1 else "s") for g, v in gates.items() if v["verdict"] == "FAIL"]
    if staging.get("match") is False:
        hold.append("staging does not serve the candidate (%s)" % (staging.get("relation") or "mismatch"))
    if hold:
        return "HOLD", hold
    unv = ["%s UNVERIFIED" % g for g, v in gates.items() if v["verdict"] == "UNVERIFIED"]
    if unresolved:
        unv.append("%d FAIL row(s) cannot be resolved to a commit" % len(unresolved))
    if staging.get("match") is None and not str(staging.get("evidence", "")).startswith("history"):
        unv.append("staging not matched (%s)" % (staging.get("relation") or staging.get("verdict") or "no evidence"))
    if prior is None:
        unv.append("no prior prod tag: first promote, rollback anchor missing")
    if not any(not v.get("env") for v in gates.values()):
        unv.append("no code-facing gate evidence in range (vacuous pass)")
    elif commits is not None and commits > 0 and covered is not None and covered * 100 < commits * COVERAGE_MIN_PCT:
        unv.append("gate coverage %d of %d commit(s) is below %d%%" % (covered, commits, COVERAGE_MIN_PCT))
    return ("PROCEED-UNVERIFIED", unv) if unv else ("PROCEED", [])


def build(repo, rd, cand, prior_tag, now, live, rows, main_ref="origin/main", release_branch=None, source="live"):
    """Pure-ish: -> manifest dict (no file I/O besides git reads)."""
    tags = prod_tags(rd, repo)
    prior = None
    if prior_tag == NO_PRIOR:
        pass
    elif prior_tag:
        for ts, t, sha in tags:
            if t == prior_tag:
                prior = {"tag": t, "sha": sha, "ts": ql.iso(tag_epoch(ts))}
    else:
        cands = [x for x in tags if x[2] != cand]
        if cands:
            ts, t, sha = cands[-1]
            prior = {"tag": t, "sha": sha, "ts": ql.iso(tag_epoch(ts))}
    base = prior["sha"] if prior else None
    if base and _g(rd, "merge-base", "--is-ancestor", base, cand)[0] != 0:
        base_note = "prior tag is not an ancestor of the candidate (diverged history); batch counted from the merge-base"
        rcb, mb, _ = _g(rd, "merge-base", base, cand)
        range_base = mb if rcb == 0 and mb else None
    else:
        base_note, range_base = "", base
    spec = (range_base + ".." + cand) if range_base else cand
    if range_base:
        rng = set(_g(rd, "rev-list", spec, timeout=120)[1].split())
    else:
        rng = {cand}
    rng.add(cand)
    count = lambda *a: int(_g(rd, "rev-list", "--count", *a, timeout=120)[1] or 0)  # noqa: E731
    commits = count("--no-merges", spec) if range_base else 1
    merges = count("--merges", spec) if range_base else 0
    subj = _g(rd, "log", "--no-merges", "--format=%s", "-n", "400", spec, timeout=120)[1].splitlines() if range_base else []
    rc_m, main_sha, _ = _g(rd, "rev-parse", "--verify", "-q", main_ref + "^{commit}")
    if release_branch is None:
        rcr, brs, _ = _g(rd, "branch", "-a", "--points-at", cand, "--format=%(refname:short)")
        rbs = sorted(b[len("origin/"):] if b.startswith("origin/") else b for b in brs.splitlines() if re.search(r"(^|/)release/", b))
        release_branch = rbs[0] if rbs else None
    covered = set()
    gates, unresolved = gate_verdicts(rd, repo, rows, rng, cand, covered)
    staging, soak = staging_block(repo, cand, rd, live, now)
    decision, reasons = decide(gates, staging, unresolved, prior, commits, len(covered))
    counts = {}
    for v in gates.values():
        counts[v["verdict"]] = counts.get(v["verdict"], 0) + 1
    summ = "%s %s: %d commit(s) since %s; gates %s%s%s" % (
        decision, cand[:10], commits, prior["tag"] if prior else "(no prior prod tag)",
        ", ".join("%s=%d" % kv for kv in sorted(counts.items())) or "none in range",
        ("; " + "; ".join(reasons)) if reasons else "", ("; " + base_note) if base_note else "")
    return {"schema": SCHEMA, "source": source, "repo": repo, "ts": ql.iso(int(now)), "mode": mode(), "candidate_sha": cand, "release_branch": release_branch,
            "main_sha": main_sha if rc_m == 0 else None, "prior_prod_tag": prior,
            "batch": {"commits": commits, "merges": merges, "features": sum(1 for s in subj if re.match(r"feat(\(|:)", s)),
                      "fixes": sum(1 for s in subj if re.match(r"fix(\(|:)", s))},
            "gates": gates, "unresolved_fail_rows": unresolved, "staging": staging, "soak_hours": soak, "decision": decision, "reasons": reasons, "summary": summ[:900],
            "rollback": {"command": ("git checkout %s" % prior["tag"]) if prior else None, "note": "DB downgrades are NOT covered (QA plan 5A)"}}


def write_manifest(m, out_dir, stamp=None):
    """-> path | None. File name <repo>-<YYYYMMDD-HHMMSS>.json; the ledger event is appended once per (repo, sha12, stamp)."""
    stamp = stamp or time.strftime("%Y%m%d-%H%M%S", time.gmtime(ql.epoch(m["ts"]) or time.time()))
    path = os.path.join(out_dir, "%s-%s.json" % (m["repo"], stamp))
    if not p5.atomic_write(path, json.dumps(m, indent=1, sort_keys=True) + "\n"):
        return None
    key = "promote_manifest|%s|%s|%s" % (m["repo"], m["candidate_sha"][:12], stamp)
    _recs, evs = ql.load_ledger()
    if key not in set(e["key"] for e in evs):
        ql.append_lines([{"kind": "event", "key": key, "rec": None, "repo": m["repo"], "type": "promote_manifest", "ts": m["ts"], "epoch": ql.epoch(m["ts"]) or int(time.time()),
                          "ref": m["candidate_sha"][:12], "decision": m["decision"], "prior_tag": (m["prior_prod_tag"] or {}).get("tag"),
                          "batch": m["batch"]["commits"], "manifest": os.path.basename(path)}])
    return path


def default_out_dir():
    return os.path.join(qc.state_dir(), "promote_manifests")


def read_rows():
    import release_candidate as rcand
    return rcand.read_shadow_rows()


def cmd_generate(argv, now=None):
    now = time.time() if now is None else now
    m = mode()
    if m == "off":
        return {"mode": "off", "wrote": None}
    repo = p5.opt(argv, "--repo")
    if not ql.safe_name(repo):
        return {"mode": m, "error": "usage: generate --repo <name>"}
    rd = qc.repo_dir(repo)
    if not rd:
        return {"mode": m, "error": "no clone for repo %s" % repo}
    cand, rb = p5.opt(argv, "--candidate"), None
    if cand:
        rc, full, _ = _g(rd, "rev-parse", "--verify", "-q", cand + "^{commit}")
        if rc != 0:
            return {"mode": m, "error": "candidate %s does not resolve in %s" % (cand[:40], rd)}
        cand = full
    else:
        import release_candidate as rcand
        plan, err = rcand.compute_plan(repo, {"main": "origin/main", "develop": "origin/develop", "date": ""})
        if err or not plan or not plan.get("candidate"):
            return {"mode": m, "error": "no candidate: %s" % ((err or {}).get("summary", "release plan failed"))}
        cand, rb = plan["candidate"], plan.get("release_branch")
    man = build(repo, rd, cand, p5.opt(argv, "--prior-tag"), now, True, read_rows(), release_branch=rb)
    path = None
    if "--no-write" not in argv:
        path = write_manifest(man, p5.opt(argv, "--out-dir") or default_out_dir())
    return {"mode": m, "path": path, "decision": man["decision"], "summary": man["summary"], "manifest": man}


def cmd_history(argv, now=None):
    now = time.time() if now is None else now
    m = mode()
    if m == "off":
        return {"mode": "off", "wrote": []}
    repo = p5.opt(argv, "--repo")
    rd = qc.repo_dir(repo) if ql.safe_name(repo) else None
    if not rd:
        return {"mode": m, "error": "no clone for repo %s" % repo}
    n = max(1, int(p5.opt(argv, "--n", "1") or 1))
    tags = prod_tags(rd, repo)
    if not tags:
        return {"mode": m, "error": "no prod-<ts>-%s tags in %s" % (repo, rd), "wrote": []}
    rows = read_rows()
    out, paths = [], []
    for i in range(len(tags) - 1, max(-1, len(tags) - 1 - n), -1):
        ts, tag, sha = tags[i]
        prior = tags[i - 1][1] if i > 0 else NO_PRIOR
        man = build(repo, rd, sha, prior, tag_epoch(ts) or now, False, rows, source="history")
        man["promoted_tag"] = tag
        man["ts"] = ql.iso(tag_epoch(ts) or int(now))
        if "--no-write" not in argv:
            paths.append(write_manifest(man, p5.opt(argv, "--out-dir") or default_out_dir(), stamp=ts if re.match(r"^\d{8}-\d{6}$", ts) else ts + "00"))
        out.append({"tag": tag, "decision": man["decision"], "prior": (man["prior_prod_tag"] or {}).get("tag"), "batch": man["batch"]["commits"], "summary": man["summary"]})
    return {"mode": m, "wrote": paths, "promotes": out}


def main(argv):
    cmd = argv[0] if argv else ""
    rest = argv[1:]
    try:
        if cmd == "generate":
            r = cmd_generate(rest)
            if "--full" not in rest:
                r.pop("manifest", None)
            print(json.dumps(r, sort_keys=True))
        elif cmd == "history":
            print(json.dumps(cmd_history(rest), sort_keys=True))
        elif cmd == "show":
            d = default_out_dir()
            fs = sorted(f for f in os.listdir(d) if f.startswith(p5.opt(rest, "--repo") + "-") and f.endswith(".json")) if os.path.isdir(d) else []
            print(open(os.path.join(d, fs[-1])).read() if fs else json.dumps({"error": "no manifest"}))
        else:
            print(__doc__)
    except Exception as ex:  # noqa: BLE001
        print(json.dumps({"error": "%s: %s" % (type(ex).__name__, str(ex)[:200]), "mode": mode()}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
