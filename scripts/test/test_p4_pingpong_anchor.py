#!/usr/bin/env python3
"""2026-11-02 (P4 / outcomes F9): ovn_pingpong_guard refinements, replayed on the real shapes (values scrubbed to the shapes that matter).

  A  FALSE POSITIVE (iptv test_notifications_service.py): three commits ADD different tests that share a line shape ("First notification" / "Blocked for A" / duplicate re-add of "First
     notification"). Old code: n=3 revisits=1 -> 'ping-pong'. New (OVN_PINGPONG_ANCHOR=on, default): adds are not flips of an earlier line -> nothing. Mutant: OVN_PINGPONG_ANCHOR=off restores it.
  B  MISS (gitlark): `error_reporting_enabled: bool = False` ADDED by the feature, then REPLACED by `= True` by a fix commit. 2 commits < MIN 3, so the literal detector is silent.
     New config-default detector (OVN_PINGPONG_BOOL, default shadow) reports kind=config-default. Mutant: OVN_PINGPONG_BOOL=off -> silent again. Non-bool and single-add controls stay silent.
  C  the real gitlark status_code 201/200/201 case is still found (anchored replace chain) - kept by the existing suite too.
  D  log dedupe: the shadow row is written once per COMMIT SET (not per day / run); a new commit gives a new row; enforce never parks config-default findings unless OVN_PINGPONG_BOOL=enforce."""
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import tmp_track  # noqa: E402
tmp_track.install()
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


_n = [0]


def load(env=None):
    """Import a fresh copy of the guard under the given env (module-level flags are read at import)."""
    _n[0] += 1
    d = os.path.realpath(tempfile.mkdtemp(prefix="p4pp-"))
    shutil.copy(os.path.join(SCRIPTS, "ovn_pingpong_guard.py"), d)
    shutil.copy(os.path.join(SCRIPTS, "ovn_churn_guard.py"), d)
    old = {k: os.environ.get(k) for k in (env or {})}
    os.environ.update(env or {})
    for k in [k for k in sys.modules if k == "ovn_churn_guard"]:
        del sys.modules[k]
    sys.path.insert(0, d)
    try:
        spec = importlib.util.spec_from_file_location("p4pp_%d" % _n[0], os.path.join(d, "ovn_pingpong_guard.py"))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
    finally:
        sys.path.remove(d)
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    m._root = d
    return m


NOW = 1793500000


def commit(sha, t, subj, path, ctx, removed, added):
    hdr = "@@%s|%d|%s\n\ndiff --git a/%s b/%s\nindex 1..2 100644\n--- a/%s\n+++ b/%s\n@@ -10,%d +10,%d @@ %s" % (sha, t, subj, path, path, path, path, len(removed), len(added), ctx)
    return "\n".join([hdr] + ["-" + r for r in removed] + ["+" + a for a in added]) + "\n"


def detect(M, text, **kw):
    return M.detect(M.parse_patches(text), NOW, **kw)


def main():
    TP = "iptv-backend/tests/test_notifications_service.py"
    ctx = "class TestNotificationService:"
    iptv = (commit("a0000001", NOW - 9000, "test: per-user notification cap isolation", TP, ctx, [], ['    svc.create_notification(user_a, "First notification")'])
            + commit("a0000002", NOW - 6000, "test: zero existing notifications", TP, ctx, [], ['    svc.create_notification(user_a, "Blocked for A")'])
            + commit("a0000003", NOW - 3000, "test: notification cap (duplicate)", TP, ctx, [], ['    svc.create_notification(user_a, "First notification")']))
    NEW, OLD = load(), load({"OVN_PINGPONG_ANCHOR": "off"})
    ok("A1 old behaviour (ANCHOR=off) reproduces the live false positive (n=3 revisits=1)", [(f["n"], f["revisits"]) for f in detect(OLD, iptv)] == [(3, 1)], detect(OLD, iptv))
    ok("A2 default: adding sibling tests of the same shape is NOT a ping-pong", detect(NEW, iptv) == [], detect(NEW, iptv))

    CP = "backend/app/core/config.py"
    cctx = "class Settings(BaseSettings):"
    gl = (commit("b0000001", NOW - 8000, "feat: add an env-gated error-reporting hook", CP, cctx, [], ["    error_reporting_enabled: bool = False"])
          + commit("b0000002", NOW - 4000, "fix: enable error reporting by default to restore previous behavior", CP, cctx, ["    error_reporting_enabled: bool = False"], ["    error_reporting_enabled: bool = True"]))
    f = detect(NEW, gl)
    ok("B1 add False then replace by True is reported as kind=config-default (n=2, shadow default)", len(f) == 1 and f[0]["kind"] == "config-default" and f[0]["n"] == 2 and f[0]["file"] == CP, f)
    ok("B2 MUTANT OVN_PINGPONG_BOOL=off: the old silence on the gitlark flip", detect(load({"OVN_PINGPONG_BOOL": "off"}), gl) == [])
    ints = (commit("c0000001", NOW - 8000, "feat: cap", CP, cctx, [], ["    max_retries: int = 3"]) + commit("c0000002", NOW - 4000, "fix: cap", CP, cctx, ["    max_retries: int = 3"], ["    max_retries: int = 5"]))
    ok("B3 control: a non-bool default change (3 -> 5) is not reported", detect(NEW, ints) == [])
    one = commit("d0000001", NOW - 4000, "feat: flag", CP, cctx, [], ["    error_reporting_enabled: bool = False"])
    ok("B4 control: a single add of a bool default is not reported", detect(NEW, one) == [])
    other = gl.replace("b0000002", "b0000009").replace("error_reporting_enabled: bool = True", "other_flag: bool = True").replace('-    error_reporting_enabled: bool = False', '-    other_flag: bool = False')
    ok("B5 control: two different settings (add A=False, replace B) are not one flip", detect(NEW, other) == [], detect(NEW, other))

    fx = open(os.path.join(HERE, "fixtures_k3", "gitlark_status_pingpong.patchlog"), encoding="utf-8").read()
    r = NEW.detect(NEW.parse_patches(fx), 1793491616 + 3600)
    ok("C1 the real gitlark 201/200/201 chain is still flagged as a literal ping-pong", len(r) == 1 and r[0]["kind"] == "literal" and r[0]["n"] == 3 and r[0]["revisits"] == 1, r)

    # D: log dedupe per commit set
    st = tempfile.mkdtemp(prefix="p4pp-state-")
    M = load({"OVN_STATE_DIR": st, "OVN_DIR": st})
    fnd = detect(M, gl)[0]
    fnd["tests"] = []
    M.shadow_log("gitlark", fnd, 0, "2026-11-02")
    M.shadow_log("gitlark", fnd, 0, "2026-11-02")
    M.shadow_log("gitlark", fnd, 0, "2026-11-03")   # next day, same commits
    rows = open(os.path.join(st, "pingpong_shadow.log")).read().strip().split("\n")
    ok("D1 same commit set on three runs/two days => ONE shadow row", len(rows) == 1 and "config-default-pingpong" in rows[0], rows)
    fnd2 = dict(fnd, commits=fnd["commits"] + [("b0000003", "fix: again")])
    M.shadow_log("gitlark", fnd2, 0, "2026-11-03")
    rows = open(os.path.join(st, "pingpong_shadow.log")).read().strip().split("\n")
    ok("D2 a NEW commit joining the family => a new row", len(rows) == 2, rows)
    ok("D3 commit_set is order-insensitive and deterministic", M.commit_set(fnd) == M.commit_set(dict(fnd, commits=list(reversed(fnd["commits"])))))
    for d in (st,):
        shutil.rmtree(d, ignore_errors=True)
    print("p4 pingpong: %d passed, %d failed" % (P, F))
    return 0 if F == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
