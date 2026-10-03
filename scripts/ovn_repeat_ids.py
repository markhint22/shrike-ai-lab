#!/usr/bin/env python3
"""ovn_repeat_ids.py - which failing test ids are a real repeat signal for the repeat circuit-breaker (2026-10-02, harness Y-e).

The breaker (lib_item_select.sh ovn_repeat_key, ovn_item_guard.sh, run_overnight.sh best-of-N loop) parks an item after the same failing test-id set on 2
consecutive attempts. ONE baseline-red or flaky test would then park EVERY item after 2 attempts as "deterministic". This helper discounts such ids:

  filter <repo> <state_dir> <item_hash>   stdin = failing ids, stdout = the ids that count
      * the repo has an ACTIVE baseline (qa/baseline_verify.py store: <state>/qa_baselines/verify/<repo>.json, younger than its ttl): ids red at the
        baseline are dropped; nothing left -> nothing prints (the failure is the repo's, not this item's).
      * no active baseline (fallback): ids that ALSO failed on the previous item's last attempt are suspect; if EVERY id did, nothing prints
        (shared/flaky red), if at least one id is new relative to the previous item, all ids print. No record of a previous item = all new.
  basis <repo> <state_dir>                 prints "baseline" or "previous-item" (which rule filter used) - for the park note
  record <repo> <state_dir> <item_hash>    stdin = this attempt's failing ids; remembers them per repo (cur slot + the last DIFFERENT item's ids)
Never raises: on any error `filter` echoes its input unchanged (the pre-existing behaviour) and exits 0.
"""
import json
import os
import sys
import time


def _lines(text):
    return [x.strip() for x in text.splitlines() if x.strip()]


def match(a, b):
    return a == b or a.endswith("/" + b) or b.endswith("/" + a)


def _in(i, group):
    return any(match(i, g) for g in group)


def baseline_ids(repo, state):
    base = os.environ.get("QA_STATE_DIR") or state
    p = os.path.join(base, "qa_baselines", "verify", repo + ".json")
    try:
        with open(p) as f:
            d = json.load(f)
        ttl = float(d.get("ttl_s", os.environ.get("OVN_QA_BASELINE_TTL_S", "86400")))
        if time.time() - float(d.get("ts", 0)) > ttl or not isinstance(d.get("failing"), list):
            return None
        return [str(x) for x in d["failing"]]
    except (OSError, ValueError, TypeError):
        return None


def _paths(repo, state):
    d = os.path.join(state, "item_fails")
    return os.path.join(d, "_repo.%s.cur" % repo), os.path.join(d, "_repo.%s.other" % repo)


def _read(p):
    try:
        return _lines(open(p).read())
    except OSError:
        return []


def prev_item_ids(repo, state, h):
    cur_p, oth_p = _paths(repo, state)
    cur = _read(cur_p)
    if cur and cur[0] != h:
        return cur[1:]          # the last attempt recorded belonged to a different item: that is "the previous item"
    return _read(oth_p)         # same item (or nothing recorded): the last different item's ids


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    data = sys.stdin.read() if cmd in ("filter", "record") else ""
    ids = _lines(data)
    try:
        repo, state = argv[2], argv[3]
        if cmd == "filter":
            h = argv[4] if len(argv) > 4 else ""
            bl = baseline_ids(repo, state)
            if bl is not None:
                keep = [i for i in ids if not _in(i, bl)]
            else:
                prev = prev_item_ids(repo, state, h)
                keep = ids if (not prev or any(not _in(i, prev) for i in ids)) else []
            sys.stdout.write("".join(i + "\n" for i in keep))
        elif cmd == "basis":
            print("baseline" if baseline_ids(repo, state) is not None else "previous-item")
        elif cmd == "record":
            h = argv[4]
            cur_p, oth_p = _paths(repo, state)
            os.makedirs(os.path.dirname(cur_p), exist_ok=True)
            cur = _read(cur_p)
            if cur and cur[0] != h:
                with open(oth_p, "w") as f:
                    f.write("".join(i + "\n" for i in cur[1:]))
            with open(cur_p, "w") as f:
                f.write(h + "\n" + "".join(i + "\n" for i in ids))
    except Exception:
        if cmd == "filter":
            sys.stdout.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
