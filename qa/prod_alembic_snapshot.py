#!/usr/bin/env python3
"""prod_alembic_snapshot.py - fetch PROD's alembic revision from its public /health and record it for qa/prod_alembic_check.py  (read-only on prod, 2026-10-10)

  python3 qa/prod_alembic_snapshot.py --repo iptv_apps [--url URL] [--dry-run]

Why: the promote's prod-alembic gate has NEVER had prod evidence ("[prod-alembic] UNVERIFIED (shadow): no read-only prod alembic snapshot" on every promote, review F3):
qa/prod_alembic_check.py only reads state/prod_alembic/<repo>.json, which only the manual `record` command writes, and nobody ever ran it. Chickadee's prod /health already
publishes the revision publicly:  {"status":"healthy","commit":"...","db_revision":"0012_referral_hardening","alembic_head":"0012_referral_hardening","migrations":"current"}.
This script does ONE plain GET of that URL (no credential, no DB, nothing written on prod) and records the revision through prod_alembic_check.cmd_record, i.e. the SAME
snapshot file/format the gate reads (so the gate, its staleness limit QA_PROD_ALEMBIC_MAX_AGE_S and its verdicts are unchanged; it stays SHADOW).

It records ONLY a believable revision. It never overwrites a good snapshot with a bad reading: a non-200, a non-JSON body, a missing / empty / non-revision `db_revision`
('unknown', 'error', 'none', ...) or a network error leaves the existing snapshot untouched and exits 3 (the gate then goes UNVERIFIED when the old snapshot ages out - the
safe direction; a wrongly recorded revision would produce a false FAIL). Exit 0 = recorded (or dry-run ok).

Repos with a known /health revision field: iptv_apps (Chickadee). billwatch and gitlark /health expose no revision yet, so they need that field added or an operator
`prod_alembic_check.py record` (PRODUCTION_URLS below; override per repo with env QA_PROD_ALEMBIC_URL_<REPO upper-case>, or --url).

Wiring (the lead installs; nothing here is scheduled by itself): a BOX cron every 30 min plus once before the daily promote, e.g.
  */30 * * * * cd ~/overnight-queue && python3 qa/prod_alembic_snapshot.py --repo iptv_apps >> logs/prod_alembic_snapshot.log 2>&1
  55 8 * * *   cd ~/overnight-queue && python3 qa/prod_alembic_snapshot.py --repo iptv_apps >> logs/prod_alembic_snapshot.log 2>&1
Kill switch: QA_PROD_ALEMBIC_SNAPSHOT=0 (exit 0, does nothing).
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prod_alembic_check as pac  # noqa: E402

PRODUCTION_URLS = {
    "iptv_apps": "https://chickadeestream-production.up.railway.app/health",
}
REV_OK = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
NOT_A_REVISION = {"unknown", "none", "null", "error", "n/a", "na", "unavailable", "pending", "undefined", "false", "true", "current", "head", "base"}


def health_url(repo, override=""):
    return override or os.environ.get("QA_PROD_ALEMBIC_URL_" + re.sub(r"[^A-Za-z0-9]", "_", repo).upper()) or PRODUCTION_URLS.get(repo, "")


def fetch_health(url, timeout=15):
    """-> (json dict | None, note). One GET; never raises."""
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "shrike-prod-alembic-snapshot/1"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            if r.status != 200:
                return None, "HTTP %d" % r.status
            raw = r.read(1_000_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return None, "HTTP %d" % e.code
    except Exception as e:  # noqa: BLE001 - DNS / refused / timeout
        return None, "request failed: %s" % type(e).__name__
    try:
        j = json.loads(raw)
    except ValueError:
        return None, "body is not JSON (HTML error page?)"
    return (j, "ok") if isinstance(j, dict) else (None, "JSON body is not an object")


def revision_of(j):
    """-> (revision | None, note) from a /health dict."""
    v = j.get("db_revision")
    if not isinstance(v, str) or not v.strip():
        return None, "no db_revision in /health (%s)" % ("null/empty" if "db_revision" in j else "field absent")
    v = v.strip()
    if v.lower() in NOT_A_REVISION or not REV_OK.match(v):
        return None, "db_revision %r is not a believable alembic revision id" % v[:60]
    return v, "ok"


def refresh(repo, url="", dry=False):
    """Library entry (promote_gate may call it): -> (recorded: bool, message). Never raises."""
    try:
        if os.environ.get("QA_PROD_ALEMBIC_SNAPSHOT") == "0":
            return True, "disabled (QA_PROD_ALEMBIC_SNAPSHOT=0)"
        u = health_url(repo, url)
        if not u:
            return False, "no /health URL known for repo %s (PRODUCTION_URLS / QA_PROD_ALEMBIC_URL_*)" % repo
        j, note = fetch_health(u)
        if j is None:
            return False, "%s: %s - snapshot left untouched" % (u, note)
        rev, note = revision_of(j)
        if rev is None:
            return False, "%s: %s - snapshot left untouched" % (u, note)
        if dry:
            return True, "dry-run: %s prod revision is %s (not recorded)" % (repo, rev)
        res = pac.cmd_record(["--repo", repo, "--revision", rev])
        return (res.get("verdict") == "NA"), "%s: %s" % (repo, res.get("summary", "recorded"))
    except Exception as e:  # noqa: BLE001
        return False, "snapshot crashed: %s: %s" % (type(e).__name__, e)


def main(argv):
    o = {"repo": "", "url": ""}
    i = 0
    while i < len(argv):
        if argv[i] in ("--repo", "--url") and i + 1 < len(argv):
            o[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    if not o["repo"]:
        print(__doc__)
        return 2
    ok, msg = refresh(o["repo"], o["url"], dry="--dry-run" in argv)
    print("%s prod-alembic-snapshot %s" % (time.strftime("%F %T"), msg))
    return 0 if ok else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
