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
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import staging_check as sc  # noqa: E402

DEAD = sc.DEAD
FINAL_OK = {"SUCCESS"}
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
    url = "%s/%s" % (os.environ.get("NTFY_SERVER", "https://ntfy.sh").rstrip("/"), os.environ.get("NTFY_TOPIC", "shrike_ovn_311380987a"))
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
        timeout = int(opt(argv, "--timeout", os.environ.get("OVN_POSTCHECK_TIMEOUT", "1800")))
        interval = max(1, int(opt(argv, "--interval", os.environ.get("OVN_POSTCHECK_INTERVAL", "60"))))
        print(watch(repo, sha, timeout, interval, once="--once" in argv))
    except Exception as ex:  # noqa: BLE001 - never raise into a cron
        log(repo, sha, "UNVERIFIED", "postcheck crashed: %s: %s" % (type(ex).__name__, ex))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
