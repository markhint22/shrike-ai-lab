#!/usr/bin/env python3
"""baseline_verify_gut.py - GUT (Godot) refresh path for baseline_verify.py (gate S4, key `baseline`; SHADOW). 2026-10-10 (analysis F6).

Why: `baseline_verify.py refresh` only knew python/pytest repos, so xlite (the focus lane with the most stage-unverified runs: 96 of 158 in 14 days)
had NO baseline: every red xlite verify read UNVERIFIED "no baseline for repo" and the 3-hourly refresh cron burned one NA row per pass.

What `refresh --repo <godot repo>` does here (lazily imported by baseline_verify.cmd_refresh only when the repo has no .venv/bin/pytest):
  1. `git archive <ref>` of the repo into a PRIVATE scratch dir (never the live clone, never a worktree: nothing in the repo's .git is written);
  2. the same two headless `--import` passes branch_hygiene.sh does (the first warms the class cache, the second's output is parsed), then the
     same GUT command the staged runner/hygiene gate use: `addons/gut/gut_cmdln.gd -gdir=res://tests [-ginclude_subdirs] -gexit -gjunit_xml_file=...`
     (OVN_GUT_SUBDIRS=off drops -ginclude_subdirs exactly like the other callers);
  3. parse the `Run Summary` block (`res://file.gd::test` ids, `godot-parse:`/`godot-load:` ids) with baseline_verify.parse_gut - the SAME parser and
     the SAME unprefixed id shape parse_verify_log gives the runner's `-- GUT FULL --` section, so a refreshed id matches a verify-log id at compare time;
  4. cross-check the junit xml (the number of FAILING TESTCASES in the xml must equal the number of failing ids the log named; the root failures attribute
     counts failing asserts, not tests, so it is only checked for consistency; a red xml that no id explains is refused);
  5. hand the parse to baseline_verify.snapshot_set: deterministic only (complete parse, no hard failures), 24 h TTL checked at compare time, never
     auto-widen (growth => growth_pending + growth_alerts row, needs --accept-growth), refuses a mostly-red suite (> OVN_QA_BASELINE_MAX).
Everything runs through qa_common.run (nice -n 15, ionice -c3, QA_CPUSET) under a hard timeout; the scratch dir is always removed (and a dir leaked by an outer-timeout kill is swept by the next refresh after >= 1 h). Nothing here calls
an LLM. Godot's user dirs (XDG_*) point into the scratch dir so the box's real ~/.local/share/godot is neither read nor written.
Kill switches: those of baseline_verify (OVN_BASELINE_SHADOW / qa mode `baseline`=off); OVN_BASELINE_GUT=off disables just this path (-> NA, as before).
Binary: $OVN_GODOT_BIN, else ~/godot/godot4. Missing binary / no project.godot / no vendored GUT at the ref => NA (the repo type is not supported
HERE), never a guess."""
import os
import re
import shutil
import tempfile
import time

PARSER_TAG = "deterministic:refresh-gut"


def godot_bin():
    return os.environ.get("OVN_GODOT_BIN") or os.path.expanduser("~/godot/godot4")


def _has(qc, rd, ref, path):
    return qc.git(rd, "cat-file", "-e", "%s:%s" % (ref, path))[0] == 0


def supported(qc, rd, ref):
    """(True, '') when `ref` of the repo is a Godot project with a vendored GUT runner at its root (what the runner's GUT stage requires)."""
    if os.environ.get("OVN_BASELINE_GUT", "on") == "off":
        return False, "GUT refresh disabled (OVN_BASELINE_GUT=off)"
    if not _has(qc, rd, ref, "project.godot"):
        return False, "no project.godot at %s" % ref
    if not _has(qc, rd, ref, "addons/gut/gut_cmdln.gd"):
        return False, "no vendored addons/gut/gut_cmdln.gd at %s" % ref
    return True, ""


_ATTR = re.compile(r'\b(failures|errors)="(\d+)"')
# one <testcase ...> element (self-closing or with a body); quoted attribute values may contain '>'
_TESTCASE = re.compile(r"<testcase\b((?:[^>\"']|\"[^\"]*\"|'[^']*')*?)(?:/>|>(.*?)</testcase>)", re.S)
_MAX_XML = 32 * 1024 * 1024


def junit_counts(path):
    """(failures, errors, no_asserts, failing_testcases) from a GUT junit xml, or None when unreadable/empty/no root.
    failures/errors are the ROOT <testsuites> attributes: GUT sets them from totals.failing, i.e. the number of failing ASSERTS, so a test with 2 failing
    asserts adds 2 there. They are NOT a count of failing tests. failing_testcases is that count: the <testcase> elements that carry a <failure>/<error>
    child or status="fail"/"error" - the number comparable to the failing test ids the log names (2026-10-11: the old root-attribute comparison refused every
    red snapshot containing a multi-assert test)."""
    try:
        if os.path.getsize(path) > _MAX_XML:
            return None
        with open(path, errors="replace") as f:
            text = f.read()
    except OSError:
        return None
    if not text.strip():
        return None
    m = re.search(r"<testsuites\b[^>]*>", text.replace("\n", " ").replace("\r", " "))
    if not m:
        return None
    at = dict((k, int(v)) for k, v in _ATTR.findall(m.group(0)))
    if "failures" not in at and "errors" not in at:
        return None
    failing_tc = 0
    no_asserts = False
    for tc in _TESTCASE.finditer(text):
        attrs, body = tc.group(1), tc.group(2) or ""
        st = re.search(r'\bstatus="([^"]*)"', attrs)
        st = st.group(1) if st else ""
        if st == "no asserts":
            no_asserts = True
        if st in ("fail", "error") or re.search(r"<(?:failure|error)\b", body):
            failing_tc += 1
    return at.get("failures", 0), at.get("errors", 0), no_asserts, failing_tc


def sweep_stale(timeout, now=None):
    """Remove leftover `qa-gut-*` scratch dirs (git archive + Godot import cache, ~30 MB+ each on tmpfs) from runs the cron wrapper's qa_timeout.py KILLED:
    a SIGTERM/SIGKILL skips run_gut_in_scratch's `finally`. Only our own real directories (not symlinks) older than max(1 h, 2 x timeout) - far longer than any run can
    live - are removed, so a concurrent refresh is never touched. Returns the number removed; never raises."""
    base = tempfile.gettempdir()
    cutoff = (time.time() if now is None else now) - max(3600, 2 * int(timeout))
    n = 0
    try:
        names = os.listdir(base)
    except OSError:
        return 0
    for nm in names:
        if not nm.startswith("qa-gut-"):
            continue
        d = os.path.join(base, nm)
        try:
            st = os.lstat(d)
            if os.path.islink(d) or not os.path.isdir(d) or st.st_uid != os.getuid() or st.st_mtime >= cutoff:
                continue
            shutil.rmtree(d, ignore_errors=True)
            n += 1
        except OSError:
            continue
    return n


def run_gut_in_scratch(qc, rd, ref, timeout):
    """git-archive `ref` into a private temp dir, run import x2 + GUT there, ALWAYS remove it.
    Returns (rc, text, xml_path_counts, why): rc 0 = GUT ran to the end (rc of godot itself is ignored: -gexit/GUT exit codes are untrustworthy, the
    caller judges the log+xml), 124 = timeout, other non-zero = could not run (why says what)."""
    sweep_stale(timeout)
    tmp = tempfile.mkdtemp(prefix="qa-gut-")
    try:
        src = os.path.join(tmp, "src")
        os.makedirs(src)
        tar = os.path.join(tmp, "src.tar")
        rc, _, err = qc.git(rd, "archive", "--format=tar", "-o", tar, ref, timeout=180)
        if rc != 0:
            return 2, "", None, "git archive %s failed: %s" % (ref, (err or "").strip()[:120])
        rc, _, err = qc.run(["tar", "-xf", tar, "-C", src], polite=False, timeout=180)
        if rc != 0:
            return 2, "", None, "tar extract failed: %s" % (err or "").strip()[:120]
        os.unlink(tar)
        gb = godot_bin()
        env = {"XDG_DATA_HOME": os.path.join(tmp, "xdg-data"), "XDG_CONFIG_HOME": os.path.join(tmp, "xdg-config"),
               "XDG_CACHE_HOME": os.path.join(tmp, "xdg-cache")}
        t_end = time.time() + timeout

        def left(cap):
            return max(1, min(cap, int(t_end - time.time())))

        # pass 1 warms the class_name/asset cache (output discarded), pass 2's output is what the runner's GUT section would contain
        rc, _, _ = qc.run([gb, "--headless", "--path", ".", "--import"], cwd=src, timeout=left(120), env=env)
        if rc == 124:
            return 124, "", None, "godot --import timed out"
        if rc == 127:
            return 3, "", None, "godot binary not runnable: %s" % gb
        rc, imp, _ = qc.run([gb, "--headless", "--path", ".", "--import"], cwd=src, timeout=left(120), env=env)
        if rc == 124:
            return 124, "", None, "godot --import timed out"
        xml = os.path.join(tmp, "gut.xml")
        cmd = [gb, "--headless", "-s", "addons/gut/gut_cmdln.gd", "-gdir=res://tests"]
        if os.environ.get("OVN_GUT_SUBDIRS", "on") != "off":
            cmd.append("-ginclude_subdirs")
        cmd += ["-gexit", "-gjunit_xml_file=%s" % xml]
        rc, out, err = qc.run(cmd, cwd=src, timeout=left(max(30, timeout)), env=env)
        if rc == 124:
            return 124, "", None, "GUT run timed out"
        if rc == 127:
            return 3, "", None, "godot binary not runnable: %s" % gb
        return 0, (imp or "") + "\n" + (out or "") + "\n" + (err or ""), junit_counts(xml), ""
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def refresh(bv, a):
    """`baseline_verify.py refresh` for a Godot/GUT repo. `bv` is the baseline_verify module (passed in: no circular import)."""
    qc, v = bv.qc, bv._v
    rd = qc.repo_dir(a.repo)
    if not rd:
        return v("UNVERIFIED", a.repo, a.ref, "repo clone not found")
    ok, why = supported(qc, rd, a.ref)
    if not ok:
        return v("NA", a.repo, a.ref, "refresh supports python/pytest repos and Godot/GUT repos only (%s)" % why)
    if not (os.path.isfile(godot_bin()) and os.access(godot_bin(), os.X_OK)):
        return v("NA", a.repo, a.ref, "godot binary not found/executable (%s); GUT refresh needs the box's Godot" % godot_bin())
    rc0, sha, _ = qc.git(rd, "rev-parse", a.ref)
    if rc0 != 0:
        return v("UNVERIFIED", a.repo, a.ref, "cannot resolve %s in the clone (no network here: not fetched)" % a.ref)
    rc, text, xml, why = run_gut_in_scratch(qc, rd, a.ref, a.timeout)
    if rc == 124:
        return v("UNVERIFIED", a.repo, a.ref, "GUT suite timed out after %ss; baseline not updated" % a.timeout)
    if rc != 0:
        return v("UNVERIFIED", a.repo, a.ref, "GUT could not run (%s); baseline not updated" % why)
    parsed = bv.parse_gut(text, prefix="")
    n_named = len([i for i in parsed["ids"] if "::" in i])
    if parsed["complete"]:
        if xml is None:
            parsed["complete"] = False
            parsed["reasons"] = list(parsed["reasons"]) + ["no/unreadable junit xml (GUT did not finish its report)"]
        else:
            fails, errs, no_asserts, failing_tc = xml
            if no_asserts:
                parsed["complete"] = False
                parsed["reasons"] = list(parsed["reasons"]) + ['junit xml has status="no asserts" testcases: the runner counts that red but no id names it']
            elif failing_tc != n_named:
                parsed["complete"] = False
                parsed["reasons"] = list(parsed["reasons"]) + [
                    "junit xml has %d failing testcase(s) but the log names %d failing test(s): not a clean red-test snapshot" % (failing_tc, n_named)]
            elif (fails + errs > 0) != (failing_tc > 0) or fails + errs < failing_tc:
                # root counts are failing ASSERTS (>= failing tests): zero with red tests, red with no failing test, or fewer than the failing tests, is inconsistent
                parsed["complete"] = False
                parsed["reasons"] = list(parsed["reasons"]) + [
                    "junit xml root says %d failure(s)+%d error(s) but %d testcase(s) are failing: inconsistent report" % (fails, errs, failing_tc)]
    sha = sha.strip()
    status, info = bv.snapshot_set(a.repo, parsed, sha, PARSER_TAG, a.accept_growth)
    if status.startswith("stored"):
        return v("PASS", a.repo, a.ref, "refreshed baseline %s (%d red ids, GUT)" % (status, info["count"]), dict(info, status=status))
    if status == "growth_pending":
        return v("FLAG", a.repo, a.ref, "GROWTH ALERT on refresh: +%d red ids" % len(info["added"]), dict(info, status=status))
    return v("UNVERIFIED", a.repo, a.ref, "refresh refused (%s): %s" % (status, info.get("why", "")), dict(info, status=status))
