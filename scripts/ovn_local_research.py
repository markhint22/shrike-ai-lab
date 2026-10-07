#!/usr/bin/env python3
"""scripts/ovn_local_research.py - evidence-grounded roadmap refuel that needs NO Claude (2026-10-05).

Why: the only thing that turns a dry roadmap into [ready] features was the Mac-side `claude -p` research job.
When the Claude account hit its usage limit (resets days later) BOTH active lanes starved for hours. Research
must never depend on one rate-limited account.

How: deterministic collectors read the fleet's own checkout and emit EVIDENCE (file:line + snippet) of real
gaps - routers with no rate limit, public functions no test mentions, swallowed exceptions, save loaders with
no type coercion, TODOs. The local 27B only turns that evidence into well-formed roadmap items; it never
browses or guesses. Every proposed item is then gated by:
  1. ovn_auto_research_validate.py (format, dedupe vs the existing roadmap, 1500-char cap, cites a real path)
  2. a path-existence check: every `path/with.ext` the item names must exist in the checkout, except new test
     files under tests/ (a 'create a test' step legitimately names a file that is not there yet)
Accepted items are appended to roadmap/<repo>.md as [ready] under a header that says they are local-research
drafts, and committed (that one file only). Nothing here touches code.

usage: ovn_local_research.py <repo> [--dry-run] [--force] [--max N] [--evidence-only]
env:   OVN_DIR (default ~/overnight-queue), LITELLM_BASE, LITELLM_MASTER_KEY, OVN_MODEL
exit:  0 always (research is best-effort); prints one summary line.
"""
import datetime
import glob
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

OVN_DIR = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
LITELLM = os.environ.get("LITELLM_BASE", "http://localhost:4000")
LITELLM_KEY = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")
MODEL = os.environ.get("OVN_MODEL", "qwen-dflash-27B")
COOLDOWN_S = int(os.environ.get("OVN_LR_COOLDOWN_H", "4")) * 3600
MAX_PER_DAY = int(os.environ.get("OVN_LR_MAX_PER_DAY", "3"))
MAX_EVIDENCE = 14
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".godot", "dist", "build", "addons", "htmlcov", "alembic"}
PATHISH = re.compile(r"`([\w./-]+\.(?:py|ts|tsx|js|vue|gd|kt|swift|sh|sql|md|json|yml|yaml|toml|html))(?::\d+(?:-\d+)?)?`")


def walk(root, exts):
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            if fn.endswith(exts):
                yield os.path.join(dp, fn)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def rel(root, p):
    return os.path.relpath(p, root)


def is_test_path(r):
    return bool(re.search(r"(^|/)(tests?|__tests__|spec)(/|$)|(^|/)test_[^/]+$|\.(test|spec)\.", r))


# ---------------------------------------------------------------- collectors (each returns [evidence dict])
def py_unlimited_routers(root):
    """Router files that define routes but never apply the rate limiter the repo uses elsewhere."""
    files = [p for p in walk(root, (".py",)) if "/routers/" in p and not is_test_path(rel(root, p))]
    if not any("limiter.limit" in read(p) for p in files):
        return []
    out = []
    for p in files:
        t = read(p)
        routes = [m.start() for m in re.finditer(r"^@router\.(get|post|put|patch|delete)\(", t, re.M)]
        if routes and "limiter.limit" not in t:
            line = t.count("\n", 0, routes[0]) + 1
            out.append({"kind": "no-rate-limit", "file": rel(root, p), "line": line,
                        "text": "%d route(s) and no @limiter.limit (other routers use it)" % len(routes)})
    return out


def py_untested_functions(root):
    """Public top-level functions in app modules that no test file mentions by name."""
    tests = [p for p in walk(root, (".py",)) if is_test_path(rel(root, p))]
    test_blob = "\n".join(read(p) for p in tests)
    out = []
    for p in walk(root, (".py",)):
        r = rel(root, p)
        if is_test_path(r) or "/app/" not in "/" + r or r.endswith("__init__.py"):
            continue
        t = read(p)
        if t.count("\n") < 40:
            continue
        for m in re.finditer(r"^(?:async )?def ([a-z][A-Za-z0-9_]*)\(", t, re.M):
            name = m.group(1)
            if name.startswith("_") or re.search(r"\b%s\b" % re.escape(name), test_blob):
                continue
            body = t[m.end(): m.end() + 900]
            if body.count("\n") < 6:
                continue
            out.append({"kind": "untested-function", "file": r, "line": t.count("\n", 0, m.start()) + 1,
                        "text": "public function `%s` is referenced by no test" % name})
    return out


def py_swallowed(root):
    out = []
    for p in walk(root, (".py",)):
        r = rel(root, p)
        if is_test_path(r):
            continue
        lines = read(p).split("\n")
        for i, l in enumerate(lines[:-1]):
            if re.match(r"\s*except( [\w.(), ]+)?( as \w+)?:\s*$", l) and lines[i + 1].strip() == "pass":
                out.append({"kind": "swallowed-exception", "file": r, "line": i + 1,
                            "text": "%s then bare `pass` (error silently lost)" % l.strip()})
    return out


def todos(root):
    out = []
    for p in walk(root, (".py", ".ts", ".vue", ".gd", ".kt")):
        r = rel(root, p)
        if is_test_path(r):
            continue
        for i, l in enumerate(read(p).split("\n")):
            if re.search(r"\b(TODO|FIXME)\b[: ]", l):
                out.append({"kind": "todo", "file": r, "line": i + 1, "text": l.strip()[:140]})
    return out


def gd_loaders_without_coercion(root):
    """GDScript _load* functions that copy values out of loaded JSON with no int()/float()/str()/bool()."""
    out = []
    for p in walk(root, (".gd",)):
        r = rel(root, p)
        if is_test_path(r):
            continue
        lines = read(p).split("\n")
        i = 0
        while i < len(lines):
            if re.match(r"func _?load\w*\(", lines[i]):
                j = i + 1
                while j < len(lines) and (lines[j].startswith(("\t", " ")) or not lines[j].strip()):
                    m = re.match(r"\s*(_\w+|var \w+)\s*(?::=|=)\s*\w+\.get\(\"(\w+)\"", lines[j])
                    if m and not re.search(r"\b(int|float|str|bool|maxi|mini|clampi)\(", lines[j]) and "is Array" not in lines[j]:
                        out.append({"kind": "uncoerced-load", "file": r, "line": j + 1,
                                    "text": lines[j].strip()[:130] + "  (no int()/clamp on a value read from JSON)"})
                    j += 1
                i = j
            else:
                i += 1
    return out


def gd_untested_classes(root):
    tests = "\n".join(read(p) for p in walk(os.path.join(root, "tests"), (".gd",))) if os.path.isdir(os.path.join(root, "tests")) else ""
    out = []
    for p in walk(os.path.join(root, "scripts"), (".gd",)) if os.path.isdir(os.path.join(root, "scripts")) else []:
        t = read(p)
        m = re.search(r"^class_name (\w+)", t, re.M)
        if not m or t.count("\n") < 40:
            continue
        if not re.search(r"\b%s\b" % m.group(1), tests):
            out.append({"kind": "untested-class", "file": rel(root, p), "line": 1,
                        "text": "class %s (%d lines) has no test referencing it" % (m.group(1), t.count("\n"))})
    return out


COLLECTORS = [py_unlimited_routers, py_swallowed, py_untested_functions, gd_loaders_without_coercion,
              gd_untested_classes, todos]


def collect(root, skip=None):
    """Round-robin across collectors so one noisy kind cannot crowd out the rest.
    skip(e) -> True drops evidence that is already covered (applied before the MAX_EVIDENCE cap, so later evidence is reachable)."""
    per = []
    for fn in COLLECTORS:
        try:
            lst = fn(root)
            per.append([e for e in lst if not (skip and skip(e))])
        except Exception as e:  # a broken collector must not kill the pass
            sys.stderr.write("collector %s failed: %s\n" % (fn.__name__, e))
            per.append([])
    out, i = [], 0
    while len(out) < MAX_EVIDENCE and any(per):
        for lst in per:
            if lst and len(out) < MAX_EVIDENCE:
                out.append(lst.pop(0))
    return out


# ---------------------------------------------------------------- model + gates
def existing_titles(roadmap_text):
    titles = []
    for l in roadmap_text.split("\n"):
        m = re.match(r"^- \[[ x]\] \[P[1-4]\] \[[a-z-]+\] (.{0,90})", l)
        if m:
            titles.append(m.group(1))
    return titles[-60:]


def build_prompt(repo, evidence, titles):
    ev = "\n".join("%d. [%s] %s:%d - %s" % (i + 1, e["kind"], e["file"], e["line"], e["text"]) for i, e in enumerate(evidence))
    ex = "\n".join("- " + t for t in titles)
    return """You are refueling ONE repo's feature roadmap for an autonomous coding fleet (a local 27B model implements items one at a time, each gated by the repo's tests). REPO: %s.
Below is EVIDENCE of real gaps collected by scripts that read the current code. Turn the best 3 to 4 pieces of evidence into roadmap items. Use ONLY the files and lines in the evidence; never invent a path or function.

EVIDENCE:
%s

ALREADY ON THE ROADMAP (do not duplicate):
%s

RULES: (a) NEVER propose adding a standalone helper/predicate/constant, or a test for one, unless the SAME item changes an existing production caller to use it. (b) One item = one behavioural change with a concrete verifiable outcome; no refactor/rename/cleanup unless you name the defect it fixes. (c) Tests live where the repo collects them (iptv_apps: iptv-backend/tests/ only; xlite: tests/ only). (d) Prefer evidence kinds no-rate-limit, uncoerced-load, swallowed-exception, then untested-function/untested-class (at most 1 test-only item), then todo. (e) If the evidence does not justify an item, return fewer; reply NONE if nothing is worth doing.
Reply with ONLY item lines, one per line, exactly:
- [ ] [P<1-4>] [ready] <short title> — <what/why naming the evidence file:line in backticks, e.g. `path/file.py:12`, and the concrete fix + test> {cat: <backend|web|mobile|game|infra|test>; size: <S|M|L>; multifile: <yes|no>; research: none}
Each item under 900 characters, single line.""" % (repo, ev, ex)


def call_model(prompt):
    body = json.dumps({"model": MODEL, "messages": [{"role": "user", "content": prompt}],
                       "temperature": 0.2, "max_tokens": 1800}).encode()
    req = urllib.request.Request(LITELLM + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + LITELLM_KEY})
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.load(r)
    u = d.get("usage") or {}
    return d["choices"][0]["message"]["content"], u.get("prompt_tokens", 0), u.get("completion_tokens", 0)


def path_check(line, root):
    """None if every named path exists (or is a new test file); else the offending path."""
    for pth in PATHISH.findall(line):
        if os.path.exists(os.path.join(root, pth)):
            continue
        if is_test_path(pth):
            continue
        return pth
    return None


def validate(proposed_lines, roadmap_path):
    here = os.path.dirname(os.path.abspath(__file__))
    val = next((p for p in (os.path.join(OVN_DIR, "ovn_auto_research_validate.py"),
                            os.path.join(here, "..", "ovn_auto_research_validate.py")) if os.path.exists(p)), None)
    if not val:
        return None, "validator script not found"
    prop = "/tmp/lr_proposed_%d.md" % os.getpid()
    with open(prop, "w") as f:
        f.write("\n".join(proposed_lines) + "\n")
    try:
        r = subprocess.run([sys.executable, val, prop, roadmap_path, "4"], capture_output=True, text=True, timeout=60)
        return [l for l in r.stdout.split("\n") if l.startswith("- [ ]")], r.stderr.strip()
    finally:
        try:
            os.unlink(prop)
        except OSError:
            pass


def append_and_commit(repo, accepted, n_ev):
    rm = os.path.join(OVN_DIR, "roadmap", repo + ".md")
    hdr = "\n## Local research %s (ovn_local_research.py; %d item(s) drafted by the local 27B from %d pieces of verified code evidence - Claude research was unavailable; review)\n" % (
        datetime.date.today().isoformat(), len(accepted), n_ev)
    with open(rm, "a") as f:
        f.write(hdr + "\n".join(accepted) + "\n")
    subprocess.run(["git", "add", "roadmap/%s.md" % repo], cwd=OVN_DIR, capture_output=True)
    subprocess.run(["git", "commit", "-q", "-m", "chore(roadmap): local research refuel for %s - %d evidence-grounded item(s) (no Claude)" % (repo, len(accepted)),
                    "--", "roadmap/%s.md" % repo], cwd=OVN_DIR, capture_output=True)


def main(argv):
    if len(argv) < 2 or argv[1].startswith("-"):
        print("usage: ovn_local_research.py <repo> [--dry-run] [--force] [--evidence-only]")
        return 0
    repo, flags = argv[1], set(argv[2:])
    if os.environ.get("OVN_LOCAL_RESEARCH", "on") == "off":
        print("%s: OVN_LOCAL_RESEARCH=off - skip" % repo)
        return 0
    root = os.path.join(OVN_DIR, "repos", repo)
    rm = os.path.join(OVN_DIR, "roadmap", repo + ".md")
    state = os.path.join(OVN_DIR, "state")
    os.makedirs(state, exist_ok=True)
    if not os.path.isdir(root) or not os.path.isfile(rm):
        print("%s: no checkout or roadmap - skip" % repo)
        return 0
    roadmap_text = read(rm)
    marker = os.path.join(state, "local_research_%s" % repo)
    cnt = os.path.join(state, "local_research_count_%s_%s" % (repo, datetime.date.today().isoformat()))
    if "--force" not in flags:
        if re.search(r"^- \[ \] \[P[1-4]\] \[ready\]", roadmap_text, re.M):
            print("%s: already has a [ready] feature - skip" % repo)
            return 0
        try:
            if time.time() - float(read(marker) or 0) < COOLDOWN_S:
                print("%s: in cooldown - skip" % repo)
                return 0
        except ValueError:
            pass
        if int(read(cnt) or 0) >= MAX_PER_DAY:
            print("%s: daily cap reached - skip" % repo)
            return 0
    # 2026-10-07: evidence whose file the roadmap already names (any status) is covered - without this the same top evidence is re-proposed every pass,
    # the validator drops the duplicates, and the rest of the evidence is never reached.
    def covered(e):
        return e["file"] in roadmap_text
    evidence = collect(root, skip=covered)
    if "--evidence-only" in flags:
        for e in evidence:
            print("[%s] %s:%d %s" % (e["kind"], e["file"], e["line"], e["text"]))
        return 0
    if len(evidence) < 2:
        print("%s: only %d piece(s) of evidence - nothing to research" % (repo, len(evidence)))
        open(marker, "w").write(str(time.time()))
        return 0
    try:
        reply, ti, to = call_model(build_prompt(repo, evidence, existing_titles(roadmap_text)))
    except Exception as e:
        print("%s: model call failed (%s) - no cooldown set, will retry" % (repo, str(e)[:120]))
        return 0
    try:
        subprocess.run(["bash", os.path.join(OVN_DIR, "scripts", "ovn_log_tokens.sh"), "local-research", repo, str(ti), str(to)],
                       capture_output=True, timeout=20)
    except Exception:
        pass
    proposed = [l.strip() for l in reply.split("\n") if l.strip().startswith("- [ ]")]
    accepted, err = validate(proposed, rm)
    if accepted is None:
        print("%s: %s - aborting" % (repo, err))
        return 0
    kept, rejected = [], []
    for l in accepted:
        bad = path_check(l, root)
        (rejected if bad else kept).append((l, bad))
    kept = [l for l, _ in kept]
    for l, bad in rejected:
        sys.stderr.write("reject: names a path that does not exist (%s): %s\n" % (bad, l[:90]))
    if "--dry-run" in flags:
        print("%s: DRY-RUN %d proposed, %d validated, %d after path check" % (repo, len(proposed), len(accepted), len(kept)))
        for l in kept:
            print("  " + l[:160])
        return 0
    open(marker, "w").write(str(time.time()))
    open(cnt, "w").write(str(int(read(cnt) or 0) + 1))
    if not kept:
        print("%s: 0 items accepted (%d proposed, %d validated) - cooldown set" % (repo, len(proposed), len(accepted)))
        return 0
    append_and_commit(repo, kept, len(evidence))
    try:
        with open(os.path.join(state, "alerts.log"), "a") as f:
            f.write("[%s] warn | local-research:%s | refueled %d [ready] item(s) from local-27B drafts (Claude not needed)\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), repo, len(kept)))
    except OSError:
        pass
    print("%s: APPENDED %d local-research [ready] item(s) (%d proposed)" % (repo, len(kept), len(proposed)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
