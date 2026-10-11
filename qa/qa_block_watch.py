#!/usr/bin/env python3
"""qa_block_watch.py - make an enforcing QA block self-resolving or LOUD (2026-10-08).

Incident: on 2026-10-07 15:02 CDT the antigaming gate (enforcing since 10-05) blocked iptv_apps overnight/feature on ONE FAIL-severity finding - a
net-new placeholder test (`def test_placeholder(): assert True`) in app/jobs/ - and held 235 commits of fleet work away from develop/staging for 17
hours. The block raised exactly one alert line in alerts.log (by design, "no 5th channel"), nobody was looking at that file, and the fleet kept
piling work behind the block.

Each run, for every record in state/qa_blocked/*.json:
  1. re-run the blocking gate on the CURRENT branch tip (net diff against develop). No FAIL left -> nothing to do, the next hygiene pass clears the record.
  2. SELF-HEAL the one class that is provably harmless to remove: every remaining FAIL is A_VACUOUS on a file that is (a) net-new on the branch and (b) a
     placeholder-only test module (only imports/docstrings/test functions whose bodies are pass / docstring / tautological assert). Those are the
     pipeline's own "stub the new file" leftovers. They are deleted in ONE commit on the feature branch (temp worktree, non-force push, retry) and an
     alert line says so. Anything else (a real finding, another gate, a protected branch) is never touched.
  3. otherwise, if the block is old (>= QA_BLOCK_STALL_H hours, default 3) or big (>= QA_BLOCK_STALL_COMMITS held, default 20), write a
     `qa-block-stall` warn line (at most one per QA_BLOCK_REALERT_H hours per block, default 6) naming the finding, so the hourly digest/triage sees it.

  4. (2026-10-10) ESCALATE: a stall older than QA_BLOCK_EMERGENCY_H (default 6) or holding >= QA_BLOCK_EMERGENCY_COMMITS (default 100) is also written as a high-priority note into state/notify_notes.jsonl
     on EVERY run, so the ONE hourly update (scripts/ovn_notify.py) lists it - alerts.log alone is a warn line nobody reads (xlite: 19.7 h blocked by a
     false positive, two stall alerts, no human saw them).
  5. (2026-10-10) DEMOTE (default OFF: QA_BLOCK_DEMOTE=on): after QA_BLOCK_DEMOTE_H hours (default 4) a block whose FAIL findings are ALL in test files
     AND in the allow-list QA_BLOCK_DEMOTE_RULES (test-only rules: E_ZERO_ASSERTS, A_VACUOUS, ...) is demoted FAIL -> FLAG for exactly those (rule, file)
     pairs: a record in state/qa_demoted.json (read by gate_antigaming.check, bound to the offending commit being in the head's history, expires after
     QA_DEMOTE_TTL_H = 168 h, global kill switch OVN_QA_DEMOTE=off), one line in state/qa_gate_modes.history.jsonl (who=qa_block_watch) and ONE alert.
     A block with any product-code finding, any other rule, a protected branch or another gate is never demoted. The next hygiene pass re-evaluates the
     range, sees FLAG, and lets the held commits through.

usage: qa_block_watch.py [--dry-run]       env: OVN_DIR, QA_GATES_DIR, QA_BLOCK_*  ; exit 0 always (it must never break the cron/hygiene chain)
"""
import ast
import calendar
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

PROTECTED_OK = re.compile(r"^(overnight|claude)/feature$")


def _num(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def git(repo, *a, timeout=120, check=False):
    r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, timeout=timeout)
    if check and r.returncode:
        raise RuntimeError("git %s: %s" % (" ".join(a[:2]), r.stderr.strip()[:200]))
    return r.stdout.strip()


def alert(msg):
    try:
        with open(os.path.join(qc.state_dir(), "alerts.log"), "a") as f:
            f.write("[%s] warn | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
    except OSError:
        pass


DEMOTE_RULES_DEFAULT = "E_ZERO_ASSERTS,A_VACUOUS,A_VACUOUS_ASSERT,A_ASSERT_NOOP,A_TESTFILE_EMPTIED,E_TEST_NOT_COLLECTED,E_GD_TEST_NOT_GUT"
DEMOTED_FILE = "qa_demoted.json"
NOTES_FILE = "notify_notes.jsonl"


def is_test_file(path):
    """Same classification as the gate (gate_antigaming.is_test_path); a plain regex when the gate module cannot be imported."""
    try:
        import gate_antigaming as ga
        return bool(ga.is_test_path(path))
    except Exception:  # noqa: BLE001
        return re.search(r"(^|/)(tests?|__tests__|e2e)/|(^|/)test_[^/]*$|_test\.[A-Za-z]+$|\.(test|spec)\.[cm]?[jt]sx?$", path or "") is not None


def demotable(gate, branch, fails):
    """-> sorted [(rule, file)] when EVERY FAIL finding is a test-file finding of an allow-listed rule on a protected feature branch of the antigaming
    gate, else None. QA_BLOCK_DEMOTE_RULES overrides the allow-list (comma separated)."""
    if gate != "antigaming" or PROTECTED_OK.match(branch or "") is None or not fails:
        return None
    allow = {r.strip() for r in os.environ.get("QA_BLOCK_DEMOTE_RULES", DEMOTE_RULES_DEFAULT).split(",") if r.strip()}
    pairs = set()
    for f in fails:
        rule, path = f.get("rule", ""), f.get("file", "")
        if rule not in allow or not path or not is_test_file(path):
            return None
        pairs.add((rule, path))
    return sorted(pairs)


def _atomic_json(path, obj):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".qa_demoted.", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f, indent=1, sort_keys=True)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def demote(repo_name, branch, rec, pairs, age_h, dry):
    """Record the demotion (idempotent per (repo, branch, offender commit)). -> 'demoted' | 'already' | 'dry-run' | 'failed'."""
    key = "%s__%s" % (repo_name, re.sub(r"[^A-Za-z0-9._-]", "_", branch))
    path = os.path.join(qc.state_dir(), DEMOTED_FILE)
    try:
        cur = json.load(open(path))
        if not isinstance(cur, dict):
            cur = {}
    except (OSError, ValueError):
        cur = {}
    commit = str(rec.get("commit", ""))
    if cur.get(key, {}).get("commit") == commit and commit:
        return "already"
    if dry:
        return "dry-run"
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    cur[key] = {"repo": repo_name, "branch": branch, "gate": rec.get("gate", "antigaming"), "commit": commit, "rules": sorted({r for r, _ in pairs}),
                "files": sorted({p for _, p in pairs}), "ts": now, "who": "qa_block_watch", "age_h": round(age_h, 1)}
    try:
        _atomic_json(path, cur)
        with open(os.path.join(qc.state_dir(), qc.GATE_MODES_HISTORY), "a") as f:
            f.write(json.dumps({"ts": now, "gate": "%s:%s/%s" % (rec.get("gate", "antigaming"), repo_name, branch), "from": "FAIL", "to": "FLAG", "who": "qa_block_watch",
                                "commit": commit[:12], "rules": cur[key]["rules"], "files": cur[key]["files"]}, sort_keys=True) + "\n")
    except OSError:
        return "failed"
    return "demoted"


def escalate_note(repo_name, branch, gate, held, age_h, top, dry):
    """High-priority note for the hourly update (scripts/ovn_notify.py reads state/notify_notes.jsonl: title/text/prio/ts). Written on EVERY run while the
    stall lasts: the hourly update only lists notes newer than the previous update."""
    title = "QA block stalled %dh: %s (%s)" % (int(age_h), repo_name, branch or "?")
    text = "gate=%s holds %s commit(s): %s %s:%s - fix forward or demote it" % (gate, held, top.get("rule", "?"), top.get("file", "?"), top.get("line", "?"))
    if dry:
        print("would escalate to the hourly update: %s | %s" % (title, text))
        return
    try:
        with open(os.path.join(qc.state_dir(), NOTES_FILE), "a") as f:
            f.write(json.dumps({"ts": time.time(), "title": title, "text": text[:160], "prio": "high", "source": "qa_block_watch"}, ensure_ascii=False) + "\n")
    except OSError:
        pass


def gate_findings(gate, repo, base, head):
    """-> list of finding dicts from `gate_<gate>.py check` (no-record, no enforce exit), or None when the gate gave nothing parsable."""
    gdir = os.environ.get("QA_GATES_DIR") or HERE
    script = os.path.join(gdir, "gate_%s.py" % gate)
    if not os.path.isfile(script):
        return None
    r = subprocess.run([sys.executable, script, "check", "--repo", repo, "--base", base, "--head", head, "--no-record"],
                       capture_output=True, text=True, timeout=300)
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    try:
        res = json.loads(lines[-1])
    except (IndexError, ValueError):
        return None
    return res.get("details", {}).get("findings", []) or []


def is_placeholder_test(src):
    """True if the module holds nothing but imports, docstrings and test functions whose bodies are `pass`, a docstring or a tautological assert."""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return False
    tests = 0
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            continue
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            continue
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test"):
            tests += 1
            for st in node.body:
                if isinstance(st, ast.Pass):
                    continue
                if isinstance(st, ast.Expr) and isinstance(st.value, ast.Constant):
                    continue
                if isinstance(st, ast.Assert) and isinstance(st.test, ast.Constant) and st.test.value:
                    continue
                return False
            continue
        return False
    return tests > 0


def self_heal(repo, branch, files, dry):
    """Delete `files` in one commit on origin/<branch> via a temp worktree (non-force push, 3 tries). -> pushed short sha, or '' on failure."""
    if dry:
        return "dry-run"
    for _ in range(3):
        wt = tempfile.mkdtemp(prefix="qa-block-heal-")
        try:
            git(repo, "fetch", "-q", "origin", branch)
            git(repo, "worktree", "add", "--detach", wt, "origin/" + branch, check=True)
            for f in files:
                git(wt, "rm", "-q", "--ignore-unmatch", f)
            if not git(wt, "status", "--porcelain"):
                return "nothing-to-delete"
            git(wt, "-c", "user.name=qa-block-watch", "-c", "user.email=qa-block-watch@localhost", "commit", "-q", "-m",
                "fix(qa): delete net-new placeholder test file(s) that hold the antigaming gate (assert True, no behaviour): %s" % ", ".join(files))
            p = subprocess.run(["git", "-C", wt, "push", "origin", "HEAD:" + branch], capture_output=True, text=True, timeout=120)
            if p.returncode == 0:
                return git(wt, "rev-parse", "--short", "HEAD")
        finally:
            subprocess.run(["git", "-C", repo, "worktree", "remove", "--force", wt], capture_output=True)
            subprocess.run(["rm", "-rf", wt])
    return ""


def handle(rec, ovn_dir, dry, alerted):
    repo_name, branch, gate = rec.get("repo", ""), rec.get("branch", ""), rec.get("gate", "")
    repo = os.path.join(ovn_dir, "repos", repo_name)
    key = "%s__%s" % (repo_name, branch)
    if not (os.path.isdir(os.path.join(repo, ".git")) or os.path.isfile(os.path.join(repo, ".git"))):
        return "no-clone"
    git(repo, "fetch", "-q", "origin")
    mt = os.environ.get("QA_BLOCK_MERGE_TARGET", "develop")
    tip = "origin/" + branch
    base = git(repo, "merge-base", "origin/" + mt, tip)
    if not base:
        return "no-merge-base"
    findings = gate_findings(gate, repo, base, tip)
    if findings is None:
        return "gate-unavailable"
    fails = [f for f in findings if f.get("sev") == "FAIL"]
    if not fails:
        return "resolved (no FAIL at the branch tip; hygiene clears the record on its next pass)"
    healable = gate == "antigaming" and PROTECTED_OK.match(branch or "") is not None
    files = []
    if healable:
        added = set(git(repo, "diff", "--name-only", "--diff-filter=A", "origin/" + mt + "..." + tip).split("\n"))
        for f in fails:
            path = f.get("file", "")
            src = git(repo, "show", "%s:%s" % (tip, path)) if path else ""
            if f.get("rule") == "A_VACUOUS" and path in added and src and is_placeholder_test(src):
                files.append(path)
            else:
                healable = False
                break
    if healable and files:
        sha = self_heal(repo, branch, sorted(set(files)), dry)
        if sha and dry:
            return "self-healed dry-run (would delete %s)" % ", ".join(sorted(set(files)))
        if sha:
            alert("qa-block-watch:%s | self-healed gate=%s block on %s: deleted %d net-new placeholder test file(s) (%s) in %s - %s held commit(s) can now flow" % (
                repo_name, gate, branch, len(set(files)), ", ".join(sorted(set(files)))[:160], sha, rec.get("held_commits", "?")))
            return "self-healed %s" % sha
        return "self-heal-push-failed"
    # not healable: loud, but not spammy
    try:
        age_h = (time.time() - calendar.timegm(time.strptime(rec.get("since", ""), "%Y-%m-%dT%H:%M:%SZ"))) / 3600.0
    except ValueError:
        age_h = 0.0
    held = int(rec.get("held_commits", 0) or 0)
    if os.environ.get("QA_BLOCK_DEMOTE", "off") == "on" and age_h >= _num("QA_BLOCK_DEMOTE_H", 4):
        pairs = demotable(gate, branch, fails)
        if pairs:
            r = demote(repo_name, branch, rec, pairs, age_h, dry)
            if r == "dry-run":
                return "would demote FAIL->FLAG (%s)" % ", ".join("%s %s" % p for p in pairs)
            if r == "demoted":
                alert("qa-block-watch:%s | DEMOTED gate=%s FAIL->FLAG on %s after %.1fh (test-file-only, allow-listed rule(s): %s): %s - the next hygiene pass lets the %s held commit(s) "
                      "through; the test itself still needs a human/Claude look (state/qa_demoted.json, revert = delete the record)" % (
                          repo_name, gate, branch, age_h, ", ".join(sorted({p[0] for p in pairs})), ", ".join(sorted({p[1] for p in pairs}))[:160], rec.get("held_commits", "?")))
                return "demoted"
            if r == "already":
                return "demoted (already; waiting for the next hygiene pass)"
    escalated = ""
    if age_h >= _num("QA_BLOCK_EMERGENCY_H", 6) or held >= _num("QA_BLOCK_EMERGENCY_COMMITS", 100):
        escalate_note(repo_name, branch, gate, held, age_h, fails[0], dry)
        escalated = " +hourly-update"
    if age_h >= _num("QA_BLOCK_STALL_H", 3) or held >= _num("QA_BLOCK_STALL_COMMITS", 20):
        last = alerted.get(key, 0)
        if time.time() - last >= _num("QA_BLOCK_REALERT_H", 6) * 3600:
            top = fails[0]
            (print if dry else alert)("qa-block-stall:%s | %s on %s has held %d commit(s) for %.1fh behind gate=%s: %s %s:%s %s - needs a human/Claude decision (fix forward or `qa_enforce.sh %s shadow`)" % (
                repo_name, repo_name, branch, held, age_h, gate, top.get("rule", "?"), top.get("file", "?"), top.get("line", "?"),
                str(top.get("msg", ""))[:120], gate))
            if not dry:
                alerted[key] = time.time()
            return "stall-alerted" + escalated
        return "stalled (already alerted)" + escalated
    return "blocked (young)" + escalated


def main(argv):
    dry = "--dry-run" in argv
    ovn_dir = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
    bdir = os.path.join(qc.state_dir(), "qa_blocked")
    apath = os.path.join(qc.state_dir(), "qa_block_watch_alerted.json")
    try:
        alerted = json.load(open(apath))
    except (OSError, ValueError):
        alerted = {}
    out = []
    try:
        names = sorted(os.listdir(bdir))
    except OSError:
        names = []
    for n in names:
        if not n.endswith(".json"):
            continue
        try:
            rec = json.load(open(os.path.join(bdir, n)))
            out.append("%s: %s" % (n[:-5], handle(rec, ovn_dir, dry, alerted)))
        except Exception as e:  # never break the caller
            out.append("%s: error %s" % (n, str(e)[:120]))
    if not dry:
        try:
            json.dump(alerted, open(apath, "w"))
        except OSError:
            pass
    print("; ".join(out) if out else "no QA blocks")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
