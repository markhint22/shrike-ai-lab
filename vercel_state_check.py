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
import json, os, re, sys, time, urllib.error, urllib.request

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
ESCALATE_POLLS = int(os.environ.get("VSC_ESCALATE_POLLS", "3"))
RETRY = os.environ.get("VSC_RETRY", "on").lower() not in ("off", "0", "false", "no")
VERCEL = os.environ.get("VSC_VERCEL_BIN", "vercel")
SCOPE = os.environ.get("VSC_SCOPE", "shrikelabs")


# 2026-11-03 (S2/F4): messages that are known fleet-identity noise, not actionable previews (gitlark: "deployment blocked because commit author lacks permission", repeated daily).
NOISE_MSG_RE = re.compile(r"commit author|author lacks permission|author does not have permission", re.I)
ESCALATE_EVERY_S = float(os.environ.get("VSC_ESCALATE_EVERY_S", str(24 * 3600)))   # S2/F1: rolling window between 'still ERROR' escalations (was: calendar day)


def fmt_age(secs):
    """'13d' / '5h' / '20m' for a duration in seconds."""
    secs = max(0, int(secs))
    return "%dd" % (secs // 86400) if secs >= 2 * 86400 else ("%dh" % (secs // 3600) if secs >= 3600 else "%dm" % (secs // 60))


def legacy_esc_epoch(v, now_s):
    """Pre-S2/F1 state stored esc_<proj> as a local 'YYYY-MM-DD' day marker. Migrate it: today's date means 'escalated now' (the old code already pushed today, and its old
    'still ERROR (N polls)' title cannot be deduped by the relay's per-title cooldown, so treating it as unset would send one extra urgent push); an older date is that day's local midnight."""
    try:
        day = time.strptime(str(v), "%Y-%m-%d")
    except (TypeError, ValueError):
        return 0.0
    if time.strftime("%Y-%m-%d", time.localtime(now_s)) == str(v):
        return now_s
    return time.mktime(day)


def last_ready_text(prod, now_s):
    """'last READY production deploy 13d ago (2026-10-21)' from the newest-first production list, or an honest 'none in the listing'."""
    for d in prod:
        if (d.get("readyState") or d.get("state")) == "READY":
            return "last READY production deploy %s ago (%s)" % (fmt_age(now_s - d["createdAt"] / 1000.0), time.strftime("%Y-%m-%d", time.gmtime(d["createdAt"] / 1000.0)))
    return "no READY production deploy in the last %d deployments" % max(1, len(prod))


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


try:
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import ovn_relay  # P1-notify-delivery: relay LAN/Tailscale fallback + checked delivery + emergency ssh/direct fallback
except Exception:  # noqa: BLE001
    ovn_relay = None


def push(title, body, urgent, dry):
    """-> True when some channel took the message. 2026-11-02 (P1): the relay address was Tailscale while Tailscale was stopped and the failure was only printed (chickadee prod=ERROR
    appeared 66 times, never pushed). Now: relay via NTFY_SERVER, LAN, Tailscale in turn; an urgent message the relay did not take is also appended to the box alerts.log and posted
    directly to ntfy.sh (rate limited); every failed delivery leaves a [delivery-failed] line in ~/.ovn_mac_jobs/alerts.log. Callers record a message as sent only when this returns True."""
    low = urgent == "low"          # Y6/5: a recovery line goes out as ONE low-priority note (urgent="low"); a bool keeps its old meaning
    urgent = urgent is True or (bool(urgent) and not low)
    if dry:
        print(("EMERGENCY " if urgent else ("LOW " if low else "NOTE ")) + title + " :: " + body)
        return True
    if ovn_relay is not None:
        r = ovn_relay.deliver("emergency" if urgent else "warn", "vercel:" + title[:60], body, title=title, prio="low" if low else None)
        # FX-P1: True only when a REAL push channel took it. An emergency that only reached the ssh alerts.log (digest) was NOT pushed, so it is retried next poll.
        # A non-urgent note may rely on the ssh digest line (that is its normal channel when the relay is down).
        ok = bool(r.get("relay") or r.get("direct") or (not urgent and r.get("ssh")))
        if not ok:
            print("push failed: no channel took %r" % title)
        return ok
    if os.environ.get("OVN_NOTIFY_DISABLE", "").strip().lower() not in ("", "0", "false", "no", "off"):   # Z6-fix: same switch definition as ovn_relay.notify_disabled
        print("notify disabled (OVN_NOTIFY_DISABLE): %r not sent" % title)
        return False
    srv = (os.environ.get("NTFY_SERVER") or "http://127.0.0.1:8099")  # P2: never default to the public ntfy.sh
    req = urllib.request.Request("%s/%s" % (srv, TOPIC), data=body.encode(), method="POST",
                                 headers={"Title": title, "Priority": "urgent" if urgent else ("low" if low else "default")})
    try:
        urllib.request.urlopen(req, timeout=15)
        return True
    except Exception as e:  # noqa: BLE001 - alert delivery must never crash the check
        print("push failed:", e)
        return False


def _mac_hb(name):
    """L2-mac-jobs: success heartbeat read by scripts/mac_jobs_health.py (epoch seconds in ~/.ovn_mac_jobs/hb/<name>). Never raises."""
    try:
        d = os.path.join(os.environ.get("OVN_MAC_STATE") or os.path.expanduser("~/.ovn_mac_jobs"), "hb")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, name), "w") as f:
            f.write(str(int(time.time())))
    except OSError:
        pass


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
    listed_ok = bool(by_name)
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
            # recorded as sent ONLY when a channel took it (a lost push used to be marked sent: the next poll stayed silent)
            # S2/F1: the body carries how long production has been without a good build (after a promote that failed, the first push already says "last READY 13d ago")
            body = "%s | %s" % ((prod[0].get("errorMessage") or "newest production deploy is not live")[:120], last_ready_text(prod, now_s))
            if push("Vercel PRODUCTION %s: %s" % (name, st(prod[0])), body[:200], True, dry) is not False:
                state["prod_" + name] = prod[0]["uid"]
        # Y6/5: ERROR -> READY recovery. chickadee prod was ERROR for 2 days (two alerts) and went READY on 11-03 09:00 with NO message. When this project had a production alert on record (prod_<name> = the
        # alerted deployment, or esc_<name>) and the newest production deployment is READY now: ONE low-priority line, then forget the alert state so a later failure alerts again.
        if prod and st(prod[0]) == "READY" and (state.get("prod_" + name) or state.get("esc_" + name)) and prod[0]["uid"] != state.get("prod_" + name):
            rbody = "production is READY again (deployment %s, %s ago); %s" % (prod[0]["uid"][:12], fmt_age(age_of(prod[0])), "it had been failing since the alerted deploy")
            if push("Vercel PRODUCTION %s recovered: READY" % name, rbody[:200], "low", dry) is not False:
                for kk in ("prod_" + name, "esc_" + name):
                    state.pop(kk, None)
        # P1 escalation: production newest state ERROR for ESCALATE_POLLS consecutive polls (a transient redeploy would have cleared it) -> ONE urgent push per day per project,
        # independent of the per-deployment dedupe above (the same ERROR deployment can sit there for days). VSC_ESCALATE_POLLS=0 disables.
        if prod and st(prod[0]) == "ERROR" and prod[0]["uid"] not in pending:
            n_err = int(state.get("errpolls_" + name, 0)) + 1
        else:
            n_err = 0
        state["errpolls_" + name] = n_err
        if ESCALATE_POLLS > 0 and n_err >= ESCALATE_POLLS:
            # S2/F1: STABLE title (the relay's per-title 3h cooldown keyed on 'still ERROR (3 polls)' vs '(7 polls)' never matched: two urgent pushes in 2h); age + poll count live in the body.
            # Age comes from the newest production deployment's createdAt and the last READY one (not the poll counter, which only counts since this code deployed).
            # Once per ROLLING 24 h (state esc_<name> = epoch of the last delivered escalation), not per calendar day (local midnight re-armed it 2h after the previous push).
            try:
                last_esc = float(state.get("esc_" + name, 0))
            except (TypeError, ValueError):
                last_esc = legacy_esc_epoch(state.get("esc_" + name), now_s)
                if isinstance(state.get("esc_" + name), str) and last_esc:
                    state["esc_" + name] = last_esc      # persist the migrated epoch so 'today' does not keep rolling forward with the clock
            if now_s - last_esc >= ESCALATE_EVERY_S:
                body = "newest production deploy ERROR for %s (%d polls); %s; %s" % (fmt_age(age_of(prod[0])), n_err, last_ready_text(prod, now_s),
                                                                                  (prod[0].get("errorMessage") or "production has not recovered")[:80])
                if push("Vercel PRODUCTION %s still ERROR" % name, body[:200], True, dry) is not False:
                    state["esc_" + name] = now_s

        def actionable(d):
            if (d.get("target") or "preview") == "production" or st(d) not in BAD or d["createdAt"] < cutoff:
                return False
            k = key_of(d)
            if k in NOISE_BRANCHES:
                return False          # fleet-only branch: not actionable
            if NOISE_MSG_RE.search(d.get("errorMessage") or ""):
                return False          # known fleet commit-identity noise (S2/F4)
            if k and k in newest and st(newest[k]) == "READY" and newest[k] is not d:
                return False          # S2/F4: the branch already recovered (its newest deployment is READY); a 6h-old ERROR must not keep reporting 'failing'
            if is_transient(d) and (newest.get(k) is not d or d["uid"] in pending):
                return False          # superseded by a later deployment, or a retry is still pending
            return True
        bad = [d for d in deps if actionable(d)]
        if bad and state.get("note_" + name) != today:
            why = (bad[0].get("errorMessage") or st(bad[0]))[:90]
            if push("Vercel previews failing: %s (%d)" % (name, len(bad)), why, False, dry) is not False:
                state["note_" + name] = today
        print("%s: prod=%s bad_previews_%dh=%d retries_pending=%d" % (name, st(prod[0]) if prod else "-", WINDOW_H, len(bad), len(pending)))
    if not dry:
        json.dump(state, open(STATE, "w"))
        if listed_ok:
            _mac_hb("vercel-state-check")


if __name__ == "__main__":
    main()
