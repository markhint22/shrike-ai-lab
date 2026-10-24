#!/usr/bin/env python3
"""scripts/ovn_qe_feature.py - the `feature-ideation` lens of the box-side explorer (ovn_qwen_explore.py), 2026-10-23.

Why: the bug / test / quality lenses need a verbatim evidence quote inside an existing defect, so they can never propose NEW product behaviour. When a repo has no [ready] feature and
the doable backlog is thin, the local Qwen must do FEATURE-LEVEL research itself (Mark: Claude out of the loop). This module holds the PURE, dependency-free parts so they are unit-testable:

  - build_outline()   deterministic app-surface outline from the read-only snapshot (regex extraction, no model): python routes / models / services, TS / Vue routes / stores / exports,
                      Kotlin screens / view-models, GDScript classes and public methods
  - build_vision()    README / ROADMAP / AGENTS / docs vision text, token budgeted
  - feature_select_prompt() / build_feature_prompt()   the two model prompts (closed JSON schema; every item is anchored to an existing file + symbol + verbatim quote INSIDE that symbol)
  - text rules        helper-only, not-observable, sensitive-area (auth / crypto / payment), multi-file, VERIFY-must-be-a-test  (mechanical, run by the explorer next to ALL the existing gates)
  - seen memory       titles proposed / rejected-as-duplicate recently are listed in the prompt and re-proposals are refused (the dup-memory idea of ovn_local_research.py 72adde6)
  - mode / starving / caps helpers and the rotating shadow audit file

The explorer (ovn_qwen_explore.py) owns every gate that touches the snapshot (file exists, symbol defined, quote inside the symbol, VERIFY allow-list, red-before, skeptic, critic).
env: OVN_QE_FEATURE_LENS=off|shadow|on (default shadow), OVN_QE_FEATURE_MAX_PER_DAY (8 passes / repo / day), OVN_QE_FEATURE_TTL_H (2), OVN_QE_FEATURE_FUEL (15 doable backlog items),
     OVN_QE_FEATURE_VISION_TOKENS (2500), OVN_QE_FEATURE_OUTLINE_TOKENS (3500), OVN_QE_FEATURE_FILE_TOKENS (14000), OVN_QE_FEATURE_SEEN_TTL_H (72), OVN_QE_FEATURE_SHADOW_MAX_MB (8).
"""
import json
import os
import re

FEATURE_LENS = "feature-ideation"
FEATURE_TAG = "[src:qwen-explore-feature]"
CHARS_PER_TOKEN = 3.6


def _num(name, default, cast=int):
    try:
        return cast(os.environ.get(name, default))
    except (TypeError, ValueError):
        return cast(default)


def feature_mode():
    """off | shadow | on. Anything else (a typo) is the SAFE mode, shadow: nothing is appended."""
    m = (os.environ.get("OVN_QE_FEATURE_LENS") or "shadow").strip().lower()
    return m if m in ("off", "shadow", "on") else "shadow"


def max_per_day():
    return _num("OVN_QE_FEATURE_MAX_PER_DAY", 8)


def lens_ttl_s():
    return int(_num("OVN_QE_FEATURE_TTL_H", 2, float) * 3600)


def fuel_threshold():
    return _num("OVN_QE_FEATURE_FUEL", 15)


def doable_backlog(backlog_text, is_parked=None):
    """Open T1-T3 backlog lines the fleet can still pull (parked / routed-to-Claude lines are not doable)."""
    n = 0
    for ln in (backlog_text or "").split("\n"):
        if re.match(r"^\s*- \[ \] \[T[1-3]\]", ln) and not (is_parked and is_parked(ln)):
            n += 1
    return n


def is_starving(ready, doable):
    """No [ready] roadmap feature AND the doable backlog is below the enough-fuel threshold."""
    return ready <= 0 and doable < fuel_threshold()


# ------------------------------------------------------------------------------------------------ outline (deterministic)
OUTLINE_EXTS = (".py", ".ts", ".tsx", ".js", ".vue", ".kt", ".gd")

_PY_ROUTE = re.compile(r"""^\s*@\s*([A-Za-z_][\w.]*)\.(get|post|put|patch|delete|head|options|websocket|api_route)\(\s*(?:path\s*=\s*)?[rf]?["']([^"']*)["']""")
_PY_PREFIX = re.compile(r"""(?:APIRouter|Blueprint)\([^)]*?(?:prefix|url_prefix)\s*=\s*["']([^"']*)["']""")
_PY_DEF = re.compile(r"^(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\(([^)]*)")
_PY_CLASS = re.compile(r"^class\s+([A-Za-z_]\w*)\s*(?:\(([^)]*)\))?\s*:")
_PY_TABLE = re.compile(r"""^\s+__tablename__\s*=\s*["']([^"']+)["']""")
_TS_ROUTE = re.compile(r"""\bpath\s*:\s*['"`]([^'"`]*)['"`]""")
_TS_ROUTE_NAME = re.compile(r"""\b(?:component|name)\s*:\s*['"]?([\w$.]+)""")
_TS_STORE = re.compile(r"""defineStore\(\s*['"]([^'"]+)['"]""")
_TS_EXPORT = re.compile(r"^\s*export\s+(?:default\s+)?(?:async\s+)?(?:function\*?|const|class|let)\s+([A-Za-z_$][\w$]*)")
_TS_CALL = re.compile(r"""\b(?:api|axios|http|client|apiClient)\.(get|post|put|patch|delete)\(\s*[`'"]([^`'"]+)""")
_VUE_FN = re.compile(r"^\s{0,4}(?:async\s+)?function\s+([A-Za-z_$][\w$]*)|^\s{0,4}const\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\(")
_KT_SCREEN = re.compile(r"^\s*(?:@Composable\s+)?fun\s+(\w*(?:Screen|Page|Dialog|Sheet|Route|Tab)\w*)\s*\(")
_KT_CLASS = re.compile(r"^\s*(?:(?:data|sealed|open|abstract|enum|inner)\s+)*(?:class|object|interface)\s+(\w+)")
_KT_FUN = re.compile(r"^\s{0,4}(?:(?:private|internal|protected|public)\s+)?(?:override\s+)?(?:suspend\s+)?fun\s+(?:<[^>]*>\s*)?(\w+)\s*\(")
_GD_CLASS = re.compile(r"^class_name\s+(\w+)")
_GD_EXT = re.compile(r"^extends\s+(\S+)")
_GD_FUNC = re.compile(r"^(?:static\s+)?func\s+([A-Za-z]\w*)\s*\(([^)]*)\)")
_GD_SIGNAL = re.compile(r"^signal\s+(\w+)")
_GD_INNER = re.compile(r"^class\s+(\w+)")

KIND_RANK = {"routes": 0, "page": 1, "store": 2, "models": 3, "screen": 4, "viewmodel": 4, "class": 5, "component": 6, "module": 7}


def _short_args(a, n=4):
    names = [re.split(r"[:=\s]", x.strip().lstrip("*"), maxsplit=1)[0] for x in (a or "").split(",") if x.strip()]
    names = [x for x in names if x and x not in ("self", "cls")]
    return ",".join(names[:n]) + ("..." if len(names) > n else "")


def outline_entries(path, text):
    """(kind, [items]) for one source file; items are short strings. ('module', []) when nothing recognisable is in it."""
    ext = os.path.splitext(path)[1]
    lines = (text or "").split("\n")
    if ext == ".py":
        return _py_entries(lines)
    if ext in (".ts", ".tsx", ".js", ".vue"):
        return _ts_entries(path, lines, ext)
    if ext == ".kt":
        return _kt_entries(path, lines)
    if ext == ".gd":
        return _gd_entries(lines)
    return "module", []


def _py_entries(lines):
    prefix = ""
    for ln in lines:
        m = _PY_PREFIX.search(ln)
        if m:
            prefix = m.group(1)
            break
    routes, models, classes, funcs = [], [], [], []
    pending = []
    cur_cls = None
    for i, ln in enumerate(lines):
        m = _PY_ROUTE.match(ln)
        if m:
            pending.append((m.group(2).upper() if m.group(2) != "api_route" else "ANY", m.group(3)))
            continue
        d = _PY_DEF.match(ln)
        if d:
            if pending:
                for verb, p in pending:
                    routes.append("%s %s -> %s" % (verb, (prefix.rstrip("/") + "/" + p.lstrip("/")).rstrip("/") if (prefix or p) else "/", d.group(1)))
                pending = []
            elif not d.group(1).startswith("_"):
                funcs.append("%s(%s)" % (d.group(1), _short_args(d.group(2))))
            continue
        if ln and not ln[0].isspace() and not ln.startswith(("@", "#")):
            pending = []
        c = _PY_CLASS.match(ln)
        if c:
            cur_cls = c.group(1)
            classes.append(cur_cls)
            continue
        t = _PY_TABLE.match(ln)
        if t and cur_cls:
            models.append("table %s (%s)" % (t.group(1), cur_cls))
    if routes:
        return "routes", routes[:24]
    if models:
        return "models", models[:14] + [c for c in classes if not any("(%s)" % c in x for x in models)][:6]
    items = ["class " + c for c in classes[:8]] + funcs[:10]
    return ("class" if classes else "module"), items


def _ts_entries(path, lines, ext):
    routes, stores, exports, calls, fns = [], [], [], [], []
    for ln in lines:
        m = _TS_ROUTE.search(ln)
        if m and re.search(r"\b(?:component|name|redirect|children|meta)\b", ln):
            nm = _TS_ROUTE_NAME.search(ln[m.end():])
            routes.append("route %s%s" % (m.group(1), (" -> " + nm.group(1)) if nm else ""))
        s = _TS_STORE.search(ln)
        if s:
            stores.append("store " + s.group(1))
        e = _TS_EXPORT.match(ln)
        if e:
            exports.append(e.group(1))
        for cm in _TS_CALL.finditer(ln):
            calls.append("%s %s" % (cm.group(1).upper(), cm.group(2)[:60]))
        if ext == ".vue":
            v = _VUE_FN.match(ln)
            if v:
                fns.append(v.group(1) or v.group(2))
    seg = "/" + path.lower()
    if routes:
        return "routes", routes[:24]
    if stores:
        return "store", stores[:6] + exports[:8]
    kind = "page" if re.search(r"/(pages?|views?|screens?|routes)/", seg) else ("component" if ext in (".vue", ".tsx") else "module")
    items = exports[:10] + fns[:10]
    seen = set()
    items = [x for x in items if not (x in seen or seen.add(x))]
    if calls:
        items += ["calls " + c for c in sorted(set(calls))[:8]]
    return kind, items[:20]


def _kt_entries(path, lines):
    screens, classes, funs = [], [], []
    for ln in lines:
        m = _KT_SCREEN.match(ln)
        if m:
            screens.append("screen " + m.group(1))
            continue
        c = _KT_CLASS.match(ln)
        if c:
            classes.append(c.group(1))
            continue
        f = _KT_FUN.match(ln)
        if f and not re.match(r"^\s*private\b", ln) and f.group(1) not in ("onCreate", "onCleared"):
            funs.append(f.group(1))
    vm = [c for c in classes if c.endswith("ViewModel")]
    if vm:
        return "viewmodel", ["class " + c for c in vm[:3]] + ["fun " + f for f in funs[:14]]
    if screens or os.path.basename(path).endswith("Screen.kt"):
        return "screen", screens[:10] or ["class " + c for c in classes[:4]]
    return ("class" if classes else "module"), ["class " + c for c in classes[:6]] + ["fun " + f for f in funs[:8]]


def _gd_entries(lines):
    cname, ext, sigs, funcs, inner = "", "", [], [], []
    for ln in lines:
        m = _GD_CLASS.match(ln)
        if m:
            cname = m.group(1)
            continue
        m = _GD_EXT.match(ln)
        if m and not ext:
            ext = m.group(1)
            continue
        m = _GD_SIGNAL.match(ln)
        if m:
            sigs.append(m.group(1))
            continue
        m = _GD_INNER.match(ln)
        if m:
            inner.append(m.group(1))
            continue
        m = _GD_FUNC.match(ln)
        if m:
            funcs.append("%s(%s)" % (m.group(1), _short_args(m.group(2))))
    head = ("class %s%s" % (cname, (" extends " + ext) if ext else "")) if cname else (("extends " + ext) if ext else "script")
    items = [head]
    if sigs:
        items.append("signals " + ",".join(sigs[:6]))
    if inner:
        items.append("inner " + ",".join(inner[:4]))
    items += funcs[:14]
    return "class", items


def build_outline(snap, paths, budget_chars=None, read=None):
    """The app-surface outline: one line per file `path [kind] item; item; ...`, routers / pages first, cut to the budget with an honest tail. `read(path)` -> text (default: open under snap)."""
    budget = budget_chars if budget_chars is not None else int(_num("OVN_QE_FEATURE_OUTLINE_TOKENS", 3500) * CHARS_PER_TOKEN)

    def _read(p):
        try:
            with open(os.path.join(snap, p), encoding="utf-8", errors="replace") as f:
                return f.read()
        except OSError:
            return ""
    rd = read or _read
    rows = []
    for p in paths:
        if not p.endswith(OUTLINE_EXTS):
            continue
        kind, items = outline_entries(p, rd(p))
        if not items and kind == "module":
            continue
        rows.append((KIND_RANK.get(kind, 9), p, kind, items))
    rows.sort(key=lambda r: (r[0], r[1]))
    out, used, cut = [], 0, []
    for _, p, kind, items in rows:
        line = ("%s [%s] %s" % (p, kind, "; ".join(items)))[:700]
        if used + len(line) + 1 > budget:
            cut.append(p)
            continue
        out.append(line)
        used += len(line) + 1
    if cut:
        out.append("(+%d more files not shown: %s%s)" % (len(cut), ", ".join(cut[:6]), ", ..." if len(cut) > 6 else ""))
    return "\n".join(out) if out else "(no recognisable routes, models, screens or classes found)"


# ------------------------------------------------------------------------------------------------ vision (README / ROADMAP / AGENTS)
def _clean_md(t):
    out, fence = [], False
    for ln in (t or "").split("\n"):
        if ln.strip().startswith("```"):
            fence = not fence
            continue
        if fence or re.match(r"^\s*(?:!\[|\[!\[|<img|<a |<p |</|\|[-: |]+\|?\s*$)", ln):
            continue
        out.append(ln.rstrip())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()


def _promises(t, budget):
    """Headings and top-level bullets of a roadmap-like doc (the PROMISES), de-duplicated, cut to the budget."""
    seen, out, used = set(), [], 0
    for ln in (t or "").split("\n"):
        s = ln.strip()
        if not re.match(r"^(#{1,4}\s|[-*]\s|\d+[.)]\s)", s):
            continue
        key = re.sub(r"\W+", " ", s.lower())[:80]
        if key in seen:
            continue
        seen.add(key)
        s = s[:200]
        if used + len(s) + 1 > budget:
            break
        out.append(s)
        used += len(s) + 1
    return "\n".join(out)


def build_vision(read, names, budget_chars=None):
    """README + roadmap-like docs + AGENTS excerpt. `read(path)` -> text or ''; `names` = the snapshot's root / docs file list. Returns '(no README ...)' text when nothing exists."""
    budget = budget_chars if budget_chars is not None else int(_num("OVN_QE_FEATURE_VISION_TOKENS", 2500) * CHARS_PER_TOKEN)
    parts = []
    readme = next((n for n in names if n.lower() in ("readme.md", "readme")), None)
    if readme:
        parts.append(("README", _clean_md(read(readme))[:int(budget * 0.5)]))
    docs = [n for n in names if "/" not in n and re.search(r"(?i)roadmap|vision|product|plan", n) and n.endswith(".md")][:2]
    docs += [n for n in names if n.startswith("docs/") and re.search(r"(?i)vision|product|roadmap|overview", n) and n.endswith(".md")][:1]
    for n in docs:
        body = _promises(read(n), int(budget * 0.25))
        if body:
            parts.append((n, body))
    ag = next((n for n in names if n == "AGENTS.md"), None)
    if ag:
        parts.append(("AGENTS.md", _clean_md(read(ag))[:int(budget * 0.25)]))
    if not parts:
        return "(no README / roadmap / AGENTS text in the repo)"
    return "\n\n".join("--- %s ---\n%s" % (n, b) for n, b in parts if b)


def salvage_items(text):
    """Complete item objects out of a reply whose outer JSON is cut off (the model ran out of tokens mid-item) or wrapped in prose: every decodable {...} that carries the item keys. [] when none."""
    dec = json.JSONDecoder()
    out, i = [], 0
    while True:
        j = text.find("{", i)
        if j < 0:
            return out
        try:
            obj, end = dec.raw_decode(text[j:])
        except ValueError:
            i = j + 1
            continue
        if isinstance(obj, dict) and obj.get("file") and obj.get("symbol") and (obj.get("evidence_quote") or obj.get("quote")) and obj.get("title"):
            out.append(obj)
            i = j + end
        else:
            i = j + 1


# ------------------------------------------------------------------------------------------------ prompts
FEATURE_DESC = "product features and behaviours the app still lacks"
FEATURE_GUIDE = ("Find USER-VALUABLE behaviour the product plausibly still lacks: a missing edge-case behaviour (empty / duplicate / over-limit / offline input a user can hit), a missing endpoint, screen or setting, "
                 "a UX gap, a reliability or observability gap a user or operator would notice, or a promise in the README / roadmap / vision text that has no implementation. The change hooks into an EXISTING "
                 "file and symbol and is verified by one test that fails now.")


def feature_select_prompt(repo, vision, outline, tree, recent, max_files, full_view_lines):
    return ("You are the product research planner of an autonomous coding fleet working on the repo %s. Every task backlog of this repo is empty: decide where NEW user-valuable behaviour could be hooked in.\n\n"
            "PRODUCT VISION AND PROMISES:\n%s\n\nAPP SURFACE OUTLINE (extracted from the code):\n%s\n\n"
            "Pick the files where a missing behaviour of the kinds below would be implemented: an existing endpoint / handler / screen / class that lacks an edge case, a setting, a status or a promised behaviour. "
            "Choose at most %d paths, copied EXACTLY from the FILES list. Prefer files of at most %d lines (only those can be shown whole) and files that carry product behaviour (routers, services, screens, game rules), not constants or glue.\n\n"
            "FILES (path | size | git churn):\n%s\n\nRECENTLY COVERED (do not pick): %s\n\nReply with ONLY this JSON and nothing else: {\"files\": [\"path1\", \"path2\"]}") % (
        repo, vision, outline, max_files, full_view_lines, tree, ", ".join(recent[:40]) or "(none)")


FEATURE_SHAPES = {
    "backend": ("Typical shapes that fit: an endpoint or handler that mirrors an existing one for the next resource; a filter / sort / limit query parameter on an existing list route; input validation that answers a clear 4xx instead of a 500; "
                "a status or counter field a client or operator can read; a graceful behaviour for an empty, duplicate or over-limit request; a promised behaviour from the README that no route implements yet.\n"),
    "web": ("Typical shapes that fit: an empty / loading / error state a page lacks; a filter, sort or search on an existing list; a confirmation or undo for a destructive action; a setting the store holds but no screen exposes; "
            "a README promise with no screen.\n"),
    "game": ("Typical shapes that fit: a NEW rule in an existing pure-logic class that its siblings in the outline already have for another case (a new status effect, modifier, threshold, directive, rank perk, objective condition); "
             "a scoring, reward or difficulty rule the README promises; a label or summary a screen would show. Not: re-checking rules the shown code already enforces.\n"),
}


def shapes_for(kinds):
    return "".join(FEATURE_SHAPES[k] for k in ("backend", "web", "game") if k in (kinds or ()))


LANDABLE_FEATURE_RULE = ("  8. This repo's items must be LANDABLE by a small model: a feature here is a NEW RULE in ONE self-contained pure-logic class (a new modifier, threshold, effect, label or conversion that the game does not have yet), "
                         "added as a function the shown symbol calls or that the new test drives directly. No scene, node, signal, UI or second production file.\n")


def build_feature_prompt(repo, agents, vision, outline, off_note, files_block, titles, seen_titles, subjects, dialect, max_items, landable=False, shapes=""):
    return ("You are a senior PRODUCT engineer for an autonomous coding fleet (a local 27B model implements one item at a time, each gated by a test). REPO: %s. The task backlog of this repo is EMPTY: "
            "your job is to find what the product still lacks, as small concrete features the 27B can land. A FEATURE is new behaviour the product does not have yet. It is NOT a bug in the shown code: if the shown code already handles a case "
            "(clamps, guards, rejects it), that is not a gap.\n"
            "LENS: %s - %s\n\n"
            "REPO RULES (AGENTS.md):\n%s\n\n%s"
            "PRODUCT VISION AND PROMISES (README / roadmap / docs):\n%s\n\n"
            "APP SURFACE OUTLINE (deterministic extraction of routes, models, screens, classes):\n%s\n\n"
            "FILES YOU MAY ANCHOR IN (the ONLY code you may cite):\n%s\n\n"
            "ALREADY ON THE ROADMAP / BACKLOG / DONE (do not duplicate, do not reword, do not redo):\n%s\n\n"
            "ALREADY PROPOSED OR REJECTED AS A DUPLICATE RECENTLY (do not propose again):\n%s\n\nRECENT COMMITS:\n%s\n\n"
            "TASK: propose %d-%d USER-VALUABLE features or behaviours this product plausibly still lacks. Think about: missing edge-case behaviour, a missing endpoint / screen / setting, a UX gap, a reliability or "
            "observability gap, a vision / README promise with no implementation. Compare the VISION promises and the OUTLINE: which promised behaviour, or which obvious companion of an existing endpoint / screen / rule (a sibling "
            "that the outline shows for one case but not for the next), has no implementation? %sDo NOT deliberate in your reply: no reasoning text, only the JSON object. "
            "A second reviewer audits every item and a wrong item costs a coder cycle and a revert, so prefer a few solid items to many marginal ones; return {\"items\": []} when nothing holds. Rules:\n"
            "  1. One item = ONE observable behaviour a user, API client, operator or player can see (a response, a screen, a message, a setting, a game rule). NOT: refactors, renames, style, comments, types, "
            "'add a helper / predicate / constant / util' (unless the SAME item changes the existing symbol to call it), tests for such helpers.\n"
            "  2. Anchor: `file` MUST be one of the files in the FILES block above (the outline lists more files than are shown: never anchor in a file that is not shown) and `symbol` an EXISTING function / class / method / route handler in it where the change hooks in; `evidence_quote` is 1-4 consecutive lines copied VERBATIM from INSIDE that symbol "
            "(the code the new behaviour extends or sits next to). Never invent a path, symbol or line: every item is checked mechanically.\n"
            "  3. The change touches that ONE file plus ONE new or existing test file. No second production file, no multi-file refactor, no new dependency, no new package.\n"
            "  4. OFF-LIMITS: authentication, authorization, login, passwords, tokens, crypto, payments, billing, secrets; database schema, tables, columns, migrations, new constraints; CI, queue scripts, AGENTS.md / roadmap / backlog files.\n"
            "  5. `current_gap` states a FACT about the shown code (what the code does not do today), never 'may', 'might', 'could', 'potentially'. If the behaviour already exists in the shown code, leave the item out.\n"
            "  6. `user_outcome` names what the user, client or operator sees afterwards (for example 'POST /x with an empty body returns 422 with the field name'). It must be observable, not 'cleaner' or 'more maintainable'.\n"
            "  7. Do NOT assert how a third-party API, SDK, library or engine behaves unless the shown code itself shows it.\n"
            "%s"
            "Each item has EXACTLY these keys:\n"
            "  title            imperative, under 100 chars, no em dash, states the behaviour (not 'Add helper ...')\n"
            "  file             exact path of one shown FILE\n"
            "  symbol           the existing function / class / method that the change hooks into, exactly as written in the file\n"
            "  evidence_quote   1-4 consecutive lines copied VERBATIM from INSIDE that symbol (no line numbers, no ellipsis, no markers)\n"
            "  current_gap      1-2 sentences: what the shown code does NOT do today, as a fact\n"
            "  user_outcome     1 sentence: the observable behaviour after the change\n"
            "  proposed_change  1-3 sentences: the concrete change in `file` (name what changes in `symbol`) and 'Add <path>' for the NEW test file\n"
            "  verify           ONE single-line test command from this closed list (no python -c, no pipes, no chaining) that FAILS now because the behaviour is absent and passes once it exists. The test file MUST be a NEW path (say 'Add <path>' in proposed_change) and must assert the observable outcome (a response, a return value, an output), NEVER that a function, file or string exists.\n%s\n"
            "  size             \"S\" (one function) or \"M\" (two or three small edits in one file); never larger\n"
            "  tier             1 (trivial, local) | 2 (normal) | 3 (needs care)\n"
            "Every string value is at most 300 characters. Reply with ONLY this JSON object and nothing before or after it: {\"items\": [ {...}, ... ]}.") % (
        repo, FEATURE_LENS, FEATURE_DESC + ". " + FEATURE_GUIDE, agents, off_note, vision, outline, files_block, titles or "(none)", seen_titles or "(none)", "\n".join("- " + s[:100] for s in subjects[:30]) or "(none)",
        max(2, max_items - 1), max_items, shapes, LANDABLE_FEATURE_RULE if landable else "", dialect)


# ------------------------------------------------------------------------------------------------ feature text rules (the explorer runs these in addition to ALL existing gates)
HELPER_RE = re.compile(r"\b(?:helpers?|predicates?|constants?|utils?|utilit(?:y|ies)|wrappers?|boilerplate|stubs?|accessors?|getters?|setters?|enums?|type aliases|type alias|dataclasses?|decorators?)\b", re.I)
HELPER_LEAD_RE = re.compile(r"^\s*(?:add|create|introduce|define|extract|implement|write)\s+(?:a|an|the|new|some)?\s*(?:new\s+)?(?:small\s+|tiny\s+|private\s+|shared\s+)?(?:\w+\s+){0,3}?(?:helpers?|predicates?|constants?|utils?|utilit(?:y|ies)|wrappers?|functions?|methods?|classes|class)\b", re.I)
CALLER_VERB_RE = re.compile(r"\b(?:call|calls|called|calling|use|uses|using|invoke|invokes|wire|wires|wired|replace|replaces|routes? (?:it|them) through|modif(?:y|ies)|chang(?:e|es)|updat(?:e|es)|edit|edits|extend|extends|apply|applies|clamps?|reference[sd]?|read|reads|pass(?:es)?)\b", re.I)


def helper_only(title, change, sym):
    """Rule (a) of ovn_local_research.py: a standalone helper / predicate / constant item is rejected unless the SAME item changes the existing symbol (a production caller) to use it."""
    first = re.split(r"(?<=[.!?])\s", change or "", maxsplit=1)[0]
    if not (HELPER_RE.search(title or "") or HELPER_LEAD_RE.match(title or "") or HELPER_LEAD_RE.match(first)):
        return False
    names_caller = bool(sym) and re.search(r"(?<![\w])%s(?![\w])" % re.escape(re.sub(r"\(.*$", "", sym).split(".")[-1].split("::")[-1]), change or "") is not None
    return not (names_caller and CALLER_VERB_RE.search(change or ""))


OBSERVABLE_RE = re.compile(r"\b(?:users?|clients?|callers?|operators?|admins?|players?|viewers?|subscribers?|customers?|readers?|api consumers?|responses?|responds?|returns?|returned|shows?|shown|displays?|renders?|prints?|messages?|notifications?|alerts?|screens?|pages?|buttons?|banners?|toasts?|status codes?|http\s*\d{3}|\b[1-5]\d\d\b|endpoints?|lists?|badges?|warnings?|errors?|log lines?|metrics?|health|settings?|options?|stops?|blocks?|rejects?|prevents?|allows?|can now|cannot|can no longer"
                           r"|units?|squad|soldiers?|enem(?:y|ies)|turns?|damage|accuracy|speed|morale|hit|health|cost|rewards?|credits?|scores?|missions?|heals?|increases?|reduces?|decreases?|gains?|loses?|grants?|triggers?|applies|penalt(?:y|ies)|bonus(?:es)?)\b", re.I)
INTERNAL_OUTCOME_RE = re.compile(r"\b(?:refactor\w*|readab\w*|maintainab\w*|cleaner|code quality|technical debt|developer experience|easier to (?:read|maintain|test|understand)|internal(?:ly)? only|no (?:user[- ]visible|observable) (?:change|difference))\b", re.I)


def not_observable(outcome):
    """'' or a reason: the user_outcome must be a concrete, user-visible behaviour."""
    o = (outcome or "").strip()
    if len(o) < 25:
        return "feature-not-observable"
    if INTERNAL_OUTCOME_RE.search(o) or not OBSERVABLE_RE.search(o):
        return "feature-not-observable"
    return ""


SENSITIVE_RE = re.compile(r"\b(?:auth(?:entication|orization|orisation|enticate[sd]?|orize[sd]?)?|login|log[- ]in|logout|passwords?|passwd|jwt|oauth\d?|sso|sessions? tokens?|access tokens?|refresh tokens?|api[ _-]?keys?|secrets?|credentials?|crypto\w*|encrypt\w*|decrypt\w*|hash(?:ing|ed)? (?:the )?passwords?|signing keys?|payments?|stripe|checkout|billing|invoices?|refunds?|revenuecat|purchases?|paywall|permissions?|rbac|roles?)\b", re.I)
SENSITIVE_PATH_RE = re.compile(r"(?i)(?:^|/)(?:auth\w*|security\w*|crypto\w*|payments?\w*|billing\w*|login\w*|passwords?\w*|oauth\w*)(?:\.|/|_)|(?:^|/)[\w-]*(?:auth|crypto|payment|billing|secret|password|token)[\w-]*\.(?:py|ts|js|vue|gd|kt)$")


def sensitive_area(prose, path):
    return bool(SENSITIVE_RE.search(prose or "") or SENSITIVE_PATH_RE.search(path or ""))


TEST_RUNNER_RE = re.compile(r"(?:^|\s)(?:python3?\s+-m\s+pytest|pytest|npx\s+vitest\s+run|vitest\s+run|(?:\S*/)?[Gg]odot4?\s.*gut_cmdln\.gd)\b|gut_cmdln\.gd")


def verify_is_test_runner(verify):
    return bool(TEST_RUNNER_RE.search(" " + (verify or "")))


# ------------------------------------------------------------------------------------------------ seen memory (proposed / duplicate-rejected recently)
def _words(s):
    stop = {"the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "is", "are", "with", "from", "that", "this", "it", "by", "as", "at", "be", "add", "new", "when", "not", "no"}
    return {w for w in re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).split() if len(w) > 2 and w not in stop}


def seen_path(root):
    return os.path.join(root, "feature_seen.jsonl")


def load_seen(root, repo, now, ttl_s=None):
    ttl = ttl_s if ttl_s is not None else int(_num("OVN_QE_FEATURE_SEEN_TTL_H", 72, float) * 3600)
    out = []
    try:
        with open(seen_path(root), encoding="utf-8") as f:
            for ln in f:
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("repo") == repo and now - float(r.get("ts") or 0) < ttl and r.get("title"):
                    out.append(r)
    except OSError:
        pass
    return out


def record_seen(root, repo, rows, now, ttl_s=None):
    """Append (repo, title, file, symbol, why) rows and prune the file to the TTL (best effort)."""
    ttl = ttl_s if ttl_s is not None else int(_num("OVN_QE_FEATURE_SEEN_TTL_H", 72, float) * 3600)
    p = seen_path(root)
    try:
        os.makedirs(root, exist_ok=True)
        keep = []
        try:
            with open(p, encoding="utf-8") as f:
                for ln in f:
                    try:
                        r = json.loads(ln)
                    except ValueError:
                        continue
                    if now - float(r.get("ts") or 0) < ttl:
                        keep.append(r)
        except OSError:
            pass
        for r in rows:
            keep.append({"ts": now, "repo": repo, "title": r["title"], "file": r.get("file", ""), "symbol": r.get("symbol", ""), "why": r.get("why", "")})
        with open(p + ".tmp", "w", encoding="utf-8") as f:
            for r in keep[-400:]:
                f.write(json.dumps(r) + "\n")
        os.replace(p + ".tmp", p)
    except OSError:
        pass


def seen_reason(title, file_, sym, seen):
    """'feature-already-proposed' when a recent proposal has (nearly) this title, or the same file + symbol with heavy word overlap."""
    tw = _words(title)
    if not tw:
        return ""
    for r in seen:
        rw = _words(r.get("title"))
        if not rw:
            continue
        j = len(tw & rw) / float(len(tw | rw))
        if j >= 0.6 or (r.get("file") == file_ and r.get("symbol") == sym and j >= 0.4):
            return "feature-already-proposed"
    return ""


# ------------------------------------------------------------------------------------------------ shadow audit file
def append_jsonl_rotating(path, records, max_bytes=None):
    """Append JSON lines; rotate to <path>.1 first when the file is past max_bytes (OVN_QE_FEATURE_SHADOW_MAX_MB, default 8). Best effort: -> True when written."""
    mb = max_bytes if max_bytes is not None else int(_num("OVN_QE_FEATURE_SHADOW_MAX_MB", 8, float) * 1048576)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        try:
            if os.path.getsize(path) > mb:
                os.replace(path, path + ".1")
        except OSError:
            pass
        with open(path, "a", encoding="utf-8") as f:
            for r in records:
                f.write(json.dumps(r, sort_keys=True) + "\n")
        return True
    except OSError:
        return False
