#!/usr/bin/env python3
"""qa/staging_check.py railway_fetch with a Railway PROJECT token (2026-11-19): no `railway link`, RAILWAY_TOKEN passed to the CLI, token never in argv.
Driven through a stub CLI; hermetic (temp token file, temp cwd root)."""
import os, stat, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "qa"))
d = tempfile.mkdtemp()
tf = os.path.join(d, "railway.env")
open(tf, "w").write("RAILWAY_TOKEN_BILLWATCH_STAGING=rlwy_proj_TESTTOKEN  # c\n")
for k in [k for k in os.environ if k.startswith("RAILWAY_TOKEN_")]:
    del os.environ[k]
os.environ.update(QA_RAILWAY_TOKEN_FILE=tf, QA_RAILWAY_CWD_ROOT=os.path.join(d, "cwd"), RW_LOG=os.path.join(d, "log"))
stub = os.path.join(d, "railway")
open(stub, "w").write('#!/bin/sh\necho "$* TOKEN=$RAILWAY_TOKEN API=$RAILWAY_API_TOKEN" >> "$RW_LOG"\n[ "$1" = deployment ] && echo \'[{"id":"x","status":"SUCCESS","createdAt":"2026-11-19T00:00:00Z","meta":{"commitHash":"abc"}}]\'\n')
os.chmod(stub, stat.S_IRWXU)
os.environ["PATH"] = d + os.pathsep + os.environ["PATH"]
import staging_check as scm
scm._RAILWAY = stub
P = F = 0
def ok(n, c):
    global P, F
    P, F = (P + 1, F) if c else (P, F + 1)
    print(("  ok   " if c else "  FAIL ") + n)
raw, note = scm.railway_fetch("billwatch", "staging")
log = open(os.environ["RW_LOG"]).read()
ok("fetch succeeds", raw and raw[0]["id"] == "x")
ok("no link call", "link" not in log.split())
ok("token passed via env, account token blanked", "TOKEN=rlwy_proj_TESTTOKEN API=\n" in log)
ok("token not in argv", log.count("rlwy_proj_TESTTOKEN") == 1)
raw, note = scm.railway_fetch("billwatch", "production")
ok("no token for env -> falls back to link (stub logs a link)", "link" in open(os.environ["RW_LOG"]).read())
print("test_qa_railway_token: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
