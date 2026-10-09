#!/usr/bin/env python3
"""scripts/ovn_spec_gate.py - the spec gate between backlog and queue (spec-compiler-v2 part C3, 2026-10-09). Shadow-first.

  scan <repo>             judge the open T-lines of backlog/<repo>.md into state/spec_gate.jsonl (cron */10; skipped while state/PAUSED exists). NEVER writes the backlog.
  lint [<repo_dir>]       stdin item lines -> stdout, static repairs R01-R03 (ovn_planner.sh, before feat tagging). Any error echoes stdin unchanged.
  report                  summary of state/spec_gate.jsonl: verdict mix, findings per rule, and how each repair rule performed
  restore <repo> <key>    undo a quarantine: the line goes back to backlog/<repo>.md and is never quarantined again (a sticky `restored` row in state/spec_gate_restored.jsonl, an append-only file the scan never rewrites)

Single writer: queue_refill.py is the ONLY code that moves a backlog line (pull / credit / quarantine / hold), consulting these verdicts for the rules named in
OVN_SPEC_GATE_ENFORCE_RULES. `restore` is the one operator exception (an explicit manual command).

Env
  OVN_SPEC_GATE=off|shadow|enforce   default shadow. off: scan/lint do nothing, queue_refill ignores the gate. shadow and enforce judge identically (the row records the mode);
                                     what is ENFORCED is decided only by OVN_SPEC_GATE_ENFORCE_RULES.
  OVN_SPEC_GATE_ENFORCE_RULES        comma list, default empty = nothing enforced. R01 R02 R03 (repairs), R04 R05 R07 R10 (quarantine), R06 (hold), PB (quarantine a
                                     VERIFY that already passes). Rollout order: R01,R02,R03 -> R04,R06 -> R05,R07,R10 (see docs/PIPELINE_REWORK_2026-10-08.md).
  OVN_SPEC_BASE                      the ref everything is judged at (default origin/overnight/feature); OVN_DIR the live dir (default: the parent of this scripts/ dir)
  OVN_SPEC_GATE_MAX_EXEC             VERIFY executions per scan (default 12); OVN_SPEC_GATE_TTL_S verdict lifetime (default 21600)
  OVN_SPEC_GATE_RETAIN_S             spec_gate.jsonl retention (default 604800 = 7 days) and OVN_SPEC_GATE_MAX_ROWS (default 5000, newest kept); restored markers are never dropped

The jsonl row: {ts, repo, item_key, feat, tier, path, base, mode, exec:{verdict,sub,rc,ms}|null, findings, repairs, action}
  item_key = sha1(queue_refill-normalised line)[:12] + '-' + base7 (the ref's short sha: a verdict dies when the code under it changes). exec is the VERIFY of the line AFTER
  the static repairs (what a repaired pull would run), judged by ovn_spec_check.sh against ONE detached worktree of the ref opened through lib_worktree.sh; ms is the batch
  wall time divided by the rows judged in it. action is what full enforcement would do: pass | repair:R.. | quarantine:RNN | hold:R06 | flag:R.. .
"""
import datetime
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    import ovn_backlog_eligibility as E  # noqa: E402
    import ovn_spec_rules as R  # noqa: E402
    from ovn_spec_classify import declared_paths, verify_of  # noqa: E402
    _IMPORT_ERR = None
except Exception as _e:  # a broken sibling module must never cost the planner its decomposition: `lint` then echoes stdin
    E = R = declared_paths = verify_of = None
    _IMPORT_ERR = _e

QUARANTINE_RULES = ("R04", "R05", "R07", "R10")
HOLD_RULES = ("R06",)


def ovn_dir():
    return os.environ.get("OVN_DIR") or os.path.dirname(HERE)


def now_ts():
    return os.environ.get("OVN_SPEC_GATE_NOW") or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_ts(ts):
    try:
        return datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
    except (TypeError, ValueError):
        return None


def mode():
    m = os.environ.get("OVN_SPEC_GATE", "shadow")
    return m if m in ("off", "shadow", "enforce") else "shadow"


def warn_enforce_noop():
    """OVN_SPEC_GATE=enforce arms nothing by itself (only OVN_SPEC_GATE_ENFORCE_RULES does): say so on stderr instead of letting an operator believe it enforces."""
    if os.environ.get("OVN_SPEC_GATE", "shadow") == "enforce" and not [r for r in os.environ.get("OVN_SPEC_GATE_ENFORCE_RULES", "").split(",") if r.strip()]:
        sys.stderr.write("spec_gate WARNING: OVN_SPEC_GATE=enforce enforces NOTHING while OVN_SPEC_GATE_ENFORCE_RULES is empty - arm rules there (e.g. R01,R02,R03)\n")


def restored_path(ovn):
    """The sticky `restored` markers live in their OWN append-only file. `scan` rewrites state/spec_gate.jsonl atomically (rotate_store: read, tmp, os.replace) under the cron flock,
    and `restore` is a manual command that does not hold that lock: a marker appended to the rewritten file between rotate's read and its replace would be lost and the next scan
    would re-judge the line the operator just restored. A file that only ever gets O_APPEND single-write rows and is never rewritten has no such window (no lock needed)."""
    return os.path.join(ovn, "state", "spec_gate_restored.jsonl")


def restored_prefixes(ovn):
    """Item-hash prefixes (the part of item_key before the first '-') ever restored: the new marker file plus legacy `restored` rows still sitting in the store."""
    out = set()
    for path in (restored_path(ovn), os.path.join(ovn, "state", "spec_gate.jsonl")):
        for r in rows_of(path):
            if r.get("restored"):
                out.add(str(r.get("item_key", "")).split("-")[0])
    return out


def mark_restored(ovn, repo, lines):
    """Append one `restored` row per line, each with ONE os.write on an O_APPEND descriptor (atomic against concurrent appenders, never rewritten by anything)."""
    path = restored_path(ovn)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        for l in lines:
            row = {"ts": now_ts(), "repo": repo, "item_key": E.line_hash(l), "restored": True, "findings": [], "exec": None, "action": "restored"}
            os.write(fd, (json.dumps(row, sort_keys=True) + "\n").encode("utf-8"))
    finally:
        os.close(fd)


def rotate_store(store, now):
    """Bound state/spec_gate.jsonl (up to 12 rows per 10-minute scan, rewritten whenever the fleet advances the ref): drop rows older than OVN_SPEC_GATE_RETAIN_S (default 7 days,
    which covers the >=3 day shadow period `report` is read after) and keep at most OVN_SPEC_GATE_MAX_ROWS (default 5000) of the newest. Restored markers are sticky and ALWAYS kept
    (they are what stops a restored line being re-judged); unparseable lines are dropped. Rewrites the file atomically, and only when something is actually dropped."""
    try:
        retain = int(os.environ.get("OVN_SPEC_GATE_RETAIN_S", str(7 * 86400)) or 7 * 86400)
        cap = int(os.environ.get("OVN_SPEC_GATE_MAX_ROWS", "5000") or 5000)
    except ValueError:
        retain, cap = 7 * 86400, 5000
    raw = [l for l in read(store).split("\n") if l.strip()]
    keep_restored, keep_rows, dropped = [], [], 0
    for l in raw:
        try:
            r = json.loads(l)
        except ValueError:
            dropped += 1
            continue
        if not isinstance(r, dict):
            dropped += 1
            continue
        if r.get("restored"):
            keep_restored.append(l)
            continue
        ts = _parse_ts(r.get("ts"))
        if ts is None or (now - ts).total_seconds() > retain:
            dropped += 1
            continue
        keep_rows.append(l)
    if len(keep_rows) > cap:
        dropped += len(keep_rows) - cap
        keep_rows = keep_rows[-cap:]
    if not dropped:
        return 0
    tmp = store + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("".join(l + "\n" for l in keep_restored + keep_rows))
    os.replace(tmp, store)
    return dropped


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def rows_of(path):
    out = []
    for raw in read(path).split("\n"):
        try:
            r = json.loads(raw)
        except ValueError:
            continue
        if isinstance(r, dict):
            out.append(r)
    return out


def _git(clone, *args, timeout=30):
    try:
        return subprocess.run(["git", "-C", clone] + list(args), capture_output=True, text=True, errors="replace", timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None


def base7(clone, ref):
    r = _git(clone, "rev-parse", "--short=7", ref)
    return r.stdout.strip() if r is not None and r.returncode == 0 else ""


def would_do(findings, exec_):
    """What full enforcement would do with a line: (action, rule)."""
    rules = [f["rule"] for f in findings]
    for r in QUARANTINE_RULES:
        if r in rules:
            return "quarantine:%s" % r
    for r in HOLD_RULES:
        if r in rules:
            return "hold:%s" % r
    if exec_ and exec_.get("verdict") == "passes-before":
        return "quarantine:PB"
    rep = [f["rule"] for f in findings if f["sev"] == "repair"]
    if rep:
        return "repair:" + ",".join(rep)
    flag = [f["rule"] for f in findings if f["sev"] == "flag"]
    if flag:
        return "flag:" + ",".join(flag)
    return "pass"


# ---------------------------------------------------------------- worktree + VERIFY execution
def _bash_lib(ovn, fn, *args):
    lib = os.path.join(ovn, "scripts", "lib_worktree.sh")
    if not os.path.exists(lib):
        lib = os.path.join(HERE, "lib_worktree.sh")
    script = '. "$1" && shift && "$@"'
    return subprocess.run(["bash", "-c", script, "_", lib, fn] + list(args), capture_output=True, text=True, errors="replace", timeout=120)


def open_worktree(ovn, clone, branch):
    try:
        r = _bash_lib(ovn, "wt_open", clone, branch, "--detach", "--tag=spec-gate")
    except (OSError, subprocess.SubprocessError):
        return None
    wt = r.stdout.strip().split("\n")[-1] if r.returncode == 0 else ""
    return wt if wt and os.path.isdir(wt) else None


def close_worktree(ovn, clone, wt):
    try:
        _bash_lib(ovn, "wt_close", clone, wt)
    except (OSError, subprocess.SubprocessError):
        pass


def run_spec_check(ovn, repo, wt, lines):
    """-> {index (0-based into `lines`): {verdict, sub, rc}} through ovn_spec_check.sh (niced), judged in the caller's worktree `wt`."""
    import tempfile
    sh = os.path.join(ovn, "scripts", "ovn_spec_check.sh")
    if not os.path.exists(sh):
        sh = os.path.join(HERE, "ovn_spec_check.sh")
    fd, tmp = tempfile.mkstemp(prefix="spec-gate-", suffix=".md")
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(lines) + "\n")
        env = dict(os.environ, OVN_DIR=ovn, OVN_SPEC_WT=wt)
        try:
            r = subprocess.run(["nice", "-n", "15", "bash", sh, repo, tmp], capture_output=True, text=True, errors="replace", env=env, cwd=ovn, timeout=1800)
        except (OSError, subprocess.SubprocessError) as e:
            sys.stderr.write("spec check failed: %s\n" % e)
            return {}
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    out = {}
    for l in r.stdout.split("\n"):
        p = l.split("\t")
        if len(p) >= 2 and p[0].isdigit():
            out[int(p[0]) - 1] = {"verdict": p[1], "sub": p[3] if len(p) > 3 else "", "rc": (int(p[4]) if len(p) > 4 and p[4].lstrip("-").isdigit() else None)}
    return out


# ---------------------------------------------------------------- scan
def scan(repo):
    ovn = ovn_dir()
    log = lambda m: print("spec_gate scan %s: %s" % (repo, m))  # noqa: E731
    if mode() == "off":
        log("OVN_SPEC_GATE=off - nothing to do")
        return 0
    warn_enforce_noop()
    if os.path.exists(os.path.join(ovn, "state", "PAUSED")):
        log("queue is paused (state/PAUSED) - skipped")
        return 0
    backlog = os.path.join(ovn, "backlog", repo + ".md")
    clone = os.path.join(ovn, "repos", repo)
    ref = os.environ.get("OVN_SPEC_BASE", "origin/overnight/feature")
    b7 = base7(clone, ref)
    if not b7:
        log("no ref %s in %s - skipped" % (ref, clone))
        return 0
    store = os.path.join(ovn, "state", "spec_gate.jsonl")
    ttl = int(os.environ.get("OVN_SPEC_GATE_TTL_S", "21600") or 21600)
    cap = int(os.environ.get("OVN_SPEC_GATE_MAX_EXEC", "12") or 12)
    now = _parse_ts(now_ts()) or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    judged_keys, restored = set(), restored_prefixes(ovn)
    for r in rows_of(store):
        k = str(r.get("item_key", ""))
        if r.get("restored"):                    # legacy: markers written into the store by an earlier version
            continue
        ts = _parse_ts(r.get("ts"))
        if r.get("repo") == repo and ts and (now - ts).total_seconds() <= ttl:
            judged_keys.add(k)
    text = read(backlog)
    open_lines = [l for l in text.split("\n") if E.is_open_item(l) and not E.is_parked(l)]
    ctx = R.Ctx(clone, ref)
    linted = R.lint_batch(open_lines, ctx)          # the whole open set: R06/R07 need the neighbours
    todo = []
    for orig, (line2, fs) in zip(open_lines, linted):
        h = E.line_hash(orig)
        key = "%s-%s" % (h, b7)
        if h in restored or key in judged_keys:
            continue
        todo.append((orig, line2, fs, key))
    fresh = len(open_lines) - len(todo)
    if not todo:
        log("%d open, all with a fresh verdict - memo hit, nothing executed" % len(open_lines))
        return 0
    batch = todo[:cap]
    # identical (command, declared paths) is executed once and the verdict shared
    groups, order = {}, []
    for i, (orig, line2, fs, key) in enumerate(batch):
        v = verify_of(line2)
        gk = (v, frozenset(declared_paths(line2))) if v else ("<none>", i)
        if gk not in groups:
            groups[gk] = []
            order.append(gk)
        groups[gk].append(i)
    reps = [groups[gk][0] for gk in order]
    exec_by_idx = {}
    wt = open_worktree(ovn, clone, ref.split("/", 1)[1] if ref.startswith("origin/") else ref) if reps else None
    t0 = time.time()
    if wt:
        try:
            res = run_spec_check(ovn, repo, wt, [batch[i][1] for i in reps])
        finally:
            close_worktree(ovn, clone, wt)
        ms = int((time.time() - t0) * 1000 / max(1, len(reps)))
        for pos, i in enumerate(reps):
            ex = res.get(pos)
            if ex is None:
                continue
            ex = dict(ex, ms=ms)
            gk = next(g for g in order if groups[g][0] == i)
            for j in groups[gk]:
                exec_by_idx[j] = ex
    else:
        log("could not open a worktree of %s - rows are written without exec" % ref)
    os.makedirs(os.path.dirname(store), exist_ok=True)
    try:
        n_rot = rotate_store(store, now)
        if n_rot:
            log("rotated %s: dropped %d old row(s)" % (os.path.basename(store), n_rot))
    except OSError as e:                 # rotation is housekeeping: never lose this scan's rows over it
        log("rotation skipped (%s)" % e)
    with open(store, "a", encoding="utf-8") as f:
        for i, (orig, line2, fs, key) in enumerate(batch):
            p = R.parse(line2) or {}
            ex = exec_by_idx.get(i)
            row = {"ts": now_ts(), "repo": repo, "item_key": key, "feat": p.get("feat"), "tier": p.get("tier"), "path": p.get("target"), "base": b7,
                   "mode": mode(), "exec": ex, "findings": fs, "repairs": [x["rule"] for x in fs if x["sev"] == "repair"], "action": would_do(fs, ex)}
            f.write(json.dumps(row, sort_keys=True) + "\n")
    log("%d open, %d fresh, %d judged now (%d executed), %d left for the next scan" % (len(open_lines), fresh, len(batch), len(reps), len(todo) - len(batch)))
    return 0


# ---------------------------------------------------------------- lint (stdin -> stdout)
def lint_stream():
    data = sys.stdin.read()
    warn_enforce_noop()
    try:
        if mode() == "off":
            sys.stdout.write(data)
            return 0
        rules = {r.strip().upper() for r in os.environ.get("OVN_SPEC_GATE_ENFORCE_RULES", "").split(",") if r.strip()}
        lines = data.split("\n")
        out, would = [], {}
        for l in lines:
            l2, fs = R.lint_static(l) if l.startswith("- [ ]") else (l, [])
            for f in fs:
                would[f["rule"]] = would.get(f["rule"], 0) + 1
            if fs and rules:
                l2, _ = R.lint_static(l, only=rules & {"R01", "R02", "R03"})
            else:
                l2 = l
            out.append(l2)
        if would:
            sys.stderr.write("spec-gate lint (%s): %s\n" % ("enforced: " + ",".join(sorted(rules & {"R01", "R02", "R03"})) if rules & {"R01", "R02", "R03"} else "shadow, nothing rewritten",
                                                              " ".join("%s=%d" % (k, v) for k, v in sorted(would.items()))))
        sys.stdout.write("\n".join(out))
    except Exception as e:  # fail-safe: never lose a decomposition to the gate
        sys.stderr.write("spec-gate lint failed (%s) - input echoed unchanged\n" % e)
        sys.stdout.write(data)
    return 0


# ---------------------------------------------------------------- report
def report():
    warn_enforce_noop()
    ovn = ovn_dir()
    rows = [r for r in rows_of(os.path.join(ovn, "state", "spec_gate.jsonl")) if not r.get("restored")]
    print("spec_gate report: %d judged rows" % len(rows))
    if not rows:
        return 0
    by_repo, verdicts, rules, actions = {}, {}, {}, {}
    rep = {}
    for r in rows:
        by_repo[r.get("repo")] = by_repo.get(r.get("repo"), 0) + 1
        ex = r.get("exec")
        vk = "no-exec" if not ex else "%s/%s" % (ex.get("verdict"), ex.get("sub") or "-")
        verdicts[vk] = verdicts.get(vk, 0) + 1
        actions[(r.get("action") or "?").split(":")[0]] = actions.get((r.get("action") or "?").split(":")[0], 0) + 1
        for f in r.get("findings") or []:
            rules[f.get("rule")] = rules.get(f.get("rule"), 0) + 1
        for rid in r.get("repairs") or []:
            d = rep.setdefault(rid, [0, 0])
            d[0] += 1
            if ex and ex.get("verdict") == "red":
                d[1] += 1
    print("per repo: " + ", ".join("%s=%d" % kv for kv in sorted(by_repo.items())))
    print("exec verdicts: " + ", ".join("%s=%d" % kv for kv in sorted(verdicts.items())))
    print("would-do actions: " + ", ".join("%s=%d" % kv for kv in sorted(actions.items())))
    for rid in sorted(rules):
        print("rule %s: %d finding(s)" % (rid, rules[rid]))
    for rid in sorted(rep):
        n, red = rep[rid]
        print("repair %s: %d line(s), %d execute red-before (%.0f%%) - promote at >= 95%%" % (rid, n, red, 100.0 * red / n))
    return 0


# ---------------------------------------------------------------- restore
_MARK = re.compile(r"\s*<!-- spec-gate:(\S+)(?: (\S+))?(?: [^>]*?)? -->\s*$")


def restore(repo, key):
    ovn = ovn_dir()
    qp = os.path.join(ovn, "backlog", "quarantine", repo + ".md")
    backlog = os.path.join(ovn, "backlog", repo + ".md")
    prefix = key.split("-")[0]
    if len(prefix) < 6:
        print("restore: key must be at least 6 hex chars of the item_key")
        return 2
    keep, back = [], []
    for l in read(qp).split("\n"):
        m = _MARK.search(l)
        if m and E.line_hash(_MARK.sub("", l)).startswith(prefix):
            back.append(_MARK.sub("", l))
        elif l != "" or keep:
            keep.append(l)
    if not back:
        print("restore: no quarantined line matches %s" % key)
        return 1
    tmp = qp + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(keep).rstrip("\n") + ("\n" if keep else ""))
    os.replace(tmp, qp)
    cur = read(backlog)
    with open(backlog + ".tmp", "w", encoding="utf-8") as f:
        f.write(cur.rstrip("\n") + ("\n" if cur else "") + "\n".join(back) + "\n")
    os.replace(backlog + ".tmp", backlog)
    mark_restored(ovn, repo, back)
    print("restored %d line(s) to %s" % (len(back), backlog))
    return 0


def main(argv):
    if _IMPORT_ERR is not None:
        if len(argv) >= 2 and argv[1] == "lint":
            sys.stderr.write("spec-gate lint unavailable (%s) - input echoed unchanged\n" % _IMPORT_ERR)
            sys.stdout.write(sys.stdin.read())
            return 0
        sys.stderr.write("ovn_spec_gate: cannot import its modules: %s\n" % _IMPORT_ERR)
        return 1
    if len(argv) >= 3 and argv[1] == "scan":
        return scan(argv[2])
    if len(argv) >= 2 and argv[1] == "lint":
        return lint_stream()
    if len(argv) >= 2 and argv[1] == "report":
        return report()
    if len(argv) >= 4 and argv[1] == "restore":
        return restore(argv[2], argv[3])
    sys.stderr.write("usage: ovn_spec_gate.py scan <repo> | lint [<repo_dir>] | report | restore <repo> <item_key>\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
