#!/usr/bin/env python3
"""P5a (2026-10-21): shadow-evidence quality of the stage-order journal (scripts/ovn_stage_order.py).

THE DEFECT. state/stage_order_shadow.log rows carried no ts / run / item_hash, identical decisions were silently dropped (frequency lost), the file was cut to its newest 500 rows
(history lost) and nothing joined a decision to the outcome of the item it flagged - so the gate governor (gate_registry.json declares ts_field "ts") could not window the rows and
precision (do flagged items really fail more?) was not computable. Analyst numbers 2026-10-21: 409 rows, 0 with a timestamp.

Contract tested here (run by test_p5_shadow_evidence.sh, which owns the scratch dir OVN_TEST_TMP):
  J1 plan rows: ts (UTC ISO, parseable), run, item_hash (+ step_hash / needs_step_hash), needs_state, decision_id
  J2 item-filter rows: ts, run, item_hash of the dependent, prereq_hashes + prereq_states, decision_id
  J3 the gate governor's own jsonl collector now finds a ts on every row (the declared ts_field matches)
  J4 an identical decision journaled twice is ONE row with count 2 (never silent loss); outside the merge window it is a new row
  J5 rotation keeps history: the full pre-rotation file is the .1 generation, not truncated to 500 lines
  J6 outcome rows (state/stage_order_outcomes.jsonl): joined to decision_id, carry class / verified / credited / fail_reason / duration_s; unflagged items write nothing
  J7 registry: ts_field ts, and the rotated generation is listed as a journal
Every mutant (a copy of the module with ONE hunk reverted) must fail core()."""
import importlib.util, json, os, re, subprocess, sys, shutil, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MOD = os.environ.get("P5_STAGE_ORDER_MOD") or os.path.join(ROOT, "scripts", "ovn_stage_order.py")
FIX = os.path.join(HERE, "fixtures", "stage_order")
GOV = os.path.join(ROOT, "scripts", "ovn_gate_governor.py")
REG = os.path.join(ROOT, "ops", "gate_registry.json")
TMP = os.environ.get("OVN_TEST_TMP") or sys.exit("OVN_TEST_TMP (scratch dir from the .sh wrapper) is required")
P = F = 0
ISO = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
H32 = re.compile(r"^[0-9a-f]{32}$")


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:300]) if extra else ""))


def run(mod, args, stdin="", env=None):
    e = dict(os.environ)
    for k in list(e):
        if k.startswith("OVN_STAGE_ORDER") or k in ("OVN_RUN_ID", "RUNID"):
            e.pop(k)
    e.update(env or {})
    return subprocess.run([sys.executable, "-I", mod] + args, input=stdin.encode(), capture_output=True, env=e, timeout=60)


def rows(path):
    if not os.path.exists(path):
        return []
    out = []
    for ln in open(path, encoding="utf-8"):
        ln = ln.strip()
        if ln:
            try:
                out.append(json.loads(ln))
            except ValueError:
                pass
    return out


PLAN = json.dumps([{"desc": "Add test for `qq_rr` helper", "files": ["t/test_q.py"]}, {"desc": "Add `qq_rr` function", "files": ["a/q.py"]}])
PROG = os.path.join(FIX, "group_taa_get_live_role.md")


def item_lines():
    return "\n".join(l for l in open(PROG, encoding="utf-8").read().split("\n") if l.startswith("- [ ] [T"))


def fresh(name):
    d = os.path.join(TMP, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    return d


def core(mod):
    """The behavioural contract. Returns the failed check names (real module: must be empty; every mutant: non-empty)."""
    bad = []

    def chk(n, c):
        if not c:
            bad.append(n)
    d = fresh("core_" + os.path.basename(os.path.dirname(mod)) + "_" + str(abs(hash(mod)) % 10**6))
    lg = os.path.join(d, "stage_order_shadow.log")
    # J1 plan rows
    run(mod, ["plan", "--mode", "shadow", "--repo", "r1", "--run", "run-1", "--item", "[T3] x.py - Add qq_rr. VERIFY: `pytest`", "--log", lg], PLAN)
    pr = [r for r in rows(lg) if r.get("event") == "would_reorder"]
    chk("J1 a plan decision row was journaled", len(pr) == 1)
    r = pr[0] if pr else {}
    chk("J1 ts is UTC ISO and parseable", bool(ISO.match(str(r.get("ts", "")))) and datetime.datetime.strptime(r["ts"], "%Y-%m-%dT%H:%M:%SZ"))
    chk("J1 run id recorded", r.get("run") == "run-1")
    chk("J1 item_hash is the ovn_item_hash of the item", bool(H32.match(str(r.get("item_hash", "")))))
    chk("J1 step_hash and needs_step_hash", bool(H32.match(str(r.get("step_hash", "")))) and bool(H32.match(str(r.get("needs_step_hash", "")))) and r.get("step_hash") != r.get("needs_step_hash"))
    chk("J1 prerequisite state at decision time", bool(r.get("needs_state")))
    chk("J1 decision_id", bool(re.match(r"^[0-9a-f]{16,40}$", str(r.get("decision_id", "")))))
    # J2 item-filter rows
    lg2 = os.path.join(d, "if.log")
    run(mod, ["item-filter", "--progress", PROG, "--repo", "taa", "--run", "run-2", "--log", lg2], item_lines())
    ir = [r for r in rows(lg2) if r.get("event") == "would_skip_item"]
    chk("J2 three would_skip_item rows", len(ir) == 3)
    r2 = ir[0] if ir else {}
    chk("J2 ts/run/item_hash", bool(ISO.match(str(r2.get("ts", "")))) and r2.get("run") == "run-2" and bool(H32.match(str(r2.get("item_hash", "")))))
    chk("J2 prereq_hashes + prereq_states aligned", bool(r2.get("prereq_hashes")) and all(H32.match(h) for h in r2.get("prereq_hashes", [])) and len(r2.get("prereq_hashes", [])) == len(r2.get("prereq_states", [])) and set(r2.get("prereq_states", [])) <= {"open", "parked"})
    chk("J2 decision_id unique per distinct decision", len({x.get("decision_id") for x in ir}) == 3)
    # J3 the governor's own collector windows these rows now
    try:
        spec = importlib.util.spec_from_file_location("gg_p5", GOV)
        g = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(g)
        st = fresh("govstate_" + os.path.basename(os.path.dirname(mod)))
        shutil.copy(lg2, os.path.join(st, "stage_order_shadow.log"))
        reg = json.load(open(REG))
        gate = next(x for x in reg["gates"] if x["id"] == "stage_order")
        os.environ["OVN_GG_STATE"] = st
        recs = g._c_jsonl(gate, gate["evidence"], g.Ctx(7))
        chk("J3 governor finds a ts on every row", len(recs) == 3 and all(x.ts is not None for x in recs))
        chk("J3 governor keys are unique per decision", len({x.key for x in recs}) == 3)
        chk("J3 governor counts the would_skip rows as blocks", sum(1 for x in recs if x.block) == 3)
    except Exception as ex:  # noqa: BLE001
        chk("J3 governor collector ran: %s" % ex, False)
    finally:
        os.environ.pop("OVN_GG_STATE", None)
    # J4 identical decision twice -> one row, count 2
    lg3 = os.path.join(d, "rep.log")
    for _ in range(2):
        run(mod, ["item-filter", "--progress", PROG, "--repo", "taa", "--run", "run-3", "--log", lg3], item_lines())
    rr = [r for r in rows(lg3) if r.get("event") == "would_skip_item"]
    chk("J4 repeat merged: 3 rows, none lost", len(rr) == 3)
    chk("J4 count field is 2 on every merged row", [x.get("count") for x in rr] == [2, 2, 2])
    chk("J4 last_ts present and >= ts", all(x.get("last_ts", "") >= x.get("ts", "z") for x in rr))
    run(mod, ["item-filter", "--progress", PROG, "--repo", "taa", "--run", "run-3", "--log", lg3], item_lines(), env={"OVN_STAGE_ORDER_MERGE_WINDOW_S": "0"})
    rr = [r for r in rows(lg3) if r.get("event") == "would_skip_item"]
    chk("J4 outside the merge window a new row is written", len(rr) == 6)
    # J5 rotation keeps history
    lg4 = os.path.join(d, "rot.log")
    with open(lg4, "w") as fh:
        for i in range(1000):
            fh.write(json.dumps({"event": "would_skip_item", "i": i, "pad": "x" * 300}) + "\n")
    run(mod, ["plan", "--mode", "shadow", "--repo", "r1", "--run", "run-4", "--log", lg4], PLAN)
    old = rows(lg4 + ".1")
    chk("J5 all 1000 old rows survive in the .1 generation", len(old) == 1000 and old[0].get("i") == 0 and old[-1].get("i") == 999)
    chk("J5 the live file holds the new row", any(r.get("run") == "run-4" for r in rows(lg4)))
    chk("J5 the live file is small again", os.path.exists(lg4) and os.path.getsize(lg4) < 262144 and len(rows(lg4)) <= 2)
    # J6 outcome rows
    ol = os.path.join(d, "out.jsonl")
    vic = ir[0] if ir else {"item_hash": "0" * 32, "decision_id": "x", "repo": "taa"}
    args = ["outcome", "--log", lg2, "--out", ol, "--repo", "taa", "--item-hash", vic.get("item_hash", ""), "--class", "reverted", "--fail-reason", "red-tests", "--duration-s", "93"]
    run(mod, args)
    orows = rows(ol)
    chk("J6 one outcome row written", len(orows) == 1)
    o = orows[0] if orows else {}
    chk("J6 joinable to the decision_id", vic.get("decision_id") in (o.get("decision_ids") or []))
    chk("J6 class/fail_reason/duration_s carried", o.get("class") == "reverted" and o.get("fail_reason") == "red-tests" and o.get("duration_s") == 93)
    chk("J6 reverted -> verified False, credited False", o.get("verified") is False and o.get("credited") is False)
    chk("J6 ts on the outcome row", bool(ISO.match(str(o.get("ts", "")))))
    run(mod, ["outcome", "--log", lg2, "--out", ol, "--repo", "taa", "--item-hash", vic.get("item_hash", ""), "--class", "landed", "--duration-s", "40"])
    orows = rows(ol)
    chk("J6 landed -> verified True, credited True", len(orows) == 2 and orows[-1].get("verified") is True and orows[-1].get("credited") is True)
    run(mod, ["outcome", "--log", lg2, "--out", ol, "--repo", "taa", "--item-hash", "f" * 32, "--class", "landed"])
    run(mod, ["outcome", "--log", lg2, "--out", ol, "--repo", "other", "--item-hash", vic.get("item_hash", ""), "--class", "landed"])
    chk("J6 an unflagged item / another repo writes nothing", len(rows(ol)) == 2)
    run(mod, ["outcome", "--log", os.path.join(d, "nope.log"), "--out", ol, "--repo", "taa", "--item-hash", "a" * 32, "--class", "landed"])
    chk("J6 a missing journal is a silent no-op", len(rows(ol)) == 2)
    return bad


def load_registry_checks():
    bad = []
    reg = json.load(open(REG))
    gate = next(x for x in reg["gates"] if x["id"] == "stage_order")
    ev = gate["evidence"]
    if ev.get("ts_field") != "ts":
        bad.append("J7 ts_field is ts")
    if not any(j.endswith("stage_order_shadow.log.1") for j in ev.get("journals", [])):
        bad.append("J7 rotated generation listed")
    return bad


def mutants(src):
    """name -> (old hunk, new hunk): each must be present in the module and make core() fail."""
    return {
        "P1 no ts stamped": ('rec.setdefault("ts", now)', 'pass'),
        "P2 no count merge (frequency lost)": ('row["count"] = int(row.get("count", 1)) + 1', 'row["count"] = 1'),
        "P3 truncate instead of rotate": ('os.replace(path, path + ".1")', 'open(path, "w").close()'),
        "P4 decision_id not unique": ('rec["decision_id"] = rec.get("decision_id") or _decision_id(rec)', 'rec["decision_id"] = "static"'),
        "P5 outcome ignores the repo": ('r.get("repo") == repo and', ''),
        "P6 outcome never credited": ('"credited": cls == "landed"', '"credited": False'),
        "P7 prereq hashes dropped": ('"prereq_hashes": [x.get("item_hash", "")', '"prereq_hashes_x": [x.get("item_hash", "")'),
    }


def main():
    global P, F
    bad = core(MOD)
    for b in bad:
        ok(b, False)
    ok("core contract (J1-J6) on the real module: %d failed" % len(bad), not bad)
    rb = load_registry_checks()
    for b in rb:
        ok(b, False)
    ok("J7 registry declares ts_field and the rotated journal", not rb)
    if "--core" in sys.argv:
        return 1 if (F or bad) else 0
    src = open(MOD, encoding="utf-8").read()
    md = fresh("mutants")
    for name, (old, new) in mutants(src).items():
        if old not in src:
            ok("mutant %s: hunk present in the module" % name, False)
            continue
        mp_dir = os.path.join(md, name.split()[0])
        os.makedirs(mp_dir, exist_ok=True)
        mp = os.path.join(mp_dir, "ovn_stage_order.py")
        open(mp, "w", encoding="utf-8").write(src.replace(old, new, 1))
        mb = core(mp)
        ok("mutant %s is caught (%d check(s) failed)" % (name, len(mb)), len(mb) > 0)
    print("test_stage_order_journal: pass=%d fail=%d" % (P, F))
    return 1 if F else 0


if __name__ == "__main__":
    sys.exit(main())
