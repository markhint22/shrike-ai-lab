#!/usr/bin/env python3
"""Tests for the contract-fuzz 'lost its auth' guard and the logout exclusion (BL-FUZZ, 2026-10-10). Stdlib only, runs anywhere.

Background: since 29ff3744 (2026-10-09, real token revocation) `POST /api/auth/logout` bumps the throwaway user's token_version, so the fuzz killed its OWN session
early: 2701 of 3187 responses were 401 and the run reported 2 signatures instead of 33 - the 10 real 500s looked fixed. Two defences: logout is excluded, and a run whose
responses are mostly 401 is UNVERIFIED instead of a meaningless FLAG."""
import json, os, re, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "qa"))
import contract_fuzz as cf  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = tempfile.mkdtemp(prefix="cf-auth-test-")


def ev(kind, **body):
    return json.dumps({kind: body})


def scenario(label, statuses):
    return ev("ScenarioFinished", status="success", recorder={"label": label, "checks": {}, "interactions": {"c%d" % i: {"response": {"status_code": s}} for i, s in enumerate(statuses)}})


def parse(lines):
    p = os.path.join(T, "r%d.ndjson" % len(os.listdir(T)))
    with open(p, "w") as f:
        f.write("\n".join(lines + [ev("EngineFinished", stop_reason="completed", payload={})]) + "\n")
    return cf.parse_ndjson(p)


print("== status census in the parser")
p = parse([scenario("GET /a", [200, 401, 401, 404]), scenario("POST /b", [201]), scenario("GET /c", [500, 401])])
ok("responses and 401s are counted over every interaction of every scenario", p["responses"] == 7 and p["unauthorized"] == 3, p)
p = parse([ev("ScenarioFinished", status="success", recorder={"label": "GET /x", "checks": {}, "interactions": {"c1": {"response": {}}, "c2": {}, "c3": {"response": {"status_code": "oops"}}}})])
ok("interactions without an integer status are ignored, not crashing", p["responses"] == 0 and p["unauthorized"] == 0, p)
ok("the existing signature extraction is unchanged next to the census", parse([ev("ScenarioFinished", status="failure", recorder={
    "label": "GET /y", "checks": {"c1": [{"name": "not_a_server_error", "status": "failure"}]}, "interactions": {"c1": {"response": {"status_code": 500}}}})])["signatures"] == ["GET /y [not_a_server_error] 500"])

print("== auth_loss()")
os.environ.pop("OVN_FUZZ_AUTH_LOSS_MAX", None)
ok("the real failing run: 2701 of 3187 401 => lost", cf.auth_loss({"responses": 3187, "unauthorized": 2701}) == (True, 0.8475))
ok("the real healthy run: 9 of 2546 401 => not lost", cf.auth_loss({"responses": 2546, "unauthorized": 9})[0] is False)
ok("exactly at the threshold is not lost (> 50%, not >=)", cf.auth_loss({"responses": 100, "unauthorized": 50})[0] is False)
ok("just over => lost", cf.auth_loss({"responses": 100, "unauthorized": 51})[0] is True)
ok("too few responses to judge (49 of 49 401) => not lost (never a verdict on noise)", cf.auth_loss({"responses": 49, "unauthorized": 49})[0] is False)
ok("no responses at all => not lost, no division by zero", cf.auth_loss({"responses": 0, "unauthorized": 0}) == (False, 0.0) and cf.auth_loss({}) == (False, 0.0))
os.environ["OVN_FUZZ_AUTH_LOSS_MAX"] = "0.9"
ok("OVN_FUZZ_AUTH_LOSS_MAX raises the bar (85% < 90%)", cf.auth_loss({"responses": 3187, "unauthorized": 2701})[0] is False)
os.environ["OVN_FUZZ_AUTH_LOSS_MAX"] = "garbage"
ok("an unparsable env value falls back to 0.5", cf.auth_loss({"responses": 100, "unauthorized": 60})[0] is True)
os.environ.pop("OVN_FUZZ_AUTH_LOSS_MAX", None)

print("== the iptv_apps exclude list covers every route that can revoke the run's own token")
c = cf.config("iptv_apps")
ex = [rx for rx, _ in c["exclude_paths"]]


def excluded(path):
    return any(re.search(rx, path) for rx in ex)


ok("POST /api/auth/logout is excluded (it bumps token_version)", excluded("/api/auth/logout"))
ok("the reason is recorded next to the pattern", any("logout" in rx and "token_version" in why for rx, why in c["exclude_paths"]))
ok("login / register / refresh / me stay fuzzed (the auth surface is still covered)", not any(excluded(p) for p in ("/api/auth/login", "/api/auth/register", "/api/auth/refresh", "/api/auth/me")))
ok("the earlier token-killers stay excluded", excluded("/api/account/me") and excluded("/api/auth/email"))
ok("the exclusion is anchored (a hypothetical /api/auth/logout-all is not swallowed by accident)", not excluded("/api/auth/logout-everywhere"))

print("\ncontract_fuzz_auth: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
