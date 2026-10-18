#!/usr/bin/env python3
"""qa/staging_check.py railway_fetch: the 60 s timeouts in the Mac exporter (2026-10-14).

Symptom: `railway link` and `railway deployment list` hit the 60 s timeout, so the staging snapshots went stale (billwatch and iptv_apps 40-60 min old, max 30).
Fix under test:
  - a call that times out (rc 124) is retried ONCE with a 120 s budget; other failures are not retried;
  - a link already cached for this cwd (.railway/config.json names the project and service) is reused, so the link step is skipped.

Every test drives railway_fetch through a STUB railway CLI (a shell script, never the real CLI). The stub's "slow" call sleeps 70 s on its first invocation:
the first attempt (60 s budget) times out, the retry (120 s budget) succeeds. Old behaviour: no retry, so the export returns None -> these assertions FAIL.
Runs in a temp dir: QA_RAILWAY_CWD_ROOT points at the temp dir, nothing touches ~/.railway or ~/.qa_railway_cwd.
"""
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))  # scripts/overnight-queue
sys.path.insert(0, os.path.join(OQ, "qa"))
import staging_check as scm  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


STUB = r"""#!/bin/sh
# stub railway CLI: logs every call; RW_SLOW=<link|list> sleeps 70 s on that subcommand's FIRST call (exec, so the timeout kills it cleanly); RW_FAIL=link exits 3.
sub="$1"; [ "$1" = deployment ] && sub=list
echo "$sub $*" >> "$RW_LOG"
n=$(cat "$RW_DIR/count.$sub" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$RW_DIR/count.$sub"
if [ "$sub" = link ]; then
  if [ "$RW_SLOW" = linkall ]; then exec sleep 70; fi
  if [ "$RW_FAIL" = link ]; then exit 3; fi
  if [ "$RW_SLOW" = link ] && [ "$n" = 1 ]; then exec sleep 70; fi
  mkdir -p .railway && printf '{"projectId":"%s","serviceId":"%s"}\n' "$RW_PROJECT" "$RW_SERVICE" > .railway/config.json
  exit 0
fi
if [ "$RW_SLOW" = list ] && [ "$n" = 1 ]; then exec sleep 70; fi
echo '[{"id":"dep-12345678-aaaa","status":"SUCCESS","createdAt":"2026-10-14T10:00:00Z","meta":{"commitHash":"abc123","branch":"develop"}}]'
exit 0
"""

W = tempfile.mkdtemp(prefix="qa-railway-retry-")
try:
    BIN = os.path.join(W, "bin")
    os.makedirs(BIN)
    STUB_PATH = os.path.join(BIN, "railway")
    with open(STUB_PATH, "w") as fh:
        fh.write(STUB)
    os.chmod(STUB_PATH, 0o755)
    CFG = scm.RAILWAY["billwatch"]
    CWDROOT = os.path.join(W, "cwdroot")
    os.environ.update({"PATH": BIN + ":/usr/bin:/bin", "QA_RAILWAY_CWD_ROOT": CWDROOT,
                       "RW_PROJECT": CFG["project"], "RW_SERVICE": CFG["service"]})
    scm._RAILWAY = STUB_PATH  # bypass railway_serial.sh so the stub is the only process (no shared ~/.railway lock)

    def fresh(name):
        d = os.path.join(W, name)
        os.makedirs(d)
        shutil.rmtree(CWDROOT, ignore_errors=True)  # a link cached by an earlier case must not leak in
        os.environ["RW_DIR"] = d
        os.environ["RW_LOG"] = os.path.join(d, "calls.log")
        os.environ["RW_SLOW"] = ""
        os.environ["RW_FAIL"] = ""
        return d

    def calls(d, sub):
        try:
            with open(os.path.join(d, "calls.log")) as fh:
                return [ln for ln in fh.read().splitlines() if ln.split(" ")[0] == sub]
        except OSError:
            return []

    def cwd_for(d_repo_env):
        return os.path.join(os.environ["QA_RAILWAY_CWD_ROOT"], d_repo_env)

    # 1. first `railway link` hangs past 60 s: the retry (120 s) succeeds, the export returns the deploy list, no stale snapshot
    d = fresh("slow_link")
    os.environ["RW_SLOW"] = "link"
    raw, note = scm.railway_fetch("billwatch", "staging")
    ok("slow link: the export SUCCEEDS on the retry (raw deploy list returned)", isinstance(raw, list) and len(raw) == 1, note)
    ok("slow link: note is the railway-cli source (not a timeout failure)", note == "railway cli", note)
    ok("slow link: link was attempted twice (timeout, then the retry)", len(calls(d, "link")) == 2, calls(d, "link"))
    ok("slow link: the deployment list ran once after the link", len(calls(d, "list")) == 1, calls(d, "list"))

    # 2. first `railway deployment list` hangs: the list is retried and succeeds; link was NOT repeated for the retry
    d = fresh("slow_list")
    os.environ["RW_SLOW"] = "list"
    raw, note = scm.railway_fetch("billwatch", "staging")
    ok("slow list: the export SUCCEEDS on the retry", isinstance(raw, list) and len(raw) == 1, note)
    ok("slow list: deployment list attempted twice", len(calls(d, "list")) == 2, calls(d, "list"))
    ok("slow list: link attempted once (it did not time out)", len(calls(d, "link")) == 1, calls(d, "link"))

    # 3. a cached link for this cwd (.railway/config.json names project + service): the link step is skipped entirely
    d = fresh("cached_link")
    cw = cwd_for("billwatch-staging")
    os.makedirs(os.path.join(cw, ".railway"), exist_ok=True)
    with open(os.path.join(cw, ".railway", "config.json"), "w") as fh:
        json.dump({"projectId": CFG["project"], "serviceId": CFG["service"]}, fh)
    raw, note = scm.railway_fetch("billwatch", "staging")
    ok("cached link: export succeeds", isinstance(raw, list) and len(raw) == 1, note)
    ok("cached link: NO link call is made", len(calls(d, "link")) == 0, calls(d, "link"))
    ok("cached link: the deployment list still runs", len(calls(d, "list")) == 1, calls(d, "list"))

    # 4. a cached link for a DIFFERENT project is not trusted: link runs again
    d = fresh("other_link")
    cw2 = cwd_for("billwatch-staging")
    os.makedirs(os.path.join(cw2, ".railway"), exist_ok=True)
    with open(os.path.join(cw2, ".railway", "config.json"), "w") as fh:
        json.dump({"projectId": "00000000-0000-0000-0000-000000000000", "serviceId": CFG["service"]}, fh)
    raw, note = scm.railway_fetch("billwatch", "staging")
    ok("foreign cached link: link IS run", len(calls(d, "link")) == 1, calls(d, "link"))

    # 5. a non-timeout failure is NOT retried (a bad login does not get better in 2 minutes)
    d = fresh("link_fails")
    os.environ["RW_FAIL"] = "link"
    shutil.rmtree(os.path.join(W, "cwdroot", "billwatch-production"), ignore_errors=True)
    raw, note = scm.railway_fetch("billwatch", "production")
    ok("link rc 3: export fails with the link message", raw is None and "railway link failed (rc=3" in note, note)
    ok("link rc 3: NOT retried (one call)", len(calls(d, "link")) == 1, calls(d, "link"))
    ok("link rc 3: no deployment list attempted", len(calls(d, "list")) == 0, calls(d, "list"))

    # The timeout cases below use short budgets (the module globals are read at call time) so they run in seconds.
    # 6. the retry ALSO times out: exactly two link calls, no list call, a bounded None result (no third attempt, no hang)
    d = fresh("retry_also_times_out")
    os.environ["RW_SLOW"] = "linkall"
    os.environ["QA_RAILWAY_RETRY_SECS"] = "3"
    scm.RAILWAY_TIMEOUT_SECS = 2
    try:
        raw, note = scm.railway_fetch("billwatch", "staging")
    finally:
        scm.RAILWAY_TIMEOUT_SECS = 60
        os.environ.pop("QA_RAILWAY_RETRY_SECS", None)
    ok("retry also times out: the export returns None (no stale-as-fresh data)", raw is None, raw)
    ok("retry also times out: note names the link failure (rc=124)", note == "railway link failed (rc=124; login expired?)", note)
    ok("retry also times out: exactly two link attempts (first + one retry)", len(calls(d, "link")) == 2, calls(d, "link"))
    ok("retry also times out: no deployment list attempted", len(calls(d, "list")) == 0, calls(d, "list"))

    # 7. a non-numeric QA_RAILWAY_RETRY_SECS must not crash the exporter: the default 120 s retry budget is used and the export succeeds
    d = fresh("bad_retry_env")
    os.environ["RW_SLOW"] = "link"
    os.environ["QA_RAILWAY_RETRY_SECS"] = "abc"
    scm.RAILWAY_TIMEOUT_SECS = 2
    try:
        raw, note = scm.railway_fetch("billwatch", "staging")
    except Exception as e:  # old behaviour: ValueError escapes railway_fetch
        raw, note = None, "EXCEPTION %s: %s" % (type(e).__name__, e)
    finally:
        scm.RAILWAY_TIMEOUT_SECS = 60
        os.environ.pop("QA_RAILWAY_RETRY_SECS", None)
    ok("bad retry env (abc): no exception, export succeeds on the default-budget retry", isinstance(raw, list) and len(raw) == 1, note)
    ok("bad retry env (abc): the retry still happened (link attempted twice)", len(calls(d, "link")) == 2, calls(d, "link"))

    print("test_qa_railway_retry: %d passed, %d failed" % (P, F))
finally:
    shutil.rmtree(W, ignore_errors=True)
sys.exit(1 if F else 0)
