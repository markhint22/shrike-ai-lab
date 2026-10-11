#!/usr/bin/env python3
"""ovn_executor_ctl.py - observe, rehearse and switch the deterministic executors (doc / ruff) (2026-10-10, package docexec; analysis[6] BX-01, analysis[0] F4).

The executors ship in SHADOW. This tool is the one place that answers "is it ready?" and flips the switch:

  summary   [--hours N] [--repo R] [--json]     what state/executor_shadow.log (written by ovn_executor_hook / ovn_doc_postcheck_gate in lib_fixup.sh; never truncated)
                                                says: would-apply rate (distinct items; live shadow cycles + rehearsals), skip reasons, on-mode applied/fail, parked-idle breadcrumbs,
                                                post-check ok/flag counts
  readiness [--repo R] [--repo-dir DIR] [--check]   the gates (see below) + info lines; with --check the exit status is 0 only when READY
  rehearse  <repo_dir> [--max N] [--kind doc]   REAL evidence for `apply`: clones the repo (read-only on the source), runs the executor on up to N open gd-missing-doc items
                                                (parked ones included) in the clone, runs each item's own VERIFY and the net-diff post-check, logs rehearsal-pass/-fail rows. Needs the model
                                                (LITELLM_BASE ...) exactly like the executor itself; commits/pushes nothing anywhere.
  status    [--repo R]                          the effective mode per kind (env override, state/executor_mode lines)
  enable    <doc|ruff> (--repo R | --all) [--require-ready]   mode=on  (prints the readiness report first; --require-ready refuses when not READY)
  disable   <doc|ruff> (--repo R | --all) [--off]             mode=shadow (the safe default; --off = off)
  reset     <doc|ruff> (--repo R | --all)                     drop the state/executor_mode line

Mode resolution (identical in lib_fixup.sh ovn_executor_mode and ovn_work_supply.doc_executor_mode): env OVN_DOC_EXECUTOR / OVN_RUFF_EXECUTOR when set (so `off` in the
environment stays a kill switch, and a cron line that sets it explicitly wins over the file), else state/executor_mode (`kind:repo=mode` beats `kind=mode`), else shadow.
Readiness gates (doc): executor script compiles; >= OVN_EXEC_READY_MIN_ITEMS (5) distinct items with a would-apply row; would-apply share of conclusive check verdicts >= 0.8;
>= OVN_EXEC_READY_MIN_REHEARSALS (3) rehearsal rows with a pass share >= 0.8. Everything else (post-check flags, orphan/duplicate baseline, parked gaps, exec_failed markers,
env overrides) is reported as info.
env: OVN_DIR (default: the directory above scripts/), OVN_EXECUTOR_LOG (default <OVN_DIR>/state/executor_shadow.log). Exit status 0 except `readiness --check`/`enable --require-ready`.
"""
import argparse
import collections
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
KINDS = ("doc", "ruff")
ENV_VAR = {"doc": "OVN_DOC_EXECUTOR", "ruff": "OVN_RUFF_EXECUTOR"}
MODES = ("off", "shadow", "on")
NOT_DOC_ITEM = "not a gd-missing-doc supply item"   # ovn_doc_executor.py check's SKIP reason for any non-doc item
MIN_ITEMS = int(os.environ.get("OVN_EXEC_READY_MIN_ITEMS", "5"))
MIN_REHEARSALS = int(os.environ.get("OVN_EXEC_READY_MIN_REHEARSALS", "3"))
MIN_RATE = float(os.environ.get("OVN_EXEC_READY_MIN_RATE", "0.8"))


def utcnow():
    return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)   # naive UTC (datetime.utcnow() is deprecated)


def od_dir():
    return os.environ.get("OVN_DIR") or os.path.dirname(HERE)


def log_path():
    return os.environ.get("OVN_EXECUTOR_LOG") or os.path.join(od_dir(), "state", "executor_shadow.log")


def mode_file():
    return os.path.join(od_dir(), "state", "executor_mode")


# ---------------------------------------------------------------- the shared identity / mode helpers (parity-tested against lib_item_select.sh / lib_fixup.sh)
def item_hash(text):
    """lib_item_select.sh ovn_item_hash: strip the checkbox; a [feat:...] tag (first one, 8- or 6-digit date stamp removed) is the identity, else the whole text."""
    t = re.sub(r"^- \[[ xX]\] ", "", text)
    m = re.search(r"\[feat:[^\]]+\]", t)
    if m:
        k = m.group(0)
        k = re.sub(r"-[0-9]{8}-", "-", k, count=1)
        k = re.sub(r"-[0-9]{6}-", "-", k, count=1)
        return hashlib.md5(k.encode()).hexdigest()
    return hashlib.md5(t.encode()).hexdigest()


def read_mode_file(path=None):
    out = {}
    try:
        for ln in open(path or mode_file(), encoding="utf-8", errors="replace"):
            ln = re.sub(r"\s", "", ln)
            if not ln or ln.startswith("#") or "=" not in ln:
                continue
            k, _, v = ln.partition("=")
            out[k] = v
    except OSError:
        pass
    return out


def mode_info(kind, repo, environ=None):
    """-> dict(mode, source, env, file, file_key, conflict). Same precedence as lib_fixup.sh ovn_executor_mode and ovn_work_supply.doc_executor_mode:
    the env var (when set) wins over state/executor_mode (`kind:repo=` beats `kind=`), else shadow. `conflict` is True when BOTH are set and their effective values differ -
    the file line then has no effect wherever that variable is set (cron lines / supervisor env), which is the trap `enable` used to leave silent."""
    env = os.environ if environ is None else environ
    ev = (env.get(ENV_VAR.get(kind, ""), "") or "").strip()
    f = read_mode_file()
    fkey = "%s:%s" % (kind, repo)
    fv, fk = "", ""
    if f.get(fkey):
        fv, fk = f[fkey], fkey
    elif f.get(kind):
        fv, fk = f[kind], kind
    fmode = fv if fv in MODES else ("shadow" if fv else "")
    if ev:
        mode = ev if ev in MODES else "shadow"
        source = "env %s=%s" % (ENV_VAR[kind], ev) + ("" if ev in MODES else " (invalid value: treated as shadow)")
    elif fv:
        mode = fmode
        source = "state file line %s=%s" % (fk, fv) + ("" if fv in MODES else " (invalid value: treated as shadow)")
    else:
        mode, source = "shadow", "default (no env, no state file line)"
    return {"mode": mode, "source": source, "env": ev, "file": fmode, "file_key": fk, "conflict": bool(ev and fmode and mode != fmode)}


def resolve_mode(kind, repo, environ=None):
    return mode_info(kind, repo, environ)["mode"]


def conflict_warning(kind, repo, environ=None):
    i = mode_info(kind, repo, environ)
    if not i["conflict"]:
        return ""
    return ("WARNING: %s=%s overrides state file line %s=%s for %s - the file line has NO effect wherever that variable is set (this shell, and any cron line or supervisor "
            "environment that sets it). Remove it there too (e.g. the xlite supply cron line) or the executor mode will not change." % (ENV_VAR[kind], i["env"], i["file_key"], i["file"], repo or "*"))


# ---------------------------------------------------------------- the log
def read_rows(hours=None, repo=None, kind=None):
    rows, cutoff = [], None
    if hours:
        cutoff = utcnow() - datetime.timedelta(hours=hours)
    try:
        fh = open(log_path(), encoding="utf-8", errors="replace")
    except OSError:
        return rows
    for ln in fh:
        f = ln.rstrip("\n").split("\t")
        if len(f) < 7:
            continue
        try:
            ts = datetime.datetime.strptime(f[0], "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            continue
        if cutoff and ts < cutoff:
            continue
        r = {"ts": ts, "repo": f[1], "kind": f[2], "mode": f[3], "verdict": f[4], "hash": f[5], "detail": f[6], "cycle": f[7] if len(f) > 7 else "-"}
        if repo and r["repo"] != repo:
            continue
        if kind and r["kind"] != kind:
            continue
        rows.append(r)
    return rows


def append_row(repo, kind, mode, verdict, h, detail, cycle="-"):
    p = log_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    d = re.sub(r"[\t\r\n]", " ", detail)[:300]
    with open(p, "a", encoding="utf-8") as fh:
        fh.write("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"), repo, kind, mode, verdict, h or "-", d, cycle))


def latest_by_hash(rows, verdicts):
    last = {}
    for r in rows:
        if r["verdict"] in verdicts and r["hash"] not in ("", "-"):
            last[r["hash"]] = r
    return last


def stats(rows):
    """-> dict of the numbers summary and readiness both use."""
    out = {}
    # `check` verdicts: from live shadow cycles AND from rehearsals (a lane with only parked gaps never reaches the hook in shadow, so rehearse is the other source)
    # a `skip` whose reason is NOT_DOC_ITEM is the executor declining a non-doc top item (every ongoing-* cycle offers the hook the top open item of ANY kind): it is not a
    # conclusive verdict about a doc gap, so it must not dilute the would-apply share (older logs carry such rows; the hook no longer writes them)
    def _conclusive(r):
        return not (r["verdict"] == "skip" and r["detail"].startswith(NOT_DOC_ITEM))
    chk = latest_by_hash([r for r in rows if r["kind"] in KINDS and r["mode"] in ("shadow", "rehearsal") and _conclusive(r)], ("would-apply", "skip"))
    out["shadow_items"] = len(chk)
    out["would_apply_items"] = sum(1 for r in chk.values() if r["verdict"] == "would-apply")
    out["shadow_rows"] = sum(1 for r in rows if r["kind"] in KINDS and r["mode"] in ("shadow", "rehearsal") and r["verdict"] in ("would-apply", "skip") and _conclusive(r))
    out["check_empty"] = sum(1 for r in rows if r["verdict"] == "check-empty")   # `check` printed nothing (timeout/crash): inconclusive, neither would-apply nor skip
    out["would_apply_rate"] = (out["would_apply_items"] / len(chk)) if chk else None
    skips = collections.Counter(re.sub(r"[`'\"][^`'\"]*[`'\"]", "X", r["detail"])[:70] for r in chk.values() if r["verdict"] == "skip")
    out["skip_reasons"] = skips.most_common(5)
    on = latest_by_hash([r for r in rows if r["kind"] in KINDS and r["mode"] == "on"], ("applied", "fail"))
    out["on_items"] = len(on)
    out["applied_items"] = sum(1 for r in on.values() if r["verdict"] == "applied")
    out["on_fail_reasons"] = collections.Counter(r["detail"][:70] for r in on.values() if r["verdict"] == "fail").most_common(5)
    reh = [r for r in rows if r["mode"] == "rehearsal" and r["verdict"].startswith("rehearsal-")]   # (the per-item check rows of a rehearsal are would-apply/skip, counted above)
    out["rehearsals"] = len(reh)
    out["rehearsal_pass"] = sum(1 for r in reh if r["verdict"] == "rehearsal-pass")
    out["rehearsal_fail"] = sum(1 for r in reh if r["verdict"] == "rehearsal-fail")
    concl = out["rehearsal_pass"] + out["rehearsal_fail"]
    out["rehearsal_rate"] = (out["rehearsal_pass"] / concl) if concl else None
    out["rehearsal_fail_reasons"] = collections.Counter(r["detail"][:70] for r in reh if r["verdict"] == "rehearsal-fail").most_common(5)
    pc = [r for r in rows if r["kind"] == "doc-postcheck"]
    out["postcheck_ok"] = sum(1 for r in pc if r["verdict"] == "ok")
    out["postcheck_flag"] = sum(1 for r in pc if r["verdict"] == "flag")
    codes = collections.Counter()
    for r in pc:
        if r["verdict"] == "flag":
            for c in r["detail"].split(":", 1)[0].split(","):
                codes[c.strip()] += 1
    out["postcheck_codes"] = codes.most_common()
    idle = [r for r in rows if r["verdict"] == "parked-idle"]
    out["parked_idle_rows"] = len(idle)
    out["parked_idle_last"] = idle[-1]["detail"] if idle else ""
    out["no_candidate"] = sum(1 for r in rows if r["verdict"] == "no-candidate")
    return out


def pct(x):
    return "n/a" if x is None else "%d%%" % round(100 * x)


def cmd_summary(a):
    rows = read_rows(a.hours, a.repo)
    s = stats(rows)
    if a.json:
        print(json.dumps(s, indent=1, default=str))
        return 0
    span = ("last %sh" % a.hours) if a.hours else "all time"
    print("executor log %s (%s%s): %d rows" % (log_path(), span, ", repo " + a.repo if a.repo else "", len(rows)))
    print("shadow check   : %d distinct item(s), would-apply %d (%s); %d row(s) in total" % (s["shadow_items"], s["would_apply_items"], pct(s["would_apply_rate"]), s["shadow_rows"]))
    for why, n in s["skip_reasons"]:
        print("   skip x%d  %s" % (n, why))
    if s["check_empty"]:
        print("   (%d inconclusive `check` row(s): no output, e.g. timeout/crash - not counted)" % s["check_empty"])
    print("on mode        : %d distinct item(s) tried, %d applied" % (s["on_items"], s["applied_items"]))
    for why, n in s["on_fail_reasons"]:
        print("   fail x%d  %s" % (n, why))
    print("rehearsals     : %d (pass %d, fail %d, pass rate %s)" % (s["rehearsals"], s["rehearsal_pass"], s["rehearsal_fail"], pct(s["rehearsal_rate"])))
    for why, n in s["rehearsal_fail_reasons"]:
        print("   fail x%d  %s" % (n, why))
    print("post-check     : ok %d, flagged %d %s" % (s["postcheck_ok"], s["postcheck_flag"], ("(" + ", ".join("%s %d" % c for c in s["postcheck_codes"]) + ")") if s["postcheck_codes"] else ""))
    print("idle breadcrumbs: parked-idle rows %d%s; no-candidate rows %d" % (s["parked_idle_rows"], (" (last: %s)" % s["parked_idle_last"]) if s["parked_idle_last"] else "", s["no_candidate"]))
    return 0


# ---------------------------------------------------------------- readiness
def readiness(repo, repo_dir, hours=None):
    rows = read_rows(hours, repo)
    s = stats(rows)
    gates, info = [], []
    script = os.path.join(HERE, "ovn_doc_executor.py")
    try:
        subprocess.run([sys.executable, "-m", "py_compile", script], check=True, capture_output=True)
        gates.append(("executor script present and compiles", True, script))
    except Exception as e:
        gates.append(("executor script present and compiles", False, str(e)[:120]))
    gates.append(("check evidence (shadow cycles + rehearsals): >= %d distinct items with a would-apply row" % MIN_ITEMS, s["would_apply_items"] >= MIN_ITEMS, "%d item(s)" % s["would_apply_items"]))
    gates.append(("would-apply share of conclusive check verdicts >= %d%%" % round(100 * MIN_RATE), s["would_apply_rate"] is not None and s["would_apply_rate"] >= MIN_RATE, pct(s["would_apply_rate"])))
    gates.append(("rehearsals (real `apply` in a clone): >= %d, pass share >= %d%%" % (MIN_REHEARSALS, round(100 * MIN_RATE)),
                  s["rehearsals"] >= MIN_REHEARSALS and s["rehearsal_rate"] is not None and s["rehearsal_rate"] >= MIN_RATE,
                  "%d run(s), pass %s" % (s["rehearsals"], pct(s["rehearsal_rate"]))))
    mi = mode_info("doc", repo or "*")
    info.append("effective doc mode for %s: %s  [source: %s]" % (repo or "(any repo)", mi["mode"], mi["source"]))
    if mi["conflict"]:
        info.append(conflict_warning("doc", repo or "*"))
    info.append("post-check: ok %d, flagged %d%s; OVN_DOC_POSTCHECK=%s" % (s["postcheck_ok"], s["postcheck_flag"], (" " + str(s["postcheck_codes"])) if s["postcheck_codes"] else "", os.environ.get("OVN_DOC_POSTCHECK", "shadow (default)")))
    if s["parked_idle_rows"]:
        info.append("idle: %s" % s["parked_idle_last"])
    fdir = os.path.join(od_dir(), "state", "exec_failed")
    if os.path.isdir(fdir):
        info.append("exec_failed markers (items the executor will not retry): %d" % len(os.listdir(fdir)))
    if repo_dir and os.path.isdir(repo_dir):
        prog = os.path.join(repo_dir, "OVERNIGHT_PROGRESS.md")
        try:
            lines = open(prog, encoding="utf-8", errors="replace").read().split("\n")
            gaps = [l for l in lines if l.startswith("- [ ] ") and "supply:gd-missing-doc" in l]
            parked = [l for l in gaps if re.search(r"\[AUTO-SKIP after [0-9]+ credit refusals", l)]
            info.append("open gd-missing-doc items in %s: %d (%d parked after credit refusals = re-routable when mode=on)" % (repo_dir, len(gaps), len(parked)))
        except OSError:
            info.append("no OVERNIGHT_PROGRESS.md in %s" % repo_dir)
        try:
            import ovn_doc_postcheck as pcmod
            tot = pcmod.scan(repo_dir, [])[-1]
            info.append("orphan/duplicate ## baseline in the working tree: %s" % tot.replace("\t", " "))
        except Exception as e:
            info.append("orphan/duplicate scan unavailable: %s" % str(e)[:80])
    ready = all(g[1] for g in gates)
    return ready, gates, info


def print_readiness(ready, gates, info):
    for name, good, detail in gates:
        print("  [%s] %s  (%s)" % ("ok" if good else "NO", name, detail))
    for i in info:
        print("  info: " + i)
    print("READY: %s" % ("yes" if ready else "no - collect shadow evidence / run `ovn_executor_ctl.py rehearse <repo_dir>` first"))


def cmd_readiness(a):
    ready, gates, info = readiness(a.repo, a.repo_dir, a.hours)
    print_readiness(ready, gates, info)
    return 0 if (ready or not a.check) else 3


# ---------------------------------------------------------------- the switch
def write_mode(kind, repo, mode):
    """mode None removes the line. repo None = all repos (`kind=mode`)."""
    key = kind if not repo else "%s:%s" % (kind, repo)
    p = mode_file()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    try:
        lines = open(p, encoding="utf-8").read().split("\n")
    except OSError:
        lines = ["# kind[:repo]=off|shadow|on   (written by scripts/ovn_executor_ctl.py; env OVN_DOC_EXECUTOR / OVN_RUFF_EXECUTOR override)"]
    lines = [l for l in lines if l.strip() != "" ]
    kept = [l for l in lines if re.sub(r"\s", "", l).partition("=")[0] != key or l.lstrip().startswith("#")]
    if mode is not None:
        kept.append("%s=%s" % (key, mode))
    tmp = p + ".tmp.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(kept) + "\n")
    os.replace(tmp, p)


def _scope(a):
    if a.repo and a.all:
        sys.exit("give --repo R or --all, not both")
    if not a.repo and not a.all:
        sys.exit("refusing to guess the scope: pass --repo <name> (e.g. xlite) or --all")
    return a.repo or None


def cmd_set(a, mode):
    repo = _scope(a)
    if a.kind not in KINDS:
        sys.exit("kind must be doc or ruff")
    if mode == "on" and a.kind == "doc":
        ready, gates, info = readiness(repo, getattr(a, "repo_dir", None))
        print_readiness(ready, gates, info)
        if not ready and getattr(a, "require_ready", False):
            print("refused: not READY (--require-ready)")
            return 3
        if not ready:
            print("WARNING: enabling without READY evidence (no --require-ready given)")
    write_mode(a.kind, repo, mode)
    shown = repo or "*"
    print("%s executor: %s -> %s (state file %s)" % (a.kind, shown, mode if mode else "(line removed)", mode_file()))
    env = os.environ.get(ENV_VAR[a.kind])
    if env:
        print("NOTE: %s=%s is set in THIS environment and overrides the file here; cron/supervisor environments that set it explicitly override it too." % (ENV_VAR[a.kind], env))
    i = mode_info(a.kind, repo or "*")
    print("effective for %s now: %s  [source: %s]" % (shown, i["mode"], i["source"]))
    w = conflict_warning(a.kind, repo or "*")
    if w:
        print(w)
    return 0


def cmd_status(a):
    f = read_mode_file()
    print("state file %s: %s" % (mode_file(), (", ".join("%s=%s" % kv for kv in sorted(f.items())) or "(none)")))
    for k in KINDS:
        scopes = [a.repo] if a.repo else ["*"] + sorted({key.split(":", 1)[1] for key in f if key.startswith(k + ":")})
        for sc in scopes:
            i = mode_info(k, sc)
            print("%s%s: effective %s  [source: %s]" % (k, (" (%s)" % sc) if sc != "*" and not a.repo else "", i["mode"], i["source"]))
            w = conflict_warning(k, sc)
            if w:
                print("  " + w)
    return 0


# ---------------------------------------------------------------- rehearsal
VERIFY_RE = re.compile(r"VERIFY: `(.*)`\. \(cat:", re.S)


def run(cmd, cwd, timeout=60, env=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)


def cmd_rehearse(a):
    import ovn_doc_executor as dx
    import ovn_doc_postcheck as pc
    src = os.path.abspath(a.repo_dir)
    if not os.path.isdir(os.path.join(src, ".git")):
        sys.exit("not a git checkout: %s" % src)
    repo = os.path.basename(src)
    tmp = tempfile.mkdtemp(prefix="ovn-rehearse-")
    clone = os.path.join(tmp, repo)
    results = []
    try:
        r = run(["git", "clone", "-q", "--local", "--no-hardlinks", src, clone], tmp, timeout=300)
        if r.returncode != 0:
            sys.exit("clone failed: " + r.stderr[:200])
        base = run(["git", "rev-parse", "HEAD"], clone).stdout.strip()
        prog = os.path.join(clone, "OVERNIGHT_PROGRESS.md")
        items = [l for l in open(prog, encoding="utf-8", errors="replace").read().split("\n") if l.startswith("- [ ] ") and "supply:gd-missing-doc" in l]
        # the executor script under test is the deployed sibling of this tool
        env = dict(os.environ)
        done = 0
        for item in items:
            if done >= a.max:
                break
            act, info = dx.decide(clone, item)
            h = item_hash(item)
            if act != "OK":   # the executor refuses this item: honest evidence for the would-apply rate (not a rehearsal)
                append_row(repo, "doc", "rehearsal", "skip", h, info)
                continue
            append_row(repo, "doc", "rehearsal", "would-apply", h, info)
            done += 1
            f = info
            verdict, why = "rehearsal-fail", ""
            try:
                ap = run([sys.executable, os.path.join(HERE, "ovn_doc_executor.py"), "apply", clone, item], clone, timeout=300, env=env)
                out = (ap.stdout.strip().split("\n") or [""])[-1]
                kind_ = out.split("\t")[0]
                if kind_ == "APPLIED":
                    run(["git", "-c", "user.name=rehearse", "-c", "user.email=r@r", "commit", "-q", "-a", "-m", "rehearsal"], clone)
                    vm = VERIFY_RE.search(item)
                    vcmd = vm.group(1) if vm else ""
                    if not vcmd.startswith("python3 -c "):
                        why = "item VERIFY missing or not the supply one-liner form"
                    else:
                        v = run(["bash", "-c", vcmd], clone, timeout=60)
                        if v.returncode != 0:
                            why = "the item's own VERIFY did not pass after apply"
                        else:
                            res = pc.check(clone, base, "HEAD", item)
                            if res[0] == "OK":
                                verdict, why = "rehearsal-pass", "%s: %s" % (f, out.split("\t")[-1])
                            else:
                                why = "post-check %s: %s" % (res[1], res[2] if len(res) > 2 else "")
                elif kind_ == "SKIP":
                    verdict, why = "rehearsal-skip", out.split("\t", 1)[-1]
                else:
                    why = out.split("\t", 1)[-1] if out else (ap.stderr.strip()[-120:] or "no output")
            except subprocess.TimeoutExpired:
                why = "timeout"
            run(["git", "reset", "-q", "--hard", base], clone)
            run(["git", "clean", "-fdq"], clone)
            append_row(repo, "doc", "rehearsal", verdict, h, "%s: %s" % (f, why))
            results.append((verdict, f, why))
            print("%-16s %s  %s" % (verdict, f, why))
        if not results:
            print("no open gd-missing-doc item that the executor's check accepts in %s" % src)
        else:
            p = sum(1 for r in results if r[0] == "rehearsal-pass")
            print("rehearsed %d item(s): pass %d, fail %d, skip %d  (rows appended to %s)" % (len(results), p, sum(1 for r in results if r[0] == "rehearsal-fail"), sum(1 for r in results if r[0] == "rehearsal-skip"), log_path()))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="ovn_executor_ctl.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("summary"); p.add_argument("--hours", type=float); p.add_argument("--repo"); p.add_argument("--json", action="store_true")
    p = sub.add_parser("readiness"); p.add_argument("--repo"); p.add_argument("--repo-dir"); p.add_argument("--hours", type=float); p.add_argument("--check", action="store_true")
    p = sub.add_parser("rehearse"); p.add_argument("repo_dir"); p.add_argument("--max", type=int, default=3); p.add_argument("--kind", default="doc")
    p = sub.add_parser("status"); p.add_argument("--repo")
    for name in ("enable", "disable", "reset"):
        p = sub.add_parser(name); p.add_argument("kind"); p.add_argument("--repo"); p.add_argument("--all", action="store_true")
        if name == "enable":
            p.add_argument("--require-ready", action="store_true"); p.add_argument("--repo-dir")
        if name == "disable":
            p.add_argument("--off", action="store_true")
    a = ap.parse_args(argv[1:])
    if a.cmd == "summary":
        return cmd_summary(a)
    if a.cmd == "readiness":
        return cmd_readiness(a)
    if a.cmd == "rehearse":
        if a.kind != "doc":
            sys.exit("only the doc executor can be rehearsed")
        return cmd_rehearse(a)
    if a.cmd == "status":
        return cmd_status(a)
    if a.cmd == "enable":
        return cmd_set(a, "on")
    if a.cmd == "disable":
        return cmd_set(a, "off" if a.off else "shadow")
    if a.cmd == "reset":
        return cmd_set(a, None)
    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
