#!/usr/bin/env python3
"""gate_mutation.py - S7: per-RANGE mutation advisory gate (registry key `mutation`; see qa/gate_mutation.README.md).

    python3 qa/gate_mutation.py check --repo R --base B --head H [--paths a.py,dir/] [--service DIR] [--no-record] ...
    python3 qa/gate_mutation.py daily [--repos "r1 r2"] [--hours 24] [--no-record]     # what cron / qa_daily_shadow.sh runs
    python3 qa/gate_mutation.py busy                                                    # prints why a daily pass would be skipped ("" = free)
    python3 qa/gate_mutation.py status                                                  # one JSON line: tooling, guards, last measured heads, recent skips

It promotes qa/spikes/mutation_spike.py (mutmut 3.8, changed functions only) into a registered ADVISORY gate:
  * unit = the merged feature RANGE base..head (never one commit: tests land in later commits), changed function bodies only;
  * hard limits, whatever the caller asks for: wall cap <= 600 s (whole process group killed), nice/ionice, --max-children <= 4,
    at most 10 named survivors;
  * mutmut skips decorated functions (every FastAPI route handler): they are listed in details.skipped_decorated. The experimental
    --unwrap-decorators runs ONLY with OVN_MUT_UNWRAP=1;
  * iptv_apps (full suite over the cap) always runs with test selection by touched module and says UNVERIFIED, with the reason, when
    selection finds nothing or the cap is still hit;
  * exactly one row per range in state/qa_shadow/mutation.jsonl with details.yield = {survivors, killed, mutants, runtime_s, cpu_s};
  * verdicts are PASS | FLAG | UNVERIFIED | NA only. NEVER FAIL, never exit non-zero, never blocks anything.
Mode OVN_QA_MUTATION=off|shadow|enforce (default shadow). `enforce` is a documented NO-OP (there is nothing to enforce: advisory by
design); the row says so. It is NOT run per merge: qa_run_shadow.sh and qa_enforce_run.py skip it (DAILY_ONLY below); it runs from
qa_daily_shadow.sh (full run or --mutation-only) behind a tooling + load guard. run.lock is NOT a guard by default (OVN_MUT_RUN_LOCK=ignore): run_overnight holds
it for its whole lifetime, so honouring it meant the daily pass never ran on the live box. OVN_MUT_RUN_LOCK=skip restores the old "only while the queue is
stopped" policy. Every skipped daily pass / repo is appended to state/qa_gate_skips.jsonl (qa_gate_precision.py verdict-rule shows the count, so a gate that
never runs is visible).
Baseline: a daily range only counts as MEASURED (and only then advances the next base) when its verdict is PASS | FLAG | NA and it was not restricted with --paths.
UNVERIFIED rows (tool missing, wall cap, undecided mutants, red clean run, SIGTERM) are kept for visibility but the next daily pass re-covers their commits.
Budget: a repo is started only when the remaining daily budget >= its wall cap + OVN_MUT_MARGIN_S (default 200), so the pass stays inside OVN_MUT_DAILY_BUDGET_S.
On SIGTERM (qa_timeout.py with QA_TIMEOUT_TERM_GRACE_S) the in-flight mutmut process group is killed, the worktree removed and an UNVERIFIED row written.
"""
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

GATE = "mutation"
DAILY_ONLY = ("mutation",)          # gate_*.py names that the per-merge runner / enforce runner must never invoke
CAP_MAX = 600                       # seconds, spike-measured limit
CHILDREN_MAX = 4
SURVIVORS_MAX = 10
DEFAULT_SELECT_REPOS = "iptv_apps"  # full suite does not fit the cap (spike: stats pass alone 552-576 s)
DEFAULT_DAILY_REPOS = "billwatch gitlark iptv_apps test-automation-agent"
VALID = ("PASS", "FLAG", "UNVERIFIED", "NA")
MEASURED = ("PASS", "FLAG", "NA")   # verdicts that mean "this range was really looked at"; UNVERIFIED never advances the daily baseline
RUN_SOURCE = "manual"               # "daily" while daily() drives check(): only daily rows advance the baseline
TERMINATED = False                  # set by the SIGTERM path; daily() stops starting repos


def load_spike():
    path = os.path.join(HERE, "spikes", "mutation_spike.py")
    spec = importlib.util.spec_from_file_location("mutation_spike_impl", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.GATE = GATE                  # the spike builds its verdicts with this module global: rows land under key `mutation`
    return mod


def _int(v, default, lo, hi):
    try:
        n = int(v)
    except (TypeError, ValueError):
        n = default
    return max(lo, min(hi, n))


def build_argv(argv, repo):
    """Spike argv with the limits clamped and the experimental / selection switches decided by env + repo, not by the caller."""
    keep, i = [], 0
    value_opts = ("--cap", "--max-children", "--survivors")
    while i < len(argv):
        a = argv[i]
        if a in value_opts and i + 1 < len(argv):
            i += 2
            continue
        if a in ("--unwrap-decorators", "--select-tests", "--require-selection"):
            i += 1
            continue
        keep.append(a)
        i += 1
    vals = {}
    for k, d, hi in (("--cap", CAP_MAX, CAP_MAX), ("--max-children", CHILDREN_MAX, CHILDREN_MAX), ("--survivors", SURVIVORS_MAX, SURVIVORS_MAX)):
        if k in argv and argv.index(k) + 1 < len(argv):
            vals[k] = _int(argv[argv.index(k) + 1], d, 1, hi)
        else:
            vals[k] = d
    env_cap = os.environ.get("OVN_MUT_CAP_S")
    if env_cap:
        vals["--cap"] = _int(env_cap, CAP_MAX, 30, vals["--cap"])
    for k, v in vals.items():
        keep += [k, str(v)]
    if os.environ.get("OVN_MUT_UNWRAP") == "1":
        keep.append("--unwrap-decorators")
    sel = os.environ.get("OVN_MUT_SELECT_REPOS", DEFAULT_SELECT_REPOS).split()
    if repo in sel:
        keep += ["--select-tests", "--require-selection"]
    return keep, vals


def opt(argv, name, default=""):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def finish(res, argv, vals, t0):
    """Normalize the spike's result into the gate contract (never FAIL, yield block, skipped_decorated always present)."""
    det = res.setdefault("details", {})
    if res.get("verdict") not in VALID:
        res["summary"] = ("mapped %s -> FLAG: " % res.get("verdict")) + res.get("summary", "")
        res["verdict"] = "FLAG"
    counts = det.get("counts") or {}
    killed = sum(counts.get(k, 0) for k in ("killed", "caught_by_typecheck", "timeout", "crashed"))   # timeout/crash = detected, as mutmut counts them
    runtime = round(time.time() - t0, 1)
    det["skipped_decorated"] = list(det.get("skipped_decorated") or [])
    det["unwrap_decorators"] = os.environ.get("OVN_MUT_UNWRAP") == "1"
    det["limits"] = {"cap_s": vals.get("--cap"), "max_children": vals.get("--max-children"), "survivors_shown_max": vals.get("--survivors")}
    partial = bool(opt(argv, "--paths"))
    det["range"] = {"base": opt(argv, "--base"), "head": opt(argv, "--head"), "source": RUN_SOURCE,
                    "measured": res["verdict"] in MEASURED and not partial}
    if partial:
        det["range"]["partial"] = "restricted with --paths"
    det["yield"] = {"survivors": int(det.get("survivors_total") or counts.get("survived", 0) or 0), "killed": killed,
                    "mutants": int(det.get("mutants_total") or 0), "undecided": int(det.get("undecided_mutants") or 0), "runtime_s": runtime, "cpu_s": det.get("cpu_s")}
    if det.get("survivors_shown"):
        det["survivors_shown"] = det["survivors_shown"][:SURVIVORS_MAX]
    if qc.mode(GATE) == "enforce":
        det["enforce_note"] = "OVN_QA_MUTATION=enforce is a no-op: mutation testing is advisory only (no enforcement path exists)"
    if res["verdict"] == "UNVERIFIED" and opt(argv, "--repo") in os.environ.get("OVN_MUT_SELECT_REPOS", DEFAULT_SELECT_REPOS).split() \
            and "wall cap" in res.get("summary", ""):
        res["summary"] = "over the %ss cap even with test selection by touched module: %s" % (vals.get("--cap"), res["summary"])
    res["ms"] = int((time.time() - t0) * 1000)
    return res


def check(argv):
    global TERMINATED
    t0 = time.time()
    repo = opt(argv, "--repo")
    base, head = opt(argv, "--base"), opt(argv, "--head")
    if qc.mode(GATE) == "off":
        return qc.verdict("NA", GATE, repo or "?", head or "?", "mode off (OVN_QA_MUTATION=off)")
    if not (repo and base and head):
        return qc.verdict("UNVERIFIED", GATE, repo or "?", head or "?", "usage: check --repo R --base B --head H")
    sargv, vals = build_argv(argv, repo)
    try:
        spike = load_spike()
        res = spike.check(sargv)
    except qc.Terminated:       # SIGTERM: spike.check's finally blocks already killed mutmut's process group and removed the worktree
        TERMINATED = True
        res = qc.verdict("UNVERIFIED", GATE, repo, head, "terminated (SIGTERM, wall limit) before the run finished; mutmut process group killed, worktree removed")
    except Exception as ex:  # noqa: BLE001 - the gate never raises into its caller
        res = qc.verdict("UNVERIFIED", GATE, repo, head, "mutation harness crashed: %s: %s" % (type(ex).__name__, ex))
    return finish(res, argv, vals, t0)


# ----------------------------------------------------------------------------------------------------------------- daily pass
def load_1m():
    try:
        return os.getloadavg()[0]
    except (OSError, AttributeError):
        return 0.0


def lock_held(path):
    """True when some process has `path` open. Read-only observation (fuser / lsof): the gate NEVER takes run.lock itself."""
    if not os.path.exists(path):
        return False
    for cmd in (["fuser", path], ["lsof", "--", path]):
        if shutil.which(cmd[0]):
            try:
                p = subprocess.run(cmd, capture_output=True, timeout=20)
                if cmd[0] == "lsof":
                    return p.returncode == 0 and bool(p.stdout.strip())
                # fuser: Linux prints holder pids on stdout and exits 1 when there are none; macOS exits 0 either way and prints "<path>:" (+ pids) on
                # stderr. So: a holder exists only when a pid (digits) is left after removing the path from the output.
                txt = (p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")).replace(path, "")
                return p.returncode == 0 and re.search(r"\d", txt) is not None
            except (OSError, subprocess.TimeoutExpired):
                continue
    return False


def load_max():
    """OVN_MUT_LOAD_MAX as a float; a non-numeric value falls back to 6 (one parser for busy_reason and the per-repo re-check)."""
    try:
        return float(os.environ.get("OVN_MUT_LOAD_MAX", "6") or 6)
    except ValueError:
        return 6.0


def busy_reason():
    """'' when a daily pass may run, else a one-line reason. Load guard always; run.lock only with OVN_MUT_RUN_LOCK=skip (default `ignore`: run_overnight
    holds run.lock for its whole lifetime, so honouring it made the daily pass skip forever on the live box)."""
    lmax = load_max()
    load = load_1m()
    if load > lmax:
        return "1-min load average %.1f > %s" % (load, os.environ.get("OVN_MUT_LOAD_MAX", "6"))
    if os.environ.get("OVN_MUT_RUN_LOCK", "ignore") == "skip":
        lock = os.environ.get("OVN_MUT_LOCK_FILE") or os.path.join(qc.state_dir(), "run.lock")
        if lock_held(lock):
            return "run.lock is held (%s)" % lock
    return ""


def tooling_reason():
    """'' when mutmut is available in the QA venv, else a one-line reason (the daily pass is then skipped up front instead of producing UNVERIFIED rows)."""
    try:
        base, sp = load_spike().qa_site_packages()
    except Exception as ex:  # noqa: BLE001
        return "cannot locate the QA venv: %s" % ex
    if sp and os.path.isdir(os.path.join(sp, "mutmut")):
        return ""
    return "mutmut is not installed in the QA venv (%s): run ops/qa_tools_install.sh (installs it into <OVN_DIR>/qa-tools/.venv)" % base


def record_skip(reason, repo=None, record=True):
    """Append one line to state/qa_gate_skips.jsonl so a gate that never runs shows up in qa_gate_precision.py verdict-rule. Never raises."""
    if not record:
        return
    try:
        d = qc.state_dir()
        os.makedirs(d, exist_ok=True)
        row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "gate": GATE, "reason": str(reason)[:300]}
        if repo:
            row["repo"] = repo
        with open(os.path.join(d, "qa_gate_skips.jsonl"), "a") as f:
            f.write(json.dumps(row, sort_keys=True) + "\n")
    except Exception:  # noqa: BLE001
        pass


def skip(reason, repo=None, record=True):
    out = {"skipped": reason}
    if repo:
        out["repo"] = repo
    print(json.dumps(out))
    record_skip(reason, repo, record)


def row_measured(r):
    """True when a mutation.jsonl row counts as a measured DAILY range: details.range.measured (rows written by this gate) or, for older rows without
    the field, a PASS/FLAG/NA verdict. Manual `check` rows (source != daily) never advance the baseline."""
    rg = (r.get("details") or {}).get("range") or {}
    if rg.get("source", "daily") != "daily":
        return False
    if "measured" in rg:
        return bool(rg["measured"])
    return r.get("verdict") in MEASURED


def last_recorded_head(repo):
    """Newest head of a MEASURED daily range for `repo` (from mutation.jsonl details.range.head), or ''."""
    best = ""
    try:
        with open(os.path.join(qc.state_dir(), "qa_shadow", "mutation.jsonl"), encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("repo") == repo and isinstance(r.get("details"), dict) and row_measured(r):
                    h = (r["details"].get("range") or {}).get("head")
                    if h:
                        best = h
    except OSError:
        pass
    return best


def resolve_range(repo, hours, ref=None, fetch=True):
    """(base, head, note): head = origin/develop, base = the previous measured head when it is an ancestor, else the last commit older than
    `hours`. (None, head, reason) when there is nothing new to measure."""
    rd = qc.repo_dir(repo)
    if not rd:
        return None, None, "no clone"
    ref = ref or os.environ.get("OVN_MUT_REF", "origin/develop")
    if fetch and "/" in ref:
        qc.git(rd, "fetch", "-q", "--no-tags", ref.split("/", 1)[0], ref.split("/", 1)[1], timeout=90)
    rc, out, _ = qc.git(rd, "rev-parse", "--verify", "-q", ref + "^{commit}")
    if rc != 0:
        return None, None, "cannot resolve %s" % ref
    head = out.strip()
    last = last_recorded_head(repo)
    if last:
        if last == head:
            return None, head, "no new commits since the last measured range"
        if qc.git(rd, "merge-base", "--is-ancestor", last, head)[0] == 0:
            rc, cnt, _ = qc.git(rd, "rev-list", "--count", "%s..%s" % (last, head))
            try:
                too_many = rc == 0 and int(cnt.strip()) > _int(os.environ.get("OVN_MUT_MAX_RANGE_COMMITS"), 300, 1, 100000)
            except ValueError:
                too_many = False
            if not too_many:
                return last, head, "since last measured head"
    rc, out, _ = qc.git(rd, "rev-list", "-1", "--before=%d hours ago" % hours, head)
    base = out.strip() if rc == 0 else ""
    if not base:
        return None, head, "no commit older than %dh to start the range from" % hours
    if base == head:
        return None, head, "no new commits in %dh" % hours
    return base, head, "last %dh" % hours


def daily(argv):
    """One advisory pass over the python repos. Prints ONE JSON line per repo (the gate row) or {"skipped": reason}. Always returns 0."""
    global RUN_SOURCE
    t0 = time.time()
    rec = "--no-record" not in argv
    if qc.mode(GATE) == "off":
        print(json.dumps({"skipped": "mode off (OVN_QA_MUTATION=off)"}))
        return 0
    why = busy_reason() or tooling_reason()
    if why:
        skip(why, record=rec)
        return 0
    repos = (opt(argv, "--repos") or os.environ.get("QA_DAILY_MUT_REPOS", DEFAULT_DAILY_REPOS)).split()
    hours = _int(opt(argv, "--hours") or os.environ.get("OVN_MUT_HOURS", "24"), 24, 1, 24 * 14)
    budget = _int(os.environ.get("OVN_MUT_DAILY_BUDGET_S"), 1800, 60, 6 * 3600)
    margin = _int(os.environ.get("OVN_MUT_MARGIN_S"), 200, 0, 3600)
    extra = ["--no-record"] if "--no-record" in argv else []
    RUN_SOURCE = "daily"
    try:
        for r in repos:
            if not re.match(r"^[A-Za-z0-9._-]+$", r):
                continue
            if TERMINATED:
                break
            need = build_argv([], r)[1]["--cap"] + margin
            left = budget - (time.time() - t0)
            if left < need:
                skip("daily budget %ss: %ds left, %s needs %ds (wall cap + margin)" % (budget, max(0, left), r, need), r, rec)
                continue
            rd = qc.repo_dir(r)
            qc.sweep_stale_scratch(repo_paths=[rd] if rd else [])   # worktrees leaked by a SIGKILLed earlier pass
            base, head, note = resolve_range(r, hours)
            if base is None:
                print(json.dumps({"repo": r, "skipped": note}))
                continue
            if load_1m() > load_max():   # load can rise while we work through repos
                skip("load rose above OVN_MUT_LOAD_MAX", r, rec)
                continue
            qc.main_guard(GATE, check, ["--repo", r, "--base", base, "--head", head] + extra)
    finally:
        RUN_SOURCE = "manual"
    return 0


def status():
    base, sp = (None, None)
    try:
        base, sp = load_spike().qa_site_packages()
    except Exception:  # noqa: BLE001
        pass
    heads = {}
    for r in DEFAULT_DAILY_REPOS.split():
        h = last_recorded_head(r)
        if h:
            heads[r] = h
    skips = []
    try:
        with open(os.path.join(qc.state_dir(), "qa_gate_skips.jsonl")) as f:
            for line in f:
                try:
                    k = json.loads(line)
                except ValueError:
                    continue
                if k.get("gate") == GATE:
                    skips.append(k)
    except OSError:
        pass
    return {"gate": GATE, "mode": qc.mode(GATE), "qa_venv": base, "mutmut_installed": not tooling_reason(), "tooling_reason": tooling_reason(),
            "run_lock_policy": os.environ.get("OVN_MUT_RUN_LOCK", "ignore"), "busy_reason": busy_reason(), "last_measured_heads": heads,
            "skips_total": len(skips), "skips_recent": skips[-3:]}


def _on_sigterm(signum, frame):
    raise qc.Terminated("signal %d" % signum)


def main():
    argv = sys.argv[1:]
    cmd = argv[0] if argv else ""
    if cmd in ("check", "daily"):
        try:
            signal.signal(signal.SIGTERM, _on_sigterm)
        except (ValueError, OSError):
            pass
    if cmd == "check":
        return qc.main_guard(GATE, check, argv[1:])
    if cmd == "daily":
        try:
            return daily(argv[1:])
        except qc.Terminated:
            print(json.dumps({"skipped": "daily terminated (SIGTERM, wall limit)"}))
            return 0
        except Exception as ex:  # noqa: BLE001
            print(json.dumps({"skipped": "daily crashed: %s: %s" % (type(ex).__name__, ex)}))
            return 0
    if cmd == "busy":
        print(busy_reason())
        return 0
    if cmd == "status":
        print(json.dumps(status(), sort_keys=True))
        return 0
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
