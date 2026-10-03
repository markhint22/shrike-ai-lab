#!/usr/bin/env python3
"""claude_queue_bridge.{py,sh}: the bug-first hand-off reaches CLAUDE_QUEUE.md (2026-10-03, A7-1, branch qa/h11-bug-pipeline).

Real failures reproduced (Chickadee, 10-03 diagnosis, BUG-2):
  * '[CLAUDE] [bug-escalated: ...]' lines (the bug-first escalation) were never harvested: the bridge only read AUTO-SKIP lines.
  * task_sig() keyed on the first 12 words, which for '[T3] <long android path> ...' are all path, so THREE different StreamsViewModel.kt bugs shared one
    signature: harvest dropped two as duplicates and retire would have closed all three when one was ticked.
Negative controls: two same-file bugs must NOT collapse; a 'sibling step' line must NOT become a second queue item; a retire of one bug must not close
the others. Benign controls: an old-style AUTO-SKIP line without a feat tag still dedupes by text; re-running the bridge appends nothing.
The shell half (the grep/sed run on the box over ssh) is exercised by running the REAL claude_queue_bridge.sh against stub ssh/scp (no network).
Runs on the box / any GNU host (the bridge's commit pass uses flock):  python3 scripts/test/test_bridge_bug_harvest.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OVNQ = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, OVNQ)
import claude_queue_bridge as cb  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


PATH_KT = "iptv-android/app/src/main/java/com/chickadeestreams/iptv/ui/mobile/StreamsViewModel.kt"


def bug(flow, h, note):
    return ("[T3] %s — Manual-test bug (reported by Mark, flow %s, 2026-10-01): %s First write a failing test that reproduces this, then fix it. "
            "VERIFY: `cd iptv-android && ./gradlew testDebugUnitTest` (cat:bugfix; multifile:no; src:manual) [feat:iptv-20261001-manual-%s]" % (PATH_KT, flow, note, h))


B_COUNTRY = bug("countries-filter", "aaaa1111", "The countries filter only showed All and Qatar 2.")
B_DOWNLOAD = bug("download-button", "bbbb2222", "The download button spins forever on a finished item.")
B_RECORD = bug("record-button", "cccc3333", "The record button shows no recording indication.")

print("== task_sig (unit)")
s1, s2, s3 = cb.task_sig(B_COUNTRY), cb.task_sig(B_DOWNLOAD), cb.task_sig(B_RECORD)
ok("three different same-file bugs => three DISTINCT signatures (was one shared signature)", len({s1, s2, s3}) == 3, (s1, s2, s3))
ok("the same bug in queue format and bare format => the SAME signature (cross-format dedup intact)",
   cb.task_sig("[CLAUDE] iptv_apps/ — " + B_COUNTRY) == s1 and cb.task_sig("[CLAUDE] [bug-escalated: 2 failed attempts] " + B_COUNTRY) == s1)
ok("the retest round (.r1) is a new signature (a reopened bug is a new item)", cb.task_sig(B_COUNTRY.replace("aaaa1111]", "aaaa1111.r1]")) != s1)
old_a = "[T2] backend/app/routers/alerts.py — Fix the alerts router so that it returns a list for a brand new account. VERIFY: `pytest -q`"
ok("a line WITHOUT a feat tag keeps the old text signature", cb.task_sig(old_a) == cb.norm_sig("backend/app/routers/alerts.py — Fix the alerts router so that it returns a list for a brand new account. VERIFY: `pytest -q`")
   and "feat" not in cb.task_sig(old_a))

print("== strip / line regexes")
esc = "- [ ] [CLAUDE] [bug-escalated: 2 failed attempts (cap 2), last: stage-runner: staged landed 0 of 2] " + B_COUNTRY
ok("strip_autoskip_task recognises an escalated bug line and strips the tag", cb.strip_autoskip_task(esc) == B_COUNTRY, cb.strip_autoskip_task(esc))
ok("an ordinary open line is not touched", cb.strip_autoskip_task("- [ ] [T2] backend/app/x.py — do a thing that is long enough to count") is None)
ok("a plain [CLAUDE] line (no bug-escalated) is not a harvest/retire candidate", cb.strip_autoskip_task("- [ ] [CLAUDE] [T3] x/y.py — some Claude-only item long enough") is None)

print("== harvest + retire through the REAL bridge.sh (stub ssh/scp)")
if not shutil.which("flock"):
    print("  SKIP: needs flock (run on the box)")
    print("%d passed, %d failed" % (P, F))
    sys.exit(0 if F == 0 else 1)

tmp = tempfile.mkdtemp(prefix="bridge-h11-")
try:
    home = os.path.join(tmp, "home")
    shared = os.path.join(tmp, "shared")
    stubs = os.path.join(tmp, "stubs")
    prog_dir = os.path.join(home, "overnight-queue", "repos", "iptv_apps")
    os.makedirs(prog_dir)
    os.makedirs(stubs)
    os.makedirs(os.path.join(shared, "scripts", "overnight-queue", "scripts"))
    os.makedirs(os.path.join(shared, "scripts", "overnight-queue", "state"))
    for f in ("claude_queue_bridge.py", "claude_queue_bridge.sh", "archive_claude_queue_done.py"):
        shutil.copy(os.path.join(OVNQ, f), os.path.join(shared, "scripts", "overnight-queue", f))
    shutil.copy(os.path.join(OVNQ, "scripts", "lib_lock.sh"), os.path.join(shared, "scripts", "overnight-queue", "scripts", "lib_lock.sh"))
    # ssh stub: run the remote command locally with HOME=fake home (last argv = the command). scp stub: cp to the path after 'host:~/'
    open(os.path.join(stubs, "ssh"), "w").write('#!/usr/bin/env bash\nfor a in "$@"; do c="$a"; done\nHOME="%s" exec bash -c "$c"\n' % home)
    open(os.path.join(stubs, "scp"), "w").write(
        '#!/usr/bin/env bash\nsrc=""; dst=""\nwhile [ $# -gt 0 ]; do case "$1" in -o) shift;; *) if [ -z "$src" ]; then src="$1"; else dst="$1"; fi;; esac; shift; done\n'
        'p="${dst#*:~/}"; mkdir -p "$(dirname "%s/$p")"; cp "$src" "%s/$p"\n' % (home, home))
    for f in ("ssh", "scp"):
        os.chmod(os.path.join(stubs, f), 0o755)
    prog = "\n".join([
        "# Progress", "## Next Steps",
        "- [ ] [CLAUDE] [bug-escalated: 2 failed attempts (cap 2), last: stage-runner: staged landed 0 of 2] " + B_COUNTRY,
        "- [ ] [CLAUDE] [bug-escalated: sibling step of this bug escalated] " + B_COUNTRY.replace("only showed All", "only showed All step two"),
        "- [ ] [AUTO-SKIP staged: 27B could not land this (beyond it) — route to CLAUDE] " + B_DOWNLOAD,
        "- [ ] [CLAUDE] [bug-escalated: 2 failed attempts (cap 2), last: stage-runner: staged landed 0 of 1] " + B_RECORD,
        "- [ ] [AUTO-SKIP staged: 27B could not land this (beyond it) — route to CLAUDE] " + old_a,
        "- [ ] [T2] backend/app/other.py — an ordinary open item that must never be harvested at all", ""])
    open(os.path.join(prog_dir, "OVERNIGHT_PROGRESS.md"), "w").write(prog)
    queue = os.path.join(shared, "CLAUDE_QUEUE.md")
    open(queue, "w").write("# Claude queue\n\n## Open\n")
    subprocess.run(["git", "init", "-q", "-b", "develop", shared], check=True)
    subprocess.run(["git", "init", "-q", "--bare", os.path.join(tmp, "origin.git")], check=True)
    subprocess.run(["git", "-C", shared, "remote", "add", "origin", os.path.join(tmp, "origin.git")], check=True)
    subprocess.run(["git", "-C", shared, "add", "CLAUDE_QUEUE.md"], check=True)
    subprocess.run(["git", "-C", shared, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed"], check=True)
    subprocess.run(["git", "-C", shared, "config", "user.email", "t@t"], check=True)
    subprocess.run(["git", "-C", shared, "config", "user.name", "t"], check=True)
    env = {"PATH": stubs + ":" + os.environ["PATH"], "HOME": home, "SHARED_DIR": shared, "OVN_SSH": "stub", "OVN_REMOTE_DIR": "overnight-queue",
           "NTFY_SERVER": "http://127.0.0.1:1"}

    def bridge():
        p = subprocess.run(["bash", os.path.join(shared, "scripts", "overnight-queue", "claude_queue_bridge.sh")], env=env, capture_output=True, timeout=120)
        return p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")

    rc, out = bridge()
    q = open(queue).read()
    items = [l for l in q.split("\n") if l.startswith("- [ ] [CLAUDE] iptv_apps/")]
    ok("bridge ran clean", rc == 0, out)
    ok("harvest appended the escalated countries bug (was never harvested)", "flow countries-filter" in q, q)
    ok("harvest appended the AUTO-SKIP download bug (was dropped: same signature as its siblings)", "flow download-button" in q, q)
    ok("harvest appended the escalated record bug", "flow record-button" in q, q)
    ok("exactly 4 new items: 3 bugs + the feat-less AUTO-SKIP line", len([l for l in items]) == 4, items)
    ok("the 'sibling step' line is NOT a second queue item", "step two" not in q)
    ok("the escalation tag is stripped from the queue text", "bug-escalated" not in q and "AUTO-SKIP" not in q, q)
    ok("the ordinary open item is never harvested", "ordinary open item" not in q)
    ok("harvest says it appended 4", "appended 4 new items" in out, out)
    rc, out = bridge()
    ok("idempotent: a second pass appends nothing", rc == 0 and "nothing new to add" in out and open(queue).read() == q, out)
    # tick ONLY the download bug in the queue -> the next pass retires ONLY that line server-side
    lines = open(queue).read().split("\n")
    lines = [l.replace("- [ ] ", "- [x] ", 1) if "manual-bbbb2222" in l else l for l in lines]
    open(queue, "w").write("\n".join(lines))
    rc, out = bridge()
    srvprog = open(os.path.join(prog_dir, "OVERNIGHT_PROGRESS.md")).read().split("\n")
    dl = [l for l in srvprog if "manual-bbbb2222" in l][0]
    ok("retire closed the ticked download bug server-side", dl.startswith("- [x] ") and "retired" in dl, dl)
    ok("retire left the other two same-file bugs OPEN (the shared-signature bug would have closed all three)",
       all(l.startswith("- [ ] ") for l in srvprog if "manual-aaaa1111" in l or "manual-cccc3333" in l), [l[:60] for l in srvprog])
    ok("retire says RETIRED exactly 1 AUTO-SKIP item", "retired 1 AUTO-SKIP" in out, out)
    # benign: tick the escalated countries item -> its progress line (the [CLAUDE] [bug-escalated] one) is retired, its sibling is not touched
    lines = open(queue).read().split("\n")
    lines = [l.replace("- [ ] ", "- [x] ", 1) if "manual-aaaa1111" in l else l for l in lines]
    open(queue, "w").write("\n".join(lines))
    rc, out = bridge()
    srvprog = open(os.path.join(prog_dir, "OVERNIGHT_PROGRESS.md")).read().split("\n")
    ok("an escalated bug ticked in CLAUDE_QUEUE.md is retired server-side too", any(l.startswith("- [x] [CLAUDE] [bug-escalated: 2 failed") and "manual-aaaa1111" in l and "step two" not in l for l in srvprog), [l[:80] for l in srvprog])
    ok("... together with its sibling step (same bug)", any(l.startswith("- [x] [CLAUDE] [bug-escalated: sibling") and "step two" in l for l in srvprog), [l[:80] for l in srvprog])
    ok("the record bug is still open", any(l.startswith("- [ ] ") and "manual-cccc3333" in l for l in srvprog))
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("%d passed, %d failed" % (P, F))
sys.exit(0 if F == 0 else 1)
