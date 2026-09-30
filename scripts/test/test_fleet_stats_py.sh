#!/usr/bin/env bash
# Exercises the REAL fleet_stats.py. The module derives every path from its own location, so instead of copying it (which would
# hide it from coverage) the driver imports it from its real path and re-points the path constants at a throwaway tree; a final
# exec pass runs it as __main__ with os.path.abspath remapped so SCRIPT_DIR is the fake tree. git/docker are a real
# throwaway repo + a stub docker on PATH. Nothing outside the temp dir is read or written.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FS=""
for c in "$HERE/../../fleet_stats.py" "$HERE/../fleet_stats.py" "$HERE/fleet_stats.py"; do [ -f "$c" ] && { FS="$(cd "$(dirname "$c")" && pwd)/$(basename "$c")"; break; }; done
[ -n "$FS" ] || { echo "  SKIP: fleet_stats.py not found"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/docker" <<'EOF'
#!/usr/bin/env bash
# docker logs <container> --since 24h
case "$2" in
  fake-llama)   [ -f "$DOCKER_LLAMA_EMPTY" ] && exit 0
                echo "slot 0: total time = 1234.5 ms / 150 tokens"; echo "noise"; echo "total time =   10.0 ms /   50 tokens"
                echo "truncated = 1"; echo "truncated = 0"; echo "truncated = 12";;
  fake-litellm) [ -f "$DOCKER_LITELLM_EMPTY" ] && exit 0
                echo '"POST /v1/chat/completions HTTP/1.1" 200'; echo '"POST /v1/chat/completions HTTP/1.1" 200'; echo '"GET /health" 200';;
esac
exit 0
EOF
chmod +x "$T/bin/docker"
export PATH="$T/bin:$PATH" DOCKER_LLAMA_EMPTY="$T/llama_empty" DOCKER_LITELLM_EMPTY="$T/litellm_empty" LLAMA_CONTAINER=fake-llama LITELLM_CONTAINER=fake-litellm
export FS T
python3 - <<'PY'
import importlib.util, json, os, subprocess, sys, time

FS, T = os.environ["FS"], os.environ["T"]
P = F = 0
def check(label, cond):
    global P, F
    if cond: P += 1; print("  ok   " + label)
    else: F += 1; print("  FAIL " + label)

def git(cwd, *a):
    return subprocess.run(["git", "-C", cwd, "-c", "user.email=t@t", "-c", "user.name=t", *a], capture_output=True, text=True)

spec = importlib.util.spec_from_file_location("fleet_stats_under_test", FS)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
tree = os.path.join(T, "tree"); state = os.path.join(tree, "state"); repos = os.path.join(tree, "repos")
os.makedirs(state); os.makedirs(repos)
m.STATE_DIR, m.REPOS_DIR = state, repos
m.TASKS_FILE = os.path.join(tree, "tasks.json"); m.TASK_STATS_LOG = os.path.join(state, "task_stats.log"); m.OUT_FILE = os.path.join(state, "fleet_stats.json")
now = time.time()

# ---- sh ----
check("sh returns stdout", m.sh("echo hi").strip() == "hi")
check("sh returns '' on failure to spawn (bad cwd)", m.sh("echo hi", cwd="/nonexistent-dir-xyz") == "")
check("sh returns '' on timeout", m.sh("sleep 5", timeout=0.2) == "")

# ---- enabled_repos ----
check("enabled_repos: missing tasks.json -> []", m.enabled_repos() == [])
open(m.TASKS_FILE, "w").write("not json")
check("enabled_repos: malformed tasks.json -> []", m.enabled_repos() == [])
json.dump([
    {"id": "t1", "repo": "/x/repos/alpha"},
    {"id": "t2", "repo": "/x/repos/alpha/"},                  # dup of alpha (trailing slash)
    {"id": "t3", "repo": "/x/repos/beta", "enabled": False},  # disabled
    {"id": "t4", "repo": "/x/repos/iptv_apps", "enabled": True},
    {"id": "t5", "repo": ""},                                 # blank repo
    {"repo": "/x/repos/gamma"},                               # no id -> falls back to dirname
], open(m.TASKS_FILE, "w"))
check("enabled_repos: dedupes by dir, skips disabled/blank, id fallback",
      m.enabled_repos() == [("t1", "alpha"), ("t4", "iptv_apps"), ("gamma", "gamma")])

# ---- queue_counts ----
check("queue_counts: missing file -> (None, None)", m.queue_counts(os.path.join(repos, "nope")) == (None, None))
os.makedirs(os.path.join(repos, "alpha"))
open(os.path.join(repos, "alpha", "OVERNIGHT_PROGRESS.md"), "w").write(
    "- [x] done 1\n- [x] done 2\n- [ ] real a\n- [ ] real b\n- [ ] HUMAN-ONLY c\n- [ ] see human/ dir\n- [ ] AUTO-SKIP d\n"
    "- [ ] BLOCKED ITEM e\n- [ ] retired-x\n  - [ ] indented not counted\nprose\n")
check("queue_counts: done/doable with all exclusion markers", m.queue_counts(os.path.join(repos, "alpha")) == (2, 2))

# ---- git_unpromoted ----
origin = os.path.join(T, "origin.git"); subprocess.run(["git", "init", "-q", "--bare", origin])
work = os.path.join(repos, "alpha")
git(work, "init", "-q", "-b", "main"); git(work, "add", "-A"); git(work, "commit", "-q", "-m", "base")
git(work, "remote", "add", "origin", origin); git(work, "push", "-q", "origin", "main")
git(work, "checkout", "-q", "-b", "develop"); [git(work, "commit", "-q", "--allow-empty", "-m", "d%d" % i) for i in range(3)]
git(work, "push", "-q", "origin", "develop")
check("git_unpromoted counts develop-only commits", m.git_unpromoted(work) == 3)
check("git_unpromoted on a non-repo -> None", m.git_unpromoted(os.path.join(T, "bin")) is None)

# ---- load_task_stats ----
def line(ts, repo, oc, tag, f="a.py"): return "%s\t%s\t%s\t%s\t%s\n" % (ts, repo, oc, tag, f)
c1, c7 = now - 86400, now - 7 * 86400
check("load_task_stats: missing log -> empty maps", m.load_task_stats(c1, c7) == ({}, {}) or (dict(m.load_task_stats(c1, c7)[0]) == {} and dict(m.load_task_stats(c1, c7)[1]) == {}))
with open(m.TASK_STATS_LOG, "w") as f:
    f.write(line(now - 60, "alpha", "pass", "{py.fix.s.t}"))                 # 1d + 7d
    f.write(line(now - 60, "alpha", "pass", "{py·feat·s·t}"))                # middle-dot separators
    f.write(line(now - 2 * 86400, "alpha", "revert", "{vue.fix.s.t}"))       # 7d only
    f.write(line(now - 3 * 86400, "alpha", "noop", "garbled-tag"))           # tag not matching -> lang '?'
    f.write(line(now - 30 * 86400, "alpha", "pass", "{py.fix.s.t}"))         # too old
    f.write("too\tfew\tcolumns\n")                                           # <5 columns
    f.write(line("not-a-number", "alpha", "pass", "{py.fix.s.t}"))           # bad ts
    f.write(line(now - 60, "iptv-apps", "pass", "{ts.fix.s.t}"))
by7, by1 = m.load_task_stats(c1, c7)
check("load_task_stats: 7d bucket has 4 alpha rows", len(by7["alpha"]) == 4)
check("load_task_stats: 1d bucket has only the 2 fresh alpha rows", len(by1["alpha"]) == 2)
check("load_task_stats: unparsable tag degrades to lang/typ '?'", any(r["lang"] == "?" and r["typ"] == "?" for r in by7["alpha"]))
check("load_task_stats: middle-dot tags parse", any(r["lang"] == "py" and r["typ"] == "feat" for r in by7["alpha"]))

# ---- pass_rate / by_category ----
rows = by7["alpha"]
check("pass_rate delegates to the canonical summarize()", m.pass_rate(rows) == m.summarize(rows)["pass_rate"])
cats = m.by_category([{"oc": "pass", "lang": "py"}, {"oc": "revert", "lang": "py"}, {"oc": "skip", "lang": "go"}, {"oc": "pass", "lang": "vue"}])
check("by_category: benign rows excluded, rates rounded", cats == {"py": {"landed": 1, "attempted": 2, "pass_rate": 50.0}, "vue": {"landed": 1, "attempted": 1, "pass_rate": 100.0}})
check("by_category: empty -> {}", m.by_category([]) == {})

# ---- docker-derived stats ----
check("llama_token_stats sums 'total time = .. / N tokens' and counts truncated>0", m.llama_token_stats("24h") == (200, 2))
open(os.environ["DOCKER_LLAMA_EMPTY"], "w").close()
check("llama_token_stats: no docker output -> (None, None)", m.llama_token_stats("24h") == (None, None))
check("litellm_request_count counts POST /v1/chat/completions lines", m.litellm_request_count("24h") == 2)
open(os.environ["DOCKER_LITELLM_EMPTY"], "w").close()
check("litellm_request_count: no output -> None", m.litellm_request_count("24h") is None)
os.remove(os.environ["DOCKER_LLAMA_EMPTY"]); os.remove(os.environ["DOCKER_LITELLM_EMPTY"])

# ---- main() via import ----
os.makedirs(os.path.join(repos, "iptv_apps"))
open(os.path.join(repos, "iptv_apps", "OVERNIGHT_PROGRESS.md"), "w").write("- [ ] only one\n")
m.main()
out = json.load(open(m.OUT_FILE))
check("main: wrote atomically (no .tmp left)", not os.path.exists(m.OUT_FILE + ".tmp"))
check("main: repos with no clone dir (gamma) are skipped", sorted(out["repos"]) == ["alpha", "iptv_apps"])
a = out["repos"]["alpha"]
check("main: alpha counters", a["task_id"] == "t1" and a["done"] == 2 and a["doable"] == 2 and a["landed_1d"] == 2 and a["landed_7d"] == 2 and a["unpromoted"] == 3)
check("main: runway_days = doable / (landed_7d/7)", a["runway_days"] == round(2 / (2 / 7.0), 1))
check("main: pass_rate_7d + breakdown keys present", "pass_rate_7d" in a and "wasted_attempts_7d" in a and "benign_excluded_7d_breakdown" in a and "by_category_7d" in a)
ip = out["repos"]["iptv_apps"]
check("main: REPO_LOG_NAME maps iptv_apps -> iptv-apps log rows", ip["landed_7d"] == 1 and ip["done"] == 0 and ip["doable"] == 1)
check("main: fleet block filled from docker stubs", out["fleet"] == {"llama_requests_today": 2, "tokens_today": 200, "context_overflow_today": 2})
check("main: generated_at is an ISO-Z timestamp", out["generated_at"].endswith("Z") and len(out["generated_at"]) == 20)

# runway None when nothing landed; progress file missing -> done/doable None
open(m.TASK_STATS_LOG, "w").close()
os.remove(os.path.join(repos, "iptv_apps", "OVERNIGHT_PROGRESS.md"))
m.main(); out = json.load(open(m.OUT_FILE))
check("main: zero landings -> runway_days null", out["repos"]["alpha"]["runway_days"] is None)
check("main: missing progress file -> done/doable null and runway null", out["repos"]["iptv_apps"]["doable"] is None and out["repos"]["iptv_apps"]["runway_days"] is None)

# ---- __main__ pass: remap abspath so SCRIPT_DIR is the fake tree, then execute the file as a script ----
real_abspath = os.path.abspath
os.makedirs(os.path.join(tree, "scripts"), exist_ok=True)
def fake_abspath(p):
    return os.path.join(tree, "fleet_stats.py") if p == FS else real_abspath(p)
os.path.abspath = fake_abspath
try:
    try:
        exec(compile(open(FS).read(), FS, "exec"), {"__name__": "__main__", "__file__": FS})
        code = "no-exit"
    except SystemExit as e:
        code = e.code
finally:
    os.path.abspath = real_abspath
check("__main__: exits 0", code == 0)
check("__main__: wrote its output file under the fake SCRIPT_DIR", os.path.exists(os.path.join(tree, "state", "fleet_stats.json")))

print("fleet_stats_py: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
PY
