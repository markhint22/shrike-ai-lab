#!/usr/bin/env python3
"""vercel_state_check.py — Mac-side Vercel awareness (deploy_watch only looked at the newest PROD build and
never saw BLOCKED/ERROR previews). For each linked project, look at deployments from the last WINDOW_H hours:
  - newest PRODUCTION deployment not READY/BUILDING/QUEUED  -> emergency push (urgent)
  - any BLOCKED/ERROR/CANCELED preview in the window         -> ONE note per day per project (folded into the hourly update)
2026-10-12: Vercel's GitHub app failed builds with errorCode git_info_fail ("GitHub fetch error - status: 403 ... secondary rate limit") whenever the fleet
pushed several branches within seconds (reconcile pushes the same sha to develop + claude/feature). That is transient and says nothing about the code, so:
  - TRANSIENT (git_info_fail / secondary rate limit): the newest deployment of a tracked branch (develop, main/production) is redeployed with `vercel redeploy`
    (max VSC_MAX_RETRIES per deployment, not before VSC_RETRY_MIN_AGE_S so the limit has cleared, never when a newer deployment of that branch exists - a redeploy
    of an OLDER commit would move the branch alias backwards); a failure that was superseded by a later deployment of the same branch is ignored.
  - previews of fleet-only branches (claude/feature, overnight/feature) are never reported (nobody looks at them; vercel.json also stops building them).
  - an emergency/note fires only for a non-transient failure, or when the retries are exhausted. The retry counter is keyed by project + branch + commit sha
    (a redeploy gets a NEW deployment id but keeps the sha), so a redeploy that fails again with the same error cannot chain forever; `--no-wait` keeps the check short.
Token comes from the Vercel CLI login. Alerts go through $NTFY_SERVER (the relay) so they obey the notification policy.
usage: vercel_state_check.py [--dry-run]
"""
import json, os, sys, time, urllib.error, urllib.request

HOME = os.path.expanduser("~")
LOCAL = os.environ.get("OVN_CLONES_DIR", os.path.join(HOME, "LocalProjects"))
# Vercel PROJECT NAMES (resolved via the API). 2026-10-01: the old path-based list used billwatch/billwatch-web/.vercel which is the CLI-only
# 'billwatch-web' project; the Git-connected project that builds every preview and the prod deploy is 'billwatch' - failures there (Node 20.x
# discontinued, 13 ERROR previews + 1 ERROR production) were invisible. Names below are the ones that actually serve our apps.
PROJECTS = ["billwatch", "chickadee", "shrike-labs-website", "gitlark", "frontend", "specpilot"]
TEAM = os.environ.get("VERCEL_TEAM_ID", "team_Acd65eA6TLuMYAZ6nbTJ7jb0")
WINDOW_H = float(os.environ.get("VSC_WINDOW_H", "6"))
STATE = os.path.join(HOME, ".ovn_vercel_state.json")
TOPIC = os.environ.get("NTFY_TOPIC", "shrike_ovn_311380987a")
BAD = {"ERROR", "BLOCKED", "CANCELED"}
TRACKED_BRANCHES = {"develop", "main"}                       # previews/prod that something looks at (staging web, prod web)
NOISE_BRANCHES = {"claude/feature", "overnight/feature"}     # fleet work branches: a failed preview there is not actionable
MAX_RETRIES = int(os.environ.get("VSC_MAX_RETRIES", "2"))
RETRY_MIN_AGE_S = float(os.environ.get("VSC_RETRY_MIN_AGE_S", "180"))
RETRY_MAX_AGE_S = float(os.environ.get("VSC_RETRY_MAX_AGE_S", str(6 * 3600)))
RETRY = os.environ.get("VSC_RETRY", "on").lower() not in ("off", "0", "false", "no")
VERCEL = os.environ.get("VSC_VERCEL_BIN", "vercel")
SCOPE = os.environ.get("VSC_SCOPE", "shrikelabs")


def branch_of(d):
    return ((d.get("meta") or {}).get("githubCommitRef") or "")


def retry_key(name, k, d):
    """Counter key that survives a redeploy (new uid, same commit): project + branch/target + commit sha."""
    return "retry_%s_%s_%s" % (name, k, ((d.get("meta") or {}).get("githubCommitSha") or d.get("uid") or "")[:12])


def is_transient(d):
    return (d.get("errorCode") or "") == "git_info_fail" or "secondary rate limit" in (d.get("errorMessage") or "").lower()


def redeploy(d, dry):
    """vercel redeploy <url>: returns True when the CLI accepted it. Never raises."""
    url = d.get("url") or ""
    if not url:
        return False
    if dry:
        print("DRY redeploy %s" % url)
        return True
    import subprocess
    try:
        r = subprocess.run([VERCEL, "redeploy", "https://" + url if not url.startswith("http") else url, "--no-wait", "--scope", SCOPE],
                           capture_output=True, text=True, timeout=300)
        return r.returncode == 0
    except Exception as e:  # noqa: BLE001
        print("redeploy failed: %s" % e)
        return False


def token():
    with open(os.path.join(HOME, "Library/Application Support/com.vercel.cli/auth.json")) as f:
        return json.load(f)["token"]


def api(tok, path):
    try:
        r = urllib.request.Request("https://api.vercel.com" + path, headers={"Authorization": "Bearer " + tok})
        return json.load(urllib.request.urlopen(r, timeout=30))
    except urllib.error.HTTPError as e:
        if e.code not in (401, 403):
            raise
        # the CLI login token is short-lived (auth.json expiresAt); any CLI call refreshes it
        import subprocess
        subprocess.run(["vercel", "whoami"], capture_output=True, timeout=60)
        r = urllib.request.Request("https://api.vercel.com" + path, headers={"Authorization": "Bearer " + token()})
        return json.load(urllib.request.urlopen(r, timeout=30))


def push(title, body, urgent, dry):
    if dry:
        print(("EMERGENCY " if urgent else "NOTE ") + title + " :: " + body)
        return
    srv = os.environ.get("NTFY_SERVER", "https://ntfy.sh")
    req = urllib.request.Request("%s/%s" % (srv, TOPIC), data=body.encode(), method="POST",
                                 headers={"Title": title, "Priority": "urgent" if urgent else "default"})
    try:
        urllib.request.urlopen(req, timeout=15)
    except Exception as e:  # noqa: BLE001 - alert delivery must never crash the check
        print("push failed:", e)


def main():
    dry = "--dry-run" in sys.argv
    try:
        state = json.load(open(STATE))
    except Exception:  # noqa: BLE001
        state = {}
    today = time.strftime("%Y-%m-%d")
    tok, cutoff = token(), (time.time() - WINDOW_H * 3600) * 1000
    try:
        by_name = {p["name"]: p["id"] for p in api(tok, "/v9/projects?teamId=%s&limit=100" % TEAM)["projects"]}
    except Exception as e:  # noqa: BLE001
        print("project list failed: %s" % e); by_name = {}
    for rel in PROJECTS:
        if rel not in by_name:
            print("%s: project not found in team (skipped)" % rel); continue
        try:
            deps = api(tok, "/v6/deployments?projectId=%s&teamId=%s&limit=40" % (by_name[rel], TEAM))["deployments"]
        except Exception as e:  # noqa: BLE001
            print("%s: check failed: %s" % (rel, e)); continue
        name = rel
        st = lambda d: d.get("readyState") or d.get("state")
        now_s = time.time()
        key_of = lambda d: "production" if (d.get("target") or "") == "production" else branch_of(d)
        newest = {}
        for d in deps:
            k = key_of(d)
            if k and (k not in newest or d["createdAt"] > newest[k]["createdAt"]):
                newest[k] = d
        age_of = lambda d: now_s - d["createdAt"] / 1000.0
        # a transient failure of the NEWEST deployment of a tracked branch (or production) is retried; anything older was superseded by a later deployment
        pending = set()
        for k, d in newest.items():
            if (k not in TRACKED_BRANCHES and k != "production") or st(d) != "ERROR" or not is_transient(d):
                continue
            rk = retry_key(name, k, d)
            n = int(state.get(rk, 0))
            if RETRY and n < MAX_RETRIES and age_of(d) <= RETRY_MAX_AGE_S:
                pending.add(d["uid"])
                if age_of(d) >= RETRY_MIN_AGE_S:
                    # count BEFORE the CLI call and persist at once: a crash/timeout (or a later project raising) must not allow an unbounded redeploy chain
                    if not dry:
                        state[rk] = n + 1
                        json.dump(state, open(STATE, "w"))
                    ok = redeploy(d, dry)
                    print("%s: transient %s on %s (%s) -> redeploy %s (attempt %d/%d)" % (name, d.get("errorCode") or "rate-limit", k, (d.get("meta") or {}).get("githubCommitSha", "")[:9], "accepted" if ok else "FAILED", n + 1, MAX_RETRIES))
        prod = sorted([d for d in deps if (d.get("target") or "") == "production"], key=lambda d: -d["createdAt"])
        if prod and st(prod[0]) in BAD and state.get("prod_" + name) != prod[0]["uid"] and prod[0]["uid"] not in pending:
            push("Vercel PRODUCTION %s: %s" % (name, st(prod[0])), (prod[0].get("errorMessage") or "newest production deploy is not live")[:200], True, dry)
            state["prod_" + name] = prod[0]["uid"]

        def actionable(d):
            if (d.get("target") or "preview") == "production" or st(d) not in BAD or d["createdAt"] < cutoff:
                return False
            k = key_of(d)
            if k in NOISE_BRANCHES:
                return False          # fleet-only branch: not actionable
            if is_transient(d) and (newest.get(k) is not d or d["uid"] in pending):
                return False          # superseded by a later deployment, or a retry is still pending
            return True
        bad = [d for d in deps if actionable(d)]
        if bad and state.get("note_" + name) != today:
            why = (bad[0].get("errorMessage") or st(bad[0]))[:90]
            push("Vercel previews failing: %s (%d)" % (name, len(bad)), why, False, dry)
            state["note_" + name] = today
        print("%s: prod=%s bad_previews_%dh=%d retries_pending=%d" % (name, st(prod[0]) if prod else "-", WINDOW_H, len(bad), len(pending)))
    if not dry:
        json.dump(state, open(STATE, "w"))


if __name__ == "__main__":
    main()
