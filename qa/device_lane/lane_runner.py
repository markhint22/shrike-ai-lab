#!/usr/bin/env python3
"""lane_runner.py - run the Chickadee Appium/WebdriverIO specs one by one with retry-once-then-report.

For every spec (node tests/<name>.test.mjs, exit 0 pass / 2 skip / else fail):
  attempt 1 -> if it fails, restart appium when the failure looks like an instrumentation crash, attempt 2.
  final status: pass | flaky (failed once, then passed) | fail (failed twice) | skip | timeout
Artifacts for every FAILED attempt: spec log, logcat dump, screen recording (adb screenrecord chunks), under <out>/<spec>/.
A crash/ANR of the app seen in logcat is reported even when the spec passed (advisory signal).
Advisory by design: the exit code is 0 unless the runner itself is misused. Secrets in spec output are redacted.
stdlib only; runs under python3.12 and the Mac python3.
"""
import argparse
import glob
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import threading
import time

APP_PKG = "com.chickadeestreams.iptv"
CRASH_RE = re.compile(r"FATAL EXCEPTION|ANR in %s|Process: %s, PID|am_crash|am_anr" % (re.escape(APP_PKG), re.escape(APP_PKG)))
APPIUM_CRASH_RE = re.compile(r"instrumentation process is not running|cannot be proxied|socket hang up|ECONNREFUSED|"
                             r"UiAutomator2 server.*(crash|did not start)|A session is either terminated|ECONNRESET", re.I)


def redact_values():
    vals = []
    for k, v in os.environ.items():
        if v and len(v) >= 6 and re.search(r"PASS|TOKEN|SECRET|KEY", k, re.I):
            vals.append(v)
    return vals


# The debug APK logs full OkHttp traffic: Authorization headers and login/token JSON bodies land in logcat. Redact by SHAPE too,
# not only by the known credential values.
SHAPES = [
    (re.compile(r"(?i)(authorization:\s*(?:bearer|basic)\s+)\S+"), r"\1<redacted>"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"), "<redacted-jwt>"),
    (re.compile(r'(?i)("(?:access_token|refresh_token|id_token|token|password|secret|api_key)"\s*:\s*")[^"]*(")'), r"\1<redacted>\2"),
    (re.compile(r"(?i)((?:password|passwd|token|secret)=)[^&\s]+"), r"\1<redacted>"),
]


def redact(text, vals):
    for v in vals:
        text = text.replace(v, "<redacted>")
    for rx, rep in SHAPES:
        text = rx.sub(rep, text)
    return text


class Recorder:
    """Chunked adb screenrecord (the tool caps one file at 180s). Cheap: 540x960 @ 1.5 Mbps."""

    def __init__(self, adb, serial, enabled):
        self.adb, self.serial, self.enabled = adb, serial, enabled
        self.stop_ev = threading.Event()
        self.th = None
        self.chunks = 0
        self.proc = None

    def _loop(self):
        while not self.stop_ev.is_set() and self.chunks < 6:
            remote = "/sdcard/qa_rec_%d.mp4" % self.chunks
            try:
                self.proc = subprocess.Popen([self.adb, "-s", self.serial, "shell", "screenrecord", "--time-limit", "170",
                                              "--bit-rate", "1500000", "--size", "540x960", remote],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.chunks += 1
                while self.proc.poll() is None and not self.stop_ev.is_set():
                    time.sleep(0.5)
            except OSError:
                return

    def start(self):
        if self.enabled:
            self.th = threading.Thread(target=self._loop, daemon=True)
            self.th.start()

    def stop(self):
        if not self.enabled:
            return
        self.stop_ev.set()
        # SIGINT makes screenrecord finalize the mp4 container (kill -9 would leave an unplayable file).
        subprocess.run([self.adb, "-s", self.serial, "shell", "pkill", "-2", "screenrecord"], capture_output=True, timeout=20)
        if self.proc:
            try:
                self.proc.wait(timeout=15)
            except Exception:  # noqa: BLE001
                self.proc.kill()
        if self.th:
            self.th.join(timeout=10)
        time.sleep(1)

    def collect(self, dest_prefix, keep):
        out = []
        for i in range(self.chunks):
            remote = "/sdcard/qa_rec_%d.mp4" % i
            if keep:
                local = "%s.rec%d.mp4" % (dest_prefix, i)
                subprocess.run([self.adb, "-s", self.serial, "pull", remote, local], capture_output=True, timeout=120)
                if os.path.exists(local):
                    out.append(local)
            subprocess.run([self.adb, "-s", self.serial, "shell", "rm", "-f", remote], capture_output=True, timeout=20)
        return out


def adb(a, serial, *args, timeout=60):
    try:
        p = subprocess.run([a, "-s", serial] + list(args), capture_output=True, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (subprocess.TimeoutExpired, OSError) as ex:
        return 124, str(ex)


CURRENT = {"p": None}


def _on_term(signum, frame):  # kill the spec we are running (own session) and leave; the shell wrapper cleans emulator/appium
    p = CURRENT["p"]
    if p is not None:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
    os._exit(0)


def run_attempt(args, spec, n, outdir, vals):
    spec_dir = os.path.join(outdir, spec.replace(".test.mjs", ""))
    os.makedirs(spec_dir, exist_ok=True)
    prefix = os.path.join(spec_dir, "attempt%d" % n)
    adb(args.adb, args.serial, "logcat", "-c")
    adb(args.adb, args.serial, "shell", "am", "force-stop", APP_PKG)
    rec = Recorder(args.adb, args.serial, not args.no_video)
    rec.start()
    t0 = time.time()
    env = dict(os.environ, E2E_DEBUG="1", APPIUM_PORT=str(args.appium_port), APPIUM_HOST="127.0.0.1")
    path = os.path.join("tests", spec) if os.path.exists(os.path.join(args.e2e_dir, "tests", spec)) else spec
    log_text, rc = "", 1
    try:
        p = subprocess.Popen([args.node, path], cwd=args.e2e_dir, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             start_new_session=True)
        CURRENT["p"] = p
        try:
            outb, _ = p.communicate(timeout=args.spec_timeout)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            outb, _ = p.communicate()
            rc = 124
        log_text = outb.decode("utf-8", "replace")
    except OSError as ex:
        rc, log_text = 127, "could not start node: %s" % ex
    secs = round(time.time() - t0, 1)
    rec.stop()
    log_text = redact(log_text, vals)
    status = "pass" if rc == 0 else "skip" if rc == 2 else "timeout" if rc == 124 else "fail"
    # logcat: always scan for app crash/ANR; keep the dump only if something went wrong
    _, lc = adb(args.adb, args.serial, "logcat", "-d", "-v", "threadtime", timeout=90)
    lc = redact(lc, vals)
    crash = bool(CRASH_RE.search(lc))
    keep = status in ("fail", "timeout") or crash
    art = {}
    with open(prefix + ".log", "w") as f:
        f.write(log_text)
    art["log"] = prefix + ".log"
    if keep:
        with open(prefix + ".logcat.txt", "w") as f:
            f.write(lc[-3_000_000:])
        art["logcat"] = prefix + ".logcat.txt"
    vids = rec.collect(prefix, keep and not args.no_video)
    if vids:
        art["video"] = vids
    return {"attempt": n, "rc": rc, "status": status, "seconds": secs, "app_crash_in_logcat": crash,
            "appium_crash_suspected": status in ("fail", "timeout") and bool(APPIUM_CRASH_RE.search(log_text)),
            "last_log_line": (log_text.strip().splitlines() or [""])[-1][:300], "artifacts": art}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--e2e-dir", required=True)
    ap.add_argument("--serial", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--specs", default="all", help="comma list of spec file names, or 'all'")
    ap.add_argument("--retries", type=int, default=1)
    ap.add_argument("--spec-timeout", type=int, default=420)
    ap.add_argument("--adb", default="adb")
    ap.add_argument("--node", default="node")
    ap.add_argument("--appium-port", type=int, default=4733)
    ap.add_argument("--appium-restart-cmd", default="", help="shell command that restarts appium (run when a crash is suspected)")
    ap.add_argument("--no-retry", default="", help="comma list of specs that run once with no retry (quarantined known issues)")
    ap.add_argument("--no-video", action="store_true")
    ap.add_argument("--max-seconds", type=int, default=0, help="stop starting new specs after this many seconds (0 = no budget)")
    args = ap.parse_args()
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGHUP, _on_term)

    tests_dir = os.path.join(args.e2e_dir, "tests")
    if args.specs == "all":
        found = sorted(os.path.basename(p) for p in glob.glob(os.path.join(tests_dir, "*.test.mjs")))
        order = ["login.test.mjs", "navigation.test.mjs", "browse-search.test.mjs", "favorites.test.mjs",
                 "settings.test.mjs", "parental.test.mjs", "playback.test.mjs"]  # same preferred order as the repo's run-all.mjs
        specs = [s for s in order if s in found] + [s for s in found if s not in order]
    else:
        specs = [s if s.endswith(".mjs") else s + ".test.mjs" for s in args.specs.split(",") if s]
    os.makedirs(args.out_dir, exist_ok=True)
    vals = redact_values()
    results, t_start = [], time.time()
    for spec in specs:
        if args.max_seconds and time.time() - t_start > args.max_seconds:
            results.append({"spec": spec, "status": "not_run", "attempts": [], "reason": "time budget exhausted"})
            continue
        attempts = []
        no_retry = set(x for x in args.no_retry.split(",") if x)
        for n in range(1, 2 if spec in no_retry else args.retries + 2):
            a = run_attempt(args, spec, n, args.out_dir, vals)
            attempts.append(a)
            print("[lane] %-34s attempt %d -> %s (%.0fs)" % (spec, n, a["status"], a["seconds"]), file=sys.stderr, flush=True)
            if a["status"] in ("pass", "skip"):
                break
            if a["appium_crash_suspected"] and args.appium_restart_cmd:
                subprocess.run(args.appium_restart_cmd, shell=True, capture_output=True, timeout=120)
        first, last = attempts[0]["status"], attempts[-1]["status"]
        final = "skip" if last == "skip" else "pass" if (last == "pass" and first == "pass") else \
                "flaky" if last == "pass" else ("timeout" if last == "timeout" else "fail")
        results.append({"spec": spec, "status": final, "attempts": attempts,
                        "app_crash_in_logcat": any(a["app_crash_in_logcat"] for a in attempts)})
    counts = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    doc = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "seconds": round(time.time() - t_start, 1),
           "counts": counts, "specs": results}
    with open(os.path.join(args.out_dir, "results.json"), "w") as f:
        json.dump(doc, f, indent=1)
    print(json.dumps({"counts": counts, "seconds": doc["seconds"], "results": os.path.join(args.out_dir, "results.json")}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
