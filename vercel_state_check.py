#!/usr/bin/env python3
"""vercel_state_check.py — Mac-side Vercel awareness (deploy_watch only looked at the newest PROD build and
never saw BLOCKED/ERROR previews). For each linked project, look at deployments from the last WINDOW_H hours:
  - newest PRODUCTION deployment not READY/BUILDING/QUEUED  -> emergency push (urgent)
  - any BLOCKED/ERROR/CANCELED preview in the window         -> ONE note per day per project (folded into the hourly update)
Token comes from the Vercel CLI login. Alerts go through $NTFY_SERVER (the relay) so they obey the notification policy.
usage: vercel_state_check.py [--dry-run]
"""
import json, os, sys, time, urllib.request

HOME = os.path.expanduser("~")
LOCAL = os.environ.get("OVN_CLONES_DIR", os.path.join(HOME, "LocalProjects"))
PROJECTS = ["billwatch/billwatch-web", "gitlark/web", "iptv_apps", "shrike-labs-website", "test-automation-agent/frontend"]
WINDOW_H = float(os.environ.get("VSC_WINDOW_H", "6"))
STATE = os.path.join(HOME, ".ovn_vercel_state.json")
TOPIC = os.environ.get("NTFY_TOPIC", "shrike_ovn_311380987a")
BAD = {"ERROR", "BLOCKED", "CANCELED"}


def token():
    with open(os.path.join(HOME, "Library/Application Support/com.vercel.cli/auth.json")) as f:
        return json.load(f)["token"]


def api(tok, path):
    r = urllib.request.Request("https://api.vercel.com" + path, headers={"Authorization": "Bearer " + tok})
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
    for rel in PROJECTS:
        try:
            pj = json.load(open(os.path.join(LOCAL, rel, ".vercel/project.json")))
            deps = api(tok, "/v6/deployments?projectId=%s&teamId=%s&limit=40" % (pj["projectId"], pj["orgId"]))["deployments"]
        except Exception as e:  # noqa: BLE001
            print("%s: check failed: %s" % (rel, e)); continue
        name = rel.split("/")[0]
        st = lambda d: d.get("readyState") or d.get("state")
        prod = [d for d in deps if (d.get("target") or "") == "production"]
        if prod and st(prod[0]) in BAD and state.get("prod_" + name) != prod[0]["uid"]:
            push("Vercel PRODUCTION %s: %s" % (name, st(prod[0])), (prod[0].get("errorMessage") or "newest production deploy is not live") , True, dry)
            state["prod_" + name] = prod[0]["uid"]
        bad = [d for d in deps if d["createdAt"] >= cutoff and (d.get("target") or "preview") != "production" and st(d) in BAD]
        if bad and state.get("note_" + name) != today:
            why = (bad[0].get("errorMessage") or st(bad[0]))[:90]
            push("Vercel previews failing: %s (%d)" % (name, len(bad)), why, False, dry)
            state["note_" + name] = today
        print("%s: prod=%s bad_previews_%dh=%d" % (name, st(prod[0]) if prod else "-", WINDOW_H, len(bad)))
    if not dry:
        json.dump(state, open(STATE, "w"))


if __name__ == "__main__":
    main()
