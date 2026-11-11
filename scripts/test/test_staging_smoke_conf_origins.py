#!/usr/bin/env python3
"""qa/staging_smoke.conf: the billwatch cors cell must preflight the REAL deployed frontend origin.
2026-11-10: the Vue frontend https://billwatch-web.vercel.app was blocked by the prod backend (400 Disallowed CORS origin) while the smoke only
checked billwatch.vercel.app (an unrelated v0 app) and billwatch.app (no DNS), so staging/prod smoke stayed green. Read-only; writes nothing."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONF = os.path.join(HERE, "..", "..", "qa", "staging_smoke.conf")
REAL_FRONTEND = "https://billwatch-web.vercel.app"


def check(conf):
    bw = conf["repos"]["billwatch"]
    errs = []
    if REAL_FRONTEND not in bw["cors"]["origins"]:
        errs.append("billwatch cors origins lack the real frontend %s" % REAL_FRONTEND)
    if bw["frontend"]["url"] != REAL_FRONTEND:
        errs.append("billwatch frontend probe does not target %s (got %s)" % (REAL_FRONTEND, bw["frontend"]["url"]))
    if any(o == "*" for o in bw["cors"]["origins"]):
        errs.append("wildcard origin in cors cell")
    return errs


def main():
    conf = json.load(open(CONF))
    errs = check(conf)
    for e in errs:
        print("FAIL:", e)
    # mutation: dropping the real origin must be detected
    mut = json.loads(json.dumps(conf))
    mut["repos"]["billwatch"]["cors"]["origins"] = [o for o in mut["repos"]["billwatch"]["cors"]["origins"] if o != REAL_FRONTEND]
    if not check(mut):
        print("FAIL: mutation (origin removed) not detected")
        errs.append("mutation")
    print("test_staging_smoke_conf_origins: %s" % ("FAIL" if errs else "PASS"))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
