#!/usr/bin/env python3
"""q-fri-shapes (2026-11-20): GD_PRELOAD_NO_PAREN (shadow verify-lint rule), TS1 env switches + park opt-in, the annotation-insensitive duplicate-def dedupe (OVN_DEDUPE_PY_ANNOT) and
ovn_placeholder_report.py (landed placeholder files). Every behaviour is also run against a source MUTANT (one piece of logic broken); each mutant must make run_checks fail."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time as _t0

HERE = os.path.dirname(os.path.abspath(__file__))
Q = os.path.abspath(os.path.join(HERE, "..", ".."))
SC = os.path.join(Q, "scripts")
PATHS = {"vl": os.path.join(Q, "ovn_verify_lint.py"), "dd": os.path.join(Q, "dedupe_python_duplicate_defs.py"), "pr": os.path.join(SC, "ovn_placeholder_report.py")}
FIXTURE = os.path.join(HERE, "fixtures_q_fri", "progress_text_d0a8f6cd.py")
_N = [0]


def load(path, name):
    sp = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


def w(p, txt=""):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(txt)


def git(repo, *a, env=None):
    e = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
    if env:
        e.update(env)
    return subprocess.run(["git", "-C", repo] + list(a), capture_output=True, text=True, env=e)


def run_checks(paths):
    fails = []

    def chk(name, cond):
        if not cond:
            fails.append(name)
    _N[0] += 1
    vl = load(paths["vl"], "vl_%d" % _N[0])
    for k in ("OVN_VERIFY_LINT", "OVN_VERIFY_LINT_PARK_RULES", "OVN_VERIFY_LINT_GD_PRELOAD", "OVN_VERIFY_LINT_TS1", "OVN_DEDUPE_PY_ANNOT"):
        os.environ.pop(k, None)
    with tempfile.TemporaryDirectory() as td:
        # ------------------------------------------------------------ 1. GD_PRELOAD_NO_PAREN
        repo = os.path.join(td, "xlite")
        w(os.path.join(repo, "scripts/mission/result_text.gd"), 'extends RefCounted\nconst StarRating = preload("res://scripts/mission/star_rating.gd")\nstatic func stars_text(stars: int) -> String:\n\treturn "%d of 3 stars" % stars\n')
        w(os.path.join(repo, "scripts/units/cmt.gd"), '# old style: preload "res://scripts/units/cooldown.gd"\nextends RefCounted\n')
        w(os.path.join(repo, "docs/notes.md"), 'preload "res://x.gd" is how some people write it\n')

        def gd(clause):
            item = "[T1] scripts/mission/result_text.gd - add the preload. VERIFY: `%s`." % clause
            return [r for r in vl.lint_all(item, repo, None) if r["rule"] == "GD_PRELOAD_NO_PAREN"]
        c1 = "grep -q 'static func stars_text' scripts/mission/result_text.gd && grep -q 'preload \"res://scripts/mission/star_rating.gd\"' scripts/mission/result_text.gd"
        r = gd(c1)
        chk("gd_flags_space_quote", len(r) == 1 and r[0]["verdict"] == "SUSPECT")
        chk("gd_suggest_paren", len(r) == 1 and "preload(\"res://scripts/mission/star_rating.gd\")" in r[0]["suggested_verify"] and r[0]["suggested_verify"].startswith("grep -qF"))
        r = gd("grep -q 'preload \"res://scripts/units/cooldown.gd\" as Cooldown' scripts/units/readiness_text.gd")
        chk("gd_flags_missing_target_file", len(r) == 1)
        chk("gd_suggest_drops_as", len(r) == 1 and " as " not in r[0]["suggested_verify"] and 'preload("res://scripts/units/cooldown.gd")' in r[0]["suggested_verify"])
        chk("gd_paren_form_ok", gd("grep -q 'preload(\"res://scripts/mission/star_rating.gd\")' scripts/mission/result_text.gd") == [])
        chk("gd_other_paren_pattern_ok", gd("grep -q 'preload(\"res://scripts/mission/other.gd\")' scripts/mission/result_text.gd") == [])
        chk("gd_non_gd_target_nomatch_ok", gd("grep -q 'preload \"res://zzz.gd\"' docs/notes.md") == [])
        chk("gd_wildcard_ok", gd("grep -q 'preload.*star_rating' scripts/mission/result_text.gd") == [])
        chk("gd_negated_ok", gd("! grep -q 'preload \"res://scripts/mission/star_rating.gd\"' scripts/mission/result_text.gd") == [])
        chk("gd_non_gd_target_ok", gd("grep -q 'preload \"res://x.gd\"' docs/notes.md") == [])
        chk("gd_matches_real_text_ok", gd("grep -q 'preload \"res://scripts/units/cooldown.gd\"' scripts/units/cmt.gd") == [])
        chk("gd_fixed_flag", len(gd("grep -qF 'preload \"res://scripts/mission/star_rating.gd\"' scripts/mission/result_text.gd")) == 1)
        chk("gd_include_gd_recursive", len(gd("grep -rq --include=*.gd 'preload \"res://scripts/mission/nope.gd\"' scripts")) == 1)
        # (a) separator-aware: a bad grep followed by || or ; can still pass; -L inverts the sense
        bad = "grep -q 'preload \"res://scripts/mission/nope.gd\"' scripts/mission/result_text.gd"
        chk("gd_or_follow_not_flagged", gd(bad + " || grep -q 'preload(' scripts/mission/result_text.gd") == [])
        chk("gd_semicolon_follow_not_flagged", gd(bad + " ; true") == [])
        chk("gd_or_after_cd_not_flagged", gd("cd scripts && " + bad.replace("scripts/mission/", "mission/") + " || true") == [])
        chk("gd_and_follow_still_flagged", len(gd(bad + " && true")) == 1 and len(gd("true || " + bad)) == 1 and len(gd(bad + " | head -1")) == 1)
        chk("gd_grep_L_not_flagged", gd("grep -L 'preload \"res://scripts/mission/nope.gd\"' scripts/mission/result_text.gd") == [])
        # (b) the suggestion must be a passable literal grep
        r = gd("grep -q 'preload \"res://scripts/mission/star_rating\\.gd\"' scripts/mission/result_text.gd")
        chk("gd_suggest_unescapes_dot", len(r) == 1 and r[0]["suggested_verify"] == "grep -qF 'preload(\"res://scripts/mission/star_rating.gd\")' scripts/mission/result_text.gd")
        sg = r[0]["suggested_verify"] if r else ""
        chk("gd_suggest_actually_passes", subprocess.run(sg, shell=True, cwd=repo, capture_output=True).returncode == 0 and sg != "")
        r = gd("grep -qE 'preload \"res://scripts/(mission|units)/star_rating\\.gd\"' scripts/mission/nofile.gd")
        chk("gd_ere_alternation_no_suggestion", len(r) == 1 and r[0]["suggested_verify"] == "")
        r = gd("grep -q 'preload \"res://scripts/mission/.*\\.gd\"' scripts/mission/nofile.gd")
        chk("gd_star_no_suggestion", len(r) == 1 and r[0]["suggested_verify"] == "")
        _gl = getattr(vl, "_gd_literal", lambda *a: "?")
        chk("gd_literal_helper", _gl("a\\.b", False) == "a.b" and _gl("(x|y)", True) is None and _gl("(x|y)", False) == "(x|y)" and _gl("a\\wb", False) is None)
        chk("gd_in_new_rules", "GD_PRELOAD_NO_PAREN" in vl.NEW_RULES)
        chk("gd_in_park_rules_ts1_not", "GD_PRELOAD_NO_PAREN" in vl.PARK_RULES and "TS1" not in vl.PARK_RULES and vl.PARK_RULES == ("NODEID_WRONG_FILE", "GD_PRELOAD_NO_PAREN"))
        # park path (the switch itself is OVN_VERIFY_LINT_PARK in the item guard, default off): 2 bad picks of a GD_PRELOAD line trip with this rule
        import hashlib
        import time as _t
        body = "[T1] scripts/mission/result_text.gd - add the preload. VERIFY: `%s`." % c1
        prog = os.path.join(td, "prog.md")
        w(prog, "- [ ] [T0] other. VERIFY: `true`\n- [ ] " + body + "\n")
        now = int(_t.time())
        md = hashlib.md5(body.encode()).hexdigest()
        outp = os.path.join(td, "out.jsonl")
        w(outp, "".join(json.dumps({"ts": _t.strftime("%Y-%m-%dT%H:%M:%SZ", _t.gmtime(now - m * 60)), "repo": "xlite", "class": "noop", "status": "no-op(ALREADY-DONE)", "item_hash": md, "item_line_hash": md, "duration_s": 30}) + "\n" for m in (50, 1)))
        pc_ = vl.park_cycle(outp, "xlite", prog, repo, os.path.join(td, "st0"), now, 2, 48)
        chk("gd_park_trips_with_default_rules", pc_["trip"] and pc_["rule"] == "GD_PRELOAD_NO_PAREN")
        os.environ["OVN_VERIFY_LINT_GD_PRELOAD"] = "off"
        chk("gd_env_off", gd(c1) == [])
        os.environ.pop("OVN_VERIFY_LINT_GD_PRELOAD")
        st = os.path.join(td, "state")
        item = "[T1] scripts/mission/result_text.gd - add the preload. VERIFY: `%s`." % c1
        vl.shadow_log(item, repo, "xlite", st, "test")
        vl.shadow_log(item, repo, "xlite", st, "test")
        lp = os.path.join(st, "verify_lint.jsonl")
        rows = [json.loads(x) for x in open(lp)] if os.path.exists(lp) else []
        chk("gd_shadow_row_once", [x["rule"] for x in rows] == ["GD_PRELOAD_NO_PAREN"])
        # ------------------------------------------------------------ 2. TS1 env switch + park opt-in
        w(os.path.join(repo, "web/package.json"), "{}\n")
        w(os.path.join(st, "tsc_baseline", "xlite__web.count"), "12\n")
        ts_item = "[T1] web/src/a.ts - add x. VERIFY: `cd web && npx tsc --noEmit`."
        chk("ts1_default_fires", any(x["rule"] == "TS1" for x in vl.lint_all(ts_item, repo, st)))
        os.environ["OVN_VERIFY_LINT_TS1"] = "off"
        chk("ts1_env_off", not any(x["rule"] == "TS1" for x in vl.lint_all(ts_item, repo, st)))
        os.environ.pop("OVN_VERIFY_LINT_TS1")
        os.environ["OVN_VERIFY_LINT_PARK_RULES"] = "TS1"
        pr_ = vl.park_cycle(os.path.join(td, "none.jsonl"), "xlite", os.path.join(td, "none.md"), repo, st, 1000000)
        chk("ts1_nameable_for_park", pr_["why"] != "no-park-rules")
        os.environ["OVN_VERIFY_LINT_PARK_RULES"] = "BOGUS_RULE"
        pr_ = vl.park_cycle(os.path.join(td, "none.jsonl"), "xlite", os.path.join(td, "none.md"), repo, st, 1000000)
        chk("unknown_park_rule_ignored", pr_["why"] == "no-park-rules")
        os.environ.pop("OVN_VERIFY_LINT_PARK_RULES")
        # ------------------------------------------------------------ 3. dedupe annotation-only duplicates (iptv_apps progress_text.py, d0a8f6cd)
        fx = open(FIXTURE).read() if os.path.exists(FIXTURE) else ""
        chk("fixture_present", fx.count("def remaining_text") == 2 and "Optional[float]" in fx and "float | None" in fx)

        def dd(mode, text):
            _N[0] += 1
            p = os.path.join(td, "dd%d" % _N[0], "f.py")
            w(p, text)
            env = dict(os.environ)
            if mode:
                env["OVN_DEDUPE_PY_ANNOT"] = mode
            r = subprocess.run([sys.executable, paths["dd"], p], capture_output=True, text=True, env=env)
            return r, open(p).read()
        r, after = dd(None, fx)
        chk("dd_default_is_shadow_no_change", r.stdout.strip() == "unchanged" and after == fx and "would remove" in r.stderr)
        r, after = dd("shadow", fx)
        chk("dd_shadow_no_change", r.stdout.strip() == "unchanged" and after == fx)
        r, after = dd("off", fx)
        chk("dd_off_silent", r.stdout.strip() == "unchanged" and after == fx and r.stderr.strip() == "")
        r, after = dd("on", fx)
        chk("dd_on_removes_later_copy", r.stdout.startswith("removed duplicate(s): remaining_text") and after.count("def remaining_text") == 1)
        chk("dd_on_keeps_earlier_complete_copy", "Optional[float]" in after and "def remaining_text(position_seconds: float | None" not in after and after.rstrip().endswith('return f"{minutes} min left"'))
        try:
            compile(after, "x", "exec")
            ok_c = True
        except SyntaxError:
            ok_c = False
        chk("dd_on_result_compiles", ok_c)
        body_diff = fx.replace('return f"{minutes} min left"', 'return f"{minutes} mins left"', 1)   # the FIRST copy differs in logic: NOT a duplicate
        r, after = dd("on", body_diff)
        chk("dd_on_logic_difference_kept", r.stdout.strip() == "unchanged" and after.count("def remaining_text") == 2)
        dflt_diff = fx.replace("duration_seconds: Optional[float]) -> str:", "duration_seconds: Optional[float] = 0) -> str:", 1)
        r, after = dd("on", dflt_diff)
        chk("dd_on_default_value_difference_kept", after.count("def remaining_text") == 2)
        r, after = dd("bogus", fx)
        chk("dd_bogus_mode_is_shadow", r.stdout.strip() == "unchanged" and after == fx)
        ret_only = "def h(a: int) -> int:\n    return a\n\n\ndef h(a: int):\n    return a\n"
        r, after = dd("on", ret_only)
        chk("dd_on_return_annotation_only", after.count("def h") == 1)
        arg_only = "def k(a):\n    return a\n\n\ndef k(a: int):\n    return a\n"
        r, after = dd("on", arg_only)
        chk("dd_on_param_annotation_only", after.count("def k") == 1)
        cls = "class A:\n    x: int = 1\n\n\nclass A:\n    x = 1\n"
        r, after = dd("on", cls)
        chk("dd_on_class_never_annot_merged", after == cls)
        ident = "def f(a):\n    return a\n\n\ndef f(a):\n    return a\n"
        r, after = dd(None, ident)
        chk("dd_byte_identical_still_removed_by_default", r.stdout.startswith("removed duplicate(s): f") and after.count("def f") == 1)
        deco = "import functools\n\n\n@functools.lru_cache\ndef f(a: int):\n    return a\n\n\n@functools.lru_cache\ndef f(a):\n    return a\n"
        r, after = dd("on", deco)
        chk("dd_on_decorated_both_kept", after == deco and r.stdout.strip() == "unchanged")
        deco1 = "@property\ndef f(a: int):\n    return a\n\n\ndef f(a):\n    return a\n"
        r, after = dd("on", deco1)
        chk("dd_on_decorated_first_only_kept", after == deco1)
        deco2 = "def f(a: int):\n    return a\n\n\n@register\ndef f(a):\n    return a\n"
        r, after = dd("on", deco2)
        chk("dd_on_decorated_second_only_kept", after == deco2)
        us = "def _(a: int):\n    return a\n\n\ndef _(a):\n    return a\n"
        r, after = dd("on", us)
        chk("dd_on_underscore_name_kept", after == us and r.stdout.strip() == "unchanged")
        r, after = dd("shadow", deco)
        chk("dd_shadow_decorated_silent", after == deco and "would remove" not in r.stderr)
        bad = "def g(:\n    pass\n\n\ndef g(x):\n    pass\n"
        r, after = dd("on", bad)
        chk("dd_syntax_error_is_not_equal", r.returncode == 0 and after.count("def g") == 2)
        # ------------------------------------------------------------ 4. placeholder report
        _N[0] += 1
        pm = load(paths["pr"], "pr_%d" % _N[0])
        g = os.path.join(td, "pg")
        os.makedirs(g)
        git(g, "init", "-q", "-b", "develop")
        git(g, "config", "user.email", "t@t")
        git(g, "config", "user.name", "t")
        M = "Placeholder - the implement step fills this in."
        old = {"GIT_AUTHOR_DATE": "2026-10-01T00:00:00Z", "GIT_COMMITTER_DATE": "2026-10-01T00:00:00Z"}
        w(os.path.join(g, "tests/test_empty.py"), '"""%s"""\n' % M)
        w(os.path.join(g, "web/a.test.ts"), "// %s\nimport { describe, it } from 'vitest'\n\ndescribe.skip('placeholder', () => { it('x', () => {}) })\n" % M)
        w(os.path.join(g, "tests/test_real.py"), '"""%s"""\nimport pytest\n\n\ndef test_a():\n    assert 1 + 1 == 2\n    assert len("ab") == 2\n' % M)
        w(os.path.join(g, "tests/test_noassert.py"), '"""%s"""\nimport os\n\n\ndef test_a():\n    x = os.getcwd()\n    print(x)\n    y = x + "a"\n' % M)
        w(os.path.join(g, "src/clean.py"), "X = 1\n")
        git(g, "add", "-A")
        git(g, "commit", "-q", "-m", "old", env=old)
        w(os.path.join(g, "tests/test_fresh.py"), '"""%s"""\n' % M)
        git(g, "add", "-A")
        git(g, "commit", "-q", "-m", "fresh")
        git(g, "update-ref", "refs/remotes/origin/develop", "HEAD")
        rows = pm.scan_repo(g, "origin/develop", 24)
        kinds = {x["path"]: x["kind"] for x in rows}
        chk("pr_marker_only", kinds.get("tests/test_empty.py") == "marker-only")
        chk("pr_stub_skip", kinds.get("web/a.test.ts") == "stub-skip")
        chk("pr_real_test_is_leftover", kinds.get("tests/test_real.py") == "marker-leftover")
        chk("pr_no_real_assert", kinds.get("tests/test_noassert.py") == "no-real-assert")
        chk("pr_fresh_under_24h_excluded", "tests/test_fresh.py" not in kinds)
        chk("pr_clean_excluded", "src/clean.py" not in kinds)
        chk("pr_test_flag", all(x["test"] for x in rows))
        chk("pr_all_when_age_zero", "tests/test_fresh.py" in {x["path"]: 1 for x in pm.scan_repo(g, "origin/develop", 0)})
        chk("pr_ref_fallback_develop", len(pm.scan_repo(g, "origin/nope", 24)) == len(rows))
        chk("pr_bad_repo_empty", pm.scan_repo(os.path.join(td, "missing"), "origin/develop", 24) == [])
        chk("pr_not_a_repo_empty", pm.scan_repo(td, "origin/develop", 24) == [])
        cli = subprocess.run([sys.executable, paths["pr"], "report", "--repo", g, "--json"], capture_output=True, text=True)
        try:
            jr = json.loads(cli.stdout)
            ok_j = cli.returncode == 0 and len(jr["repos"]["pg"]) == len(rows)
        except ValueError:
            ok_j = False
        chk("pr_cli_json", ok_j)
        cli = subprocess.run([sys.executable, paths["pr"], "report", "--repo", os.path.join(td, "missing")], capture_output=True, text=True)
        chk("pr_cli_missing_rc0", cli.returncode == 0 and "TOTAL 0" in cli.stdout)
        stp = os.path.join(td, "pstate")
        os.makedirs(stp)
        nw = pm.alert(g, stp, "origin/develop", 24, day="2026-11-20", dry=True)
        chk("pr_dry_run_writes_nothing", len(nw) == len(rows) and os.listdir(stp) == [])
        nw = pm.alert(g, stp, "origin/develop", 24, day="2026-11-20")
        chk("pr_alert_first_run", len(nw) == len(rows))
        ap = os.path.join(stp, "alerts.log")
        al = open(ap).read().strip().split("\n") if os.path.exists(ap) else []
        chk("pr_one_alert_per_repo_day", len(al) == 1 and "] warn | placeholder-landed:pg | " in al[0] and "3 placeholder file(s)" in al[0])
        lgp = os.path.join(stp, "placeholder_landed.log")
        lg = [json.loads(x) for x in open(lgp)] if os.path.exists(lgp) else []
        chk("pr_log_rows_all_kinds", sorted(x["path"] for x in lg) == sorted(kinds))
        nw = pm.alert(g, stp, "origin/develop", 24, day="2026-11-20")
        chk("pr_same_day_deduped", nw == [] and len(open(ap).read().strip().split("\n")) == 1)
        T0 = int(_t0.time())
        nw = pm.alert(g, stp, "origin/develop", 24, day="2026-11-21", now=T0 + 86400)
        # (the day-old placeholder test_fresh.py crosses the 24h age gate here: it is the ONLY new key; every file already reported is not repeated)
        chk("pr_next_day_not_reported_again", [x["path"] for x in nw] == ["tests/test_fresh.py"] and len(open(ap).read().strip().split("\n")) == 2 and len(open(lgp).read().strip().split("\n")) == len(rows) + 1)
        nw = pm.alert(g, stp, "origin/develop", 24, day="2026-11-26", now=T0 + 6 * 86400)
        chk("pr_day6_still_deduped", nw == [])
        nw = pm.alert(g, stp, "origin/develop", 24, day="2026-11-28", now=T0 + 7 * 86400 + 3600)
        chk("pr_after_7_days_warns_again", sorted(x["path"] for x in nw) == sorted(kinds) and len(open(ap).read().strip().split("\n")) == 3)
        # a changed file (new blob sha) is a new key: warns at once
        w(os.path.join(g, "tests/test_empty.py"), '"""%s"""\n# edited\n' % M)
        git(g, "add", "-A")
        git(g, "commit", "-q", "-m", "edit", env=old)
        git(g, "update-ref", "refs/remotes/origin/develop", "HEAD")
        nw = pm.alert(g, stp, "origin/develop", 24, day="2026-11-28", now=T0 + 7 * 86400 + 7200)
        chk("pr_changed_blob_warns_at_once", [x["path"] for x in nw] == ["tests/test_empty.py"])
        # bounded: seen + log trimmed to the last KEEP_LINES, atomically (no tmp left behind)
        pm.KEEP_LINES = 3
        nw = pm.alert(g, stp, "origin/develop", 24, day="2026-12-30", now=T0 + 60 * 86400)
        sl = open(os.path.join(stp, "placeholder_landed.seen")).read().strip().split("\n")
        ll = open(lgp).read().strip().split("\n")
        chk("pr_seen_and_log_bounded", len(sl) == 3 and len(ll) == 3 and all(json.loads(x) for x in ll))
        chk("pr_no_tmp_left", not [x for x in os.listdir(stp) if ".tmp." in x])
        pm.KEEP_LINES = 5000
        h = os.path.join(td, "ph")
        os.makedirs(h)
        git(h, "init", "-q", "-b", "develop")
        git(h, "config", "user.email", "t@t")
        git(h, "config", "user.name", "t")
        w(os.path.join(h, "tests/test_real.py"), '"""%s"""\n\n\ndef test_a():\n    assert 1 + 1 == 2\n    assert len("ab") == 2\n' % M)
        git(h, "add", "-A")
        git(h, "commit", "-q", "-m", "old", env=old)
        st2 = os.path.join(td, "pstate2")
        os.makedirs(st2)
        pm.alert(h, st2, "develop", 24, day="2026-11-20")
        chk("pr_leftover_logged_not_alerted", os.path.exists(os.path.join(st2, "placeholder_landed.log")) and not os.path.exists(os.path.join(st2, "alerts.log")))
        chk("pr_alert_never_raises_bad_state", pm.alert(g, "/proc/definitely/not/writable", "origin/develop", 24, day="2026-11-22") is not None)
    return fails


# (file key, old, new): each must make run_checks fail
MUTANTS = [
    ("vl", 'if "v" in flags or "L" in flags or not specs or not _PRELOAD_SPACE_Q.search(pat) or "preload(" in pat.replace("\\\\(", "("):', 'if "v" in flags or "L" in flags or not specs:'),
    ("vl", 'if not gd:\n            continue', 'if False:\n            continue'),
    ("vl", 'if _count(rx, files) > 0:\n                continue                    # it matches real text: not this shape', 'if False:\n                continue'),
    ("vl", 'if os.environ.get("OVN_VERIFY_LINT_GD_PRELOAD", "shadow").strip().lower() == "off":\n        return None', 'if False:\n        return None'),
    ("vl", '(?:\\s+as\\s+\\w+)?', ''),
    ("vl", 'lambda: rule_gd_preload(clause, repo_root))', 'lambda: None)'),
    ("vl", 'PARK_RULES = ("NODEID_WRONG_FILE", "GD_PRELOAD_NO_PAREN")', 'PARK_RULES = ("NODEID_WRONG_FILE",)'),
    ("vl", 'if os.environ.get("OVN_VERIFY_LINT_TS1", "shadow").strip().lower() == "off":\n        return None', 'if False:\n        return None'),
    ("vl", 'PARKABLE_EXTRA = ("TS1",)', 'PARKABLE_EXTRA = ()'),
    ("vl", 'if x in NEW_RULES + PARKABLE_EXTRA)', 'if True)'),
    ("dd", 'if key in seen_bodies and kind == "def" and amode != "off" and same_modulo_annotations(seen_bodies[key], body):', 'if False:'),
    ("dd", 'if amode == "on":\n                decisions.append(False)', 'if True:\n                decisions.append(False)'),
    ("dd", 'n.returns = None', 'pass'),
    ("dd", 'arg.annotation = None', 'pass'),
    ("dd", 'return v if v in ("off", "shadow", "on") else "shadow"', 'return v if v in ("off", "shadow", "on") else "on"'),
    ("dd", '    except (SyntaxError, ValueError, RecursionError, MemoryError):\n        return False', '    except (ValueError, RecursionError, MemoryError):\n        return False'),
    ("pr", 'if age_h < min_age_h:\n                continue', 'if False:\n                continue'),
    ("pr", 'if SKIP_RE.search(body):\n        return "stub-skip"', 'if False:\n        return "stub-skip"'),
    ("pr", 'if path and is_test_path(path) and _scan_verdict(path, body) == "stub":', 'if False:'),
    ("pr", 'if t_now - last.get((name, r["path"], r.get("sha", "")), -REWARN_S) >= REWARN_S]', 'if True]'),
    ("pr", 'REWARN_S = 7 * 86400', 'REWARN_S = 86400'),
    ("pr", 'REWARN_S = 7 * 86400', 'REWARN_S = 30 * 86400'),
    ("pr", '(name, r["path"], r.get("sha", ""))', '(name, r["path"], "")'),
    ("pr", '[-KEEP_LINES:])', ')'),
    ("pr", '        _trim(os.path.join(state, "placeholder_landed.log"))\n', ''),
    ("pr", 'os.replace(tmp, path)', 'os.rename(tmp, path); open(tmp, "w").write("x")'),
    ("vl", 'if nsep in ("||", ";"):', 'if False:'),
    ("vl", 'if nsep in ("||", ";"):', 'if nsep in ("||",):'),
    ("vl", 'if "v" in flags or "L" in flags or not specs', 'if "v" in flags or not specs'),
    ("vl", 'lit0 = pat if fixed else _gd_literal(pat, "E" in flags or t[0] == "egrep")', 'lit0 = pat'),
    ("vl", 'if d in ".[]*^$/\\\\\\"\'-" or (ere and d in "(){}|+?"):', 'if False:'),
    ("vl", 'if c in "*[^$" or (ere and c in "(){}|+?"):\n            return None', 'if False:\n            return None'),
    ("dd", 'if getattr(n, "decorator_list", None):', 'if False:'),
    ("dd", 'if getattr(n, "name", "") == "_":', 'if False:'),
    ("pr", 'return row["kind"] in ("stub-skip", "marker-only", "no-real-assert")', 'return True'),
    ("pr", 'if dry or not new:\n            return new', 'if not new:\n            return new'),
    ("pr", 'for r in ([ref] if ref else []) + ["origin/develop", "develop"]:', 'for r in ([ref] if ref else []):'),
]


def main():
    fails = run_checks(PATHS)
    for f in fails:
        print("FAIL", f)
    srcs = {k: open(v).read() for k, v in PATHS.items()}
    survived = 0
    for i, (key, old, new) in enumerate(MUTANTS):
        if old not in srcs[key]:
            print("MUTANT %d: pattern not found (stale mutant): %s" % (i, old[:70]))
            fails.append("stale_mutant_%d" % i)
            continue
        with tempfile.TemporaryDirectory() as td:
            mp = {}
            # a mutant lives next to a copy of its siblings so imports / relative paths (ovn_pick_cap, ovn_placeholder_scan) resolve
            mp["vl"] = os.path.join(td, "ovn_verify_lint.py")
            open(mp["vl"], "w").write(srcs["vl"] if key != "vl" else srcs["vl"].replace(old, new, 1))
            open(os.path.join(td, "ovn_pick_cap.py"), "w").write(open(os.path.join(Q, "ovn_pick_cap.py")).read())
            mp["dd"] = os.path.join(td, "dedupe_python_duplicate_defs.py")
            open(mp["dd"], "w").write(srcs["dd"] if key != "dd" else srcs["dd"].replace(old, new, 1))
            os.makedirs(os.path.join(td, "scripts"))
            mp["pr"] = os.path.join(td, "scripts", "ovn_placeholder_report.py")
            open(mp["pr"], "w").write(srcs["pr"] if key != "pr" else srcs["pr"].replace(old, new, 1))
            open(os.path.join(td, "scripts", "ovn_placeholder_scan.py"), "w").write(open(os.path.join(SC, "ovn_placeholder_scan.py")).read())
            try:
                mf = run_checks(mp)
            except Exception as e:
                mf = ["exception:%s" % e]
        if not mf:
            survived += 1
            print("MUTANT %d SURVIVED: %s -> %s" % (i, old[:70], new[:40]))
            fails.append("mutant_%d_survived" % i)
    print("q-fri-shapes: %d failure(s), %d of %d mutants survived" % (len(fails), survived, len(MUTANTS)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
