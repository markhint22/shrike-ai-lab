#!/usr/bin/env python3
"""gate_reviewer.py - S8 (Wave 2, ADVISORY): a local-Qwen code REVIEWER whose every finding is mechanically verified and then attacked by a
second Qwen call (the REFUTER). See qa/gate_reviewer.README.md and docs/QA_GATES_SPEC.md.

    python3 qa/gate_reviewer.py check --repo <name|path> --base <ref> --head <ref> [--no-record] [--enforce-exit]
            [--llm-url URL] [--model NAME] [--trace FILE]

qa_run_shadow.sh runs every qa/gate_*.py over each merged range, so this file is picked up with no wiring.

Pipeline (the model proposes, the HARNESS disposes):
  1. diff of NON-test, NON-generated, NON-lockfile product code (py + js/ts/vue by default), cut into chunks per file under a hard token budget
     (a request is <= ~12k of the 65k context). Files too big to review are SKIPPED and listed - never silently dropped.
  2. per chunk, ask Qwen for at most 3 concrete defects as strict JSON {file,line,quote,claim,severity}; `quote` must be a verbatim piece of ONE
     ADDED line.
  3. harness verification (anti-hallucination): schema ok, file is the chunk's file, `line` lies inside a hunk of that file, and the quote exists
     verbatim in an ADDED line of THAT hunk. Anything else is dropped and counted.
  4. REFUTER: a second call sees only the claim + the quote + +-20 lines of the head file around it and is asked to refute the claim. Refuted
     is the DEFAULT whenever the answer is missing, unparseable or not a boolean. Only survivors are recorded.
  5. verdict: FLAG when something survives, PASS when the whole range was reviewed and nothing survived, NA for docs/test-only (or nothing
     reviewable) diffs, UNVERIFIED when the model is unreachable/slow/garbled or the range was only partly reviewed. NEVER FAIL, never exit
     non-zero: this gate is advisory and influences nothing until qa_reviewer_label.py shows >= 50 labelled findings at >= 60% precision.

Counts (proposed / verified / survived, plus drop reasons) are always in details so precision can be measured. Recorded text is redacted.
Hard limits: a total wall deadline (QA_REVIEWER_DEADLINE, default 120 s), a per-call cap, a call-count cap and a circuit breaker (the first
failed/hung call marks the model dead for this run - nothing waits on it twice). Loopback model URL only. One request at a time.
"""
import hashlib
import json
import os
import re
import signal
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402
import acceptance_card as ac  # noqa: E402  (REUSED: call_model = loopback-only litellm client, parse_card_json)
import gate_antigaming as ga  # noqa: E402  (REUSED: test/generated/lockfile path classification)

GATE = "reviewer"
DEFAULT_URL = "http://127.0.0.1:4000"
DEFAULT_MODEL = "qwen-dflash-27B"
MAX_REQUEST_TOKENS = 12000        # hard ceiling for ONE request (the model context is 65,536 in total)
COMPLETION_TOKENS = 700           # what acceptance_card.call_model asks for
CHUNK_DIFF_TOKENS = 8500          # rendered diff per chunk; + prompt text + completion stays well under MAX_REQUEST_TOKENS
FILE_DIFF_TOKENS = 17000          # a file whose whole diff is bigger than this is skipped as huge
MAX_PER_CHUNK = 3
MAX_FILES = 300
MIN_QUOTE = 6
SEVERITIES = ("low", "medium", "high")
CTX_LINES = 20
REVIEW_LANGS_DEFAULT = "py,js,kt,gd"    # 2026-10-03: Kotlin (Chickadee Android) and GDScript (xlite) enabled - xlite was 100% NA; swift stays off until measured


def est_tokens(s):
    """Deliberately pessimistic (dense code is ~2.8 chars/token), so a chunk never overflows the budget."""
    return int(len(s) / 2.8) + 1


# ------------------------------------------------------------------------------------------------------------ redaction
_KV_RE = re.compile(r"(?i)(\b[\w.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|apikey|auth|credential)s?\b[\"']?\s*[:=]\s*[\"']?)"
                    r"([^\s\"',;)]{4,})")
_STANDALONE_RES = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)"),
    re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    re.compile(r"\b(?:sk|pk|rk)[-_](?:live|test|proj|ant|or|[A-Za-z0-9])[-_A-Za-z0-9]{14,}"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}"),
    re.compile(r"(?=[A-Za-z0-9+/=_-]*\d)(?=[A-Za-z0-9+/=_-]*[A-Za-z])[A-Za-z0-9+/=_-]{32,}"),
]
_URL_CRED_RE = re.compile(r"(://[^/\s:@]+:)[^@\s/]{3,}(@)")


def secret_values(text):
    """Literal secret-looking values found in CODE text (the added lines of a chunk): a finding's claim may repeat one in prose, where no
    `name = value` shape marks it, so redaction also replaces every literal occurrence of a value seen in the code."""
    vals = set()
    for m in _KV_RE.finditer(text or ""):
        vals.add(m.group(2))
    for rx in _STANDALONE_RES:
        for m in rx.finditer(text or ""):
            vals.add(m.group(0))
    return set(v for v in vals if len(v) >= 4)


def redact(s, limit=400, known=()):
    s = str(s if s is not None else "")
    for v in sorted(known, key=len, reverse=True):
        s = s.replace(v, "<redacted>")
    for rx in _STANDALONE_RES:
        s = rx.sub("<redacted>", s)
    s = _URL_CRED_RE.sub(r"\1<redacted>\2", s)
    s = _KV_RE.sub(r"\1<redacted>", s)
    return s[:limit]


# ------------------------------------------------------------------------------------------------------------ diff parsing
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def parse_diff(text):
    """Unified diff -> {path: [hunk]} with hunk = {start, end, lines:[(kind, new_lineno|None, text)]}. Counter-driven (an added line that itself
    starts with '++ ' cannot be mistaken for a file header). Deleted/binary files have no '+++ b/...' target and are ignored."""
    files = {}
    cur = None
    lines = text.split("\n")
    i, n = 0, len(lines)
    while i < n:
        raw = lines[i]
        if raw.startswith("diff --git "):
            cur = None
        elif raw.startswith("+++ "):
            p = raw[4:].split("\t")[0]
            if p == "/dev/null" or p.startswith('"'):
                cur = None
            else:
                cur = p[2:] if p.startswith("b/") else p
                files.setdefault(cur, [])
        elif raw.startswith("@@") and cur is not None:
            m = HUNK_RE.match(raw)
            if m:
                rem_old = int(m.group(2)) if m.group(2) is not None else 1
                nstart = int(m.group(3))
                rem_new = int(m.group(4)) if m.group(4) is not None else 1
                hunk = {"start": nstart, "end": nstart + rem_new - 1, "lines": []}
                ln = nstart
                i += 1
                while i < n and (rem_old > 0 or rem_new > 0):
                    t = lines[i]
                    c = t[:1]
                    if c == "+":
                        hunk["lines"].append(("+", ln, t[1:]))
                        ln += 1
                        rem_new -= 1
                    elif c == "-":
                        hunk["lines"].append(("-", None, t[1:]))
                        rem_old -= 1
                    elif c == " " or t == "":
                        hunk["lines"].append((" ", ln, t[1:]))
                        ln += 1
                        rem_old -= 1
                        rem_new -= 1
                    elif c == "\\":
                        pass
                    else:
                        break
                    i += 1
                files[cur].append(hunk)
                continue
        i += 1
    return files


def hunk_added(h):
    return [(no, t) for k, no, t in h["lines"] if k == "+"]


def render_hunk(h, width=300):
    out = ["@@ new lines %d-%d @@" % (h["start"], h["end"])]
    for k, no, t in h["lines"]:
        t = t[:width]
        out.append("%5s %s %s" % (no if no is not None else "", k, t))
    return "\n".join(out)


GENERATED_RE = re.compile(r"(auto-?generated|do not edit|generated by|@generated)", re.I)
GENERATED_PATH_RE = re.compile(r"(_pb2(_grpc)?\.py$|\.g\.(dart|ts)$|\.generated\.|(^|/)generated/|\.min\.|(^|/)gen/)")


def classify_files(files, langs):
    """-> (reviewable {path: hunks}, skipped [{file, reason}])."""
    ok, skipped = {}, []
    for p, hunks in sorted(files.items()):
        lang = ga.lang_of(p)
        if lang is None or ga.ignorable(p) or p.endswith((".lock", "package-lock.json")):
            continue                                             # docs/data/lockfiles/vendored: not product code, not worth listing
        if ga.is_test_path(p):
            continue
        if GENERATED_PATH_RE.search(p):
            skipped.append({"file": p, "reason": "generated"})
            continue
        if lang not in langs:
            skipped.append({"file": p, "reason": "lang-not-enabled(%s)" % lang})
            continue
        head_txt = "\n".join(t for h in hunks[:1] for k, _, t in h["lines"][:6])
        if GENERATED_RE.search(head_txt) and any(h["start"] <= 5 for h in hunks[:1]):
            skipped.append({"file": p, "reason": "generated"})
            continue
        if not any(t.strip() for h in hunks for _, t in hunk_added(h)):
            continue                                             # pure deletions / whitespace only: nothing added to review
        ok[p] = hunks
    return ok, skipped


def build_chunks(path, hunks, budget=CHUNK_DIFF_TOKENS):
    """Greedy grouping of whole hunks under the token budget. -> (chunks [{path, hunks, text}], skip_reason|None)."""
    rendered = [(h, render_hunk(h)) for h in hunks if hunk_added(h)]
    total = sum(est_tokens(r) for _, r in rendered)
    if total > FILE_DIFF_TOKENS:
        return [], "huge(~%dk tokens of diff)" % (total // 1000)
    if any(est_tokens(r) > budget for _, r in rendered):
        return [], "single-hunk-over-budget"
    chunks, cur, cur_t = [], [], 0
    for h, r in rendered:
        t = est_tokens(r)
        if cur and cur_t + t > budget:
            chunks.append(cur)
            cur, cur_t = [], 0
        cur.append((h, r))
        cur_t += t
    if cur:
        chunks.append(cur)
    return [{"path": path, "hunks": [h for h, _ in c], "text": "\n".join(r for _, r in c)} for c in chunks], None


# ------------------------------------------------------------------------------------------------------------ severity floor + patterns
# 2026-10-03: the shadow reviewer labelled billwatch's UNAUTHENTICATED POST /reset-password (account takeover) 'medium'. A label is not evidence, but these
# two families are never below 'high': a verified finding whose claim/quote reads as an auth bypass or a secret exposure is raised (and marked).
AUTH_BYPASS_RE = re.compile(r"(?i)\bunauthenticated\W+(?:\w+\W+){0,3}(?:endpoint|route|handler|request|caller|user|client|access|api|view|call|post|put|delete|patch)|"
                            r"(?:endpoint|route|handler|api|view)\W+(?:\w+\W+){0,4}(?:is|are|lacks?|has|with)?\W*(?:unauthenticated|unauthori[sz]ed access|no auth\w*|without auth\w*)|"
                            r"authenticat\w*\W+(?:check\W+)?(?:is\W+)?(?:missing|absent|not required|bypass\w*)|"
                            r"(?:without|missing|lacks?|skips?|bypass\w*)\W+(?:any\W+|an?\W+|the\W+)?(?:auth\w*\W+(?:check|guard|dependency|middleware|required)|login|token\W+(?:check|verification|validation)|"
                            r"credential\W+check|permission\W+check|ownership|owner\W+check|admin\W+check)|"
                            r"no\W+(?:auth\w*\W+(?:check|guard|dependency|middleware|required)|ownership\W+check|owner\W+check|admin\W+check|permission\W+check)|"
                            r"anyone (?:can|could)|any (?:user|caller|client) can|account takeover|privilege escalation|"
                            r"auth(?:orization|entication)? (?:check|guard|dependency) (?:removed|dropped|deleted)|is_admin\W*(?:=|or)\W*true")
SECRET_EXPOSURE_RE = re.compile(r"(?i)hard-?coded\W+(?:\w+\W+){0,2}(?:secret|password|passwd|api\W?key|token|credential\w*|private\W+key|encryption\W+key)|"
                                r"(?:secret|password|api\W?key|token|credential\w*|private\W+key)s?\W+(?:is|are|gets?|was)?\W*(?:logged|leak\w*|expos\w+|returned in|"
                                r"sent to the client|committed|printed)|(?:leak\w*|expos\w+|logs?)\W+(?:the\W+|a\W+|an\W+)?(?:secret|password|api\W?key|token|credential\w*)|"
                                r"default (?:secret|password|encryption|signing)\W+(?:\w+\W+){0,2}key|secret\W+(?:default|fallback)")
# a claim that says the behaviour is intended / confined to tests / debug-only is not a floor candidate
BENIGN_CLAIM_RE = re.compile(r"(?i)as designed|by design|intended|only in tests?|in tests? only|test[- ](?:only|code|fixture)|debug[- ]level|at debug|"
                             r"\bno\b[^.]{0,30}\berrors?\b|not (?:logged|exposed|leaked)")
_SEV_ORDER = {"low": 0, "medium": 1, "high": 2}


def severity_floor(claim, quote, sev):
    """-> (severity, raised: bool). Never lowers a severity."""
    txt = "%s\n%s" % (claim or "", quote or "")
    if BENIGN_CLAIM_RE.search(claim or ""):
        return sev, False
    if (AUTH_BYPASS_RE.search(txt) or SECRET_EXPOSURE_RE.search(txt)) and _SEV_ORDER.get(sev, 1) < _SEV_ORDER["high"]:
        return "high", True
    return sev, False


ROUTE_RE = re.compile(r"""^\s*@\s*[\w.]+\.(?:post|put|patch|delete)\(\s*[rf]?["']([^"']*)["']""")
SENSITIVE_ROUTE_RE = re.compile(r"(?i)reset[-_/]?pass|change[-_/]?pass|set[-_/]?pass|forgot[-_/]?pass|delete[-_/]?(?:account|user)|/admin\b|impersonat|"
                                r"promote|make[-_/]?admin|grant|revoke|api[-_/]?key|/users?/\{?\w*\}?/(?:role|password|email)")
AUTHISH_RE = re.compile(r"(?i)current_user|get_user|require_\w+|\bauth\w*|\bAuthorization\b|HTTPBearer|oauth2|Security\(|verify_\w*token|"
                        r"\b\w*token\w*\s*:|\bcredentials\b|permission|admin|login_required|jwt|api_key|x_api_key|\bsession\b|\bcode\s*:|\botp\b")
DEF_RE = re.compile(r"^\s*(?:async\s+)?def\s+\w+\s*\(", re.M)
SECRET_DEFAULT_RE = re.compile(r"""(?ix)^\s*[\w.]*(?:secret|password|passwd|token|api[_-]?key|encryption[_-]?key|private[_-]?key|signing[_-]?key)\w*
                                   \s*(?::\s*[\w\[\], |]+)?=\s*(?:[\w.]+\(\s*(?:[^()"']*,\s*)?(?:default\s*=\s*)?)?["']([^"']{8,})["']""")
WEAK_SECRET_VALUE_RE = re.compile(r"(?i)change|changeme|default|\bdev\b|local|example|placeholder|insecure|not-?secret|todo|your[-_]|test")


def pattern_findings(path, hunks):
    """Deterministic, model-free findings for the two families whose cost of a miss is highest. Only ADDED lines are considered, so these are about
    THIS change. Each is {file,line,quote,claim,severity='high',source='pattern'}. Python/JS route decorators and secret-looking defaults only."""
    out = []
    lang = ga.lang_of(path)
    if lang not in ("py", "js", "kt"):
        return out
    for h in hunks:
        added = hunk_added(h)
        by_line = dict(added)
        for no, t in added:
            m = ROUTE_RE.match(t) if lang == "py" else None
            if m and SENSITIVE_ROUTE_RE.search(m.group(1)):
                sig = [t]
                j = no + 1
                while j in by_line and j < no + 25:
                    sig.append(by_line[j])
                    if re.search(r"\)\s*(?:->[^:]*)?:\s*$", by_line[j]) and not by_line[j].lstrip().startswith("@"):
                        break
                    j += 1
                blob = "\n".join(sig)
                if DEF_RE.search(blob) and not AUTHISH_RE.search(blob):
                    out.append({"file": path, "line": no, "quote": t.strip(), "severity": "high", "source": "pattern",
                                "claim": "new route %s is added with no authentication, authorization or token parameter in its signature "
                                         "(anyone who can reach it can use it)" % m.group(1)})
            m2 = SECRET_DEFAULT_RE.match(t)
            if m2 and WEAK_SECRET_VALUE_RE.search(m2.group(1)) and not re.search(r"(?i)example|sample|test|fixture", path):
                out.append({"file": path, "line": no, "quote": t.strip(), "severity": "high", "source": "pattern",
                            "claim": "hardcoded default secret in code: if the environment variable is unset the service runs with a publicly known value"})
    return out


# ------------------------------------------------------------------------------------------------------------ prompts
REVIEW_EXAMPLE = {"findings": [{"file": "app/api/items.py", "line": 42, "quote": "if user.id = item.owner_id:",
                                "claim": "assignment instead of comparison, so the owner check is a syntax error / always true", "severity": "high"}]}


def review_prompt(repo, path, text):
    return (
        "REPO: %s\nFILE: %s\n\nDIFF (only the file's changed hunks). Each line is `<new line number> <+ added | space context | - removed> <code>`:\n%s\n\n"
        "TASK: review ONLY the ADDED ('+') lines for concrete defects that would cause wrong behaviour, a crash, data loss or a security hole: "
        "wrong condition / off-by-one / inverted logic, missing authorization or input validation on a new path, swallowed or unhandled errors, "
        "a deleted guard, wrong API use, resource leaks, secrets in code.\n"
        "Reply with ONE JSON object only: {\"findings\": [ {\"file\": string, \"line\": integer, \"quote\": string, \"claim\": string, \"severity\": \"low\"|\"medium\"|\"high\"} ]}\n"
        "RULES:\n"
        "1. At most %d findings. Return {\"findings\": []} when nothing is clearly wrong - that is the expected answer for most diffs.\n"
        "2. `quote` is ONE '+' line copied VERBATIM (no line number, no leading '+'), `line` is that line's number as printed. `file` is exactly %s.\n"
        "3. `claim` is one sentence naming the exact failing input or condition. No style, naming, formatting, missing docs/tests/comments, performance "
        "guesses or 'could potentially' speculation. If you cannot point at the failing case, do not report it.\n"
        "EXAMPLE (different code): %s" % (repo, path, text, MAX_PER_CHUNK, path, json.dumps(REVIEW_EXAMPLE)))


def refute_prompt(repo, f, ctx):
    return (
        "REPO: %s\nFILE: %s\n\nA reviewer claims a defect at line %d, quoting: %s\nCLAIM: %s\n\nCODE AROUND IT (the version after the change; "
        "`<line number> <code>`):\n%s\n\n"
        "TASK: you are the REFUTER. Try to show the claim is WRONG using only the code shown. The claim is refuted if the code already handles the "
        "case, the quoted line does not behave as claimed, the failing input is impossible, the issue is only style or speculation, or you cannot "
        "confirm the failure from the code shown. When unsure, refuted is true. Only answer refuted=false if you can name the concrete input and "
        "the wrong result.\n"
        "Reply with ONE JSON object only: {\"refuted\": true|false, \"reason\": \"one sentence\"}"
        % (repo, f["file"], f["line"], json.dumps(f["quote"]), f["claim"], ctx))


# ------------------------------------------------------------------------------------------------------------ model budget + breaker
class Budget:
    """Same contract as manual_locator.Budget: a call cap, a wall deadline for the WHOLE run and a circuit breaker - the first failed/hung call
    (None) marks the model dead, so a hung model costs one call-timeout, never one per chunk."""

    def __init__(self, fn, limit, deadline_s, call_timeout):
        self.fn, self.limit, self.calls, self.dead = fn, limit, 0, False
        self.deadline_s, self.call_timeout = deadline_s, call_timeout
        self.t0 = time.time()
        self.stopped = ""           # why no more calls were made: dead | deadline | cap
        self.usage = {"prompt_tokens": 0, "completion_tokens": 0, "gpu_s": 0.0}

    def remaining(self):
        return self.deadline_s - (time.time() - self.t0)

    def __call__(self, prompt):
        if self.dead:
            self.stopped = self.stopped or "dead"
            return None
        if self.calls >= self.limit:
            self.stopped = self.stopped or "cap"
            return None
        if self.remaining() < 5:
            self.stopped = self.stopped or "deadline"
            return None
        self.calls += 1
        try:
            res = self.fn(prompt, max(2.0, min(self.call_timeout, self.remaining() - 2)), self.usage)
        except Exception:  # noqa: BLE001
            res = None
        if res is None:
            self.dead = True
            self.stopped = "dead"
        return res


class _Alarm(Exception):
    pass


def _on_alarm(_s, _f):
    raise _Alarm()


def make_model_fn(url, model):
    key = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")

    def fn(prompt, timeout, usage):
        """One acceptance_card.call_model request -> text, or None on ANY problem. SIGALRM backs up the socket timeout: a server that trickles
        bytes forever must not outlive the run deadline."""
        old_sig = old_env = None
        had_env = "QA_ACCEPTANCE_LLM_TIMEOUT" in os.environ
        old_env = os.environ.get("QA_ACCEPTANCE_LLM_TIMEOUT")
        os.environ["QA_ACCEPTANCE_LLM_TIMEOUT"] = str(timeout)     # call_model lets this env var override its argument; pin it to OUR cap
        try:
            try:
                old_sig = signal.signal(signal.SIGALRM, _on_alarm)
                signal.alarm(int(timeout) + 5)
            except ValueError:
                old_sig = None
            text, meta = ac.call_model(prompt, url, model, key, timeout)
            for k in ("prompt_tokens", "completion_tokens", "gpu_s"):
                usage[k] += meta.get(k) or 0
            return re.sub(r"(?s)<think>.*?</think>", "", text or "")
        except Exception:  # noqa: BLE001 - ModelError, timeout, alarm, refused
            return None
        finally:
            try:
                signal.alarm(0)
                if old_sig is not None:
                    signal.signal(signal.SIGALRM, old_sig)
            except Exception:  # noqa: BLE001
                pass
            if had_env:
                os.environ["QA_ACCEPTANCE_LLM_TIMEOUT"] = old_env
            else:
                os.environ.pop("QA_ACCEPTANCE_LLM_TIMEOUT", None)
    return fn


# ------------------------------------------------------------------------------------------------------------ harness verification
def verify_finding(f, chunk):
    """Mechanical anti-hallucination checks. -> (normalized|None, drop_reason|None)."""
    if not isinstance(f, dict):
        return None, "malformed"
    q, claim, sev = f.get("quote"), f.get("claim"), f.get("severity")
    ln, fl = f.get("line"), f.get("file")
    if isinstance(ln, str) and ln.strip().isdigit():
        ln = int(ln.strip())
    if isinstance(ln, bool) or not isinstance(ln, int):
        return None, "malformed"
    if not (isinstance(q, str) and isinstance(claim, str) and isinstance(fl, str)):
        return None, "malformed"
    claim = claim.strip()
    if not claim or len(claim) > 600:
        return None, "malformed"
    sev = sev.strip().lower() if isinstance(sev, str) else ""
    sev_defaulted = sev not in SEVERITIES   # 2026-10-02: the real model returned a correct finding WITHOUT `severity`; severity is a label, not evidence,
    if sev_defaulted:                       # so a missing/unknown one is coerced to "medium" (and counted) instead of discarding a verified finding
        sev = "medium"
    fl = fl.strip()
    fl = fl[2:] if fl.startswith(("a/", "b/")) else (fl[2:] if fl.startswith("./") else fl)
    if fl != chunk["path"]:
        return None, "wrong_file"
    if "\n" in q or "\r" in q:
        return None, "malformed"
    qs = q.strip()
    if len(qs) < MIN_QUOTE or not re.search(r"[A-Za-z0-9_]", qs):
        return None, "quote_too_short"
    hit = None
    for h in chunk["hunks"]:
        if h["start"] <= ln <= h["end"]:                  # the line the model cites must be INSIDE a hunk ...
            hit = h
            break
    if hit is None:
        return None, "line_outside_hunk"
    cands = [no for no, t in hunk_added(hit) if qs in t]  # ... and the quote must be verbatim in an ADDED line of that same hunk
    if not cands:
        return None, "quote_not_found"
    real = min(cands, key=lambda x: abs(x - ln))
    return {"file": chunk["path"], "line": real, "quote": qs, "claim": claim, "severity": sev, "sev_defaulted": sev_defaulted}, None


def context_block(head_lines, line):
    lo, hi = max(1, line - CTX_LINES), min(len(head_lines), line + CTX_LINES)
    return "\n".join("%5d %s" % (i, head_lines[i - 1][:300]) for i in range(lo, hi + 1))


def parse_refute(text):
    """-> (refuted bool, reason str). Refuted is the default for anything but an explicit boolean false."""
    d = ac.parse_card_json(text or "")
    if not isinstance(d, dict) or not isinstance(d.get("refuted"), bool):
        return True, "unparseable-or-missing-verdict"
    return d["refuted"], str(d.get("reason") or "")[:300]


def finding_id(repo, head, f):
    return hashlib.sha1(("%s|%s|%s|%s" % (repo, head, f["file"], f["quote"])).encode("utf-8", "replace")).hexdigest()[:12]


# ------------------------------------------------------------------------------------------------------------ the gate
def parse_args(argv):
    a = {"repo": None, "base": None, "head": None, "llm_url": None, "model": None, "trace": None}
    i = 0
    while i < len(argv):
        k = argv[i]
        if k in ("--repo", "--base", "--head", "--llm-url", "--model", "--trace") and i + 1 < len(argv):
            a[k[2:].replace("-", "_")] = argv[i + 1]
            i += 2
        else:
            i += 1
    return a


def env_num(name, default, cast=float):
    try:
        return cast(os.environ.get(name, default))
    except (TypeError, ValueError):
        return cast(default)


def check(argv, model_fn=None):
    a = parse_args(argv)
    if not argv or argv[0] != "check" or not (a["repo"] and a["base"] and a["head"]):
        return qc.verdict("UNVERIFIED", GATE, a["repo"] or "?", "?", "usage: gate_reviewer.py check --repo R --base B --head H")
    name = a["repo"]
    rd = name if os.path.isdir(name) else qc.repo_dir(name)
    name = os.path.basename(name.rstrip("/")) if os.path.isdir(name) else name
    ref = "%s..%s" % (a["base"], a["head"])
    if qc.mode(GATE) == "off":
        return qc.verdict("NA", GATE, name, ref, "gate mode is off")
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, name, ref, "no clone found for repo")
    qc.ensure_commits(rd, (a["base"], a["head"]), wait=env_num("QA_FETCH_WAIT", "15"))
    shas = []
    for r in (a["base"], a["head"]):
        rc, out, _ = qc.git(rd, "rev-parse", "--verify", "-q", r + "^{commit}")
        if rc != 0:
            return qc.verdict("UNVERIFIED", GATE, name, ref, "cannot resolve ref %s" % r)
        shas.append(out.strip())
    base, head = shas
    langs = set(x.strip() for x in os.environ.get("QA_REVIEWER_LANGS", REVIEW_LANGS_DEFAULT).split(",") if x.strip())
    changed = qc.changed_files(rd, base, head)
    if not changed:
        return qc.verdict("NA", GATE, name, ref, "empty diff", {"files_in_diff": 0})
    cand = [p for p in changed if ga.lang_of(p) and not ga.ignorable(p) and not ga.is_test_path(p)]
    notes = []
    if len(cand) > MAX_FILES:
        notes.append("only the first %d of %d candidate files were considered" % (MAX_FILES, len(cand)))
        cand = cand[:MAX_FILES]
    if not cand:
        return qc.verdict("NA", GATE, name, ref, "docs/test/generated-only diff: no product code to review",
                          {"files_in_diff": len(changed), "counts": {"proposed": 0, "verified": 0, "survived": 0}})
    dtext = ""
    for i in range(0, len(cand), 150):                       # keep argv bounded on huge merges
        dtext += qc.diff_text(rd, base, head, cand[i:i + 150], unified=3)
    files = parse_diff(dtext)
    reviewable, skipped = classify_files(files, langs)
    chunks = []
    for p, hunks in reviewable.items():
        cs, why = build_chunks(p, hunks)
        if why:
            skipped.append({"file": p, "reason": why})
        else:
            chunks.extend(cs)
    # smallest diffs first: reviewer accuracy collapses on big diffs (plan section 4) and more files get covered inside the deadline
    chunks.sort(key=lambda c: (sum(len(hunk_added(h)) for h in c["hunks"]), c["path"]))
    base_details = {"files_in_diff": len(changed), "skipped": skipped[:40], "notes": notes, "chunks_total": len(chunks),
                    "counts": {"proposed": 0, "verified": 0, "survived": 0}}
    if not chunks:
        return qc.verdict("NA", GATE, name, ref, "no reviewable product code (%d file(s) skipped: %s)" % (
            len(skipped), ", ".join(sorted(set(s["reason"].split("(")[0] for s in skipped))) or "none"), base_details)

    url = a["llm_url"] or os.environ.get("QA_REVIEWER_URL", DEFAULT_URL)
    model = a["model"] or os.environ.get("QA_REVIEWER_MODEL", DEFAULT_MODEL)
    budget = Budget(model_fn or make_model_fn(url, model), env_num("QA_REVIEWER_MAX_CALLS", "16", int),
                    env_num("QA_REVIEWER_DEADLINE", "120"), env_num("QA_REVIEWER_CALL_TIMEOUT", "60"))
    drops = {}
    counts = {"proposed": 0, "verified": 0, "refuted": 0, "refute_unavailable": 0, "survived": 0}
    survivors, seen, head_cache = [], set(), {}
    # model-free pass over the same reviewable files (no model call, cannot be refuted by one): auth-less sensitive routes, hardcoded default secrets
    npat = 0
    for p_, hunks_ in reviewable.items():
        for pf in pattern_findings(p_, hunks_):
            kn_ = secret_values(pf["quote"])
            pf["id"] = finding_id(name, head, pf)
            pf["quote"] = redact(pf["quote"], 300, kn_)
            pf["refuter"] = "n/a (deterministic pattern, not model-proposed)"
            survivors.append(pf)
            seen.add((pf["file"], pf["line"], pf["claim"][:60]))
            npat += 1

    chunks_ok = chunks_tried = sev_defaulted = 0
    trace = []

    def tr(chunk, stage, f, extra=None):
        kn = chunk["secrets"]
        trace.append(dict({"file": chunk["path"], "stage": stage, "finding": {k: redact(v, 300, kn) if isinstance(v, str) else v for k, v in (f or {}).items()}},
                          **(extra or {})))

    for ch in chunks:
        if budget.dead or budget.stopped:
            break
        chunks_tried += 1
        ch["secrets"] = secret_values("\n".join(t for h in ch["hunks"] for _, t in hunk_added(h)))   # redact these wherever the model repeats them
        text = budget(review_prompt(name, ch["path"], ch["text"]))
        if text is None:
            break
        d = ac.parse_card_json(text)
        raw = d.get("findings") if isinstance(d, dict) else None
        if not isinstance(raw, list):
            drops["bad_json"] = drops.get("bad_json", 0) + 1
            continue
        chunks_ok += 1
        counts["proposed"] += len(raw)
        if len(raw) > MAX_PER_CHUNK:
            drops["over_cap"] = drops.get("over_cap", 0) + len(raw) - MAX_PER_CHUNK
        for f in raw[:MAX_PER_CHUNK]:
            nf, why = verify_finding(f, ch)
            if nf is None:
                drops[why] = drops.get(why, 0) + 1
                tr(ch, "dropped:" + why, f if isinstance(f, dict) else {"raw": str(f)})
                continue
            key = (nf["file"], nf["line"], nf["claim"][:60])
            if key in seen:
                drops["duplicate"] = drops.get("duplicate", 0) + 1
                continue
            seen.add(key)
            counts["verified"] += 1
            sev_defaulted += 1 if nf.pop("sev_defaulted", False) else 0
            if nf["file"] not in head_cache:
                rc, out, _ = qc.git(rd, "show", "%s:%s" % (head, nf["file"]))
                head_cache[nf["file"]] = out.split("\n") if rc == 0 else None
            hl = head_cache[nf["file"]]
            if not hl:
                counts["refute_unavailable"] += 1
                continue
            rtext = budget(refute_prompt(name, nf, context_block(hl, nf["line"])))
            if rtext is None:
                counts["refute_unavailable"] += 1
                tr(ch, "refute-unavailable", nf)
                break                                          # the breaker/deadline/cap tripped; the outer loop stops too
            refuted, reason = parse_refute(rtext)
            if refuted:
                counts["refuted"] += 1
                tr(ch, "refuted", nf, {"reason": redact(reason, 200, ch["secrets"])})
                continue
            counts["survived"] += 1
            tr(ch, "survived", nf, {"reason": redact(reason, 200, ch["secrets"])})
            sev_final, raised = severity_floor(nf["claim"], nf["quote"], nf["severity"])
            survivors.append({"id": finding_id(name, head, nf), "file": nf["file"], "line": nf["line"], "quote": redact(nf["quote"], 300, ch["secrets"]),
                              "claim": redact(nf["claim"], 400, ch["secrets"]), "severity": sev_final, "severity_raised": raised,
                              "refuter": redact(reason, 200, ch["secrets"])})
    if a["trace"] and trace:
        try:
            with open(a["trace"], "a") as fh:
                for t in trace:
                    fh.write(json.dumps(dict(t, repo=name, ref=ref), ensure_ascii=False) + "\n")
        except OSError:
            pass
    complete = chunks_ok == len(chunks) and counts["refute_unavailable"] == 0
    details = dict(base_details)
    details.update({"counts": counts, "dropped": drops, "findings": survivors, "chunks_reviewed": chunks_ok, "chunks_tried": chunks_tried,
                    "severity_defaulted": sev_defaulted, "pattern_findings": npat, "model_calls": budget.calls, "model_stopped": budget.stopped or None, "complete": complete,
                    "usage": {"prompt_tokens": budget.usage["prompt_tokens"], "completion_tokens": budget.usage["completion_tokens"],
                              "gpu_s": round(budget.usage["gpu_s"], 2)},
                    "model": model, "deadline_s": budget.deadline_s})
    cs = "proposed=%d verified=%d survived=%d" % (counts["proposed"], counts["verified"], counts["survived"])
    if survivors:
        return qc.verdict("FLAG", GATE, name, ref, "%d finding(s) survived the refuter%s (advisory, unlabelled) [%s]%s" % (
            len(survivors), " (%d from the model-free pattern pass)" % npat if npat else "", cs,
            "" if complete else " PARTIAL: %d/%d chunks reviewed" % (chunks_ok, len(chunks))), details)
    if chunks_ok == 0:
        return qc.verdict("UNVERIFIED", GATE, name, ref, "model unavailable, too slow or unparseable (%s after %d call(s)); nothing was reviewed" % (
            budget.stopped or "bad-json", budget.calls), details)
    if not complete:
        return qc.verdict("UNVERIFIED", GATE, name, ref, "partial review: %d/%d chunks, %d refute call(s) lost (%s) - not a PASS [%s]" % (
            chunks_ok, len(chunks), counts["refute_unavailable"], budget.stopped or "bad-json", cs), details)
    return qc.verdict("PASS", GATE, name, ref, "reviewed %d chunk(s), nothing survived the refuter [%s]" % (chunks_ok, cs), details)


def main():
    return qc.main_guard(GATE, check)


if __name__ == "__main__":
    sys.exit(main())
