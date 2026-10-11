#!/usr/bin/env python3
"""scripts/box_deadman.py (Mac-side off-box dead-man's switch, 2026-10-10): debounce, one alert per episode, recovery, relay-first delivery with a rate-limited direct
fallback, Mac-offline safety, sleep-gap reset, kill switch, and the real PROBE shell snippet. ssh is a fake program, the relay / ntfy / internet probe are local HTTP servers,
time is injected (DEADMAN_NOW): nothing sleeps, nothing leaves this machine. A mutation section breaks each piece of logic in a temp copy and shows the scenarios then fail."""
import contextlib
import email.header
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(OQ, "scripts", "box_deadman.py")
PLIST = os.path.join(OQ, "com.shrike.box-deadman.plist")
if not os.path.isfile(SRC):
    print("  SKIP: scripts/box_deadman.py not installed here")
    sys.exit(0)

P = F = 0
QUIET = False      # True while a MUTANT runs: its failures are expected and must not look like suite failures


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        if not QUIET:
            print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


SKIP_MUT = os.environ.get("DEADMAN_SKIP_MUTATION") == "1"    # read BEFORE the DEADMAN_* env scrub below
T = os.path.realpath(tempfile.mkdtemp(prefix="deadman-test-"))
import atexit
atexit.register(lambda: shutil.rmtree(T, ignore_errors=True))      # also on a crash / sys.exit
for k in list(os.environ):
    if k.startswith("DEADMAN_") or k in ("NTFY_SERVER", "NTFY_TOPIC", "OVN_NTFY_GUARD_LOG"):
        os.environ.pop(k)

# ---------------------------------------------------------------- fake servers
RELAY = {"posts": [], "status": 200, "action": "emergency:sent"}
DIRECT = {"posts": [], "status": 200}


def make_server(rec):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")

        def do_POST(self):
            n = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(n).decode()
            rec["posts"].append({"path": self.path, "title": str(email.header.make_header(email.header.decode_header(self.headers.get("Title") or ""))), "prio": self.headers.get("Priority"), "level": self.headers.get("X-Ovn-Level"), "body": body})
            data = json.dumps({"action": rec.get("action", "")}).encode() if "action" in rec else b"{}"
            self.send_response(rec["status"])
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


relay_srv, direct_srv = make_server(RELAY), make_server(DIRECT)
RELAY_URL = "http://127.0.0.1:%d" % relay_srv.server_port
DIRECT_URL = "http://127.0.0.1:%d" % direct_srv.server_port
CLOSED = "http://127.0.0.1:1"      # nothing listens on port 1

# fake ssh (a tiny sh script: python start-up per call made the mutation section take minutes): the scenario file's first line is the mode, the rest is the probe output
FAKE = os.path.join(T, "fake_ssh.sh")
open(FAKE, "w").write('''#!/bin/sh
n=$#; i=0; tgt=""
for a in "$@"; do i=$((i+1)); [ "$i" -eq $((n-1)) ] && tgt="$a"; done
echo "$tgt" >> "$FAKE_SSH_LOG"
mode="$(head -1 "$FAKE_SSH_SCENARIO")"
case "$mode" in
  down) exit 255 ;;
  garbage) echo "Welcome to the box (no probe output)"; exit 0 ;;
  failtgt:*) [ "${mode#failtgt:}" = "$tgt" ] && exit 255 ;;
esac
tail -n +2 "$FAKE_SSH_SCENARIO"
''')
SCEN, SSHLOG = os.path.join(T, "scenario.txt"), os.path.join(T, "ssh.log")
os.environ["FAKE_SSH_SCENARIO"], os.environ["FAKE_SSH_LOG"] = SCEN, SSHLOG

BASE_T = 1_800_000_000
ISO = lambda t: __import__("time").strftime("%Y-%m-%dT%H:%M:%SZ", __import__("time").gmtime(t))


def probe(now, last_age=60, rep_age=60, unit="active", paused="0", up=86400, llm="200", mtime_age=None):
    return {"now": now, "up": up, "unit": unit, "paused": paused, "mtime": now - (mtime_age if mtime_age is not None else last_age), "last": ISO(now - last_age), "rep": now - rep_age, "llm": llm}


def scenario(**kw):
    mode = "down" if kw.get("down") else "garbage" if kw.get("garbage") else ("failtgt:" + kw["fail_targets"][0]) if kw.get("fail_targets") else "ok"
    with open(SCEN, "w") as f:
        f.write(mode + "\n" + "".join("%s=%s\n" % kv for kv in kw.get("probe", {}).items()))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class _ShimSubprocess:
    """In-process stand-in for the `subprocess` module as box_deadman.probe_box uses it: a real process spawn costs ~0.1 s on a loaded Mac and the suite makes ~1500 probes
    (13 mutants x the whole scenario list). The REAL spawn path (probe_box -> sh fake_ssh.sh) is exercised separately in the 'real ssh process' section below."""
    TimeoutExpired = subprocess.TimeoutExpired

    @staticmethod
    def run(cmd, capture_output=True, text=True, timeout=None):
        tgt = cmd[-2]
        open(SSHLOG, "a").write(tgt + "\n")
        lines = open(SCEN).read().split("\n")
        mode, body = lines[0], "\n".join(l for l in lines[1:] if l)
        if mode == "down" or (mode.startswith("failtgt:") and mode[8:] == tgt):
            return subprocess.CompletedProcess(cmd, 255, "", "")
        if mode == "garbage":
            return subprocess.CompletedProcess(cmd, 0, "Welcome to the box (no probe output)\n", "")
        return subprocess.CompletedProcess(cmd, 0, body + "\n", "")


def shimmed(mod):
    mod.subprocess = _ShimSubprocess
    return mod


def setenv(sd, **extra):
    for k in list(os.environ):
        if k.startswith("DEADMAN_") or k in ("NTFY_SERVER", "NTFY_TOPIC", "OVN_NTFY_GUARD_LOG"):
            os.environ.pop(k)
    os.environ.update(DEADMAN_STATE_DIR=sd, DEADMAN_SSH="sh %s" % FAKE, DEADMAN_SSH_TARGETS="tgt-a tgt-b", NTFY_SERVER=RELAY_URL, NTFY_TOPIC="t_test",
                      DEADMAN_DIRECT_URL=DIRECT_URL, DEADMAN_NET_URL=DIRECT_URL + "/", DEADMAN_LOG=os.path.join(sd, "deadman.log"))
    os.environ.update({k: str(v) for k, v in extra.items()})


def reset(name, **extra):
    sd = os.path.join(T, name)
    shutil.rmtree(sd, ignore_errors=True)
    os.makedirs(sd)
    RELAY["posts"].clear(); DIRECT["posts"].clear(); RELAY.update(status=200, action="emergency:sent"); DIRECT["status"] = 200
    open(SSHLOG, "w").close()
    setenv(sd, **extra)
    return sd


def at(D, t):
    os.environ["DEADMAN_NOW"] = str(t)
    with contextlib.redirect_stdout(io.StringIO()):
        return D.run()


def state(sd):
    return json.load(open(os.path.join(sd, "state.json")))


def run_suite(D, label=""):
    """All behavioural scenarios against module D. Returns nothing; counts via ok()."""
    # ---- S1 healthy: nothing happens
    sd = reset("s1")
    scenario(probe=probe(BASE_T))
    r = at(D, BASE_T)
    ok(label + "S1 healthy box: result ok, no post, no miss", r == "ok" and not RELAY["posts"] and not DIRECT["posts"] and not state(sd)["misses"].get("stalled"), r)

    # ---- S2 stalled: debounce 2, ONE alert per episode, ONE recovery
    sd = reset("s2")
    scenario(probe=probe(BASE_T, last_age=1900, rep_age=1900))
    at(D, BASE_T)
    ok(label + "S2 first miss: no alert (debounce)", not RELAY["posts"] and state(sd)["misses"]["stalled"] == 1)
    scenario(probe=probe(BASE_T + 600, last_age=2500, rep_age=2500))
    r = at(D, BASE_T + 600)
    ok(label + "S2 second consecutive miss: ONE alert through the RELAY", len(RELAY["posts"]) == 1 and not DIRECT["posts"], r)
    a = RELAY["posts"][0] if RELAY["posts"] else {}
    ok(label + "S2 alert is urgent + X-Ovn-Level emergency on the configured topic, names 'stalled' and the age", a.get("prio") == "urgent" and a.get("level") == "emergency" and a.get("path") == "/t_test" and "stalled" in a.get("title", "").lower() and "41 min" in a.get("body", ""), a)
    scenario(probe=probe(BASE_T + 1200, last_age=3100, rep_age=3100))
    at(D, BASE_T + 1200)
    at(D, BASE_T + 1800)
    ok(label + "S2 still bad: NO second alert (one per episode)", len(RELAY["posts"]) == 1 and not DIRECT["posts"])
    scenario(probe=probe(BASE_T + 2400))
    r = at(D, BASE_T + 2400)
    ok(label + "S2 recovered: ONE recovery message via the relay, priority default, no emergency level", len(RELAY["posts"]) == 2 and RELAY["posts"][1]["prio"] == "default" and not RELAY["posts"][1]["level"] and "recover" in RELAY["posts"][1]["title"].lower(), RELAY["posts"][-1:])
    ok(label + "S2 recovered: state forgets the episode (next outage alerts again)", not state(sd)["alerted"] and not state(sd)["misses"].get("stalled"))
    at(D, BASE_T + 3000)
    ok(label + "S2 healthy afterwards: silent", len(RELAY["posts"]) == 2)

    # ---- S3 the live false positive: an exhausted-idle fleet writes no outcomes rows but one report per pass
    sd = reset("s3")
    scenario(probe=probe(BASE_T, last_age=3000, rep_age=70))
    at(D, BASE_T); r = at(D, BASE_T + 600)
    scenario(probe=probe(BASE_T + 600, last_age=3600, rep_age=70))
    r = at(D, BASE_T + 600)
    ok(label + "S3 outcomes 1h old but a run report 70 s old (idle fleet): NOT stalled, no alert", not RELAY["posts"] and not state(sd)["misses"].get("stalled"), r)
    scenario(probe=probe(BASE_T + 1200, last_age=3600, rep_age=1500))
    at(D, BASE_T + 1200); at(D, BASE_T + 1800)
    ok(label + "S3 both outcomes AND reports stale -> alert", len(RELAY["posts"]) == 1)

    # ---- S4 paused / inactive / boot grace / llm
    sd = reset("s4")
    scenario(probe=probe(BASE_T, last_age=9000, rep_age=9000, paused="1"))
    at(D, BASE_T); at(D, BASE_T + 600); at(D, BASE_T + 1200)
    ok(label + "S4 paused queue (state/PAUSED): silent even when nothing is recorded", not RELAY["posts"])
    scenario(probe=probe(BASE_T + 1800, unit="inactive", paused="1"))
    at(D, BASE_T + 1800); at(D, BASE_T + 2400)
    ok(label + "S4 unit inactive but paused: silent", not RELAY["posts"])
    sd = reset("s4b")
    scenario(probe=probe(BASE_T, unit="failed"))
    at(D, BASE_T); at(D, BASE_T + 600)
    ok(label + "S4 unit failed, not paused: 'Queue service is DOWN' after 2 misses", len(RELAY["posts"]) == 1 and "queue service" in RELAY["posts"][0]["title"].lower(), RELAY["posts"])
    sd = reset("s4c")
    scenario(probe=probe(BASE_T, last_age=9000, rep_age=9000, up=120, llm="000"))
    at(D, BASE_T); at(D, BASE_T + 600)
    ok(label + "S4 first 10 min of uptime: no stalled/llm verdict yet (loop still starting)", not RELAY["posts"])
    sd = reset("s4d")
    scenario(probe=probe(BASE_T, llm="000"))
    at(D, BASE_T); at(D, BASE_T + 600)
    ok(label + "S4 LiteLLM not answering 200 for 2 probes: ONE alert", len(RELAY["posts"]) == 1 and "model" in RELAY["posts"][0]["title"].lower(), RELAY["posts"])

    # ---- S5 unreachable: the relay lives on the box, so the alert goes DIRECT; recovery follows the same channel
    sd = reset("s5")
    scenario(down=True)
    r1 = at(D, BASE_T)
    ok(label + "S5 first ssh failure: no alert", not DIRECT["posts"] and not RELAY["posts"], r1)
    r2 = at(D, BASE_T + 600)
    ok(label + "S5 second failure: ONE direct post; the relay (on the dead box) is never contacted", len(DIRECT["posts"]) == 1 and not RELAY["posts"], r2)
    d = DIRECT["posts"][0] if DIRECT["posts"] else {}
    ok(label + "S5 direct alert is urgent and says the box is DOWN", d.get("prio") == "urgent" and "DOWN" in d.get("title", ""), d)
    ok(label + "S5 both addresses were tried each run (Tailscale then LAN)", len([l for l in open(SSHLOG) if "tgt-a" in l]) >= 2 and len([l for l in open(SSHLOG) if "tgt-b" in l]) >= 2)
    for i in range(2, 8):
        at(D, BASE_T + 600 * i)
    ok(label + "S5 an hour of continued outage: still exactly ONE alert (no storm)", len(DIRECT["posts"]) == 1)
    scenario(probe=probe(BASE_T + 6000, up=1500))
    r = at(D, BASE_T + 6000)
    ok(label + "S5 box back: ONE recovery sent direct (the alert went direct), names the uptime and an unclean reboot", len(DIRECT["posts"]) == 2 and "recovered" in DIRECT["posts"][1]["title"].lower() and "25 min" in DIRECT["posts"][1]["body"] and "unclean" in DIRECT["posts"][1]["body"], DIRECT["posts"][-1:])
    ok(label + "S5 recovery does not use the relay", not RELAY["posts"])
    ok(label + "S5 state cleared after recovery", not state(sd)["alerted"])

    # ---- S6 Mac offline: ssh fails AND the Mac has no internet -> not the box's fault, no miss, no alert
    sd = reset("s6", DEADMAN_NET_URL=CLOSED + "/")
    scenario(down=True)
    rs = [at(D, BASE_T + 600 * i) for i in range(6)]
    ok(label + "S6 Mac offline: result mac-offline, misses never counted, nothing sent", all(x == "mac-offline" for x in rs) and not state(sd)["misses"] and not DIRECT["posts"] and not RELAY["posts"], rs)
    os.environ["DEADMAN_NET_URL"] = DIRECT_URL + "/"
    at(D, BASE_T + 4000)
    ok(label + "S6 Mac back online with the box still down: counting starts fresh (1 miss, no alert yet)", state(sd)["misses"].get("unreachable") == 1 and not DIRECT["posts"])

    # ---- S7 a gap (the Mac slept) resets the misses
    sd = reset("s7")
    scenario(probe=probe(BASE_T, last_age=2000, rep_age=2000))
    at(D, BASE_T)
    scenario(probe=probe(BASE_T + 10800, last_age=2000, rep_age=2000))
    at(D, BASE_T + 10800)
    ok(label + "S7 3 h gap between runs: misses restart at 1 (no alert from 'stale' evidence)", not RELAY["posts"] and state(sd)["misses"]["stalled"] == 1)

    # ---- S8 relay trouble: fall back to direct, relay-handled answers are final
    sd = reset("s8")
    RELAY["status"] = 500
    scenario(probe=probe(BASE_T, last_age=2000, rep_age=2000)); at(D, BASE_T); at(D, BASE_T + 600)
    ok(label + "S8 relay answers HTTP 500: the alert falls back to ONE direct post", len(DIRECT["posts"]) == 1 and state(sd)["alerted"].get("stalled", {}).get("via") == "direct", (DIRECT["posts"], state(sd)))
    sd = reset("s8b")
    RELAY["action"] = "emergency:failed"
    scenario(probe=probe(BASE_T, last_age=2000, rep_age=2000)); at(D, BASE_T); at(D, BASE_T + 600)
    ok(label + "S8 relay reports emergency:failed (its own upstream push failed): fall back to direct", len(DIRECT["posts"]) == 1)
    sd = reset("s8b2")
    RELAY["action"] = "emergency:capped"
    scenario(probe=probe(BASE_T, last_age=2000, rep_age=2000)); at(D, BASE_T); at(D, BASE_T + 600)
    ok(label + "S8 relay says capped (daily cap: the alert is only buffered, never pushed): fall back to ONE direct post, recorded as direct", len(DIRECT["posts"]) == 1 and state(sd)["alerted"].get("stalled", {}).get("via") == "direct", (DIRECT["posts"], state(sd)))
    sd = reset("s8c")
    RELAY["action"] = "emergency:deduped"
    scenario(probe=probe(BASE_T, last_age=2000, rep_age=2000)); at(D, BASE_T); at(D, BASE_T + 600)
    ok(label + "S8 relay says deduped (it already pushed this title): handled, NO direct post, episode recorded", not DIRECT["posts"] and "stalled" in state(sd)["alerted"])
    sd = reset("s8d", NTFY_SERVER=CLOSED)
    scenario(probe=probe(BASE_T, last_age=2000, rep_age=2000)); at(D, BASE_T); at(D, BASE_T + 600)
    ok(label + "S8 relay unreachable: direct fallback", len(DIRECT["posts"]) == 1)

    # ---- S9 direct limiter
    sd = reset("s9", DEADMAN_DIRECT_DAILY_CAP=1)
    scenario(down=True); at(D, BASE_T); at(D, BASE_T + 600)
    scenario(probe=probe(BASE_T + 1200, up=300)); at(D, BASE_T + 1200)       # recovery: direct #2 is over the cap of 1
    ok(label + "S9 daily direct cap 1: the recovery is suppressed (limited) instead of storming", len(DIRECT["posts"]) == 1 and not state(sd)["alerted"], DIRECT["posts"])
    sd = reset("s9b", DEADMAN_REMIND_S=3600, DEADMAN_DIRECT_COOLDOWN_S=10800)
    scenario(down=True)
    for i in range(0, 8):
        at(D, BASE_T + 600 * i)
    ok(label + "S9 reminder due after 1 h but the per-kind direct cooldown (3 h) holds it back", len(DIRECT["posts"]) == 1, len(DIRECT["posts"]))
    sd = reset("s9c", DEADMAN_REMIND_S=3600, DEADMAN_DIRECT_COOLDOWN_S=60)
    scenario(down=True)
    for i in range(0, 8):
        at(D, BASE_T + 600 * i)
    ok(label + "S9 with a short cooldown the 1 h reminder IS sent (2 posts in 70 min)", len(DIRECT["posts"]) == 2, len(DIRECT["posts"]))

    # ---- S10 undeliverable: not marked alerted, retried next run
    sd = reset("s10", NTFY_SERVER=CLOSED, DEADMAN_DIRECT_URL=CLOSED)
    scenario(probe=probe(BASE_T, last_age=2000, rep_age=2000)); at(D, BASE_T); r = at(D, BASE_T + 600)
    ok(label + "S10 nothing reachable: episode NOT recorded as alerted", "failed" in r and not state(sd)["alerted"], r)
    os.environ["DEADMAN_DIRECT_URL"] = DIRECT_URL
    at(D, BASE_T + 1200)
    ok(label + "S10 delivery works again: the alert is retried and sent once", len(DIRECT["posts"]) == 1 and "stalled" in state(sd)["alerted"])

    # ---- S11 ssh garbage / one bad target
    sd = reset("s11")
    scenario(garbage=True)
    r = at(D, BASE_T)
    ok(label + "S11 ssh succeeds but prints no probe output: treated as unreachable (never as healthy)", state(sd)["misses"].get("unreachable") == 1, r)
    sd = reset("s11b")
    scenario(fail_targets=["tgt-a"], probe=probe(BASE_T))
    r = at(D, BASE_T)
    ok(label + "S11 first address dead, second answers: box is reachable and healthy", r == "ok" and not state(sd)["misses"].get("unreachable"), r)

    # ---- S12 kill switch / dry run
    sd = reset("s12", DEADMAN_DISABLE=1)
    scenario(down=True)
    r = at(D, BASE_T)
    ok(label + "S12 DEADMAN_DISABLE=1: does nothing, never even calls ssh", r == "disabled" and os.path.getsize(SSHLOG) == 0)
    sd = reset("s12b")
    scenario(probe=probe(BASE_T, last_age=2000, rep_age=2000))
    at(D, BASE_T)
    os.environ["DEADMAN_NOW"] = str(BASE_T + 600)
    with contextlib.redirect_stdout(io.StringIO()):
        r = D.run(dry=True)
    ok(label + "S12 --dry-run: would alert but posts nothing and does not persist state", not RELAY["posts"] and not DIRECT["posts"] and state(sd)["misses"]["stalled"] == 1, r)


# ================================================================== real module
D = shimmed(load(SRC, "box_deadman_under_test"))
run_suite(D)

# ---- pure unit checks of evaluate()
os.environ.pop("DEADMAN_STALE_S", None)
bad = D.evaluate(probe(BASE_T, last_age=1300, rep_age=1300))
ok("evaluate: 1300 s without any heartbeat is stalled", "stalled" in bad)
ok("evaluate: 1100 s is not (threshold is 1200 s)", not D.evaluate(probe(BASE_T, last_age=1100, rep_age=1100)))
ok("evaluate: 'activating' counts as running (crash-loop with no outcomes is caught)", "stalled" in D.evaluate(probe(BASE_T, last_age=4000, rep_age=4000, unit="activating")))
ok("evaluate: newest of last/mtime/rep wins", not D.evaluate({"now": BASE_T, "up": 99999, "unit": "active", "paused": "0", "last": ISO(BASE_T - 5000), "mtime": BASE_T - 5000, "rep": BASE_T - 30, "llm": "200"}))
ok("evaluate: no heartbeat data at all while the unit runs is stalled", "stalled" in D.evaluate({"now": BASE_T, "up": 99999, "unit": "active", "paused": "0", "llm": "200"}))
ok("evaluate: llm 000 and 503 are llm_down, 200 is healthy", "llm_down" in D.evaluate(probe(BASE_T, llm="000")) and "llm_down" in D.evaluate(probe(BASE_T, llm="503")) and not D.evaluate(probe(BASE_T)))
ok("evaluate: no ~/overnight-queue dir is stalled", "stalled" in D.evaluate({"nodir": "1"}))
os.environ["DEADMAN_STALE_S"] = "100"
ok("evaluate: DEADMAN_STALE_S is honoured", "stalled" in D.evaluate(probe(BASE_T, last_age=200, rep_age=200)))
os.environ.pop("DEADMAN_STALE_S", None)

# ---- the log rotates (one line per 10 min must not grow forever)
sd = reset("logrot", DEADMAN_LOG_MAX=300)
scenario(probe=probe(BASE_T))
for i in range(12):
    at(D, BASE_T + 600 * i)
lg = os.path.join(sd, "deadman.log")
ok("log: rotated to deadman.log.1 once it passes DEADMAN_LOG_MAX, current log stays small", os.path.exists(lg + ".1") and os.path.getsize(lg) < 1200, (os.path.exists(lg + ".1"), os.path.getsize(lg)))

# ---- test-suite guard: a direct post to an 'ntfy.sh' URL is swallowed + logged when OVN_NTFY_GUARD_LOG is set (the test uses a dead local address that merely contains the text)
sd = reset("guard", DEADMAN_DIRECT_URL="https://127.0.0.1:1/ntfy.sh", NTFY_SERVER=CLOSED, OVN_NTFY_GUARD_LOG=os.path.join(T, "guard.log"))
scenario(down=True)
at(D, BASE_T); at(D, BASE_T + 600)
ok("guard: with OVN_NTFY_GUARD_LOG set the real ntfy.sh is never contacted, the attempt is logged", os.path.exists(os.path.join(T, "guard.log")) and "box_deadman" in open(os.path.join(T, "guard.log")).read())

# ---- the real PROBE snippet, run through sh against a fake $HOME/overnight-queue
fh = os.path.join(T, "home")
os.makedirs(os.path.join(fh, "overnight-queue", "state"))
os.makedirs(os.path.join(fh, "overnight-queue", "reports"))
open(os.path.join(fh, "overnight-queue", "state", "outcomes.jsonl"), "w").write('{"ts":"2026-10-10T12:46:54Z","repo":"x"}\n{"ts":"2026-10-10T12:48:55Z","repo":"iptv_apps","id":"a"}\n')
open(os.path.join(fh, "overnight-queue", "reports", "20261010-082926.md"), "w").write("# r\n")
r = subprocess.run(["sh", "-c", D.PROBE], capture_output=True, text=True, env=dict(os.environ, HOME=fh), timeout=60)
kv = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
ok("PROBE: runs under plain sh and prints now/paused/last/llm", r.returncode == 0 and {"now", "paused", "last", "llm"} <= set(kv), r.stdout + r.stderr)
ok("PROBE: 'last' is the ts of the NEWEST outcomes row", kv.get("last") == "2026-10-10T12:48:55Z", kv)
ok("PROBE: paused=0 without state/PAUSED, 1 with it", kv.get("paused") == "0")
open(os.path.join(fh, "overnight-queue", "state", "PAUSED"), "w").close()
r2 = subprocess.run(["sh", "-c", D.PROBE], capture_output=True, text=True, env=dict(os.environ, HOME=fh), timeout=60)
ok("PROBE: paused=1 with state/PAUSED", "paused=1" in r2.stdout)
if subprocess.run(["stat", "-c", "%Y", "/"], capture_output=True).returncode == 0:      # GNU stat (the box)
    ok("PROBE: rep= is a numeric mtime of the newest report (GNU stat)", kv.get("rep", "").isdigit(), kv)
    ok("PROBE: up= comes from /proc/uptime on Linux", (not os.path.exists("/proc/uptime")) or kv.get("up", "").isdigit(), kv)
r3 = subprocess.run(["sh", "-c", D.PROBE], capture_output=True, text=True, env=dict(os.environ, HOME=os.path.join(T, "nohome")), timeout=60)
ok("PROBE: a box without ~/overnight-queue answers nodir=1 (not an ssh failure)", "nodir=1" in r3.stdout)

# ---- real ssh process path: probe_box spawns `sh fake_ssh.sh` for real (no shim): healthy, then a stalled episode alerts after 2 runs
Dreal = load(SRC, "box_deadman_real_spawn")
sd = reset("realspawn")
scenario(probe=probe(BASE_T))
ok("real spawn: healthy probe parsed (no alert)", at(Dreal, BASE_T) == "ok" and not RELAY["posts"])
scenario(probe=probe(BASE_T + 600, last_age=3000, rep_age=3000)); at(Dreal, BASE_T + 600)
scenario(probe=probe(BASE_T + 1200, last_age=3600, rep_age=3600)); at(Dreal, BASE_T + 1200)
ok("real spawn: a stalled box alerts through the relay after 2 runs", len(RELAY["posts"]) == 1)
scenario(down=True); sd = reset("realspawn2"); at(Dreal, BASE_T); at(Dreal, BASE_T + 600)
ok("real spawn: ssh exit 255 on both addresses = unreachable -> direct alert", len(DIRECT["posts"]) == 1 and not RELAY["posts"])

# ---- plist (NOT installed anywhere by this change)
if os.path.isfile(PLIST):
    import plistlib
    pl = plistlib.load(open(PLIST, "rb"))
    ok("plist: 10-minute StartInterval, not RunAtLoad, points at box_deadman.py", pl["StartInterval"] == 600 and pl["RunAtLoad"] is False and any(a.endswith("scripts/overnight-queue/scripts/box_deadman.py") for a in pl["ProgramArguments"]))
    ok("plist: NTFY_SERVER is the relay on the box (the same value the other Mac jobs use)", pl["EnvironmentVariables"]["NTFY_SERVER"] == "http://100.79.64.64:8099")
    ok("plist label", pl["Label"] == "com.shrike.box-deadman")
    ok("plist is not installed in ~/Library/LaunchAgents by the code", True)

# ================================================================== mutation proofs: break each rule in a temp copy; the suite must then FAIL
MUT = [
    ("heartbeat ignores run reports (the live false positive)", '    beats = [b for b in (_iso_epoch(p.get("last", "")), _num(p.get("mtime")), _num(p.get("rep"))) if b]', '    beats = [b for b in (_iso_epoch(p.get("last", "")), _num(p.get("mtime"))) if b]'),
    ("no debounce (alert on the first miss)", 'need = int(env_f("DEADMAN_MISSES", 2))', 'need = 1'),
    ("alerts every run (no one-alert-per-episode memory)", '                if a is None or (remind and t - a.get("ts", 0) >= remind):', '                if True:'),
    ("recovery message never sent", '        else:\n            miss[k] = 0\n            if k in alerted:\n                to_recover.append(k)', '        else:\n            miss[k] = 0'),
    ("Mac offline counted as a box miss", '        if not internet_ok():', '        if False:'),
    ("sleep gap does not reset misses", '    if state.get("last_run") and t - state["last_run"] > max_gap:\n        state["misses"].clear()\n    probe, tgt = probe_box()', '    probe, tgt = probe_box()'),
    ("unreachable alert tries the dead relay only (no direct fallback)", '    r = send_direct(state, kind, title, body, prio, tags, level, t)\n    return r, "direct"', '    return "failed", "relay"'),
    ("direct limiter disabled", '    if len(hist) >= env_f("DEADMAN_DIRECT_DAILY_CAP", 8):\n        return False', '    if False:\n        return False'),
    ("paused queue still alerts", '    paused = p.get("paused") == "1"', '    paused = False'),
    ("kill switch ignored", '    if os.environ.get("DEADMAN_DISABLE") == "1":\n        return "disabled"', '    if False:\n        return "disabled"'),
    ("alerted recorded even when delivery failed", '        if res in ("sent", "limited"):\n            state["alerted"][kind] = {"ts": t, "via": ch}', '        if True:\n            state["alerted"][kind] = {"ts": t, "via": ch}'),
    ("relay-reported emergency:failed treated as delivered", '    return not (action.endswith(":failed") or action.endswith(":capped"))', '    return not action.endswith(":capped")'),
    ("relay-reported emergency:capped treated as delivered", '    return not (action.endswith(":failed") or action.endswith(":capped"))', '    return not action.endswith(":failed")'),
    ("log never rotates", '            if os.path.getsize(p) > env_f("DEADMAN_LOG_MAX", 524288):', '            if False:'),
    ("test guard removed (real ntfy.sh reachable under the suite)", '    if "ntfy.sh" in base and os.environ.get("OVN_NTFY_GUARD_LOG"):', '    if False:'),
]
if not SKIP_MUT:
    src = open(SRC).read()
    for label, old, new in MUT:
        if old not in src:
            ok("mutation anchor present: " + label, False, "anchor text not found in box_deadman.py (update the test)")
            continue
        mp = os.path.join(T, "mut_box_deadman.py")
        open(mp, "w").write(src.replace(old, new, 1))
        p0, f0 = P, F
        if os.environ.get("DEADMAN_TEST_VERBOSE") or os.environ.get("VERBOSE_MUT"):
            print("  mutant:", label, file=sys.stderr, flush=True)
        Mmod = shimmed(load(mp, "mut_" + str(abs(hash(label)))))
        guard = os.path.join(T, "guard_mut.log")
        try:
            os.remove(guard)
        except OSError:
            pass
        QUIET = True
        run_suite(Mmod, "[mut] ")
        # the guard scenario lives outside run_suite: run it against the mutant too (the URL is a dead local address that merely CONTAINS 'ntfy.sh': never the real host)
        reset("guardm", DEADMAN_DIRECT_URL="https://127.0.0.1:1/ntfy.sh", NTFY_SERVER=CLOSED, OVN_NTFY_GUARD_LOG=guard)
        scenario(down=True)
        at(Mmod, BASE_T); at(Mmod, BASE_T + 600)
        if label.startswith("test guard") and not os.path.exists(guard):
            F += 1
        if label.startswith("log never rotates"):
            reset("logrotm", DEADMAN_LOG_MAX=300)
            scenario(probe=probe(BASE_T))
            for i in range(12):
                at(Mmod, BASE_T + 600 * i)
            if not os.path.exists(os.path.join(os.environ["DEADMAN_STATE_DIR"], "deadman.log.1")):
                F += 1
        caught = F > f0
        QUIET = False
        P, F = p0, f0          # failures of mutants are EXPECTED: neither their passes nor their failures count toward the suite totals
        ok("mutation CAUGHT by the suite: " + label, caught)
else:
    print("  (mutation section skipped: DEADMAN_SKIP_MUTATION=1)")

shutil.rmtree(T, ignore_errors=True)
print("test_box_deadman: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
