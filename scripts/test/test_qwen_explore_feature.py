#!/usr/bin/env python3
"""scripts/ovn_qwen_explore.py + scripts/ovn_qe_feature.py: the `feature-ideation` lens (the local Qwen proposes NEW product behaviour when a repo is starving), the OVN_QE_FEATURE_LENS=off|shadow|on switch,
the separate feature cap, the zero-call-pass cap accounting (default cap 72) and the small-repo candidate-file fallback.

Hermetic like test_qwen_explore.py, whose fixture / stub-server prefix is reused verbatim (exec of everything above its GROUPS marker): stub LiteLLM, stub red-before checker, stub planner / refill.
The real validator, the real intake lint and ALL the real mechanical gates run unmodified. Every rule and behaviour has a MUTANT at the end: the same checks re-run against a scratch copy of the
scripts with that behaviour removed must FAIL (QE_TEST_NO_MUT=1 skips the mutants; QE_TEST_MUT="substring|substring" runs only the mutants whose name contains one of them).
"""
import hashlib
import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(_HERE, "test_qwen_explore.py")).read()
_cut = _src.index("\nGROUPS = {}")
_g = globals()
_g["__file__"] = os.path.join(_HERE, "test_qwen_explore.py")
exec(compile(_src[:_cut], "test_qwen_explore.py(prefix)", "exec"), _g)

QF_PATH = os.path.join(SCRIPTS, "ovn_qe_feature.py")  # noqa: F821
FEATURE = "feature-ideation"


def load_qf(path=QF_PATH):
    spec = importlib.util.spec_from_file_location("qf_under_test", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


README = ("# Streamz\n\n![badge](x.png)\n\nStreamz lets families record live TV and share watchlists.\n\n## Promises\n\n- Parents can redeem a referral code to unlock a free month.\n"
          "- Every stream list can be filtered by category.\n- Recordings are removed after 30 days.\n")
ROADMAP_MD = "# Product roadmap\n\n## Next\n- Offline playback on tvOS\n- Share a watchlist by link\n"
UPLOADS = 'def confirm_upload(db, upload_id):\n    existing = db.get(upload_id)\n    if existing is None:\n        raise ValueError("missing")\n    existing.status = "processed"\n    return existing\n'
FFILES = dict(FILES, **{"README.md": README, "ROADMAP.md": ROADMAP_MD, "iptv-backend/app/routers/uploads.py": UPLOADS})  # noqa: F821
PASS_A_F = reply_files("iptv-backend/app/routers/referrals.py", "iptv-backend/app/routers/streams.py", "iptv-backend/app/services/twice.py")  # noqa: F821
GOOD_CRITIC = json.dumps({"real_problem": 4, "scoped_s_m": 4, "verify_discriminates": 4, "not_dup_cosmetic": 4, "within_27b": 4, "risk": 1, "approve": True, "reasons": ["ok"]})  # noqa: F821


def fitem(**kw):
    base = {"title": "Return 404 for an unknown referral code", "file": "iptv-backend/app/routers/referrals.py", "symbol": "redeem_code",
            "evidence_quote": "    row = db.find(code)\n    row.used = True",
            "current_gap": "The handler has no branch for a code that does not exist: db.find returns None and the next line dereferences it.",
            "user_outcome": "POST /api/refs/redeem with an unknown code returns HTTP 404 with a clear message instead of a server error.",
            "proposed_change": "In redeem_code return a 404 response when db.find returns None; add iptv-backend/tests/test_referrals_unknown_code.py.",
            "verify": "cd iptv-backend && python3 -m pytest tests/test_referrals_unknown_code.py -q", "size": "S", "tier": 2}
    base.update(kw)
    return base


def freply(*items, ideas=("referral codes: unknown code",)):
    return json.dumps({"ideas": list(ideas), "items": list(items)})  # noqa: F821


def shadow_file(d):
    return os.path.join(d, "state", "qwen_explore", "feature_shadow.jsonl")


def shadow_recs(d):
    p = shadow_file(d)
    return [json.loads(l) for l in open(p).read().split("\n") if l.strip()] if os.path.exists(p) else []


def digest(p):
    return hashlib.sha1(open(p, "rb").read()).hexdigest() if os.path.exists(p) else None


def fpass(script, items, extra=None, roadmap="# roadmap\n", backlog="", files=None, flags=("--lens", FEATURE), replies=None, passa=None):
    """One feature pass over a fresh fixture. -> (d, rc, out). REPLIES: pass A, pass B (the items), then whatever `replies` adds (critic samples)."""
    d = make_fixture(roadmap=roadmap, backlog=backlog, files=files or FFILES)  # noqa: F821
    reset_llm(passa or PASS_A_F, freply(*items), *(replies or []))  # noqa: F821
    rc, out = run(d, *flags, extra=dict({"OVN_QE_FEATURE_LENS": "shadow"}, **(extra or {})), script=script)  # noqa: F821
    return d, rc, out


def rm_fixture(d):
    shutil.rmtree(d, ignore_errors=True)  # noqa: F821
    try:
        os.unlink(d + ".spec_wt")
    except OSError:
        pass


def ledger(d):
    return json.load(open(os.path.join(d, "state", "qwen_explore", "ledger_%s.json" % REPO)))  # noqa: F821


def rejected_of(d):
    rec = [r for r in shadow_recs(d) if r["type"] == "pass"]
    return rec[-1]["rejected"] if rec else {}


GROUPS = {}


def group(fn):
    GROUPS[fn.__name__] = fn
    return fn


# ====================================================================================================================== outline / vision (pure)
PY_ROUTER = '''from fastapi import APIRouter
router = APIRouter(prefix="/api/refs")

@router.post("/redeem")
def redeem_code(db, code):
    return 1

@router.get("/{code}", response_model=dict)
async def get_code(code: str):
    return {}

def _private_helper(x):
    return x
'''
PY_MODEL = '''from sqlalchemy.orm import declarative_base
Base = declarative_base()

class Referral(Base):
    __tablename__ = "referrals"
    id = 1

class Plain:
    pass
'''
PY_SERVICE = '''def charge_user(db, user, amount, *, dry=False):
    return 1

def _hidden():
    pass

class Mailer:
    pass
'''
TS_ROUTER = '''import { createRouter } from 'vue-router'
const routes = [
  { path: '/watchlist', component: WatchlistPage, name: 'watchlist' },
  { path: '/settings', name: 'settings', component: Settings },
]
export default createRouter({ routes })
'''
TS_STORE = '''import { defineStore } from 'pinia'
export const useRecordings = defineStore('recordings', () => {
  async function load() { return api.get('/recordings') }
  return { load }
})
export function removeOne(id) { return api.delete('/recordings/' + id) }
'''
VUE_PAGE = '''<template><div/></template>
<script setup>
function addToWatchlist(id) { return 1 }
const onShare = async (e) => { return 2 }
</script>
'''
KT_VM = '''package app
class HomeViewModel : ViewModel() {
    fun refreshFeed() {}
    private fun secret() {}
    suspend fun toggleFavorite(id: Int) {}
}
'''
KT_SCREEN = '''@Composable
fun SettingsScreen(nav: Nav) {}
@Composable
fun PlayerScreen() {}
'''
GD_UNIT = '''class_name Soldier
extends RefCounted
signal died
signal healed(amount)
class Wound:
    pass
func take_hit(dmg: int, source) -> void:
    pass
static func make(kind: String) -> Soldier:
    return null
func _ready():
    pass
'''


@group
def g_outline(script):
    qf = load_qf(os.path.join(os.path.dirname(script), "ovn_qe_feature.py"))
    res = {}
    k, items = qf.outline_entries("backend/app/routers/refs.py", PY_ROUTER)
    res["outline_py_routes_with_prefix_and_handler"] = k == "routes" and "POST /api/refs/redeem -> redeem_code" in items and "GET /api/refs/{code} -> get_code" in items
    res["outline_py_private_defs_skipped"] = not any("_private_helper" in i for i in items)
    k, items = qf.outline_entries("backend/app/models.py", PY_MODEL)
    res["outline_py_model_table"] = k == "models" and "table referrals (Referral)" in items and "Plain" in " ".join(items)
    k, items = qf.outline_entries("backend/app/services/pay.py", PY_SERVICE)
    res["outline_py_service_public_defs_and_classes"] = k == "class" and "charge_user(db,user,amount,dry)" in items and "class Mailer" in items and not any("_hidden" in i for i in items)
    k, items = qf.outline_entries("web/src/router/index.ts", TS_ROUTER)
    res["outline_ts_routes"] = k == "routes" and "route /watchlist -> WatchlistPage" in items and "route /settings -> settings" in items
    k, items = qf.outline_entries("web/src/stores/rec.ts", TS_STORE)
    res["outline_ts_store_and_exports"] = k == "store" and "store recordings" in items and "removeOne" in items
    k, items = qf.outline_entries("web/src/views/Home.vue", VUE_PAGE)
    res["outline_vue_page_handlers"] = k == "page" and "addToWatchlist" in items and "onShare" in items
    k, items = qf.outline_entries("app/ui/HomeViewModel.kt", KT_VM)
    res["outline_kotlin_viewmodel_public_funs"] = k == "viewmodel" and "fun refreshFeed" in items and "fun toggleFavorite" in items and not any("secret" in i for i in items)
    k, items = qf.outline_entries("app/ui/Screens.kt", KT_SCREEN)
    res["outline_kotlin_screens"] = k == "screen" and "screen SettingsScreen" in items and "screen PlayerScreen" in items
    k, items = qf.outline_entries("scripts/soldier.gd", GD_UNIT)
    res["outline_gd_class_signals_public_methods"] = (k == "class" and items[0] == "class Soldier extends RefCounted" and "signals died,healed" in items and "inner Wound" in items
                                                      and "take_hit(dmg,source)" in items and "make(kind)" in items and not any("_ready" in i for i in items))
    files = {"a/routes.py": PY_ROUTER, "a/zz.py": PY_SERVICE, "web/src/router/index.ts": TS_ROUTER}
    out = qf.build_outline("/nonexistent", sorted(files), 100000, read=lambda p: files[p])
    lines = out.split("\n")
    res["outline_routers_first_and_one_line_per_file"] = len(lines) == 3 and lines[0].startswith("a/routes.py [routes]") and lines[1].startswith("web/src/router/index.ts [routes]") and lines[2].startswith("a/zz.py [class]")
    cut = qf.build_outline("/nonexistent", sorted(files), 130, read=lambda p: files[p])
    res["outline_budget_cut_has_honest_tail"] = "more files not shown" in cut and len(cut) < 400
    res["outline_empty_is_stated"] = "no recognisable" in qf.build_outline("/nonexistent", ["x.py"], 1000, read=lambda p: "x = 1\n")
    names = ["README.md", "ROADMAP.md", "AGENTS.md", "docs/VISION.md", "a.py"]
    txt = {"README.md": README, "ROADMAP.md": ROADMAP_MD, "AGENTS.md": "# AGENTS\nScope: backend only.\n", "docs/VISION.md": "# Vision\n- Be the best family recorder\n"}
    v = qf.build_vision(lambda p: txt.get(p, ""), names, 100000)
    res["vision_has_readme_promises_roadmap_agents"] = ("--- README ---" in v and "redeem a referral code" in v and "badge" not in v and "Offline playback on tvOS" in v and "Scope: backend only" in v and "best family recorder" in v)
    res["vision_budget_cut"] = len(qf.build_vision(lambda p: txt.get(p, ""), names, 120)) < 700
    res["vision_none_is_stated"] = "no README" in qf.build_vision(lambda p: "", ["a.py"], 1000)
    return res


# ====================================================================================================================== eligibility (starving / off / caps)
def lens_row(d):
    rows = script_rows(d)  # noqa: F821
    return rows[-1]["lens"] if rows else None


@group
def g_eligibility(script):
    res = {}
    # starving (empty roadmap + empty backlog), default mode (shadow): the un-forced pass picks the feature lens
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    run(d, extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    res["starving_picks_feature_lens"] = lens_row(d) == FEATURE
    rm_fixture(d)  # noqa: F821
    # the DEFAULT (variable unset) is shadow: the feature lens runs and nothing is appended
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    e = env_for(d)  # noqa: F821
    e.pop("OVN_QE_FEATURE_LENS", None)
    r = sh(sys.executable, script, REPO, env=e)  # noqa: F821
    res["default_mode_is_shadow"] = lens_row(d) == FEATURE and "ready" not in open(os.path.join(d, "roadmap", REPO + ".md")).read() and os.path.exists(shadow_file(d))  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # a [ready] feature on the roadmap: not starving
    d = make_fixture(roadmap="# roadmap\n- [ ] [P3] [ready] Existing feature — `iptv-backend/app/services/other.py:1` x. {cat: backend; size: S; multifile: no; research: none}\n", files=FFILES)  # noqa: F821
    reset_llm(PASS_A, reply_items())  # noqa: F821
    run(d, extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    res["ready_feature_means_not_starving"] = lens_row(d) not in (FEATURE, None)
    rm_fixture(d)  # noqa: F821
    # doable backlog at / above the threshold: not starving; below: starving
    bl = lambda n: "".join("- [ ] [T2] iptv-backend/app/services/other.py — Guard helper_%d. VERIFY: `true`. (cat:python; multifile:no)\n" % i for i in range(n))  # noqa: E731
    d = make_fixture(backlog=bl(3), files=FFILES)  # noqa: F821
    reset_llm(PASS_A, reply_items())  # noqa: F821
    run(d, extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_FEATURE_FUEL": "3"}, script=script)  # noqa: F821
    res["enough_doable_backlog_means_not_starving"] = lens_row(d) not in (FEATURE, None)
    rm_fixture(d)  # noqa: F821
    d = make_fixture(backlog=bl(2), files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    run(d, extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_FEATURE_FUEL": "3"}, script=script)  # noqa: F821
    res["thin_doable_backlog_means_starving"] = lens_row(d) == FEATURE
    rm_fixture(d)  # noqa: F821
    # parked backlog lines are not doable
    parked = "".join("- [ ] [T2] iptv-backend/app/services/other.py — Guard helper_%d. AUTO-SKIP. VERIFY: `true`. (cat:python; multifile:no)\n" % i for i in range(5))
    d = make_fixture(backlog=parked, files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    run(d, extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_FEATURE_FUEL": "3"}, script=script)  # noqa: F821
    res["parked_backlog_lines_are_not_doable"] = lens_row(d) == FEATURE
    rm_fixture(d)  # noqa: F821
    # off: never picked, a forced request is refused with no model call
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A, reply_items())  # noqa: F821
    run(d, extra={"OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
    res["off_never_picks_feature_lens"] = lens_row(d) not in (FEATURE, None) and not os.path.exists(shadow_file(d))
    rm_fixture(d)  # noqa: F821
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    rc, out = run(d, "--lens", FEATURE, extra={"OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
    res["off_refuses_forced_feature_lens_without_model_call"] = "skip-bad-lens" in out and len(SEEN) == 0  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # a typo in the switch is the SAFE mode (shadow): nothing appended
    d, rc, out = fpass(script, [fitem()], extra={"OVN_QE_FEATURE_LENS": "enabled"})
    res["unknown_mode_is_shadow"] = "ready" not in open(os.path.join(d, "roadmap", REPO + ".md")).read() and len(shadow_recs(d)) >= 2  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # the feature lens has its own cap and does not consume the bug cap
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    run(d, extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    L = ledger(d)  # noqa: F821
    res["feature_pass_counts_against_feature_cap_only"] = L["feature_day_count"] == 1 and L["day_count"] == 0
    reset_llm(PASS_A, reply_items())  # noqa: F821
    run(d, extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_FEATURE_MAX_PER_DAY": "1", "OVN_QE_COOLDOWN_EMPTY_H": "0", "OVN_QE_LENS_TTL_H": "0", "OVN_QE_FEATURE_TTL_H": "0"}, script=script)  # noqa: F821
    res["feature_cap_stops_feature_lens_only"] = lens_row(d) not in (FEATURE, None) and ledger(d)["feature_day_count"] == 1  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # the bug cap is spent but the feature lens (own cap) still runs on a starving repo
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A, reply_items())  # noqa: F821
    run(d, "--lens", "bug-hunt", extra={"OVN_QE_MAX_PER_DAY": "1", "OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
    n = len(SEEN)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    rc, out = run(d, extra={"OVN_QE_MAX_PER_DAY": "1", "OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_COOLDOWN_EMPTY_H": "0"}, script=script)  # noqa: F821
    res["feature_lens_runs_when_bug_cap_spent"] = "skip-cap" not in out and lens_row(d) == FEATURE
    reset_llm(PASS_A, reply_items())  # noqa: F821
    rc, out = run(d, "--lens", "bug-hunt", extra={"OVN_QE_MAX_PER_DAY": "1", "OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_COOLDOWN_EMPTY_H": "0"}, script=script)  # noqa: F821
    res["bug_lens_still_capped_when_feature_lens_available"] = "skip-cap" in out
    rm_fixture(d)  # noqa: F821
    return res


# ====================================================================================================================== prompts
@group
def g_prompt(script):
    res = {}
    d, rc, out = fpass(script, [fitem()])
    a, b = SEEN[0]["messages"][0]["content"], SEEN[1]["messages"][0]["content"]  # noqa: F821
    res["passA_has_vision_and_outline"] = "redeem a referral code" in a and "POST /api/refs/redeem -> redeem_code" in a and "iptv-backend/app/routers/referrals.py" in a
    res["passB_has_vision_outline_agents"] = "Parents can redeem a referral code" in b and "APP SURFACE OUTLINE" in b and "POST /api/refs/redeem -> redeem_code" in b and "Scope: iptv-backend + iptv-web only" in b
    res["passB_closed_schema"] = all(("\n  %s " % k) in b for k in ("title", "file", "symbol", "evidence_quote", "current_gap", "user_outcome", "proposed_change", "verify", "size", "tier"))
    res["passB_asks_for_user_valuable_features_not_defects"] = "USER-VALUABLE" in b and "missing edge-case behaviour" in b and "vision / README promise" in b
    res["passB_states_rules"] = all(s in b for s in ("OFF-LIMITS: authentication", "schema, tables, columns, migrations", "helper / predicate / constant", "INSIDE that symbol", "NEVER that a function, file or string exists"))
    res["passB_lists_existing_titles_and_recent_commits"] = "ALREADY ON THE ROADMAP" in b and "RECENT COMMITS" in b and "init: streams module" in b
    res["passB_closed_verify_dialect_included"] = "python3 -m pytest tests/test_<name>.py" in b
    res["passB_has_repo_kind_shapes_and_no_deliberation"] = "Typical shapes that fit: an endpoint or handler that mirrors" in b and "Do NOT deliberate" in b and "{\"items\": [ {...}, ... ]}" in b
    res["passB_lists_the_shown_files_explicitly"] = "SHOWN FILES (anchor ONLY in these): iptv-backend/app/routers/referrals.py" in b and "never anchor in a file that is not shown" in b
    res["feature_prompt_is_low_temperature_json"] = SEEN[1].get("temperature", 1) <= 0.5 and SEEN[1].get("max_tokens", 0) >= 1000  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # titles proposed before are listed (dup memory) in the next prompt
    d, rc, out = fpass(script, [fitem()])
    reset_llm(PASS_A_F, freply())  # noqa: F821
    run(d, "--lens", FEATURE, "--force", extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_FILE_TTL_H": "0"}, script=script)  # noqa: F821
    res["passB_lists_recently_proposed_titles"] = "Return 404 for an unknown referral code" in SEEN[1]["messages"][0]["content"].split("ALREADY PROPOSED OR REJECTED")[1].split("RECENT COMMITS")[0]  # noqa: F821
    rm_fixture(d)  # noqa: F821
    return res


# ====================================================================================================================== shadow vs on
@group
def g_modes(script):
    res = {}
    d = make_fixture(files=FFILES)  # noqa: F821
    rm0, bl0 = digest(os.path.join(d, "roadmap", REPO + ".md")), digest(os.path.join(d, "backlog", REPO + ".md"))
    head0 = git(d, "rev-parse", "HEAD").stdout  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem(), fitem(title="Reject a made up symbol", symbol="no_such_function")))  # noqa: F821
    rc, out = run(d, "--lens", FEATURE, extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    recs = shadow_recs(d)
    items = [r for r in recs if r["type"] == "item"]
    passes = [r for r in recs if r["type"] == "pass"]
    res["shadow_writes_items_and_pass_line"] = len(items) == 2 and len(passes) == 1 and {i["status"] for i in items} == {"accepted", "rejected"}
    acc = [i for i in items if i["status"] == "accepted"]
    res["shadow_accepted_item_has_roadmap_line_tag_and_red"] = len(acc) == 1 and "[src:qwen-explore-feature]" in acc[0]["roadmap_line"] and acc[0]["red"].startswith("red") and "Outcome:" in acc[0]["roadmap_line"]
    rej = [i for i in items if i["status"] == "rejected"]
    res["shadow_rejected_item_has_reason_and_raw"] = len(rej) == 1 and rej[0]["reasons"] == ["symbol-missing"] and rej[0]["raw"]["symbol"] == "no_such_function"
    res["shadow_pass_line_has_histogram"] = passes[0]["rejected"] == {"symbol-missing": 1} and passes[0]["proposed"] == 2 and passes[0]["accepted"] == 1 and passes[0]["files"]
    res["shadow_roadmap_and_backlog_untouched"] = digest(os.path.join(d, "roadmap", REPO + ".md")) == rm0 and digest(os.path.join(d, "backlog", REPO + ".md")) == bl0
    res["shadow_makes_no_commit"] = git(d, "rev-parse", "HEAD").stdout == head0  # noqa: F821
    res["shadow_does_not_chain_planner"] = not os.path.exists(os.path.join(d, "chain_calls.txt")) and not os.path.exists(os.path.join(d, "state", "supply_kick"))
    res["shadow_no_accepted_jsonl"] = not os.path.exists(os.path.join(d, "state", "qwen_explore", "accepted.jsonl"))
    log = open(os.path.join(d, "logs", "qwen_explore.log")).read().strip().split("\n")
    res["shadow_one_summary_line_in_log"] = len(log) == 1 and "lens=feature-ideation" in log[0] and "result=shadow" in log[0] and "feature=shadow shadow_items=1" in log[0] and "accepted=1" in log[0]
    row = script_rows(d)[-1]  # noqa: F821
    res["shadow_row_not_productive_cooldown"] = row["result"] == "shadow" and ledger(d)["last_accepted"] == 0  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # a shadow pass with the critic on records the verdict next to the item
    d, rc, out = fpass(script, [fitem()], extra={"OVN_QWEN_CRITIC": "on"}, replies=[GOOD_CRITIC, GOOD_CRITIC])
    it = [r for r in shadow_recs(d) if r["type"] == "item"]
    res["shadow_runs_critic_and_stores_verdict"] = len(it) == 1 and it[0].get("critic", {}).get("verdict") == "approve"
    rm_fixture(d)  # noqa: F821
    # rotation past the size limit
    d = make_fixture(files=FFILES)  # noqa: F821
    os.makedirs(os.path.dirname(shadow_file(d)), exist_ok=True)
    open(shadow_file(d), "w").write("x" * 4000 + "\n")
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    run(d, "--lens", FEATURE, extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_FEATURE_SHADOW_MAX_MB": "0.001"}, script=script)  # noqa: F821
    res["shadow_file_rotates_past_limit"] = os.path.exists(shadow_file(d) + ".1") and open(shadow_file(d) + ".1").read().startswith("x") and len(shadow_recs(d)) == 2
    rm_fixture(d)  # noqa: F821
    # on: appended with the feature tag, chained, attributed
    d, rc, out = fpass(script, [fitem()], extra={"OVN_QE_FEATURE_LENS": "on"})
    rm = open(os.path.join(d, "roadmap", REPO + ".md")).read()
    res["on_appends_ready_line_with_feature_tag"] = bool(re.search(r"^- \[ \] \[P3\] \[(?:ready|decomposed)\] Return 404 for an unknown referral code .*\[src:qwen-explore-feature\] \{cat: backend", rm, re.M))  # noqa: F821
    res["on_line_names_user_outcome"] = "Outcome: POST /api/refs/redeem with an unknown code returns HTTP 404" in rm
    res["on_chains_planner_and_refill"] = open(os.path.join(d, "chain_calls.txt")).read().split("\n")[:2] == ["planner %s" % REPO, "refill %s MIN_DOABLE=15" % REPO]  # noqa: F821
    res["on_records_attribution_with_feature_lens"] = '"lens": "feature-ideation"' in open(os.path.join(d, "state", "qwen_explore", "accepted.jsonl")).read()
    res["on_commit_names_feature_tag"] = "src:qwen-explore-feature" in git(d, "log", "-1", "--format=%s").stdout  # noqa: F821
    res["on_writes_no_shadow_file"] = not os.path.exists(shadow_file(d))
    res["on_counts_feature_cap"] = ledger(d)["feature_day_count"] == 1 and ledger(d)["day_count"] == 0  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # dry run: prints every proposed item with its verdict, writes nothing
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem(), fitem(title="Reject a made up symbol", symbol="no_such_function")))  # noqa: F821
    before = tree_digest(d)  # noqa: F821
    rc, out = run(d, "--lens", FEATURE, "--dry-run", extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    res["dry_run_prints_accepted_and_rejected_items"] = "PROPOSED [accepted]" in out and "PROPOSED [rejected: symbol-missing]" in out and "Return 404 for an unknown referral code" in out and "FEATURE files shown:" in out
    res["dry_run_writes_nothing"] = tree_digest(d) == before and not os.path.exists(shadow_file(d))  # noqa: F821
    rm_fixture(d)  # noqa: F821
    return res


# ====================================================================================================================== gates still reject bad feature items + the new text rules
def gate_case(script, name, expect, item_kw=None, extra=None, files=None, roadmap="# roadmap\n", backlog="", passa=None):
    d, rc, out = fpass(script, [fitem(**(item_kw or {}))], extra=extra, files=files, roadmap=roadmap, backlog=backlog, passa=passa)
    rej = rejected_of(d)
    recs = [r for r in shadow_recs(d) if r["type"] == "item"]
    ok_ = (expect in rej and len(recs) == 1 and recs[0]["status"] == "rejected") if expect else (len(recs) == 1 and recs[0]["status"] == "accepted")
    rm_fixture(d)  # noqa: F821
    return ok_, rej


STREAMS_Q = "    rows = db.query(\"select * from streams\")\n    return rows"


@group
def g_gates(script):
    res = {}
    cases = [
        ("gate_accepts_a_good_feature_item", None, {}),
        ("gate_hallucinated_symbol", "symbol-missing", dict(symbol="no_such_function")),
        ("gate_hallucinated_file", "path-missing", dict(file="iptv-backend/app/routers/nope.py")),
        ("gate_quote_outside_symbol", "quote-outside-symbol", dict(file="iptv-backend/app/routers/streams.py", symbol="parse_page_size", evidence_quote="    rows = db.query(\"select * from streams\")\n    return rows")),
        ("gate_quote_not_in_file", "quote-missing", dict(evidence_quote="    row = db.lookup(code)\n    row.spent = True")),
        ("gate_existence_only_verify_grep", "feature-verify-not-test", dict(verify="cd iptv-backend && grep -q 'unknown referral code' app/routers/referrals.py")),
        ("gate_existence_only_verify_test_f", "feature-verify-not-test", dict(verify="test -f iptv-backend/tests/test_referrals_unknown_code.py")),
        ("gate_protected_path", "banned-path", dict(file="AGENTS.md", symbol="AGENTS")),
        ("gate_banned_file", "banned-path", dict(file="iptv-backend/app/services/vendored_like.py", symbol="vend_one", evidence_quote="def vend_one(x):\n    return x + 1")),
        ("gate_schema_migration", "needs-migration", dict(proposed_change="Add a column used_at via an alembic migration and return 404 for an unknown code; add iptv-backend/tests/test_referrals_unknown_code.py.")),
        ("gate_add_helper", "feature-helper-only", dict(title="Add a helper that normalises referral codes", proposed_change="Add a normalise_code helper in redeem_code's module and add iptv-backend/tests/test_referrals_unknown_code.py.")),
        ("gate_not_observable_outcome", "feature-not-observable", dict(user_outcome="The redeem handler becomes cleaner and more maintainable for developers.")),
        ("gate_missing_outcome", "feature-no-outcome", dict(user_outcome="")),
        ("gate_auth_crypto_payment_area", "feature-sensitive-area", dict(title="Reject a redeem call without a valid login", proposed_change="In redeem_code return 401 when the user is not logged in; add iptv-backend/tests/test_referrals_unknown_code.py.")),
        ("gate_multi_file_change", "feature-multifile", dict(proposed_change="In redeem_code return a 404 and also update iptv-backend/app/routers/streams.py; add iptv-backend/tests/test_referrals_unknown_code.py.")),
        ("gate_hedged_gap", "hedged-claim", dict(current_gap="The handler may possibly crash when the code does not exist.")),
        ("gate_already_green_verify", "verify-already-green", dict(verify="cd iptv-backend && python3 -m pytest tests/test_GREENVERIFY.py -q")),
    ]
    for name, expect, kw in cases:
        r, rej = gate_case(script, name, expect, kw)
        res[name] = r
        if not r:
            print("    (%s rejected=%s)" % (name, rej))
    r, rej = gate_case(script, "wired", None, dict(title="Cap how often one referral code can be redeemed", proposed_change="Add a constant MAX_REDEEMS in referrals.py and modify redeem_code to clamp against it; add iptv-backend/tests/test_referrals_unknown_code.py.",
                                                    user_outcome="POST /api/refs/redeem returns HTTP 409 once a code was redeemed the maximum number of times."))
    res["gate_constant_wired_into_the_symbol_is_not_helper_only"] = r
    r, rej = gate_case(script, "nonecheck", None, dict(title="Return 409 when confirming an already processed upload", file="iptv-backend/app/routers/uploads.py", symbol="confirm_upload",
                                                        current_gap="confirm_upload does not check the current status of the upload before processing it, so it can be confirmed twice.",
                                                        evidence_quote="    if existing is None:\n        raise ValueError(\"missing\")", user_outcome="Confirming an upload that is already processed returns HTTP 409 instead of processing it again.",
                                                        proposed_change="In confirm_upload raise a conflict error when existing.status is already processed; add iptv-backend/tests/test_confirm_twice.py.",
                                                        verify="cd iptv-backend && python3 -m pytest tests/test_confirm_twice.py -q"),
                       passa=reply_files("iptv-backend/app/routers/uploads.py", "iptv-backend/app/routers/streams.py"))  # noqa: F821
    res["gate_does_not_check_for_x_is_not_a_none_claim_for_features"] = r
    r, rej = gate_case(script, "game", None, dict(user_outcome="A unit that is suppressed has its move speed reduced by 50 percent until its next turn."))
    res["gate_game_rule_outcome_counts_as_observable"] = r
    # duplicates: same title as a backlog item; the same feature reworded against a roadmap line
    r, rej = gate_case(script, "dup", "duplicate-title", {}, backlog="- [ ] [T2] iptv-backend/app/routers/referrals.py — Return 404 for an unknown referral code. VERIFY: `true`. (cat:python; multifile:no)\n")
    res["gate_duplicate_of_backlog_item"] = r
    road = "# roadmap\n- [ ] [P3] [decomposed] Return a 404 response for an unknown referral code on redeem — `iptv-backend/app/services/other.py:1` x. {cat: backend; size: S; multifile: no; research: none}\n"
    r, rej = gate_case(script, "dupc", "feature-duplicate-concept", {}, roadmap=road)
    res["gate_reworded_duplicate_of_roadmap_item"] = r
    r, rej = gate_case(script, "done", "already-covered", {}, files=dict(FFILES, **{"OVERNIGHT_DONE.md": "- [x] [T2] iptv-backend/app/routers/referrals.py — Handle redeem_code unknown code: return 404 when db.find returns None. VERIFY: `true`. (cat:python; multifile:no)\n"}))
    res["gate_duplicate_of_done_item"] = r
    # an OPEN line about the same file + symbol but ANOTHER concern does not block a feature anchored there; one on the same topic does
    other = "- [ ] [T2] iptv-backend/app/routers/referrals.py — In redeem_code reject codes longer than 64 characters with a clear 422. VERIFY: `true`. (cat:python; multifile:no)\n"
    r, rej = gate_case(script, "openother", None, {}, backlog=other)
    res["gate_open_line_on_another_concern_is_not_a_duplicate_for_features"] = r
    same = "- [ ] [T2] iptv-backend/app/routers/referrals.py — redeem_code: an unknown code should answer 404 when db.find returns None instead of a server error crash. VERIFY: `true`. (cat:python; multifile:no)\n"
    r, rej = gate_case(script, "opensame", "already-covered", {}, backlog=same)
    res["gate_open_line_on_the_same_topic_is_a_duplicate"] = r
    # a new test file is demoted to P4 by the existing red-before handling
    d, rc, out = fpass(script, [fitem(verify="cd iptv-backend && python3 -m pytest tests/test_NEWTARGET_ref.py -q", proposed_change="In redeem_code return 404 when db.find returns None; add iptv-backend/tests/test_NEWTARGET_ref.py.")])
    it = [r for r in shadow_recs(d) if r["type"] == "item"]
    res["gate_new_test_file_is_demoted_p4"] = len(it) == 1 and it[0]["status"] == "accepted" and "[P4]" in it[0]["roadmap_line"] and it[0]["red"].endswith("demoted-P4")
    rm_fixture(d)  # noqa: F821
    # skeptic refutation drops the item (the existing skeptic runs on feature items too)
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    SKEPTIC["refute"] = {1}  # noqa: F821
    run(d, "--lens", FEATURE, extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    it = [r for r in shadow_recs(d) if r["type"] == "item"]
    res["gate_skeptic_refutes_feature_item"] = len(it) == 1 and it[0]["status"] == "rejected" and it[0]["reasons"] == ["skeptic-refuted"]
    rm_fixture(d)  # noqa: F821
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    run(d, "--lens", FEATURE, extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    sk = SKEPTIC_SEEN[-1]["messages"][0]["content"]  # noqa: F821
    res["skeptic_prompt_reads_reports_as_feature_gaps"] = "FEATURE REPORTS" in sk and "SKEPTICAL AUDIT" in sk
    rm_fixture(d)  # noqa: F821
    # dup memory: the same proposal again (lens TTL / file TTL off, cooldown off) is refused as already proposed
    d, rc, out = fpass(script, [fitem()])
    reset_llm(PASS_A_F, freply(fitem(title="Return 404 for an unknown referral code now")))  # noqa: F821
    run(d, "--lens", FEATURE, "--force", extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_FILE_TTL_H": "0"}, script=script)  # noqa: F821
    ps = [r for r in shadow_recs(d) if r["type"] == "pass"]
    res["gate_re_proposal_refused_by_dup_memory"] = len(ps) == 2 and ps[1]["rejected"].get("feature-already-proposed") == 1 and ps[1]["accepted"] == 0
    rm_fixture(d)  # noqa: F821
    # the remembered title expires (TTL)
    d, rc, out = fpass(script, [fitem()])
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    run(d, "--lens", FEATURE, "--force", extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_FILE_TTL_H": "0", "OVN_QE_FEATURE_SEEN_TTL_H": "0"}, script=script)  # noqa: F821
    ps = [r for r in shadow_recs(d) if r["type"] == "pass"]
    res["dup_memory_expires"] = len(ps) == 2 and "feature-already-proposed" not in ps[1]["rejected"]
    rm_fixture(d)  # noqa: F821
    return res


@group
def g_salvage(script):
    res = {}
    qf = load_qf(os.path.join(os.path.dirname(script), "ovn_qe_feature.py"))
    cut = '{"ideas": {"a": 1}} {"items": [' + json.dumps(fitem()) + ', {"title": "Cut off mid item", "file": "iptv-backend/app/routers/streams.py", "current_gap": "It was never fini'  # noqa: F821
    res["salvage_unit_complete_item_of_a_cut_reply"] = len(qf.salvage_items(cut)) == 1 and qf.salvage_items(cut)[0]["symbol"] == "redeem_code" and qf.salvage_items("no json here") == []
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, cut)  # noqa: F821
    run(d, "--lens", FEATURE, extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    items = [r for r in shadow_recs(d) if r["type"] == "item"]
    res["salvage_cut_reply_still_yields_its_complete_item"] = len(items) == 1 and items[0]["status"] == "accepted" and len(SEEN) == 2  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # an `ideas` array first (older schema) must not be taken for the item list
    rep = '{"ideas": ["a", "b"], "items": [' + json.dumps(fitem()) + ', {"title": "cut'  # noqa: F821
    d = make_fixture(files=FFILES)  # noqa: F821
    reset_llm(PASS_A_F, rep)  # noqa: F821
    run(d, "--lens", FEATURE, extra={"OVN_QE_FEATURE_LENS": "shadow"}, script=script)  # noqa: F821
    items = [r for r in shadow_recs(d) if r["type"] == "item"]
    res["salvage_ideas_array_is_not_the_item_list"] = len(items) == 1 and items[0]["status"] == "accepted"
    rm_fixture(d)  # noqa: F821
    # a dry run that keeps its ledger (OVN_QE_CACHE_DIR) keeps the dup memory too: the second dry run lists the first one's titles
    d = make_fixture(files=FFILES)  # noqa: F821
    cache = tempfile.mkdtemp(prefix="qef-cache-")  # noqa: F821
    reset_llm(PASS_A_F, freply(fitem()))  # noqa: F821
    run(d, "--lens", FEATURE, "--dry-run", extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_CACHE_DIR": cache}, script=script)  # noqa: F821
    reset_llm(PASS_A_F, freply())  # noqa: F821
    run(d, "--lens", FEATURE, "--dry-run", "--force", extra={"OVN_QE_FEATURE_LENS": "shadow", "OVN_QE_CACHE_DIR": cache, "OVN_QE_FILE_TTL_H": "0"}, script=script)  # noqa: F821
    res["dry_run_with_cache_dir_keeps_dup_memory"] = "Return 404 for an unknown referral code" in SEEN[1]["messages"][0]["content"].split("ALREADY PROPOSED OR REJECTED")[1].split("RECENT COMMITS")[0]  # noqa: F821
    shutil.rmtree(cache, ignore_errors=True)  # noqa: F821
    rm_fixture(d)  # noqa: F821
    return res


# ====================================================================================================================== cap accounting + small-repo fallback
SMALL = {"AGENTS.md": "# AGENTS\nsmall\n", "iptv-backend/app/only.py": OTHER, "main.py": OTHER.replace("helper", "m"), "worker.py": OTHER.replace("helper", "w")}  # noqa: F821
VUES = {"AGENTS.md": "# AGENTS\nsmall\n", "iptv-web/src/a.vue": "<template><div/></template>\n<script>\nexport default { name: 'a' }\n</script>\n" * 2, "iptv-web/src/b.vue": "<template><div/></template>\n<script>\nexport default { name: 'b' }\n</script>\n" * 2}  # noqa: F821
ONE = {"AGENTS.md": "# AGENTS\nsmall\n", "iptv-backend/app/only.py": OTHER}  # noqa: F821


@group
def g_caps(script):
    res = {}
    d = make_fixture(files=ONE)  # noqa: F821
    reset_llm(PASS_A, reply_items())  # noqa: F821
    rc, out = run(d, "--lens", "bug-hunt", extra={"OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
    res["zero_call_pass_not_counted_toward_cap"] = "fewer than 2 candidate files" in out and len(SEEN) == 0 and ledger(d)["day_count"] == 0  # noqa: F821
    rm_fixture(d)  # noqa: F821
    d = make_fixture()  # noqa: F821
    reset_llm(PASS_A, reply_items())  # noqa: F821
    run(d, "--lens", "bug-hunt", script=script)  # noqa: F821
    res["model_call_pass_is_counted"] = ledger(d)["day_count"] == 1 and len(SEEN) > 0  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # a long run of zero-call passes never reaches the cap (no skip-cap after many passes with a cap of 2)
    d = make_fixture(files=ONE)  # noqa: F821
    outs = []
    for _ in range(4):
        reset_llm(PASS_A, reply_items())  # noqa: F821
        outs.append(run(d, "--lens", "bug-hunt", extra={"OVN_QE_FEATURE_LENS": "off", "OVN_QE_MAX_PER_DAY": "2", "OVN_QE_COOLDOWN_EMPTY_H": "0"}, script=script)[1])  # noqa: F821
    res["zero_call_passes_never_hit_the_cap"] = not any("skip-cap" in o for o in outs)
    rm_fixture(d)  # noqa: F821
    # default cap is 72
    envx = {k: v for k, v in os.environ.items() if k != "OVN_QE_MAX_PER_DAY"}
    r = sh(sys.executable, "-c", "import sys; sys.path.insert(0, %r); import ovn_qwen_explore as m; print(m.MAX_PER_DAY)" % os.path.dirname(script), env=envx)  # noqa: F821
    res["default_cap_is_72"] = r.stdout.strip() == "72"
    import datetime
    for count, expect_skip in ((71, False), (72, True)):
        d = make_fixture()  # noqa: F821
        os.makedirs(os.path.join(d, "state", "qwen_explore"))
        json.dump({"day": datetime.date.today().isoformat(), "day_count": count, "lenses": {}, "files": {}, "last_pass_ts": 0, "last_accepted": 0}, open(os.path.join(d, "state", "qwen_explore", "ledger_%s.json" % REPO), "w"))  # noqa: F821
        reset_llm(PASS_A, reply_items())  # noqa: F821
        rc, out = run(d, "--lens", "bug-hunt", extra={"OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
        res["cap_boundary_%d" % count] = ("skip-cap" in out) == expect_skip
        rm_fixture(d)  # noqa: F821
    return res


@group
def g_fallback(script):
    res = {}
    d = make_fixture(files=SMALL)  # noqa: F821
    reset_llm(reply_files("main.py", "worker.py"), reply_items())  # noqa: F821
    rc, out = run(d, "--lens", "bug-hunt", extra={"OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
    row = script_rows(d)[-1]  # noqa: F821
    res["small_repo_top_level_modules_are_tried"] = row["result"] != "error" and len(SEEN) >= 2 and "main.py" in row["files"] + ["main.py" if "main.py" in str(row) else ""] and "relaxed-files=1" in row["note"]  # noqa: F821
    rm_fixture(d)  # noqa: F821
    d = make_fixture(files=VUES)  # noqa: F821
    reset_llm(reply_files("iptv-web/src/a.vue", "iptv-web/src/b.vue"), reply_items())  # noqa: F821
    rc, out = run(d, "--lens", "authz-input", extra={"OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
    row = script_rows(d)[-1]  # noqa: F821
    res["lens_extension_filter_dropped_when_still_under_two"] = len(SEEN) >= 2 and "relaxed-files=2" in row["note"]  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # an item anchored in a relaxed (top-level) module is accepted; without relaxation the same file is out of scope
    main_py = "def top_level_job(x):\n    try:\n        return int(x)\n    except Exception:\n        pass\n    return 0\n"
    files = dict(SMALL, **{"main.py": main_py})
    d = make_fixture(files=files)  # noqa: F821
    it = item(title="Stop top_level_job swallowing every error", file="main.py", symbol="top_level_job", evidence_quote="    except Exception:\n        pass\n    return 0",  # noqa: F821
              what_is_wrong="top_level_job swallows every exception and returns 0 so callers cannot tell bad input from zero.", proposed_change="Catch ValueError only and re-raise others; add iptv-backend/tests/test_top_level_job.py.",
              verify="cd iptv-backend && python3 -m pytest tests/test_top_level_job.py -q")
    reset_llm(reply_files("main.py", "worker.py"), reply_items(it))  # noqa: F821
    run(d, "--lens", "bug-hunt", extra={"OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
    res["relaxed_module_item_is_accepted"] = script_rows(d)[-1]["accepted"] == 1  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # a normal repo (>= 2 candidates) is NOT relaxed: an item in a top-level file stays out of scope
    files = dict(FILES, **{"main.py": main_py})  # noqa: F821
    d = make_fixture(files=files)  # noqa: F821
    reset_llm(reply_files("iptv-backend/app/routers/streams.py", "main.py"), reply_items(it))  # noqa: F821
    run(d, "--lens", "bug-hunt", extra={"OVN_QE_FEATURE_LENS": "off"}, script=script)  # noqa: F821
    res["normal_repo_is_not_relaxed"] = script_rows(d)[-1]["accepted"] == 0 and "relaxed" not in script_rows(d)[-1]["note"]  # noqa: F821
    rm_fixture(d)  # noqa: F821
    return res


# ====================================================================================================================== driver + mutants
REAL = {}
GROUP_KEYS = {}
for _n, _fn in GROUPS.items():
    if os.environ.get("QE_TEST_ONLY") and _n not in os.environ["QE_TEST_ONLY"].split(","):
        continue
    _r = _fn(SCRIPT)  # noqa: F821
    GROUP_KEYS[_n] = set(_r)
    REAL.update(_r)
for _k, _v in REAL.items():
    ok(_k, _v)  # noqa: F821

MUT_ROOT = tempfile.mkdtemp(prefix="qef-mut-")  # noqa: F821


def mutated(name, subs):
    """A scratch scripts/ tree (symlinks) where each (file, old, new) substitution is applied to a COPY of that file; -> path of the explorer in it."""
    base = os.path.join(MUT_ROOT, name)
    sd = os.path.join(base, "scripts")
    os.makedirs(sd)
    changed = {s[0] for s in subs}
    for fn in os.listdir(SCRIPTS):  # noqa: F821
        if fn.endswith((".py", ".sh")) and fn not in changed:
            os.symlink(os.path.join(SCRIPTS, fn), os.path.join(sd, fn))  # noqa: F821
    os.symlink(os.path.join(ROOT, "ovn_auto_research_validate.py"), os.path.join(base, "ovn_auto_research_validate.py"))  # noqa: F821
    for fn in changed:
        src = open(os.path.join(SCRIPTS, fn)).read()  # noqa: F821
        for f2, old, new in subs:
            if f2 == fn:
                assert src.count(old) >= 1, "mutation anchor missing: " + old[:70]
                src = src.replace(old, new, 1)
        open(os.path.join(sd, fn), "w").write(src)
    return os.path.join(sd, "ovn_qwen_explore.py")


EXP, QFM = "ovn_qwen_explore.py", "ovn_qe_feature.py"
MUTANTS = [
    ("feature lens always eligible (starving check removed)", [(EXP, "    feat_wanted = fmode != \"off\" and (forced_lens == FEATURE_LENS or (not forced_lens and feature_starving(repo, roadmap_text)))", "    feat_wanted = fmode != \"off\" and (forced_lens == FEATURE_LENS or not forced_lens)")],
     ["ready_feature_means_not_starving", "enough_doable_backlog_means_not_starving"]),
    ("ready feature ignored by starving rule", [(QFM, "    return ready <= 0 and doable < fuel_threshold()", "    return doable < fuel_threshold()")], ["ready_feature_means_not_starving"]),
    ("doable backlog ignored by starving rule", [(QFM, "    return ready <= 0 and doable < fuel_threshold()", "    return ready <= 0")], ["enough_doable_backlog_means_not_starving"]),
    ("parked lines counted as doable", [(QFM, "if re.match(r\"^\\s*- \\[ \\] \\[T[1-3]\\]\", ln) and not (is_parked and is_parked(ln)):", "if re.match(r\"^\\s*- \\[ \\] \\[T[1-3]\\]\", ln):")], ["parked_backlog_lines_are_not_doable"]),
    ("off switch ignored", [(QFM, "    return m if m in (\"off\", \"shadow\", \"on\") else \"shadow\"", "    return \"shadow\"")], ["off_never_picks_feature_lens", "off_refuses_forced_feature_lens_without_model_call"]),
    ("typo mode means on", [(QFM, "    return m if m in (\"off\", \"shadow\", \"on\") else \"shadow\"", "    return m if m in (\"off\", \"shadow\", \"on\") else \"on\"")], ["unknown_mode_is_shadow"]),
    ("default mode is off", [(QFM, "os.environ.get(\"OVN_QE_FEATURE_LENS\") or \"shadow\"", "os.environ.get(\"OVN_QE_FEATURE_LENS\") or \"off\"")], ["default_mode_is_shadow"]),
    ("feature passes eat the bug cap", [(EXP, "            if lens == FEATURE_LENS:\n                L[\"feature_day_count\"]", "            if False:\n                L[\"feature_day_count\"]")], ["feature_pass_counts_against_feature_cap_only"]),
    ("feature cap not enforced", [(EXP, "    feat_avail = feat_wanted and (force or int(L[\"feature_day_count\"]) < QF.max_per_day())", "    feat_avail = feat_wanted")], ["feature_cap_stops_feature_lens_only"]),
    ("bug cap blocks the feature lens", [(EXP, "        if bug_capped and not feat_avail:", "        if bug_capped:")], ["feature_lens_runs_when_bug_cap_spent"]),
    ("bug cap removed", [(EXP, "        if bug_capped and not feat_avail:", "        if False:")], ["bug_lens_still_capped_when_feature_lens_available"]),
    ("vision not in the prompts", [(QFM, "PRODUCT VISION AND PROMISES (README / roadmap / docs):\\n%s", "PRODUCT VISION AND PROMISES (README / roadmap / docs):\\n%.0s")], ["passB_has_vision_outline_agents"]),
    ("outline not in the item prompt", [(QFM, "APP SURFACE OUTLINE (deterministic extraction of routes, models, screens, classes):\\n%s", "APP SURFACE OUTLINE (deterministic extraction of routes, models, screens, classes):\\n%.0s")], ["passB_has_vision_outline_agents"]),
    ("outline not in the file-pick prompt", [(QFM, "APP SURFACE OUTLINE (extracted from the code):\\n%s", "APP SURFACE OUTLINE (extracted from the code):\\n%.0s")], ["passA_has_vision_and_outline"]),
    ("schema loses user_outcome", [(QFM, "  user_outcome     1 sentence: the observable behaviour after the change\\n", "")], ["passB_closed_schema"]),
    ("recently proposed titles not listed", [(EXP, "    seen_titles = \"\\n\".join(\"- \" + r[\"title\"][:110] for r in seen[-30:])", "    seen_titles = \"\"")], ["passB_lists_recently_proposed_titles"]),
    ("shadow appends to the roadmap", [(EXP, "    if feat_shadow:\n        n_shadow", "    if feat_shadow and False:\n        n_shadow")], ["shadow_roadmap_and_backlog_untouched", "shadow_makes_no_commit", "shadow_does_not_chain_planner", "shadow_writes_items_and_pass_line"]),
    ("shadow file not written", [(EXP, "    QF.append_jsonl_rotating(os.path.join(qdir(), \"feature_shadow.jsonl\"), recs)", "    pass")], ["shadow_writes_items_and_pass_line"]),
    ("shadow file never rotates", [(QFM, "            if os.path.getsize(path) > mb:", "            if False:")], ["shadow_file_rotates_past_limit"]),
    ("shadow pass is productive for the cooldown", [(EXP, "        return _end_pass(repo, L, lens, picked, row, t0, dry, now, 0, \" feature=shadow", "        return _end_pass(repo, L, lens, picked, row, t0, dry, now, 1, \" feature=shadow")], ["shadow_row_not_productive_cooldown"]),
    ("critic skipped in shadow", [(EXP, "    if mode != \"off\" and accepted and (mode == \"on\" or dry or feat_shadow):", "    if mode != \"off\" and accepted and (mode == \"on\" or dry):")], ["shadow_runs_critic_and_stores_verdict"]),
    ("on mode loses the feature tag", [(EXP, "        item[\"tag\"] = QF.FEATURE_TAG\n", "")], ["on_appends_ready_line_with_feature_tag", "shadow_accepted_item_has_roadmap_line_tag_and_red"]),
    ("on line drops the user outcome", [(EXP, "    outcome = (\" Outcome: %s\" % it[\"outcome\"].rstrip()) if it.get(\"outcome\") else \"\"", "    outcome = \"\"")], ["on_line_names_user_outcome"]),
    ("dry run does not print proposals", [(EXP, "            for rec in freport:\n                print(\"PROPOSED", "            for rec in []:\n                print(\"PROPOSED")], ["dry_run_prints_accepted_and_rejected_items"]),
    ("helper-only rule removed", [(EXP, "    if QF.helper_only(it[\"title\"], it[\"change\"], it[\"sym\"]):", "    if False:")], ["gate_add_helper"]),
    ("not-observable rule removed", [(EXP, "    why = QF.not_observable(it.get(\"outcome\", \"\"))\n    if why:\n        return why\n", "")], ["gate_not_observable_outcome"]),
    ("missing outcome accepted", [(EXP, "        if not outcome:\n            return None, \"feature-no-outcome\"", "        if False:\n            return None, \"feature-no-outcome\"")], ["gate_missing_outcome"]),
    ("sensitive-area rule removed", [(EXP, "    if QF.sensitive_area(prose, it[\"file\"]):", "    if False:")], ["gate_auth_crypto_payment_area"]),
    ("multi-file rule removed", [(EXP, "    if others:\n        return \"feature-multifile\"", "    if False:\n        return \"feature-multifile\"")], ["gate_multi_file_change"]),
    ("verify-must-be-test rule removed (and static greps allowed)", [(EXP, "    if not QF.verify_is_test_runner(it[\"verify\"]):", "    if False:"), (EXP, "    if lens == \"docs-drift\":\n        return \"\"\n    mt = _TEST_VERIFY.match", "    if True:\n        return \"\"\n    mt = _TEST_VERIFY.match")],
     ["gate_existence_only_verify_grep", "gate_existence_only_verify_test_f"]),
    ("dup memory not consulted", [(EXP, "    seen = QF.seen_reason(it[\"title\"], it[\"file\"], it[\"sym\"], env.get(\"feature_seen\") or [])\n    if seen:\n        return seen\n", "")], ["gate_re_proposal_refused_by_dup_memory"]),
    ("dup memory never expires", [(QFM, "if r.get(\"repo\") == repo and now - float(r.get(\"ts\") or 0) < ttl and r.get(\"title\"):", "if r.get(\"repo\") == repo and r.get(\"title\"):")], ["dup_memory_expires"]),
    ("dup memory never recorded", [(EXP, "        QF.record_seen(seen_root, repo, feature_seen_rows(freport, accepted, row), now)\n        row.d[\"result\"] = \"shadow\"", "        row.d[\"result\"] = \"shadow\"")], ["gate_re_proposal_refused_by_dup_memory"]),
    ("concept-duplicate rule removed", [(EXP, "            return \"feature-duplicate-concept\"", "            continue")], ["gate_reworded_duplicate_of_roadmap_item"]),
    ("duplicate check removed for features", [(EXP, "        dup = duplicate_reason(it, ctx_env[\"corpus\"], ctx_env[\"subjects\"], ctx_env[\"claims\"], topical_open=ctx_env[\"lens\"] == FEATURE_LENS)\n", "        dup = ''\n")], ["gate_duplicate_of_backlog_item", "gate_duplicate_of_done_item"]),
    ("quote-inside-symbol check removed", [(EXP, "        if not in_sym:\n            row.reject(why_sym)", "        if False:\n            row.reject(why_sym)")], ["gate_quote_outside_symbol"]),
    ("symbol check removed", [(EXP, "        if not symbol_ok(it[\"sym\"], text):\n            row.reject(\"symbol-missing\")\n            continue\n", "")], ["gate_hallucinated_symbol"]),
    ("protected-path check removed", [(EXP, "        f_why = scope.forbidden(it[\"file\"])\n", "        f_why = ''\n")], ["gate_protected_path", "gate_banned_file"]),
    ("migration rule removed for features", [(EXP, "    if lens != \"docs-drift\" and SCHEMA_RE.search(prose):", "    if False:")], ["gate_schema_migration"]),
    ("skeptic skipped", [(EXP, "    if accepted and os.environ.get(\"OVN_QE_SKEPTIC\", \"on\") != \"off\":", "    if False:")], ["gate_skeptic_refutes_feature_item"]),
    ("skeptic has no feature note", [(EXP, "SKEPTIC_FEATURE_NOTE if lens == FEATURE_LENS else \"\"", "\"\"")], ["skeptic_prompt_reads_reports_as_feature_gaps"]),
    ("red-before ignored", [(EXP, "        if v == \"red\":\n            if sub == ", "        if True:\n            if sub == ")], ["gate_already_green_verify"]),
    ("zero-call passes counted", [(EXP, "        if calls is None or calls > 0:", "        if True:")], ["zero_call_pass_not_counted_toward_cap", "zero_call_passes_never_hit_the_cap"]),
    ("passes never counted", [(EXP, "        if calls is None or calls > 0:", "        if False:")], ["model_call_pass_is_counted"]),
    ("default cap back to 24", [(EXP, "MAX_PER_DAY = _env_num(\"OVN_QE_MAX_PER_DAY\", 72)", "MAX_PER_DAY = _env_num(\"OVN_QE_MAX_PER_DAY\", 24)")], ["default_cap_is_72"]),
    ("cap off by one", [(EXP, "bug_capped = (not force) and L[\"day_count\"] >= MAX_PER_DAY", "bug_capped = (not force) and L[\"day_count\"] > MAX_PER_DAY")], ["cap_boundary_72"]),
    ("small-repo fallback removed", [(EXP, "    for lvl in (1, 2):", "    for lvl in ():")], ["small_repo_top_level_modules_are_tried", "lens_extension_filter_dropped_when_still_under_two", "relaxed_module_item_is_accepted"]),
    ("extension relaxation removed", [(EXP, "    for lvl in (1, 2):", "    for lvl in (1,):")], ["lens_extension_filter_dropped_when_still_under_two"]),
    ("relaxed roots not honoured by the gate", [(EXP, " or ctx_env.get(\"relaxed\")):", "):")], ["relaxed_module_item_is_accepted"]),
    ("always relaxed", [(EXP, "        if len(cands) >= 2:\n            break\n        more =", "        if False:\n            break\n        more =")], ["normal_repo_is_not_relaxed"]),
    ("shown files not listed", [(EXP, "    files = \"SHOWN FILES (anchor ONLY in these): %s\\n\" % \", \".join(d[0] for d in docs) + \"\\n\".join(", "    files = \"\\n\".join(")], ["passB_lists_the_shown_files_explicitly"]),
    ("open lines block any feature anchored at their symbol", [(EXP, "topical_open=ctx_env[\"lens\"] == FEATURE_LENS)", "topical_open=False)")], ["gate_open_line_on_another_concern_is_not_a_duplicate_for_features"]),
    ("open line on the same topic ignored", [(EXP, "                        if lw and len(lw & item_bag) / float(len(lw)) >= 0.5:\n                            return \"already-covered\"\n                        continue", "                        continue")], ["gate_open_line_on_the_same_topic_is_a_duplicate"]),
    ("none-check contradiction applies to feature gaps", [(EXP, " and (lens != FEATURE_LENS or NONE_TOPIC_RE.search(claim)):", "):")], ["gate_does_not_check_for_x_is_not_a_none_claim_for_features"]),
    ("salvage removed", [(EXP, "    return salv or items", "    return items")], ["salvage_cut_reply_still_yields_its_complete_item", "salvage_ideas_array_is_not_the_item_list"]),
    ("salvage ignores item keys", [(QFM, "if isinstance(obj, dict) and obj.get(\"file\") and obj.get(\"symbol\") and (obj.get(\"evidence_quote\") or obj.get(\"quote\")) and obj.get(\"title\"):", "if isinstance(obj, dict):")], ["salvage_unit_complete_item_of_a_cut_reply"]),
    ("dry run forgets its dup memory", [(EXP, "            if LEDGER_ROOT[0]:                              # an evidence dry run", "            if False:                              # an evidence dry run")], ["dry_run_with_cache_dir_keeps_dup_memory"]),
    ("helper rule too strict (wired constants rejected)", [(QFM, "    return not (names_caller and CALLER_VERB_RE.search(change or \"\"))", "    return True")], ["gate_constant_wired_into_the_symbol_is_not_helper_only"]),
    ("shapes missing", [(QFM, "def shapes_for(kinds):\n    return", "def shapes_for(kinds):\n    return \"\" and")], ["passB_has_repo_kind_shapes_and_no_deliberation"]),
    ("outline: python routes", [(QFM, "                    routes.append(", "                    pass  # routes.append(")], ["outline_py_routes_with_prefix_and_handler"]),
    ("outline: private defs listed", [(QFM, "            elif not d.group(1).startswith(\"_\"):", "            else:")], ["outline_py_service_public_defs_and_classes"]),
    ("outline: gd public methods only", [(QFM, "_GD_FUNC = re.compile(r\"^(?:static\\s+)?func\\s+([A-Za-z]\\w*)", "_GD_FUNC = re.compile(r\"^(?:static\\s+)?func\\s+(\\w+)")], ["outline_gd_class_signals_public_methods"]),
    ("outline: kotlin private funs listed", [(QFM, "if f and not re.match(r\"^\\s*private\\b\", ln) and", "if f and")], ["outline_kotlin_viewmodel_public_funs"]),
    ("outline: ts routes", [(QFM, "        if m and re.search(r\"\\b(?:component|name|redirect|children|meta)\\b\", ln):", "        if False:")], ["outline_ts_routes"]),
    ("outline: routers not first", [(QFM, "    rows.sort(key=lambda r: (r[0], r[1]))", "    rows.sort(key=lambda r: r[1])")], ["outline_routers_first_and_one_line_per_file"]),
    ("outline: budget ignored", [(QFM, "        if used + len(line) + 1 > budget:", "        if False:")], ["outline_budget_cut_has_honest_tail"]),
    ("vision: roadmap promises dropped", [(QFM, "    for n in docs:\n        body = _promises", "    for n in []:\n        body = _promises")], ["vision_has_readme_promises_roadmap_agents"]),
]
if os.environ.get("QE_TEST_NO_MUT"):
    MUTANTS = []
if os.environ.get("QE_TEST_MUT"):
    MUTANTS = [m for m in MUTANTS if any(k in m[0] for k in os.environ["QE_TEST_MUT"].split("|"))]
for name, subs, checks in MUTANTS:
    need = {g for g, keys in GROUP_KEYS.items() for c in checks if c in keys}
    try:
        ms = mutated(re.sub(r"[^a-z0-9]+", "_", name.lower())[:60], subs)  # noqa: F821
    except AssertionError as e:
        ok("MUTANT %s: anchor present" % name, False, e)  # noqa: F821
        continue
    try:
        res = {}
        for n in need:
            res.update(GROUPS[n](ms))
        caught = [c for c in checks if not res.get(c)]
        detail = {c: res.get(c) for c in checks}
    except Exception as e:  # the mutated script broke the fixture so badly the group cannot inspect it: the behaviour is certainly gone
        caught, detail = list(checks), "group raised %s" % type(e).__name__
    ok("MUTANT '%s' is caught by %s" % (name, "/".join(checks)), len(caught) >= 1, detail)  # noqa: F821

shutil.rmtree(MUT_ROOT, ignore_errors=True)  # noqa: F821
for _d in ALL_FIXTURES:  # noqa: F821
    shutil.rmtree(_d, ignore_errors=True)  # noqa: F821
    try:
        os.unlink(_d + ".spec_wt")
    except OSError:
        pass
srv.shutdown()  # noqa: F821
print("qwen explore feature: %d passed, %d failed" % (P, F))  # noqa: F821
sys.exit(1 if F else 0)  # noqa: F821
