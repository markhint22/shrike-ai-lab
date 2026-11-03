#!/usr/bin/env python3
"""vercel_prod_state.py - READ-ONLY view of a repo's Vercel PRODUCTION deployments (K4, 2026-11-03).

  python3 qa/vercel_prod_state.py export --repo <name>     # Mac: writes state/vercel_prod/<repo>.json (copy to the box like state/prod_deploys)
  python3 qa/vercel_prod_state.py show   --repo <name>

Why: promote_postcheck only watched Railway, so Chickadee's Vercel PRODUCTION was ERROR for 13 days (vercel.ts schema failure) while every promote logged SUCCESS.
Token source is the same as vercel_state_check.py: env VERCEL_TOKEN, else the Vercel CLI login (~/Library/Application Support/com.vercel.cli/auth.json, Mac only).
Only GET requests are made (project lookup + deployment list). Nothing is ever deployed, redeployed or promoted; the token is never printed or logged.
On the box there is no token: promote_postcheck then reads the exported file (state/vercel_prod/<repo>.json), exactly like state/prod_deploys.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

# repo dir name -> Vercel PROJECT name (same names vercel_state_check.py resolves)
PROJECTS = {"iptv_apps": "chickadee", "billwatch": "billwatch", "gitlark": "gitlark", "shrike-labs-website": "shrike-labs-website"}
TEAM = os.environ.get("VERCEL_TEAM_ID", "team_Acd65eA6TLuMYAZ6nbTJ7jb0")
BAD = {"ERROR"}              # promote post-check emergency state (CANCELED = an ignored-build skip, reported UNVERIFIED, never an emergency)
GOOD = {"READY"}


def export_path(repo):
    return os.path.join(qc.state_dir(), "vercel_prod", repo + ".json")


def token():
    t = os.environ.get("VERCEL_TOKEN", "").strip()
    if t:
        return t
    try:
        with open(os.path.expanduser("~/Library/Application Support/com.vercel.cli/auth.json")) as f:
            return str(json.load(f).get("token") or "")
    except (OSError, ValueError, AttributeError):
        return ""


def normalize(raw):
    """Vercel /v6/deployments rows -> [{id, state, created_ts, sha, target}], newest first. Never raises."""
    out = []
    for d in (raw or []):
        if not isinstance(d, dict):
            continue
        meta = d.get("meta") or {}
        try:
            ts = float(d.get("created") or d.get("createdAt") or 0) / 1000.0
        except (TypeError, ValueError):
            ts = 0.0
        out.append({"id": str(d.get("uid") or d.get("id") or ""), "state": str(d.get("state") or d.get("readyState") or "").upper(),
                    "created_ts": ts, "sha": str(meta.get("githubCommitSha") or ""), "target": str(d.get("target") or "")})
    out.sort(key=lambda x: -x["created_ts"])
    return out


def _get(tok, path):
    r = urllib.request.Request("https://api.vercel.com" + path, headers={"Authorization": "Bearer " + tok})
    return json.load(urllib.request.urlopen(r, timeout=30))


def fetch_api(repo):
    """-> (normalized list | None, note). GET only."""
    name = PROJECTS.get(repo)
    if not name:
        return None, "no Vercel project for %s" % repo
    tok = token()
    if not tok:
        return None, "no Vercel token (VERCEL_TOKEN / CLI login)"
    try:
        pid = _get(tok, "/v9/projects/%s?teamId=%s" % (urllib.parse.quote(name), TEAM))["id"]
        j = _get(tok, "/v6/deployments?projectId=%s&teamId=%s&target=production&limit=10" % (pid, TEAM))
        return normalize(j.get("deployments")), "vercel api"
    except Exception as e:  # noqa: BLE001
        return None, "vercel api failed: %s" % type(e).__name__


def read_export(repo):
    try:
        with open(export_path(repo)) as f:
            j = json.load(f)
        return j.get("deployments") or [], "exported vercel_prod (%ds old)" % (time.time() - float(j.get("fetched_at", 0)))
    except (OSError, ValueError, TypeError, AttributeError):
        return None, "no state/vercel_prod/%s.json" % repo


def gather(repo):
    """-> (deploys | None, note): live API when a token exists (Mac), else the exported file."""
    if os.environ.get("OVN_POSTCHECK_NO_VERCEL_API") != "1":
        d, note = fetch_api(repo)
        if d is not None:
            return d, note
    d, note2 = read_export(repo)
    return d, note2


def match(a, b):
    a, b = (a or "").lower(), (b or "").lower()
    return len(a) >= 7 and len(b) >= 7 and (a.startswith(b) or b.startswith(a))


def evaluate(deploys, sha, since=None):
    """-> ('SUCCESS'|'FAILED'|None, deploy|None). Newest PRODUCTION deployment of `sha` created at/after `since`. READY=SUCCESS, ERROR=FAILED, else keep polling."""
    for d in deploys or []:
        if d.get("target") not in ("production", ""):
            continue
        if not match(d.get("sha"), sha):
            continue
        if since is not None and d.get("created_ts") and d["created_ts"] < since:
            continue
        if d["state"] in GOOD:
            return "SUCCESS", d
        if d["state"] in BAD:
            return "FAILED", d
        return None, d
    return None, None


def cmd_export(repo):
    d, note = fetch_api(repo)
    if d is None:
        print("export skipped: %s" % note)
        return 3
    path = export_path(repo)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"repo": repo, "fetched_at": time.time(), "deployments": d}, f)
    os.replace(tmp, path)
    print("exported %d production deployment(s) for %s" % (len(d), repo))
    return 0


def main(argv):
    if len(argv) < 3 or argv[0] not in ("export", "show") or argv[1] != "--repo":
        print(__doc__)
        return 2
    if argv[0] == "export":
        return cmd_export(argv[2])
    d, note = gather(argv[2])
    print(json.dumps({"note": note, "deployments": (d or [])[:5]}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
