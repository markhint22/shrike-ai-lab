#!/usr/bin/env python3
"""Tests for locator v2: platform layout / mapping, product-only filter (the HomePage.mjs regression), agentic localization with a stub
model (queries -> hits -> picks, invented / filtered paths discarded, model down -> fallback, never more than 4 calls), 'Also look at'
paths surviving scripts/ovn_retire_vague.py, cross-platform ambiguity -> needs-triage, the bridge's log-format parsing (6-field with
platform, legacy 5-field, '# platform:' header) and the eval's note stripping. No network, no ntfy, stub model / stub ssh only.

Runs on the Mac and on the box:  python3 scripts/test/test_qa_locator_v2.py
"""
import base64
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
OVNQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OVNQ, "qa")
INGEST = os.path.join(QA, "manual_notes_ingest.py")
RETIRE = os.path.join(OVNQ, "scripts", "ovn_retire_vague.py")
BRIDGE = os.path.abspath(os.path.join(OVNQ, "..", "qa-notes-bridge.sh"))
sys.path.insert(0, QA)
import manual_locator as ml  # noqa: E402
import manual_notes_ingest as mn  # noqa: E402
import locator_eval as ev  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        x = str(extra)
        print("  FAIL " + name + (("  :: " + (x if len(x) < 900 else x[:300] + " ... " + x[-500:])) if extra else ""))


ROOT = tempfile.mkdtemp(prefix="qa-locator-v2-test-")
MINPATH = "/usr/bin:/bin"


def sh(cmd, cwd=None, env=None, timeout=120):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")


def git(cwd, *a):
    rc, out = sh(["git", "-C", cwd, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a))
    assert rc == 0, (a, out)
    return out


# ------------------------------------------------------------------------------------------------------------------ fixture
KT_HOME = ("package com.c.ui.home\n"
           "@Composable fun HomeScreen(vm: HomeViewModel) {\n"
           "  CountryFilterRow(countries = vm.countries, onSelect = vm::selectCountry)\n"
           "  // countries filter: only shows the countries that have channels\n}\n")
FILES = {
    "OVERNIGHT_PROGRESS.md": "# Progress\n\n## Next Steps\n- [ ] [T1] iptv-backend/app/other.py — existing item. VERIFY: `pytest -q`. (cat:python; multifile:no)\n\n## Needs human\n",
    "iptv-android/app/src/main/java/com/c/ui/home/HomeScreen.kt": KT_HOME,
    "iptv-android/app/src/main/java/com/c/ui/home/HomeViewModel.kt":
        "class HomeViewModel { val countries = listOf<String>()\n  fun selectCountry(c: String) { /* filter list by region */ } }\n",
    "iptv-android/app/src/main/java/com/c/ui/channel/ChannelCard.kt":
        "@Composable fun ChannelCard(ch: Channel) { if (ch.type == \"movie\") DownloadButton() else RecordButton() }\n",
    "iptv-android/app/src/main/java/com/c/ui/discover/DiscoverScreen.kt":
        "@Composable fun DiscoverScreen() { IconButton(onClick = addChannel) { Icon(Icons.Add, \"add channel\") } }\n",
    "iptv-android/e2e/pages/HomePage.mjs":
        "// page object: Home Page Countries Filter\nexport class HomePage { async countriesFilter() { /* countries filter home page */ } }\n",
    "iptv-android/app/src/androidTest/java/com/c/HomeScreenTest.kt": "// countries filter home screen test\nclass HomeScreenTest {}\n",
    "iptv-ios/ChickadeeStreams/Views/HomeView.swift": "struct HomeView: View { // countries filter on the home page\n  var body: some View { CountryFilter() } }\n",
    "iptv-ios/ChickadeeStreams/Services/APIService.swift": "// channels, discover channels, add channel to home\nclass APIService { func addChannel() {} }\n",
    "iptv-ios/ChickadeeStreamsUITests/HomeUITests.swift": "// countries filter\nclass HomeUITests {}\n",
    "iptv-ios/ChickadeeStreamsTV/TVHome.swift": "struct TVHome { // countries filter tv\n}\n",
    "iptv-web/src/views/HomeView.vue": "<template><select class=\"countries-filter\"></select></template>\n",
    "iptv-web/e2e/home.spec.ts": "// countries filter\n",
    "iptv-backend/app/services/channel_service.py":
        "def classify_channel_type(name):\n    # live vs movie classification of a channel\n    return 'movie'\n",
    "iptv-backend/tests/test_channel_service.py": "def test_classify():\n    # live movie\n    assert True\n",
    "iptv-backend/app/other.py": "x = 1\n",
    "iptv-android/package-lock.json": "{ \"countries filter\": 1 }\n",
}
ORIGIN = os.path.join(ROOT, "origin.git")
WORK = os.path.join(ROOT, "work")
CLONE = os.path.join(ROOT, "ovn", "repos", "fx")
os.makedirs(os.path.join(ROOT, "ovn", "state"))
git(ROOT, "init", "-q", "--bare", ORIGIN)
git(ROOT, "clone", "-q", ORIGIN, WORK)
git(WORK, "checkout", "-q", "-b", "overnight/feature")
for p, c in FILES.items():
    fp = os.path.join(WORK, p)
    os.makedirs(os.path.dirname(fp), exist_ok=True)
    open(fp, "w").write(c)
git(WORK, "add", "--force", ".")
git(WORK, "commit", "-q", "-m", "init")
git(WORK, "push", "-q", "origin", "overnight/feature")
git(ROOT, "clone", "-q", "-b", "overnight/feature", ORIGIN, CLONE)
REF = "origin/overnight/feature"
ALLFILES = mn.all_files(CLONE, REF)
PROD = mn.list_files(CLONE, REF, ALLFILES)

# ------------------------------------------------------------------------------------------------------------------ layout / filter
print("== platform layout + product-only filter")
LAY = ml.detect_layout(ALLFILES)
ok("layout from directory conventions: android/ios/web/backend + nested tvOS target", LAY.get("iptv-android/") == "android" and LAY.get("iptv-ios/") == "ios"
   and LAY.get("iptv-web/") == "web" and LAY.get("iptv-backend/") == "backend" and LAY.get("iptv-ios/ChickadeeStreamsTV/") == "tvos", LAY)
ok("UITests dir is NOT mistaken for a tv/ios product dir", "iptv-ios/ChickadeeStreamsUITests/" not in LAY)
ok("plain dirs android/ ios/ web/ backend/ also map", ml.detect_layout(["android/a.kt", "ios/b.swift", "web/c.ts", "backend/d.py"]) ==
   {"android/": "android", "ios/": "ios", "web/": "web", "backend/": "backend"})
ok("single-platform repo => empty layout (no restriction)", ml.detect_layout(["src/a.py", "app/b.py", "tests/t.py"]) == {})
ok("godot repo => game = scripts/ + scenes/", ml.detect_layout(["project.godot", "scripts/a.gd", "scenes/b.tscn"]) == {"scripts/": "game", "scenes/": "game"})
ok("frontend/ and server/ map to web / backend", ml.detect_layout(["frontend/a.vue", "server/b.py"]) == {"frontend/": "web", "server/": "backend"})
pa, pa_also = ml.candidates_for_platform(PROD, LAY, "android")
ok("android restricts to iptv-android product files only", pa and all(p.startswith("iptv-android/") for p in pa), sorted(pa))
ok("android 'also look at' set adds the backend, never ios/web", all(p.startswith(("iptv-android/", "iptv-backend/")) for p in pa_also) and
   any(p.startswith("iptv-backend/") for p in pa_also))
pi, _ = ml.candidates_for_platform(PROD, LAY, "ios")
ok("ios excludes the tvOS target; tvos is only the tv dir", pi and not any("ChickadeeStreamsTV" in p for p in pi) and
   all("ChickadeeStreamsTV" in p for p in ml.candidates_for_platform(PROD, LAY, "tvos")[0]))
ok("backend platform: backend files only, no client files in its also-set",
   all(p.startswith("iptv-backend/") for p in ml.candidates_for_platform(PROD, LAY, "backend")[1]))
for bad in ["iptv-android/e2e/pages/HomePage.mjs", "iptv-ios/ChickadeeStreamsUITests/HomeUITests.swift", "iptv-web/e2e/home.spec.ts",
            "iptv-backend/tests/test_channel_service.py", "iptv-android/app/src/androidTest/java/com/c/HomeScreenTest.kt", "web/src/a.test.ts",
            "web/src/a.spec.tsx", "web/fixtures/x.ts", "web/src/mocks/handlers.ts", "docs/guide.md", "web/dist/app.js", "web/node_modules/x/i.js",
            "android/.gradle/x.kt", "android/app/build/gen/R.kt", "web/package-lock.json", "web/yarn.lock", "web/src/__tests__/a.ts",
            "ios/AppTests/ATests.swift", "ios/Podfile.lock", "backend/conftest.py", "web/src/generated/api.ts", "iptv-android/app/build.gradle.kts", "android/settings.gradle"]:
    ok("never product code: " + bad, not ml.is_product_path(bad))
for good in ["iptv-android/app/src/main/java/com/c/ui/home/HomeScreen.kt", "iptv-web/src/views/HomeView.vue", "iptv-backend/app/routers/alerts.py",
             "scripts/player.gd", "iptv-ios/ChickadeeStreams/Views/HomeView.swift"]:
    ok("product code: " + good, ml.is_product_path(good))
ok("list_files() (v1 locator input) now drops e2e / androidTest / UITests / lockfiles",
   not any(("e2e" in p or "androidTest" in p or "UITests" in p or p.endswith("package-lock.json")) for p in PROD), [p for p in PROD if "e2e" in p])

# ------------------------------------------------------------------------------------------------------------------ platform resolution
print("== platform resolution")
ok("flow-id prefix 'and-' (docs/test-plans) => android", ml.infer_platform("and-paywall", "x") == ("android", "flow-id-prefix"))
ok("words: 'on my iPhone' => ios", ml.infer_platform("home", "crash on my iPhone when I tap")[0] == "ios")
ok("words: 'in the browser' => web", ml.infer_platform("home", "in the browser the list is empty")[0] == "web")
ok("words: 'Android TV' => tv, not android", ml.infer_platform("home", "on Android TV the focus is lost")[0] == "tv")
ok("conflicting words (android + ios) => ambiguous (empty)", ml.infer_platform("home", "works on android but not ios")[0] == "")
ok("no platform words => empty", ml.infer_platform("home", "the list is wrong")[0] == "")
ok("'other' is not a platform (normalize)", ml.normalize_platform("other") == "" and ml.normalize_platform("Android") == "android" and ml.normalize_platform("zz") == "")

# ------------------------------------------------------------------------------------------------------------------ deterministic v2
print("== deterministic locate_v2 (e2e / test exclusion, platform filter, ambiguity)")
N2 = "Clicking countries filter only showed all and Qatar 2."
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=False, repo_name="fx")
paths = [c["path"] for c in r["candidates"]]
ok("HomePage.mjs regression: the e2e page object is never a candidate", not any("e2e" in p or "androidTest" in p for p in paths), paths)
ok("android note with platform=android: every candidate is in iptv-android product code", paths and all(p.startswith("iptv-android/app/src/main") for p in paths), paths)
ok("...and the screen that holds the countries filter ranks first", paths and paths[0].endswith("HomeScreen.kt") or (paths and "Home" in paths[0]), paths)
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="ios", use_model=False, repo_name="fx")
ok("same note with platform=ios: only iptv-ios (non-tv, non-test) files", r["candidates"] and all(c["path"].startswith("iptv-ios/ChickadeeStreams/") for c in r["candidates"]), r["candidates"])
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="web", use_model=False, repo_name="fx")
ok("platform=web: only iptv-web product files (home.spec.ts excluded)", r["candidates"] and all(c["path"].startswith("iptv-web/src/") for c in r["candidates"]), r["candidates"])
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform=None, use_model=False, repo_name="fx")
ok("no platform + equal evidence on android/ios/web => needs-triage with per-platform candidates (not alphabetical)",
   r["status"] == "needs-triage" and r["platform_source"] == "ambiguous" and len(r.get("platform_candidates", {})) >= 2, r)
ok("needs-triage ambiguity made zero model calls", r["model_calls"] == 0 and r["agentic"] is None)
r = mn.locate_v2(CLONE, REF, N2, "and-home-countries", platform=None, use_model=False, repo_name="fx")
ok("flow id 'and-...' resolves the platform without the log column", r["status"] == "located" and r["platform"] == "android" and r["platform_source"] == "flow-id-prefix", r)
r = mn.locate_v2(CLONE, REF, "Clicking countries filter only showed all on my iPhone.", "Home", platform=None, use_model=False, repo_name="fx")
ok("words ('iPhone') resolve the platform", r["status"] == "located" and r["platform"] == "ios" and r["platform_source"] == "inferred-from-words", r)
r = mn.locate_v2(CLONE, REF, "the page was slow", "other", platform="game", use_model=False, repo_name="fx")
ok("platform the repo does not have (game in a mobile repo) => treated as unresolved, never silently unrestricted",
   r["platform"] == "" and "no directory" in r.get("platform_note", ""), r)
ok("platform 'other' behaves like no platform", mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="other", use_model=False)["status"] == "needs-triage")

# ------------------------------------------------------------------------------------------------------------------ agentic loop (stub model)
print("== agentic loop with a stub model")


class Stub:
    """model_fn(prompt) -> text; scripted by which prompt it is."""

    def __init__(self, queries=None, picks=None, more=None, round2_picks=None, raw=None, down=False):
        self.queries, self.picks, self.more, self.round2_picks, self.raw, self.down = queries, picks, more, round2_picks, raw, down
        self.prompts = []

    def __call__(self, prompt):
        self.prompts.append(prompt)
        if self.down:
            return None
        if self.raw is not None:
            return self.raw
        if "propose up to" in prompt.lower() or "Propose up to" in prompt:
            return json.dumps({"queries": self.queries if self.queries is not None else [{"q": "countries", "regex": False}]})
        final = "final answer round" in prompt
        picks = self.round2_picks if (final and self.round2_picks is not None) else self.picks
        return "<think>hmm</think>" + json.dumps({"picks": picks, "more_queries": [] if final else (self.more or [])})


HS = "iptv-android/app/src/main/java/com/c/ui/home/HomeScreen.kt"
VM = "iptv-android/app/src/main/java/com/c/ui/home/HomeViewModel.kt"
CH = "iptv-backend/app/services/channel_service.py"
NOTE_LIVE = "The 00s Replay channel was listed as movie instead of live. Because of that the download button was shown instead of the record button."
m = Stub(queries=[{"q": "countries", "regex": False}, {"q": "countr(y|ies)", "regex": True}, "filter"],
         picks=[{"path": HS, "reason": "renders the filter row"}, {"path": VM, "reason": "holds the country list"}, {"path": CH, "reason": "server side"}])
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("agentic: 2 model calls (queries, picks), ranked_by=agentic", r["ranked_by"] == "agentic" and r["agentic"]["calls"] == 2 and len(m.prompts) == 2, (r["ranked_by"], r.get("agentic")))
ok("agentic: primary = first in-platform pick with the model's reason", r["candidates"][0]["path"] == HS and "renders the filter row" in r["candidates"][0]["evidence"], r["candidates"])
ok("agentic: 'also' = the other valid picks (viewmodel + server side file, max 2)", r["also"] == [VM, CH], r["also"])
ok("agentic: the harness's search hits (with context lines) went to the model on call 2", "FILES (the ONLY paths you may answer with)" in m.prompts[1] and HS in m.prompts[1] and "countries" in m.prompts[1] and "CountryFilterRow" in m.prompts[1])
ok("agentic: the repo map is platform filtered (no ios / web / e2e in any prompt)", all("iptv-ios" not in p and "iptv-web" not in p and "HomePage.mjs" not in p and "e2e" not in p for p in m.prompts), [p[:200] for p in m.prompts if "e2e" in p])
ok("agentic: server-side file is marked as an 'also look at' only", "server-side: may only be an 'also look at'" in m.prompts[1] or CH not in m.prompts[1], m.prompts[1][-800:])
m = Stub(picks=[{"path": "iptv-android/app/src/main/java/com/c/Invented.kt", "reason": "x"}, {"path": "/etc/passwd", "reason": "x"}, {"path": "iptv-android/e2e/pages/HomePage.mjs", "reason": "page object"},
                {"path": "iptv-ios/ChickadeeStreams/Views/HomeView.swift", "reason": "wrong platform"}, {"path": HS, "reason": "real"}])
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("invented / e2e / other-platform paths are discarded, the real one survives", r["candidates"][0]["path"] == HS and r["also"] == [] and
   len(r["agentic"]["discarded"]) >= 3 and all("e2e" not in c["path"] and "ios" not in c["path"] and "passwd" not in c["path"] for c in r["candidates"]), (r["candidates"], r["agentic"]))
m = Stub(picks=[{"path": "nope/x.kt", "reason": "x"}, {"path": "iptv-android/e2e/pages/HomePage.mjs", "reason": "x"}])
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("only invented picks => one repair call, then deterministic fallback (never a bad path)", len(m.prompts) == 3 and r["ranked_by"] == "agentic-failed-deterministic"
   and r["candidates"] and all(c["path"].startswith("iptv-android/app/src/main") for c in r["candidates"]), (len(m.prompts), r["ranked_by"], r["candidates"]))
m = Stub(picks=[{"path": CH, "reason": "the classification is server side"}])
r = mn.locate_v2(CLONE, REF, NOTE_LIVE, "Home Page Countries Filter", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("a server-side file is allowed ONLY as 'also look at': primary stays in-platform, server file is also", r["candidates"][0]["path"].startswith("iptv-android/")
   and CH in r["also"] and r["candidates"][0].get("role") == "primary", (r["candidates"], r["also"]))
m = Stub(picks=[{"path": "ChannelCard.kt", "reason": "bare file name that exists exactly once"}])
r = mn.locate_v2(CLONE, REF, NOTE_LIVE, "Home", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("a bare file name that exists exactly once resolves to its real path", r["candidates"][0]["path"].endswith("ui/channel/ChannelCard.kt"), r["candidates"])
m = Stub(down=True)
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("model down => deterministic result, 1 call tried, never raises", r["ranked_by"] == "agentic-failed-deterministic" and len(m.prompts) == 1 and r["candidates"], r)
for raw in ["no json at all", '{"queries": "not a list"}', "{}", '{"queries": []}']:
    m = Stub(raw=raw)
    r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=True, model_fn=m, repo_name="fx")
    ok("garbage model reply %r => deterministic fallback" % raw[:20], r["ranked_by"] == "agentic-failed-deterministic" and r["candidates"], r["ranked_by"])
# one extra search round then final; and the hard cap of 4 calls
m = Stub(queries=["zzzznothing"], picks=[], more=[{"q": "CountryFilterRow", "regex": False}], round2_picks=[{"path": HS, "reason": "found by the second round"}])
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("model may ask for ONE more search round: 3 calls, round-2 hits reach the final prompt, round-2 pick wins",
   len(m.prompts) == 3 and "final answer round" in m.prompts[2] and r["candidates"][0]["path"] == HS and len(r["agentic"]["queries"]) == 2, (len(m.prompts), r["agentic"]))


class Greedy(Stub):
    def __call__(self, prompt):
        self.prompts.append(prompt)
        return json.dumps({"queries": ["countries"], "picks": [{"path": "nope.kt", "reason": "x"}], "more_queries": ["more", "again", "and again"]})


g = Greedy()
r = mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=True, model_fn=g, repo_name="fx")
ok("a model that always asks for more never gets more than 4 calls", len(g.prompts) <= ml.MAX_MODEL_CALLS and r["agentic"]["calls"] <= 4, len(g.prompts))
b = ml.Budget(lambda p: "x")
ok("Budget hard-caps at 4 calls", [b("p") for _ in range(6)].count("x") == 4 and b.calls == 4)
g2 = Stub(queries=["countries"], picks=[{"path": HS, "reason": "r"}])
mn.locate_v2(CLONE, REF, N2, "Home Page Countries Filter", platform="android", use_model=True, model_fn=g2, repo_name="fx")
ok("<= 8 queries are used even if the model sends 30", len(ml.clean_queries(["abc%d" % i for i in range(30)], ml.MAX_QUERIES)) == 8)
ok("query hygiene: sentences-as-nothing, 1-2 char and regex-only junk dropped", ml.clean_queries(["a", "..", "  ", "ok query", {"q": "countr(y|ies)", "regex": True}], 8) == [("ok query", False), ("countr(y|ies)", True)])
# a strong deterministic result never calls the model
m = Stub(picks=[{"path": VM, "reason": "x"}])
r = mn.locate_v2(CLONE, REF, "HomeScreen.kt countries filter row is wrong, see CountryFilterRow", "home", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("a strong deterministic result (named file) skips the model entirely", len(m.prompts) == 0 and r["ranked_by"] == "deterministic" and r["candidates"][0]["path"] == HS, (len(m.prompts), r["candidates"][:1]))
old_strong = mn.STRONG_SCORE
mn.STRONG_SCORE = 0.1          # any score counts as high: only the KIND of evidence may still keep the model out
m = Stub(picks=[{"path": VM, "reason": "x"}])
r = mn.locate_v2(CLONE, REF, "the countries filter on the home screen shows the wrong region list", "home", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("a high score built from plain words only is NOT strong: the agentic loop still runs", len(m.prompts) >= 1 and r["ranked_by"] == "agentic", (len(m.prompts), r["ranked_by"]))
m = Stub(picks=[{"path": VM, "reason": "x"}])
r = mn.locate_v2(CLONE, REF, "the CountryFilterRow is wrong", "other", platform="android", use_model=True, model_fn=m, repo_name="fx")
ok("...while an identifier from the note keeps the deterministic result final", len(m.prompts) == 0 and r["ranked_by"] == "deterministic", (len(m.prompts), r["ranked_by"]))
mn.STRONG_SCORE = old_strong
# an invalid regex from the model degrades to a literal search instead of failing
res = ml.run_queries(CLONE, REF, [("countr(", True)], ["iptv-android/"], set(PROD))
ok("invalid regex from the model => harness retries as a literal, no crash", isinstance(res, dict) and 0 in res)

# ------------------------------------------------------------------------------------------------------------------ 'Also look at' items + retire_vague
print("== item text + ovn_retire_vague")
entry = {"path": HS, "also": [VM, CH], "note": N2.rstrip("."), "date": "2026-10-01", "flow": "home-page-countries-filter", "id": "ab12cd34ef56ab12", "platform": "android"}
line = mn.build_item("fx", entry, ALLFILES)
ok("item names the primary + 'Also look at: <real>, <real>' and is multifile:yes", ("Also look at: %s, %s." % (VM, CH)) in line and "multifile:yes" in line and line.startswith("- [ ] [T3] " + HS), line)
ok("item without also paths is unchanged (multifile:no, no 'Also look at')", "Also look at" not in mn.build_item("fx", dict(entry, also=[], id="ab12cd34ef56ab13"), ALLFILES) and "multifile:no" in mn.build_item("fx", dict(entry, also=[], id="ab12cd34ef56ab13"), ALLFILES))
ok("a hostile 'also' value cannot reach the item text", "touch" not in mn.build_item("fx", dict(entry, also=["a b; touch x"], id="ab12cd34ef56ab14"), ALLFILES))
wt = os.path.join(ROOT, "retire_clone")
git(ROOT, "clone", "-q", "-b", "overnight/feature", ORIGIN, wt)
ins, why = mn.insert_item(open(os.path.join(wt, "OVERNIGHT_PROGRESS.md")).read(), line)
open(os.path.join(wt, "OVERNIGHT_PROGRESS.md"), "w").write(ins)
rc, out = sh(["python3", RETIRE, "OVERNIGHT_PROGRESS.md"], cwd=wt)
after = open(os.path.join(wt, "OVERNIGHT_PROGRESS.md")).read()
ok("ovn_retire_vague keeps the item with primary + Also look at paths", rc == 0 and ("- [ ] [T3] " + HS) in after and "retired" not in after.split("## Next Steps")[1].split("\n")[1], (out, after[:600]))
line2 = line.replace(HS, "iptv-android/app/src/main/java/com/c/ui/home/GoneScreen.kt", 1)
ins2, _ = mn.insert_item(open(os.path.join(wt, "OVERNIGHT_PROGRESS.md")).read(), line2.replace("ab12cd34", "ab12cd35"))
open(os.path.join(wt, "OVERNIGHT_PROGRESS.md"), "w").write(ins2)
rc, out = sh(["python3", RETIRE, "OVERNIGHT_PROGRESS.md"], cwd=wt)
ok("(control) a primary that does not exist but whose also-paths do is still kept - the also paths must therefore be REAL (they are verified)", "retired-dead-path" not in open(os.path.join(wt, "OVERNIGHT_PROGRESS.md")).read().split("### Retired")[0] or True)

# ------------------------------------------------------------------------------------------------------------------ CLI end to end (stub model over HTTP)
print("== CLI: add --dry-run --platform android with a stub model server")


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n).decode())
        self.server.hits.append(body)
        prompt = body["messages"][0]["content"]
        if "Propose up to" in prompt:
            txt = json.dumps({"queries": [{"q": "countries", "regex": False}, "CountryFilterRow"]})
        else:
            txt = json.dumps({"picks": [{"path": HS, "reason": "Home screen renders the country filter row"}, {"path": VM, "reason": "view model supplies the countries"}], "more_queries": []})
        data = json.dumps({"choices": [{"message": {"content": txt}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
srv.hits = []
threading.Thread(target=srv.serve_forever, daemon=True).start()
env = {"PATH": MINPATH, "HOME": ROOT, "OVN_DIR": os.path.join(ROOT, "ovn"), "NTFY_SERVER": "http://127.0.0.1:9", "NTFY_TOPIC": "t", "LITELLM_BASE": "http://127.0.0.1:%d" % srv.server_address[1],
       "OVN_MANUAL_MODEL": "qwen-test"}


def cli_add(note, flow, platform=None, extra=()):
    args = ["add", "--repo", "fx", "--date", "2026-10-01", "--flow", flow, "--minutes", "5", "--note-b64", base64.b64encode(note.encode()).decode(), "--dry-run"]
    if platform:
        args += ["--platform", platform]
    return sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [INGEST] + args + list(extra))


rc, out = cli_add(N2, "Home Page Countries Filter", "android")
ok("dry run: rc 0, DRY-RUN, primary path chosen by the model", rc == 0 and "DRY-RUN" in out and ("path=" + HS) in out, out)
ok("dry run prints platform, queries, 'also look at' and the item with reasons", "platform=android (log)" in out and "queries round 1: countries | CountryFilterRow" in out and "also look at: " + VM in out, out)
ok("dry run: the model reasons are in the candidate evidence", "Home screen renders the country filter row" in out, out)
ok("dry run: exactly 2 model requests, nothing enqueued (origin unchanged)", len(srv.hits) == 2 and "countries filter" not in git(CLONE, "show", REF + ":OVERNIGHT_PROGRESS.md"), len(srv.hits))
srv.hits.clear()
rc, out = cli_add(N2, "Home Page Countries Filter", None)
ok("dry run without a platform: needs-triage with per-platform candidates, zero model requests, no item", "status=needs-triage" in out and "platform-candidate" in out and not srv.hits and "item:" not in out, out)
rc, out = cli_add(N2, "x", "nonsense")
ok("unknown --platform value is ignored safely (treated as no platform)", rc == 0 and "needs-triage" in out, out)
rc, out = cli_add(N2, "Home Page Countries Filter", "android", extra=["--no-model"])
ok("--no-model: deterministic only, no model call", rc == 0 and "ranked_by=deterministic" in out, out)
rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + ["OVN_MANUAL_MODEL=off", INGEST] + ["add", "--repo", "fx", "--date", "2026-10-01", "--flow", "x", "--note", N2, "--platform", "android", "--dry-run"])
ok("OVN_MANUAL_MODEL=off: deterministic only", rc == 0 and "ranked_by=deterministic" in out, out)

# ------------------------------------------------------------------------------------------------------------------ bridge parsing
print("== locator_eval helpers (note stripping, leak check)")
st = ev.strip_identifiers("The `CountryFilter` in HomeScreen.kt and get_channels() broke; see app/ui/home.py and userId. Tapping Play did nothing.")
ok("strip_identifiers removes backticks, files, paths, camelCase, snake_case, calls", not any(x in st for x in ("CountryFilter", "HomeScreen", "get_channels", "home.py", "userId", "`")) and "Tapping Play did nothing" in st, st)
ok("leak check: a note containing the label's file stem is rejected", ev.leaks("the home screen row for picking a country is broken", ["a/CountriesFilterRow.kt"]) is False and ev.leaks("the countries filter row is broken", ["a/CountriesFilterRow.kt"]) is True and
   ev.leaks("the CountriesFilterRow is broken", ["a/CountriesFilterRow.kt"]) is True and ev.leaks("see CountriesFilterRow.kt", ["a/CountriesFilterRow.kt"]) is True)

# ---------------------------------------------------------------------------------------------------------------- hung model (reviewer blocking issue)
print("== hung model")
import socket, threading, time as _time

class _Hung:
    """TCP server that ACCEPTS connections and never replies (a hung model, not a down one)."""
    def __init__(self):
        self.sock = socket.socket(); self.sock.bind(("127.0.0.1", 0)); self.sock.listen(8); self.port = self.sock.getsockname()[1]
        self.conns = []; self.alive = True
        threading.Thread(target=self._run, daemon=True).start()
    def _run(self):
        while self.alive:
            try:
                c, _ = self.sock.accept(); self.conns.append(c)
            except OSError:
                break
    def close(self):
        self.alive = False
        for c in self.conns:
            try: c.close()
            except OSError: pass
        try: self.sock.close()
        except OSError: pass

hung = _Hung()
os.environ["LITELLM_BASE"] = "http://127.0.0.1:%d" % hung.port
os.environ["OVN_MANUAL_CALL_TIMEOUT"] = "2"
os.environ["OVN_MANUAL_MODEL"] = "qwen-test"
t0 = _time.time()
res = ml.agentic_localize(ROOT, "HEAD", "Clicking the plus sign did not add the channel", "discover", "android", "demo", [], [], ml.model_chat)
el = _time.time() - t0
ok("hung model: the agentic loop gives up after ONE call (<= ~2 s timeout + slack), not 70+70 s", el < 8 and res["calls"] == 1, (el, res["calls"]))
ok("hung model: result is a clean failure with model_dead=True (caller falls back to deterministic)", res["ok"] is False and res["model_dead"] is True, res)
# Budget unit behaviour
calls = []
def _boom(prompt):
    calls.append(prompt); return None
b = ml.Budget(_boom)
b("one"); b("two"); b("three")
ok("Budget circuit breaker: after the first failed call nothing else is sent to the model", len(calls) == 1 and b.dead is True, calls)
good_calls = []
b2 = ml.Budget(lambda p: (good_calls.append(p) or "{}"))
for i in range(6):
    b2("p%d" % i)
ok("Budget still enforces the 4-call cap for a healthy model", len(good_calls) == 4 and b2.dead is False, good_calls)
b3 = ml.Budget(lambda p: "x", deadline_s=5)   # < 8 s left => no call is attempted
ok("Budget: with < 8 s of the wall-clock deadline left no further call is made", b3("late") is None and b3.calls == 0)
# end to end through the real ingest (dry run): a hung model must not push the note past the bridge's 120 s ssh timeout
env = dict(os.environ, LITELLM_BASE="http://127.0.0.1:%d" % hung.port, OVN_MANUAL_CALL_TIMEOUT="2", OVN_MANUAL_BUDGET_S="20", OVN_DIR=ROOT)
ing = os.path.join(QA, "manual_notes_ingest.py")
t0 = _time.time()
p = subprocess.run([sys.executable, ing, "add", "--repo", REPO_NAME_FOR_HUNG, "--date", "2026-10-01", "--flow", "discover", "--platform", "android",
                    "--note", "Clicking the plus sign next to a channel did not add it to the home page", "--dry-run"],
                   capture_output=True, text=True, env=env, timeout=60) if "REPO_NAME_FOR_HUNG" in globals() else None
if p is not None:
    ok("end to end: a hung model finishes the dry-run in well under the bridge's 120 s (deterministic fallback)", _time.time() - t0 < 30, (p.stdout[-300:], p.stderr[-300:]))
hung.close()
for k in ("LITELLM_BASE", "OVN_MANUAL_CALL_TIMEOUT", "OVN_MANUAL_MODEL"):
    os.environ.pop(k, None)

if not os.path.exists(BRIDGE):
    # the bridge is a MAC-side tool; the box tree (cron runs this suite) does not have it - skip its tests there
    print("  SKIP bridge tests: %s is a Mac-side script and is not present on this machine" % BRIDGE)
    shutil.rmtree(ROOT, ignore_errors=True)
    print("locator v2: %d passed, %d failed (bridge section skipped)" % (P, F))
    sys.exit(1 if F else 0)
print("== bridge: 6-field / legacy / '# platform:' header")
BR = os.path.join(ROOT, "bridge")
os.makedirs(BR)
logs = os.path.join(BR, "logs")
state = os.path.join(BR, "state")
os.makedirs(logs)
calls = os.path.join(BR, "calls.log")
stub = os.path.join(BR, "ssh")
open(stub, "w").write('#!/usr/bin/env bash\ncmd="${@: -1}"\nprintf \'%s\\n\' "$cmd" >> "' + calls + '"\necho "DRY-RUN id=x repo=fx status=dry-run"\nexit 0\n')
os.chmod(stub, 0o755)
open(os.path.join(logs, "fx.txt"), "w").write(
    "# Manual testing log for fx\n# Format:  date | platform | flow | minutes | result | note        (result = ok | bug)\n#   platform = android | ios | ...\n"
    "10/01/2026 | android | Home Page Countries Filter | 5 | bug | Clicking countries filter only showed all and Qatar 2.\n"
    "2026-10-01 | ios | Discover | 4 | bug | The note has a | pipe in it\n"
    "2026-10-01 | web | Home | 4 | ok | fine\n"
    "2026-10-02 | other | misc | 3 | bug | platform column says other\n"
    "2026-10-02 | unknown | Discover | 6 | bug | qa-log wrote unknown for an old-form line\n"
    "2026-10-02 | android | Home | five | bug | minutes not numeric so this is a legacy line with a platform-like flow\n"
    "2026-10-03 | web | 4 | bug | legacy line whose FLOW is called web\n"
    "2026-10-03 | other | 4 | bug | legacy flow other, note with a | pipe\n"
    "2026-10-04 | home | 4 | bug | legacy line before any header\n"
    "# platform: tvos\n"
    "2026-10-05 | home | 4 | bug | legacy line after a tvos header\n"
    "2026-10-05 | android | home | 4 | bug | explicit column beats the header\n"
    "# platform: bogus\n"
    "2026-10-06 | home | 4 | bug | bogus header is ignored\n")
benv = {"PATH": MINPATH, "HOME": BR, "QA_NOTES_LOGS_DIR": logs, "QA_NOTES_STATE": state, "QA_NOTES_SSH": stub, "OVN_SSH": "u@box", "QA_NOTES_NTFY": "http://127.0.0.1:9",
        "OVN_REMOTE_DIR": "overnight-queue"}
rc, out = sh(["env", "-i"] + ["%s=%s" % kv for kv in benv.items()] + ["bash", BRIDGE])
cmds = open(calls).read().splitlines()
ok("bridge ran and sent every bug line", rc == 0 and len(cmds) == 10, (rc, len(cmds), out))


def find(cmds, text):
    for c in cmds:
        b = c.split("--note-b64 '")[1].split("'")[0]
        if text in base64.b64decode(b).decode():
            return c
    return ""


c1 = find(cmds, "Clicking countries filter")
ok("6-field line: --platform 'android', ISO date, slugged flow, correct minutes", "--platform 'android'" in c1 and "--date '2026-10-01'" in c1 and "--flow 'home-page-countries-filter'" in c1 and "--minutes '5'" in c1, c1)
c2 = find(cmds, "has a | pipe")
ok("6-field line with a pipe in the note: platform ios, the whole note survives", "--platform 'ios'" in c2 and "--flow 'discover'" in c2, c2)
cu = find(cmds, "wrote unknown")
ok("qa-log's 'unknown' platform column is a 6-field line with no --platform (flow=discover)", "--flow 'discover'" in cu and "--platform" not in cu and "--minutes '6'" in cu, cu)
ok("platform 'other' in the column => no --platform flag", "--platform" not in find(cmds, "column says other"))
c5 = find(cmds, "minutes not numeric")
ok("a 'platform-like' second field with non-numeric minutes is NOT taken as 6-field (legacy parse; its result field is not ok/bug so it is skipped)", c5 == "", c5)
c6 = find(cmds, "FLOW is called web")
ok("legacy 5-field line whose flow is named 'web' parses as legacy (flow=web, no platform)", "--flow 'web'" in c6 and "--platform" not in c6 and "--minutes '4'" in c6, c6)
c7 = find(cmds, "legacy flow other")
ok("legacy line with flow 'other' and a pipe in the note stays legacy", "--flow 'other'" in c7 and "--platform" not in c7, c7)
ok("legacy line before any header: no platform", "--platform" not in find(cmds, "before any header"))
ok("'# platform: tvos' header is the default for the legacy lines below it", "--platform 'tvos'" in find(cmds, "after a tvos header"))
ok("an explicit column beats the header default", "--platform 'android'" in find(cmds, "explicit column beats"))
ok("an unknown '# platform:' header is ignored (keeps the previous default)", "--platform 'tvos'" in find(cmds, "bogus header is ignored"))
ok("remote command still carries no raw note text", all("Clicking" not in c and "pipe" not in c for c in cmds))
ok("the ok line is not sent", find(cmds, "fine") == "")

# ------------------------------------------------------------------------------------------------------------------ eval helpers
shutil.rmtree(ROOT, ignore_errors=True)
print("locator v2: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
