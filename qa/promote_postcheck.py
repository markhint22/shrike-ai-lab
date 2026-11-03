#!/usr/bin/env python3
"""promote_postcheck.py - POST-PROMOTE check: did the PROD deploy of the promoted SHA actually succeed?  (read-only, bounded, detached)

  python3 qa/promote_postcheck.py watch --repo <name> --sha <promoted main tip> [--timeout S] [--interval S] [--once]

Why (2026-10-03): the promote reported "PROMOTED ... Prod deploy triggered" and nothing ever looked at the deploy; the Chickadee prod deploy FAILED
(aiohttp removed from requirements.txt, a revision-less alembic file) and prod stayed on the old build while /health kept answering 200 from it.

promote_to_prod.sh starts this DETACHED (nohup ... &, all fds redirected) right after the push, so it can never hang the cron/daily_promote critical
path. It polls the Railway PRODUCTION deployment list (read-only) until the deploy whose commit is the promoted SHA reaches a final state:
  SUCCESS            -> one log line (state/promote_postcheck.jsonl + logs/promote_postcheck.log): "prod deploy <id> of <sha> SUCCESS"
  FAILED / CRASHED   -> EMERGENCY push through the ntfy relay (Priority: urgent => relay class "emergency"; NTFY_SERVER/NTFY_TOPIC env as everywhere)
                        + one alerts.log ERROR line; deduped per (repo, sha) via state/promote_postcheck/<repo>_<sha10>.done
  not seen by --timeout (default 1800s) -> alerts.log WARN "UNVERIFIED" (no push: it may simply be a Vercel-only repo / the export is down)
Evidence sources, in order: the railway CLI (production env, present on the Mac only) then state/prod_deploys/<repo>.json written by
`qa/staging_check.py export --repo R --env production` on the Mac and copied to the box by scripts/qa-staging-export.sh (every poll re-reads it).
ALWAYS exits 0. stdlib only. No tokens are read or printed.
"""
import datetime
import json
import os
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import staging_check as sc  # noqa: E402

DEAD = sc.DEAD
FINAL_OK = {"SUCCESS"}
RAILWAY_REPOS = ("billwatch", "gitlark", "iptv_apps")
SKEW_S = float(os.environ.get("OVN_POSTCHECK_SKEW_S", "300"))


def match(commit, sha):
    c, s = (commit or "").lower(), (sha or "").lower()
    return len(c) >= 7 and len(s) >= 7 and (c.startswith(s) or s.startswith(c))


def created_ts(d):
    """createdAt (ISO-8601, 'Z' or offset) -> epoch seconds, or None when missing/unparsable (unknown age => treated as fresh: fail-safe)."""
    v = str(d.get("created") or "").strip()
    if not v:
        return None
    try:
        v = v.replace("Z", "+00:00")
        if "." in v:  # Railway gives nanosecond fractions; fromisoformat on 3.12 handles 6 digits at most
            head, rest = v.split(".", 1)
            tz = rest[6:] if len(rest) > 6 and not rest[:6].isdigit() else ""
            digits = ""
            for ch in rest:
                if not ch.isdigit():
                    break
                digits += ch
            tz = rest[len(digits):]
            v = head + "." + digits[:6].ljust(6, "0") + tz
        dt = datetime.datetime.fromisoformat(v)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt.timestamp()
    except (ValueError, TypeError):
        return None


def find_deploy(deploys, sha, since=None):
    """Newest deploy (normalize() order) whose commit is `sha` and (when `since` is given) that was created at/after it. -> dict | None.
    `since` keeps an OLDER deploy of the same sha (rollback, then re-promote) from reporting its stale FAILED/SUCCESS for the new promote."""
    for d in deploys:
        if not match(d["commit"], sha):
            continue
        if since is not None:
            t = created_ts(d)
            if t is not None and t < since:
                continue
        return d
    return None


def gather_prod(repo):
    """-> (normalized deploys, note). CLI first (fresh), then the exported file (any age: the caller decides by status, the file's own staleness is noted)."""
    raw, note = (None, "railway CLI disabled (OVN_POSTCHECK_NO_CLI=1)") if os.environ.get("OVN_POSTCHECK_NO_CLI") == "1" else sc.railway_fetch(repo, "production")
    if raw:
        return sc.normalize(raw), "railway cli"
    try:
        with open(sc.deploys_file(repo, "prod_deploys")) as f:
            j = json.load(f)
        age = time.time() - float(j.get("fetched_at", 0))
        return sc.normalize(j.get("deployments")), "exported prod_deploys (%ds old)" % age
    except (OSError, ValueError, TypeError, AttributeError):
        return [], "no prod deploy evidence (%s; no state/prod_deploys/%s.json)" % (note, repo)


def alerts_line(level, msg):
    try:
        d = qc.state_dir()
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "alerts.log"), "a") as f:
            f.write("[%s] %s | promote-postcheck | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), level, msg))
    except OSError:
        pass


def log(repo, sha, status, msg):
    row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "repo": repo, "sha": sha, "status": status, "msg": msg}
    try:
        d = qc.state_dir()
        with open(os.path.join(d, "promote_postcheck.jsonl"), "a") as f:
            f.write(json.dumps(row, sort_keys=True) + "\n")
        ld = os.path.join(qc.ovn_dir(), "logs")
        os.makedirs(ld, exist_ok=True)
        with open(os.path.join(ld, "promote_postcheck.log"), "a") as f:
            f.write("%s %s %s %s: %s\n" % (row["ts"], repo, sha[:10], status, msg))
    except OSError:
        pass


def push_emergency(title, body):
    """Emergency push via the relay (NTFY_SERVER), exactly how the shell scripts do it. Never raises; the stub-able `curl` binary on PATH."""
    url = "%s/%s" % ((os.environ.get("NTFY_SERVER") or "http://127.0.0.1:8099").rstrip("/"), os.environ.get("NTFY_TOPIC", "shrike_ovn_311380987a"))
    try:
        subprocess.run(["curl", "-fsS", "--max-time", "8", "-H", "Title: " + title, "-H", "Tags: rotating_light", "-H", "Priority: urgent",
                        "-H", "X-OVN-Level: emergency", "-d", body, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       stdin=subprocess.DEVNULL, timeout=15)
    except Exception:  # noqa: BLE001
        pass


def done_marker(repo, sha):
    return os.path.join(qc.state_dir(), "promote_postcheck", "%s_%s.done" % (repo, sha[:10]))


def evaluate(repo, sha, deploys, since=None):
    """-> (final_status|None, deploy|None). None = keep polling."""
    d = find_deploy(deploys, sha, since)
    if not d:
        return None, None
    if d["status"] in FINAL_OK:
        return "SUCCESS", d
    if d["status"] in DEAD:
        return "FAILED", d
    return None, d


def watch(repo, sha, timeout, interval, once=False):
    mk = done_marker(repo, sha)
    if os.path.exists(mk):
        log(repo, sha, "SKIP", "already reported for this (repo, sha)")
        return "SKIP"
    t_start = time.time()
    since = t_start - SKEW_S  # only deploys created after this watcher started (minus clock skew) can be the promote's own deploy
    t_end = t_start + timeout
    last_note = ""
    while True:
        deploys, last_note = gather_prod(repo)
        st, d = evaluate(repo, sha, deploys, since)
        if st:
            os.makedirs(os.path.dirname(mk), exist_ok=True)
            open(mk, "w").write(st + "\n")
            if st == "SUCCESS":
                log(repo, sha, "SUCCESS", "prod deploy %s of %s SUCCESS (%s)" % (d["id"], sha[:10], last_note))
            else:
                msg = "PROD deploy %s of promoted %s %s - prod is still serving the previous build" % (d["id"], sha[:10], d["status"])
                log(repo, sha, "FAILED", msg)
                alerts_line("ERROR", "%s %s (promote post-check; rollback tag prod-*-%s)" % (repo, msg, repo))
                push_emergency("PROD deploy FAILED after promote: %s" % repo,
                               "%s: %s. Prod is on the previous build; /health 200 does not mean the new code is live." % (repo, msg))
            return st
        if once or time.time() >= t_end:
            break
        time.sleep(interval)
    msg = "no prod deploy for promoted %s reached a final state within %ds (%s) - UNVERIFIED" % (sha[:10], timeout, last_note)
    log(repo, sha, "UNVERIFIED", msg)
    alerts_line("WARN", "%s %s" % (repo, msg))
    return "UNVERIFIED"


# ---------------------------------------------------------------- K4 (2026-11-03): prod /health provenance + Vercel PRODUCTION state
HEALTH_TIMEOUT_S = float(os.environ.get("OVN_POSTCHECK_HEALTH_TIMEOUT", "600"))
VERCEL_TIMEOUT_S = float(os.environ.get("OVN_POSTCHECK_VERCEL_TIMEOUT", "1800"))
PROCESS_START = None  # epoch the postcheck process started (set by main()); anchors the Vercel `since` so a long Railway wait cannot hide the promote's own ERROR deploy


def vercel_repos():
    try:
        import vercel_prod_state as vps
        return tuple(vps.PROJECTS)
    except ImportError:
        return ()


def candidate_head(repo, sha):
    """Single alembic head of the promoted tree (git only), or None (no alembic / unknown / several heads)."""
    try:
        import prod_alembic_check as pac
        rd = qc.repo_dir(repo)
        files = pac.load_files(rd, sha) if rd else None
        if not files:
            return None
        revs, bad = pac.parse_versions(files)
        hs = pac.heads_of(revs)
        return hs[0] if (len(hs) == 1 and not bad) else None
    except Exception:  # noqa: BLE001
        return None


def health_compare(health, sha, head):
    """Pure. -> (state, msg). OK | MISMATCH | UNVERIFIED. Only fields /health exposes are compared; a field that is absent is UNVERIFIED, never a mismatch."""
    if not isinstance(health, dict):
        return "UNVERIFIED", "no /health JSON"
    problems, seen = [], 0
    commit = str(health.get("commit") or "").strip()
    if commit and commit.lower() not in ("unknown", "none", "null", "dev"):
        seen += 1
        if not match(commit, sha):
            problems.append("prod /health commit %s != promoted %s" % (commit[:10], sha[:10]))
    rev = str(health.get("db_revision") or "").strip()
    if rev and head and rev.lower() not in ("unknown", "none", "null", "error"):
        seen += 1
        if rev != head:
            problems.append("prod db_revision %s != candidate head %s" % (rev, head))
    if problems:
        return "MISMATCH", "; ".join(problems)
    if not seen:
        return "UNVERIFIED", "health-has-no-revision (/health exposes neither a usable commit nor db_revision)"
    return "OK", "prod /health matches the promoted commit%s" % (" and alembic head" if (rev and head) else "")


def health_stage(repo, sha, timeout=None, interval=30, once=False, fetch=None, now=time.time, sleep=time.sleep):
    """Poll prod /health until it serves the promoted SHA (a rolling deploy lags the Railway SUCCESS), else report. Shadow: WARN only (emergency needs
    OVN_POSTCHECK_HEALTH_EMERGENCY=on). -> OK | MISMATCH | UNVERIFIED | NA."""
    import prod_alembic_snapshot as pas
    url = pas.health_url(repo)
    if not url:
        log(repo, sha, "HEALTH_NA", "health-has-no-revision: no prod /health URL known for %s" % repo)
        return "NA"
    head = candidate_head(repo, sha)
    timeout = HEALTH_TIMEOUT_S if timeout is None else timeout
    end = now() + timeout
    fetch = fetch or pas.fetch_health
    while True:
        j, note = fetch(url)
        st, msg = health_compare(j, sha, head) if j is not None else ("UNVERIFIED", "prod /health unreachable: %s" % note)
        if st == "OK" or once or now() >= end:
            break
        sleep(interval)
    log(repo, sha, "HEALTH_" + st, msg)
    if st == "MISMATCH":
        alerts_line("WARN", "%s %s (promote post-check, shadow)" % (repo, msg))
        if os.environ.get("OVN_POSTCHECK_HEALTH_EMERGENCY", "off") == "on":
            push_emergency("Prod /health does not match the promote: %s" % repo, "%s: %s" % (repo, msg))
    return st


def vercel_stage(repo, sha, timeout=None, interval=60, once=False, gather=None, now=time.time, sleep=time.sleep):
    """Watch the Vercel PRODUCTION deployment of the promoted SHA. ERROR => the SAME emergency path as a Railway FAILED (alerts.log ERROR + urgent push, deduped per
    (repo, sha)). -> SUCCESS | FAILED | UNVERIFIED | NA | SKIP."""
    import vercel_prod_state as vps
    if repo not in vps.PROJECTS:
        return "NA"
    mk = done_marker(repo, sha) + ".vercel"
    if os.path.exists(mk):
        log(repo, sha, "VERCEL_SKIP", "already reported for this (repo, sha)")
        return "SKIP"
    gather = gather or vps.gather
    t0 = now()
    since = (PROCESS_START if PROCESS_START is not None else t0) - SKEW_S  # anchored at process start / promote time, NOT stage start
    end = t0 + (VERCEL_TIMEOUT_S if timeout is None else timeout)
    note = ""
    while True:
        deploys, note = gather(repo)
        st, d = vps.evaluate(deploys, sha, since) if deploys is not None else (None, None)
        if st:
            os.makedirs(os.path.dirname(mk), exist_ok=True)
            open(mk, "w").write(st + "\n")
            if st == "SUCCESS":
                log(repo, sha, "VERCEL_SUCCESS", "vercel production deploy %s of %s READY (%s)" % (d["id"], sha[:10], note))
            else:
                msg = "VERCEL PRODUCTION deploy %s of promoted %s is %s - the frontend is still serving the previous build" % (d["id"], sha[:10], d["state"])
                log(repo, sha, "VERCEL_FAILED", msg)
                alerts_line("ERROR", "%s %s (promote post-check)" % (repo, msg))
                push_emergency("Vercel PROD deploy FAILED after promote: %s" % repo, "%s: %s." % (repo, msg))
            return st
        if once or now() >= end:
            break
        sleep(interval)
    msg = "no Vercel production deploy of promoted %s reached READY/ERROR within the window (%s) - UNVERIFIED" % (sha[:10], note)
    log(repo, sha, "VERCEL_UNVERIFIED", msg)
    alerts_line("WARN", "%s %s" % (repo, msg))
    return "UNVERIFIED"


def opt(argv, name, default):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def main(argv):
    if not argv or argv[0] != "watch":
        print(__doc__)
        return 0
    repo, sha = opt(argv, "--repo", ""), opt(argv, "--sha", "")
    if not repo or not sha:
        print("usage: promote_postcheck.py watch --repo R --sha S")
        return 0
    try:
        global PROCESS_START
        PROCESS_START = time.time()
        timeout = int(opt(argv, "--timeout", os.environ.get("OVN_POSTCHECK_TIMEOUT", "1800")))
        interval = max(1, int(opt(argv, "--interval", os.environ.get("OVN_POSTCHECK_INTERVAL", "60"))))
        once = "--once" in argv
        railway = os.environ.get("OVN_POSTCHECK_RAILWAY", "auto")
        # K4 stages: kill switches OVN_POSTCHECK_HEALTH=off / OVN_POSTCHECK_VERCEL=off; a crash in one stage never skips the other.
        # The Vercel stage runs CONCURRENTLY with the (up to 1800s) Railway watch so its first poll is not delayed and a Railway FAILED does not postpone it.
        def run_stage(name, fn):
            if os.environ.get("OVN_POSTCHECK_" + name.upper(), "on") == "off":
                return
            try:
                print("%s %s" % (name, fn()))
            except Exception as ex:  # noqa: BLE001
                log(repo, sha, "UNVERIFIED", "%s stage crashed: %s: %s" % (name, type(ex).__name__, ex))
        vthread = threading.Thread(target=run_stage, args=("vercel", lambda: vercel_stage(repo, sha, once=once)), daemon=True)
        vthread.start()
        try:
            if railway == "on" or (railway == "auto" and (repo not in vercel_repos() or repo in RAILWAY_REPOS
                                                           or os.path.exists(sc.deploys_file(repo, "prod_deploys")))):
                print(watch(repo, sha, timeout, interval, once=once))
        finally:
            run_stage("health", lambda: health_stage(repo, sha, once=once))
            vthread.join()
    except Exception as ex:  # noqa: BLE001 - never raise into a cron
        log(repo, sha, "UNVERIFIED", "postcheck crashed: %s: %s" % (type(ex).__name__, ex))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
