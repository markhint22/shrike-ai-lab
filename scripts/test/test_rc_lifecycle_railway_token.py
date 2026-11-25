#!/usr/bin/env python3
"""scripts/qa/rc_lifecycle_e2e.py secret() with a Railway PROJECT token (2026-11-20): no `railway link`, RAILWAY_TOKEN passed in env, token never in argv
or error text; falls back to the linked cwd + login when no token. Stub CLI (RC_RAILWAY_SERIAL); hermetic (temp token file + cwd)."""
import os, stat, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "qa"))
d = tempfile.mkdtemp()
tf = os.path.join(d, "railway.env")
for k in [k for k in os.environ if k.startswith("RAILWAY_TOKEN_")]:
    del os.environ[k]
os.environ.update(QA_RAILWAY_TOKEN_FILE=tf, RC_RAILWAY_CWD=os.path.join(d, "cwd"), RC_RAILWAY_RETRY_S="0", RW_LOG=os.path.join(d, "log"))
stub = os.path.join(d, "railway")
open(stub, "w").write('#!/bin/sh\necho "$* TOKEN=$RAILWAY_TOKEN API=$RAILWAY_API_TOKEN" >> "$RW_LOG"\n'
                      '[ -n "$RW_FAIL" ] && { echo "Unauthorized. Please login rlwy_proj_TESTTOKEN" >&2; exit 1; }\necho REVENUECAT_WEBHOOK_SECRET=whsec_x\n')
os.chmod(stub, stat.S_IRWXU)
os.environ["RC_RAILWAY_SERIAL"] = stub
import rc_lifecycle_e2e as rc
P = F = 0
def ok(n, c):
    global P, F
    P, F = (P + 1, F) if c else (P, F + 1)
    print(("  ok   " if c else "  FAIL ") + n)
def log():
    return open(os.environ["RW_LOG"]).read() if os.path.exists(os.environ["RW_LOG"]) else ""
open(tf, "w").write("RAILWAY_TOKEN_CHICKADEE_STAGING=rlwy_proj_TESTTOKEN  # c\n")
ok("secret read", rc.secret() == "whsec_x")
l = log()
ok("no link call", "link" not in l.split())
ok("explicit --service and --environment staging", "--service" in l and "--environment staging" in l)
ok("token via env, account token blanked", "TOKEN=rlwy_proj_TESTTOKEN API=\n" in l)
ok("token not in argv", l.count("rlwy_proj_TESTTOKEN") == 1)
os.environ["RW_FAIL"] = "1"
try:
    rc.secret(); ok("failure raises", False)
except rc.SecretUnavailable as e:
    ok("failure raises, token scrubbed from message", "rlwy_proj_TESTTOKEN" not in str(e) and "rc=1" in str(e))
del os.environ["RW_FAIL"]
open(tf, "w").write("")
os.remove(os.environ["RW_LOG"])
rc.RC_CWD = os.path.join(d, "linked"); os.makedirs(rc.RC_CWD)
ok("no token -> old path (secret read, no --service, TOKEN empty)", rc.secret() == "whsec_x" and "--service" not in log() and "TOKEN= API=" in log())
print("test_rc_lifecycle_railway_token: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
