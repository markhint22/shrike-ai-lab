#!/usr/bin/env python3
"""scripts/ovn_qwen_explore.py CRITIC stage (OVN_QWEN_CRITIC=off|shadow|on): a second, independent, fresh-context Qwen opinion on every mechanically verified item.

Hermetic like test_qwen_explore.py, whose fixture / stub-server prefix is reused verbatim (exec of everything above its GROUPS marker). The stub LLM's critic replies are scripted
per item (matched on the item title inside the critic prompt) so each scenario is deterministic: both-approve, disagree, hard-fail, malformed JSON, timeout / 503, top-N cut,
shadow vs on, off, DRY_RUN, audit log, self-throttle feedback. MUTATION PROOFS at the end: the same checks run against a scratch copy of the script with the behaviour removed must FAIL.
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(_HERE, "test_qwen_explore.py")).read()
_cut = _src.index("\nGROUPS = {}")
_g = globals()
_g["__file__"] = os.path.join(_HERE, "test_qwen_explore.py")
exec(compile(_src[:_cut], "test_qwen_explore.py(prefix)", "exec"), _g)

import http.server  # noqa: E402  (names below come from the exec'd prefix: ok, sh, git, make_fixture, run, item, reply_*, PASS_A, REPLIES, SEEN, MODE, srv, PORT, SCRIPT, SCRIPTS, ROOT, REPO)

CRIT = {"fn": None, "count": {}}          # fn(prompt, body) -> reply text | None (=> HTTP 503) | float seconds (sleep, then an empty reply)

_orig_env_for = env_for  # noqa: F821


def env_for(d, extra=None):               # the shared fixture pins the critic off; here the DEFAULT (unset) must reach the script unless a test sets it
    e = _orig_env_for(d, extra)
    if "OVN_QWEN_CRITIC" not in (extra or {}):
        e.pop("OVN_QWEN_CRITIC", None)
    return e


def _do_post(self):
    body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")  # noqa: F821
    prompt = body["messages"][-1]["content"] if body.get("messages") else ""
    if "SKEPTICAL AUDIT" in prompt:  # the explorer's own skeptic pass (shared stub behaviour): every survivor is "real"; not recorded in SEEN
        n = len(re.findall(r"=== END REPORT \d+ ===", prompt))  # noqa: F821
        text = json.dumps({"verdicts": [{"id": i, "real": True, "reason": "stub verdict %d" % i} for i in range(1, n + 1)]})
        out = json.dumps({"choices": [{"message": {"content": text}}], "usage": {"prompt_tokens": 1000, "completion_tokens": 200}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
        return
    SEEN.append(body)  # noqa: F821
    if "independent, skeptical reviewer" in prompt and CRIT["fn"]:
        text = CRIT["fn"](prompt, body)
        if text is None:
            self.send_response(503)
            self.end_headers()
            return
        if text == "TRUNC":                                    # a truncated body: http.client.IncompleteRead (not an OSError)
            out = b'{"choices": [{"message": {"content": "x"}}]}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out) + 500))
            self.end_headers()
            self.wfile.write(out)
            self.wfile.flush()
            self.close_connection = True
            return
        if isinstance(text, float):
            time.sleep(text)  # noqa: F821
            text = ""
    elif MODE["down"]:  # noqa: F821
        self.send_response(503)
        self.end_headers()
        return
    else:
        text = REPLIES.pop(0) if len(REPLIES) > 1 else (REPLIES[0] if REPLIES else '{"files": []}')  # noqa: F821
    out = json.dumps({"choices": [{"message": {"content": text}}], "usage": {"prompt_tokens": 1000, "completion_tokens": 200}}).encode()
    self.send_response(200)
    self.send_header("Content-Type", "application/json")
    self.send_header("Content-Length", str(len(out)))
    self.end_headers()
    self.wfile.write(out)


H.do_POST = _do_post  # noqa: F821


def crit_reply(approve=True, **ov):
    sc = {"real_problem": 4, "scoped_s_m": 4, "verify_discriminates": 4, "not_dup_cosmetic": 4, "within_27b": 4, "risk": 2}
    sc.update(ov)
    return json.dumps({"scores": sc, "approve": approve, "reasons": ["looks %s" % ("fine" if approve else "wrong")]})


def script_critic(by_key, default=None):
    """by_key: {title substring: [reply for sample 1, reply for sample 2, ...]} (the last repeats); an unmatched prompt gets `default`."""
    CRIT["count"] = {}

    def fn(prompt, body):
        for k, replies in by_key.items():
            if "title: " + k in prompt:
                n = CRIT["count"].get(k, 0)
                CRIT["count"][k] = n + 1
                return replies[min(n, len(replies) - 1)]
        return default if default is not None else crit_reply()
    CRIT["fn"] = fn


def critic_prompts():
    return [b["messages"][-1]["content"] for b in SEEN if "independent, skeptical reviewer" in (b["messages"][-1]["content"] if b.get("messages") else "")]  # noqa: F821


def four_items():
    return [
        item(),
        item(title="Guard cancel_subscription against a missing subscription row", file="iptv-backend/app/services/billing.py", symbol="cancel_subscription",
             evidence_quote="    sub = db.get(user.id)\n    sub.active = False", what_is_wrong="cancel_subscription dereferences a missing subscription row and raises AttributeError for users without one.",
             proposed_change="Return None when db.get finds no row and let the caller answer 404; add iptv-backend/tests/test_cancel.py.", verify="cd iptv-backend && python3 -m pytest tests/test_cancel.py -q"),
        item(title="Scope load_streams to the requesting user's rows", file="iptv-backend/app/routers/streams.py", symbol="load_streams",
             evidence_quote="    rows = db.query(\"select * from streams\")", what_is_wrong="load_streams ignores user_id and returns every user's streams (IDOR across accounts).",
             proposed_change="Filter the query by user_id; add iptv-backend/tests/test_streams_owner.py.", verify="cd iptv-backend && python3 -m pytest tests/test_streams_owner.py -q"),
        item(title="Make billing_history query only the callers rows in the database", file="iptv-backend/app/services/billing.py", symbol="billing_history",
             evidence_quote="    return [r for r in db.all() if r.user_id == user.id]", what_is_wrong="billing_history loads every row of the table into memory and filters in Python, so cost grows with the size of the table.",
             proposed_change="Query only this user's rows in the database; add iptv-backend/tests/test_billing_history.py.", verify="cd iptv-backend && python3 -m pytest tests/test_billing_history.py -q"),
    ]


T_A, T_B, T_C, T_D = "Stop parse_page_size", "Guard cancel_subscription", "Scope load_streams", "Make billing_history"


def audit_rows(d):
    p = os.path.join(d, "state", "qwen_critic.jsonl")
    return [json.loads(x) for x in open(p).read().split("\n") if x.strip()] if os.path.exists(p) else []


def roadmap_of(d):
    return open(os.path.join(d, "roadmap", REPO + ".md")).read()  # noqa: F821


def go(d, mode, *flags, extra=None, script=None):
    e = {"OVN_QWEN_CRITIC": mode}
    e.update(extra or {})
    return run(d, "--lens", "bug-hunt", "--no-chain", *flags, extra=e, script=script)  # noqa: F821


def rm_fixture(d):
    shutil.rmtree(d, ignore_errors=True)  # noqa: F821
    try:
        os.unlink(d + ".spec_wt")
    except OSError:
        pass


GROUPS = {}


def group(fn):
    GROUPS[fn.__name__] = fn
    return fn


def fresh(items=None, cap=8):
    d = make_fixture()  # noqa: F821
    reset_llm(PASS_A, reply_items(*(items or four_items())))  # noqa: F821
    return d


@group
def g_on_mixed(script):
    res = {}
    d = fresh()
    script_critic({T_A: [crit_reply(), crit_reply()],                                           # both approve
                   T_B: [crit_reply(), crit_reply(False)],                                      # disagreement
                   T_C: [crit_reply(True, real_problem=2), crit_reply(True, real_problem=2)],   # says approve but a hard-fail dimension trips
                   T_D: ["this is not json at all", crit_reply()]})                             # malformed reply
    rc, out = go(d, "on", "--max-items", "8", script=script)
    rm = roadmap_of(d)
    row = script_rows(d)[-1]  # noqa: F821
    res["on_both_approve_appended"] = rc == 0 and "Stop parse_page_size" in rm and rm.count("[src:qwen-explore]") == 1
    res["on_disagree_rejected"] = "Guard cancel_subscription" not in rm and row["rejected"].get("critic-disagree") == 1
    res["on_hardfail_rejected"] = "Scope load_streams" not in rm and row["rejected"].get("critic-reject") == 1
    res["on_malformed_fail_closed"] = "Make billing_history" not in rm and row["rejected"].get("critic-error") == 1
    cd = row.get("critic") or {}
    res["on_counts"] = (cd.get("mode"), cd.get("evaluated"), cd.get("approved"), cd.get("rejected"), cd.get("disagree"), cd.get("errors")) == ("on", 4, 1, 1, 1, 1)
    res["on_reject_rate_in_summary"] = "critic=on eval=4 approved=1 rejected=1 disagree=1 errors=1 cut=0 critic_reject_rate=67%" in out and cd.get("reject_rate") == 0.667
    res["on_row_accepted"] = row["accepted"] == 1 and row["proposed"] == 4
    rows = {r["title"][:20]: r for r in audit_rows(d)}
    res["audit_one_row_per_item"] = len(audit_rows(d)) == 4
    ra = next((r for r in audit_rows(d) if r["title"].startswith(T_A)), {})
    res["audit_fields"] = bool(ra) and ra["verdict"] == "approve" and ra["outcome"] == "accepted" and ra["mode"] == "on" and len(ra["item_hash"]) == 16 and ra["score"] == 18.0 and len(ra["samples"]) == 2 \
        and ra["samples"][0]["temp"] != ra["samples"][1]["temp"] and ra["samples"][0]["seed"] != ra["samples"][1]["seed"] and ra["samples"][0]["scores"]["real_problem"] == 4 and ra["reasons"]
    res["audit_outcomes"] = sorted(r["outcome"] for r in audit_rows(d)) == sorted(["accepted", "rejected-disagree", "rejected-reject", "rejected-error"]) and len(rows) == 4
    res["audit_hardfail_reason"] = any("hard-fail: real_problem<3" in " ".join(r["reasons"]) for r in audit_rows(d) if r["title"].startswith(T_C))
    res["audit_malformed_status"] = any(s["status"] == "malformed" for r in audit_rows(d) if r["title"].startswith(T_D) for s in r["samples"])
    ap = os.path.join(d, "state", "qwen_explore", "accepted.jsonl")
    acc = [json.loads(x) for x in open(ap).read().split("\n") if x.strip()] if os.path.exists(ap) else []
    res["accepted_records_critic_verdict"] = len(acc) == 1 and acc[0].get("critic") == "approve" and acc[0].get("critic_score") == 18.0 and len(acc[0].get("item_hash", "")) == 16
    # a second pass appends to the same audit log (append-only)
    first = audit_rows(d)
    n_before = len(first)
    reset_llm(PASS_A, reply_items(four_items()[1]))  # noqa: F821
    script_critic({})
    _lp = os.path.join(d, "state", "qwen_explore", "ledger_%s.json" % REPO)  # noqa: F821
    _L = json.load(open(_lp))  # noqa: F821
    _L["files"] = {}                       # the hardened explorer rotates files (72 h TTL): forget the shown files so pass A's picks are usable again
    json.dump(_L, open(_lp, "w"))  # noqa: F821
    run(d, "--force", "--lens", "performance", "--no-chain", extra={"OVN_QWEN_CRITIC": "on"}, script=script)  # noqa: F821
    res["audit_append_only"] = len(audit_rows(d)) > n_before and audit_rows(d)[:n_before] == first
    rm_fixture(d)  # noqa: F821
    return res


@group
def g_fresh_context(script):
    res = {}
    d = fresh([item()])
    script_critic({})
    go(d, "on", script=script)
    ps = critic_prompts()
    bodies = [b for b in SEEN if b.get("messages") and "independent, skeptical reviewer" in b["messages"][-1]["content"]]  # noqa: F821
    res["critic_two_samples_per_item"] = len(ps) == 2
    res["critic_fresh_single_message"] = bool(bodies) and all(len(b["messages"]) == 1 and b["messages"][0]["role"] == "user" for b in bodies)
    p = ps[0] if ps else ""
    res["critic_prompt_has_evidence"] = "    except Exception:\n        pass\n    return size" in p and "parse_page_size" in p and "Scope: iptv-backend" in p and "RUBRIC" in p and "Red-before check" in p and "red" in p
    res["critic_prompt_no_explorer_context"] = bool(p) and "FILES TO REVIEW" not in p and "ALREADY ON THE ROADMAP" not in p and "RECENT COMMITS" not in p and "LENS:" not in p and "Reply with ONLY this JSON object: {\"items\"" not in p
    res["critic_prompt_shows_code_window"] = "def load_streams" in p or "def parse_page_size" in p
    res["critic_temps_and_seeds_differ"] = len(bodies) == 2 and bodies[0]["temperature"] != bodies[1]["temperature"] and bodies[0]["seed"] != bodies[1]["seed"] and "seed" not in SEEN[0]  # noqa: F821
    res["critic_item_calls_counted"] = script_rows(d)[-1]["calls"] == 5  # noqa: F821  (pass A + pass B + skeptic + 2 critic samples)
    rm_fixture(d)  # noqa: F821
    return res


@group
def g_topn(script):
    res = {}
    d = fresh()
    # all four approved by both samples; rubric score ranks them: B (best) > D > A > C
    def both(**ov):
        return [crit_reply(True, **ov), crit_reply(True, **ov)]
    script_critic({T_A: both(real_problem=3, scoped_s_m=3, verify_discriminates=3, not_dup_cosmetic=3, within_27b=3, risk=3),
                   T_B: both(real_problem=5, scoped_s_m=5, verify_discriminates=5, not_dup_cosmetic=5, within_27b=5, risk=1),
                   T_C: both(real_problem=3, scoped_s_m=3, verify_discriminates=3, not_dup_cosmetic=3, within_27b=3, risk=3),
                   T_D: both(real_problem=4, scoped_s_m=4, verify_discriminates=4, not_dup_cosmetic=4, within_27b=4, risk=2)})
    rc, out = go(d, "on", "--max-items", "8", extra={"OVN_QWEN_CRITIC_TOPN": "2"}, script=script)
    rm = roadmap_of(d)
    row = script_rows(d)[-1]  # noqa: F821
    res["topn_keeps_two_best_not_first_two"] = "Guard cancel_subscription" in rm and "Make billing_history" in rm and "Stop parse_page_size" not in rm and "Scope load_streams" not in rm
    res["topn_cut_counted"] = row["accepted"] == 2 and row["rejected"].get("critic-cut") == 2 and row["critic"]["cut"] == 2 and "cut=2" in out
    outs = {r["title"][:12]: r["outcome"] for r in audit_rows(d)}
    res["topn_cut_audited"] = sorted(outs.values()) == ["accepted", "accepted", "cut-top-n", "cut-top-n"]
    res["topn_ranking_order_in_roadmap"] = rm.find("Guard cancel_subscription") < rm.find("Make billing_history")
    rm_fixture(d)  # noqa: F821
    # default N is 6: four approved items are all kept
    d = fresh()
    script_critic({})
    go(d, "on", "--max-items", "8", script=script)
    res["topn_default_6_keeps_all_four"] = roadmap_of(d).count("[src:qwen-explore]") == 4
    rm_fixture(d)  # noqa: F821
    return res


@group
def g_failclosed(script):
    res = {}
    # critic LLM down (HTTP 503) in ON mode: nothing appended, pass is an error, lens NOT burned, retry soon
    d = fresh()
    script_critic({}, default=None)
    CRIT["fn"] = lambda prompt, body: None
    calls_before = len(SEEN)  # noqa: F821
    rc, out = go(d, "on", "--max-items", "8", script=script)
    row = script_rows(d)[-1]  # noqa: F821
    res["on_critic_down_fails_closed"] = rc == 0 and roadmap_of(d) == "# roadmap\n" and row["result"] == "error" and "critic-unavailable" in row["note"] and row["accepted"] == 0
    lp = os.path.join(d, "state", "qwen_explore", "ledger_%s.json" % REPO)  # noqa: F821
    res["on_critic_down_does_not_burn_lens"] = (not os.path.exists(lp)) or "bug-hunt" not in json.load(open(lp)).get("lenses", {})
    nxt = os.path.join(d, "state", "qwen_explore", "next_%s" % REPO)  # noqa: F821
    res["on_critic_down_retries_soon"] = os.path.exists(nxt) and float(open(nxt).read().strip() or 0) - time.time() < 700  # noqa: F821
    crit_calls = len(critic_prompts())
    res["on_critic_down_short_circuits"] = crit_calls == 1                                            # one failed call, the other samples/items are skipped (no 8 x timeouts)
    res["on_critic_down_audited"] = len(audit_rows(d)) == 4 and all(r["verdict"] == "error" and r["outcome"] == "rejected-error" for r in audit_rows(d))
    rm_fixture(d)  # noqa: F821
    # timeout (reply slower than OVN_QE_CRITIC_TIMEOUT) behaves the same
    d = fresh([item()])
    CRIT["fn"] = lambda prompt, body: 3.0
    rc, out = go(d, "on", extra={"OVN_QE_CRITIC_TIMEOUT": "1"}, script=script)
    row = script_rows(d)[-1]  # noqa: F821
    res["on_critic_timeout_fails_closed"] = roadmap_of(d) == "# roadmap\n" and row["result"] == "error" and "critic-unavailable" in row["note"]
    rm_fixture(d)  # noqa: F821
    # verdict algebra on the real module: approve needs BOTH; approve+reject = disagree; error+reject = decisive reject; error+approve = error (retry later)
    import importlib.util
    sp = importlib.util.spec_from_file_location("qe_under_test", script or SCRIPT)  # noqa: F821
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    smp = lambda v, sc=10: {"verdict": v, "score": sc}  # noqa: E731
    res["combine_algebra"] = (m.combine_samples([smp("approve", 8), smp("approve", 10)]) == ("approve", 9.0) and m.combine_samples([smp("approve"), smp("reject")])[0] == "disagree"
                              and m.combine_samples([smp("reject"), smp("approve")])[0] == "disagree" and m.combine_samples([smp("error"), smp("reject")])[0] == "reject"
                              and m.combine_samples([smp("error"), smp("approve")])[0] == "error" and m.combine_samples([smp("error"), smp("error")])[0] == "error"
                              and m.combine_samples([smp("reject"), smp("reject")])[0] == "reject")
    res["parse_critique_strict"] = (m.parse_critique(crit_reply()) is not None and m.parse_critique("<think>x</think>```json\n" + crit_reply() + "\n```") is not None and m.parse_critique("nope") is None
                                    and m.parse_critique(json.dumps({"scores": {"real_problem": 9}, "approve": True})) is None and m.parse_critique(crit_reply().replace("true", "\"yes\"")) is None
                                    and m.parse_critique(json.dumps({"scores": {"real_problem": 4, "scoped_s_m": 4, "verify_discriminates": 4, "not_dup_cosmetic": 4, "within_27b": 4, "risk": 2}})) is None)
    res["hard_fail_rules"] = m.hard_fails({"real_problem": 5, "scoped_s_m": 5, "verify_discriminates": 2, "not_dup_cosmetic": 5, "within_27b": 5, "risk": 1}) == ["verify_discriminates<3"] \
        and m.hard_fails({"real_problem": 3, "scoped_s_m": 3, "verify_discriminates": 3, "not_dup_cosmetic": 3, "within_27b": 3, "risk": 4}) == ["risk>3"] \
        and m.hard_fails({"real_problem": 3, "scoped_s_m": 3, "verify_discriminates": 3, "not_dup_cosmetic": 3, "within_27b": 3, "risk": 3}) == []
    return res


@group
def g_shadow(script):
    res = {}
    d = fresh()
    script_critic({T_A: [crit_reply(), crit_reply()], T_B: [crit_reply(), crit_reply(False)], T_C: [crit_reply(False), crit_reply(False)], T_D: ["garbage", "garbage"]})
    rc, out = go(d, "shadow", "--max-items", "8", script=script)
    rm = roadmap_of(d)
    row = script_rows(d)[-1]  # noqa: F821
    res["shadow_filters_nothing"] = rm.count("[src:qwen-explore]") == 4 and row["accepted"] == 4 and not any(k.startswith("critic-") for k in row["rejected"])
    res["shadow_logs_verdicts"] = sorted(r["outcome"] for r in audit_rows(d)) == ["shadow-approve", "shadow-disagree", "shadow-error", "shadow-reject"] and all(r["mode"] == "shadow" for r in audit_rows(d))
    res["shadow_summary_reports_would_reject"] = "critic=shadow eval=4 approved=1 rejected=1 disagree=1 errors=1" in out
    rm_fixture(d)  # noqa: F821
    # shadow + critic down: fail-OPEN
    d = fresh()
    CRIT["fn"] = lambda prompt, body: None
    rc, out = go(d, "shadow", "--max-items", "8", script=script)
    row = script_rows(d)[-1]  # noqa: F821
    res["shadow_critic_down_fails_open"] = roadmap_of(d).count("[src:qwen-explore]") == 4 and row["result"] == "accepted" and row["accepted"] == 4
    rm_fixture(d)  # noqa: F821
    # DEFAULT (OVN_QWEN_CRITIC unset) is shadow: the critic runs, nothing is filtered
    d = fresh([item()])
    script_critic({T_A: [crit_reply(False), crit_reply(False)]})
    rc, out = run(d, "--lens", "bug-hunt", "--no-chain", script=script)  # noqa: F821
    res["default_is_shadow"] = len(critic_prompts()) == 2 and "Stop parse_page_size" in roadmap_of(d) and "critic=shadow" in out and audit_rows(d)[0]["mode"] == "shadow"
    rm_fixture(d)  # noqa: F821
    # an unknown value falls back to shadow (never silently to 'on')
    d = fresh([item()])
    script_critic({T_A: [crit_reply(False), crit_reply(False)]})
    run(d, "--lens", "bug-hunt", "--no-chain", extra={"OVN_QWEN_CRITIC": "banana"}, script=script)  # noqa: F821
    res["unknown_mode_is_shadow"] = "Stop parse_page_size" in roadmap_of(d) and audit_rows(d)[0]["mode"] == "shadow"
    rm_fixture(d)  # noqa: F821
    return res


@group
def g_off(script):
    res = {}
    d = fresh([item()])
    script_critic({T_A: [crit_reply(False), crit_reply(False)]})
    rc, out = go(d, "off", script=script)
    row = script_rows(d)[-1]  # noqa: F821
    res["off_no_critic_calls"] = len(critic_prompts()) == 0 and row["calls"] == 3
    res["off_item_appended_unchanged"] = "Stop parse_page_size" in roadmap_of(d) and row["accepted"] == 1
    res["off_no_audit_no_summary"] = not os.path.exists(os.path.join(d, "state", "qwen_critic.jsonl")) and "critic" not in out and "critic" not in row
    ap = os.path.join(d, "state", "qwen_explore", "accepted.jsonl")
    res["off_accepted_row_has_no_verdict"] = json.loads(open(ap).read().split("\n")[0]).get("critic") == ""
    rm_fixture(d)  # noqa: F821
    return res


@group
def g_dry(script):
    res = {}
    d = fresh([item()])
    script_critic({T_A: [crit_reply(), crit_reply()]})
    before = tree_digest(d)  # noqa: F821
    rc, out = run(d, "--lens", "bug-hunt", "--dry-run", "--no-chain", extra={"OVN_QWEN_CRITIC": "on"}, script=script)  # noqa: F821
    res["dry_critic_runs_and_reports"] = len(critic_prompts()) == 2 and "critic=on eval=1 approved=1" in out and "ACCEPTED" in out
    res["dry_writes_no_audit_nothing_else"] = not os.path.exists(os.path.join(d, "state", "qwen_critic.jsonl")) and tree_digest(d) == before  # noqa: F821
    rm_fixture(d)  # noqa: F821
    d = fresh([item()])
    script_critic({T_A: [crit_reply(), crit_reply()]})
    before = tree_digest(d)  # noqa: F821
    e = {"OVN_QWEN_CRITIC": "on", "DRY_RUN": "1"}
    r = sh(sys.executable, script or SCRIPT, REPO, "--lens", "bug-hunt", env=env_for(d, e))  # noqa: F821
    res["dry_env_var_honored"] = not os.path.exists(os.path.join(d, "state", "qwen_critic.jsonl")) and tree_digest(d) == before and "DRY-RUN" in r.stdout  # noqa: F821
    rm_fixture(d)  # noqa: F821
    return res


def _outcomes(d, slug, landed, total, tag):
    rows = [{"ts": "2026-10-13T10:00:00Z", "repo": REPO, "id": "x", "class": "landed" if i < landed else "noop", "item_hash": "%s%d" % (tag, i), "feat_tag": "%s-20261013-%s" % (REPO, slug)} for i in range(total)]  # noqa: F821
    return rows


@group
def g_throttle_feedback(script):
    res = {}
    qd = lambda d: os.path.join(d, "state", "qwen_explore")  # noqa: E731
    sa, sb = "critic-approved-slug", "critic-rejected-slug"

    def setup(d, a_landed, a_total, b_landed=20, b_total=20, a_critic="approve"):
        os.makedirs(qd(d), exist_ok=True)
        now = time.time()  # noqa: F821
        open(os.path.join(qd(d), "accepted.jsonl"), "w").write("\n".join(json.dumps(r) for r in [
            {"ts_epoch": now, "repo": REPO, "slug": sa, "title": "a", "critic": a_critic}, {"ts_epoch": now, "repo": REPO, "slug": sb, "title": "b", "critic": "reject"}]) + "\n")  # noqa: F821
        rows = _outcomes(d, sa, a_landed, a_total, "a") + _outcomes(d, sb, b_landed, b_total, "b")
        open(os.path.join(d, "state", "outcomes.jsonl"), "w").write("\n".join(json.dumps(r) for r in rows) + "\n")

    # critic-approved subset lands 5/20 (25%) although the overall rate is 25/40 = 62%: pause
    d = make_fixture()  # noqa: F821
    setup(d, 5, 20)
    reset_llm(PASS_A, reply_items())  # noqa: F821
    rc, out = run(d, "--force", "--lens", "bug-hunt", extra={"OVN_QWEN_CRITIC": "shadow"}, script=script)  # noqa: F821
    alerts = open(os.path.join(d, "state", "alerts.log")).read() if os.path.exists(os.path.join(d, "state", "alerts.log")) else ""
    res["throttle_critic_approved_not_landing_pauses"] = "skip-paused" in out and len(SEEN) == 0 and os.path.exists(os.path.join(qd(d), "paused_%s.json" % REPO))  # noqa: F821
    res["throttle_critic_alert_text"] = alerts.count("the critic approved but only 5 of 20") == 1 and alerts.count("self-throttle PAUSED") == 1
    res["throttle_critic_info_in_skip_note"] = "critic-approved" in out
    run(d, "--force", "--lens", "bug-hunt", script=script)  # noqa: F821
    alerts = open(os.path.join(d, "state", "alerts.log")).read()
    res["throttle_critic_one_alert"] = alerts.count("self-throttle PAUSED") == 1
    # overall rate fine and critic subset fine again => resumes
    setup(d, 10, 20)
    reset_llm(PASS_A, reply_items())  # noqa: F821
    run(d, "--force", "--lens", "bug-hunt", script=script)  # noqa: F821
    res["throttle_critic_resumes_on_recovery"] = len(SEEN) > 0 and not os.path.exists(os.path.join(qd(d), "paused_%s.json" % REPO))  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # fewer than 20 critic-approved consumed: never pauses on the critic rule
    d = make_fixture()  # noqa: F821
    setup(d, 3, 19)
    reset_llm(PASS_A, reply_items())  # noqa: F821
    rc, out = run(d, "--force", "--lens", "bug-hunt", script=script)  # noqa: F821
    res["throttle_critic_needs_20"] = "skip-paused" not in out and len(SEEN) > 0  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # a poor rate on critic-REJECTED items (shadow) is not a reason to pause
    d = make_fixture()  # noqa: F821
    setup(d, 20, 20, b_landed=0, b_total=20)
    reset_llm(PASS_A, reply_items())  # noqa: F821
    rc, out = run(d, "--force", "--lens", "bug-hunt", script=script)  # noqa: F821
    res["throttle_ignores_critic_rejected_subset"] = "skip-paused" not in out and len(SEEN) > 0  # noqa: F821
    rm_fixture(d)  # noqa: F821
    return res


# ======================================================================================================================================
@group
def g_shadow_never_loses_items(script):
    """Reviewer 3, defect 4: the shadow critic runs AFTER the append, under a hard total budget; a hung, erroring or truncating critic loses and delays no accepted item."""
    res = {}
    # 1) the item is already committed to the roadmap when the critic is first called
    d = fresh([item()])
    seen = []
    CRIT["fn"] = lambda prompt, body: (seen.append("Stop parse_page_size" in roadmap_of(d)), crit_reply())[1]
    go(d, "shadow", script=script)
    res["shadow_critic_runs_after_the_item_is_in_the_roadmap"] = bool(seen) and all(seen)
    rm_fixture(d)  # noqa: F821
    # 2) a HUNG critic: every item lands, the pass ends within the budget
    d = fresh()
    CRIT["fn"] = lambda prompt, body: 6.0
    t0 = time.time()  # noqa: F821
    rc, out = go(d, "shadow", "--max-items", "8", extra={"OVN_QE_CRITIC_TIMEOUT": "10", "OVN_QE_CRITIC_SHADOW_BUDGET_S": "2"}, script=script)
    row = script_rows(d)[-1]  # noqa: F821
    res["hung_critic_loses_no_item"] = roadmap_of(d).count("[src:qwen-explore]") == 4 and row["accepted"] == 4 and row["result"] == "accepted"
    res["hung_critic_is_bounded_by_the_budget"] = time.time() - t0 < 40 and len(critic_prompts()) == 1 and (row.get("critic") or {}).get("errors") == 4        # deterministic: with the 2 s budget the first call times out and the other 7 are never made; without it all 8 calls wait their 6 s reply (no wall-clock threshold: a loaded machine must not flake this)  # noqa: F821
    rm_fixture(d)  # noqa: F821
    # 3) a TRUNCATED critic reply (IncompleteRead): no crash, no loss
    d = fresh()
    CRIT["fn"] = lambda prompt, body: "TRUNC"
    rc, out = go(d, "shadow", "--max-items", "8", script=script)
    row = script_rows(d)[-1]  # noqa: F821
    res["truncating_critic_loses_no_item"] = rc == 0 and roadmap_of(d).count("[src:qwen-explore]") == 4 and row["accepted"] == 4 and row["result"] == "accepted"
    rm_fixture(d)  # noqa: F821
    # 4) with the chain: items committed + chain started BEFORE the critic; the verdicts follow in their own log line, and the throttle sees them via accepted.jsonl
    d = fresh([item()])
    script_critic({T_A: [crit_reply(), crit_reply()]})
    rc, out = run(d, "--lens", "bug-hunt", extra={"OVN_QWEN_CRITIC": "shadow"}, script=script)  # noqa: F821
    log = open(os.path.join(d, "logs", "qwen_explore.log")).read()
    calls = open(os.path.join(d, "chain_calls.txt")).read() if os.path.exists(os.path.join(d, "chain_calls.txt")) else ""
    res["shadow_with_chain_commits_and_chains_first"] = "Stop parse_page_size" in roadmap_of(d) and "planner" in calls and log.find("chain:") != -1 and log.find("critic-shadow:") > log.find("chain:")
    ap = os.path.join(d, "state", "qwen_explore", "accepted.jsonl")
    acc = [json.loads(x) for x in open(ap).read().split("\n") if x.strip()] if os.path.exists(ap) else []
    res["shadow_verdict_row_reaches_accepted_jsonl_for_the_throttle"] = any(r.get("critic") == "approve" and r.get("slug") for r in acc) and len(audit_rows(d)) == 1
    rm_fixture(d)  # noqa: F821
    # 5) hung critic WITH the chain: items committed, chain ran, the process still ends within the budget
    d = fresh([item()])
    CRIT["fn"] = lambda prompt, body: 6.0
    t0 = time.time()  # noqa: F821
    rc, out = run(d, "--lens", "bug-hunt", extra={"OVN_QWEN_CRITIC": "shadow", "OVN_QE_CRITIC_TIMEOUT": "1", "OVN_QE_CRITIC_SHADOW_BUDGET_S": "2"}, script=script)  # noqa: F821
    calls = open(os.path.join(d, "chain_calls.txt")).read() if os.path.exists(os.path.join(d, "chain_calls.txt")) else ""
    res["hung_critic_with_chain_loses_nothing_and_chain_ran"] = rc == 0 and "Stop parse_page_size" in roadmap_of(d) and "planner" in calls and time.time() - t0 < 25  # noqa: F821
    rm_fixture(d)  # noqa: F821
    return res


GROUP_KEYS = {}
REAL = {}
for _g_name, _fn in GROUPS.items():
    if os.environ.get("QC_TEST_ONLY") and _g_name not in os.environ["QC_TEST_ONLY"].split(","):
        continue
    _r = _fn(SCRIPT)  # noqa: F821
    GROUP_KEYS[_g_name] = set(_r)
    REAL.update(_r)
for _name, _v in REAL.items():
    ok(_name, _v)  # noqa: F821

# ---- MUTATION PROOFS
import tempfile  # noqa: E402
import os as _tt_os, sys as _tt_sys
_tt_sys.path.insert(0, _tt_os.path.dirname(_tt_os.path.abspath(__file__)))
import tmp_track
tmp_track.install()   # 2026-10-16: every tempfile.mkdtemp() below is removed at exit (these tests left dirs in the private TMPDIR)
MUT_ROOT = tempfile.mkdtemp(prefix="qc-mut-")


def mutated_script(name, old, new):
    base = os.path.join(MUT_ROOT, name.replace(" ", "_").replace("/", "_"))
    sd = os.path.join(base, "scripts")
    os.makedirs(sd)
    for fn in os.listdir(SCRIPTS):  # noqa: F821
        if fn.endswith((".py", ".sh")) and fn != "ovn_qwen_explore.py":
            os.symlink(os.path.join(SCRIPTS, fn), os.path.join(sd, fn))  # noqa: F821
    os.symlink(os.path.join(ROOT, "ovn_auto_research_validate.py"), os.path.join(base, "ovn_auto_research_validate.py"))  # noqa: F821
    src = open(SCRIPT).read()  # noqa: F821
    assert src.count(old) >= 1, "mutation anchor missing: " + old[:80]
    open(os.path.join(sd, "ovn_qwen_explore.py"), "w").write(src.replace(old, new, 1))
    return os.path.join(sd, "ovn_qwen_explore.py")


MUTATIONS = [
    ("either-approve instead of both-approve", "    if all(v == \"approve\" for v in vs):\n        return \"approve\"", "    if any(v == \"approve\" for v in vs):\n        return \"approve\"", ["on_disagree_rejected", "on_counts"]),
    ("top-N cut removed", "        keep = approved[:topn]\n", "        keep = approved\n", ["topn_keeps_two_best_not_first_two", "topn_cut_counted"]),
    ("fail-open in on mode (error counts as approve)", "    return \"error\", 0.0\n", "    return \"approve\", 3.0\n", ["on_malformed_fail_closed", "on_critic_down_fails_closed", "on_critic_timeout_fails_closed", "combine_algebra"]),
    ("ranking removed (keeps proposal order)", "key=lambda it: -it[\"critic\"][\"score\"])", "key=lambda it: 0)", ["topn_keeps_two_best_not_first_two", "topn_ranking_order_in_roadmap"]),
    ("hard-fail dimension ignored", "    rec[\"verdict\"] = \"approve\" if (c[\"approve\"] and not hf) else \"reject\"", "    rec[\"verdict\"] = \"approve\" if c[\"approve\"] else \"reject\"", ["on_hardfail_rejected"]),
    ("audit log not written", "    if dry:\n        return\n    try:\n        ap = os.path.join(OVN_DIR, \"state\", \"qwen_critic.jsonl\")", "    return\n    try:\n        ap = os.path.join(OVN_DIR, \"state\", \"qwen_critic.jsonl\")", ["audit_one_row_per_item", "audit_fields", "shadow_logs_verdicts"]),
    ("DRY_RUN writes the audit log", "    if dry:\n        return\n    try:\n        ap = os.path.join(OVN_DIR, \"state\", \"qwen_critic.jsonl\")", "    try:\n        ap = os.path.join(OVN_DIR, \"state\", \"qwen_critic.jsonl\")", ["dry_writes_no_audit_nothing_else", "dry_env_var_honored"]),
    ("shadow mode filters like on", "    if mode == \"shadow\":                                   # observe only", "    if False:                                   # observe only", ["shadow_filters_nothing", "shadow_critic_down_fails_open"]),
    ("default mode is on instead of shadow", "m = (os.environ.get(\"OVN_QWEN_CRITIC\") or \"shadow\")", "m = (os.environ.get(\"OVN_QWEN_CRITIC\") or \"on\")", ["default_is_shadow"]),
    ("unknown mode falls through to on", "return m if m in (\"off\", \"shadow\", \"on\") else \"shadow\"", "return m if m in (\"off\", \"shadow\", \"on\") else \"on\"", ["unknown_mode_is_shadow"]),
    ("kill switch off still runs the critic", "    if mode == \"shadow\" and written:\n        shadow_critic(repo, lens, accepted, snap, row, stats, now)", "    if mode != \"on\" and written:\n        shadow_critic(repo, lens, accepted, snap, row, stats, now)", ["off_no_critic_calls", "off_no_audit_no_summary"]),
    ("shadow critic runs BEFORE the append again", "(mode == \"on\" or dry):", "(mode != \"off\"):", ["shadow_critic_runs_after_the_item_is_in_the_roadmap"]),
    ("critic total budget ignored", "    left = (down[\"deadline\"] - time.time()) if down.get(\"deadline\") else CRITIC_TIMEOUT", "    left = CRITIC_TIMEOUT", ["hung_critic_is_bounded_by_the_budget"]),
    ("shadow verdicts never reach accepted.jsonl", "    record_critic(repo, items, now)\n\n\ndef ready_count", "    pass\n\n\ndef ready_count", ["shadow_verdict_row_reaches_accepted_jsonl_for_the_throttle"]),
    ("critic prompt leaks explorer context", "\"PROPOSED ITEM:\\n  title:", "\"FILES TO REVIEW (the ONLY code you may cite):\\nPROPOSED ITEM:\\n  title:", ["critic_prompt_no_explorer_context"]),
    ("critic samples share temperature and seed", "CRITIC_SAMPLES = ((0.1, 7101), (0.7, 7202))", "CRITIC_SAMPLES = ((0.1, 7101), (0.1, 7101))", ["critic_temps_and_seeds_differ", "audit_fields"]),
    ("critic reject-rate not in summary", "    cd = d.get(\"critic\")\n    if cd:", "    cd = None\n    if cd:", ["on_reject_rate_in_summary", "shadow_summary_reports_would_reject"]),
    ("critic-approved landing rate ignored by self-throttle", "    bad = bad_all or bad_critic\n", "    bad = bad_all\n", ["throttle_critic_approved_not_landing_pauses", "throttle_critic_alert_text"]),
    ("critic verdict not recorded for the throttle", "\"critic\": (it.get(\"critic\") or {}).get(\"verdict\", \"\"), ", "\"critic\": \"\", ", ["accepted_records_critic_verdict"]),
    ("critic outage burns the lens (no retry)", "            row.d[\"result\"], row.d[\"note\"] = \"error\", (row.d[\"note\"] + \" critic-unavailable", "            row.d[\"result\"], row.d[\"note\"] = \"empty\", (row.d[\"note\"] + \" critic-unavailable", ["on_critic_down_fails_closed"]),
]
if os.environ.get("QC_TEST_NO_MUT") or os.environ.get("QE_TEST_NO_MUT"):
    MUTATIONS = []
for _mn, _old, _new, _checks in MUTATIONS:
    need = {g for g, keys in GROUP_KEYS.items() for c in _checks if c in keys}
    if not (os.environ.get("QC_TEST_ONLY")):                               # a mutation whose checks live in no executed group would count as 'caught' vacuously (round 4 D1)
        ok("MUTATION '%s': its checks belong to an executed group" % _mn, bool(need), _checks)  # noqa: F821
        if not need:
            continue
    try:
        ms = mutated_script(_mn, _old, _new)
    except AssertionError as e:
        ok("MUTATION %s: anchor present" % _mn, False, e)  # noqa: F821
        continue
    try:
        res = {}
        for g in need:
            res.update(GROUPS[g](ms))
        caught = [c for c in _checks if not res.get(c)]
        detail = {c: res.get(c) for c in _checks}
    except Exception as e:
        caught, detail = list(_checks), "group raised %s" % type(e).__name__
    ok("MUTATION '%s': the mutated script FAILS %s" % (_mn, "/".join(caught)), len(caught) >= 1, detail)  # noqa: F821

shutil.rmtree(MUT_ROOT, ignore_errors=True)  # noqa: F821
srv.shutdown()  # noqa: F821
print("qwen critic: %d passed, %d failed" % (P, F))  # noqa: F821
sys.exit(1 if F else 0)
