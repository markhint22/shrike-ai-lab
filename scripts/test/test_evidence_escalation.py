#!/usr/bin/env python3
"""K1 (2026-11-01): qa/evidence_freshness_check.py escalates to EMERGENCY (alerts.log line + relay push) when the staging deploy export is stale > 6 h or the daily promote was
HELD for EVIDENCE_STALE across more than a day; the deploy_export hint names the 'copy to box fails' cause. Time injected, push injected (nothing touches a network). Mutants must fail."""
import importlib.util, json, os, shutil, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
QA = os.path.abspath(os.path.join(HERE, "..", "..", "qa"))
SRC = os.path.join(QA, "evidence_freshness_check.py")
if not os.path.isfile(SRC):
    print("  SKIP: qa/evidence_freshness_check.py not installed here")
    sys.exit(0)
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1; print("  ok   " + name)
    else:
        F += 1; print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="evesc-test-"))
for k in ("OVN_QA_STAGING_E2E", "QA_STAGING_MAX_AGE_S", "OVN_EVIDENCE_FRESHNESS", "QA_STATE_DIR", "OVN_DIR", "OVN_EVIDENCE_ESCALATE", "OVN_EVIDENCE_ESCALATE_S"):
    os.environ.pop(k, None)
os.environ["OVN_QA_STAGING_E2E"] = "off"  # e2e sources are not the subject here


def load(path, name):
    d = os.path.dirname(path)
    if d not in sys.path:
        sys.path.insert(0, d)
    spec = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


FM = load(SRC, "esc_under_test")
NOW = 1_800_000_000.0
H = 3600.0


def stamp(t):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))


def mk(name, export_age, holds=()):
    d = os.path.join(T, name); shutil.rmtree(d, ignore_errors=True); os.makedirs(os.path.join(d, "staging_deploys"))
    for repo in ("billwatch", "iptv_apps"):
        json.dump({"repo": repo, "fetched_at": NOW - export_age}, open(os.path.join(d, "staging_deploys", repo + ".json"), "w"))
    with open(os.path.join(d, "alerts.log"), "w") as f:
        for t, repo in holds:
            f.write("[%s] WARN | promote-staging-gate | %s promote SKIPPED: staging_check EVIDENCE_STALE for candidate abc1234567 (enforce); other repos unaffected\n" % (stamp(t), repo))
    return d


def lines(d):
    return [l for l in open(os.path.join(d, "alerts.log")).read().splitlines() if "evidence-freshness" in l]


def scenario(mod, label):
    bad = []
    pushed = []
    push = lambda title, msg: pushed.append((title, msg))
    # export 7 h old => EMERGENCY line + push; hint names the copy-to-box cause
    d = mk("exp7_" + label, 7 * H)
    os.environ["QA_STATE_DIR"] = d
    mod.run(d, NOW, push=push)
    L = lines(d)
    if not any("EMERGENCY | evidence-freshness" in l and "7.0 h old" in l for l in L):
        bad.append("export 7 h old must write an EMERGENCY evidence-freshness line, got %s" % L)
    if len(pushed) != 1:
        bad.append("export 7 h old must push exactly one emergency, pushed %d" % len(pushed))
    if not any("export runs but copy to box fails: check ssh to $OVN_SSH and Tailscale" in l for l in L):
        bad.append("hint must read 'export runs but copy to box fails: check ssh to $OVN_SSH and Tailscale'")
    # export 2 h old => stale-by-30-min WARN only, no emergency, no push
    pushed.clear()
    d = mk("exp2_" + label, 2 * H); os.environ["QA_STATE_DIR"] = d
    mod.run(d, NOW, push=push)
    L = lines(d)
    if any("EMERGENCY" in l for l in L) or pushed or not any("WARN | evidence-freshness" in l for l in L):
        bad.append("export 2 h old: WARN only, got %s pushed=%d" % (L, len(pushed)))
    # promote held twice a day apart (26 h) while the export is 1 h old => promote_held_stale EMERGENCY
    pushed.clear()
    d = mk("held_" + label, 1 * H, holds=[(NOW - 28 * H, "billwatch"), (NOW - 2 * H, "billwatch")]); os.environ["QA_STATE_DIR"] = d
    mod.run(d, NOW, push=push)
    L = lines(d)
    if not any("EMERGENCY" in l and "HELD for EVIDENCE_STALE" in l for l in L) or len(pushed) != 1:
        bad.append("promote held > 1 day must EMERGENCY + push, got %s pushed=%d" % (L, len(pushed)))
    # a single hold 2 h ago (first day) => no escalation
    pushed.clear()
    d = mk("held1_" + label, 1 * H, holds=[(NOW - 2 * H, "billwatch")]); os.environ["QA_STATE_DIR"] = d
    mod.run(d, NOW, push=push)
    if any("EMERGENCY" in l for l in lines(d)) or pushed:
        bad.append("one hold (< 1 day) must not escalate")
    # old holds long recovered (last one 3 days ago) => no escalation
    d = mk("heldold_" + label, 1 * H, holds=[(NOW - 100 * H, "billwatch"), (NOW - 76 * H, "billwatch")]); os.environ["QA_STATE_DIR"] = d
    pushed.clear(); mod.run(d, NOW, push=push)
    if any("EMERGENCY" in l for l in lines(d)) or pushed:
        bad.append("holds that ended 3 days ago must not escalate")
    # dedupe: a second run within 6 h does not push again; at 6 h it does
    d = mk("dd_" + label, 7 * H); os.environ["QA_STATE_DIR"] = d
    pushed.clear(); mod.run(d, NOW, push=push); mod.run(d, NOW + 1 * H, push=push)
    if len(pushed) != 1:
        bad.append("escalation deduped inside 6 h, pushed %d" % len(pushed))
    return bad


bad = scenario(FM, "orig")
ok("scenario passes on the real module", not bad, bad)
os.environ["OVN_EVIDENCE_ESCALATE"] = "shadow"
d = mk("shadow", 7 * H); os.environ["QA_STATE_DIR"] = d
pushed = []; FM.run(d, NOW, push=lambda t, m: pushed.append(t))
ok("OVN_EVIDENCE_ESCALATE=shadow: EMERGENCY line written, NO push", any("EMERGENCY" in l for l in lines(d)) and not pushed)
os.environ["OVN_EVIDENCE_ESCALATE"] = "off"
d = mk("off", 7 * H); os.environ["QA_STATE_DIR"] = d
pushed = []; FM.run(d, NOW, push=lambda t, m: pushed.append(t))
ok("OVN_EVIDENCE_ESCALATE=off: old WARN behaviour, no EMERGENCY, no push", not any("EMERGENCY" in l for l in lines(d)) and not pushed)
os.environ.pop("OVN_EVIDENCE_ESCALATE")
ok("push_emergency never raises on an unreachable relay", FM.push_emergency("t", "m") in (True, False))

print("# mutation checks")
src = open(SRC).read()
muts = {
    "6h threshold disabled": ("if ages and min(ages) > lim:", "if ages and min(ages) > lim * 1000:"),
    "hint without the copy-to-box cause": ("If the export runs but copy to box fails: check ssh to $OVN_SSH and Tailscale", "see logs"),
    "held > 1 day never escalates": ("if holds[-1] - first > HELD_ESCALATE_S:", "if False:"),
    "emergency written as WARN": ('lvl = "EMERGENCY" if key in esc else "WARN"', 'lvl = "WARN"'),
    "no push": ('if key in esc and esc_mode == "on":', "if False:"),
}
for label, (a, b) in muts.items():
    if a not in src:
        ok("mutant [%s] applies" % label, False); continue
    mp = os.path.join(T, "mut_%d.py" % abs(hash(label))); open(mp, "w").write(src.replace(a, b))
    try:
        mm = load(mp, "mut_%d" % abs(hash(label)))
        bm = scenario(mm, "m%d" % abs(hash(label)))
    except Exception as ex:  # noqa: BLE001
        bm = ["crash %s" % ex]
    ok("mutant [%s]: scenario FAILS (%d broken)" % (label, len(bm)), len(bm) > 0)
shutil.rmtree(T, ignore_errors=True)
print("evidence escalation: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
