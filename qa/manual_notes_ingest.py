#!/usr/bin/env python3
"""manual_notes_ingest.py - turn Mark's manual-testing 'bug' notes into real, landable fleet queue items.

Box side of the manual-notes loop (the Mac side is scripts/qa-notes-bridge.sh). Subcommands:

  add    --repo R --date D --flow F --minutes M [--platform P] (--note-b64 B64 | --note TEXT) [--no-model] [--dry-run]
         sanitize -> dedupe -> LOCATE the code (locator v2: platform -> product-code-only -> deterministic git-grep locator -> on a weak or
         ambiguous result a bounded agentic loop with the local Qwen, <= 4 calls, every path it names verified by the harness; see
         manual_locator.py) -> enqueue ONE item at the
         top of '## Next Steps' on origin/overnight/feature (hold / reset / edit / commit / push / release, same pattern as
         ovn_park_sweep.sh) -> enable the repo's dev lane if QA mode has them all off.
  sweep  refresh every open entry from OVERNIGHT_PROGRESS.md on origin/overnight/feature (fixed / needs-human / open), publish ONE
         relay note per status change, release lanes we enabled (queue drained, or the 24h safety valve).
  list   table of all entries.
  retest (2026-10-02, bugs-first policy) apply Mark's retest verdict: 'ok' closes a bug the fleet fixed ('fixed (awaiting your retest)' ->
         'closed'); 'still-broken' reopens it at the top of Next Steps with his note attached and a FRESH attempt counter (new [feat:..rN] tag =>
         new item hash => the loop's per-item counters start at zero). Fed by scripts/qa-retest -> the bridge. Statuses: open, fixed (awaiting
         your retest), escalated (fleet gave up after 2 attempts -> '[CLAUDE] [bug-escalated: ..]', see state/bug_escalations.jsonl),
         needs-human, needs-triage, closed.
  close  --id ID --by COMMIT   (2026-10-03) an interactive Claude fix landed: entry -> fixed (awaiting retest), its progress lines -> [x]. The sweep also
         honors a 'Fixes-manual-bug: <feat|id>' commit trailer reachable from develop/main/claude/feature. reopen --id ID: re-queue a wrongly credited bug.
         'fixed' by the fleet now needs a landed commit on the located file + a real (non-tautological) test (OVN_MANUAL_FIX_EVIDENCE=off = old behavior).
  brief  [--id ID] [--force]   (2026-10-02) research + plan + decompose the claimed bug(s) into a test-first brief of single-file steps and replace the
         single item with them (qa/bug_brief.py; kill switch OVN_BUG_BRIEF=off). `add` marks the entry brief:pending and spawns this detached; the sweep
         retries leftovers. A failed / invalid / slow brief leaves the single item exactly as enqueued.

Why the locator exists: scripts/ovn_retire_vague.py retires any '- [ ]' item that names no existing file. An item without a real
path is dead on arrival, so a note we cannot place becomes status 'needs-triage' (one relay note, NOT enqueued).

Hard rules (docs/QA_GATES_SPEC.md): never fail open silently, the model is advisory (paths it invents are discarded, any model
error falls back to the deterministic result), no secrets in output, never `git add -A`, always release the hold, never push
anywhere but origin overnight/feature, never reach ntfy.sh unless NTFY_SERVER says so (unset => no notification, logged).
State: $OVN_DIR/state/manual_notes.json (atomic writes, flock). Env: OVN_DIR, OVN_REPOS_DIR, NTFY_SERVER, NTFY_TOPIC,
LITELLM_BASE, LITELLM_MASTER_KEY, OVN_MANUAL_MODEL (name or 'off'), OVN_MANUAL_AUTOLANE (off disables lanes),
OVN_MANUAL_LANE_TTL_H (default 24).
"""
import argparse
import base64
import fcntl
import hashlib
import json
import math
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.request

try:                      # locator v2 building blocks (platform layout, product-only filter, agentic loop); v1 behaviour without it
    import manual_locator as ml
except ImportError:       # pragma: no cover - the file is deployed next to this one
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import manual_locator as ml
    except ImportError:
        ml = None

OVN_BRANCH = "overnight/feature"
COMMIT_ENV = ["-c", "user.email=22970726+markhint22@users.noreply.github.com", "-c", "user.name=shrike-fleet"]
NOTE_CAP = 400
THRESHOLD = 3.0          # a candidate needs this much evidence to count as "located"
PLAUSIBLE_RATIO = 0.5    # a candidate within this fraction of the top score is "plausible" (>=2 plausible => ask the model)
MAX_FILES_PER_KW = 40    # a keyword hitting more files than this is not discriminative
LANE_TTL_H_DEFAULT = 24.0
OPEN_STATES = ("open", "pending-enqueue")
# 2026-10-02 bugs-first: what a human reads. The stored value stays 'fixed' (older state files, tests and the sweep use it); only the display changes.
STATUS_LABEL = {"fixed": "fixed (awaiting your retest)", "escalated": "escalated (Claude session)", "closed": "closed (retest ok)"}
RETESTABLE = ("fixed", "escalated", "needs-human")      # a retest verdict applies to bugs in these states

# ----------------------------------------------------------------------------------------------------------------------
# paths / state
# ----------------------------------------------------------------------------------------------------------------------

def ovn_dir():
    return os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")


def state_dir():
    return os.path.join(ovn_dir(), "state")


def state_path():
    return os.path.join(state_dir(), "manual_notes.json")


def repos_root():
    return os.environ.get("OVN_REPOS_DIR") or os.path.join(ovn_dir(), "repos")


def repo_path(name):
    """Clone under repos/ only (no ~/LocalProjects fallback: this tool writes to the box clones). None if absent/invalid."""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,80}", name or ""):
        return None
    p = os.path.join(repos_root(), name)
    return p if os.path.exists(os.path.join(p, ".git")) else None


def log(msg):
    print("%s manual_notes: %s" % (time.strftime("%F %T"), msg), flush=True)


class StateLock:
    """flock on state/manual_notes.lock with a bounded wait (never hangs a cron or a bridge call)."""

    def __init__(self, wait=90):
        self.wait = wait
        self.fh = None

    def __enter__(self):
        os.makedirs(state_dir(), exist_ok=True)
        self.fh = open(os.path.join(state_dir(), "manual_notes.lock"), "a")
        end = time.time() + self.wait
        while True:
            try:
                fcntl.flock(self.fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except OSError:
                if time.time() > end:
                    raise TimeoutError("manual_notes state lock busy")
                time.sleep(0.5)

    def __exit__(self, *a):
        try:
            fcntl.flock(self.fh, fcntl.LOCK_UN)
            self.fh.close()
        except Exception:  # noqa: BLE001
            pass


def load_state():
    try:
        with open(state_path()) as f:
            d = json.load(f)
        if isinstance(d, dict) and isinstance(d.get("entries"), dict):
            return d
    except (OSError, ValueError):
        pass
    return {"version": 1, "entries": {}}


def save_state(st):
    os.makedirs(state_dir(), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".manual_notes.", dir=state_dir())
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(st, f, indent=1, sort_keys=True, ensure_ascii=False)
        os.replace(tmp, state_path())
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ----------------------------------------------------------------------------------------------------------------------
# sanitizing
# ----------------------------------------------------------------------------------------------------------------------

def _strip_controls(s):
    s = unicodedata.normalize("NFC", s)
    out = []
    for ch in s:
        cat = unicodedata.category(ch)
        if ch in "\n\r\t\v\f\x85  ":
            out.append(" ")
        elif cat in ("Cc", "Cf", "Cs", "Co", "Cn"):
            continue  # control, format (zero-width / bidi), surrogate, private, unassigned
        else:
            out.append(ch)
    return re.sub(r"\s+", " ", "".join(out)).strip()


def clean_for_locator(note):
    """Light clean: keeps identifiers (underscores, quotes) the locator needs."""
    return _strip_controls(note)[:NOTE_CAP]


_TAGS = re.compile(r"(?i)\b(verify|cat|multifile|src|feat|recovery|polish|tier)\s*:")


def sanitize_note(note):
    """The text that goes INTO the queue item: one line, no markdown, nothing that a queue parser could mistake for syntax
    (VERIFY:, (cat:, [feat:], [T1], AUTO-SKIP, HUMAN-ONLY, ' — ', html comments, shell substitutions)."""
    s = _strip_controls(note)
    s = s.replace("`", "'")
    s = re.sub(r"<!--|-->", " ", s)
    s = re.sub(r"[*#~^<>\\{}]", " ", s)          # markdown / html / escape chars
    s = s.replace("$(", "( ").replace("${", "( ")
    s = s.replace("[", "(").replace("]", ")")     # no [T1] / [feat:] / [CLAUDE] lookalikes
    s = s.replace("|", "/")
    s = s.replace(" — ", " - ").replace("—", "-").replace("–", "-")
    s = _TAGS.sub(lambda m: m.group(1).lower() + " -", s)
    s = re.sub(r"(?i)auto-skip", "auto skip", s)
    s = re.sub(r"(?i)human-only", "human only", s)
    # 2026-10-02 (bugs-first): every queue selector drops a line that contains these park markers (case-insensitive) - a tester note such as
    # "playback is blocked after login" would make its own bug item invisible to the loop forever (and to the lane-focus rule).
    s = re.sub(r"(?i)blocked", "block-ed", s)
    s = re.sub(r"(?i)human/", "human /", s)
    s = re.sub(r"(?i)hard file ban", "hard file-ban", s)
    s = re.sub(r"\s+", " ", s).strip()
    if len(s) > NOTE_CAP:
        s = s[:NOTE_CAP - 3].rstrip() + "..."
    return s.strip(" .;:!,") or ""


def entry_id(repo, date, flow, note):
    norm = re.sub(r"\s+", " ", clean_for_locator(note)).lower()
    return hashlib.sha256(("%s|%s|%s|%s" % (repo, date, flow.strip().lower(), norm)).encode("utf-8")).hexdigest()[:16]


# ----------------------------------------------------------------------------------------------------------------------
# git helpers
# ----------------------------------------------------------------------------------------------------------------------

def sh(cmd, cwd=None, timeout=60, env=None):
    e = dict(os.environ)
    e["GIT_TERMINAL_PROMPT"] = "0"
    if env:
        e.update(env)
    try:
        p = subprocess.run(cmd, cwd=cwd, env=e, capture_output=True, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return 124, "", "timeout after %ss" % timeout
    except FileNotFoundError as ex:
        return 127, "", str(ex)


def git(repo, *args, timeout=60):
    return sh(["git", "-C", repo] + list(args), timeout=timeout)


def ref_for(repo):
    """Prefer origin/overnight/feature (what the fleet works on); fall back to origin/develop for the locator only."""
    for r in ("origin/" + OVN_BRANCH,):
        rc, _, _ = git(repo, "rev-parse", "--verify", "-q", r + "^{commit}")
        if rc == 0:
            return r
    return None


# ----------------------------------------------------------------------------------------------------------------------
# locator
# ----------------------------------------------------------------------------------------------------------------------

SRC_EXT = {"py", "vue", "ts", "tsx", "js", "jsx", "mjs", "kt", "kts", "java", "xml", "swift", "gd", "tscn", "tres", "html", "css",
           "strings", "json", "gradle", "sql"}
RESOURCE_HINT = re.compile(r"(^|/)(strings\.xml|[^/]*\.strings|locales?/[^/]+\.json|i18n/[^/]+\.json|messages/[^/]+\.json)$", re.I)
EXCLUDE_DIR = re.compile(r"(^|/)(node_modules|\.git|dist|build|Pods|\.venv|venv|htmlcov|__pycache__|\.gradle|DerivedData|vendor|"
                         r"addons|\.godot|coverage|\.next|\.nuxt|android/app/build|alembic/versions|migrations/versions|"
                         r"docs?|assets|public|\.idea|\.vscode)(/|$)")
EXCLUDE_FILE = re.compile(r"(package-lock\.json|yarn\.lock|\.min\.(js|css)|tsconfig[^/]*\.json|package\.json|\.lock$|OVERNIGHT_|"
                          r"\.d\.ts$|\.import$|\.snap$)")
TEST_PATH = re.compile(r"(^|/)(tests?|__tests__|spec|androidTest|test)/|[._]test\.|_test\.|\.spec\.|Tests?\.(kt|swift|java)$|(^|/)test_[^/]*$",
                       re.I)
JSONISH = re.compile(r"\.json$")

STOP = set("""
a an and are as at be been being but by can cant cannot could did didnt do does doesnt doing dont done for from get gets got had has
have having her here him his how if in into is isnt it its just let like may me might more most much must my no not now of off ok
on one only or other our out over own really same she should so some such than that the their them then there these they this
those through to too under until up us use used uses using very want was wasnt we were what when where which while who why will
with wont would you your yours also after again always any anything around back because before below between both down during each
even every few first going good great keep last later least less long look looks made make makes many never next nothing once
still take taking tried try trying turn turns two went seems seem shows show showed shown sometimes someone something somewhere
sure tap taps tapped click clicks clicked press pressed opens open opened opening button buttons screen screens page pages app apps
thing things stuff works work working worked broken bug bugs issue issues error errors wrong right bad weird fine nice feels feel
felt seemed expected expect instead happens happen happened happening time times lot lots bit little big small new old again
user users mark test testing tested tests page view views click when while doesn does
""".split())
GENERIC_FLOWS = {"other", "ui", "misc", "general", "app", "test", "manual", ""}


def _is_strong_ident(tok):
    if len(tok) < 5:
        return False
    if "_" in tok.strip("_") and re.search(r"[A-Za-z]", tok):
        return True
    if re.search(r"[a-z][A-Z]", tok):          # camelCase / PascalCase with a hump
        return True
    if re.fullmatch(r"[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*", tok):
        return True
    return False


def _variants(words):
    w = [x.lower() for x in words]
    return sorted({" ".join(w), "".join(w), "_".join(w), "-".join(w)})


def extract_keywords(note, flow):
    """-> list of {label, variants, weight, kind}. Strong = identifiers/quoted labels/routes/bigrams, weak = rare plain words."""
    kws = {}

    def add(label, variants, weight, kind):
        key = label.lower()
        if key in kws and kws[key]["weight"] >= weight:
            return
        variants = [v for v in variants if len(v) >= 4]
        if variants:
            kws[key] = {"label": label, "variants": variants, "weight": weight, "kind": kind}

    text = clean_for_locator(note)
    for m in re.finditer(r"(?:^|[\s(])(['\"“‘])(.{3,60}?)(['\"”’])(?=$|[\s.,;:!?)])", text):
        phrase = m.group(2).strip()
        if len(phrase) >= 3:
            add(phrase, [phrase], 4.0, "quoted")
    for m in re.finditer(r"(?<![\w/])(/[A-Za-z0-9_\-]+(?:/[A-Za-z0-9_{}\-]+)+)", text):
        add(m.group(1), [m.group(1).rstrip("/")], 4.0, "route")
    for m in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*", text):
        tok = m.group(0)
        after = text[m.end():m.end() + 2]
        if _is_strong_ident(tok) or (after.startswith("(") and len(tok) >= 5 and tok.lower() not in STOP):
            add(tok, [tok], 4.0, "identifier")
    # plain words -> weak; adjacent significant words -> phrase concepts (restore purchases -> restorePurchases / restore_purchases ...)
    seq = []
    for m in re.finditer(r"[A-Za-z][A-Za-z0-9']*", text):
        w = m.group(0).lower().strip("'")
        seq.append(None if (w in STOP or len(w) < 3) else w)
    for w in seq:
        if w and len(w) >= 4:
            add(w, [w], 1.0, "word")
    runs, cur = [], []
    for w in seq + [None]:
        if w:
            cur.append(w)
        else:
            if len(cur) >= 2:
                runs.append(cur)
            cur = []
    n = 0
    for run in runs:
        for size in (3, 2):
            for i in range(0, len(run) - size + 1):
                if n >= 9:
                    break
                g = run[i:i + size]
                add(" ".join(g), _variants(g), 3.0, "phrase")
                n += 1
    for part in re.split(r"[-_.\s/]+", (flow or "").lower()):
        if part and part not in GENERIC_FLOWS and part not in STOP and len(part) >= 4:
            add("flow:" + part, [part], 1.5, "flow")
    return list(kws.values())


def named_files(note, files):
    """Files the note names outright (basename or path with a code extension that exists in the tree)."""
    out = []
    base = {}
    for f in files:
        base.setdefault(os.path.basename(f).lower(), []).append(f)
    for m in re.finditer(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}\b", clean_for_locator(note)):
        tok = m.group(0).strip("./")
        if tok in files:
            out.append(tok)
        else:
            out += [f for f in base.get(os.path.basename(tok).lower(), []) if f.endswith(tok)][:3]
    return list(dict.fromkeys(out))


def all_files(repo, ref):
    rc, out, _ = git(repo, "ls-tree", "-r", "--name-only", ref, timeout=60)
    return out.splitlines() if rc == 0 else []


def list_files(repo, ref, names=None):
    keep = []
    for f in (all_files(repo, ref) if names is None else names):
        ext = f.rsplit(".", 1)[-1].lower() if "." in f else ""
        if ext in SRC_EXT and not EXCLUDE_DIR.search(f) and not EXCLUDE_FILE.search(f) and (ml is None or ml.is_product_path(f)):
            keep.append(f)
    return keep


def grep_kw(repo, ref, variant, allowed, specs=None):
    """-> {path: (line_no, text)} for fixed-string case-insensitive matches (first hit per file). `specs` = path prefixes to search."""
    rc, out, _ = git(repo, "grep", "-n", "-I", "-i", "-F", "-m", "2", "-e", variant, ref, "--", *(specs or []), timeout=40)
    hits = {}
    if rc != 0:
        return hits
    prefix = ref + ":"
    for ln in out.splitlines():
        if not ln.startswith(prefix):
            continue
        rest = ln[len(prefix):]
        m = re.match(r"(.+?):(\d+):(.*)$", rest)
        if m and m.group(1) in allowed and m.group(1) not in hits:
            hits[m.group(1)] = (int(m.group(2)), m.group(3).strip())
    return hits


def _label_key(path, text):
    """If a hit is a UI-label resource line, return the resource KEY the code references it by (R.string.<key>, t('<key>'))."""
    if path.endswith(".xml"):
        m = re.search(r'<string\s+name="([A-Za-z0-9_.]+)"', text)
        return m.group(1) if m else None
    if path.endswith(".strings"):
        m = re.match(r'"([^"]+)"\s*=', text)
        return m.group(1) if m else None
    if path.endswith(".json") and RESOURCE_HINT.search(path):
        m = re.match(r'"([A-Za-z0-9_.\-]+)"\s*:', text)
        return m.group(1) if m else None
    return None


STEM_SUFFIX = ("viewmodel", "controller", "service", "router", "screen", "store", "view", "page", "activity", "fragment")
PLATFORMS = {"android": ("android", ["android"]), "kotlin": ("android", ["android"]), "ios": ("ios", ["ios"]), "iphone": ("ios", ["ios"]),
             "ipad": ("ios", ["ios"]), "swift": ("ios", ["ios"]), "web": ("web", ["web", "frontend"]), "browser": ("web", ["web", "frontend"]),
             "website": ("web", ["web", "frontend"]), "chrome": ("web", ["web", "frontend"]), "safari": ("web", ["web", "frontend"]),
             "tvos": ("tv", ["tv"]), "backend": ("backend", ["backend", "server", "routers", "api"]),
             "server": ("backend", ["backend", "server", "routers", "api"]),
             "endpoint": ("backend", ["backend", "server", "routers", "api"]), "api": ("backend", ["backend", "server", "routers", "api"])}


def file_stems(path):
    """Normalized names a file answers to: 'routers/alerts.py' -> {'alerts'}, 'AlertsView.vue' -> {'alertsview','alerts'}."""
    base = os.path.basename(path).rsplit(".", 1)[0].lower().replace("_", "").replace("-", "")
    out = {base}
    for suf in STEM_SUFFIX:
        if base.endswith(suf) and len(base) > len(suf) + 2:
            out.add(base[:-len(suf)])
    return out


def stem_match(word, stems):
    w = word.lower().replace("_", "").replace("-", "").replace(" ", "")
    return any(w == st or w + "s" == st or w == st + "s" for st in stems)


def platform_hints(note, flow):
    toks = set(re.findall(r"[a-z]+", (note + " " + (flow or "")).lower()))
    return [PLATFORMS[t] for t in sorted(toks) if t in PLATFORMS]


def locate(repo, ref, note, flow, allow=None, top_n=3, specs=None):
    """Deterministic locator. -> {"candidates": [top <=top_n dicts], "all": n_scored, "keywords": n}. A candidate dict:
    {path, score, evidence, matched:[labels], located: bool}. `allow` restricts the candidates to a set of paths (platform filter),
    `specs` the git-grep path prefixes (speed only)."""
    files = list_files(repo, ref)
    if allow is not None:
        files = [f for f in files if f in allow]
    allowed = set(files)
    scores, evid, matched = {}, {}, {}

    def credit(path, w, label, ev=None):
        scores[path] = scores.get(path, 0.0) + w
        matched.setdefault(path, [])
        if label not in matched[path]:
            matched[path].append(label)
        if ev and (path not in evid or w >= evid[path][0]):
            evid[path] = (w, ev)

    for f in named_files(note, files):
        credit(f, 6.0, "named in note", "%s (named in the note)" % f)
    kws = extract_keywords(note, flow)
    lower_paths = {f: f.lower() for f in files}
    stem_cache = {}
    named = set(named_files(note, files))
    label_keys = []
    for kw in kws:
        file_hits = {}
        for v in kw["variants"]:
            for p, (ln, tx) in grep_kw(repo, ref, v, allowed, specs).items():
                file_hits.setdefault(p, (ln, tx, v))
            if kw["kind"] == "flow":
                break
        # path-name matches
        pathhits = set()
        for v in kw["variants"]:
            vv = v.replace(" ", "")
            if len(vv) >= 4:
                pathhits |= {f for f, lp in lower_paths.items() if vv in lp.replace("_", "").replace("-", "")}
        if kw["kind"] in ("word", "flow", "phrase"):
            vv = kw["variants"][0]
            exact = [f for f in files if stem_match(vv, stem_cache.setdefault(f, file_stems(f)))]
            if 0 < len(exact) <= 6:                # the file is NAMED after the word (alerts -> routers/alerts.py)
                for f in exact:
                    credit(f, 2.5 if kw["kind"] != "flow" else 3.5, kw["label"] + " (file is named after it)",
                           "%s (file name is '%s')" % (f, kw["label"]))
        if kw["kind"] == "flow":
            file_hits = {}                         # a flow word only counts through the file NAME, never through content
        if len(file_hits) > MAX_FILES_PER_KW and kw["weight"] < 4.0:
            continue
        if len(file_hits) > MAX_FILES_PER_KW * 2:
            continue
        for p, (ln, tx, v) in file_hits.items():
            credit(p, kw["weight"], kw["label"], "%s:%d: %s" % (p, ln, tx[:140]))
            if kw["kind"] in ("quoted", "phrase", "identifier") and len(label_keys) < 3:
                k = _label_key(p, tx)
                if k and k not in label_keys:
                    label_keys.append(k)
        if len(pathhits) <= MAX_FILES_PER_KW:
            for p in pathhits:
                credit(p, kw["weight"] * 0.8, kw["label"] + " (in file name)", "%s (file name matches '%s')" % (p, kw["label"]))
    # a UI label found in a resource file -> the code files that reference its key (R.string.x / t('x') / strings.xml key)
    for k in label_keys:
        for p, (ln, tx) in grep_kw(repo, ref, k, allowed, specs).items():
            if not RESOURCE_HINT.search(p):
                credit(p, 3.0, "uses label key " + k, "%s:%d: %s" % (p, ln, tx[:140]))
    hints = platform_hints(note, flow)
    ranked = []
    for p, s in scores.items():
        adj = s
        if TEST_PATH.search(p) and p not in named:
            continue          # a bug is fixed in source, not in a test; a test file is evidence at best, never the target
        if RESOURCE_HINT.search(p):
            adj *= 0.7
        segs = p.lower().split("/")
        if adj > 0 and any(tok in seg for _name, toks in hints for tok in toks for seg in segs):
            adj += 2.5    # the note/flow says android / ios / web / backend and this file lives there
        ranked.append((adj, p))
    ranked.sort(key=lambda t: (-t[0], t[1]))
    cands = []
    for adj, p in ranked[:top_n]:
        cands.append({"path": p, "score": round(adj, 2), "evidence": (evid.get(p) or (0, p))[1], "matched": matched.get(p, [])[:6],
                      "located": adj >= THRESHOLD})
    return {"candidates": cands, "all": len(scores), "keywords": len(kws)}


def plausible(cands):
    good = [c for c in cands if c["located"]]
    if not good:
        return []
    top = good[0]["score"]
    return [c for c in good if c["score"] >= top * PLAUSIBLE_RATIO]


# ----------------------------------------------------------------------------------------------------------------------
# locator v2: platform -> product-only -> deterministic -> (weak/ambiguous) agentic loop
# ----------------------------------------------------------------------------------------------------------------------
STRONG_SCORE = float(os.environ.get("OVN_LOCATOR_STRONG", "9"))   # a deterministic top result at/above this with no rival is final


def _cand(path, score, evidence, matched, located=True, role=None):
    d = {"path": path, "score": round(score, 2), "evidence": evidence, "matched": matched, "located": located}
    if role:
        d["role"] = role
    return d


def det_margin():
    """OVN_LOCATOR_DET_MARGIN: how much more evidence the deterministic top must have to beat the agentic primary (None = feature off)."""
    v = os.environ.get("OVN_LOCATOR_DET_MARGIN", "1.0").strip().lower()
    if v in ("off", "no", "none", "false"):
        return None
    try:
        return float(v)
    except ValueError:
        return 1.0


def locate_v2(rp, ref, note, flow, platform=None, use_model=True, model_fn=None, repo_name=""):
    """Platform-aware, product-only, agentic locator. -> {"status": "located"|"needs-triage", "candidates": [...], "also": [paths],
    "platform", "platform_source", "ranked_by", "agentic": {...}|None, "model_calls": n, "platform_candidates": {...}, "all", "keywords"}.
    Never raises on a model problem (falls back to the deterministic result)."""
    out = {"status": "located", "candidates": [], "also": [], "platform": "", "platform_source": "", "ranked_by": "deterministic",
           "agentic": None, "model_calls": 0, "all": 0, "keywords": 0}
    files = all_files(rp, ref)
    prod = list_files(rp, ref, files)
    layout = ml.detect_layout(files) if ml else {}
    plat = ml.normalize_platform(platform) if ml else ""
    src = "log" if plat else ""
    if ml and not plat:
        plat, src = ml.infer_platform(flow, note)
    if layout and plat and not ml.platforms_for(plat, layout):
        out["platform_note"] = "platform '%s' has no directory in this repo (%s)" % (plat, ", ".join(sorted(set(layout.values()))))
        plat, src = "", "not-in-repo"
    allow, prim, also, specs = None, set(prod), set(prod), None
    if layout and plat:
        prim, also = ml.candidates_for_platform(prod, layout, plat)
        allow = prim
        plats = ml.platforms_for(plat, layout) | ({"backend"} if plat in ml.CLIENTS else set())
        specs = sorted(pre for pre, p in layout.items() if p in plats) or None
    det = locate(rp, ref, note, flow, allow=allow, top_n=12, specs=specs)
    out["all"], out["keywords"] = det["all"], det["keywords"]
    ranked = det["candidates"]
    if layout and not plat:
        # no platform from the log, the flow id or the words: only decisive EVIDENCE may pick one. Otherwise triage - never alphabetical.
        best = {}
        for c in ranked:
            if c["located"]:
                best.setdefault(ml.plat_of(c["path"], layout) or "shared", []).append(c)
        order = sorted(best, key=lambda k: -best[k][0]["score"])
        if order and (len(order) == 1 or best[order[0]][0]["score"] >= 1.5 * best[order[1]][0]["score"]):
            plat, src = order[0], "evidence"
            if plat != "shared":
                prim, also = ml.candidates_for_platform(prod, layout, plat)
                ranked = [c for c in ranked if c["path"] in prim]
        else:
            out["status"] = "needs-triage"
            out["platform_source"] = "ambiguous"
            out["platform_candidates"] = {k: [(c["path"], c["score"]) for c in v[:2]] for k, v in best.items()}
            out["candidates"] = ranked[:3]
            return out
    out["platform"], out["platform_source"] = plat, src
    cands = ranked[:3]
    good = plausible(cands)
    # "strong" = a high score that rests on a NAMED file or an identifier / quoted label / route from the note. A high score built from
    # many plain words (a long prose note) is exactly the weak evidence the agentic loop exists for.
    strong_labels = {k["label"] for k in extract_keywords(note, flow) if k["kind"] in ("quoted", "identifier", "route")} | {"named in note"}
    strong = (bool(good) and good[0]["score"] >= STRONG_SCORE and len(good) == 1
              and any(m_ in strong_labels for m_ in good[0].get("matched", [])))
    calls = 0
    if use_model and not strong and ml and os.environ.get("OVN_MANUAL_AGENTIC", "") != "off" and (model_fn is not None or model_enabled()):
        seeds = {}
        for c in ranked[:3]:
            if c["located"]:
                m = re.match(r"(.+?):(\d+): (.*)$", c["evidence"] or "")
                seeds[c["path"]] = (int(m.group(2)), m.group(3)) if m and m.group(1) == c["path"] else (1, (c["evidence"] or "")[:140])
        agent = ml.agentic_localize(rp, ref, loc_clean(note), flow, plat or "app", repo_name or os.path.basename(rp), prim, also,
                                    model_fn or ml.model_chat, prefixes=specs, seed_hits=seeds)
        calls = agent["calls"]
        out["agentic"] = {k: agent.get(k) for k in ("ok", "queries", "calls", "discarded", "grep_ranked", "error", "model_dead")}
        if agent["ok"]:
            picked = []
            byp = {c["path"]: c for c in ranked}
            if agent["primary"]:
                p, why = agent["primary"]
                picked.append(_cand(p, byp[p]["score"] if p in byp else 5.0, "model: " + (why or "picked from search hits"),
                                    byp[p]["matched"] if p in byp else [], True, "primary"))
            for p, why in agent["also"]:
                picked.append(_cand(p, byp[p]["score"] if p in byp else 4.0, "model: " + (why or "picked from search hits"),
                                    byp[p]["matched"] if p in byp else [], True, "also" if picked else "primary"))
            if picked and picked[0].get("role") != "primary":
                picked[0]["role"] = "primary"
            if not agent["primary"]:
                # the model only named server-side files: keep the best in-platform file as the primary, the server files as also-look-at
                fb = next((c for c in ranked if c["located"] and c["path"] in prim), None)
                gr = next((p for p, _s in agent["grep_ranked"] if p in prim), None)
                if fb:
                    picked.insert(0, dict(fb, role="primary"))
                elif gr:
                    picked.insert(0, _cand(gr, 3.0, "search hits", [], True, "primary"))
            for c in picked[1:]:
                c["role"] = "also"
            # 2026-10-03 (A8/BUG-6): the model may OVERRIDE the deterministic ranking, but not with a pick that has clearly less evidence than the
            # deterministic top (the categories bug: the locator dropped its top file for a data-model file and the plan then said 'no change required').
            # The deterministic top wins when it is located and out-scores the agentic primary by more than OVN_LOCATOR_DET_MARGIN (default 1.0; 'off' = never).
            dm = det_margin()
            det_top = next((c for c in ranked if c["located"]), None)
            if dm is not None and picked and det_top and picked[0]["path"] != det_top["path"]:
                agent_score = byp[picked[0]["path"]]["score"] if picked[0]["path"] in byp else 0.0
                if det_top["score"] - agent_score > dm:
                    demoted = picked[0]
                    picked = [dict(det_top, role="primary"), dict(demoted, role="also")] + [c for c in picked[1:] if c["path"] != det_top["path"]]
                    out["det_override"] = "kept deterministic top %s (%.2f) over agentic %s (%.2f)" % (det_top["path"], det_top["score"], demoted["path"], agent_score)
            seen = {c["path"] for c in picked}
            for c in ranked:
                if len(picked) >= 3:
                    break
                if c["path"] not in seen and c["located"]:
                    picked.append(dict(c, role="det"))
                    seen.add(c["path"])
            out["candidates"] = picked[:3]
            out["also"] = [c["path"] for c in picked[:3] if c.get("role") == "also"][:2]
            out["ranked_by"] = "agentic"
            return out
        out["ranked_by"] = "agentic-failed-deterministic"
    out["candidates"] = cands
    out["model_calls"] = calls
    # classic tie-break (kept from v1): only when the agentic loop did not run or failed and the 4-call budget allows one more
    good = plausible(cands)
    if len(good) >= 2 and use_model and ml and calls < ml.MAX_MODEL_CALLS and (model_fn is None) and model_enabled() and not (out.get("agentic") or {}).get("model_dead"):
        order = model_rank(loc_clean(note), flow, good)
        out["model_calls"] = calls + 1
        if order:
            out["ranked_by"] = "model"
            out["model_order"] = order + [c["path"] for c in good if c["path"] not in order]
            byp = {c["path"]: c for c in good}
            rest = [c for c in cands if c["path"] not in byp]
            out["candidates"] = [byp[p] for p in out["model_order"]] + rest
        elif out["ranked_by"] == "deterministic":
            out["ranked_by"] = "model-unavailable-deterministic"
    return out


def loc_clean(note):
    return clean_for_locator(note)


# ----------------------------------------------------------------------------------------------------------------------
# model (advisory tie-break only)
# ----------------------------------------------------------------------------------------------------------------------

class _Alarm(Exception):
    pass


def _alarm(_s, _f):
    raise _Alarm()


def model_enabled():
    return os.environ.get("OVN_MANUAL_MODEL", "qwen-dflash-27B") not in ("", "off", "none")


def model_rank(note, flow, cands, timeout=100):
    """Ask the local Qwen to order the candidate paths. Returns an ordered list of paths drawn ONLY from `cands`, or None on any
    problem (disabled, down, timeout, garbage, nothing valid)."""
    name = os.environ.get("OVN_MANUAL_MODEL", "qwen-dflash-27B")
    if name in ("", "off", "none"):
        return None
    base = os.environ.get("LITELLM_BASE", "http://localhost:4000").rstrip("/")
    key = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")
    listing = "\n".join("%d. %s\n   evidence: %s" % (i + 1, c["path"], c["evidence"][:200]) for i, c in enumerate(cands))
    prompt = ("A tester reported a bug in app flow '%s':\n\"%s\"\n\nCandidate source files (the ONLY allowed answers):\n%s\n\n"
              "Which file most likely contains the code responsible? Order the candidates from most to least likely. "
              "Reply with ONLY a JSON object: {\"ranking\": [\"<path>\", ...], \"reason\": \"<one short sentence>\"}. "
              "Use paths exactly as listed; do not add any path that is not listed." % (flow, note[:NOTE_CAP], listing))
    body = json.dumps({"model": name, "messages": [{"role": "user", "content": prompt}], "temperature": 0.3, "max_tokens": 500}).encode()
    req = urllib.request.Request(base + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    old = None
    try:
        try:
            old = signal.signal(signal.SIGALRM, _alarm)
            signal.alarm(timeout + 20)
        except ValueError:
            old = None
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(1 << 20).decode("utf-8", "replace")
        content = json.loads(raw)["choices"][0]["message"]["content"] or ""
        content = re.sub(r"(?s)<think>.*?</think>", "", content)
        m = re.search(r"\{.*\}", content, re.S)
        if not m:
            return None
        ranking = json.loads(m.group(0)).get("ranking")
        if not isinstance(ranking, list):
            return None
        valid = {c["path"] for c in cands}
        out = []
        for p in ranking:
            if isinstance(p, str) and p.strip() in valid and p.strip() not in out:   # anything not in the list is discarded
                out.append(p.strip())
        return out or None
    except Exception:  # noqa: BLE001 - timeout, connection refused, bad JSON, HTTP error: all => deterministic fallback
        return None
    finally:
        try:
            signal.alarm(0)
            if old is not None:
                signal.signal(signal.SIGALRM, old)
        except Exception:  # noqa: BLE001
            pass


# ----------------------------------------------------------------------------------------------------------------------
# item construction
# ----------------------------------------------------------------------------------------------------------------------

LANG_RISK = {
    "kt": ("kotlin", "weak"), "kts": ("kotlin", "weak"), "java": ("java", "weak"), "xml": ("android-xml", "weak"),
    "swift": ("swift", "weak"), "gd": ("gdscript", "weak"), "tscn": ("godot-scene", "weak"), "tres": ("godot-scene", "weak"),
    "vue": ("vue", "medium"), "tsx": ("tsx", "medium"), "ts": ("typescript", "medium"), "js": ("javascript", "medium"),
    "jsx": ("jsx", "medium"), "html": ("html", "medium"), "css": ("css", "medium"), "py": ("python", "normal"),
}
RISK_TEXT = {"weak": "the local 27B lands Kotlin/Swift/GDScript/Android-XML fixes only ~20-35% of the time; expect this to park for a human",
             "medium": "UI/TypeScript fix; the 27B lands these less reliably than Python", "normal": "Python/backend fix, the 27B's strongest area"}


def lang_risk(path):
    ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
    return LANG_RISK.get(ext, (ext or "unknown", "medium"))


def _safe_token(s):
    return re.sub(r"[^A-Za-z0-9_.-]", "", s)


def verify_command(files, path):
    """Pick a real test command for `path` from the tree (formats copied from existing queue items)."""
    fs = set(files)
    parts = path.split("/")
    stem = _safe_token(os.path.splitext(parts[-1])[0])
    ext = parts[-1].rsplit(".", 1)[-1].lower() if "." in parts[-1] else ""
    top = parts[0] if len(parts) > 1 else ""

    def has(p):
        return p in fs

    def any_under(prefix, pred):
        return any(f.startswith(prefix) and pred(f) for f in fs)
    if ext == "py":
        root = ""
        for i in range(len(parts) - 1, 0, -1):
            cand = "/".join(parts[:i])
            if any_under(cand + "/tests/", lambda f: f.endswith(".py")) or any_under(cand + "/test/", lambda f: f.endswith(".py")):
                root = cand
                break
        tests_dir = (root + "/tests") if root else "tests"
        for t in ("%s/test_%s.py" % (tests_dir, stem), "%s/test_%ss.py" % (tests_dir, stem)):
            if has(t):
                return "pytest %s -v" % t
        near = sorted((f for f in fs if f.startswith(tests_dir + "/") and f.endswith(".py")
                       and os.path.basename(f).startswith("test_") and stem.lower() in os.path.basename(f).lower()), key=lambda f: (len(f), f))
        if near:
            return "pytest %s -v" % near[0]          # e.g. alerts.py -> tests/test_alerts_router.py
        if any_under(tests_dir + "/", lambda f: f.endswith(".py")):
            return "pytest %s -q -x" % tests_dir
        return "pytest -q"
    if ext in ("vue", "ts", "tsx", "js", "jsx", "mjs"):
        app = top if top and has(top + "/package.json") else ""
        if app:
            return "cd %s && npm run test -- %s" % (app, stem)
        if has("package.json"):
            return "npm run test -- %s" % stem
        return "npm test"
    if ext in ("gd", "tscn", "tres"):
        for t in ("tests/test_%s.gd" % stem,):
            if has(t):
                return "godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://%s -gexit" % t
        return "godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit"
    if ext in ("kt", "kts", "java", "xml"):
        app = top if top else ""
        if app and any_under(app + "/", lambda f: f.endswith(("gradlew", "build.gradle", "build.gradle.kts"))):
            return "cd %s && ./gradlew testDebugUnitTest" % app
        return "./gradlew testDebugUnitTest"
    if ext == "swift":
        return "cd %s && swift test" % top if top else "swift test"
    return "pytest -q"


def build_item(repo, entry, files):
    path = entry["path"]
    verify = verify_command(files, path)
    lang, risk = lang_risk(path)
    entry["language"], entry["risk"], entry["risk_note"] = lang, risk, RISK_TEXT.get(risk, "")
    entry["verify"] = verify
    # ALWAYS T3 (2026-10-01 integration): run_overnight.sh runs ovn_stage_runner.sh first whenever the repo has any doable T3-T5 item and
    # that runner takes the first T3+ line (.py first) - a T2 manual bug would queue behind every other T3+ item. T3 routes the fix through
    # decompose -> reproduce-first step -> fix step -> independent full verify, which is the right shape for a bug fix anyway.
    tier = "T3"
    note = entry["note"].rstrip(".;:! ")
    feat = "%s-%s-manual-%s" % (repo, entry["date"].replace("-", ""), entry["id"][:8])
    entry["feat"] = feat
    also = [p for p in entry.get("also", []) if p != path and re.fullmatch(r"[A-Za-z0-9_./@+-]+", p)][:2]
    also_txt = (" Also look at: %s." % ", ".join(also)) if also else ""
    line = ("- [ ] [%s] %s — Manual-test bug (reported by Mark, flow %s, %s): %s.%s First write a failing test that reproduces this, "
            "then fix it; if the cause is not in this file, say so. VERIFY: `%s`. (cat:bugfix; multifile:%s; src:manual) [feat:%s]"
            % (tier, path, _safe_token(entry["flow"]) or "other", entry["date"], note, also_txt, verify,
               "yes" if also else "no", feat))
    return line


def insert_item(text, line):
    """Insert `line` as the first line under '## Next Steps'. Idempotent on the [feat:..] tag. -> (new_text|None, why)."""
    m = re.search(r"\[feat:([^\]]+)\]\s*$", line)
    if m and ("[feat:%s]" % m.group(1)) in text:
        return text, "already-present"
    lines = text.split("\n")
    for i, l in enumerate(lines):
        if re.match(r"^## Next Steps\s*$", l):
            lines.insert(i + 1, line)
            return "\n".join(lines), "inserted"
    return None, "no '## Next Steps' section"


# ----------------------------------------------------------------------------------------------------------------------
# enqueue (the ovn_park_sweep.sh pattern; hold ALWAYS released)
# ----------------------------------------------------------------------------------------------------------------------

def queue_sh(*args):
    qs = os.path.join(ovn_dir(), "queue.sh")
    if not os.path.exists(qs):
        return 127, "", "queue.sh missing"
    return sh(["bash", qs] + list(args), cwd=ovn_dir(), timeout=30)


def enqueue(repo, rp, line):
    """-> (ok, message). hold -> fetch -> verify branch -> reset to origin -> edit -> commit (explicit path) -> push(+rebase retry)
    -> release in finally. Any failure leaves the clone at origin/overnight/feature (best effort) and the hold released."""
    return edit_progress(repo, rp, lambda text: insert_item(text, line),
                         "chore(queue): add manual-test bug to the top of Next Steps (reported by Mark)")


def edit_progress(repo, rp, edit_fn, commit_msg):
    """The atomic OVERNIGHT_PROGRESS.md edit (the ovn_park_sweep.sh pattern) shared by enqueue and the bug brief (2026-10-02: the brief REPLACES the
    single item by its decomposed items under the very same hold / reset / commit / push / release). edit_fn(text) -> (new_text|None, why): None = the
    edit cannot be made (-> failure), new_text == text = nothing to do ('already...' / 'skip...': success, no commit)."""
    if os.path.exists(os.path.join(ovn_dir(), "state", "HOLD_" + repo)):
        # a human (or another job) is holding this repo: never take over or clear their hold - the sweep retries this entry later
        return False, "repo is on hold (state/HOLD_%s) - will retry" % repo
    queue_sh("hold", repo)
    try:
        rc, _, err = git(rp, "fetch", "-q", "origin", OVN_BRANCH, timeout=120)
        if rc != 0:
            return False, "git fetch failed: %s" % err.strip()[:160]
        rc, out, _ = git(rp, "rev-parse", "--abbrev-ref", "HEAD")
        if rc != 0 or out.strip() != OVN_BRANCH:
            return False, "live clone is on '%s', not %s - not touching it" % (out.strip(), OVN_BRANCH)
        rc, _, err = git(rp, "reset", "-q", "--hard", "origin/" + OVN_BRANCH)
        if rc != 0:
            return False, "git reset failed: %s" % err.strip()[:160]
        f = os.path.join(rp, "OVERNIGHT_PROGRESS.md")
        try:
            with open(f, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as ex:
            return False, "cannot read OVERNIGHT_PROGRESS.md: %s" % ex
        new, why = edit_fn(text)
        if new is None:
            return False, why
        if why == "already-present":
            return True, "already present on %s" % OVN_BRANCH
        if new == text:
            return True, why
        with open(f, "w", encoding="utf-8") as fh:
            fh.write(new)
        rc, _, err = git(rp, "add", "OVERNIGHT_PROGRESS.md")
        if rc == 0:
            rc, _, err = sh(["git", "-C", rp] + COMMIT_ENV + ["commit", "-q", "-m", commit_msg], timeout=60)
        if rc != 0:
            _undo(rp)
            return False, "git commit failed: %s" % err.strip()[:160]
        rc, _, err = git(rp, "push", "-q", "origin", OVN_BRANCH, timeout=120)
        if rc != 0:
            rc1, _, err1 = git(rp, "pull", "-q", "--rebase", "origin", OVN_BRANCH, timeout=120)
            rc = rc1
            if rc1 == 0:
                rc, _, err = git(rp, "push", "-q", "origin", OVN_BRANCH, timeout=120)
            else:
                err = err1
        if rc != 0:
            _undo(rp)
            return False, "git push failed: %s" % err.strip()[:160]
        return True, "pushed to %s" % OVN_BRANCH
    except Exception as ex:  # noqa: BLE001
        try:
            _undo(rp)
        except Exception:  # noqa: BLE001
            pass
        return False, "enqueue error: %s" % ex
    finally:
        queue_sh("release", repo)


def _undo(rp):
    git(rp, "rebase", "--abort")
    git(rp, "reset", "-q", "--hard", "origin/" + OVN_BRANCH)


# ----------------------------------------------------------------------------------------------------------------------
# relay notifications (plain note, default priority; NEVER ntfy.sh unless NTFY_SERVER says so)
# ----------------------------------------------------------------------------------------------------------------------

def notify(title, message):
    server = os.environ.get("NTFY_SERVER", "").strip().rstrip("/")
    topic = os.environ.get("NTFY_TOPIC", "").strip()
    if not topic:
        try:
            with open(os.path.join(state_dir(), "ntfy_topic")) as f:
                topic = f.read().strip()
        except OSError:
            topic = ""
    if not server or not topic:
        log("notify skipped (no NTFY_SERVER/topic): %s" % title)
        return False
    try:
        req = urllib.request.Request("%s/%s" % (server, topic), data=message.encode("utf-8")[:900], method="POST",
                                     headers={"Title": title.encode("ascii", "replace").decode()[:120], "Priority": "default",
                                              "Tags": "memo"})
        with urllib.request.urlopen(req, timeout=8) as r:
            r.read(256)
        return True
    except Exception as ex:  # noqa: BLE001
        log("notify failed (%s): %s" % (type(ex).__name__, title))
        return False


def trim(s, n=80):
    s = re.sub(r"\s+", " ", s).strip()
    return s if len(s) <= n else s[:n - 3].rstrip() + "..."


def notify_once(entry, kind, title, msg):
    if kind in entry.setdefault("notified", []):
        return
    if notify(title, msg):
        entry["notified"].append(kind)


# ----------------------------------------------------------------------------------------------------------------------
# lanes
# ----------------------------------------------------------------------------------------------------------------------

def qa_state():
    try:
        with open(os.path.join(state_dir(), "qa_mode.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def lane_id(repo):
    return "ongoing-" + repo.replace("_", "-")


def maybe_enable_lane(repo, entry):
    if os.environ.get("OVN_MANUAL_AUTOLANE", "") == "off":
        return
    qs = qa_state()
    if not qs or qs.get("mode") != "qa":
        return
    if lane_id(repo) in (qs.get("temp_lanes") or []):
        entry["lane_note"] = "lane already enabled by someone else; left alone"
        return
    script = os.path.join(ovn_dir(), "qa_mode.sh")
    if not os.path.exists(script):
        entry["lane_note"] = "qa_mode.sh missing"
        return
    rc, out, err = sh(["bash", script, "lane", repo], cwd=ovn_dir(), timeout=30)
    if rc == 0:
        entry["lane_enabled_by_us"] = True
        entry["lane_enabled_at"] = time.time()
        entry["lane_note"] = "dev lane enabled so the fleet can work it"
    else:
        entry["lane_note"] = "lane enable failed: %s" % (err or out).strip()[:120]


def release_lanes(st, now=None):
    """Unlane repos whose lane we enabled when nothing is open any more, or after the TTL valve. Only while QA mode is still on
    (after `qa_mode.sh off` the lanes belong to the restored dev state)."""
    now = now or time.time()
    ttl = float(os.environ.get("OVN_MANUAL_LANE_TTL_H", LANE_TTL_H_DEFAULT)) * 3600.0
    by_repo = {}
    for e in st["entries"].values():
        by_repo.setdefault(e["repo"], []).append(e)
    for repo, es in by_repo.items():
        ours = [e for e in es if e.get("lane_enabled_by_us") and not e.get("lane_released")]
        if not ours:
            continue
        still_open = any(e["status"] in OPEN_STATES for e in es)
        oldest = min(e.get("lane_enabled_at", now) for e in ours)
        expired = (now - oldest) >= ttl
        if still_open and not expired:
            continue
        qs = qa_state()
        if qs and qs.get("mode") == "qa":
            script = os.path.join(ovn_dir(), "qa_mode.sh")
            rc, out, err = sh(["bash", script, "unlane", repo], cwd=ovn_dir(), timeout=30)
            if rc != 0:
                log("%s: unlane failed (%s) - will retry next sweep" % (repo, (err or out).strip()[:100]))
                continue
        reason = "24h safety valve" if (still_open and expired) else "no open manual items left"
        for e in ours:
            e["lane_released"] = True
            e["lane_released_at"] = now
            e["lane_note"] = "dev lane released (%s)" % reason
        log("%s: lane released (%s)" % (repo, reason))


# ----------------------------------------------------------------------------------------------------------------------
# commands
# ----------------------------------------------------------------------------------------------------------------------

def decode_note(args):
    if args.note_b64 is not None:
        raw = base64.b64decode(args.note_b64, validate=False)
        return raw.decode("utf-8", "replace")
    return args.note or ""


_BRIEF_SPAWN = []      # entry ids that were enqueued by THIS `add` and want a bug brief (spawned after the state lock is released)


def cmd_add(args):
    rc = _cmd_add(args)
    try:
        while _BRIEF_SPAWN:
            spawn_brief(_BRIEF_SPAWN.pop(0))
    except Exception as ex:  # noqa: BLE001 - the brief is an enhancement; it can never fail an add
        log("bug brief spawn failed (%s: %s) - the single item stays as enqueued; the sweep retries" % (type(ex).__name__, ex))
    return rc


def _cmd_add(args):
    repo, flow = args.repo, (args.flow or "other")
    rp = repo_path(repo)
    if not rp:
        print("ERROR: unknown repo '%s' (no clone under %s)" % (repo, repos_root()))
        return 2
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date or ""):
        print("ERROR: --date must be YYYY-MM-DD")
        return 2
    try:
        raw_note = decode_note(args)
    except Exception:  # noqa: BLE001
        print("ERROR: --note-b64 is not valid base64")
        return 2
    note = sanitize_note(raw_note)
    loc_note = clean_for_locator(raw_note)
    if not note:
        print("ERROR: empty note after sanitizing")
        return 2
    eid = entry_id(repo, args.date, flow, raw_note)
    with StateLock():
        st = load_state()
        existing = st["entries"].get(eid)
        if existing and existing["status"] != "pending-enqueue":
            print("DUPLICATE id=%s status=%s" % (eid, existing["status"]))
            return 0
        entry = existing or {"id": eid, "repo": repo, "date": args.date, "flow": flow, "minutes": args.minutes, "note": note,
                             "created": time.time(), "notified": []}
        ref = ref_for(rp)
        if not ref:
            print("ERROR: %s has no origin/%s ref (fetch the clone first)" % (repo, OVN_BRANCH))
            return 1
        files = all_files(rp, ref)          # whole tree (VERIFY detection needs package.json / gradlew too)
        if existing:
            cands = entry.get("candidates", [])      # retrying a pending enqueue: keep the earlier location
        else:
            if ml is not None:
                res = locate_v2(rp, ref, loc_note, flow, platform=getattr(args, "platform", None),
                                use_model=not args.no_model, repo_name=repo)
            else:
                res = dict(locate(rp, ref, loc_note, flow), status="located", also=[], ranked_by="deterministic", model_calls=0)
                res["candidates"] = res["candidates"]
            cands = res["candidates"]
            entry["candidates"] = cands
            entry["locator"] = {"scored_files": res["all"], "keywords": res["keywords"]}
            for k in ("platform", "platform_source", "platform_note", "platform_candidates", "agentic", "model_calls", "model_order"):
                if res.get(k) not in (None, "", {}):
                    entry[k] = res[k]
            entry["ranked_by"] = res["ranked_by"]
            if res["status"] == "located":
                if res.get("ranked_by") == "agentic":
                    good = [c for c in cands if c["located"]]
                else:
                    good = plausible(cands)
                    if res.get("model_order"):
                        byp = {c["path"]: c for c in good}
                        good = [byp[p] for p in res["model_order"] if p in byp] or good
                if good:
                    entry["path"] = good[0]["path"]
                    if res.get("also"):
                        entry["also"] = [p for p in res["also"] if p != entry["path"]][:2]
        if not entry.get("path"):
            entry["status"] = "needs-triage"
            entry["updated"] = time.time()
            st["entries"][eid] = entry
            if not args.dry_run:
                notify_once(entry, "needs-triage", "Manual bug needs triage: %s" % repo,
                            "Could not place this note in the code, so it was NOT queued (an item naming no real file is retired as "
                            "vague). Flow %s: %s. %s" % (flow, trim(note, 120), _triage_hint(entry)))
                save_state(st)
            _print_entry(entry, dry=args.dry_run)
            return 0
        line = build_item(repo, entry, files)
        entry["item"] = line
        if args.dry_run:
            entry["status"] = "dry-run"
            _print_entry(entry, dry=True)
            return 0
        ok, msg = enqueue(repo, rp, line)
        entry["enqueue_result"] = msg
        entry["updated"] = time.time()
        if ok:
            entry["status"] = "open"
            entry["enqueued_at"] = time.time()
            maybe_enable_lane(repo, entry)
            if brief_wanted(args):
                # 2026-10-02: the single item is ALREADY at the top of the queue (right away, as before). The brief replaces it by a test-first
                # list of single-file steps when it is ready (minutes); if it never is, nothing changes.
                entry["brief"] = {"status": "pending", "since": time.time()}
                _BRIEF_SPAWN.append(eid)
        else:
            entry["status"] = "pending-enqueue"
            log("%s: enqueue failed (%s) - kept as pending-enqueue, the sweep retries" % (repo, msg))
        st["entries"][eid] = entry
        save_state(st)
        _print_entry(entry)
        return 0


def _triage_hint(e):
    pc = e.get("platform_candidates")
    if pc:
        return ("The platform is unclear (%s); re-log it with the platform column (android/ios/web/backend/...). Candidates: %s"
                % (e.get("platform_source", "?"), "; ".join("%s: %s" % (k, ", ".join(os.path.basename(p) for p, _s in v)) for k, v in sorted(pc.items()))))
    return "Add a screen/label/function name or the platform and re-log it."


def _print_entry(e, dry=False):
    print("%s id=%s repo=%s status=%s path=%s" % ("DRY-RUN" if dry else "ADDED", e["id"], e["repo"], e["status"], e.get("path", "-")))
    for c in e.get("candidates", []):
        print("  candidate %.1f %s%s :: %s" % (c["score"], c["path"], "" if c["located"] else " (below threshold)", c["evidence"][:110]))
    if e.get("platform") or e.get("platform_source"):
        print("  platform=%s (%s)%s" % (e.get("platform") or "-", e.get("platform_source", "-"), "  " + e["platform_note"] if e.get("platform_note") else ""))
    for pl, v in sorted((e.get("platform_candidates") or {}).items()):
        print("  platform-candidate %s: %s" % (pl, ", ".join("%s (%.1f)" % (p, sc) for p, sc in v)))
    ag = e.get("agentic")
    if ag:
        print("  agentic: ok=%s calls=%s%s" % (ag.get("ok"), ag.get("calls"), ("  error=" + ag["error"]) if ag.get("error") else ""))
        for i, qs in enumerate(ag.get("queries") or []):
            print("    queries round %d: %s" % (i + 1, " | ".join(qs)))
        if ag.get("discarded"):
            print("    discarded (invented/filtered): %s" % ", ".join(ag["discarded"]))
    if e.get("also"):
        print("  also look at: %s" % ", ".join(e["also"]))
    if e.get("ranked_by"):
        print("  ranked_by=%s risk=%s lang=%s" % (e["ranked_by"], e.get("risk", "-"), e.get("language", "-")))
    if e.get("brief"):
        print("  brief: %s%s" % (e["brief"].get("status"), ("  (%s)" % e["brief"]["why"]) if e["brief"].get("why") else ""))
    if e.get("item"):
        print("  item: " + e["item"])


# ----------------------------------------------------------------------------------------------------------------------
# bug brief (2026-10-02): research + plan + decompose the enqueued bug; replace the single item. See qa/bug_brief.py.
# ----------------------------------------------------------------------------------------------------------------------
BRIEF_STALE_S = 1800        # a 'running' claim older than this is taken over (the claiming process died)
BRIEF_MAX_TRIES = 3         # apply failures (hold / push races) before the entry is left as the single item


def _bb():
    """The bug_brief module, or None (not deployed / broken / OVN_BUG_BRIEF=off): today's single-item behaviour."""
    try:
        import bug_brief
        return bug_brief if bug_brief.enabled() else None
    except Exception:  # noqa: BLE001
        return None


def brief_wanted(args=None):
    return (not getattr(args, "no_model", False)) and model_enabled() and _bb() is not None


def spawn_brief(eid):
    """Run `brief --id <eid>` detached (the bridge's ssh budget is 120 s; a brief takes minutes). OVN_BUG_BRIEF_SPAWN=off => the sweep does it."""
    if os.environ.get("OVN_BUG_BRIEF_SPAWN", "on") == "off":
        return
    logd = os.path.join(ovn_dir(), "logs")
    os.makedirs(logd, exist_ok=True)
    lf = open(os.path.join(logd, "bug_brief.log"), "a")
    try:
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "brief", "--id", eid], stdin=subprocess.DEVNULL, stdout=lf, stderr=lf,
                         start_new_session=True, close_fds=True, env=dict(os.environ))
    finally:
        lf.close()


def _brief_claim(eid=None, force=False, limit=1):
    """Under the state lock: pick open entries whose brief is pending (or a stale 'running' claim) and mark them running. -> [entry copies]"""
    out = []
    with StateLock():
        st = load_state()
        now = time.time()
        for k, e in sorted(st["entries"].items(), key=lambda kv: kv[1].get("created", 0)):
            if eid and k != eid:
                continue
            b = e.get("brief") or {}
            if e.get("status") != "open" or not e.get("path") or not e.get("feat"):
                continue
            stale = b.get("status") == "running" and now - b.get("claimed_at", 0) > BRIEF_STALE_S
            if not (b.get("status") == "pending" or stale or (force and b.get("status") in ("done", "fallback", "skipped", "running", None))):
                continue
            e["brief"] = dict(b, status="running", claimed_at=now, tries=b.get("tries", 0))
            out.append(json.loads(json.dumps(e)))
            if len(out) >= limit:
                break
        if out:
            save_state(st)
    return out


def _brief_finish(eid, patch, items=None):
    with StateLock():
        st = load_state()
        e = st["entries"].get(eid)
        if e is None:
            return
        e["brief"] = dict(e.get("brief") or {}, **patch)
        if items is not None:
            e["brief_items"] = items
        e["updated"] = time.time()
        save_state(st)


def _brief_run_one(e):
    """Compute the brief OUTSIDE the state lock (minutes of model + test time), then apply under it. Never raises; every outcome is recorded."""
    eid, repo = e["id"], e["repo"]
    bb = _bb()
    t0 = time.time()
    try:
        if bb is None:
            return _brief_finish(eid, {"status": "skipped", "why": "bug brief disabled or not deployed", "at": time.time()})
        rp = repo_path(repo)
        if not rp:
            return _brief_finish(eid, {"status": "pending", "why": "clone missing; will retry"})
        git(rp, "fetch", "-q", "origin", OVN_BRANCH, timeout=120)
        ref = ref_for(rp)
        if not ref:
            return _brief_finish(eid, {"status": "pending", "why": "no %s ref; will retry" % OVN_BRANCH})
        res = bb.make_brief(rp, ref, e["note"], e["flow"], e["path"], e.get("also", []), e.get("platform") or None, repo_name=repo, feat=e["feat"],
                            date=e["date"])
        bb.save_brief_record(e["feat"], res, ovn_dir())
        info = {"calls": res.get("calls", 0), "seconds": round(time.time() - t0, 1), "at": time.time(),
                "red_proof": (res.get("red_proof") or {}).get("status")}
        if res["status"] != "ok":
            log("%s: bug brief fell back to the single item (%s)" % (repo, res.get("why")))
            return _brief_finish(eid, dict(info, status="fallback", why=str(res.get("why"))[:300]))
        with StateLock():
            ok, msg = edit_progress(repo, rp, lambda t: bb.apply_to_text(t, e["feat"], res["items"]),
                                    "chore(queue): decompose manual-test bug into a test-first brief of %d step(s) (%s)" % (len(res["items"]), e["feat"]))
        if not ok:
            tries = (e.get("brief") or {}).get("tries", 0) + 1
            log("%s: bug brief apply failed (%s) try %d" % (repo, msg, tries))
            return _brief_finish(eid, dict(info, status="pending" if tries < BRIEF_MAX_TRIES else "fallback", tries=tries,
                                           why="apply failed: %s" % msg[:200]))
        st_ = "done" if msg.startswith("pushed") or msg.startswith("replaced") or msg == "replaced" else "skipped"
        log("%s: bug brief %s: %s (%d item(s))" % (repo, st_, msg, len(res["items"])))
        return _brief_finish(eid, dict(info, status=st_, why=msg[:200], **({"items": len(res["items"])} if st_ == "done" else {})),
                             items=res["items"] if st_ == "done" else None)
    except Exception as ex:  # noqa: BLE001
        log("%s: bug brief error (%s: %s) - single item stays" % (repo, type(ex).__name__, ex))
        try:
            _brief_finish(eid, {"status": "fallback", "why": "error: %s" % type(ex).__name__, "at": time.time()})
        except Exception:  # noqa: BLE001
            pass


def _pending_brief_ids(limit=1):
    """Ids of open entries whose brief is pending (or a stale 'running' claim). Read only."""
    with StateLock():
        st = load_state()
    now = time.time()
    out = []
    for k, e in sorted(st["entries"].items(), key=lambda kv: kv[1].get("created", 0)):
        b = e.get("brief") or {}
        if e.get("status") == "open" and e.get("path") and e.get("feat") and (
                b.get("status") == "pending" or (b.get("status") == "running" and now - b.get("claimed_at", 0) > BRIEF_STALE_S)):
            out.append(k)
            if len(out) >= limit:
                break
    return out


def sweep_briefs():
    """The sweep's brief pass. A brief takes minutes (model + test run) and the cron wrapper runs ONE sweep at a time with a 600 s hard timeout, so the
    sweep must not do it inline: it spawns the pending brief detached (the child claims it under the state lock; a fresh claim is never taken twice).
    OVN_BUG_BRIEF_SPAWN=off (tests, manual use) runs it inline instead."""
    if _bb() is None:
        return
    if os.environ.get("OVN_BUG_BRIEF_SPAWN", "on") == "off":
        brief_run_pending()
        return
    for eid in _pending_brief_ids():
        spawn_brief(eid)


def brief_run_pending(eid=None, force=False, limit=1):
    """Claim + run pending briefs, ONE at a time (a global non-blocking lock keeps two model/test jobs from running together)."""
    lockf = None
    try:
        os.makedirs(state_dir(), exist_ok=True)
        lockf = open(os.path.join(state_dir(), "bug_brief.lock"), "a")
        try:
            fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            log("another bug brief is running - leaving the pending entries for the next sweep")
            return 0
        n = 0
        for e in _brief_claim(eid, force, limit):
            _brief_run_one(e)
            n += 1
        return n
    except TimeoutError as ex:
        log("bug brief: %s" % ex)
        return 0
    finally:
        if lockf:
            try:
                fcntl.flock(lockf, fcntl.LOCK_UN)
                lockf.close()
            except Exception:  # noqa: BLE001
                pass


def cmd_brief(args):
    if _bb() is None:
        print("bug brief is off (OVN_BUG_BRIEF=off) or bug_brief.py is not deployed: nothing to do")
        return 0
    n = brief_run_pending(args.id, args.force, limit=(1 if args.id else 2))
    print("brief: %d entr%s processed" % (n, "y" if n == 1 else "ies"))
    return 0


def read_ref_file(rp, ref, name):
    rc, out, _ = git(rp, "show", "%s:%s" % (ref, name), timeout=60)
    return out if rc == 0 else None


def classify_lines(lines):
    """Aggregate every queue line carrying one [feat:ID] tag -> (status, reason)."""
    if not lines:
        return None, "item not found"
    states = []
    for ln in lines:
        s = ln.lstrip()
        done = s.startswith("- [x]") or s.startswith("- [X]")
        parked = bool(re.search(r"\[(AUTO-SKIP|HUMAN-ONLY|CLAUDE)\b", s) or "(retired-" in s)
        sat = "already-satisfied" in s or "already-done" in s
        states.append((done, parked, sat))
    if any(not d and not p for d, p, _ in states):
        return "open", "still queued"
    if any(p for _, p, _ in states):
        # 2026-10-02: ovn_item_guard.sh tags a bug that used up its attempts '[CLAUDE] [bug-escalated: ...]' (never a silent AUTO-SKIP)
        if any("[bug-escalated" in l for l in lines):
            return "escalated", "fleet gave up after its attempt cap; handed to a Claude fix session (state/bug_escalations.jsonl)"
        return "needs-human", "parked by the fleet (AUTO-SKIP / [CLAUDE] / retired)"
    if all(sat for _, _, sat in states):
        return "needs-human", "fleet judged it already satisfied in code - the bug may not be in this file"
    return "fixed", "checked off [x] by the fleet"


# ----------------------------------------------------------------------------------------------------------------------
# fix evidence (2026-10-03, A7-2): '[x]' on the queue line is NOT proof. The closed-captions bug was reported 'fixed' to Mark on the strength of a
# 0-byte test file and then `assert(true)` ("placeholder"); no commit ever touched the located source file. 'fixed' now needs a landed commit
# that touched the located file (or an 'also look at' file) AND a landed test that really asserts something about the bug.
# ----------------------------------------------------------------------------------------------------------------------
ASSERT_CALL_RE = re.compile(r"\b(?:assert\w*|expect|verify|require|check|should\w*|XCTAssert\w*|Assert\.\w+|assertThat)\s*\(|^\s*assert\s+\S|\bexpect\s*\(|\.should\b|\bassert\w*\s*\{", re.I)
VACUOUS_ASSERT_RES = [
    re.compile(r"\bassert\w*\s*\(\s*(?:true|True|1)\s*[,)]", re.I),          # assert(true), assertTrue(true), assertTrue(true, "msg")
    re.compile(r"^\s*assert\s+(?:True|true|1)\s*(?:#.*)?$"),                      # python: assert True
    re.compile(r"\bassert\w*\s*\(\s*(?:\"[^\"]*\"\s*,\s*)?(\w+)\s*,\s*\1\s*\)", re.I),   # assertEquals(x, x)
    re.compile(r"\bassert\w*\s*\(\s*\"[^\"]*\"\s*,\s*(?:true|1)\s*\)", re.I),         # assertTrue("msg", true)
    re.compile(r"\bassert\w*\s*\(\s*(?:\"[^\"]*\"\s*,\s*)?(\"[^\"]*\"|'[^']*'|-?\d+(?:\.\d+)?)\s*,\s*\1\s*\)", re.I),   # assertEquals("a", "a") / (1, 1)
    re.compile(r"\bassertFalse\s*\(\s*(?:\"[^\"]*\"\s*,\s*)?false\s*\)|\bassertNull\s*\(\s*(?:\"[^\"]*\"\s*,\s*)?null\s*\)", re.I),
    re.compile(r"\b(?:check|require)\s*\(\s*true\s*\)", re.I),
    re.compile(r"\bexpect\s*\(\s*(?:true|1)\s*\)\s*\.\s*(?:toBe|toEqual|toBeTruthy)\s*\(\s*(?:true|1)?\s*\)", re.I),
]
PLACEHOLDER_RE = re.compile(r"placeholder|to ensure the file is not empty|TODO:? *(?:write|add|implement) *(?:a )?test", re.I)
KEYWORD_MIN_WEIGHT = 3.0


def real_test_lines(added_text):
    """Non-vacuous assertion lines in the ADDED text of ONE test file ([] when the file is a placeholder or only asserts tautologies)."""
    if PLACEHOLDER_RE.search(added_text or ""):
        return []
    out = []
    for ln in (added_text or "").split("\n"):
        if not ASSERT_CALL_RE.search(ln):
            continue
        if any(r.search(ln) for r in VACUOUS_ASSERT_RES):
            continue
        out.append(ln.strip())
    return out


def _test_path(path):
    return bool(TEST_PATH.search(path))


def fix_evidence(rp, ref, e):
    """-> (True|False|None, why). True = a landed commit touched the located file AND a landed test really asserts something that references the
    bug; False = checked off without that; None = could not check (git/infra problem or no located file) - the caller keeps the old verdict."""
    if os.environ.get("OVN_MANUAL_FIX_EVIDENCE", "").lower() == "off":
        return None, "evidence check off"
    targets = [x for x in [e.get("path")] + list(e.get("also") or []) if x]
    if not targets:
        return None, "no located file to check"
    since = float(e.get("enqueued_at") or e.get("created") or 0) - 5       # commit times are whole seconds, enqueued_at is not
    rc, out, err = git(rp, "log", "-n", "2000", "--since=@%d" % int(since), "--format=@@%H %ct", "--name-only", ref, timeout=120)
    if rc != 0:
        return None, "git log failed: %s" % err.strip()[:100]
    commits, cur = [], None
    for ln in out.split("\n"):
        if ln.startswith("@@"):
            sha, ct = ln[2:].split(" ")
            cur = {"sha": sha, "ct": float(ct), "files": []}
            commits.append(cur)
        elif ln.strip() and cur is not None:
            cur["files"].append(ln.strip())
    commits = [c for c in commits if c["ct"] >= since]
    src = [c for c in commits if any(f in targets for f in c["files"])]
    if not src:
        return False, "checked off, but no landed commit touched %s" % targets[0]
    stems = {os.path.splitext(os.path.basename(t))[0].lower() for t in targets if not _test_path(t)}
    stems = {x for x in stems if len(x) >= 4}
    kws = set()
    for k in extract_keywords(e.get("note", ""), e.get("flow", "")):
        if k["weight"] >= KEYWORD_MIN_WEIGHT:
            kws.update(v.lower() for v in k["variants"])
    for c in commits:
        for f in c["files"]:
            if not _test_path(f):
                continue
            rc, diff, _ = git(rp, "show", "-U0", "--format=", c["sha"], "--", f, timeout=60)
            if rc != 0:
                continue
            added = "\n".join(l[1:] for l in diff.split("\n") if l.startswith("+") and not l.startswith("+++"))
            if not real_test_lines(added):
                continue
            low = added.lower() + " " + f.lower()
            if any(x in low for x in stems) or any(k in low for k in kws):
                return True, "commit %s touched %s; test %s asserts it" % (c["sha"][:8], targets[0], f)
    return False, "checked off, but no landed test with a real assertion references the bug (placeholder / tautology / no test)"


# ----------------------------------------------------------------------------------------------------------------------
# close / reopen / 'Fixes-manual-bug:' trailer (2026-10-03, A7-4/A7-5): an interactive Claude fix must retire the notes entry AND its progress lines
# (the h7 fixes were merged 10-02 20:33; the fleet re-attempted all three overnight because nothing told it).
# ----------------------------------------------------------------------------------------------------------------------
TRAILER_RE = re.compile(r"^Fixes-manual-bug:[ \t]*(.+?)[ \t]*$", re.I | re.M)
CLOSABLE_STATES = OPEN_STATES + ("escalated", "needs-human")


def close_progress_lines(text, feat, sha):
    """Flip every open '- [ ]' line carrying [feat:<feat>] to '- [x]' with a pointer to the fixing commit. Idempotent."""
    tag = "[feat:%s]" % feat
    out, n = [], 0
    for ln in text.split("\n"):
        if tag in ln and re.match(r"^\s*- \[ \] ", ln):
            ln = re.sub(r"^(\s*)- \[ \] ", r"\1- [x] ", ln, count=1) + " (closed: fixed by Claude %s, Fixes-manual-bug)" % sha[:12]
            n += 1
        out.append(ln)
    return "\n".join(out), ("closed %d line(s)" % n) if n else "skip: no open line for the tag"


def _feat_base(f):
    return re.sub(r"\.r\d+$", "", f or "")


def entry_matches_ref(e, ref):
    r = (ref or "").strip().strip("[]").lower()
    r = re.sub(r"^feat:", "", r)
    if not r:
        return False
    return r in (e["feat"].lower(), _feat_base(e["feat"]).lower(), e["id"].lower()) or (len(r) >= 6 and e["id"].lower().startswith(r))


def apply_close(e, repo, rp, sha, now, reason=None):
    """Mark ONE entry fixed-awaiting-retest by commit `sha` and retire its progress lines. Caller holds the StateLock. -> (ok, message)."""
    ok_, msg = True, "no clone"
    if rp:
        ok_, msg = edit_progress(repo, rp, lambda t: close_progress_lines(t, e["feat"], sha),
                                 "chore(queue): close manual-test bug %s (fixed by %s)" % (e["feat"], sha[:12]))
    if not ok_:
        return False, msg
    e["status"] = "fixed"
    e["status_reason"] = reason or ("fixed by Claude commit %s (awaiting your retest)" % sha[:12])
    e["closed_by"] = sha
    e["updated"] = now
    e["notified"] = list(set(e.get("notified", [])) | {"fixed"})          # Mark knows (he asked for the fix); no 'fleet says it landed' relay note
    return True, msg


def trailer_fixes(rp):
    """-> [(sha, commit_time, [refs])] for commits on develop / main / claude/feature / the fleet branch whose message carries 'Fixes-manual-bug:'."""
    refs = []
    for b in ("develop", "main", "claude/feature", OVN_BRANCH):
        git(rp, "fetch", "-q", "origin", b, timeout=120)
        rc, _, _ = git(rp, "rev-parse", "--verify", "-q", "origin/%s^{commit}" % b)
        if rc == 0:
            refs.append("origin/%s" % b)
    if not refs:
        return []
    rc, out, _ = git(rp, "log", "-n", "300", "-i", "--grep=^Fixes-manual-bug:", "--format=%H%x1f%ct%x1f%B%x1e", *refs, timeout=120)
    if rc != 0:
        return []
    res = []
    for rec in out.split("\x1e"):
        if "\x1f" not in rec:
            continue
        sha, ct, body = rec.strip().split("\x1f", 2)
        vals = []
        for m in TRAILER_RE.finditer(body):
            vals += [v for v in re.split(r"[,\s]+", m.group(1)) if v]
        if vals:
            res.append((sha, float(ct), vals))
    return res


def _find_entry(st, ident, repo=""):
    ident = (ident or "").strip()
    hits = [e for e in st["entries"].values() if (not repo or e["repo"] == repo) and (e["id"].startswith(ident) or entry_matches_ref(e, ident))]
    return hits


def cmd_close(args):
    with StateLock():
        st = load_state()
        hits = _find_entry(st, args.id, args.repo)
        if len(hits) != 1:
            print("ERROR: %s entries match '%s' (give a longer id prefix, or --repo)" % (len(hits), args.id))
            return 2
        e = hits[0]
        rc, full, _ = git(repo_path(e["repo"]) or ".", "rev-parse", "--verify", "-q", args.by + "^{commit}")
        sha = full.strip() if rc == 0 and full.strip() else args.by
        ok_, msg = apply_close(e, e["repo"], repo_path(e["repo"]), sha, time.time(), reason=args.reason or None)
        if not ok_:
            print("ERROR: could not retire the progress lines (%s); entry left as %s" % (msg, e["status"]))
            return 1
        release_lanes(st)
        save_state(st)
        print("CLOSED id=%s repo=%s status=%s by=%s (%s)" % (e["id"], e["repo"], e["status"], sha[:12], msg))
        return 0


def cmd_reopen(args):
    """Re-queue an entry the pipeline (or a Claude session) wrongly counted as done: a fresh [feat:...rN] tag => fresh attempt counters."""
    with StateLock():
        st = load_state()
        hits = _find_entry(st, args.id, args.repo)
        if len(hits) != 1:
            print("ERROR: %s entries match '%s' (give a longer id prefix, or --repo)" % (len(hits), args.id))
            return 2
        e = hits[0]
        rp = repo_path(e["repo"])
        if not rp or not e.get("item") or not e.get("feat"):
            print("ERROR: entry %s has no clone or stored queue item to reopen" % e["id"])
            return 3
        n = int(e.get("retest_count", 0)) + 1
        old, base = e["feat"], _feat_base(e["feat"])
        newfeat = "%s.r%d" % (base, n)
        item = e["item"].replace("[feat:%s]" % old, "[feat:%s]" % newfeat)
        why = "REOPENED %s%s: the earlier credit was not backed by a real fix. Earlier attempts are in the git log under feat tag %s - read them first, do NOT repeat the same change." % (
            args.date or time.strftime("%Y-%m-%d"), (" (%s)" % sanitize_note(args.reason)[:120]) if args.reason else "", base)
        item = item.replace(" First write a failing test", " " + why + " First write a failing test", 1) if " First write a failing test" in item else item.rstrip() + " " + why
        if args.dry_run:
            print("DRY-RUN reopen id=%s feat=%s\n  item: %s" % (e["id"], newfeat, item))
            return 0
        now = time.time()
        e.setdefault("feat_history", []).append(old)
        e["retest_count"] = n
        e["item"], e["feat"] = item, newfeat
        e["notified"] = []
        e["updated"] = now
        e["status_reason"] = "reopened (%s)" % (args.reason or "credit not backed by a fix")
        e.pop("lane_released", None)
        e.pop("closed_by", None)
        ok_, msg = enqueue(e["repo"], rp, item)
        e["enqueue_result"] = msg
        if ok_:
            e["status"], e["enqueued_at"] = "open", now
            maybe_enable_lane(e["repo"], e)
        else:
            e["status"] = "pending-enqueue"
        save_state(st)
        print("REOPENED id=%s repo=%s status=%s feat=%s attempts=reset" % (e["id"], e["repo"], e["status"], e["feat"]))
        return 0


def cmd_sweep(args):
    changed = 0
    with StateLock():
        st = load_state()
        by_repo = {}
        for e in st["entries"].values():
            if e["status"] in CLOSABLE_STATES:          # escalated / needs-human entries are only visited for a 'Fixes-manual-bug:' trailer
                by_repo.setdefault(e["repo"], []).append(e)
        for repo, es in by_repo.items():
            rp = repo_path(repo)
            if not rp:
                log("%s: clone missing, skipping" % repo)
                continue
            rc, _, err = git(rp, "fetch", "-q", "origin", OVN_BRANCH, timeout=120)
            try:
                fixes = trailer_fixes(rp) if rc == 0 else []
            except Exception as ex:  # noqa: BLE001
                log("%s: trailer scan failed (%s) - skipped" % (repo, type(ex).__name__))
                fixes = []
            for e in es:
                if e["status"] == "pending-enqueue":
                    continue
                since = float(e.get("enqueued_at") or e.get("created") or 0) - 60
                hit = next(((sha, ct) for sha, ct, vals in fixes if ct >= since and any(entry_matches_ref(e, v) for v in vals)), None)
                if hit:
                    ok_, msg = apply_close(e, repo, rp, hit[0], time.time())
                    log("%s: %s closed by 'Fixes-manual-bug' commit %s (%s)" % (repo, e["id"], hit[0][:12], msg))
                    changed += 1 if ok_ else 0
            es = [x for x in es if x["status"] in OPEN_STATES]
            if not es:
                continue
            ref = ref_for(rp)
            if rc != 0 or not ref:
                log("%s: fetch failed (%s) - leaving statuses as they are" % (repo, err.strip()[:100]))
                continue
            prog = read_ref_file(rp, ref, "OVERNIGHT_PROGRESS.md")
            done = read_ref_file(rp, ref, "OVERNIGHT_DONE.md") or ""
            if prog is None:
                log("%s: no OVERNIGHT_PROGRESS.md on %s" % (repo, ref))
                continue
            for e in es:
                if e["status"] == "pending-enqueue":
                    ok, msg = enqueue(repo, rp, e["item"]) if e.get("item") else (False, "no item stored")
                    e["enqueue_result"] = msg
                    e["updated"] = time.time()
                    if ok:
                        e["status"] = "open"
                        e["enqueued_at"] = time.time()
                        maybe_enable_lane(repo, e)
                        if brief_wanted() and not e.get("brief"):
                            e["brief"] = {"status": "pending", "since": time.time()}      # same as `add`: the retry enqueue also gets its brief
                        changed += 1
                        log("%s: pending item enqueued on retry (%s)" % (repo, e["id"]))
                    continue
                tag = "[feat:%s]" % e["feat"]
                lines = [l for l in prog.split("\n") if tag in l]
                if not lines:
                    lines = [l for l in done.split("\n") if tag in l]     # archive_done moves [x] lines to OVERNIGHT_DONE.md
                status, why = classify_lines(lines)
                if status is None:
                    age = time.time() - e.get("enqueued_at", e.get("created", time.time()))
                    if age > 3600:
                        status, why = "needs-human", "item vanished from the queue (retired or removed); re-log it if still broken"
                    else:
                        continue
                if status == "fixed" and e["status"] != "fixed":
                    verdict, ev = fix_evidence(rp, ref, e)       # '[x]' alone is not proof (A7-2)
                    if verdict is False:
                        status, why = "needs-human", ev
                    elif verdict is True:
                        why = "checked off [x] by the fleet; " + ev
                if status != e["status"]:
                    e["status"] = status
                    e["status_reason"] = why
                    e["updated"] = time.time()
                    changed += 1
                    if status == "fixed":
                        if not args.no_notify:
                            notify_once(e, "fixed", "Manual bug fixed: %s" % repo,
                                        "Fleet says it landed (retest it with scripts/qa-retest): %s" % trim(e["note"]))
                    # status == "escalated": NO note here - ovn_item_guard.sh already sent the one 'Manual bug escalated' relay note
                    elif status == "needs-human":
                        if not args.no_notify:
                            notify_once(e, "needs-human", "Manual bug needs a human: %s" % repo,
                                        "The fleet could not fix it (%s): %s" % (e["language"] if e.get("language") else "?", trim(e["note"])))
        release_lanes(st)
        save_state(st)
    if not args.no_brief:
        try:
            sweep_briefs()               # AFTER the state lock is released: a brief takes minutes of model + test time (spawned detached)
        except Exception as ex:  # noqa: BLE001
            log("bug brief pass failed (%s: %s)" % (type(ex).__name__, ex))
    log("sweep done: %d status change(s)" % changed)
    return 0


def cmd_list(args):
    st = load_state()
    es = sorted(st["entries"].values(), key=lambda e: (e["repo"], e["date"], e["id"]))
    if args.json:
        print(json.dumps(es, indent=1, sort_keys=True))
        return 0
    if not es:
        print("(no manual notes yet)")
        return 0
    print("%-20s %-10s %-14s %-6s %-44s %s" % ("repo", "date", "status", "risk", "files", "note"))
    for e in es:
        files = e.get("path") or ", ".join(c["path"] for c in e.get("candidates", [])[:2]) or "-"
        print("%-20s %-10s %-14s %-6s %-44s %s" % (e["repo"], e["date"], e["status"], e.get("risk", "-"), trim(files, 44), trim(e["note"], 70)))
    # 2026-10-02: the human-readable meaning of the statuses that ask something of Mark (stored values stay as printed above)
    shown = sorted({e["status"] for e in es if e["status"] in STATUS_LABEL})
    if shown:
        print("status key: " + "; ".join("%s = %s" % (k, STATUS_LABEL[k]) for k in shown))
    return 0


# ----------------------------------------------------------------------------------------------------------------------
# retest (2026-10-02, bugs-first): Mark's verdict on a bug the fleet reported fixed (or gave up on)
# ----------------------------------------------------------------------------------------------------------------------

def norm_flow(f):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9._]", "-", (f or "").lower())).strip("-") or "other"


def retest_key(repo, date, flow, result, note):
    return hashlib.sha256(("retest|%s|%s|%s|%s|%s" % (repo, date, norm_flow(flow), result, re.sub(r"\s+", " ", note).strip().lower())).encode("utf-8")).hexdigest()[:16]


def build_retest_item(entry, note, n, date):
    """The ORIGINAL queue line with a new [feat:...rN] tag (=> a new item hash => fresh per-item attempt counters in the loop) and the retest
    note attached. Works on whatever line the ingest wrote (also tolerant of an item that no longer has the standard wording)."""
    line = entry["item"]
    old = entry["feat"]
    base = re.sub(r"\.r\d+$", "", old)
    new = "%s.r%d" % (base, n)
    line = line.replace("[feat:%s]" % old, "[feat:%s]" % new)
    # NEVER write a literal "[feat:" in the retest text: the loop's ovn_item_hash takes the FIRST [feat:..] tag in the line, which would then be the OLD
    # one (same hash as the original item => the attempt counter would NOT be fresh). The real, new tag is the trailing one.
    rt = "RETEST FAILED %s: Mark retested the fleet's earlier fix and the bug is STILL THERE%s. The earlier attempt is in the git log under feat tag %s - read it first, do NOT repeat the same change." % (
        date, (" (his words: %s)" % note.rstrip(".;:! ")) if note else "", base)
    if " First write a failing test" in line:
        line = line.replace(" First write a failing test", " " + rt + " First write a failing test", 1)
    elif " VERIFY:" in line:
        line = line.replace(" VERIFY:", " " + rt + " VERIFY:", 1)
    else:
        line = line.rstrip() + " " + rt
    return line


def cmd_retest(args):
    repo, result = args.repo, args.result
    flow = norm_flow(args.flow)
    rp = repo_path(repo)
    if not rp:
        print("ERROR: unknown repo '%s' (no clone under %s)" % (repo, repos_root()))
        return 2
    if result not in ("ok", "still-broken"):
        print("ERROR: --result must be ok or still-broken")
        return 2
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date or ""):
        print("ERROR: --date must be YYYY-MM-DD")
        return 2
    try:
        raw = base64.b64decode(args.note_b64).decode("utf-8", "replace") if args.note_b64 else (args.note or "")
        note = sanitize_note(raw) if raw.strip() else ""
    except Exception:  # noqa: BLE001
        print("ERROR: --note-b64 is not valid base64")
        return 2
    note = note[:300]
    rid = retest_key(repo, args.date, flow, result, note)
    with StateLock():
        st = load_state()
        for e in st["entries"].values():                       # idempotent: the bridge may re-send a verdict after a lost ack
            if any(r.get("key") == rid for r in e.get("retests", [])):
                print("DUPLICATE retest id=%s status=%s" % (e["id"], e["status"]))
                return 0
        cands = [e for e in st["entries"].values() if e["repo"] == repo and norm_flow(e.get("flow")) == flow and e["status"] in RETESTABLE
                 and (not args.id or e["id"].startswith(args.id))]
        if not cands:
            print("NOMATCH no bug in %s / flow '%s' is awaiting a retest (statuses: %s)" % (
                repo, flow, ", ".join(RETESTABLE)))
            return 2 if result == "ok" else 3         # 3 = the bridge files an unmatched 'still-broken' as a normal new bug instead
        now = time.time()
        if result == "ok":
            for e in cands:
                e.setdefault("retests", []).append({"ts": now, "date": args.date, "result": "ok", "note": note, "key": rid, "from_status": e["status"]})
                e["status"] = "closed"
                e["status_reason"] = "retest ok (confirmed by Mark %s)" % args.date
                e["closed_at"] = now
                e["updated"] = now
            save_state(st)
            print("RETESTED result=ok closed=%d ids=%s" % (len(cands), ",".join(e["id"] for e in cands)))
            return 0
        prio = {"fixed": 0, "escalated": 1, "needs-human": 2}
        e = sorted(cands, key=lambda x: (prio.get(x["status"], 9), -x.get("updated", 0)))[0]
        if not e.get("item") or not e.get("feat"):
            print("NOMATCH entry %s has no stored queue item to reopen" % e["id"])
            return 3
        n = int(e.get("retest_count", 0)) + 1
        e.setdefault("retests", []).append({"ts": now, "date": args.date, "result": "still-broken", "note": note, "key": rid, "from_status": e["status"]})
        e.setdefault("feat_history", []).append(e["feat"])
        e["retest_count"] = n
        e["item"] = build_retest_item(e, note, n, args.date)
        e["feat"] = re.sub(r"\.r\d+$", "", e["feat"]) + ".r%d" % n
        e["notified"] = []                                     # the next fixed / needs-human / escalated transition notifies again
        e["updated"] = now
        e["status_reason"] = "reopened by retest %s (still broken)" % args.date
        e.pop("lane_released", None)
        if args.dry_run:
            print("DRY-RUN reopen id=%s feat=%s" % (e["id"], e["feat"]))
            print("  item: " + e["item"])
            return 0
        ok, msg = enqueue(repo, rp, e["item"])
        e["enqueue_result"] = msg
        if ok:
            e["status"] = "open"
            e["enqueued_at"] = now
            maybe_enable_lane(repo, e)
        else:
            e["status"] = "pending-enqueue"                    # the sweep retries it (same as a first enqueue that failed)
            log("%s: reopen enqueue failed (%s) - kept as pending-enqueue, the sweep retries" % (repo, msg))
        save_state(st)
        print("REOPENED id=%s repo=%s status=%s feat=%s attempts=reset" % (e["id"], repo, e["status"], e["feat"]))
        return 0



def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add")
    a.add_argument("--repo", required=True)
    a.add_argument("--date", required=True)
    a.add_argument("--flow", default="other")
    a.add_argument("--minutes", default="0")
    a.add_argument("--platform", default="", help="android|ios|tv|tvos|roku|web|backend|game|desktop|other (what the tester tested ON)")
    g = a.add_mutually_exclusive_group(required=True)
    g.add_argument("--note-b64")
    g.add_argument("--note")
    a.add_argument("--no-model", action="store_true")
    a.add_argument("--dry-run", action="store_true")
    s = sub.add_parser("sweep")
    s.add_argument("--no-notify", action="store_true")
    s.add_argument("--no-brief", action="store_true")
    b = sub.add_parser("brief")
    b.add_argument("--id", default="")
    b.add_argument("--force", action="store_true")
    l = sub.add_parser("list")
    l.add_argument("--json", action="store_true")
    r = sub.add_parser("retest")
    r.add_argument("--repo", required=True)
    r.add_argument("--date", required=True)
    r.add_argument("--flow", required=True)
    r.add_argument("--result", required=True, choices=["ok", "still-broken"])
    r.add_argument("--id", default="", help="entry id (prefix) when several bugs share a flow")
    r.add_argument("--note-b64", default="")
    r.add_argument("--note", default="")
    r.add_argument("--dry-run", action="store_true")
    c = sub.add_parser("close", help="an interactive Claude fix landed: mark the entry fixed-awaiting-retest and retire its progress lines")
    c.add_argument("--id", required=True, help="entry id (prefix) or its feat tag")
    c.add_argument("--by", required=True, help="the fixing commit")
    c.add_argument("--repo", default="")
    c.add_argument("--status", default="awaiting-retest", choices=["awaiting-retest"])
    c.add_argument("--reason", default="")
    o = sub.add_parser("reopen", help="re-queue an entry that was credited without a real fix (fresh attempt counters)")
    o.add_argument("--id", required=True)
    o.add_argument("--repo", default="")
    o.add_argument("--date", default="")
    o.add_argument("--reason", default="")
    o.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    try:
        return {"add": cmd_add, "sweep": cmd_sweep, "list": cmd_list, "retest": cmd_retest, "brief": cmd_brief, "close": cmd_close,
                "reopen": cmd_reopen}[args.cmd](args)
    except TimeoutError as ex:
        print("ERROR: %s" % ex)
        return 1


if __name__ == "__main__":
    sys.exit(main())
