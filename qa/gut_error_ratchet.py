#!/usr/bin/env python3
"""qa/gut_error_ratchet.py - SHADOW ratchet over the GUT `SCRIPT ERROR`s a green suite hides (2026-10-09).

Why: GUT exits green with every test passing while the engine log of the same run carries SCRIPT ERRORs (xlite on 2026-10-09: 171-180 of them, ~8 distinct
sites - battle.gd _refresh_ap_display x65, _refresh_hit_chance_display x62-72, _end_battle create_timer, _rebuild_cover_objects, tests/test_uid_hygiene.gd
_check_orphans x25). All the battle.gd sites are hard-banned for the fleet, so nobody can fix them mechanically - but a NEW signature appearing means a landing
introduced a fresh runtime error that no assertion caught. This tool makes that visible without blocking anything (enforcement is a later flip).

usage: gut_error_ratchet.py run <repo_dir> [--update-baseline] [--json]
           run the FULL GUT suite in a scratch copy (`git archive` of origin/overnight/feature, falls back to HEAD; the live clone is never touched; nice 15),
           strip ANSI, parse `SCRIPT ERROR: <msg>` + next-line `at: <func> (res://file:line)`, compare the signature SET with the baseline.
       gut_error_ratchet.py parse <logfile> [--json]     signatures of an existing log (no run)
signature = (normalised message, function, file); line numbers, object ids and addresses are NOT part of it, so a refactor that moves a site does not alarm.
baseline: state/gut_script_errors_baseline.json {repo: {updated, signatures: {sig: count}}}; created ONLY by --update-baseline, never automatically.
NEW signature  -> one `[ts] warn | gut-script-error | <sig>` line in state/alerts.log (deduped per signature per day: state/gut_ratchet_alerted.json).
REMOVED one    -> reported as fixed (no alert). No baseline yet -> the signatures are listed and nothing is alerted.
env: OVN_DIR (default ~/overnight-queue), OVN_GODOT_BIN (default ~/godot/godot4), OVN_MUT_REF (default origin/overnight/feature), OVN_GUT_TIMEOUT (default 900),
     OVN_GUT_RATCHET = shadow (default: always exit 0) | enforce (exit 1 when a NEW signature appears - the later flip) | off (no-op).
exit: 0 always in shadow mode, including on internal errors.
"""
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

OVN_DIR = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
ERR = re.compile(r"^SCRIPT ERROR:\s*(.*?)\s*$")
AT = re.compile(r"^\s*at:\s+(.*?)\s+\((\S+?):(\d+)\)\s*$")


def godot_bin():
    return os.environ.get("OVN_GODOT_BIN") or os.path.join(os.path.expanduser("~"), "godot", "godot4")


def normalise(msg):
    """Message without the parts that change between runs: addresses, object ids, line refs, runs of blanks."""
    m = re.sub(r"0x[0-9a-fA-F]+", "0x?", msg)
    m = re.sub(r"<[A-Za-z0-9_]*#\d+>", "<obj>", m)
    m = re.sub(r"\(\s*[A-Za-z0-9_]+:\d+\s*\)", "(?)", m)
    m = re.sub(r":\d+\b", ":N", m)
    return re.sub(r"\s+", " ", m).strip()


def parse_log(text):
    """-> list of (signature, msg, func, file, line). One entry per SCRIPT ERROR occurrence."""
    lines = ANSI.sub("", text).replace("\r", "").split("\n")
    out = []
    i = 0
    while i < len(lines):
        m = ERR.match(lines[i])
        if m:
            func, fil, ln = "?", "?", 0
            if i + 1 < len(lines):
                a = AT.match(lines[i + 1])
                if a:
                    func, fil, ln = a.group(1), re.sub(r"^res://", "", a.group(2)), int(a.group(3))
                    i += 1
            msg = normalise(m.group(1))
            out.append((" | ".join((msg, func, fil)), msg, func, fil, ln))
        i += 1
    return out


def signature_counts(text):
    c = {}
    for sig, *_ in parse_log(text):
        c[sig] = c.get(sig, 0) + 1
    return c


def compare(current, baseline):
    """-> (new, fixed) as sorted lists of signatures."""
    return sorted(set(current) - set(baseline)), sorted(set(baseline) - set(current))


def _load(path, default):
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return default


def _save(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w") as f:
        json.dump(obj, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


def alert(sig, state_dir):
    """ONE warn line per signature per day."""
    seen_p = os.path.join(state_dir, "gut_ratchet_alerted.json")
    seen = _load(seen_p, {})
    today = datetime.date.today().isoformat()
    if seen.get(sig) == today:
        return False
    seen[sig] = today
    _save(seen_p, seen)
    with open(os.path.join(state_dir, "alerts.log"), "a") as f:
        f.write("[%s] warn | gut-script-error | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), sig))
    return True


def archive_tree(repo_dir, dest):
    ref = os.environ.get("OVN_MUT_REF", "origin/overnight/feature")
    if subprocess.run(["git", "-C", repo_dir, "rev-parse", "-q", "--verify", ref + "^{commit}"], capture_output=True).returncode != 0:
        ref = "HEAD"
    p1 = subprocess.Popen(["git", "-C", repo_dir, "archive", ref], stdout=subprocess.PIPE)
    subprocess.run(["tar", "-x", "-C", dest], stdin=p1.stdout, check=True)
    p1.stdout.close()
    if p1.wait() != 0 or not os.path.exists(os.path.join(dest, "project.godot")):
        raise RuntimeError("git archive of %s failed or has no project.godot" % ref)
    return ref


def seed_and_import(scratch, repo_dir):
    """Copy the live clone's gitignored import cache (read-only), then run the incremental headless --import."""
    if os.path.isdir(os.path.join(repo_dir, ".godot")) and shutil.which("rsync"):
        subprocess.run(["rsync", "-a", "--include=.godot/***", "--include=*/", "--include=*.import", "--exclude=*", "--prune-empty-dirs", repo_dir.rstrip("/") + "/", scratch + "/"],
                       capture_output=True)
    if os.path.exists(godot_bin()):
        try:
            subprocess.run([godot_bin(), "--headless", "--path", ".", "--import"], cwd=scratch, capture_output=True, timeout=300, preexec_fn=lambda: os.nice(15))
        except (subprocess.TimeoutExpired, OSError):
            pass


def run_suite(scratch):
    cmd = [godot_bin(), "--headless", "--path", ".", "-s", "addons/gut/gut_cmdln.gd", "-gdir=res://tests", "-ginclude_subdirs", "-gexit"]
    p = subprocess.Popen(cmd, cwd=scratch, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace", start_new_session=True,
                         preexec_fn=lambda: os.nice(15))
    try:
        out, _ = p.communicate(timeout=int(os.environ.get("OVN_GUT_TIMEOUT", "900")))
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, 9)
        p.communicate()
        return None
    return out


def run(repo_dir, update_baseline, as_json):
    mode = os.environ.get("OVN_GUT_RATCHET", "shadow")
    name = os.path.basename(os.path.abspath(repo_dir))
    sd = os.path.join(OVN_DIR, "state")
    base_p = os.path.join(sd, "gut_script_errors_baseline.json")
    res = {"repo": name, "mode": mode}
    scratch = tempfile.mkdtemp(prefix="gutratchet-")
    try:
        res["ref"] = archive_tree(repo_dir, scratch)
        seed_and_import(scratch, repo_dir)
        out = run_suite(scratch)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    if out is None:
        res["error"] = "GUT run timed out"
        return finish(res, as_json, mode, [])
    if not re.search(r"^\s*Tests\s+\d+", ANSI.sub("", out), re.M):
        # the run did not reach GUT's summary (crash, no project, import failure): an empty result must never read as 'every signature was fixed'
        res["error"] = "no GUT summary in the output - the run did not complete"
        return finish(res, as_json, mode, [])
    cur = signature_counts(out)
    res["errors"] = sum(cur.values())
    res["signatures"] = len(cur)
    all_base = _load(base_p, {})
    base = all_base.get(name)
    if update_baseline:
        all_base[name] = {"updated": int(time.time()), "ref": res["ref"], "signatures": cur}
        _save(base_p, all_base)
        res["baseline"] = "updated (%d signatures)" % len(cur)
        res["new"], res["fixed"] = [], []
        return finish(res, as_json, mode, [])
    if base is None:
        res["baseline"] = "none yet - review the signatures, then run with --update-baseline"
        res["new"], res["fixed"] = [], []
        res["current"] = cur
        return finish(res, as_json, mode, [])
    new, fixed = compare(cur, base.get("signatures", {}))
    res["baseline"] = "%d signatures" % len(base.get("signatures", {}))
    res["new"], res["fixed"] = new, fixed
    alerted = [s for s in new if alert(s, sd)]
    res["alerted"] = len(alerted)
    return finish(res, as_json, mode, new)


def finish(res, as_json, mode, new):
    if as_json:
        print(json.dumps(res, sort_keys=True))
    else:
        print("gut ratchet %s [%s]: %s errors, %s signatures, baseline: %s; NEW %d, fixed %d%s" % (
            res.get("repo"), res.get("mode"), res.get("errors", "?"), res.get("signatures", "?"), res.get("baseline", "-"), len(res.get("new", [])),
            len(res.get("fixed", [])), ("; ERROR: " + res["error"]) if res.get("error") else ""))
        for s in res.get("new", []):
            print("  NEW   " + s)
        for s in res.get("fixed", []):
            print("  fixed " + s)
        if "current" in res:
            for s, n in sorted(res["current"].items()):
                print("  %4d x %s" % (n, s))
    return 1 if (mode == "enforce" and new) else 0


def main(argv):
    if len(argv) < 3 or argv[1] not in ("run", "parse"):
        print(__doc__)
        return 0
    if os.environ.get("OVN_GUT_RATCHET", "shadow") == "off":
        print("gut ratchet: OVN_GUT_RATCHET=off - skip")
        return 0
    try:
        if argv[1] == "parse":
            c = signature_counts(open(argv[2], errors="replace").read())
            if "--json" in argv:
                print(json.dumps(c, sort_keys=True))
            else:
                for s, n in sorted(c.items()):
                    print("%4d x %s" % (n, s))
            return 0
        return run(argv[2], "--update-baseline" in argv, "--json" in argv)
    except Exception as e:   # shadow mode never fails the cron line
        print("gut ratchet: internal error: %s: %s" % (type(e).__name__, str(e)[:200]))
        return 1 if os.environ.get("OVN_GUT_RATCHET", "shadow") == "enforce" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
