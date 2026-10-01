#!/usr/bin/env python3
"""acceptance_card.py - gate S0: Qwen drafts an ACCEPTANCE CARD for a backlog item; a deterministic linter + an execution check decide
whether the card is usable (see qa/acceptance_card.README.md, docs/QA_GATES_SPEC.md).

    python3 qa/acceptance_card.py check --repo <name> --base <ref> [--head <ref>] --item "<backlog line>" [--no-record] [--enforce-exit]
            [--card-json FILE]   skip the model, lint+exec a stored card (deterministic; used by tests)
            [--no-exec] [--venv-bin DIR] [--exec-timeout S] [--repair] [--llm-url URL] [--model NAME]
    python3 qa/acceptance_card.py pilot --repo <name> --base <ref> --items-file F [--items-file F2 ...] --out DIR [--limit 30] [...]

The model's output is ADVISORY TEXT. It is never executed until card_lint has proven the verify command is read-only and allow-listed,
and the VERDICT comes from the linter + the execution check, not from the model:

  NA          the item is out of scope (GDScript/Swift/Kotlin/UI/non-code) or states that no change is needed - no model call is made
  UNVERIFIED  model unreachable / timed out / returned unparseable JSON, or the execution check could not run (infra)
  FAIL        card_lint rejected the card (check cannot fail, wrong direction, nonexistent path, vague bullets, unsafe command ...)
  FLAG        card is lint-clean but suspicious: verify ALREADY PASSES at the base ref (vacuous, or the item is already done), or lint flags
  PASS        lint-clean AND the verify command fails at the base ref for a legitimate reason (the card can detect "not done yet")
"""
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402
import card_lint as cl  # noqa: E402

GATE = "acceptance"
DEFAULT_URL = "http://127.0.0.1:4000"
DEFAULT_MODEL = "qwen-dflash-27B"
MAX_TOKENS = 700
LLM_TIMEOUT = 90
EXEC_TIMEOUT = 120
UNSAFE_RULES = {"unsafe-command", "unknown-command", "unsafe-redirect", "shell-unparseable", "shell-compound", "path-absolute", "path-escape",
                "verify-missing", "files-unsafe", "verify-too-long"}


# ------------------------------------------------------------------------------------------------------------ item + repo context
def item_from_args(a):
    """Build the item dict from --item (a backlog line or 'path - description') / --item-file / --item-path+--item-desc."""
    text = a.get("item")
    if a.get("item_file"):
        with open(a["item_file"]) as f:
            text = f.read().strip().splitlines()[0]
    if text:
        it = cl.parse_item_line(text if text.lstrip().startswith("-") else "- [ ] " + text)
        if it:
            return it
        return None
    if a.get("item_path") and a.get("item_desc"):
        return {"raw": a["item_desc"], "tier": None, "path": a["item_path"], "desc": a["item_desc"], "verify": None, "cat": None, "tags": []}
    return None


def git_show(repo, ref, path, limit=6000):
    rc, out, _ = qc.git(repo, "show", "%s:%s" % (ref, path))
    return out[:limit] if rc == 0 else None


def git_ls(repo, ref, subdir):
    rc, out, _ = qc.git(repo, "ls-tree", "--name-only", ref, (subdir.rstrip("/") + "/") if subdir else "")
    return [os.path.basename(x) for x in out.splitlines()] if rc == 0 else []


def repo_context(repo, base, item):
    """Small, deterministic context for the prompt: target file head, sibling names, how tests run and how they import."""
    path = item["path"]
    body = git_show(repo, base, path)
    d = os.path.dirname(path)
    siblings = git_ls(repo, base, d)[:40]
    stem = os.path.splitext(os.path.basename(path))[0]
    # find test dir + pytest config
    rc, tree, _ = qc.git(repo, "ls-tree", "-r", "--name-only", base)
    files = tree.splitlines() if rc == 0 else []
    pytest_ini = next((f for f in files if os.path.basename(f) in ("pytest.ini",) or f.endswith("/pytest.ini")), None)
    pyproject_pytest = None
    tests = [f for f in files if re.search(r"(^|/)tests?/test_[^/]*\.py$", f)]
    test_dir = os.path.dirname(tests[0]) if tests else None
    related = [f for f in tests if stem and stem.replace("test_", "") in os.path.basename(f)][:6]
    tops = {}
    for f in tests[:12]:
        txt = git_show(repo, base, f, 4000) or ""
        for m in re.finditer(r"^from ([A-Za-z_][\w]*)\.", txt, re.M):
            tops[m.group(1)] = tops.get(m.group(1), 0) + 1
    import_root = max(tops, key=tops.get) if tops else None
    run_dir = os.path.dirname(pytest_ini) if pytest_ini else ""
    hint = "python tests run with pytest"
    if run_dir:
        hint = "python tests run as `cd %s && python -m pytest tests/<file>.py -q` (pytest.ini lives in %s/)" % (run_dir, run_dir)
    elif test_dir:
        hint = "python tests run as `python -m pytest %s/<file>.py -q` from the repo root" % test_dir
    if import_root:
        hint += "; modules are imported as `from %s.<pkg>.<mod> import ...` (so `python -c` checks must run from the directory that makes `%s` importable)" % (import_root, import_root)
    return {"target_body": body, "siblings": siblings, "test_hint": hint, "related_tests": related, "test_dir": test_dir, "run_dir": run_dir,
            "import_root": import_root}


SCHEMA_EXAMPLE = {
    "bullets": ["`parse_bool('yes')` returns True", "`parse_bool('0')` returns False", "`parse_bool('maybe')` raises ValueError",
                "the function is importable from `app.utils.parse_bool`"],
    "verify_cmd": "cd backend && python -c \"from app.utils.parse_bool import parse_bool; assert parse_bool('yes') is True; assert parse_bool('0') is False\"",
    "files": ["backend/app/utils/parse_bool.py"],
    "risk_class": "C",
    "needs_human_review": False,
}


def build_prompt(repo, item, ctx, feedback=None):
    body = ctx["target_body"]
    parts = ["REPO: %s" % repo, "HOW TESTS RUN: %s" % ctx["test_hint"],
             "ITEM (file: %s%s):\n%s" % (item["path"], ", tier " + item["tier"] if item.get("tier") else "", item["desc"])]
    if body is None:
        parts.append("TARGET FILE: does not exist yet - this item creates it.")
    else:
        parts.append("TARGET FILE CURRENT CONTENT (first 4000 chars):\n" + body[:4000])
    if ctx["siblings"]:
        parts.append("FILES NEXT TO THE TARGET: " + ", ".join(ctx["siblings"]))
    if ctx["related_tests"]:
        parts.append("EXISTING RELATED TESTS: " + ", ".join(ctx["related_tests"]))
    parts.append(
        "TASK: write an ACCEPTANCE CARD for this item. Reply with ONE JSON object only, exactly these keys:\n"
        "{\"bullets\": [3-7 strings], \"verify_cmd\": string, \"files\": [strings], \"risk_class\": \"A\"|\"B\"|\"C\", \"needs_human_review\": boolean}\n"
        "RULES:\n"
        "1. Each bullet states ONE observable fact a reviewer can check (a returned value, status code, raised exception, symbol present/absent, file created/removed). "
        "Never write 'works correctly/properly/as expected'.\n"
        "2. verify_cmd is ONE shell command run from the repo root on the code BEFORE the change. It MUST exit non-zero before the change and zero after it. "
        "For behaviour, run a pytest file/test the item adds, or `cd <dir> && python -c \"from pkg.mod import f; assert f(...) == ...\"`. "
        "A bare `grep -q` is only acceptable for renames/constants/imports. For deletions use `test ! -e <path>`. "
        "Never use `|| true`, `|| echo`, `; true`, trailing `| tail/head`, curl, network, pip/npm install, rm, or writes outside /dev/null. Max 400 chars.\n"
        "3. files: files that change (at most 5), including the target.\n"
        "4. risk_class: A = auth, billing, paywall, entitlement, migration, secrets, data loss; B = API endpoints, DB models, services; C = pure helpers, tests, docs.\n"
        "5. needs_human_review: true if the item is ambiguous, spans several files or is security sensitive.\n"
        "6. Only reference files, modules and test names that already exist (listed above) or that the ITEM ITSELF creates. Do NOT invent extra test files "
        "or test names: nobody will write them. If the item says to create a test file, verify by running exactly that file.\n"
        "7. `python -c` code must be valid single-line Python made of simple statements joined by `;` (imports, assert, calls). No try/except, class, def, with or for.\n"
        "EXAMPLE (different item): " + json.dumps(SCHEMA_EXAMPLE))
    if feedback:
        parts.append("YOUR PREVIOUS CARD WAS REJECTED BY THE LINTER FOR:\n- " + "\n- ".join(feedback[:6]) + "\nFix exactly those problems and reply with the corrected JSON only.")
    return "\n\n".join(parts)


# ------------------------------------------------------------------------------------------------------------ model call
class ModelError(Exception):
    pass


def _loopback(url):
    h = urllib.parse.urlparse(url).hostname or ""
    return h in ("127.0.0.1", "localhost", "::1")


def call_model(prompt, url, model, key, timeout=LLM_TIMEOUT):
    """One chat completion (temperature 0.1, JSON mode, small max_tokens). Returns (text, meta). Raises ModelError."""
    timeout = float(os.environ.get("QA_ACCEPTANCE_LLM_TIMEOUT", timeout))
    if not _loopback(url):
        raise ModelError("refusing non-loopback model url (gate talks only to the local litellm)")
    body = {"model": model, "temperature": 0.1, "max_tokens": MAX_TOKENS, "response_format": {"type": "json_object"},
            "messages": [{"role": "system", "content": "You are a strict QA engineer. Reply with a single JSON object and nothing else."},
                         {"role": "user", "content": prompt}]}
    req = urllib.request.Request(url.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    try:
        # no proxies: this is a loopback call
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(req, timeout=timeout) as r:
            raw = r.read(2_000_000)
        d = json.loads(raw.decode("utf-8", "replace"))
    except urllib.error.HTTPError as ex:
        raise ModelError("HTTP %s from model" % ex.code)
    except (urllib.error.URLError, OSError, ValueError) as ex:
        raise ModelError("model call failed: %s" % type(ex).__name__)
    try:
        text = d["choices"][0]["message"]["content"] or ""
    except (KeyError, IndexError, TypeError):
        raise ModelError("model response had no choices")
    u = d.get("usage") or {}
    tm = d.get("timings") or {}
    gpu_ms = (tm.get("prompt_ms") or 0) + (tm.get("predicted_ms") or 0)
    meta = {"prompt_tokens": u.get("prompt_tokens"), "completion_tokens": u.get("completion_tokens"),
            "gpu_s": round(gpu_ms / 1000.0, 3) if gpu_ms else None, "wall_s": round(time.time() - t0, 3),
            "finish": (d.get("choices") or [{}])[0].get("finish_reason")}
    return text, meta


def parse_card_json(text):
    """Extract a JSON object from model text (tolerates code fences / leading prose). Returns dict or None."""
    t = (text or "").strip()
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", t)
    for cand in (t, t[t.find("{"):t.rfind("}") + 1] if "{" in t else ""):
        try:
            v = json.loads(cand)
            if isinstance(v, dict):
                return v
        except ValueError:
            continue
    return None


def normalize_card(card):
    """Strip only trivial wrappers (fences/outer backticks, whitespace, case). Never repairs substance."""
    c = dict(card)
    v = c.get("verify_cmd")
    if isinstance(v, str):
        v = v.strip()
        v = re.sub(r"^```(?:bash|sh)?\s*|\s*```$", "", v).strip()
        if v.startswith("`") and v.endswith("`") and v.count("`") == 2:
            v = v[1:-1].strip()
        c["verify_cmd"] = v
    if isinstance(c.get("bullets"), list):
        c["bullets"] = [b.strip() if isinstance(b, str) else b for b in c["bullets"]]
    if isinstance(c.get("risk_class"), str):
        c["risk_class"] = c["risk_class"].strip().upper()[:1]
    return c


def draft_card(repo, item, ctx, url, model, key, repair=False, repo_root=None):
    """Up to 2 requests, sequential: attempt 1; on transport/parse failure retry once; with repair=True a lint-rejected card is retried once with
    the lint errors as feedback. Returns (card|None, lint|None, meta). meta carries tokens/gpu seconds summed over attempts and `error`."""
    meta = {"attempts": 0, "prompt_tokens": 0, "completion_tokens": 0, "gpu_s": 0.0, "wall_s": 0.0, "errors": [], "repaired": False}
    feedback = None
    card = lint = None
    for attempt in (1, 2):
        meta["attempts"] = attempt
        try:
            text, m = call_model(build_prompt(repo, item, ctx, feedback), url, model, key)
        except ModelError as ex:
            meta["errors"].append(str(ex))
            card = None
            continue
        for k in ("prompt_tokens", "completion_tokens", "gpu_s", "wall_s"):
            meta[k] += (m.get(k) or 0)
        parsed = parse_card_json(text)
        if parsed is None:
            meta["errors"].append("model returned unparseable JSON (finish=%s)" % m.get("finish"))
            card = None
            continue
        card = normalize_card(parsed)
        if repo_root is not None:
            lint = cl.lint_card(card, item, repo_root)
        if repair and attempt == 1 and lint is not None and lint["errors"]:
            feedback = ["[%s] %s" % (f["rule"], f["msg"]) for f in lint["errors"]]
            meta["repaired"] = True
            continue
        break
    meta["gpu_s"] = round(meta["gpu_s"], 3)
    meta["wall_s"] = round(meta["wall_s"], 3)
    if card is None:
        meta["error"] = "; ".join(meta["errors"]) or "no card"
    return card, lint, meta


# ------------------------------------------------------------------------------------------------------------ execution check
_PROBE_CACHE = {}


def _exec_env(wt, venv_bin):
    home = tempfile.mkdtemp(prefix="qa-acc-home-")
    path = os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
    if venv_bin:
        path = venv_bin + os.pathsep + path
    # cards say `python`; hosts that only ship python3 (macOS, some boxes) get a shim in the throwaway HOME
    import shutil
    if not shutil.which("python", path=path):
        py3 = shutil.which("python3", path=path)
        if py3:
            shim = os.path.join(home, "shim")
            os.makedirs(shim, exist_ok=True)
            os.symlink(py3, os.path.join(shim, "python"))
            path = shim + os.pathsep + path
    env = {"PATH": path, "HOME": home, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "PYTHONDONTWRITEBYTECODE": "1", "PYTEST_ADDOPTS": "-p no:cacheprovider",
           "CI": "1", "NO_COLOR": "1", "TERM": "dumb", "TMPDIR": home,
           # defence in depth: nothing in a verify may reach the network (lint also forbids it; there is no unprivileged netns on the box)
           "HTTP_PROXY": "http://127.0.0.1:9", "HTTPS_PROXY": "http://127.0.0.1:9", "ALL_PROXY": "http://127.0.0.1:9", "NO_PROXY": "",
           "PIP_NO_INDEX": "1", "NPM_CONFIG_OFFLINE": "true", "ANTHROPIC_API_KEY": "", "OPENAI_API_KEY": ""}
    return env, home


def run_sandboxed(cmd, cwd, env, timeout):
    """bash -c <cmd> in its own process group with nice/ionice, hard timeout (kills the whole group). Returns (rc, output_tail, ms)."""
    t0 = time.time()
    p = subprocess.Popen(qc.cpu_prefix() + ["bash", "-c", cmd], cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
        rc = p.returncode
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        out, _ = p.communicate()
        rc = 124
    text = (out or b"")[-20000:].decode("utf-8", "replace")
    return rc, text, int((time.time() - t0) * 1000)


def _repo_module_exists(wt, top):
    for root, dirs, files in os.walk(wt):
        depth = root[len(wt):].count(os.sep)
        if depth > 3:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".venv", "venv", "__pycache__")]
        if top in dirs or (top + ".py") in files:
            return True
    return False


def classify_outcome(rc, out, wt):
    """('passed'|'failed'|'broken'|'infra', reason). 'failed' = the verify legitimately does not pass yet; 'broken' = the verify command itself is
    defective (SyntaxError/NameError in the check, not in the repo) so it would fail after the change too."""
    if rc == 124:
        return "infra", "timeout"
    if rc == 0:
        return "passed", ""
    if rc == 127 or re.search(r"(^|\n)bash: .*command not found", out):
        return "infra", "command-not-found"
    m = re.search(r"\b(SyntaxError|IndentationError|TabError|NameError)\b: ?([^\n]{0,80})", out)
    if m:
        return "broken", "%s: %s" % (m.group(1), m.group(2).strip())
    m = re.search(r"ModuleNotFoundError: No module named '([\w.]+)'|ImportError: No module named '?([\w.]+)'?", out)
    if m:
        mod = (m.group(1) or m.group(2)).split(".")[0]
        if not _repo_module_exists(wt, mod):
            return "infra", "missing-dependency:" + mod
        return "failed", "import-error-repo-module:" + mod
    if re.search(r"cannot import name|ImportError", out):
        return "failed", "import-error"
    if re.search(r"no tests ran|collected 0 items", out) or rc == 5:
        return "failed", "no-tests-collected"
    if re.search(r"file or directory not found|No such file or directory|can't open file", out):
        return "failed", "target-missing"
    if re.search(r"AssertionError|FAILED|assert ", out):
        return "failed", "assertion"
    return "failed", "nonzero-exit-%s" % rc


def exec_check(repo, ref, cmd, venv_bin=None, timeout=EXEC_TIMEOUT):
    """Run `cmd` in a detached worktree of `ref` (scrubbed env, nice, no network). Returns dict {outcome, reason, rc, ms, tail}."""
    path = qc.repo_dir(repo) if not os.path.isdir(repo) else repo
    if not path:
        return {"outcome": "infra", "reason": "repo-not-found", "rc": None, "ms": 0, "tail": ""}
    linked = []
    home = None
    with qc.worktree(path, ref) as wt:
        if wt is None:
            return {"outcome": "infra", "reason": "worktree-failed", "rc": None, "ms": 0, "tail": ""}
        try:
            env, home = _exec_env(wt, venv_bin)
            # provision node_modules by symlink (removed before the worktree is deleted; never followed by rmtree)
            for nm in ("node_modules", "frontend/node_modules"):
                src = os.path.join(path, nm)
                dst = os.path.join(wt, nm)
                if os.path.isdir(src) and os.path.isdir(os.path.dirname(dst)) and not os.path.exists(dst):
                    os.symlink(src, dst)
                    linked.append(dst)
            if re.search(r"\bpytest\b", cmd):
                key = (venv_bin, env["PATH"])
                if key not in _PROBE_CACHE:
                    rc, out, _ = run_sandboxed("python -m pytest --version", wt, env, 60)
                    _PROBE_CACHE[key] = rc == 0
                if not _PROBE_CACHE[key]:
                    return {"outcome": "infra", "reason": "pytest-unavailable-in-env", "rc": None, "ms": 0, "tail": ""}
            rc, out, ms = run_sandboxed(cmd, wt, env, timeout)
            outcome, reason = classify_outcome(rc, out, wt)
            return {"outcome": outcome, "reason": reason, "rc": rc, "ms": ms, "tail": re.sub(r"\s+", " ", out[-240:]).strip()}
        finally:
            for l in linked:
                try:
                    os.unlink(l)
                except OSError:
                    pass
            if home:
                import shutil
                shutil.rmtree(home, ignore_errors=True)


def guess_venv_bin(repo):
    """Best-effort: <clone>/{.venv,venv,backend/.venv,backend/venv}/bin that has a python and pytest."""
    path = qc.repo_dir(repo)
    if not path:
        return None
    for rel in ("backend/.venv/bin", ".venv/bin", "backend/venv/bin", "venv/bin"):
        d = os.path.join(path, rel)
        if os.path.exists(os.path.join(d, "pytest")) and os.path.exists(os.path.join(d, "python")):
            return d
    return None


# ------------------------------------------------------------------------------------------------------------ the gate
def evaluate_verify(repo, base, head, item, verify, venv_bin, repo_root, do_exec=True, exec_timeout=EXEC_TIMEOUT):
    """Lint + execute one verify command. Returns dict(lint, exec, after)."""
    lint = {"errors": [], "flags": []}
    f, info = cl.lint_verify(verify, item, repo_root)
    lint["errors"] = [x for x in f if x["severity"] == "error"]
    lint["flags"] = [x for x in f if x["severity"] == "flag"]
    lint["info"] = info
    res = {"lint": lint, "exec": None, "after": None}
    if do_exec and not any(x["rule"] in UNSAFE_RULES for x in lint["errors"]):
        res["exec"] = exec_check(repo, base, verify, venv_bin, exec_timeout)
        if head and head != base and res["exec"]["outcome"] != "infra":
            res["after"] = exec_check(repo, head, verify, venv_bin, exec_timeout)
    return res


def decide(item_kind, lint, ex, after, model_flags=()):
    """Map (lint, exec, after) to (verdict, summary)."""
    errs = lint["errors"]
    if errs:
        return "FAIL", "card rejected by lint: " + "; ".join("[%s]" % e["rule"] for e in errs[:5])
    if ex is not None and ex["outcome"] == "infra":
        return "UNVERIFIED", "execution check could not run: %s" % ex["reason"]
    if ex is not None and ex["outcome"] == "broken":
        return "FAIL", "the verify command is itself broken (%s) - it would fail after the change too" % ex["reason"]
    if ex is not None and ex["outcome"] == "failed" and ex["reason"] == "no-tests-collected" and item_kind != "test":
        return "FAIL", "the verify selects no tests at the base ref and the item adds none - it would also select none after the change"
    if ex is not None and ex["outcome"] == "passed":
        return "FLAG", "verify ALREADY PASSES at the base ref - the card is vacuous or the item is already done"
    if after is not None and after["outcome"] in ("failed", "broken"):
        return "FLAG", "verify still fails AFTER the change (%s) - wrong card or incomplete change" % after["reason"]
    if lint["flags"]:
        return "FLAG", "lint flags: " + "; ".join("[%s]" % e["rule"] for e in lint["flags"][:5])
    if ex is None:
        return "FLAG", "lint-clean, but the execution check was not run (--no-exec)"
    return "PASS", "card is lint-clean and the verify fails before the change (%s)" % ex["reason"]


def check(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="acceptance_card.py check")
    ap.add_argument("cmd")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--base", required=True)
    ap.add_argument("--head")
    ap.add_argument("--item")
    ap.add_argument("--item-file")
    ap.add_argument("--item-path")
    ap.add_argument("--item-desc")
    ap.add_argument("--card-json")
    ap.add_argument("--no-exec", action="store_true")
    ap.add_argument("--repair", action="store_true")
    ap.add_argument("--venv-bin")
    ap.add_argument("--exec-timeout", type=int, default=EXEC_TIMEOUT)
    ap.add_argument("--llm-url", default=os.environ.get("LITELLM_BASE", DEFAULT_URL))
    ap.add_argument("--model", default=os.environ.get("OVN_MODEL", DEFAULT_MODEL))
    ap.add_argument("--no-record", action="store_true")
    a = ap.parse_args(argv)
    ref = a.base
    item = item_from_args(vars(a))
    if item is None:
        return qc.verdict("UNVERIFIED", GATE, a.repo, ref, "could not parse an item (need --item '<path> - <description>')")
    rpath = qc.repo_dir(a.repo)
    if not rpath:
        return qc.verdict("UNVERIFIED", GATE, a.repo, ref, "repo clone not found")
    rc, _, _ = qc.git(rpath, "rev-parse", "--verify", "-q", a.base + "^{commit}")
    if rc != 0:
        return qc.verdict("UNVERIFIED", GATE, a.repo, ref, "base ref %s not found" % a.base)
    return evaluate_item(a, item, rpath)


def evaluate_item(a, item, rpath, venv_bin=None):
    """Core per-item evaluation used by `check` and `pilot`. Returns a verdict dict (details hold card/lint/exec/llm)."""
    ref = a.base
    ok, why = cl.eligibility(item)
    details = {"item": {"path": item["path"], "tier": item.get("tier"), "desc": item["desc"][:300]}}
    if not ok:
        return qc.verdict("NA", GATE, a.repo, ref, "out of scope: " + why, details)
    ki = cl.classify_item(item)
    details["item"].update(ki)
    if ki["kind"] == "nochange":
        return qc.verdict("NA", GATE, a.repo, ref, "item says no change is needed - no card drafted", details)
    venv_bin = a.venv_bin or venv_bin or guess_venv_bin(a.repo)
    with qc.worktree(rpath, ref) as wt:
        if wt is None:
            return qc.verdict("UNVERIFIED", GATE, a.repo, ref, "could not create a worktree at the base ref", details)
        # ---- card: stored or drafted
        if a.card_json:
            with open(a.card_json) as f:
                card = normalize_card(json.load(f))
            lint, meta = cl.lint_card(card, item, wt), {"attempts": 0, "source": "card-json"}
        else:
            ctx = repo_context(rpath, ref, item)
            key = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")
            card, lint, meta = draft_card(a.repo, item, ctx, a.llm_url, a.model, key, repair=a.repair, repo_root=wt)
            if card is None:
                details["llm"] = meta
                return qc.verdict("UNVERIFIED", GATE, a.repo, ref, "model gave no usable card: " + meta.get("error", "?"), details)
    details["card"] = card
    details["llm"] = meta
    details["lint"] = {"errors": lint["errors"], "flags": lint["flags"], "info": lint["info"]}
    ex = after = None
    unsafe = any(x["rule"] in UNSAFE_RULES for x in lint["errors"])
    if not a.no_exec and isinstance(card.get("verify_cmd"), str) and not unsafe:
        ev = evaluate_verify(a.repo, ref, a.head, item, card["verify_cmd"], venv_bin, None, True, a.exec_timeout)
        ex, after = ev["exec"], ev["after"]
    details["exec"], details["after"] = ex, after
    v, summary = decide(ki["kind"], lint, ex, after)
    details["risk_class"] = lint["info"].get("risk_class_final")
    details["needs_human_review"] = lint["info"].get("needs_human_review_final")
    return qc.verdict(v, GATE, a.repo, ref, summary, details)


# ------------------------------------------------------------------------------------------------------------ pilot
def load_items(files):
    seen, items = set(), []
    for fp in files:
        with open(fp, errors="replace") as f:
            for line in f:
                if not re.match(r"^\s*-\s*\[ \]", line):
                    continue
                it = cl.parse_item_line(line)
                if not it:
                    continue
                if any("HUMAN" in t.upper() for t in it["tags"]):
                    continue
                k = (it["path"], it["desc"][:100])
                if k in seen:
                    continue
                seen.add(k)
                items.append(it)
    return items


def pct(xs, p):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return None
    return xs[min(len(xs) - 1, int(round((p / 100.0) * (len(xs) - 1))))]


def pilot(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="acceptance_card.py pilot")
    ap.add_argument("cmd")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--base", required=True)
    ap.add_argument("--head")
    ap.add_argument("--items-file", action="append", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=30)
    ap.add_argument("--no-exec", action="store_true")
    ap.add_argument("--repair", action="store_true")
    ap.add_argument("--compare-existing", action="store_true", help="also lint + execute each item's own existing VERIFY for comparison")
    ap.add_argument("--venv-bin")
    ap.add_argument("--exec-timeout", type=int, default=EXEC_TIMEOUT)
    ap.add_argument("--llm-url", default=os.environ.get("LITELLM_BASE", DEFAULT_URL))
    ap.add_argument("--model", default=os.environ.get("OVN_MODEL", DEFAULT_MODEL))
    ap.add_argument("--no-record", action="store_true")
    ap.add_argument("--item")
    ap.add_argument("--item-file")
    ap.add_argument("--item-path")
    ap.add_argument("--item-desc")
    ap.add_argument("--card-json")
    a = ap.parse_args(argv)
    rpath = qc.repo_dir(a.repo)
    if not rpath:
        return qc.verdict("UNVERIFIED", GATE, a.repo, a.base, "repo clone not found")
    os.makedirs(a.out, exist_ok=True)
    items = load_items(a.items_file)
    excluded = {}
    chosen = []
    for it in items:
        ok, why = cl.eligibility(it)
        if not ok:
            excluded[why] = excluded.get(why, 0) + 1
            continue
        if cl.classify_item(it)["kind"] == "nochange":
            excluded["no-change item"] = excluded.get("no-change item", 0) + 1
            continue
        chosen.append(it)
    chosen = chosen[:a.limit]
    venv_bin = a.venv_bin or guess_venv_bin(a.repo)
    recs = []
    out_path = os.path.join(a.out, "cards.jsonl")
    with open(out_path, "w") as fo:
        for n, it in enumerate(chosen, 1):
            a.item = a.item_file = a.item_path = a.item_desc = a.card_json = None
            res = evaluate_item(a, it, rpath, venv_bin)
            rec = {"n": n, "item": {k: it[k] for k in ("path", "tier", "desc", "verify", "cat")}, "result": res}
            if a.compare_existing and it.get("verify"):
                with qc.worktree(rpath, a.base) as wt:
                    rec["existing"] = evaluate_verify(a.repo, a.base, None, it, it["verify"], venv_bin, wt, not a.no_exec, a.exec_timeout) if wt else None
            recs.append(rec)
            fo.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
            fo.flush()
            print("[%2d/%d] %-10s %s" % (n, len(chosen), res["verdict"], it["path"]), file=sys.stderr)
    summ = summarize(recs, excluded, len(items))
    with open(os.path.join(a.out, "summary.json"), "w") as f:
        json.dump(summ, f, indent=1, sort_keys=True)
    return qc.verdict("PASS" if recs else "NA", GATE, a.repo, a.base, "pilot done: %d cards" % len(recs), {"summary": summ, "out": a.out})


def summarize(recs, excluded, n_items):
    vc = {}
    for r in recs:
        vc[r["result"]["verdict"]] = vc.get(r["result"]["verdict"], 0) + 1
    cards = [r for r in recs if r["result"]["details"].get("card")]
    lint_ok = [r for r in cards if not r["result"]["details"]["lint"]["errors"]]
    execd = [r for r in cards if r["result"]["details"].get("exec")]
    failed_before = [r for r in execd if r["result"]["details"]["exec"]["outcome"] == "failed"]
    passed_before = [r for r in execd if r["result"]["details"]["exec"]["outcome"] == "passed"]
    broken = [r for r in execd if r["result"]["details"]["exec"]["outcome"] == "broken"]
    infra = [r for r in execd if r["result"]["details"]["exec"]["outcome"] == "infra"]
    llm = [r["result"]["details"].get("llm") or {} for r in recs]
    gpu = [m.get("gpu_s") for m in llm if m.get("gpu_s")]
    wall = [m.get("wall_s") for m in llm if m.get("wall_s")]
    ptok = [m.get("prompt_tokens") for m in llm if m.get("prompt_tokens")]
    ctok = [m.get("completion_tokens") for m in llm if m.get("completion_tokens")]
    rules = {}
    for r in cards:
        for e in r["result"]["details"]["lint"]["errors"]:
            rules[e["rule"]] = rules.get(e["rule"], 0) + 1
    ex_rec = [r for r in recs if r.get("existing")]
    ex_lint_bad = [r for r in ex_rec if r["existing"]["lint"]["errors"]]
    ex_pass = [r for r in ex_rec if r["existing"]["exec"] and r["existing"]["exec"]["outcome"] == "passed"]
    ex_exec = [r for r in ex_rec if r["existing"]["exec"]]
    ex_rules = {}
    for r in ex_rec:
        for e in r["existing"]["lint"]["errors"]:
            ex_rules[e["rule"]] = ex_rules.get(e["rule"], 0) + 1

    def avg(xs):
        return round(sum(xs) / len(xs), 2) if xs else None
    return {
        "items_scanned": n_items, "excluded": excluded, "cards_attempted": len(recs), "verdicts": vc,
        "cards_generated": len(cards), "model_failures": len(recs) - len(cards) - sum(1 for r in recs if r["result"]["verdict"] == "NA"),
        "lint_pass_rate": round(len(lint_ok) / len(cards), 3) if cards else None, "lint_pass": len(lint_ok),
        "lint_error_rules": rules,
        "exec_ran": len(execd), "fails_before": len(failed_before), "passes_before_vacuous": len(passed_before), "verify_broken": len(broken), "exec_infra": len(infra),
        "fails_before_rate_of_cards": round(len(failed_before) / len(cards), 3) if cards else None,
        "fails_before_rate_of_lint_clean": round(sum(1 for r in lint_ok if r in failed_before) / len(lint_ok), 3) if lint_ok else None,
        "gpu_s_per_card": {"mean": avg(gpu), "p50": pct(gpu, 50), "p90": pct(gpu, 90), "total": round(sum(gpu), 1)},
        "wall_s_per_card": {"mean": avg(wall), "p50": pct(wall, 50), "p90": pct(wall, 90)},
        "prompt_tokens_mean": avg(ptok), "completion_tokens_mean": avg(ctok),
        "existing_verify": {"n": len(ex_rec), "lint_rejected": len(ex_lint_bad), "lint_rules": ex_rules, "exec_ran": len(ex_exec), "passes_before": len(ex_pass)} if ex_rec else None,
    }


def relint(argv):
    """Re-lint and re-decide STORED cards (a pilot's cards.jsonl) with the current linter - no model, no GPU, no re-execution (the stored exec
    outcomes are reused). Used to tune the linter against real model output and to recompute pilot numbers after a lint change."""
    import argparse
    ap = argparse.ArgumentParser(prog="acceptance_card.py relint")
    ap.add_argument("cmd")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--base", required=True)
    ap.add_argument("--cards", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-record", action="store_true")
    a = ap.parse_args(argv)
    rpath = qc.repo_dir(a.repo)
    if not rpath:
        return qc.verdict("UNVERIFIED", GATE, a.repo, a.base, "repo clone not found")
    os.makedirs(a.out, exist_ok=True)
    recs = []
    with qc.worktree(rpath, a.base) as wt:
        if wt is None:
            return qc.verdict("UNVERIFIED", GATE, a.repo, a.base, "could not create a worktree at the base ref")
        with open(a.cards) as f:
            old = [json.loads(l) for l in f if l.strip()]
        for r in old:
            it = dict(r["item"], desc=r["item"]["desc"], tags=[], raw=r["item"]["desc"])
            res = r["result"]
            d = dict(res["details"])
            card = d.get("card")
            ki = cl.classify_item(it)
            if card and ki["kind"] == "nochange":
                res = qc.verdict("NA", GATE, a.repo, a.base, "item is an audit/no-change item - no card drafted", {"item": d.get("item")})
            elif card:
                lint = cl.lint_card(card, it, wt)
                d["lint"] = {"errors": lint["errors"], "flags": lint["flags"], "info": lint["info"]}
                v, summary = decide(ki["kind"], lint, d.get("exec"), d.get("after"))
                d["risk_class"] = lint["info"].get("risk_class_final")
                d["needs_human_review"] = lint["info"].get("needs_human_review_final")
                res = qc.verdict(v, GATE, a.repo, a.base, summary, d)
            nr = {"n": r["n"], "item": r["item"], "result": res}
            if r.get("existing") is not None and it.get("verify"):
                lf, info = cl.lint_verify(it["verify"], it, wt)
                ex = dict(r["existing"])
                ex["lint"] = {"errors": [x for x in lf if x["severity"] == "error"], "flags": [x for x in lf if x["severity"] == "flag"], "info": info}
                nr["existing"] = ex
            recs.append(nr)
    with open(os.path.join(a.out, "cards.jsonl"), "w") as fo:
        for r in recs:
            fo.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
    summ = summarize(recs, {}, len(recs))
    with open(os.path.join(a.out, "summary.json"), "w") as f:
        json.dump(summ, f, indent=1, sort_keys=True)
    return qc.verdict("PASS", GATE, a.repo, a.base, "relint done: %d cards" % len(recs), {"summary": summ, "out": a.out})


def main(argv):
    if not argv or argv[0] not in ("check", "pilot", "relint"):
        print("usage: acceptance_card.py check|pilot|relint ...", file=sys.stderr)
        return 2
    fn = {"pilot": pilot, "relint": relint}.get(argv[0], check)
    return qc.main_guard(GATE, fn, argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
