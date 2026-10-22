#!/usr/bin/env python3
"""qa_tool_health.py - gate-tool health sentinel (P1, SHADOW). Read-only: it never installs, repairs, deletes or blocks anything.

Why: the 2026-10-16 box home wipe removed the scanners (bandit, semgrep, gitleaks, pip-audit), mutmut, schemathesis, the staging URLs, qa_creds,
qa_gate_modes.json and the contract-fuzz baseline. Every gate that needed them quietly turned UNVERIFIED (16 of 20 scanner rows) - a PASS-looking
dashboard with no evidence behind it. This sentinel turns that into ONE loud, de-duplicated alert.

  python3 qa/qa_tool_health.py [--no-record] [--enforce-exit] [--json]

Checks (all read-only):
  tools   bandit semgrep gitleaks pip-audit mutmut schemathesis mypy ruff docker flock. Lookup order is the gates' own (gate_scanners.find_tool):
          env QA_TOOL_<NAME> > ~/qa-venv/bin > ~/qa-tools/bin > PATH > <OVN_DIR>/qa-tools/.venv/bin (ops/qa_tools_install.sh; LAST, so installing it never
          changes which tool an already-working gate uses - it only fills a gap).
          status ok | missing | broken (a script whose #! interpreter no longer exists, or a tool whose `<tool> --version` probe dies with an exec/import/shared-library
          error: wrong-arch binary, wiped site-packages, python upgrade that broke the wheel). The probe runs only the tool's own --version (20 s cap, a timeout or a
          plain non-zero exit is NOT broken); OVN_QA_TOOL_HEALTH_PROBE=0 turns it off.
  state   state/staging_url_<repo> for every repo in qa/staging_smoke.conf; state/qa_creds/<repo>.json (must exist, parse, hold email+password, and be mode 600:
          any group/other bit is flagged) for repos whose smoke login has no auto_register AND no fallback (a missing file is fine when the conf declares a repo_default, or the email_env/password_env
          pair is set: staging_smoke resolves env > file > repo_default); a file that exists is still checked. state/qa_gate_modes.json: only a CORRUPT file is flagged
          (missing = every gate in its default shadow mode, legitimate on a fresh install);
          state/qa_shadow/contract_fuzz_baseline_<repo>.json for the contract-fuzz repos.
  cron    every QA job script must appear in a non-comment line of the crontab (`crontab -l`, or the file in OVN_QA_CRONTAB_FILE).

Output: ONE row per run in state/qa_shadow/tool_health.jsonl (verdict PASS when nothing is wrong, FLAG otherwise; FAIL instead of FLAG only in enforce mode)
and one JSON line on stdout. Exit 0 always; with --enforce-exit exit 1 only when OVN_QA_TOOL_HEALTH=enforce and something is wrong. Nothing else reads the
verdict: the sentinel only reports, it is never a gate of any other gate.

Alert (state/alerts.log, the path every other QA monitor uses): a finding must be present for 2+ consecutive sentinel passes (OVN_QA_TOOL_HEALTH_MIN_PASSES) before
it alerts, so a tool mid-upgrade does not page. All findings that crossed the bar in the same pass go in ONE bounded line (finding keys, capped at ~300 chars, + a pointer to the jsonl). The same finding is not re-announced until
OVN_QA_TOOL_HEALTH_REALERT_H hours (default 24; 0 = never) have passed; a finding that clears is forgotten, so its next outage alerts at once.
Pass counters + alert times live in state/tool_health_state.json (unique temp file + os.replace, under an flock on state/tool_health_state.lock, so overlapping runs
cannot clobber it). While a finding is past the bar, every run also writes a high-priority note to state/notify_notes.jsonl (like qa_block_watch) so the ONE hourly update
(scripts/ovn_notify.py) lists it; OVN_QA_TOOL_HEALTH_NOTE=0 disables. tool_health.jsonl rows are compact and the file is trimmed to the last OVN_QA_TOOL_HEALTH_MAX_ROWS (1500; 0 = never).
This sentinel DETECTS only. Restoring state (staging_url_*, qa_creds, fuzz baseline, tools) stays a deliberate manual step: see qa_tool_health.README.md.

Flag: OVN_QA_TOOL_HEALTH=off|shadow|enforce (default shadow; env > state/qa_gate_modes.json > shadow, like every QA gate). off = prints NA, records and alerts nothing.
Other env: OVN_QA_TOOL_HEALTH_SKIP="docker,flock" (tool names to ignore), OVN_QA_TOOL_HEALTH_NOW (epoch, tests), OVN_QA_CRONTAB_FILE.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

GATE = "tool_health"

# tool -> gates that go UNVERIFIED without it ("advisory" tools are reported too: a missing ruff/mypy silently drops advisory lint)
TOOLS = {
    "bandit": ("gate_scanners",),
    "semgrep": ("gate_scanners",),
    "gitleaks": ("gate_scanners",),
    "pip-audit": ("gate_scanners",),
    "mutmut": ("mutation",),
    "schemathesis": ("contract_fuzz",),
    "mypy": ("gate_scanners(advisory)",),
    "ruff": ("gate_scanners",),
    "docker": ("web_e2e(advisory)",),
    "flock": ("cron wrappers",),
}

# QA cron jobs: script basename that must be in a live (non-comment) crontab line -> what it feeds
CRON_JOBS = {
    "qa_ledger_cron.sh": "S12 ledger",
    "manual_notes_cron.sh": "manual notes ingest",
    "qa_daily_shadow.sh": "daily shadow gates + hourly staging smoke",
    "baseline_refresh_cron.sh": "baseline refresh",
    "qa_block_watch.py": "block watch",
    "staging_e2e_run.sh": "staging e2e run",
    "staging_e2e_ingest.py": "staging e2e ingest",
    "evidence_freshness_check.py": "evidence freshness",
    "contract_fuzz_cron.sh": "contract fuzz (Schemathesis)",
    "qa_tool_health.py": "this sentinel",
}

DEFAULT_FUZZ_REPOS = ("iptv_apps",)


def now_ts():
    v = os.environ.get("OVN_QA_TOOL_HEALTH_NOW")
    try:
        return float(v) if v else time.time()
    except ValueError:
        return time.time()


def _num(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


# ---------------------------------------------------------------- tools
def tool_dirs():
    return [os.path.expanduser("~/qa-venv/bin"), os.path.expanduser("~/qa-tools/bin")]


def venv_dir():
    return os.path.join(qc.ovn_dir(), "qa-tools", ".venv", "bin")


def find_tool(name):
    """Same order as gate_scanners.find_tool: env > ~/qa-venv > ~/qa-tools > PATH > the dedicated install venv (last: it only fills a gap). None when missing."""
    ov = os.environ.get("QA_TOOL_" + name.upper().replace("-", "_"))
    if ov:
        return ov if os.path.exists(ov) else None
    for d in tool_dirs():
        p = os.path.join(d, name)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    w = shutil.which(name)
    if w:
        return w
    p = os.path.join(venv_dir(), name)
    return p if os.path.isfile(p) and os.access(p, os.X_OK) else None


def shebang_broken(path):
    """True when `path` is a script whose #! interpreter does not exist (a venv whose python was removed). Binaries / unreadable files: False."""
    try:
        with open(path, "rb") as f:
            head = f.read(256)
    except OSError:
        return False
    if not head.startswith(b"#!"):
        return False
    line = head.split(b"\n", 1)[0][2:].decode("utf-8", "replace").strip()
    parts = line.split()
    if not parts:
        return False
    interp = parts[0]
    if os.path.basename(interp) == "env":
        names = [p for p in parts[1:] if not p.startswith("-")]
        return not (names and shutil.which(names[0]))
    return not os.path.exists(interp)


BAD_MARKERS = ("Traceback (most recent call last)", "ModuleNotFoundError", "ImportError", "Exec format error", "bad CPU type", "cannot execute binary file",
               "cannot open shared object", "error while loading shared libraries", "Library not loaded", "dyld:")


# `mutmut --version` (mutmut 3.x has no version flag) imports everything, then dies with this FileNotFoundError when run outside a project. That is a HEALTHY wheel: the first real
# install (2026-10-18, ops/install_qa_tools.sh) made the sentinel call it "broken" forever. Only this exact config message is excused; any other traceback still counts.
BENIGN_MARKERS = ("Could not figure out where the code to mutate is",)


def probe_broken(path):
    """None when `path --version` looks runnable; else a short reason. ONLY an OSError at exec (wrong arch / not executable) or a non-zero exit whose output
    carries an import / exec / shared-library failure counts. A timeout or a plain non-zero exit is NOT broken (some tools reject --version)."""
    if os.environ.get("OVN_QA_TOOL_HEALTH_PROBE", "1") == "0":
        return None
    env = dict(os.environ, SEMGREP_SEND_METRICS="off", SEMGREP_ENABLE_VERSION_CHECK="0", PYTHONDONTWRITEBYTECODE="1")
    try:
        r = subprocess.run([path, "--version"], capture_output=True, text=True, errors="replace", timeout=_num("OVN_QA_TOOL_HEALTH_PROBE_TIMEOUT_S", 20),
                           stdin=subprocess.DEVNULL, env=env)
    except subprocess.TimeoutExpired:
        return None
    except OSError as ex:
        return "cannot execute: %s" % (ex.strerror or type(ex).__name__)
    except subprocess.SubprocessError:
        return None
    out = ((r.stdout or "") + (r.stderr or ""))[:8000]
    if r.returncode != 0:
        if any(b in out for b in BENIGN_MARKERS) and not any(m in out for m in BAD_MARKERS if m != "Traceback (most recent call last)"):
            return None
        for m in BAD_MARKERS:
            if m in out:
                return "--version fails (%s)" % m
    return None


def check_tools(skip):
    out = {}
    for name, gates in TOOLS.items():
        if name in skip:
            out[name] = {"status": "skipped", "gates": list(gates)}
            continue
        p = find_tool(name)
        if not p:
            out[name] = {"status": "missing", "gates": list(gates)}
        elif shebang_broken(p):
            out[name] = {"status": "broken", "path": p, "gates": list(gates), "reason": "its #! interpreter is gone"}
        else:
            why = probe_broken(p)
            if why:
                out[name] = {"status": "broken", "path": p, "gates": list(gates), "reason": why}
            else:
                out[name] = {"status": "ok", "path": p}
    return out


# ---------------------------------------------------------------- state
def smoke_conf():
    try:
        with open(os.path.join(HERE, "staging_smoke.conf")) as f:
            return (json.load(f).get("repos") or {})
    except (OSError, ValueError):
        return {}


def fuzz_repos():
    try:
        import contract_fuzz  # noqa: WPS433 - read the repo table only
        r = tuple(getattr(contract_fuzz, "REPOS", {}).keys())
        if r:
            return r
    except Exception:  # noqa: BLE001
        pass
    return DEFAULT_FUZZ_REPOS


def fuzz_dark_item():
    """The nightly contract fuzz is installed but has SKIPPED its last OVN_QA_FUZZ_DARK_RUNS (default 3) runs on load (logs/contract_fuzz.log), so the gate is dark and the
    cron line alone says nothing about that. -> one finding item or None. Only a recent log counts (a log from an off/removed cron is not a live gate). Advisory like every row here."""
    n = int(_num("OVN_QA_FUZZ_DARK_RUNS", 3))
    if n <= 0:
        return None
    p = os.path.join(qc.ovn_dir(), "logs", "contract_fuzz.log")
    try:
        if now_ts() - os.path.getmtime(p) > _num("OVN_QA_FUZZ_DARK_MAX_AGE_H", 96) * 3600:
            return None
        with open(p, errors="replace") as f:
            lines = [ln for ln in f.read().splitlines()[-400:] if " contract_fuzz: " in ln]
    except OSError:
        return None
    last = lines[-n:]
    if len(last) < n or not all("skipped (1-min load average" in ln for ln in last):
        return None
    return {"key": "state:contract_fuzz_dark", "gate": "contract_fuzz",
            "problem": "the last %d nightly contract fuzz runs were all SKIPPED on box load (logs/contract_fuzz.log: %s); the gate has produced no row. Raise OVN_FUZZ_LOAD_MAX or move the cron slot" % (n, last[-1][:160])}


def check_state():
    """-> list of {key, gate, problem, path} (empty list = all present and sane)."""
    sd = qc.state_dir()
    items = []
    conf = smoke_conf()
    for repo in sorted(conf):
        p = os.path.join(sd, "staging_url_" + repo)
        try:
            with open(p) as f:
                ok = bool(f.read().split())
        except OSError:
            ok = False
        if not ok:
            items.append({"key": "state:staging_url_" + repo, "gate": "staging_smoke", "problem": "state/staging_url_%s missing or empty" % repo})
        login = conf[repo].get("login") or {}
        creds = login.get("creds") or {}
        if creds and "auto_register" not in creds:
            name = creds.get("file", repo)
            cp = os.path.join(sd, "qa_creds", name + ".json")
            # staging_smoke resolves env > file > repo_default: the file is only REQUIRED when neither fallback exists
            ee, pe = creds.get("email_env"), creds.get("password_env")
            optional = bool(creds.get("repo_default")) or bool(ee and pe and os.environ.get(ee) and os.environ.get(pe))
            try:
                st = os.stat(cp)
            except OSError:
                if optional:
                    continue
                items.append({"key": "state:qa_creds_" + name, "gate": "staging_smoke/staging_e2e", "problem": "state/qa_creds/%s.json missing" % name})
                continue
            if st.st_mode & 0o077:
                items.append({"key": "state:qa_creds_mode_" + name, "gate": "staging_smoke/staging_e2e",
                              "problem": "state/qa_creds/%s.json is mode %o (must be 600: group/other can read the staging password)" % (name, st.st_mode & 0o777)})
            try:
                with open(cp) as f:
                    j = json.load(f)
                if not (isinstance(j, dict) and j.get("email") and j.get("password")):
                    raise ValueError("no email/password")
            except (OSError, ValueError):
                items.append({"key": "state:qa_creds_content_" + name, "gate": "staging_smoke/staging_e2e",
                              "problem": "state/qa_creds/%s.json is not a JSON object with email and password" % name})
    gm = os.path.join(sd, qc.GATE_MODES_FILE)
    try:
        with open(gm) as f:
            if not isinstance(json.load(f), dict):
                raise ValueError("not an object")
    except OSError:
        pass    # missing = every gate in its default shadow mode (qc.mode falls back): legitimate until a gate is first flipped, never an alert
    except ValueError:
        items.append({"key": "state:qa_gate_modes", "gate": "all gates", "problem": "state/qa_gate_modes.json is not a valid JSON object (ignored: every gate falls back to shadow)"})
    for repo in fuzz_repos():
        bp = os.path.join(sd, "qa_shadow", "contract_fuzz_baseline_%s.json" % repo)
        if not os.path.isfile(bp):
            items.append({"key": "state:contract_fuzz_baseline_" + repo, "gate": "contract_fuzz",
                          "problem": "state/qa_shadow/contract_fuzz_baseline_%s.json missing (written only by contract_fuzz.py --accept-baseline)" % repo})
    dark = fuzz_dark_item()
    if dark:
        items.append(dark)
    return items


# ---------------------------------------------------------------- cron
def read_crontab():
    """-> (text or None, source). None = could not read (then the cron check is skipped, never reported as 'missing')."""
    f = os.environ.get("OVN_QA_CRONTAB_FILE")
    if f:
        try:
            with open(f) as fh:
                return fh.read(), "file"
        except OSError:
            return None, "file-unreadable"
    exe = shutil.which("crontab")
    if not exe:
        return None, "no-crontab-binary"
    try:
        r = subprocess.run([exe, "-l"], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None, "crontab-error"
    if r.returncode == 0:
        return r.stdout, "crontab -l"
    if "no crontab" in (r.stderr or "").lower():
        return "", "crontab -l (empty)"
    return None, "crontab-error"


def check_cron():
    text, src = read_crontab()
    if text is None:
        return [], src
    live = [ln for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
    items = []
    for script, what in CRON_JOBS.items():
        if not any(re.search(r"(^|[\s/])" + re.escape(script) + r"(\s|$|[;&|'\"])", ln) for ln in live):
            items.append({"key": "cron:" + script, "gate": what, "problem": "no live crontab line runs %s (%s)" % (script, what)})
    return items, src


# ---------------------------------------------------------------- findings, streaks, alert
def findings_of(tools, state_items, cron_items):
    out = []
    for name, t in sorted(tools.items()):
        if t["status"] in ("missing", "broken"):
            out.append({"key": "tool:" + name, "gate": ",".join(t["gates"]),
                        "problem": "%s %s (UNVERIFIED for: %s)" % (name, "not installed" if t["status"] == "missing" else "is broken (%s)" % t.get("reason", "unrunnable"), ", ".join(t["gates"]))})
    return out + state_items + cron_items


def state_file():
    return os.path.join(qc.state_dir(), "tool_health_state.json")


def load_state():
    try:
        with open(state_file()) as f:
            s = json.load(f)
        if isinstance(s, dict):
            note = s.get("note")
            return {"streak": dict(s.get("streak") or {}), "alerted": dict(s.get("alerted") or {}), "note": dict(note) if isinstance(note, dict) else {}}
    except (OSError, ValueError, AttributeError, TypeError):
        pass
    return {"streak": {}, "alerted": {}, "note": {}}


def _mk_tmp():
    return tempfile.mkstemp(dir=qc.state_dir(), prefix="tool_health_state.", suffix=".tmp")   # unique per process: overlapping runs never share a temp file


def atomic_write(path, text):
    fd, tmp = _mk_tmp() if path == state_file() else tempfile.mkstemp(dir=os.path.dirname(path), prefix=os.path.basename(path) + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)      # our own mkstemp name only
        except OSError:
            pass
        raise


def save_state(s):
    os.makedirs(qc.state_dir(), exist_ok=True)
    atomic_write(state_file(), json.dumps(s, sort_keys=True))


@contextmanager
def state_lock(wait_s=30):
    """flock on state/tool_health_state.lock so a cron run and a manual run serialize their load->update->save. Never hangs a run: after wait_s, or when the
    lock file cannot be opened / flock is unavailable, it proceeds unlocked."""
    fh = None
    try:
        import fcntl
        os.makedirs(qc.state_dir(), exist_ok=True)
        fh = open(os.path.join(qc.state_dir(), "tool_health_state.lock"), "a")
        t0 = time.time()
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.time() - t0 > wait_s:
                    break
                time.sleep(0.05)
    except (ImportError, OSError):
        pass
    try:
        yield
    finally:
        if fh is not None:
            try:
                fh.close()      # releases the lock
            except OSError:
                pass


def bounded_keys(keys, cap=300):
    out, n = "", 0
    for i, k in enumerate(keys):
        piece = (", " if out else "") + k
        if len(out) + len(piece) > cap and out:
            return out + " (+%d more)" % (len(keys) - i)
        out += piece
        n += 1
    return out


def write_note(crossed, min_passes, now=None, last=None):
    """High-priority note for the ONE hourly update (scripts/ovn_notify.py reads state/notify_notes.jsonl).
    2026-10-21: written only when the finding SET changed or OVN_QA_TOOL_HEALTH_NOTE_REPEAT_H (default 24 h) passed since the last note (it was every run = 24 high notes/day
    for the same 5 findings). `last` = the previous {"hash","ts"} record. Returns the record to persist (the findings themselves stay in tool_health.jsonl)."""
    if os.environ.get("OVN_QA_TOOL_HEALTH_NOTE", "1") == "0" or not crossed:
        return {}   # nothing past the bar: forget the hash so a recurrence notes at once
    now = time.time() if now is None else now
    h = hashlib.sha256("\n".join(sorted(f["key"] for f in crossed)).encode()).hexdigest()[:16]
    last = last or {}
    repeat_s = _num("OVN_QA_TOOL_HEALTH_NOTE_REPEAT_H", 24) * 3600
    if last.get("hash") == h and isinstance(last.get("ts"), (int, float)) and (repeat_s <= 0 or now - last["ts"] < repeat_s):
        return last
    title = "QA gate tools unverified: %d finding(s)" % len(crossed)
    text = bounded_keys([f["key"] for f in crossed], 150)
    try:
        with open(os.path.join(qc.state_dir(), "notify_notes.jsonl"), "a") as f:
            f.write(json.dumps({"ts": time.time(), "title": title, "text": text, "prio": "high", "source": "qa_tool_health"}, ensure_ascii=False) + "\n")
    except OSError:
        return last     # not written: retry next run
    return {"hash": h, "ts": now}


def trim_rows():
    """Keep tool_health.jsonl to the last OVN_QA_TOOL_HEALTH_MAX_ROWS rows (0 = never trim). Atomic; never raises."""
    n = int(_num("OVN_QA_TOOL_HEALTH_MAX_ROWS", 1500))
    p = os.path.join(qc.state_dir(), "qa_shadow", GATE + ".jsonl")
    if n <= 0:
        return
    try:
        with state_lock():
            with open(p) as f:
                lines = f.read().splitlines()
            if len(lines) > n:
                atomic_write(p, "\n".join(lines[-n:]) + "\n")
    except (OSError, ValueError):
        pass


def update_and_alert(findings, now):
    """Advance per-finding consecutive-pass counters; write at most ONE alerts.log line. -> (streaks, alerted_keys). Serialized by state_lock()."""
    with state_lock():
        return _update_and_alert(findings, now)


def _update_and_alert(findings, now):
    st = load_state()
    keys = [f["key"] for f in findings]
    streak = {k: int(st["streak"].get(k, 0)) + 1 for k in keys}      # a finding that disappeared is dropped here (forgotten)
    alerted = {k: v for k, v in st["alerted"].items() if k in streak}  # cleared => the next outage alerts at once
    min_passes = int(_num("OVN_QA_TOOL_HEALTH_MIN_PASSES", 2))
    realert_s = _num("OVN_QA_TOOL_HEALTH_REALERT_H", 24) * 3600
    due = []
    for f in findings:
        k = f["key"]
        if streak[k] < min_passes:
            continue
        last = alerted.get(k)
        if isinstance(last, (int, float)) and (realert_s <= 0 or now - last < realert_s):
            continue
        due.append(f)
    if due:
        msg = bounded_keys([f["key"] for f in due])
        line = "[%s] WARN | qa-tool-health | %d QA gate dependenc%s missing/broken for %d+ passes, gates running UNVERIFIED (not PASS): %s | detail: state/qa_shadow/tool_health.jsonl\n" % (
            time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), len(due), "y" if len(due) == 1 else "ies", min_passes, msg.replace("\n", " "))
        os.makedirs(qc.state_dir(), exist_ok=True)
        with open(os.path.join(qc.state_dir(), "alerts.log"), "a") as fh:
            fh.write(line)
        for f in due:               # only after the line is on disk
            alerted[f["key"]] = now
    note = write_note([f for f in findings if streak[f["key"]] >= min_passes], min_passes, now, st.get("note"))
    save_state({"streak": streak, "alerted": alerted, "note": note})
    return streak, [f["key"] for f in due]


# ---------------------------------------------------------------- main
def run(argv):
    m = qc.mode(GATE)
    if m == "off":
        return qc.verdict("NA", GATE, "all", "-", "tool health disabled (OVN_QA_TOOL_HEALTH=off)")
    skip = set(x.strip() for x in os.environ.get("OVN_QA_TOOL_HEALTH_SKIP", "").split(",") if x.strip())
    tools = check_tools(skip)
    state_items = check_state()
    cron_items, cron_src = check_cron()
    findings = findings_of(tools, state_items, cron_items)
    streak, alerted = ({}, [])
    try:
        if "--no-record" not in argv:   # a dry run neither advances the pass counters nor alerts
            streak, alerted = update_and_alert(findings, now_ts())
    except OSError as ex:   # an unwritable state dir must not hide the verdict
        cron_src += " (state not writable: %s)" % type(ex).__name__
    missing_tools = sorted(n for n, t in tools.items() if t["status"] in ("missing", "broken"))
    if findings:
        v = "FAIL" if m == "enforce" else "FLAG"
        parts = []
        if missing_tools:
            parts.append("tools missing/broken: " + ",".join(missing_tools))
        if state_items:
            parts.append("state: " + ",".join(i["key"][6:] for i in state_items))
        if cron_items:
            parts.append("cron: " + ",".join(i["key"][5:] for i in cron_items))
        summary = "%d finding(s); %s" % (len(findings), "; ".join(parts))
    else:
        v, summary = "PASS", "all gate tools, state files and QA cron lines present"
    details = {"tools": tools, "state": state_items, "cron": cron_items, "cron_source": cron_src, "findings": [f["key"] for f in findings],
               "streak": streak, "alerted_now": alerted, "missing_tools": missing_tools}
    return qc.verdict(v, GATE, "all", "-", summary, details)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    argv = [a for a in argv if a != "--json"]   # accepted for symmetry; stdout is always one JSON line
    if qc.mode(GATE) == "off" and "--no-record" not in argv:
        argv.append("--no-record")              # off = records nothing, alerts nothing
    rc = qc.main_guard(GATE, run, argv)
    if "--no-record" not in argv:
        trim_rows()
    # main_guard exits non-zero only for enforce+FAIL+--enforce-exit, which is exactly this gate's contract
    return rc


if __name__ == "__main__":
    sys.exit(main())
