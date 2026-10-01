#!/usr/bin/env python3
"""manual_locator.py - locator v2 building blocks for manual_notes_ingest.py (no side effects, no state, no network except the
injected model function).

  * PLATFORM: which part of a multi-platform repo a note is about (android / ios / web / backend / tvos / roku / game ...), mapped to
    path prefixes AUTOMATICALLY from the directory conventions of the tree (`*-android/`, `ios/`, `web/`, `backend/` ...). A tester
    writes the platform in the log; if not, it is inferred from the flow-id prefix (`and-` ...) or the words of the note; if that is
    still ambiguous the caller must triage (never guess).
  * PRODUCT CODE ONLY: e2e/, tests/, androidTest/, UITests/, *.spec.*, fixtures/, mocks/, docs, generated/build output, lockfiles
    are never a target. Tests are supporting evidence at best.
  * AGENTIC LOCALIZATION: a bounded loop of at most MAX_MODEL_CALLS local-model calls (queries -> harness git-grep -> picks, one
    optional extra search round, one repair call). The model never touches the repo; the harness runs the searches and verifies every
    path the model names (exists, in-platform, product code). Anything invented or filtered is discarded. Any model problem => the
    caller falls back to the deterministic result.
"""
import json
import os
import re
import signal
import subprocess
import time
import urllib.request

MAX_MODEL_CALLS = 4
MAX_QUERIES = 8
MAX_QUERIES_ROUND2 = 6
MAX_PICKS = 3
PLATFORM_NAMES = ("android", "ios", "tv", "tvos", "roku", "web", "backend", "game", "desktop", "other")

# ----------------------------------------------------------------------------------------------------------------------
# product-code filter
# ----------------------------------------------------------------------------------------------------------------------
_NON_PRODUCT_DIR = re.compile(
    r"(^|/)(node_modules|\.git|\.github|\.cursor|\.idea|\.vscode|\.gradle|\.godot|\.swiftpm|dist|build|Pods|\.venv|venv|"
    r"htmlcov|coverage|__pycache__|DerivedData|\.next|\.nuxt|vendor|addons|generated|docs?|assets|public|store-assets|"
    r"e2e|e2e-tests?|tests?|__tests__|__mocks__|spec|specs|androidTest|testDebug|fixtures?|mocks?|stubs?|snapshots?|"
    r"test-utils|testutils|alembic/versions|migrations/versions)(/|$)")
_NON_PRODUCT_SEG_SUFFIX = re.compile(r"(Tests?|UITests?|Specs?)$")       # ChickadeeStreamsUITests/, iptv-iosTests/, BillWatchTests/
_NON_PRODUCT_FILE = re.compile(
    r"(\.(spec|test|stories|story)\.[A-Za-z0-9]+$|(^|/)test_[^/]*$|_test\.[A-Za-z0-9]+$|Tests?\.(kt|swift|java|m)$|"
    r"(package-lock|yarn\.lock|pnpm-lock|poetry\.lock|Podfile\.lock|Package\.resolved|gradle\.lockfile)|\.lock$|\.min\.(js|css)$|"
    r"\.d\.ts$|\.snap$|\.import$|OVERNIGHT_|(^|/)conftest\.py$|\.(md|txt|rst|png|jpg|jpeg|gif|svg|webp|ico|mp3|mp4|ttf|otf|woff2?)$|"
    r"tsconfig[^/]*\.json$|(^|/)package\.json$|(^|/)\.env|(^|/)(build|settings)\.gradle(\.kts)?$|\.gradle$)")


def is_product_path(path):
    """True for real product source: never tests, e2e page objects, fixtures, mocks, docs, generated/build output, lockfiles."""
    if _NON_PRODUCT_DIR.search(path) or _NON_PRODUCT_FILE.search(path):
        return False
    return not any(_NON_PRODUCT_SEG_SUFFIX.search(seg) for seg in path.split("/")[:-1])


# ----------------------------------------------------------------------------------------------------------------------
# platform layout (from directory conventions)
# ----------------------------------------------------------------------------------------------------------------------
_SEG_TOKENS = {"android": "android", "ios": "ios", "tvos": "tvos", "roku": "roku", "web": "web", "frontend": "web", "website": "web",
               "webapp": "web", "backend": "backend", "server": "backend", "api": "backend", "desktop": "desktop",
               "electron": "desktop"}
CLIENTS = {"android", "ios", "tv", "tvos", "roku", "web", "desktop"}


def _seg_platform(seg):
    toks = [t for t in re.split(r"[-_. ]+", seg.lower()) if t]
    for t in toks:
        if t in _SEG_TOKENS:
            return _SEG_TOKENS[t]
    return None


def detect_layout(files):
    """-> {prefix_with_slash: platform}. Top-level dirs named by convention (`iptv-android/`, `web/`, `backend/`), nested tv targets
    (`iptv-ios/ChickadeeStreamsTV/` -> tvos), godot repos (project.godot: scripts/ + scenes/ -> game). {} for a single-platform repo."""
    lay = {}
    tops = sorted({f.split("/")[0] for f in files if "/" in f})
    for top in tops:
        p = _seg_platform(top)
        if p:
            lay[top + "/"] = p
    for top in list(lay):
        if lay[top] != "ios":
            continue
        for sub in sorted({f.split("/")[1] for f in files if f.startswith(top) and f.count("/") >= 2}):
            if re.search(r"(?i)(tvos|[a-z0-9]TV)$", sub) and not _NON_PRODUCT_SEG_SUFFIX.search(sub):
                lay["%s%s/" % (top, sub)] = "tvos"
    if "project.godot" in files and not lay:
        lay.update({"scripts/": "game", "scenes/": "game"})
    return lay


def plat_of(path, layout):
    best, plat = -1, None
    for pre, p in layout.items():
        if path.startswith(pre) and len(pre) > best:
            best, plat = len(pre), p
    return plat


def platforms_for(platform, layout):
    """Set of layout platforms a logged platform covers in THIS repo (empty => the repo has no such part)."""
    have = set(layout.values())
    want = {"tv": {"tv", "tvos", "roku", "android"}}.get(platform, {platform})
    return want & have


def candidates_for_platform(files, layout, platform):
    """Product files restricted to the platform (+ the backend files that may only be an 'also look at'). -> (primary_set, also_set)."""
    plats = platforms_for(platform, layout)
    prim = {f for f in files if plat_of(f, layout) in plats}
    also = set(prim)
    if platform in CLIENTS:
        also |= {f for f in files if plat_of(f, layout) == "backend"}
    return prim, also


# ----------------------------------------------------------------------------------------------------------------------
# platform resolution
# ----------------------------------------------------------------------------------------------------------------------
PLAN_PREFIX = {"and": "android", "ios": "ios", "tvos": "tvos", "tv": "tv", "web": "web", "api": "backend", "roku": "roku",
               "site": "web"}
_WORDS = {"android": ("android", "kotlin", "logcat", "apk", "gradle"), "ios": ("ios", "iphone", "ipad", "swift", "xcode", "testflight"),
          "web": ("browser", "chrome", "firefox", "website", "webpage", "localhost", "url"),
          "backend": ("endpoint", "backend", "server", "api", "database", "500", "migration"),
          "tvos": ("tvos",), "roku": ("roku",), "game": ("godot", "gdscript"),
          "tv": ("firestick", "dpad", "d-pad", "leanback")}


def normalize_platform(p):
    p = (p or "").strip().lower()
    return p if p in PLATFORM_NAMES and p != "other" else ""


def infer_platform(flow, note):
    """-> (platform|'' , source). Explicit evidence only: a flow-id prefix from docs/test-plans (`and-paywall`) or words of the flow /
    note that point at exactly ONE platform. Anything ambiguous returns '' (the caller triages, it never guesses)."""
    m = re.match(r"^([a-z]+)-", (flow or "").strip().lower())
    if m and m.group(1) in PLAN_PREFIX:
        return PLAN_PREFIX[m.group(1)], "flow-id-prefix"
    text = (str(flow or "") + " " + str(note or "")).lower()
    text = re.sub(r"android tv|fire ?tv|apple tv", " tvhw ", text)
    toks = set(re.findall(r"[a-z0-9][a-z0-9-]*", text))
    found = set()
    for plat, ws in _WORDS.items():
        if any(w in toks for w in ws):
            found.add(plat)
    if "tvhw" in toks:
        found.add("tv")
    if len(found) == 1:
        return found.pop(), "inferred-from-words"
    return "", "ambiguous" if found else "none"


# ----------------------------------------------------------------------------------------------------------------------
# repo map
# ----------------------------------------------------------------------------------------------------------------------
ROLE = re.compile(r"(Screen|Activity|Fragment|View|ViewModel|Page|Route|Router|Routes|Controller|Service|Repository|Store|Manager|"
                  r"Adapter|Component|Composable|Dialog|Worker|Dao|Api|Client|Provider|Presenter|Cell|Row|Card|Sheet|Model|Models|"
                  r"Handler|Helper|Util|Utils|Config)\b|\.(vue|tsx|jsx)$|(^|/)(routers?|routes|api|endpoints|services|screens|views|"
                  r"pages|components|viewmodels|ui)/", re.I)
_ROLE_W = (("Screen", 1.0), ("Activity", .9), ("Fragment", .9), ("ViewModel", 1.0), ("View", .8), ("Page", .8), ("Route", .9),
           ("Router", 1.0), ("Controller", .9), ("Service", .9), ("Repository", .9), ("Store", .8), ("Manager", .7), ("Adapter", .6),
           ("Component", .6), ("Dialog", .5), ("Client", .6), ("Model", .5), ("Api", .8))


def role_weight(path):
    base = os.path.basename(path).rsplit(".", 1)[0]
    w = 0.0
    for k, v in _ROLE_W:
        if k.lower() in base.lower():
            w = max(w, v)
    if re.search(r"(^|/)(routers?|routes|api|endpoints|services|screens|views|pages|viewmodels)/", path, re.I):
        w = max(w, 0.6)
    return w


def repo_map(paths, cap=6500):
    """Compact map: directory -> file names. Full detail when it fits, role files only (screens/views/routes/viewmodels/services)
    when it does not."""
    def render(names_by_dir, per_dir):
        out = []
        for d in sorted(names_by_dir):
            names = names_by_dir[d]
            shown = names[:per_dir]
            more = len(names) - len(shown)
            out.append("%s/: %s%s" % (d, ", ".join(shown), (" (+%d more)" % more) if more > 0 else ""))
        return "\n".join(out)
    by_dir = {}
    for p in sorted(paths):
        d, _, n = p.rpartition("/")
        by_dir.setdefault(d, []).append(n)
    txt = render(by_dir, 60)
    if len(txt) <= cap:
        return txt
    role_dir = {}
    for p in sorted(paths):
        if ROLE.search(p):
            d, _, n = p.rpartition("/")
            role_dir.setdefault(d, []).append(n)
    for per in (40, 20, 10, 5):
        txt = render(role_dir, per)
        if len(txt) <= cap:
            return txt
    return txt[:cap]


# ----------------------------------------------------------------------------------------------------------------------
# harness searches
# ----------------------------------------------------------------------------------------------------------------------

def _git(repo, args, timeout=30):
    env = dict(os.environ)
    env["GIT_TERMINAL_PROMPT"] = "0"
    try:
        p = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, timeout=timeout, env=env)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return 124, ""


def clean_queries(raw, limit):
    """Model output -> [(query, is_regex)] (<= limit, deduped, sane lengths). Accepts strings or {"q":..,"regex":bool}."""
    out, seen = [], set()
    if not isinstance(raw, list):
        return out
    for it in raw:
        rx = False
        if isinstance(it, dict):
            rx = bool(it.get("regex"))
            it = it.get("q") or it.get("query") or ""
        if not isinstance(it, str):
            continue
        q = re.sub(r"[\x00-\x1f]", " ", it).strip().strip("`'\"")
        if not (3 <= len(q) <= 80) or q.lower() in seen:
            continue
        if re.fullmatch(r"[\W_]+", q) or re.fullmatch(r"[.*+?\\]+", q):
            continue
        seen.add(q.lower())
        out.append((q, rx))
        if len(out) >= limit:
            break
    return out


def run_queries(repo, ref, queries, prefixes, allowed, max_per_file=3, timeout=25):
    """Run each query with git grep -n -I -i on the platform prefixes. -> {qi: {path: [(line_no, text)]}} (allowed paths only)."""
    res = {}
    specs = sorted(prefixes) or ["."]
    for qi, (q, rx) in enumerate(queries):
        hits = {}
        out = ""
        for mode in (["-E", "-F"] if rx else ["-F"]):
            rc, o = _git(repo, ["grep", "-n", "-I", "-i", mode, "-m", str(max_per_file), "-e", q, ref, "--"] + specs, timeout=timeout)
            if rc in (0, 1):
                out = o
                break
            if rc != 2:
                break               # timeout: nothing from this query; the deterministic fallback covers it
        pre = ref + ":"
        for ln in out.splitlines()[:600]:
            if not ln.startswith(pre):
                continue
            m = re.match(r"(.+?):(\d+):(.*)$", ln[len(pre):])
            if m and m.group(1) in allowed:
                hits.setdefault(m.group(1), []).append((int(m.group(2)), m.group(3).strip()[:160]))
        res[qi] = hits
    return res


def rank_hits(res, queries, resource_users=None):
    """Rank files by DISTINCT-query hits (discriminative queries count more) + file role. -> [(score, path, [qi...])]"""
    per = {}
    for qi, hits in res.items():
        n = len(hits)
        if n == 0:
            continue
        w = 1.0 if n <= 8 else (0.6 if n <= 25 else (0.25 if n <= 60 else 0.08))
        for p in hits:
            per.setdefault(p, {})[qi] = w
    for p, qis in (resource_users or {}).items():          # code files that use a label found in a resource file
        for qi, w in qis.items():
            per.setdefault(p, {})[qi] = max(per.get(p, {}).get(qi, 0), w)
    ranked = []
    for p, qw in per.items():
        base = sum(qw.values())
        name = os.path.basename(p).lower().replace("_", "").replace("-", "")
        nb = 0.0
        for qi in qw:
            qt = re.sub(r"[^a-z0-9]", "", queries[qi][0].lower())
            if len(qt) >= 4 and qt in name:
                nb = 0.8
        rb = role_weight(p) * 0.6
        if re.search(r"(strings\.xml|\.strings$|locales?/|i18n/)", p, re.I):
            base *= 0.4
        ranked.append((round(base + nb + rb, 3), p, sorted(qw)))
    ranked.sort(key=lambda t: (-t[0], t[1]))
    return ranked


_RESOURCE = re.compile(r"(^|/)(strings\.xml|[^/]*\.strings|locales?/[^/]+\.json|i18n/[^/]+\.json|messages/[^/]+\.json)$", re.I)


def _label_key(path, text):
    if path.endswith(".xml"):
        m = re.search(r'<string\s+name="([A-Za-z0-9_.]+)"', text)
    elif path.endswith(".strings"):
        m = re.match(r'"([^"]+)"\s*=', text)
    else:
        m = re.match(r'"([A-Za-z0-9_.\-]+)"\s*:', text)
    return m.group(1) if m else None


def resource_users(repo, ref, res, allowed, prefixes, max_keys=4):
    """A query that hit a UI-label resource (strings.xml ...) counts for the CODE that uses the label key. -> {path: {qi: weight}}"""
    users, keys = {}, 0
    for qi, hits in res.items():
        for p, hl in hits.items():
            if not _RESOURCE.search(p) or keys >= max_keys:
                continue
            k = _label_key(p, hl[0][1]) if hl else None
            if not k or len(k) < 4:
                continue
            keys += 1
            for cp, cl in run_queries(repo, ref, [(k, False)], prefixes, allowed, max_per_file=1)[0].items():
                if not _RESOURCE.search(cp):
                    users.setdefault(cp, {})[qi] = 0.9
    return users


def snippet(repo, ref, path, line_no, ctx=2, width=150):
    rc, out = _git(repo, ["show", "%s:%s" % (ref, path)], timeout=20)
    if rc != 0:
        return ""
    lines = out.splitlines()
    a, b = max(0, line_no - 1 - ctx), min(len(lines), line_no + ctx)
    return "\n".join("      %d: %s" % (i + 1, lines[i].strip()[:width]) for i in range(a, b))


# ----------------------------------------------------------------------------------------------------------------------
# model plumbing
# ----------------------------------------------------------------------------------------------------------------------
class _Alarm(Exception):
    pass


def _on_alarm(_s, _f):
    raise _Alarm()


def model_name():
    return os.environ.get("OVN_MANUAL_MODEL", "qwen-dflash-27B")


def model_chat(prompt, timeout=70, max_tokens=700):
    """One request to the local litellm. -> text or None on ANY problem. (Used for exactly one request at a time.)"""
    name = model_name()
    if name in ("", "off", "none"):
        return None
    try:   # hard per-call cap (a HUNG model - accepts the connection, never replies - must not eat the bridge's 120 s ssh budget)
        timeout = max(2, min(int(timeout), int(os.environ.get("OVN_MANUAL_CALL_TIMEOUT", "60"))))
    except ValueError:
        timeout = 60
    base = os.environ.get("LITELLM_BASE", "http://localhost:4000").rstrip("/")
    key = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")
    body = json.dumps({"model": name, "messages": [{"role": "user", "content": prompt}], "temperature": 0.2,
                       "max_tokens": max_tokens}).encode()
    req = urllib.request.Request(base + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    old = None
    try:
        try:
            old = signal.signal(signal.SIGALRM, _on_alarm)
            signal.alarm(timeout + 15)
        except ValueError:
            old = None
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(1 << 20).decode("utf-8", "replace")
        content = json.loads(raw)["choices"][0]["message"]["content"] or ""
        return re.sub(r"(?s)<think>.*?</think>", "", content)
    except Exception:  # noqa: BLE001 - timeout, refused, HTTP error, bad JSON => caller falls back
        return None
    finally:
        try:
            signal.alarm(0)
            if old is not None:
                signal.signal(signal.SIGALRM, old)
        except Exception:  # noqa: BLE001
            pass


def parse_json_obj(text):
    if not text:
        return None
    for m in re.finditer(r"\{", text):
        depth, i = 0, m.start()
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        d = json.loads(text[i:j + 1])
                        return d if isinstance(d, dict) else None
                    except ValueError:
                        break
        # try the next '{'
    return None


class Budget:
    """Hard cap on model calls for one localization (the contract says 4), a wall-clock deadline for the WHOLE localization, and a circuit
    breaker: the first failed/hung call (None) marks the model dead for this localization, so nothing waits on it a second time.
    2026-10-01 (reviewer): a hung model made one note take 170 s (70 s call + 70 s tie-break + greps); qa-notes-bridge kills ssh at 120 s, so the
    note was never enqueued and was retried forever."""

    def __init__(self, fn, limit=MAX_MODEL_CALLS, deadline_s=None):
        self.fn, self.limit, self.calls = fn, limit, 0
        self.dead = False
        try:
            self.deadline_s = float(os.environ.get("OVN_MANUAL_BUDGET_S", "90")) if deadline_s is None else float(deadline_s)
        except ValueError:
            self.deadline_s = 90.0
        self.t0 = time.time()

    def remaining(self):
        return self.deadline_s - (time.time() - self.t0)

    def __call__(self, prompt):
        if self.dead or self.calls >= self.limit or self.remaining() < 8:
            return None
        self.calls += 1
        try:
            if self.fn is model_chat:
                res = self.fn(prompt, timeout=int(max(2, min(60, self.remaining() - 5))))
            else:
                res = self.fn(prompt)
        except Exception:  # noqa: BLE001
            res = None
        if res is None:
            self.dead = True
        return res


# ----------------------------------------------------------------------------------------------------------------------
# the agentic loop
# ----------------------------------------------------------------------------------------------------------------------
def _p_queries(note, flow, platform, repo, map_txt):
    return (
        "You help find the source code behind a bug that a human tester reported. The tester does not know code names.\n"
        "App: %s, platform: %s\nScreen/flow label: %s\nTester note: \"%s\"\n\n"
        "Repository map for the %s code (directory: file names):\n%s\n\n"
        "Propose up to %d search queries that a case-insensitive git grep over this code could use to find the code responsible. Mix:\n"
        "1. literal UI text the user sees (button / title / label as it would appear in code or string resources),\n"
        "2. likely identifiers in the naming style of the map above (class, function, variable, route names),\n"
        "3. concept synonyms (e.g. filter/country/region, live/movie/stream type, DVR/record/download, add/favorite/watchlist).\n"
        "Each query must be SHORT: one to three words, one identifier, or a short regex. Never a sentence.\n"
        "Reply with ONLY JSON: {\"queries\": [{\"q\": \"...\", \"regex\": false}]}" % (repo, platform, flow, note, platform, map_txt, MAX_QUERIES))


def _hits_block(repo, ref, ranked, queries, res, prim, also_only, nprim=10, nback=4):
    lines = ["FILES (the ONLY paths you may answer with):"]
    shown = 0
    back = 0
    for sc, p, qis in ranked:
        is_back = p not in prim
        if is_back:
            if back >= nback:
                continue
            back += 1
        else:
            if shown >= nprim:
                continue
            shown += 1
        qs = ", ".join('"%s"' % queries[i][0] for i in qis[:4])
        lines.append("- %s%s  [matched: %s]" % (p, "  (server-side: may only be an 'also look at')" if is_back else "", qs))
        n = 0
        for qi in qis:
            for ln_no, _t in res.get(qi, {}).get(p, [])[:1]:
                if n < 2:
                    sn = snippet(repo, ref, p, ln_no)
                    if sn:
                        lines.append(sn)
                        n += 1
    if len(lines) == 1:
        lines.append("(no search matched anything)")
    return "\n".join(lines)


def _p_picks(note, flow, platform, queries, block, allow_more):
    more = ("If the matches are not enough you may ask for ONE more search round with up to %d NEW queries in \"more_queries\"; "
            "otherwise leave it []. " % MAX_QUERIES_ROUND2) if allow_more else "This is the final answer round: \"more_queries\" must be []. "
    return (
        "A human tester of a %s app reported: \"%s\" (screen/flow: %s).\n"
        "Searches that were run: %s\n\n%s\n\n"
        "Pick up to %d files, most likely first. The FIRST is the primary file where the fix most likely belongs; the others are files "
        "that must also be looked at (a bug can span a screen and its viewmodel/service/server code). Use paths exactly as printed under "
        "FILES. Give a reason of at most 20 words for each. %s\n"
        "Reply with ONLY JSON: {\"picks\": [{\"path\": \"...\", \"reason\": \"...\"}], \"more_queries\": []}"
        % (platform, note, flow, ", ".join('"%s"' % q for q, _ in queries), block, MAX_PICKS, more))


def _validate_picks(raw, prim, also, base_index):
    """-> (primary_pick|None, also_picks[], discarded[]). Every path must exist (be in the allowed set); a path that is not an exact
    match but whose file name is unique in the allowed set is resolved (it exists); anything else is discarded."""
    valid, discarded = [], []
    if not isinstance(raw, list):
        return None, [], []
    for it in raw[:6]:
        if not isinstance(it, dict):
            continue
        p = it.get("path")
        reason = re.sub(r"\s+", " ", str(it.get("reason") or ""))[:200]
        if not isinstance(p, str):
            continue
        p = p.strip().strip("`'\"")
        if p.startswith("./"):
            p = p[2:]
        if p not in also:
            alt = base_index.get(os.path.basename(p).lower(), [])
            if len(alt) == 1 and ("/" not in p or alt[0].endswith("/" + p.lstrip("/"))):
                p = alt[0]              # an exact existing file named by its file name only (not invented)
        if p in also and is_product_path(p):
            if p not in [v[0] for v in valid]:
                valid.append((p, reason))
        else:
            discarded.append(str(it.get("path"))[:120])
    primary = next(((p, r) for p, r in valid if p in prim), None)
    extra = [(p, r) for p, r in valid if primary is None or p != primary[0]]
    return primary, extra[:MAX_PICKS - 1], discarded


def agentic_localize(repo, ref, note, flow, platform, repo_name, prim, also, model_fn, prefixes=None, seed_hits=None):
    """Run the bounded loop. `prim` = in-platform product files (primary targets), `also` = prim + server files (also-look-at only).
    -> {ok, primary:(path,reason)|None, also:[(path,reason)], queries:[[...]], calls, discarded:[], grep_ranked:[(path,score)], error}
    `model_fn(prompt) -> text|None` (wrapped in the 4-call budget here). Never raises."""
    out = {"ok": False, "primary": None, "also": [], "queries": [], "calls": 0, "discarded": [], "grep_ranked": [], "error": "", "model_dead": False}
    budget = Budget(model_fn)
    try:
        base_index = {}
        for f in also:
            base_index.setdefault(os.path.basename(f).lower(), []).append(f)
        prefixes = list(prefixes) if prefixes else ["."]
        map_txt = repo_map(prim)
        # (a) queries
        d = parse_json_obj(budget(_p_queries(note, flow, platform, repo_name, map_txt)))
        qs = clean_queries((d or {}).get("queries"), MAX_QUERIES)
        out["calls"] = budget.calls; out["model_dead"] = budget.dead
        if not qs:
            out["error"] = "model returned no usable queries"
            return out
        out["queries"].append([q for q, _ in qs])
        # (b) harness runs them
        res = run_queries(repo, ref, qs, prefixes, also)
        if seed_hits:                      # what the keyword locator already found counts as one more (pseudo) query
            qs = qs + [("(keyword locator)", False)]
            res[len(qs) - 1] = {p: [(ln, tx)] for p, (ln, tx) in seed_hits.items() if p in also}
        ranked = rank_hits(res, qs, resource_users(repo, ref, res, also, prefixes))
        out["grep_ranked"] = [(p, s) for s, p, _ in ranked[:8]]
        block = _hits_block(repo, ref, ranked, qs, res, prim, also)
        # (c) picks (+ at most ONE more search round)
        d = parse_json_obj(budget(_p_picks(note, flow, platform, qs, block, True)))
        out["calls"] = budget.calls; out["model_dead"] = budget.dead
        if d is None:
            out["error"] = "model returned no usable picks"
            return out
        more = clean_queries(d.get("more_queries"), MAX_QUERIES_ROUND2) if budget.calls < budget.limit else []
        if more:
            out["queries"].append([q for q, _ in more])
            allq = qs + more
            res2 = run_queries(repo, ref, more, prefixes, also)
            res.update({len(qs) + i: h for i, h in res2.items()})
            ranked = rank_hits(res, allq, resource_users(repo, ref, res, also, prefixes))
            out["grep_ranked"] = [(p, s) for s, p, _ in ranked[:8]]
            block = _hits_block(repo, ref, ranked, allq, res, prim, also)
            d = parse_json_obj(budget(_p_picks(note, flow, platform, allq, block, False)))
            out["calls"] = budget.calls; out["model_dead"] = budget.dead
            qs = allq
            if d is None:
                out["error"] = "model returned no usable picks (round 2)"
                return out
        primary, extra, disc = _validate_picks(d.get("picks"), prim, also, base_index)
        out["discarded"] += disc
        if primary is None and not extra and budget.calls < budget.limit:
            # (d) repair call: everything it named was invented or filtered
            d = parse_json_obj(budget(_p_picks(note, flow, platform, qs, block + "\nYour previous answer named paths that are not in FILES; "
                                               "choose ONLY from FILES.", False)))
            out["calls"] = budget.calls; out["model_dead"] = budget.dead
            primary, extra, disc = _validate_picks((d or {}).get("picks"), prim, also, base_index)
            out["discarded"] += disc
        out["calls"] = budget.calls; out["model_dead"] = budget.dead
        if primary is None and not extra:
            out["error"] = "no valid pick (discarded: %d)" % len(out["discarded"])
            return out
        out["ok"] = True
        out["primary"], out["also"] = primary, extra
        return out
    except Exception as ex:  # noqa: BLE001
        out["error"] = "agentic error: %s" % type(ex).__name__
        out["calls"] = budget.calls; out["model_dead"] = budget.dead
        return out
