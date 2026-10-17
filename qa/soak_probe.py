#!/usr/bin/env python3
"""soak_probe.py - QA Phase 4: synthetic-traffic SOAK probe of a STAGING backend (SHADOW only) + per-candidate-SHA soak summary.

  python3 qa/soak_probe.py probe   --repo R [--base-url URL] [--config FILE] [--candidate SHA] [--no-record]
  python3 qa/soak_probe.py summary --repo R --sha SHA [--min-hours H] [--now EPOCH]
  python3 qa/soak_probe.py readiness --repo R [--min-hours H]     (enforce-readiness from real rows: how many served builds ever reached PASS)

Why: a single healthy staging smoke right after a deploy says nothing about a build that degrades 20 minutes later (leaks, a cold cache, a migration that
only breaks the second request). The soak probe samples staging every 10-15 min for the whole soak window with ONE synthetic user journey, so promote_gate
can ask "how many hours of CLEAN samples does the candidate have, and did it show an error signature the previous build never had?".

probe  (one sample; cron runs it every 15 min via qa/soak_probe_cron.sh). Reuses the staging_smoke.py cells and the qa_creds mechanism - nothing new is
       invented for credentials. Steps: health (+ provenance when --candidate is given: a healthy but STALE deploy is a FAIL), canonical login, ONE business
       endpoint, ONE DB write + read-back through a different request (+ cleanup) tagged `soak-<hhmmss>-<hex>` so soak rows are recognisable in staging, and
       the CORS preflight from the real frontend origin. Per request: latency + status. Row appended to state/qa_shadow/soak.jsonl (gate "soak"):
       verdict PASS | FLAG (partial by design, or slow) | FAIL (a step failed: a 5xx, bad body, write not visible, CORS broken, stale build) |
       UNVERIFIED (could not run: no URL / no creds / no HTTP response). details: sha (the build that answered), sha_source, candidate, n_requests, n_5xx,
       latency_p50_ms / latency_max_ms, slow, signatures (METHOD /path/{id} -> 5xx and "step: failure" signatures; never bodies or tokens), steps.
       SAFETY: refuses (UNVERIFIED, nothing sent) any base URL that is not a Railway staging host (staging_smoke.is_staging; loopback only with
       QA_SMOKE_ALLOW_LOCAL=1 for the tests and the drill). Credentials/tokens are scrubbed from every printed or recorded byte.

summary (pure over soak.jsonl; promote_gate reads the same function in SHADOW):
       attributable samples = rows whose served build IS the candidate or CONTAINS it (git ancestor test), plus rows that were asked to verify the candidate
       (row.candidate) and caught a stale build. clean sample = PASS, or FLAG that is not slow. A FAIL or a slow sample breaks the streak. UNVERIFIED samples
       carry no signal (they neither extend nor break a streak, but a gap longer than 3 intervals breaks it: no coverage = no soak).
       RECENCY: a PASS also needs the newest clean sample younger than 3 intervals (STALE_FACTOR); staging down / probe dead after a clean streak is FLAG/HOLD
       ("no current coverage = no soak"), reported as stale + trailing_unverified.
       clean_hours = span of the trailing unbroken clean streak. new_signatures = signatures in the streak window that no earlier build's rows (7 days) showed.
       verdict: UNVERIFIED (no attributable sample, or none that carried signal: NEVER reported as PASS) | FAIL (a FAIL/slow sample in the trailing window or a new
       signature) | FLAG (clean but clean_hours < min: still soaking) | PASS (clean_hours >= min, no new signature).
       decision: HOLD for FAIL and FLAG, OK for PASS, UNVERIFIED for UNVERIFIED (infra problems never hold, same rule as every other promote evidence).
Soak minimum: OVN_QA_SOAK_MIN_HOURS, default 2.0 - chosen from `qa/deploy_drill.py` output (see qa/soak_probe.README.md).
stdlib only. Always exit 0.
"""
import json
import os
import random
import re
import secrets
import sys
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402
import staging_smoke as ss  # noqa: E402

GATE = "soak"
DEFAULT_MIN_HOURS = 2.0
DEFAULT_INTERVAL_S = 900          # cron cadence (15 min)
GAP_FACTOR = 3                    # a hole longer than 3 intervals between two clean samples breaks the streak
STALE_FACTOR = 3                  # a PASS needs its newest clean sample younger than 3 intervals (a dead probe / unreachable staging is not a soak)
SLOW_MS_DEFAULT = 8000            # one request slower than this makes the sample "slow" (FLAG, not clean)
BASELINE_DAYS = 7
SIG_CAP = 12
LOG_MAX_BYTES = 8 * 1024 * 1024


def _env_float(name, default):
    try:
        v = float(os.environ.get(name, ""))
        return v if v > 0 else default
    except ValueError:
        return default


def min_hours():
    return _env_float("OVN_QA_SOAK_MIN_HOURS", DEFAULT_MIN_HOURS)


def slow_ms():
    return _env_float("OVN_SOAK_SLOW_MS", SLOW_MS_DEFAULT)


# ------------------------------------------------------------------------------------------------ signatures
_ID = re.compile(r"^(\d+|[0-9a-fA-F]{8,}|[0-9a-fA-F-]{32,36})$")


def path_template(url):
    """'http://h/api/items/123?x=1' -> '/api/items/{id}' (never the query string: it can carry tokens)."""
    p = urllib.parse.urlparse(url).path or "/"
    return "/".join("{id}" if _ID.match(seg) else seg for seg in p.split("/"))


def norm_detail(d):
    """Strip volatile bits from a step failure detail so the same failure gives the same signature across samples."""
    d = re.sub(r"soak-\d{6}-[0-9a-f]{4}", "soak-<tag>", str(d))      # first: the digit rules below would otherwise eat the tag's hhmmss
    d = re.sub(r"\b[0-9a-fA-F]{7,40}\b", "<sha>", d)
    d = re.sub(r"\d{4,}", "N", d)
    return d[:90]


def step_signatures(steps, reqs):
    sigs = set()
    for method, tmpl, status, _ms in reqs:
        if status >= 500:
            sigs.add("%s %s -> %dxx" % (method, tmpl, status // 100))
    for s in steps:
        if s["status"] == "fail":
            base = s["name"].split(":")[0].strip() if s["name"].startswith(("cors", "business", "write_read")) else s["name"]
            sigs.add("%s: %s" % (base, norm_detail(s["detail"])))
    return sorted(sigs)


# ------------------------------------------------------------------------------------------------ the probe
def _served_sha(run, repo):
    """(sha, source): the commit /health reports, else the newest SUCCESS staging deploy from the exported evidence (fresh only), else ('', '')."""
    if isinstance(run.health_json, dict):
        for k in ("commit", "commit_sha", "git_sha", "git_commit", "sha", "release"):
            v = run.health_json.get(k)
            if isinstance(v, str) and re.fullmatch(r"[0-9a-fA-F]{7,40}", v):
                return v.lower(), "health"
    try:
        import staging_check as sc
        state, _age = sc.file_evidence_state(repo)
        if state == "ok":
            with open(sc.deploys_file(repo)) as f:
                deps = sc.normalize(json.load(f).get("deployments"))
            ok = next((d for d in deps if d["status"] == "SUCCESS" and re.fullmatch(r"[0-9a-f]{7,40}", d["commit"] or "")), None)
            if ok and deps and deps[0]["status"] == "SUCCESS":
                return ok["commit"], "deploys"
    except Exception:  # noqa: BLE001
        pass
    return "", ""


_VISIBLE_FAIL = ("NOT visible", "not found in list")


def _retry_write_read_race(run, cfg, skip):
    """The canonical QA account is shared with staging_smoke / staging_e2e (same field, their own marker): an overlapping writer makes OUR read-back mismatch
    although staging is fine. ONE retry with a fresh marker after a short jitter; a real read-back failure fails twice and stays a FAIL. `retries` is recorded."""
    if "write_read" in skip or not cfg.get("write_read"):
        return
    idx = next((i for i, s in enumerate(run.steps) if s["name"].startswith("write_read:") and s["status"] == "fail"
                and any(m in s["detail"] for m in _VISIBLE_FAIL)), None)
    if idx is None:
        return
    first = run.steps.pop(idx)
    try:
        cap = max(0.0, float(os.environ.get("OVN_SOAK_RETRY_SLEEP_S", "3")))     # 0 is allowed (tests, drill)
    except ValueError:
        cap = 3.0
    time.sleep(cap * random.random())
    run.vars["marker"] = "soak-%s-%s" % (time.strftime("%H%M%S"), secrets.token_hex(2))
    n = len(run.steps)
    run.write_read()
    run.retried = {"first_detail": first["detail"][:120], "recovered": all(s["status"] != "fail" for s in run.steps[n:])}


def sample(repo, base, cfg, defaults, candidate="", ts=None, skip=(), slow_threshold_ms=None):
    """One probe. -> the result dict (qc.verdict shape, scrubbed). `skip` names checks to leave out ({"cors", "provenance", "write_read"}); it exists for the
    drill's mutant proof and is never set by the cron path. `ts` overrides the row timestamp (drill / tests)."""
    t0 = time.time()
    thr = slow_threshold_ms if slow_threshold_ms else slow_ms()
    if not ss.is_staging(base):
        return ss.scrub(qc.verdict("UNVERIFIED", GATE, repo, base[:60], "REFUSING: %s is not a staging URL (the soak probe never touches production)" %
                                   (urllib.parse.urlparse(base).hostname or "?"), {"refused": True}))
    cfg = dict(cfg)
    biz_all = [b for b in cfg.get("business", []) if not b.get("expect_status")]
    cfg["business"] = []                       # chosen after login (an authenticated one when we have a token)
    if "cors" in skip:
        cfg.pop("cors", None)
    else:
        c = cfg.get("cors")
        if c and c.get("origins"):
            cfg["cors"] = dict(c, origins=c["origins"][:1])   # one real origin + the arbitrary-origin check: enough for a probe every 15 minutes
    cfg.pop("frontend", None)                  # the frontend is the PROD asset; a soak of staging never loads it
    if "write_read" in skip:
        cfg.pop("write_read", None)
    reqs = []
    orig_http = ss.http

    def traced(method, url, *a, **k):
        t1 = time.time()
        r = orig_http(method, url, *a, **k)
        reqs.append((method, path_template(url), int(r[0]), int((time.time() - t1) * 1000)))
        return r

    ss.http = traced
    try:
        run = ss.Run(repo, base, cfg, defaults)
        run.vars["marker"] = "soak-" + run.vars["marker"]       # the tag every synthetic row carries in staging
        run.health()
        if run.steps[0]["status"] in ("unverified", "fail"):
            for n in ("login", "business", "write_read", "cors"):
                if n == "business" or n in cfg:
                    run.add(n, "skip", "health did not pass")
        else:
            if candidate and "provenance" not in skip:
                run.provenance(candidate)
            run.login()
            pick = None
            if run.token_state == "ok":
                pick = next((b for b in biz_all if b.get("auth")), None)
            if pick is None:
                pick = next((b for b in biz_all if not b.get("auth")), biz_all[0] if biz_all else None)
            if pick is not None:
                run.cfg["business"] = [pick]
                run.business()
            run.write_read()
            _retry_write_read_race(run, cfg, skip)
            run.cors()
    finally:
        ss.http = orig_http
    steps = run.steps
    by = {}
    for s in steps:
        by.setdefault(s["status"], []).append(s["name"])
    fails, unv, na = by.get("fail", []), by.get("unverified", []), by.get("na", [])
    lat = sorted(r[3] for r in reqs)
    p50 = lat[len(lat) // 2] if lat else None
    mx = lat[-1] if lat else None
    n5 = sum(1 for r in reqs if r[2] >= 500)
    slow = bool(mx is not None and mx > thr)
    sigs = step_signatures(steps, reqs)
    sha, src = _served_sha(run, repo)
    if fails:
        v, s = "FAIL", "%d step(s) FAILED: %s" % (len(fails), "; ".join("%s (%s)" % (x["name"], x["detail"]) for x in steps if x["status"] == "fail")[:260])
    elif unv or not reqs:
        v, s = "UNVERIFIED", "could not run: %s" % ("; ".join("%s (%s)" % (x["name"], x["detail"]) for x in steps if x["status"] == "unverified")[:260] or "no request completed")
    elif slow:
        v, s = "FLAG", "SLOW: slowest request %dms > %dms (p50 %sms)" % (mx, thr, p50)
    elif na:
        v, s = "FLAG", "PARTIAL soak sample: %d ok, N/A by design: %s" % (len(by.get("ok", [])), "; ".join(na))
    else:
        v, s = "PASS", "clean sample: %d steps ok, %d requests, p50 %sms, max %sms" % (len(by.get("ok", [])), len(reqs), p50, mx)
    det = {"base_url_host": urllib.parse.urlparse(base).hostname, "sha": sha, "sha_source": src, "candidate": candidate.lower(), "n_requests": len(reqs), "n_5xx": n5,
           "latency_p50_ms": p50, "latency_max_ms": mx, "slow": slow, "partial": bool(na), "signatures": sigs[:SIG_CAP], "marker": run.vars["marker"],
           "steps": [{"name": x["name"][:60], "status": x["status"], "ms": x["ms"]} for x in steps], "creds_source": run.creds_source,
           "write_read_retry": getattr(run, "retried", None)}
    res = qc.verdict(v, GATE, repo, (candidate or sha or "")[:10], s, det, ms=int((time.time() - t0) * 1000))
    if ts is not None:
        res["ts"] = ts if isinstance(ts, str) else time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))
    return ss.scrub(res)


# ------------------------------------------------------------------------------------------------ log
def log_path():
    return os.path.join(qc.state_dir(), "qa_shadow", GATE + ".jsonl")


def parse_ts(v):
    try:
        import calendar
        return float(calendar.timegm(time.strptime(str(v), "%Y-%m-%dT%H:%M:%SZ")))
    except (ValueError, TypeError, OverflowError):
        return None


def read_rows(repo=None, path=None, max_bytes=6 * 1024 * 1024):
    """soak.jsonl rows (dicts with a numeric `_t`), oldest first, tolerant of corrupt lines / a partial first line; only the last `max_bytes` are read."""
    p = path or log_path()
    rows = []
    try:
        with open(p, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - max_bytes))
            data = f.read().decode("utf-8", "replace")
    except OSError:
        return rows
    for line in data.splitlines():
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if not isinstance(r, dict) or r.get("gate") != GATE or (repo and r.get("repo") != repo):
            continue
        t = parse_ts(r.get("ts"))
        if t is None:
            continue
        r["_t"] = t
        rows.append(r)
    rows.sort(key=lambda r: r["_t"])
    return rows


def trim_log(path=None, max_bytes=LOG_MAX_BYTES):
    """Keep the log bounded: above max_bytes rewrite it with its newest half (atomic replace). Never raises."""
    p = path or log_path()
    try:
        if os.path.getsize(p) <= max_bytes:
            return False
        with open(p, "rb") as f:
            f.seek(-(max_bytes // 2), 2)
            f.readline()                      # drop the partial line
            tail = f.read()
        tmp = p + ".tmp"
        with open(tmp, "wb") as f:
            f.write(tail)
        os.replace(tmp, p)
        return True
    except OSError:
        return False


# ------------------------------------------------------------------------------------------------ summary
def _d(r):
    return r.get("details") if isinstance(r.get("details"), dict) else {}


def _matches(a, b):
    return bool(a and b and len(a) >= 7 and len(b) >= 7 and (a.startswith(b) or b.startswith(a)))


def served_is(row, sha, is_anc):
    """True when the build that ANSWERED the row is `sha` or contains it (as opposed to a row only attributable because it asked to verify sha)."""
    served = str(_d(row).get("sha") or "").lower()
    return bool(served and (_matches(served, sha) or is_anc(sha, served) is True))


def attributable(row, sha, is_anc):
    """True when the row speaks about build `sha`: it was served by sha or a descendant of it, or it was explicitly asked to verify sha."""
    d = _d(row)
    served, cand = str(d.get("sha") or "").lower(), str(d.get("candidate") or "").lower()
    if served and (_matches(served, sha) or is_anc(sha, served) is True):
        return True
    return bool(cand and _matches(cand, sha))


def is_clean(row):
    d = _d(row)
    return row.get("verdict") == "PASS" or (row.get("verdict") == "FLAG" and not d.get("slow"))


def is_bad(row):
    return row.get("verdict") == "FAIL" or bool(_d(row).get("slow"))


def summarize(rows, repo, sha, now=None, is_anc=None, min_h=None, interval_s=DEFAULT_INTERVAL_S):
    """Pure. rows: read_rows() output (any repo). -> dict(verdict, decision, clean_hours, min_hours, samples, informative, bad, new_signatures, summary, ...)."""
    now = time.time() if now is None else now
    is_anc = is_anc or (lambda a, b: None)
    min_h = min_hours() if min_h is None else min_h
    sha = (sha or "").lower()
    mine = [r for r in rows if r.get("repo") == repo and attributable(r, sha, is_anc)]
    out = {"repo": repo, "sha": sha[:10], "min_hours": min_h, "samples": len(mine), "informative": 0, "clean_hours": 0.0, "bad_samples": 0, "new_signatures": [],
           "unverified_samples": 0, "stale": False, "trailing_unverified": 0, "verdict": "UNVERIFIED", "decision": "UNVERIFIED", "summary": "", "last_sample_age_s": None}
    if not mine:
        out["summary"] = "no soak sample is attributable to %s (no traffic / no error source): UNVERIFIED, not PASS" % sha[:10]
        return out
    informative = [r for r in mine if r.get("verdict") != "UNVERIFIED"]
    out["unverified_samples"] = len(mine) - len(informative)
    out["informative"] = len(informative)
    out["last_sample_age_s"] = int(max(0, now - mine[-1]["_t"]))
    if not informative:
        out["summary"] = "all %d soak sample(s) of %s were UNVERIFIED (could not run): no signal, UNVERIFIED not PASS" % (len(mine), sha[:10])
        return out
    gap = GAP_FACTOR * interval_s
    # trailing unbroken clean streak
    streak = []
    last_clean_t = None
    for r in informative:
        if is_bad(r):
            streak, last_clean_t = [], None
            continue
        if not is_clean(r):
            continue
        if last_clean_t is not None and r["_t"] - last_clean_t > gap:
            streak = []
        streak.append(r)
        last_clean_t = r["_t"]
    clean_h = (streak[-1]["_t"] - streak[0]["_t"]) / 3600.0 if len(streak) >= 2 else 0.0
    out["clean_hours"] = round(clean_h, 2)
    out["bad_samples"] = sum(1 for r in informative if is_bad(r))
    # recency: the streak must be CURRENT. Probe rows of an unreachable staging carry no served sha, so they are not attributable to any build and the loop above
    # never sees them; count them (any attribution, same repo) after the streak's end, and require the newest clean sample to be younger than STALE_FACTOR intervals.
    end_t = streak[-1]["_t"] if streak else None
    if end_t is not None:
        out["trailing_unverified"] = sum(1 for x in rows if x.get("repo") == repo and x.get("verdict") == "UNVERIFIED" and not _d(x).get("refused") and x["_t"] > end_t)
        out["stale"] = (now - end_t) > STALE_FACTOR * interval_s
    out["last_clean_age_s"] = None if end_t is None else int(max(0, now - end_t))
    first_t = mine[0]["_t"]
    known = set()
    mine_ids = {id(r) for r in mine}
    for r in rows:
        if r.get("repo") == repo and id(r) not in mine_ids and r["_t"] < first_t and now - r["_t"] <= BASELINE_DAYS * 86400:
            known.update(_d(r).get("signatures") or [])
    window_start = streak[0]["_t"] if streak else (informative[-1]["_t"] - min_h * 3600)
    window = [r for r in informative if r["_t"] >= window_start]
    seen = set()
    for r in window:
        seen.update(_d(r).get("signatures") or [])
    new = sorted(seen - known)
    out["new_signatures"] = new[:SIG_CAP]
    tail_bad = [r for r in informative if is_bad(r) and r["_t"] >= informative[-1]["_t"] - min_h * 3600]
    # a bad row of a build that is NOT the candidate (staging still deploying it, only attributable through row.candidate) breaks the streak but is not a FAIL once
    # staging serves the candidate again: otherwise every deploy lag would hold the promote for min_h hours.
    tail_bad = [r for r in tail_bad if served_is(r, sha, is_anc) or r is informative[-1]]
    if tail_bad or new:
        out["verdict"], out["decision"] = "FAIL", "HOLD"
        out["summary"] = "%s: %d bad sample(s) in the last %.1fh%s; clean streak %.2fh/%.1fh" % (
            sha[:10], len(tail_bad), min_h, ("; NEW signature(s): " + " | ".join(new[:3])) if new else "", clean_h, min_h)
    elif clean_h < min_h:
        out["verdict"], out["decision"] = "FLAG", "HOLD"
        out["summary"] = "%s still soaking: %.2fh clean of %.1fh required (%d informative sample(s))" % (sha[:10], clean_h, min_h, len(informative))
    elif out["stale"]:
        out["verdict"], out["decision"] = "FLAG", "HOLD"
        out["summary"] = "%s: %.2fh clean streak ended %.1fh ago (> %d intervals), %d UNVERIFIED sample(s) since: staging unreachable or the probe is not running; no current coverage = no soak" % (
            sha[:10], clean_h, out["last_clean_age_s"] / 3600.0, STALE_FACTOR, out["trailing_unverified"])
    else:
        out["verdict"], out["decision"] = "PASS", "OK"
        out["summary"] = "%s soaked %.2fh clean (>= %.1fh), %d sample(s), no new error signature" % (sha[:10], clean_h, min_h, len(informative))
    return out


# ------------------------------------------------------------------------------------------------ cli
def _opt(argv, name, default=""):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def _is_ancestor_in(rd):
    def f(a, b):
        if not rd or qc.git(rd, "cat-file", "-e", a + "^{commit}")[0] != 0 or qc.git(rd, "cat-file", "-e", b + "^{commit}")[0] != 0:
            return None
        return qc.git(rd, "merge-base", "--is-ancestor", a, b)[0] == 0
    return f


def resolve_candidate(repo, given):
    """--candidate SHA | auto (default for the cron: the develop head of the repo's clone, OVN_SOAK_CANDIDATE_REF, 'off' = none) | '' -> sha or ''.
    The row then carries `candidate`, so a healthy-but-STALE deploy is a provenance FAIL in the real cron path too (not only in the drill)."""
    if given and given != "auto":
        return given
    ref = os.environ.get("OVN_SOAK_CANDIDATE_REF", "origin/develop")
    if given != "auto" or ref in ("", "off"):
        return ""
    rd = qc.repo_dir(repo)
    if not rd:
        return ""
    rc, out, _ = qc.git(rd, "rev-parse", "--verify", "-q", ref + "^{commit}")
    out = out.strip()
    return out if rc == 0 and re.fullmatch(r"[0-9a-f]{40}", out) else ""


def readiness(rows, repo, min_h=None, interval_s=DEFAULT_INTERVAL_S):
    """Pure. Enforce-readiness from REAL rows: for every build that answered the probe, would it have reached PASS (>= min hours clean, judged at its last row)?
    A build replaced after less than min hours (develop merges redeploy staging) can never PASS: a high 'never_soaked' share means enforcing would starve promotes."""
    min_h = min_hours() if min_h is None else min_h
    mine = [r for r in rows if r.get("repo") == repo and _d(r).get("sha")]
    shas = []
    for r in mine:
        if _d(r)["sha"] not in shas:
            shas.append(_d(r)["sha"])
    per = []
    for sh in shas:
        last = max(r["_t"] for r in mine if _d(r)["sha"] == sh)
        s = summarize(rows, repo, sh, now=last + 60, min_h=min_h, interval_s=interval_s)
        per.append({"sha": sh[:10], "verdict": s["verdict"], "clean_hours": s["clean_hours"], "samples": s["samples"]})
    n = len(per)
    passed = sum(1 for p in per if p["verdict"] == "PASS")
    return {"repo": repo, "min_hours": min_h, "builds": n, "reached_pass": passed, "never_soaked": n - passed, "pass_share": round(passed / n, 2) if n else None,
            "verdict": "UNVERIFIED" if not n else ("PASS" if passed / n >= 0.5 else "FLAG"),
            "summary": "no served-build rows yet: nothing to judge" if not n else "%d of %d builds reached %.1fh clean before being replaced%s" % (
                passed, n, min_h, "" if passed / n >= 0.5 else ": enforcing would hold most promotes; do NOT enforce yet"), "builds_detail": per[-20:]}


def cmd_probe(argv):
    repo = _opt(argv, "--repo")
    if not repo:
        return qc.verdict("UNVERIFIED", GATE, "?", "?", "usage: probe --repo <name>")
    cfg_path = _opt(argv, "--config", os.path.join(HERE, "staging_smoke.conf"))
    try:
        conf = ss.load_config(cfg_path)
    except (OSError, ValueError) as ex:
        return qc.verdict("UNVERIFIED", GATE, repo, "?", "cannot read smoke config: %s" % type(ex).__name__)
    cfg = (conf.get("repos") or {}).get(repo)
    if not cfg:
        return qc.verdict("NA", GATE, repo, "?", "no smoke config for repo %s" % repo)
    base = ss.base_url_for(repo, _opt(argv, "--base-url"))
    if not base:
        res = qc.verdict("UNVERIFIED", GATE, repo, "?", "no staging URL (state/staging_url_%s)" % repo, {"sha": "", "candidate": "", "signatures": []})
    else:
        res = sample(repo, base, cfg, conf.get("defaults", {}), candidate=resolve_candidate(repo, _opt(argv, "--candidate")))
    return res


def cmd_summary(argv):
    repo, sha = _opt(argv, "--repo"), _opt(argv, "--sha")
    if not repo or not sha:
        return {"verdict": "UNVERIFIED", "decision": "UNVERIFIED", "summary": "usage: summary --repo R --sha S"}
    try:
        now = float(_opt(argv, "--now", "")) if "--now" in argv else None
        mh = float(_opt(argv, "--min-hours", "")) if "--min-hours" in argv else None
    except ValueError:
        now, mh = None, None
    rd = qc.repo_dir(repo)
    return summarize(read_rows(repo), repo, sha, now, _is_ancestor_in(rd), mh)


def main(argv):
    if not argv or argv[0] not in ("probe", "summary", "readiness"):
        print(__doc__)
        return 0
    try:
        if argv[0] == "readiness":
            repo = _opt(argv, "--repo")
            mh = _opt(argv, "--min-hours")
            print(json.dumps(readiness(read_rows(repo), repo, float(mh) if mh else None), sort_keys=True))
            return 0
        if argv[0] == "summary":
            print(json.dumps(cmd_summary(argv[1:]), sort_keys=True))
            return 0
        res = cmd_probe(argv[1:])
        if "--no-record" not in argv and res.get("verdict") != "NA" and not (res.get("details") or {}).get("refused"):
            qc.record(res)
            trim_log()
        print(json.dumps(res, ensure_ascii=False, sort_keys=True))
    except Exception as ex:  # noqa: BLE001 - never raise into a cron
        print(json.dumps(qc.verdict("UNVERIFIED", GATE, "?", "?", "soak_probe crashed: %s: %s" % (type(ex).__name__, str(ex)[:120])), sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
