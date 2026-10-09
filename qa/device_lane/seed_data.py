#!/usr/bin/env python3
"""seed_data.py - give the STAGING premium test account the extra data the e2e suite assumes, through the public API only.

Why: the suite was written against the PROD premium account, which carries hand-seeded streams ("Big Buck Bunny" vod,
"Mux Live Test" live), guide mappings and a watch-history row. The canonical STAGING premium account (see iptv_apps
docs/TEST_ACCOUNTS.md) has none of those, so ~5 specs failed on missing data, not on app behaviour. This script recreates
exactly that data, idempotently. The nightly wrapper runs `e2e_janitor.py --env staging` after the specs, which deletes
everything non-canonical again (streams take their mappings/history with them), so the accounts end canonical.

  seed_data.py            seed (env: CHICK_API_BASE, CHICK_PREMIUM_EMAIL, CHICK_PREMIUM_PASSWORD)
Prints one JSON line {"ok": bool, "actions": [...]}. Exit 0 always (advisory lane); never prints credentials or tokens.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

MUX = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
SEEDS = [
    {"name": "Big Buck Bunny", "url": MUX + "?qa=vod", "stream_type": "vod", "category": "QA Test"},
    {"name": "Mux Live Test", "url": MUX + "?qa=live", "stream_type": "live", "category": "QA Test"},
]
MAP_STREAM, MAP_EPG = "QA Test Channel 1", "qa.test.channel"


def call(base, method, path, token=None, body=None, timeout=30):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, None
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        return 0, None


def seed(base, email, password):
    actions = []
    code, tok = call(base, "POST", "/api/auth/login", body={"email": email, "password": password})
    if code != 200 or not tok or "access_token" not in tok:
        return False, ["login failed (%s)" % code]
    t = tok["access_token"]
    code, streams = call(base, "GET", "/api/streams", t)
    if code != 200 or not isinstance(streams, list):
        return False, ["list streams failed (%s)" % code]
    have = {s["name"]: s for s in streams}
    ok = True
    for spec in SEEDS:
        if spec["name"] in have:
            continue
        c, s = call(base, "POST", "/api/streams", t, spec)
        actions.append("create stream %s -> %s" % (spec["name"], c))
        if c in (200, 201) and isinstance(s, dict):
            have[spec["name"]] = s
        else:
            ok = False
    anchor = have.get(MAP_STREAM)
    if anchor:
        c, maps = call(base, "GET", "/api/epg/mappings", t)
        if c == 200 and not any(m.get("stream_id") == anchor["id"] for m in (maps or [])):
            c2, _ = call(base, "POST", "/api/epg/mappings", t, {"stream_id": anchor["id"], "epg_channel_id": MAP_EPG})
            actions.append("create epg mapping -> %s" % c2)
            ok = ok and c2 in (200, 201)
        c, hist = call(base, "GET", "/api/history", t)
        # a row for THIS stream: leftover rows of streams the janitor deleted would otherwise look like "history exists"
        if c == 200 and not any((h.get("stream_id") == anchor["id"] or (h.get("stream") or {}).get("id") == anchor["id"])
                                for h in (hist or [])):
            c3, _ = call(base, "POST", "/api/history", t,
                        {"stream_id": anchor["id"], "progress_seconds": 12, "duration_seconds": 120})
            actions.append("create watch history -> %s" % c3)
            ok = ok and c3 in (200, 201)
    else:
        ok = False
        actions.append("anchor stream %r missing (premium account not canonical?)" % MAP_STREAM)
    multi = os.environ.get("DL_GUIDE_MULTI_URL", "")
    if multi:
        ok = seed_multi_guide(base, t, multi, actions) and ok
    return ok, actions


def seed_multi_guide(base, t, url, actions):
    """Optional: a hosted multi-channel XMLTV (see make_xmltv.py) so the guide picker / load-more specs have data."""
    c, srcs = call(base, "GET", "/api/epg/sources", t)
    if c != 200:
        return False
    if any(s.get("url") == url for s in srcs or []):
        return True
    c, src = call(base, "POST", "/api/epg/sources", t, {"name": "QA Multi Guide", "url": url})
    actions.append("create multi guide source -> %s" % c)
    if c not in (200, 201) or not isinstance(src, dict):
        return False
    for _ in range(40):  # import runs in the background server side
        time.sleep(3)
        c, st = call(base, "GET", "/api/epg/sources/%d/import-status" % src["id"], t)
        if c == 200 and isinstance(st, dict) and str(st.get("status", "")).lower() in ("completed", "complete", "done", "success", "failed", "error"):
            break
    c, _ = call(base, "POST", "/api/epg/sources/%d/auto-map" % src["id"], t, {})
    actions.append("auto-map multi guide -> %s" % c)
    return c in (200, 201, 202)


def main():
    base = os.environ.get("CHICK_API_BASE", "").rstrip("/")
    email, pw = os.environ.get("CHICK_PREMIUM_EMAIL", ""), os.environ.get("CHICK_PREMIUM_PASSWORD", "")
    if not (base and email and pw):
        print(json.dumps({"ok": False, "actions": ["missing CHICK_API_BASE / premium credentials"]}))
        return 0
    ok, actions = seed(base, email, pw)
    print(json.dumps({"ok": ok, "actions": actions}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
