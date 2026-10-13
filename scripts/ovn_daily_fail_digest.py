#!/usr/bin/env python3
"""ovn_daily_fail_digest.py - READ-ONLY 24 h digest of what went wrong in the fleet, as JSON or short markdown (2026-10-11, r11 acct, platform P11).

The recurring 12-24 h review used to rebuild the same queries by hand every pass (24h analysis 2026-10-11: starvation hours per lane, top GPU-second sinks with
landed==0, bad outcomes grouped by root cause, landed-vs-uncredited ratio, shadow-gate counts). This runs them deterministically over state/ and prints only what a
person can act on, with the exact outcomes row text, so a scheduled agent can paste it instead of re-deriving it.

READ-ONLY: it opens state/outcomes.jsonl, state/cycle_walltime.jsonl, state/verify_gate_shadow.log and state/research_trigger_starving.json for reading and nothing else;
it creates, edits and deletes no file, never touches ~/overnight-queue's repos, never pushes, never runs git. (Missing/unreadable inputs just leave that section empty.)

Sections (JSON keys)
  window            {hours, from, to, rows, malformed}
  buckets           canonical good/bad/benign counts + pass_rate (ovn_outcome_buckets.py, the ONE definition every report shares)
  classes           {class: n} for every row in the window
  bad               the BAD rows (bucket_from_outcome_row == bad): total, by_class, by_repo, by_repo_class, and by_signature (the root-cause grouping, below)
  landing           landed / landed-uncredited / credit-only / net-zero counts and the uncredited share of pushes
  starvation        per repo: skip(exhausted) rows + their seconds in the window, and the trigger-check's starving hours when state/research_trigger_starving.json exists
  gpu_sinks         items (feat_tag, else item_hash) with the most cycle seconds that LANDED NOTHING in the window (top N; a landed or landed-uncredited push counts as landing, a credit-only push does not), with their share of all busy seconds
  walltime          per repo busy / generation / verify / fix-up seconds from cycle_walltime.jsonl rows in the window (verify_s is measured only on rows whose verify_basis is
                    "markers", i.e. written after the runner logs '--- verify done in Ns ---'; the count of such rows is reported)
  verify_shadow     result counts of state/verify_gate_shadow.log rows of FLEET repos in the window. That log is every VERIFY EXECUTION (red-before runs, item rechecks, unwinnable clauses retried every
                    10-20 minutes), not a count of failed items, so raw FAIL rows overstate the problem (2026-10-13: 116 FAIL of 153 rows, ~54 of them three unwinnable clauses): the digest also reports per
                    (repo, cmd) the FINAL result (the newest row), `distinct_cmds_last_fail` = how many distinct commands END on FAIL, how many went FAIL then PASS (a healthy red-before / green-after) and the
                    top still-failing commands. Rows whose repo label is not a fleet repo (tmp.*, dbg*, a test run that wrote into the live state dir) are NOT counted: they are labelled in `foreign_rows` /
                    `foreign_labels` / `foreign_examples`
  not_covered       the P11 signals this digest does NOT compute (they need cycle logs / git): pre-existing-red detector, held-branch age, placeholder-only files, reboot/NRestarts

Root-cause signature of a bad row = "<class>/<core>" where <core> is the row's fail_reason when it has one (ovn_classify_fail.sh's bounded tags: net-zero, test-regression,
...), else the status text normalised (lower-case, [tags] removed, digits -> N, shas -> <sha>, paths -> <path>, cut at 70 chars). Rows that differ only in a count or a sha group.

Usage: ovn_daily_fail_digest.py [--hours 24] [--state-dir DIR] [--now EPOCH] [--top 10] [--json | --md]
  default state dir: $OVN_DIR/state, else ~/overnight-queue/state. Default output: markdown. Exit 0 always (2 on a bad argument).
"""
import json
import os
import re
import sys
import time
from datetime import datetime

sys.dont_write_bytecode = True   # the docstring promises no file is created: importing ovn_outcome_buckets from the live scripts dir must not drop a __pycache__ there
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ovn_outcome_buckets as B  # noqa: E402  (the one canonical GOOD/BAD/BENIGN split)

NOT_COVERED = [
    "pre-existing-red detector (identical failing-id sets across consecutive reverted-red cycles: needs the cycle logs)",
    "held-branch age per repo (state/qa_blocked + ovn_hygiene_stuck_check: needs git)",
    "placeholder-only files on develop/main (needs the repos)",
    "reboot / boot-count change and NRestarts of the LLM stack (needs systemd)",
]
LANDING_CLASSES = ("landed", "landed-uncredited")
# repos the fleet runs (ovn_recover_parked.sh REPOS); a shadow-log repo label outside this set AND outside the repos seen in outcomes is a test run that wrote into the live state dir
FLEET_REPOS = ("billwatch", "gitlark", "iptv_apps", "test-automation-agent", "xlite", "shrike-notify", "shrike-monitor")
_CMD_RE = re.compile(r"\bcmd=(.*?)(?:\s+tail=|\s*$)")
_LINE_NO_RE = re.compile(r"\bline=(\d+)")
_SHA = re.compile(r"\b[0-9a-f]{7,40}\b")
_PATH = re.compile(r"(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+")
_TAG = re.compile(r"\[[^\]]*\]")
_NUM = re.compile(r"\d+")


def epoch_of(ts):
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return 0.0


def num(v):
    try:
        return max(0.0, float(v))
    except (TypeError, ValueError):
        return 0.0


def core_of(status):
    """Normalised status text: rows that differ only in a count, a sha or a path share it."""
    s = _TAG.sub(" ", str(status or "").lower())
    s = _SHA.sub("<sha>", s)
    s = _PATH.sub("<path>", s)
    s = _NUM.sub("N", s)
    return " ".join(s.split())[:70] or "(empty status)"


def signature(row):
    fr = str(row.get("fail_reason") or "").strip()
    return "%s/%s" % (row.get("class") or "?", fr if fr else core_of(row.get("status")))


def read_tail_lines(path, cutoff_epoch, ts_of, block=1 << 20, max_bytes=256 << 20, stale_stop=25):
    """Yield the raw lines of a jsonl file NEWEST FIRST; stops after `stale_stop` CONSECUTIVE lines older than cutoff_epoch (by ts_of(line) -> epoch, 0 = unknown) so one
    stray out-of-order old row cannot truncate the window. Binary-safe (errors='replace'), reads backward in blocks so a 20 MB log costs one block, not the whole file."""
    try:
        f = open(path, "rb")
    except OSError:
        return
    with f:
        f.seek(0, os.SEEK_END)
        pos = f.tell()
        carry = b""
        read = 0
        stale = 0
        while pos > 0 and read < max_bytes:
            n = min(block, pos)
            pos -= n
            f.seek(pos)
            buf = f.read(n) + carry
            read += n
            parts = buf.split(b"\n")
            carry = parts[0] if pos > 0 else b""
            lines = parts[1:] if pos > 0 else parts
            for raw in reversed(lines):
                if not raw.strip():
                    continue
                line = raw.decode("utf-8", "replace")
                e = ts_of(line)
                if e and e < cutoff_epoch:
                    stale += 1
                    if stale >= stale_stop:
                        return
                    continue
                stale = 0
                yield line


_TS_JSON = re.compile(r'"ts"\s*:\s*"([^"]+)"')


def _ts_json(line):
    m = _TS_JSON.search(line)
    return epoch_of(m.group(1)) if m else 0.0


def load_rows(path, cutoff):
    rows, bad = [], 0
    for line in read_tail_lines(path, cutoff, _ts_json):
        try:
            r = json.loads(line)
        except ValueError:
            bad += 1
            continue
        if isinstance(r, dict) and epoch_of(r.get("ts")) >= cutoff:
            rows.append(r)
    rows.sort(key=lambda r: epoch_of(r.get("ts")))
    return rows, bad


def _top(d, n):
    return sorted(d.items(), key=lambda kv: (-kv[1], kv[0]))[:n]


def build(state_dir, hours=24.0, now=None, top=10):
    now = time.time() if now is None else float(now)
    cutoff = now - hours * 3600.0
    rows, malformed = load_rows(os.path.join(state_dir, "outcomes.jsonl"), cutoff)
    out = {"window": {"hours": hours, "from": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(cutoff)),
                      "to": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)), "rows": len(rows), "malformed": malformed},
           "state_dir": state_dir}
    classes, buckets = {}, []
    for r in rows:
        classes[r.get("class") or "?"] = classes.get(r.get("class") or "?", 0) + 1
        buckets.append(B.bucket_from_outcome_row(r))
    c = B.counts(buckets)
    out["classes"] = dict(sorted(classes.items()))
    out["buckets"] = {"good": c["good"], "bad": c["bad"], "benign": c["benign"], "pass_rate": B.pass_rate(buckets)}

    # ---- bad rows by class / repo / root-cause signature
    bad_rows = [r for r, b in zip(rows, buckets) if b == "bad"]
    by_class, by_repo, by_rc, sigs = {}, {}, {}, {}
    for r in bad_rows:
        cl, rp = r.get("class") or "?", r.get("repo") or "?"
        by_class[cl] = by_class.get(cl, 0) + 1
        by_repo[rp] = by_repo.get(rp, 0) + 1
        by_rc.setdefault(rp, {})[cl] = by_rc.setdefault(rp, {}).get(cl, 0) + 1
        s = sigs.setdefault(signature(r), {"n": 0, "repos": {}, "first": r, "last": r, "tokens": 0, "seconds": 0})
        s["n"] += 1
        s["repos"][rp] = s["repos"].get(rp, 0) + 1
        s["last"] = r
        s["tokens"] += int(num(r.get("tokens_sent")) + num(r.get("tokens_recv")))
        s["seconds"] += int(num(r.get("duration_s")))
    out["bad"] = {
        "total": len(bad_rows), "by_class": dict(sorted(by_class.items())), "by_repo": dict(sorted(by_repo.items())),
        "by_repo_class": {k: dict(sorted(v.items())) for k, v in sorted(by_rc.items())},
        "by_signature": [{"signature": k, "n": v["n"], "repos": dict(sorted(v["repos"].items())), "tokens": v["tokens"], "seconds": v["seconds"],
                          "example": {"ts": v["last"].get("ts"), "repo": v["last"].get("repo"), "class": v["last"].get("class"), "status": v["last"].get("status"),
                                      "fail_reason": v["last"].get("fail_reason") or ""}}
                         for k, v in sorted(sigs.items(), key=lambda kv: (-kv[1]["n"], kv[0]))[:top]],
    }

    # ---- landing accounting
    n_l = classes.get("landed", 0)
    n_u = classes.get(B.UNCREDITED_CLASS, 0)
    n_c = classes.get(B.CREDIT_ONLY_CLASS, 0)
    n_z = sum(1 for r in rows if "net-zero" in str(r.get("status") or "") or r.get("fail_reason") == "net-zero")
    out["landing"] = {"landed": n_l, "landed_uncredited": n_u, "credit_only": n_c, "net_zero": n_z,
                      "uncredited_share_of_pushes": round(n_u / float(n_l + n_u), 3) if (n_l + n_u) else None}

    # ---- starvation per repo
    st = {}
    for r in rows:
        if r.get("class") == "skipped" and ("exhausted" in str(r.get("status") or "") or r.get("fail_reason") == "queue-exhausted"):
            d = st.setdefault(r.get("repo") or "?", {"skip_exhausted_rows": 0, "skip_exhausted_seconds": 0})
            d["skip_exhausted_rows"] += 1
            d["skip_exhausted_seconds"] += int(num(r.get("duration_s")))
    try:
        with open(os.path.join(state_dir, "research_trigger_starving.json")) as f:
            tj = json.load(f)
        for x in tj.get("starving", []):
            if isinstance(x, dict) and x.get("repo"):
                st.setdefault(x["repo"], {"skip_exhausted_rows": 0, "skip_exhausted_seconds": 0})["starving_hours"] = x.get("hours")
    except (OSError, ValueError, AttributeError):
        pass
    out["starvation"] = dict(sorted(st.items()))

    # ---- GPU-second sinks that landed nothing
    items = {}
    busy = 0
    for r in rows:
        dur = int(num(r.get("duration_s")))
        if r.get("class") != "skipped":
            busy += dur
        k = r.get("feat_tag") or r.get("item_hash") or ""
        if not k:
            continue
        d = items.setdefault(k, {"repo": r.get("repo"), "cycles": 0, "seconds": 0, "tokens": 0, "landed": 0})
        d["cycles"] += 1
        d["seconds"] += dur
        d["tokens"] += int(num(r.get("tokens_sent")) + num(r.get("tokens_recv")))
        if r.get("class") in LANDING_CLASSES:   # landed-uncredited IS a real code push (the F7 population): an item whose cycles pushed code is not "GPU time that landed nothing"; credit-only (progress-file-only push, no code) still is
            d["landed"] += 1
    sinks = sorted(((k, v) for k, v in items.items() if v["landed"] == 0 and v["seconds"] > 0), key=lambda kv: (-kv[1]["seconds"], kv[0]))[:top]
    out["gpu_sinks"] = [{"item": k, "repo": v["repo"], "cycles": v["cycles"], "seconds": v["seconds"], "tokens": v["tokens"],
                         "share_of_busy": round(v["seconds"] / float(busy), 3) if busy else None} for k, v in sinks]
    out["busy_seconds"] = busy

    # ---- wall-time ledger
    wt = {}
    for line in read_tail_lines(os.path.join(state_dir, "cycle_walltime.jsonl"), cutoff, _ts_json):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if not isinstance(r, dict) or epoch_of(r.get("ts")) < cutoff:
            continue
        d = wt.setdefault(r.get("repo") or "?", {"rows": 0, "busy_s": 0, "gen_s": 0, "verify_s": 0, "fixup_s": 0, "rows_with_verify_markers": 0})
        d["rows"] += 1
        d["busy_s"] += int(num(r.get("duration_s")))
        d["gen_s"] += int(num(r.get("gen_s")))
        d["verify_s"] += int(num(r.get("verify_s")))
        d["fixup_s"] += int(num(r.get("fixup_s")))
        d["rows_with_verify_markers"] += 1 if r.get("verify_basis") == "markers" else 0
    out["walltime"] = dict(sorted(wt.items()))

    # ---- shadow-gate rows: fleet rows only (test pollution is labelled, never counted), final result per (repo, cmd)
    fleet = set(FLEET_REPOS) | set(r.get("repo") for r in rows if r.get("repo"))
    shadow = {"rows": 0, "results": {}, "foreign_rows": 0, "foreign_labels": {}, "foreign_examples": []}
    line_re = re.compile(r"^(\S+)\s+repo=(\S+)\s+.*?\b(result|path_gate)=(\S+)")

    def _ts_plain(line):
        return epoch_of(line.split(" ", 1)[0])
    execs = []    # (epoch, seq, repo, result, cmd, line_no) of fleet rows that carry a command and a result
    seq = 0
    for line in read_tail_lines(os.path.join(state_dir, "verify_gate_shadow.log"), cutoff, _ts_plain):
        m = line_re.match(line)
        if not m or epoch_of(m.group(1)) < cutoff:
            continue
        repo = m.group(2)
        if repo not in fleet:
            shadow["foreign_rows"] += 1
            shadow["foreign_labels"][repo] = shadow["foreign_labels"].get(repo, 0) + 1
            if len(shadow["foreign_examples"]) < 3:
                shadow["foreign_examples"].append(line[:160])
            continue
        shadow["rows"] += 1
        key = "%s=%s" % (m.group(3), m.group(4))
        shadow["results"][key] = shadow["results"].get(key, 0) + 1
        cm = _CMD_RE.search(line) if m.group(3) == "result" else None
        if cm:
            ln = _LINE_NO_RE.search(line)
            seq += 1
            execs.append((epoch_of(m.group(1)), -seq, repo, m.group(4), " ".join(cm.group(1).split()), ln.group(1) if ln else ""))   # -seq: the reader yields NEWEST first, so a tie keeps the later line
    shadow["results"] = dict(sorted(shadow["results"].items()))
    shadow["foreign_labels"] = dict(sorted(shadow["foreign_labels"].items()))
    execs.sort()
    cmds = {}
    for e, _, repo, result, cmd, ln in execs:
        d = cmds.setdefault((repo, cmd), {"rows": 0, "fails": 0, "passes": 0, "first": result, "last": result, "last_ts": e, "lines": []})
        d["rows"] += 1
        d["fails"] += 1 if result == "FAIL" else 0
        d["passes"] += 1 if result == "PASS" else 0
        d["last"], d["last_ts"] = result, e
        if ln and ln not in d["lines"] and len(d["lines"]) < 3:
            d["lines"].append(ln)
    final = {}
    for d in cmds.values():
        final["result=" + d["last"]] = final.get("result=" + d["last"], 0) + 1
    last_fail = sorted(((k, d) for k, d in cmds.items() if d["last"] == "FAIL"), key=lambda kv: (-kv[1]["rows"], kv[0]))
    shadow["distinct_cmds"] = len(cmds)
    shadow["final"] = dict(sorted(final.items()))
    shadow["distinct_cmds_last_fail"] = len(last_fail)
    shadow["fail_then_pass"] = sum(1 for d in cmds.values() if d["last"] == "PASS" and d["fails"] > 0)
    shadow["last_fail"] = [{"repo": k[0], "cmd": k[1][:140], "rows": d["rows"], "fails": d["fails"], "last_ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(d["last_ts"])), "lines": d["lines"]}
                           for k, d in last_fail[:top]]
    out["verify_shadow"] = shadow
    out["not_covered"] = NOT_COVERED
    return out


def _fmt_s(s):
    s = int(s or 0)
    return "%dh%02dm" % (s // 3600, (s % 3600) // 60) if s >= 3600 else "%dm%02ds" % (s // 60, s % 60)


def markdown(d, top=10):
    w, b, bad = d["window"], d["buckets"], d["bad"]
    L = ["# Fleet fail digest - last %sh (%s -> %s)" % (("%g" % w["hours"]), w["from"], w["to"]), "",
         "%d outcome rows (%d unreadable). good %d / bad %d / benign %d, pass rate %s." % (
             w["rows"], w["malformed"], b["good"], b["bad"], b["benign"], ("%s%%" % b["pass_rate"]) if b["pass_rate"] is not None else "n/a")]
    ld = d["landing"]
    L.append("Pushes: %d landed, %d landed-uncredited%s, %d credit-only, %d net-zero." % (
        ld["landed"], ld["landed_uncredited"], (" (%d%% of pushes)" % round(100 * ld["uncredited_share_of_pushes"])) if ld["uncredited_share_of_pushes"] is not None else "",
        ld["credit_only"], ld["net_zero"]))
    L += ["", "## Bad outcomes: %d" % bad["total"]]
    if bad["total"]:
        L.append("By repo: " + ", ".join("%s %d" % kv for kv in _top(bad["by_repo"], 8)) + ".  By class: " + ", ".join("%s %d" % kv for kv in _top(bad["by_class"], 8)) + ".")
        L += ["", "| n | root-cause signature | repos | example (exact row text) |", "|---|---|---|---|"]
        for s in bad["by_signature"][:top]:
            ex = s["example"]
            L.append("| %d | `%s` | %s | %s %s %s |" % (s["n"], s["signature"], ", ".join("%s %d" % kv for kv in s["repos"].items()), ex["ts"], ex["repo"], "`%s`" % ex["status"]))
    else:
        L.append("none.")
    if d["gpu_sinks"]:
        L += ["", "## GPU time that landed nothing (top %d items, %s busy overall)" % (len(d["gpu_sinks"]), _fmt_s(d["busy_seconds"]))]
        for s in d["gpu_sinks"]:
            L.append("- %s `%s`: %s over %d cycle(s), %dk tokens%s" % (s["repo"], s["item"][:60], _fmt_s(s["seconds"]), s["cycles"], s["tokens"] // 1000,
                                                                       (", %d%% of busy time" % round(100 * s["share_of_busy"])) if s["share_of_busy"] is not None else ""))
    if d["starvation"]:
        L += ["", "## Starvation"]
        for repo, v in d["starvation"].items():
            L.append("- %s: %d idle-skip rows (%s)%s" % (repo, v["skip_exhausted_rows"], _fmt_s(v["skip_exhausted_seconds"]),
                                                       (", starving %sh (no [ready] roadmap feature)" % v["starving_hours"]) if v.get("starving_hours") is not None else ""))
    if d["walltime"]:
        L += ["", "## Where the cycle seconds went"]
        for repo, v in d["walltime"].items():
            L.append("- %s: %s busy over %d cycles; generation %s, verify %s (measured on %d rows), fix-up %s" % (
                repo, _fmt_s(v["busy_s"]), v["rows"], _fmt_s(v["gen_s"]), _fmt_s(v["verify_s"]), v["rows_with_verify_markers"], _fmt_s(v["fixup_s"])))
    vs = d["verify_shadow"]
    if vs["rows"]:
        L += ["", "## Shadow gate rows: %d (%s)" % (vs["rows"], ", ".join("%s %d" % kv for kv in vs["results"].items()))]
        L.append("These are VERIFY executions, not items. %d distinct command(s): %s; **%d end on FAIL**, %d went FAIL then PASS (healthy red-before / green-after)." % (
            vs["distinct_cmds"], ", ".join("%s %d" % (k.split("=", 1)[1], v) for k, v in vs["final"].items()) or "none", vs["distinct_cmds_last_fail"], vs["fail_then_pass"]))
        for x in vs["last_fail"]:
            L.append("- %s `%s`: %d rows, %d FAIL, last %s%s" % (x["repo"], x["cmd"], x["rows"], x["fails"], x["last_ts"], (" (line %s)" % ", ".join(x["lines"])) if x["lines"] else ""))
    if vs["foreign_rows"]:
        L += ["", "WARNING: %d row(s) from non-fleet repo labels (%s), NOT counted above (a test wrote into the live state dir): e.g. `%s`" % (
            vs["foreign_rows"], ", ".join("%s %d" % kv for kv in list(vs["foreign_labels"].items())[:5]), vs["foreign_examples"][0])]
    L += ["", "Not covered here: " + "; ".join(x.split(" (")[0] for x in d["not_covered"]) + "."]
    return "\n".join(L) + "\n"


def main(argv):
    hours, state_dir, now, top, fmt = 24.0, None, None, 10, "md"
    i = 0
    try:
        while i < len(argv):
            a = argv[i]
            if a == "--hours":
                hours = float(argv[i + 1]); i += 2
            elif a == "--state-dir":
                state_dir = argv[i + 1]; i += 2
            elif a == "--now":
                now = float(argv[i + 1]); i += 2
            elif a == "--top":
                top = int(argv[i + 1]); i += 2
            elif a == "--json":
                fmt = "json"; i += 1
            elif a == "--md":
                fmt = "md"; i += 1
            else:
                raise ValueError("unknown argument %r" % a)
    except (ValueError, IndexError) as e:
        print("ovn_daily_fail_digest: %s\nusage: ovn_daily_fail_digest.py [--hours 24] [--state-dir DIR] [--now EPOCH] [--top 10] [--json | --md]" % e, file=sys.stderr)
        return 2
    if state_dir is None:
        state_dir = os.path.join(os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue"), "state")
    try:
        d = build(state_dir, hours, now, top)
    except Exception as e:  # noqa: BLE001 - a digest must never raise out of a scheduled review
        print("ovn_daily_fail_digest: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 0
    sys.stdout.write(json.dumps(d, indent=1, sort_keys=True) + "\n" if fmt == "json" else markdown(d, top))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
