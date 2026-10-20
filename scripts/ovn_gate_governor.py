#!/usr/bin/env python3
"""ovn_gate_governor.py - ONE place for every shadow/enforce gate switch: evidence, safe promote, auto-demote (package L3, 2026-10-18).

Why (incidents of 2026-10-17/18): a SHADOW gate (OVN_STAGE_ITEM_VERIFY) let ~27 `refuse: item VERIFY RED` verdicts still credit and push (a billwatch refresh-token auth bypass reached
develop); there was no evidence-driven way to flip it, and no safety net if an ENFORCED gate stalled a lane - so nobody dared enforce. This tool closes both halves.

Registry: ops/gate_registry.json lists every switch (env var, default, channel, where its shadow evidence is journalled, how a would-block is recognised, how to roll back). `selfcheck`
verifies the registry against the real source tree, so it cannot drift silently.

Commands (all read-only unless --apply is given; OVN_GATE_GOVERNOR=off disables every command except list/status):
  list | status                      every gate, its EFFECTIVE mode and where that mode comes from (pilot_flags.env > process env > code default; qa: env > qa_gate_modes.json > shadow)
  report [--gate G] [--days N] [--json] [--write]   evidence per gate from the real journals (read-only): would-block count, how many shadow would-blocks were still credited (state/stage_credited.ledger,
                                     summary.commits_pushed) and how many of those credits later turned out bad (outcomes.jsonl: later revert / item re-opened; git `This reverts commit`; human labels),
                                     FP candidates for a human spot-check, and the promotion criteria checklist. --write stores state/gate_governor/reports/<date>.{md,json}
  label <gate> <key> tp|fp [--note T]   record a hand-checked verdict for one would-block (key = the id printed in the report). Only labels count toward "n>=20 hand-checked hits"
  attest <gate> replay|cost --ref TEXT [--p90-s N]   record that the replay against history / the p90 cost measurement was done elsewhere (stored with who/when)
  promote <gate> [--to enforce] [--apply] [--i-checked-the-samples --reason T]   raise a gate. REFUSED unless every criterion is met; the override flag is logged as an override
  demote  <gate> [--to shadow|off] [--apply] [--reason T]            lower a gate (always allowed, never needs evidence)
  rollback [--list] [--to ID] [--apply]  restore state/pilot_flags.env to a backup (default: the state before the last governor write); the restore is verified byte-for-byte
  watchdog                           AUTO-DEMOTE: an ENFORCED gate that (T1) blocks the same lane+item N times in H hours, or (T2) sits on a lane with 0 landings for X hours while its refuse
                                     count rose, is flipped back to shadow + ONE alert with the evidence. Writes ONLY when OVN_GATE_GOVERNOR=enforce; otherwise it
                                     reports (and alerts once) what it WOULD do.
  mode [off|shadow|enforce]          show / persist the governor mode in state/gate_governor/mode (env OVN_GATE_GOVERNOR overrides it); this is the ONLY switch for auto-demote
  selfcheck                          registry vs source tree (env vars exist, defaults agree)

Writes (only with --apply / enforce): state/pilot_flags.env (atomic, backed up first, `bash -n`-checked, read back) and the governor's own state/gate_governor/{audit.jsonl,backups/,labels.jsonl,
attest.json,alerted.json,reports/}. Nothing else. A change is live from the NEXT run_overnight.sh start (pilot_flags.env is sourced there), never mid-run.

Env: OVN_GATE_GOVERNOR=off|shadow|enforce (default shadow; or state/gate_governor/mode)   OVN_DIR (queue root)   OVN_GG_STATE / QA_STATE_DIR (state dir)   OVN_GG_REGISTRY   OVN_GG_NOW (epoch, tests)
     OVN_GG_REPEAT_N / OVN_GG_REPEAT_H / OVN_GG_STALL_H / OVN_GG_STALL_MIN_BLOCKS / OVN_GG_ALERT_TTL_H   (override the registry's watchdog block)
     OVN_GG_GIT=0 disables the git-revert join.   Pure stdlib, python >= 3.8.
Exit: 0 ok, 1 refused (criteria / validation), 2 usage / registry error.
"""
import argparse
import collections
import fcntl
import glob
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

RANK = {"off": 0, "shadow": 1, "enforce": 2}
VALUE_RE = re.compile(r"^[A-Za-z0-9_,.:@+-]*$")
ENV_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
TAG = "gate-governor"
GOOD_CLASSES = ("landed", "landed-uncredited")


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# paths / config
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def now():
    try:
        return float(os.environ["OVN_GG_NOW"])
    except (KeyError, ValueError):
        return time.time()


def ovn_dir():
    return os.environ.get("OVN_DIR") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def state_dir():
    return os.environ.get("OVN_GG_STATE") or os.environ.get("QA_STATE_DIR") or os.path.join(ovn_dir(), "state")


def gg_dir():
    return os.path.join(state_dir(), "gate_governor")


def flags_path():
    return os.path.join(state_dir(), "pilot_flags.env")


def registry_path():
    return os.environ.get("OVN_GG_REGISTRY") or os.path.join(ovn_dir(), "ops", "gate_registry.json")


def mode_file():
    return os.path.join(gg_dir(), "mode")


def governor_mode():
    """off | shadow | enforce: env OVN_GATE_GOVERNOR > state/gate_governor/mode (one word, written by `mode <m>`) > shadow. A typo or unreadable file never enforces."""
    v = os.environ.get("OVN_GATE_GOVERNOR")
    if not v:
        try:
            v = open(mode_file()).read()
        except OSError:
            v = ""
    v = (v or "shadow").strip().lower()
    return v if v in RANK else "shadow"


def iso(ts):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def fnum(name, default):
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return float(default)


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def atomic_write(path, text, mode=None):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def append_jsonl(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps(obj, sort_keys=True, ensure_ascii=False) + "\n")


def sha(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None


class Lock:
    """Non-blocking-optional exclusive flock on state/gate_governor/<name>.lock."""

    def __init__(self, name, wait=True):
        self.path = os.path.join(gg_dir(), name + ".lock")
        self.wait = wait
        self.f = None

    def __enter__(self):
        os.makedirs(gg_dir(), exist_ok=True)
        self.f = open(self.path, "a")
        try:
            fcntl.flock(self.f, fcntl.LOCK_EX | (0 if self.wait else fcntl.LOCK_NB))
        except OSError:
            self.f.close()
            self.f = None
        return self

    @property
    def held(self):
        return self.f is not None

    def __exit__(self, *a):
        if self.f is not None:
            fcntl.flock(self.f, fcntl.LOCK_UN)
            self.f.close()


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# registry
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
class RegistryError(Exception):
    pass


_REG = {}   # the loaded registry, for the member-default fallback


def load_registry(path=None):
    path = path or registry_path()
    try:
        with open(path) as f:
            reg = json.load(f)
    except (OSError, ValueError) as e:
        raise RegistryError("cannot read registry %s: %s" % (path, e))
    problems = validate_registry(reg)
    if problems:
        raise RegistryError("invalid registry %s: %s" % (path, "; ".join(problems[:6])))
    _REG["reg"] = reg
    return reg


def validate_registry(reg):
    p = []
    if not isinstance(reg, dict) or not isinstance(reg.get("gates"), list) or not reg["gates"]:
        return ["no gates[]"]
    seen = set()
    for g in reg["gates"]:
        gid = g.get("id", "?")
        if gid in seen:
            p.append("duplicate id " + gid)
        seen.add(gid)
        if not ENV_RE.match(g.get("env", "")):
            p.append("%s: bad env" % gid)
        if g.get("kind") not in ("mode", "bool", "member"):
            p.append("%s: bad kind" % gid)
        if g.get("channel") not in ("pilot_env", "qa_modes", "cron_env"):
            p.append("%s: bad channel" % gid)
        if g.get("default") not in RANK:
            p.append("%s: bad default" % gid)
        if g.get("kind") == "member" and not g.get("member"):
            p.append("%s: member kind needs member" % gid)
        for v in (g.get("values") or {}).values():
            if not VALUE_RE.match(v):
                p.append("%s: unsafe value %r" % (gid, v))
        ev = g.get("evidence") or {}
        if ev.get("type") not in ("stage_event", "text", "tsv", "jsonl", "lq_rule", "none"):
            p.append("%s: bad evidence type" % gid)
        for pat in (ev.get("patterns") or []):
            try:
                re.compile(pat["re"])
            except (re.error, KeyError):
                p.append("%s: bad pattern" % gid)
        if ev.get("block_re"):
            try:
                re.compile(ev["block_re"])
            except re.error:
                p.append("%s: bad block_re" % gid)
    return p


def owner_hint(g, to):
    """Why the governor does not write this gate, and the exact thing to do instead."""
    if g["channel"] == "qa_modes":
        return "%s is owned by qa/qa_enforce.sh (state/qa_gate_modes.json). Run: bash qa/qa_enforce.sh %s %s" % (g["id"], g["qa_gate"], to)
    return ("%s is read by CRON-launched scripts (%s), which never source state/pilot_flags.env, so a write there would silently do nothing. "
            "Set %s=%s in the environment of those crontab lines instead (a deliberate crontab edit)" % (g["id"], g.get("consumers", "cron jobs"), g["env"], mode_value(g, to) if g["kind"] != "member" else to))


def gate_modes(g):
    if g.get("modes"):
        return list(g["modes"])
    return ["off", "shadow", "enforce"]


def mode_value(g, mode):
    """The literal written to pilot_flags.env for `mode`."""
    if g["kind"] == "member":
        raise ValueError("member gates are rewritten as a list")
    return (g.get("values") or {}).get(mode, mode)


def parse_mode_value(g, raw):
    if raw is None:
        return None
    raw = raw.strip().strip("'\"")
    inv = {v.lower(): k for k, v in (g.get("values") or {}).items()}
    low = raw.lower()
    if low in inv:
        return inv[low]
    if low in RANK and low in gate_modes(g) and low not in ("on",):
        return low
    if g.get("kind") != "bool" and low in ("on", "1", "true"):
        return "enforce"
    if low in ("0", "false"):
        return "off"
    return None


def default_members(g):
    """Members enforced by default for a member gate: parsed from the code (DEFAULT_ENFORCE = ("A", "B"))."""
    f = g.get("default_members_file")
    txt = None
    if f:
        try:
            txt = open(os.path.join(ovn_dir(), f)).read()
        except OSError:
            txt = None
    m = re.search(r"^DEFAULT_ENFORCE\s*=\s*\(([^)]*)\)", txt or "", re.M)
    if m:
        return set(re.findall(r"[\"']([A-Z_]+)[\"']", m.group(1)))
    # the code file is not readable here (a partial checkout): fall back to the registry's own defaults for every rule sharing this env var
    return {x["member"] for x in _REG.get("reg", {}).get("gates", []) if x.get("env") == g["env"] and x.get("kind") == "member" and x.get("default") == "enforce"}


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# pilot_flags.env
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def parse_flag_line(ln):
    """-> (kind, [(VAR, value), ...]); kind = blank | comment | assign | complex.
    `assign` = optional `export`, then one or MORE plain NAME=value words (quotes allowed, trailing ` # comment` allowed): `export A=x B=y` is valid bash and gives BOTH.
    `complex` = anything else (`[ -n "$X" ] && export V=enforce`, `V=${FOO:-enforce}`, `A=1; B=2`, `FOO=1 cmd`, backticks, `V=a#b`): the governor cannot know what it does and never guesses."""
    s = ln.strip()
    if not s:
        return "blank", []
    if s.startswith("#"):
        return "comment", []
    if re.search(r"[^\s]#", re.sub(r"'[^']*'|\"[^\"]*\"", "", ln)):
        return "complex", []   # a mid-word '#' is a literal in bash but a comment to shlex: do not guess
    try:
        lex = shlex.shlex(ln, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = "#"
        toks = list(lex)
    except ValueError:
        return "complex", []
    if toks and toks[0] == "export":
        toks = toks[1:]
    if not toks:
        return "complex", []
    out = []
    for t in toks:
        m = ASSIGN_RE.match(t)
        if not m or "$" in m.group(2) or "`" in m.group(2):
            return "complex", []
        out.append((m.group(1), m.group(2)))
    return "assign", out


def read_flags(path=None):
    """-> ({VAR: value} from the LAST plain assignment of each var (what a bash `.` would leave), the raw lines). Lines that are not plain assignments are reported by complex_flag_lines()."""
    path = path or flags_path()
    try:
        with open(path) as f:
            lines = f.read().split("\n")
    except OSError:
        return {}, []
    out = {}
    for ln in lines:
        kind, assigns = parse_flag_line(ln)
        if kind == "assign":
            for var, val in assigns:
                out[var] = val
    return out, lines


def complex_flag_lines(lines=None):
    """-> [(line_no, text, [VARS mentioned])] for every non-plain-assignment line that mentions an UPPER_CASE name (a conditional / computed assignment is invisible to the parser)."""
    lines = read_flags()[1] if lines is None else lines
    out = []
    for n, ln in enumerate(lines, 1):
        if parse_flag_line(ln)[0] == "complex":
            out.append((n, ln.strip()[:120], sorted(set(re.findall(r"[A-Z][A-Z0-9_]{3,}", ln)))))
    return out


def effective(g, flags=None, environ=None):
    """-> (mode, source) for gate g. pilot_env: pilot_flags.env > process env > default (run_overnight.sh sources the file over its env)."""
    flags = read_flags()[0] if flags is None else flags
    environ = os.environ if environ is None else environ
    if g["channel"] == "qa_modes":
        env = environ.get(g["env"])
        if env in RANK:
            return env, "env"
        for fn, src in (("qa_gate_modes.json", "file"), ("qa_modes.json", "legacy")):
            v = read_json(os.path.join(state_dir(), fn), {})
            if isinstance(v, dict) and v.get(g["qa_gate"]) in RANK:
                return v[g["qa_gate"]], src
        return "shadow", "default"
    sources = [("pilot_flags.env", flags.get(g["env"])), ("env", environ.get(g["env"]))]
    if g["channel"] == "cron_env":
        sources = sources[1:]   # pilot_flags.env never reaches these consumers (cron-launched): only the cron line's own env counts, which the governor cannot see
    for src, raw in sources:
        if raw is None:
            continue
        if g["kind"] == "member":
            members = {m.strip() for m in raw.split(",") if m.strip()}
            return ("enforce" if g["member"] in members else "shadow"), src
        m = parse_mode_value(g, raw)
        if m is not None:
            return m, src
    if g["kind"] == "member":
        return ("enforce" if g["member"] in default_members(g) else "shadow"), "default"
    return g["default"], "default"


def member_list(g, flags, environ=None):
    environ = os.environ if environ is None else environ
    raw = flags.get(g["env"])
    if raw is None:
        raw = environ.get(g["env"])
    if raw is None:
        return sorted(default_members(g))
    return sorted({m.strip() for m in raw.split(",") if m.strip()})


def render_flags(old_lines, updates, note):
    """Rewrite old_lines so every var in `updates` ({VAR: value}) has exactly ONE governed line; every other line is preserved verbatim, and the OTHER assignments of a multi-variable
    `export A=x B=y` line are kept (as their own export lines) when A is governed."""
    out, done = [], set()
    for ln in old_lines:
        kind, assigns = parse_flag_line(ln)
        if kind == "assign" and any(v in updates for v, _ in assigns):
            for v, val in assigns:
                if v not in updates:
                    out.append("export %s=%s" % (v, shlex.quote(val)))
            for v, _ in assigns:
                if v in updates and v not in done:   # duplicates of a governed var collapse into the first
                    out.append("export %s='%s'  # %s %s" % (v, updates[v], TAG, note))
                    done.add(v)
        else:
            out.append(ln)
    while out and out[-1] == "":
        out.pop()
    if not out:
        out.append("# state/pilot_flags.env - sourced by run_overnight.sh at start. Lines tagged '# %s' are written by scripts/ovn_gate_governor.py (rollback: ovn_gate_governor.py rollback)." % TAG)
    for var, val in updates.items():
        if var not in done:
            out.append("export %s='%s'  # %s %s" % (var, val, TAG, note))
    return "\n".join(out) + "\n"


def bash_ok(text, expect=None):
    """`bash -n` + a sourcing smoke test (+ when `expect` {VAR: value} is given: after sourcing, every VAR must hold EXACTLY that value, so a later conditional / computed line that
    overrides a governed var makes the write REFUSE instead of silently doing nothing). True when bash is unavailable (nothing to prove with)."""
    bash = shutil.which("bash")
    if not bash:
        return True
    with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False) as t:
        t.write(text)
        tp = t.name
    try:
        if subprocess.run([bash, "-n", tp], capture_output=True).returncode != 0:
            return False
        names = sorted(expect or {})
        script = 'set -u; . "$1"; echo ok' + "".join('; printf "GG:%s=%%s\\n" "${%s-}"' % (n, n) for n in names)
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.environ.get("HOME", "/")}
        r = subprocess.run([bash, "-c", script, "_", tp], capture_output=True, text=True, env=env)
        if r.returncode != 0 or "ok" not in r.stdout.split("\n"):
            return False
        got = {}
        for ln in r.stdout.split("\n"):
            m = re.match(r"^GG:([A-Z0-9_]+)=(.*)$", ln)
            if m:
                got[m.group(1)] = m.group(2)
        return all(got.get(n) == expect[n] for n in names)
    finally:
        try:
            os.unlink(tp)
        except OSError:
            pass


def backup_dir():
    return os.path.join(gg_dir(), "backups")


BID_RE = re.compile(r"^(\d{8}T\d{6}Z)-(\d+)$")


def bid_key(b):
    m = BID_RE.match(b)
    return (m.group(1), int(m.group(2))) if m else (b, 0)


def index_path():
    return os.path.join(backup_dir(), "index.jsonl")


def backup_kinds():
    """{backup id: kind}. kind = change (written by promote / demote / auto-demote: the state BEFORE that change) | rollback-pre (the state a rollback replaced). Unknown = change."""
    out = {}
    try:
        for ln in open(index_path()):
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if isinstance(r, dict) and r.get("id"):
                out[r["id"]] = r.get("kind", "change")
    except OSError:
        pass
    return out


def make_backup(kind="change"):
    """Copy the current pilot_flags.env to backups/<id>.env (or <id>.absent) and index its kind. -> backup id. Prunes to the newest OVN_GG_BACKUP_KEEP (default 50)."""
    os.makedirs(backup_dir(), exist_ok=True)
    bid = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(now()))
    n = 0
    while any(os.path.exists(os.path.join(backup_dir(), "%s-%d.%s" % (bid, n, e))) for e in ("env", "absent")):
        n += 1
    bid = "%s-%d" % (bid, n)
    if os.path.exists(flags_path()):
        shutil.copy2(flags_path(), os.path.join(backup_dir(), bid + ".env"))
    else:
        open(os.path.join(backup_dir(), bid + ".absent"), "w").close()
    append_jsonl(index_path(), {"id": bid, "kind": kind, "ts": iso(now())})
    prune_backups(int(fnum("OVN_GG_BACKUP_KEEP", 50)))
    return bid


def prune_backups(keep):
    """Delete all but the newest `keep` backups (and their .restored markers); the newest `change` backup is never pruned. Index rewritten to match."""
    keep = max(2, keep)
    ids = list_backups()
    if len(ids) <= keep:
        return
    kinds = backup_kinds()
    changes = [i for i in ids if kinds.get(i, "change") == "change"]
    protect = set(ids[-keep:]) | ({changes[-1]} if changes else set())
    for i in ids:
        if i in protect:
            continue
        for ext in ("env", "absent", "restored"):
            try:
                os.unlink(os.path.join(backup_dir(), "%s.%s" % (i, ext)))
            except OSError:
                pass
    left = set(list_backups())
    try:
        recs = [json.loads(x) for x in open(index_path()) if x.strip()]
        atomic_write(index_path(), "".join(json.dumps(r, sort_keys=True) + "\n" for r in recs if r.get("id") in left))
    except (OSError, ValueError):
        pass


def write_flags(updates, who, action, reason):
    """Apply {VAR: value} to pilot_flags.env under lock: backup -> render -> bash check (syntax, sourcing, AND every governed var reads back as written) -> atomic write -> read back.
    -> (backup_id, new_sha). Raises RuntimeError (file untouched / restored)."""
    with Lock("write"):
        cur_flags, old_lines = read_flags()
        if callable(updates):
            updates = updates(cur_flags)   # computed under the lock so a concurrent writer's change to the same list is never lost
        for var, val in updates.items():
            if not ENV_RE.match(var) or not VALUE_RE.match(val):
                raise RuntimeError("refusing to write unsafe %s=%r" % (var, val))
        note = "%s %s by=%s%s" % (iso(now()), action, re.sub(r"[^A-Za-z0-9_.@-]", "", who)[:40], (" reason=" + re.sub(r"[^A-Za-z0-9 _.,:;=/-]", "", reason)[:80]) if reason else "")
        text = render_flags(old_lines, updates, note)
        if not bash_ok(text, updates):
            cx = [c for c in complex_flag_lines(old_lines) if set(c[2]) & set(updates)]
            raise RuntimeError("rendered pilot_flags.env fails the bash check (syntax / sourcing / the governed value does not survive sourcing)%s; nothing written" % (
                (": line %d is not a plain assignment and mentions %s (`%s`) - edit it by hand" % (cx[0][0], ",".join(sorted(set(cx[0][2]) & set(updates))), cx[0][1])) if cx else ""))
        bid = make_backup("change")
        try:
            atomic_write(flags_path(), text)
            if sha(flags_path()) != hashlib.sha256(text.encode()).hexdigest():
                raise RuntimeError("read-back of pilot_flags.env differs from what was written")
        except BaseException:
            restore_backup(bid)
            raise
        return bid, sha(flags_path())


def restore_backup(bid):
    """Restore pilot_flags.env from backup `bid` and VERIFY (feedback: a rollback that silently failed kept the new state). -> True when the file now equals the backup."""
    env_b = os.path.join(backup_dir(), bid + ".env")
    abs_b = os.path.join(backup_dir(), bid + ".absent")
    if os.path.exists(env_b):
        atomic_write(flags_path(), open(env_b).read())
        return sha(flags_path()) == sha(env_b)
    if os.path.exists(abs_b):
        try:
            os.unlink(flags_path())
        except FileNotFoundError:
            pass
        return not os.path.exists(flags_path())
    raise RuntimeError("no such backup " + bid)


def list_backups():
    ids = set()
    try:
        for fn in os.listdir(backup_dir()):
            m = re.match(r"^(.+)\.(env|absent)$", fn)
            if m:
                ids.add(m.group(1))
    except OSError:
        pass
    return sorted(ids, key=bid_key)


def audit(**rec):
    rec["ts"] = iso(now())
    append_jsonl(os.path.join(gg_dir(), "audit.jsonl"), rec)


def who():
    return os.environ.get("OVN_GG_WHO") or ("%s@gate_governor" % (os.environ.get("USER") or "?"))


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# journals -> normalised evidence records
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def norm_repo(s):
    s = (s or "").strip().lower()
    s = re.sub(r"^stage-", "", s)
    s = re.sub(r"\.[a-z0-9]{3,6}$", "", s)
    return s.replace("_", "-")


def item_hash(text):
    """Mirror of lib_item_select.sh ovn_item_hash (the key outcomes.jsonl uses)."""
    t = re.sub(r"^- \[[ xX]\] ", "", text or "")
    m = re.search(r"\[feat:[^\]]+\]", t)
    if m:
        k = re.sub(r"-[0-9]{8}-", "-", m.group(0), count=1)
        k = re.sub(r"-[0-9]{6}-", "-", k, count=1)
        return hashlib.md5(k.encode()).hexdigest()
    return hashlib.md5(t.encode()).hexdigest()


def parse_ts(s, kind="auto"):
    """-> epoch or None. iso = ...Z (UTC); local = 'YYYY-MM-DD HH:MM:SS' (system tz); run = YYYYMMDD-HHMMSS (UTC, stage run ids)."""
    if s is None:
        return None
    if isinstance(s, (int, float)):
        return float(s)
    s = str(s).strip().lstrip("[")
    m = re.match(r"^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z", s)
    if m:
        import calendar
        return float(calendar.timegm(tuple(int(x) for x in m.groups()) + (0, 0, 0)))
    m = re.match(r"^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)", s)
    if m:
        return float(time.mktime(tuple(int(x) for x in m.groups()) + (0, 0, -1)))
    m = re.match(r"^(\d{4})(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d)", s)
    if m:
        if kind == "run":
            import calendar
            return float(calendar.timegm(tuple(int(x) for x in m.groups()) + (0, 0, 0)))
        return float(time.mktime(tuple(int(x) for x in m.groups()) + (0, 0, -1)))
    return None


class Rec:
    """One normalised evidence record."""
    __slots__ = ("ts", "repo", "key", "run", "text", "mode", "block", "cost_s", "item", "unverified", "flag")

    def __init__(self, ts=None, repo="", key="", run="", text="", mode="shadow", block=False, cost_s=None, item="", unverified=False, flag=False):
        self.ts, self.repo, self.key, self.run, self.text, self.mode = ts, norm_repo(repo), key, run, (text or "")[:240], mode
        self.block, self.cost_s, self.item, self.unverified, self.flag = block, cost_s, item, unverified, flag


def line_key(*parts):
    return "l:" + hashlib.md5("|".join(str(p) for p in parts).encode()).hexdigest()[:10]


class Ctx:
    """Lazily loaded, shared read-only view of the journals."""

    def __init__(self, days=7.0):
        self.days = days
        self.t_now = now()
        self.since = self.t_now - days * 86400.0
        self._runs = None
        self._outcomes = None
        self._ledger = None
        self._labels = None
        self._glob_cache = {}

    # --- stage run journals
    def runs(self):
        if self._runs is None:
            self._runs = {}
            d = os.path.join(state_dir(), "stage_runs")
            lo = self.since - 7 * 86400   # outcome / credit join looks a little before the window too
            for fp in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
                m = re.search(r"(\d{8}-\d{6})-[^/]*\.jsonl$", fp)
                ts = parse_ts(m.group(1), "run") if m else None
                if ts is not None and ts < lo:
                    continue
                run = {"file": os.path.basename(fp), "ts": ts, "repo": "", "item": "", "events": [], "summary": {}}
                try:
                    with open(fp, errors="replace") as f:
                        for ln in f:
                            try:
                                r = json.loads(ln)
                            except ValueError:
                                continue
                            if not isinstance(r, dict):
                                continue
                            if r.get("repo") and not run["repo"]:
                                run["repo"] = r["repo"]
                            if r.get("item") and not run["item"]:
                                run["item"] = r["item"]
                            if r.get("event") == "summary":
                                run["summary"] = r
                            if r.get("event"):
                                run["events"].append(r)
                            if not run.get("run") and r.get("run"):
                                run["run"] = r["run"]
                except OSError:
                    continue
                if not run["repo"]:
                    run["repo"] = re.sub(r"-\d{8}-\d{6}-.*$", "", run["file"])
                run.setdefault("run", run["file"])
                self._runs[run["file"]] = run
        return self._runs

    def ledger(self):
        if self._ledger is None:
            self._ledger = set()
            try:
                for ln in open(os.path.join(state_dir(), "stage_credited.ledger"), errors="replace"):
                    ln = ln.strip()
                    if ln:
                        self._ledger.add(os.path.basename(ln))
            except OSError:
                pass
        return self._ledger

    def outcomes(self):
        if self._outcomes is None:
            self._outcomes = []
            try:
                for ln in open(os.path.join(state_dir(), "outcomes.jsonl"), errors="replace"):
                    try:
                        r = json.loads(ln)
                    except ValueError:
                        continue
                    if isinstance(r, dict):
                        r["_ts"] = parse_ts(r.get("ts"))
                        r["_repo"] = norm_repo(r.get("repo", ""))
                        self._outcomes.append(r)
            except OSError:
                pass
            self._outcomes.sort(key=lambda r: r["_ts"] or 0)
        return self._outcomes

    def labels(self):
        if self._labels is None:
            self._labels = {}
            try:
                for ln in open(os.path.join(gg_dir(), "labels.jsonl")):
                    try:
                        r = json.loads(ln)
                    except ValueError:
                        continue
                    if r.get("gate") and r.get("key") and r.get("label") in ("tp", "fp"):
                        self._labels[(r["gate"], r["key"])] = r   # latest wins
            except OSError:
                pass
        return self._labels

    def globbed(self, pattern):
        if pattern not in self._glob_cache:
            self._glob_cache[pattern] = sorted(glob.glob(os.path.join(ovn_dir(), pattern)) if not os.path.isabs(pattern) else glob.glob(pattern))
        return self._glob_cache[pattern]


def state_glob(ctx, pattern):
    """Journal paths are written relative to the queue root (state/...) in the registry; resolve state/ through state_dir() so OVN_GG_STATE works."""
    if pattern.startswith("state/"):
        return sorted(glob.glob(os.path.join(state_dir(), pattern[len("state/"):])))
    return sorted(glob.glob(os.path.join(ovn_dir(), pattern)))


def collect(g, ctx):
    """-> list[Rec] for gate g inside ctx's window (records with mode shadow|enforce; block=True marks a would-block / a block)."""
    ev = g.get("evidence") or {}
    t = ev.get("type")
    if t == "stage_event":
        return _c_stage_event(g, ev, ctx)
    if t == "lq_rule":
        return _c_lq_rule(g, ev, ctx)
    if t == "text":
        return _c_text(g, ev, ctx)
    if t == "tsv":
        return _c_tsv(g, ev, ctx)
    if t == "jsonl":
        return _c_jsonl(g, ev, ctx)
    return []


def _norm_mode(m):
    m = (m or "").strip().lower()
    return {"on": "enforce", "1": "enforce", "": "shadow"}.get(m, m if m in RANK else "shadow")


def _in_window(ts, ctx):
    return ts is None or (ctx.since <= ts <= ctx.t_now + 3600)


def _c_stage_event(g, ev, ctx):
    out = []
    block_re = re.compile(ev.get("block_re") or "^$")
    for run in ctx.runs().values():
        for e in run["events"]:
            if e.get("event") != ev["event"]:
                continue
            ts = run["ts"]
            if not _in_window(ts, ctx):
                continue
            val = str(e.get(ev.get("field", ""), ""))
            out.append(Rec(ts, run["repo"], "run:" + run["file"].replace(".jsonl", ""), run["file"], "%s | %s" % (val, run["item"][:120]),
                           _norm_mode(e.get("mode")), bool(block_re.search(val)), None, run["item"]))
    return out


def _c_lq_rule(g, ev, ctx):
    out = []
    rule = re.escape(ev["rule"])
    shadow_re = re.compile(r"(?:^|\|)\s*~%s\b" % rule)
    enf_re = re.compile(r"(?:^|\|)\s*%s\b" % rule)
    for run in ctx.runs().values():
        for e in run["events"]:
            if e.get("event") not in ("landing_quality_shadow", "landing_quality"):
                continue
            det = str(e.get("detail", ""))
            ts = run["ts"]
            if not _in_window(ts, ctx):
                continue
            if e["event"] == "landing_quality_shadow" and shadow_re.search(det):
                out.append(Rec(ts, run["repo"], "run:" + run["file"].replace(".jsonl", ""), run["file"], det[:200], "shadow", True, None, run["item"]))
            elif e["event"] == "landing_quality" and enf_re.search(det):
                # the runner journals this event with mode=$OVN_STAGE_LANDING_QUALITY (the MASTER switch): only master=enforce actually refused anything. A shadow master recorded the
                # finding but blocked nothing, so it is a would-block (never an enforced block the watchdog could demote); master off = nothing was checked. No mode (old rows) = enforce.
                m = _norm_mode(e["mode"]) if e.get("mode") else "enforce"
                if (e.get("mode") or "").strip().lower() == "off":
                    continue
                out.append(Rec(ts, run["repo"], "run:" + run["file"].replace(".jsonl", ""), run["file"], det[:200], "enforce" if m == "enforce" else "shadow", True, None, run["item"]))
    return out


def _dir_ts(path):
    return parse_ts(os.path.basename(os.path.dirname(path)))


def _c_text(g, ev, ctx):
    out = []
    pats = [(re.compile(p["re"]), _norm_mode(p.get("mode")), re.compile(p["repo_re"]) if p.get("repo_re") else None) for p in ev["patterns"]]
    rf = re.compile(ev["repo_from_file"]) if ev.get("repo_from_file") else None
    kind = ev.get("ts", "iso")
    for pattern in ev.get("journals", []):
        for fp in state_glob(ctx, pattern):
            try:
                st = os.stat(fp)
            except OSError:
                continue
            fts = _dir_ts(fp) if kind in ("dirname", "auto") and re.match(r"^\d{8}-\d{6}$", os.path.basename(os.path.dirname(fp))) else None
            if fts is not None and fts < ctx.since - 86400:
                continue
            if fts is None and st.st_mtime < ctx.since:
                continue
            repo_f = ""
            if rf:
                m = rf.search(os.path.basename(fp))
                repo_f = m.group("repo") if m else ""
            try:
                fh = open(fp, errors="replace")
            except OSError:
                continue
            with fh:
                for n, ln in enumerate(fh):
                    for rx, mode, repo_rx in pats:
                        m = rx.search(ln)
                        if not m:
                            continue
                        ts = fts
                        if ts is None:
                            ts = parse_ts(ln.strip().lstrip("[")[:20]) if kind in ("iso", "auto") else None
                        if ts is None and kind in ("iso", "auto"):
                            ts = None
                        if ts is not None and not _in_window(ts, ctx):
                            break
                        repo = repo_f
                        gd = m.groupdict()
                        if gd.get("repo"):
                            repo = gd["repo"]
                        if not repo and repo_rx:
                            rm = repo_rx.search(ln)
                            repo = rm.group("repo") if rm else ""
                        out.append(Rec(ts, repo, line_key(g["id"], os.path.basename(os.path.dirname(fp)), os.path.basename(fp), n, ln[:80]), "", ln.strip()[:220], mode, True, None, re.sub(r"^\S+Z ", "", ln.strip())[:200]))
                        break
    return out


def _c_tsv(g, ev, ctx):
    out = []
    for pattern in ev.get("journals", []):
        for fp in state_glob(ctx, pattern):
            try:
                fh = open(fp, errors="replace")
            except OSError:
                continue
            with fh:
                for n, ln in enumerate(fh):
                    c = ln.rstrip("\n").split("\t")
                    if len(c) <= max(ev["ts_col"], ev["repo_col"], ev["mode_col"], ev["decision_col"]):
                        continue
                    ts = parse_ts(c[ev["ts_col"]])
                    if not _in_window(ts, ctx):
                        continue
                    mode = _norm_mode(c[ev["mode_col"]])
                    # `enforce_block_values` (default: block_values): what counts as a REFUSAL once the gate is enforced. doc_executor's `apply` is an edit that was MADE, not a block.
                    bv = ev.get("enforce_block_values", ev.get("block_values", [])) if mode == "enforce" else ev.get("block_values", [])
                    out.append(Rec(ts, c[ev["repo_col"]], line_key(g["id"], n, ln[:60]), "", ln.strip()[:200], mode, c[ev["decision_col"]] in bv))
    return out


def _c_jsonl(g, ev, ctx):
    out = []
    bv, fv, uv = set(ev.get("block_values", [])), set(ev.get("flag_values", [])), set(ev.get("unverified_values", []))
    for pattern in ev.get("journals", []):
        for fp in state_glob(ctx, pattern):
            try:
                fh = open(fp, errors="replace")
            except OSError:
                continue
            with fh:
                for n, ln in enumerate(fh):
                    try:
                        r = json.loads(ln)
                    except ValueError:
                        continue
                    if not isinstance(r, dict):
                        continue
                    ts = parse_ts(r.get(ev.get("ts_field", "ts")))
                    if not _in_window(ts, ctx):
                        continue
                    if ev.get("nonempty_field"):
                        blocked = bool(r.get(ev["nonempty_field"]))
                        verdict = ""
                    else:
                        verdict = str(r.get(ev.get("verdict_field", "verdict"), ""))
                        blocked = verdict in bv
                    ms = r.get(ev.get("cost_ms_field", ""), None)
                    cost = (ms / 1000.0) if isinstance(ms, (int, float)) else None
                    txt = r.get("summary") or r.get("verify") or json.dumps(r, sort_keys=True)[:160]
                    ref = r.get("ref") or r.get("verify") or ""
                    out.append(Rec(ts, r.get(ev.get("repo_field", "repo"), ""), line_key(g["id"], os.path.basename(fp), r.get("repo", ""), ref, r.get(ev.get("ts_field", "ts"), n)),
                                   "", "%s %s" % (verdict, str(txt)[:150]), _norm_mode(r.get(ev.get("mode_field", "mode"))), blocked, cost, str(ref)[:200], verdict in uv, verdict in fv))
    return out


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# the credit join
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def run_credited(ctx, run):
    s = run.get("summary") or {}
    pushed = s.get("commits_pushed")
    return run["file"] in ctx.ledger() or (isinstance(pushed, (int, float)) and pushed > 0)


def reverted_shas(repo, since_ts):
    """set of sha prefixes named by 'This reverts commit X' in the queue repo clone since since_ts (empty when no clone / git / OVN_GG_GIT=0)."""
    if os.environ.get("OVN_GG_GIT", "1") == "0":
        return set()
    rd = os.path.join(os.environ.get("OVN_REPOS_DIR") or os.path.join(ovn_dir(), "repos"), repo)
    if not os.path.isdir(rd):
        return set()
    try:
        r = subprocess.run(["git", "-C", rd, "log", "--all", "--since=" + iso(since_ts), "--grep=This reverts commit", "--format=%B"],
                           capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return set()
    return set(re.findall(r"This reverts commit ([0-9a-f]{7,40})", r.stdout))


def join_credit(ctx, gate, recs):
    """For would-block records of run-based evidence: annotate whether the change was still credited and whether the credit later proved bad.
    -> {key: {credited, strong_bad, reopened, feature_reverted, why}}; keys absent = not run based.
      strong_bad       the credited commit was later reverted in git ('This reverts commit <sha>'), or a human labelled it tp
      reopened         the EXACT same item text was attempted again in a later stage run (a credited item is ticked and never picked again)
      feature_reverted informational only: a later outcome of the same feature (item_hash is per feature, not per item) was reverted"""
    info = {}
    rev_cache = {}
    outs = ctx.outcomes()
    by_item = collections.defaultdict(list)
    for r2 in ctx.runs().values():
        by_item[(norm_repo(r2["repo"]), r2["item"])].append(r2)
    for rec in recs:
        if not rec.block or not rec.run:
            continue
        run = ctx.runs().get(rec.run)
        if not run:
            continue
        credited = run_credited(ctx, run)
        d = {"credited": credited, "strong_bad": False, "reopened": False, "feature_reverted": False, "why": ""}
        info[rec.key] = d
        if not credited:
            continue
        h = item_hash(run["item"])
        repo = norm_repo(run["repo"])
        t0 = run["ts"] or rec.ts or 0
        # the outcome that recorded this landing: first landed* outcome of the item's feature within the stage timeout after the run started
        credit_out = next((o for o in outs if o["_repo"] == repo and o.get("item_hash") == h and t0 - 60 <= (o["_ts"] or 0) <= t0 + 4 * 3600 and o.get("class") in GOOD_CLASSES), None)
        t_credit = (credit_out["_ts"] if credit_out else t0) or t0
        later = [r2 for r2 in by_item[(repo, run["item"])] if r2["file"] != run["file"] and (r2["ts"] or 0) > t0]
        if later:
            d["reopened"], d["why"] = True, "the same item was attempted again in stage run %s after the credit" % later[0]["file"]
        for o in outs:
            if o["_repo"] == repo and o.get("item_hash") == h and (o["_ts"] or 0) > t_credit + 1 and o is not credit_out and (o.get("class") == "reverted" or "revert" in str(o.get("status", ""))):
                d["feature_reverted"] = True
                break
        if credit_out:
            heads = [credit_out.get("head_after")] + list(credit_out.get("commits") or [])
            heads = [x for x in heads if isinstance(x, str) and len(x) >= 7]
            if heads:
                if repo not in rev_cache:
                    rev_cache[repo] = reverted_shas(run["repo"], t_credit)
                for x in heads:
                    if any(x.startswith(r) or r.startswith(x[:len(r)]) for r in rev_cache[repo]):
                        d["strong_bad"], d["why"] = True, "commit %s was later reverted in git" % x[:10]
                        break
        lab = ctx.labels().get((gate["id"], rec.key))
        if lab and lab["label"] == "tp":
            d["strong_bad"], d["why"] = True, d["why"] or "human label tp"
    return info


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# attestations / criteria
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def attest_path():
    return os.path.join(gg_dir(), "attest.json")


def attestations():
    v = read_json(attest_path(), {})
    return v if isinstance(v, dict) else {}


def p90(xs):
    xs = sorted(xs)
    if not xs:
        return None
    return xs[min(len(xs) - 1, int(0.9 * len(xs)))]


def criteria_for(reg, g):
    c = dict(reg.get("criteria", {}))
    c.update(g.get("criteria") or {})
    return c


def gate_report(reg, g, ctx, flags=None, max_candidates=15):
    """The evidence dict for one gate."""
    flags = read_flags()[0] if flags is None else flags
    mode, src = effective(g, flags)
    ev = g.get("evidence") or {}
    crit = criteria_for(reg, g)
    rep = {"id": g["id"], "title": g.get("title", ""), "env": g["env"], "default": g["default"], "effective": mode, "source": src, "channel": g["channel"],
           "journals": [], "window_days": ctx.days, "evidence_type": ev.get("type")}
    if g["channel"] == "pilot_env":
        rep["promote_cmd"] = "python3 scripts/ovn_gate_governor.py promote %s --apply" % g["id"]
        rep["rollback_cmd"] = "python3 scripts/ovn_gate_governor.py rollback --apply   (or: python3 scripts/ovn_gate_governor.py demote %s --apply)" % g["id"]
    elif g["channel"] == "qa_modes":
        rep["promote_cmd"] = "bash qa/qa_enforce.sh %s enforce   (owned by qa_enforce.sh: state/qa_gate_modes.json)" % g["qa_gate"]
        rep["rollback_cmd"] = "bash qa/qa_enforce.sh %s shadow" % g["qa_gate"]
    else:
        rep["promote_cmd"] = owner_hint(g, "enforce")
        rep["rollback_cmd"] = "remove %s from the crontab line environment" % g["env"]
    for pat in ev.get("journals", []):
        files = state_glob(ctx, pat)
        newest = max((os.path.getmtime(f) for f in files if os.path.exists(f)), default=None)
        rep["journals"].append({"path": pat, "files": len(files), "newest": iso(newest) if newest else None})
    if ev.get("type") == "none":
        rep.update(records=0, would_block=0, evidence_note=ev.get("why", "no journal"))
        recs = []
    else:
        recs = collect(g, ctx)
    shadow = [r for r in recs if r.mode == "shadow"]
    enforced = [r for r in recs if r.mode == "enforce"]
    wb = [r for r in shadow if r.block]
    jinfo = join_credit(ctx, g, wb) if ev.get("credit_join") else {}
    dated = [r.ts for r in shadow if r.ts is not None]
    rep["records"] = len(shadow)
    rep["would_block"] = len(wb)
    rep["enforced_blocks"] = len([r for r in enforced if r.block])
    rep["flagged"] = len([r for r in shadow if r.flag])
    rep["unverified"] = len([r for r in shadow if r.unverified])
    rep["unverified_rate"] = (rep["unverified"] / float(len(shadow))) if shadow else None
    rep["shadow_days"] = round((max(dated) - min(dated)) / 86400.0, 2) if len(dated) >= 2 else 0.0
    rep["newest_record"] = iso(max(dated)) if dated else None
    rep["undated_records"] = len([r for r in shadow if r.ts is None])
    by_repo = collections.Counter(r.repo for r in wb)
    rep["by_repo"] = dict(sorted(by_repo.items()))
    if ev.get("credit_join"):
        cd = [r for r in wb if jinfo.get(r.key, {}).get("credited")]
        rep["credited_despite_would_block"] = len(cd)
        rep["blocked_anyway"] = len([r for r in wb if r.key in jinfo and not jinfo[r.key]["credited"]])
        rep["later_bad_strong"] = len([r for r in cd if jinfo[r.key]["strong_bad"]])
        rep["later_bad_reopened"] = len([r for r in cd if not jinfo[r.key]["strong_bad"] and jinfo[r.key]["reopened"]])
        rep["feature_later_reverted"] = len([r for r in cd if jinfo[r.key]["feature_reverted"]])
        rep["false_credits_confirmed"] = rep["later_bad_strong"] + rep["later_bad_reopened"]
    labels = ctx.labels()
    keys = {r.key for r in wb}
    lab = [labels[(g["id"], k)] for k in keys if (g["id"], k) in labels]
    tp = len([x for x in lab if x["label"] == "tp"])
    fp = len([x for x in lab if x["label"] == "fp"])
    rep["labelled"], rep["labelled_tp"], rep["labelled_fp"] = len(lab), tp, fp
    rep["fp_rate"] = (fp / float(len(lab))) if lab else None
    costs = [r.cost_s for r in shadow if r.cost_s is not None]
    att = attestations().get(g["id"], {})
    rep["p90_cost_s"] = p90(costs)
    rep["cost_source"] = "journal" if costs else ("attested" if att.get("cost") else None)
    if not costs and att.get("cost") and att["cost"].get("p90_s") is not None:
        rep["p90_cost_s"] = float(att["cost"]["p90_s"])
    rep["replay_attested"] = bool(att.get("replay"))
    # FP candidates for a human spot-check: unlabelled would-blocks; for credit-joined gates the ones that were credited with no later evidence of harm come first
    def prio(r):
        j = jinfo.get(r.key)
        if j is None:
            return 1
        return 0 if (j["credited"] and not j["strong_bad"] and not j["reopened"]) else 2
    cand = sorted([r for r in wb if (g["id"], r.key) not in labels], key=lambda r: (prio(r), -(r.ts or 0)))
    rep["fp_candidates"] = [{"key": r.key, "repo": r.repo, "ts": iso(r.ts) if r.ts else None, "text": r.text[:160],
                             "credited": jinfo.get(r.key, {}).get("credited"), "label_cmd": "label %s %s tp|fp" % (g["id"], r.key)} for r in cand[:max_candidates]]
    rep["criteria"] = criteria_checklist(crit, rep, g)
    rep["promotable"] = all(c["ok"] for c in rep["criteria"])
    rep["_wb_recs"] = wb
    rep["_enf_recs"] = [r for r in enforced if r.block]
    return rep


def criteria_checklist(crit, rep, g):
    out = []

    def add(name, ok, detail):
        out.append({"name": name, "ok": bool(ok), "detail": detail})
    if g.get("evidence", {}).get("type") == "none":
        add("evidence", False, "no shadow journal exists for this gate (%s)" % g["evidence"].get("why", ""))
    add("shadow_days>=%g" % crit["min_shadow_days"], rep.get("shadow_days", 0) >= crit["min_shadow_days"], "%s days of dated shadow records" % rep.get("shadow_days", 0))
    fresh = None
    if rep.get("newest_record"):
        fresh = (now() - (parse_ts(rep["newest_record"]) or 0)) / 86400.0
    add("fresh<=%gd" % crit["max_stale_days"], fresh is not None and fresh <= crit["max_stale_days"], "newest shadow record %s" % (("%.1f days old" % fresh) if fresh is not None else "n/a"))
    add("labelled>=%d" % crit["min_labelled"], rep.get("labelled", 0) >= crit["min_labelled"], "%d hand-checked would-block hit(s) (%d tp, %d fp)" % (rep.get("labelled", 0), rep.get("labelled_tp", 0), rep.get("labelled_fp", 0)))
    fp = rep.get("fp_rate")
    add("fp_rate<%g" % crit["max_fp_rate"], fp is not None and fp < crit["max_fp_rate"], "FP rate %s over the labelled hits" % ("n/a" if fp is None else "%.1f%%" % (100 * fp)))
    c = rep.get("p90_cost_s")
    add("p90_cost<%gs" % crit["max_p90_cost_s"], c is not None and c < crit["max_p90_cost_s"], "p90 cost %s (%s)" % ("unmeasured - run `attest %s cost --p90-s N --ref ...`" % g["id"] if c is None else "%.1fs" % c, rep.get("cost_source") or "-"))
    add("replay", rep.get("replay_attested"), "replay against history %s" % ("attested" if rep.get("replay_attested") else "not attested (`attest %s replay --ref ...`)" % g["id"]))
    add("rollback", bool(rep.get("rollback_cmd")), "one-command rollback: %s" % rep.get("rollback_cmd"))
    ur = rep.get("unverified_rate")
    if ur is not None:
        add("unverified<=%g" % crit["max_unverified_rate"], ur <= crit["max_unverified_rate"], "%.0f%% of shadow rows were UNVERIFIED (tools missing / could not run)" % (100 * ur))
    return out


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# watchdog (auto-demote)
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def wd_cfg(reg):
    w = dict(reg.get("watchdog", {}))
    w.setdefault("hard_stall_h", 3 * w.get("stall_h", 6))
    for env, k in (("OVN_GG_REPEAT_N", "repeat_block_n"), ("OVN_GG_REPEAT_H", "repeat_block_h"), ("OVN_GG_STALL_H", "stall_h"),
                   ("OVN_GG_STALL_MIN_BLOCKS", "stall_min_blocks"), ("OVN_GG_HARD_STALL_H", "hard_stall_h"), ("OVN_GG_ALERT_TTL_H", "alert_ttl_h")):
        if os.environ.get(env):
            w[k] = fnum(env, w.get(k, 1))
    return w


def exact_item_key(text):
    """Key of ONE item: md5 of its exact text (whitespace-normalised). NOT item_hash(), which is per [feat:...] tag, so the several steps of one feature would count as one item."""
    return hashlib.md5(re.sub(r"\s+", " ", (text or "").strip()).encode()).hexdigest()


def find_trips(reg, flags=None, ctx=None):
    """-> list of trips for ENFORCED gates: {gate, trigger, lane, item, count, window_h, samples[]}.
    repeat_block: the SAME item (exact text) refused repeat_block_n times in repeat_block_h.
    lane_stall: a lane with attempts and 0 landings for stall_h while one gate's refusals there rose. `proven` = there is evidence the refusals were WRONG (a human labelled one of them fp);
    an unproven stall is only alerted (a gate that refuses bad work is working: demoting it is the harm) until the lane has had 0 landings for hard_stall_h, when liveness wins."""
    flags = read_flags()[0] if flags is None else flags
    w = wd_cfg(reg)
    H = max(w["repeat_block_h"], w["stall_h"] * 2, w["hard_stall_h"])
    ctx = ctx or Ctx(days=H / 24.0 + 0.05)
    t_now = ctx.t_now
    paused = os.path.exists(os.path.join(state_dir(), "PAUSED"))
    trips = []
    lane_blocks = collections.defaultdict(lambda: collections.Counter())      # lane -> gate -> blocks in last stall_h
    lane_prev = collections.defaultdict(lambda: collections.Counter())        # lane -> gate -> would-blocks AND blocks (any mode) in the stall_h before that
    lane_samples = collections.defaultdict(list)
    lane_fp = collections.defaultdict(lambda: collections.Counter())          # lane -> gate -> refusals in the window a human labelled fp
    labels = ctx.labels()
    for g in reg["gates"]:
        mode, _ = effective(g, flags)
        if mode != "enforce" or (g.get("evidence") or {}).get("type") == "none":
            continue
        recs = collect(g, ctx)
        blocks = [r for r in recs if r.mode == "enforce" and r.block]
        per_item = collections.defaultdict(list)
        for r in blocks:
            ik = exact_item_key(r.item) if r.item else r.key
            per_item[(r.repo, ik)].append(r)
            if r.ts is not None:
                age_h = (t_now - r.ts) / 3600.0
                if age_h <= w["stall_h"]:
                    lane_blocks[r.repo][g["id"]] += 1
                    lane_samples[(r.repo, g["id"])].append(r.text[:120])
                    if (labels.get((g["id"], r.key)) or {}).get("label") == "fp":
                        lane_fp[r.repo][g["id"]] += 1
        # the previous window is compared against what the gate refused OR would have refused: a freshly enforced gate has no enforced history, and its shadow would-blocks are the baseline
        for r in recs:
            if r.block and r.ts is not None and w["stall_h"] < (t_now - r.ts) / 3600.0 <= 2 * w["stall_h"]:
                lane_prev[r.repo][g["id"]] += 1
        for (repo, ik), rs in per_item.items():
            recent = [r for r in rs if r.ts is not None and (t_now - r.ts) / 3600.0 <= w["repeat_block_h"]]
            if len(recent) >= w["repeat_block_n"]:
                trips.append({"gate": g["id"], "trigger": "repeat_block", "lane": repo, "item": ik, "item_text": (recent[0].item or "")[:100], "count": len(recent), "window_h": w["repeat_block_h"],
                              "samples": [r.text[:140] for r in recent[:3]]})
    if not paused:
        outs = ctx.outcomes()
        lo = t_now - w["stall_h"] * 3600
        lo_hard = t_now - w["hard_stall_h"] * 3600
        for lane, per_gate in lane_blocks.items():
            lane_out = [o for o in outs if o["_repo"] == lane and (o["_ts"] or 0) >= lo]
            attempts = [o for o in lane_out if o.get("class") != "skipped"]
            landed = [o for o in lane_out if o.get("class") in GOOD_CLASSES]
            if landed or not attempts:
                continue
            # the gate with the most refusals on this lane that ALSO rose vs the previous window
            cand = [(n, gid) for gid, n in per_gate.items() if n >= w["stall_min_blocks"] and n > lane_prev[lane][gid]]
            if not cand:
                continue
            n, gid = max(cand)
            hard_out = [o for o in outs if o["_repo"] == lane and (o["_ts"] or 0) >= lo_hard]
            hard = bool(hard_out) and not any(o.get("class") in GOOD_CLASSES for o in hard_out)
            fp = lane_fp[lane][gid]
            trips.append({"gate": gid, "trigger": "lane_stall", "lane": lane, "item": "", "count": n, "window_h": w["stall_h"], "proven": bool(fp or hard),
                          "proof": ("%d refusal(s) labelled fp" % fp) if fp else (("0 landings for %gh (hard stall)" % w["hard_stall_h"]) if hard else "none"),
                          "prev_count": lane_prev[lane][gid], "attempts": len(attempts), "samples": lane_samples[(lane, gid)][:3]})
    return trips


def alerted_path():
    return os.path.join(gg_dir(), "alerted.json")


def alert_once(key, msg, ttl_h, prio_note=True, level="warn"):
    """alerts.log warn line + one high-priority hourly-update note, at most once per key per ttl. -> True when emitted."""
    seen = read_json(alerted_path(), {})
    if not isinstance(seen, dict):
        seen = {}
    t = now()
    if t - seen.get(key, 0) < ttl_h * 3600:
        return False
    seen = {k: v for k, v in seen.items() if t - v < 7 * 86400}
    seen[key] = t
    atomic_write(alerted_path(), json.dumps(seen, sort_keys=True, indent=1) + "\n")
    try:
        with open(os.path.join(state_dir(), "alerts.log"), "a") as f:
            f.write("%s %s | gate-governor | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)), level, msg))
    except OSError:
        pass
    if prio_note:
        try:
            with open(os.path.join(state_dir(), "notify_notes.jsonl"), "a") as f:
                f.write(json.dumps({"ts": t, "title": "Gate governor: " + msg[:70], "text": msg[:160], "prio": "high", "source": "gate_governor"}, ensure_ascii=False) + "\n")
        except OSError:
            pass
    return True


def demote_updates(g, flags):
    """-> {VAR: value} that lowers gate g to shadow (member gates: drop the member from the list; bool gates: off)."""
    if g["kind"] == "member":
        members = [m for m in member_list(g, flags) if m != g["member"]]
        return {g["env"]: ",".join(members)}
    target = "shadow" if "shadow" in gate_modes(g) else "off"
    return {g["env"]: mode_value(g, target)}


def demote_fn(g):
    """callable form of demote_updates for write_flags (evaluated under the write lock)."""
    return lambda flags: demote_updates(g, flags)


def run_watchdog(reg, apply, ctx=None, flags=None):
    """-> list of result dicts. apply=True writes pilot_flags.env for demotable pilot_env gates."""
    flags = read_flags()[0] if flags is None else flags
    w = wd_cfg(reg)
    by_id = {g["id"]: g for g in reg["gates"]}
    results = []
    done_gates = set()
    for t in find_trips(reg, flags, ctx):
        g = by_id[t["gate"]]
        ev_txt = "%s on lane %s: %d refusal(s) in %gh%s%s | e.g. %s" % (
            t["trigger"], t["lane"], t["count"], t["window_h"],
            (" (prev window %d)" % t["prev_count"]) if "prev_count" in t else "",
            (", 0 landings, %d attempts, evidence refusals are wrong: %s" % (t["attempts"], t["proof"])) if t["trigger"] == "lane_stall" else (", item %s" % (t.get("item_text") or t["item"])[:60]),
            "; ".join(t["samples"])[:200])
        res = dict(t, gate_env=g["env"], action="none", applied=False, evidence=ev_txt)
        if g["channel"] != "pilot_env" or not g.get("demotable", True):
            res["action"] = "alert-only (channel %s: demote with `%s`)" % (g["channel"], ("bash qa/qa_enforce.sh %s shadow" % g["qa_gate"]) if g["channel"] == "qa_modes" else "remove %s from the cron line env" % g["env"])
        elif t["trigger"] == "lane_stall" and not t.get("proven"):
            res["action"] = "alert-only (stall with no evidence the refusals are wrong: label one fp, or demote by hand with `python3 scripts/ovn_gate_governor.py demote %s --apply`)" % g["id"]
        elif t["gate"] in done_gates:
            res["action"] = "already demoted this run"
            results.append(res)
            continue
        else:
            res["action"] = "demote %s -> shadow" % g["id"]
            if apply:
                try:
                    bid, new_sha = write_flags(demote_fn(g), "watchdog", "auto-demote", "%s %s" % (t["trigger"], t["lane"]))
                    res.update(applied=True, backup=bid)
                    done_gates.add(t["gate"])
                    flags = read_flags()[0]
                    audit(action="auto-demote", gate=g["id"], env=g["env"], trigger=t["trigger"], lane=t["lane"], count=t["count"], evidence=ev_txt, backup=bid, who="watchdog",
                          rollback="python3 scripts/ovn_gate_governor.py rollback --to %s --apply" % bid)
                except Exception as e:  # noqa: BLE001 - the watchdog must never raise into cron
                    res["action"] = "demote FAILED: %s" % e
                    audit(action="auto-demote-failed", gate=g["id"], error=str(e)[:200], who="watchdog")
        if res["applied"]:
            msg = "AUTO-DEMOTED %s (%s) to shadow: %s | rollback: python3 scripts/ovn_gate_governor.py rollback --to %s --apply" % (g["id"], g["env"], ev_txt, res.get("backup"))
        elif res["action"].startswith("alert-only (stall with no evidence"):
            msg = "ENFORCED GATE %s (%s) MAY BE STALLING lane %s - no evidence its refusals are wrong, so NOT auto-demoted: %s | %s" % (g["id"], g["env"], t["lane"], res["action"].split("`")[1], ev_txt)
        elif res["action"].startswith("alert-only"):
            msg = "ENFORCED GATE STALLING A LANE %s (%s), not governed here - demote by hand: %s | %s" % (g["id"], g["env"], res["action"].split("`")[1] if "`" in res["action"] else "", ev_txt)
        else:
            msg = "WOULD DEMOTE %s (%s) to shadow [OVN_GATE_GOVERNOR=%s: report-only]: %s" % (g["id"], g["env"], governor_mode(), ev_txt)
        would = not res["applied"] and res["action"].startswith("demote ")
        # one alert per trip per TTL. A pure WOULD-DEMOTE (report-only governor: nothing will change) is ONE line per gate+lane+trigger (not per item), no hourly-update note, and `info` level.
        key = "%s|%s|%s|%s|%s" % (t["gate"], t["trigger"], t["lane"], "" if would else t["item"], "applied" if res["applied"] else "would")
        res["alert_emitted"] = alert_once(key, msg, w["alert_ttl_h"], prio_note=not would, level="info" if would else "warn")
        results.append(res)
    return results


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# selfcheck
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def selfcheck(reg):
    """-> list of problems: registry env/default vs the real source tree."""
    probs = []
    root = ovn_dir()
    for g in reg["gates"]:
        if g["channel"] == "qa_modes":
            qc = os.path.join(root, "qa", "qa_common.py")
            if g["env"] != "OVN_QA_" + g["qa_gate"].upper().replace("-", "_"):
                probs.append("%s: env %s does not match qa_common's OVN_QA_<GATE> rule" % (g["id"], g["env"]))
            if not os.path.exists(os.path.join(root, "qa", "gate_%s.py" % g["qa_gate"])) and g["qa_gate"] not in ("staging_check", "staging_e2e", "wip_cap", "tool_health", "soak", "card_credit", "baseline", "mutation"):
                probs.append("%s: no qa/gate_%s.py" % (g["id"], g["qa_gate"]))
            continue
        files = g.get("default_files") or []
        if g["channel"] == "cron_env" and not g.get("consumers"):
            probs.append("%s: cron_env gate needs `consumers` (who reads it)" % g["id"])
        if g["kind"] == "member":
            f = os.path.join(root, g.get("default_members_file", ""))
            if not os.path.isfile(f):
                probs.append("%s: default_members_file missing" % g["id"])
                continue
            txt = open(f).read()
            if g["env"] not in txt:
                probs.append("%s: %s not referenced in %s" % (g["id"], g["env"], g["default_members_file"]))
            exp = "enforce" if g["member"] in default_members(g) else "shadow"
            if exp != g["default"]:
                probs.append("%s: registry default %s but code DEFAULT_ENFORCE says %s" % (g["id"], g["default"], exp))
            if not re.search(r"ALL_RULES\s*=\s*\([^)]*[\"']%s[\"']" % g["member"], txt):
                probs.append("%s: rule %s not in ALL_RULES" % (g["id"], g["member"]))
            continue
        found_any = False
        for rel in files:
            f = os.path.join(root, rel)
            if not os.path.isfile(f):
                probs.append("%s: default file %s missing" % (g["id"], rel))
                continue
            txt = open(f).read()
            if g["env"] not in txt:
                continue
            found_any = True
            defaults = set(re.findall(r"\$\{%s:-([A-Za-z0-9_]+)\}" % g["env"], txt))
            defaults |= set(re.findall(r"_sg_mode \"\$\{%s:-\}\" ([a-z]+)" % g["env"], txt))
            defaults |= set(m for m in re.findall(r"\"\$\{%s:-\}\" ([a-z]+)" % g["env"], txt))
            codev = (g.get("values") or {}).get(g["default"], g["default"])
            bad = {d for d in defaults if d and d != codev}
            if bad:
                probs.append("%s: %s defaults %s in %s but the registry says %s" % (g["id"], g["env"], sorted(bad), rel, codev))
        if files and not found_any:
            probs.append("%s: %s not referenced in any default_file" % (g["id"], g["env"]))
        if g["id"] == "supply_mutation":
            txt = open(os.path.join(root, "scripts", "ovn_mutation_supply.py")).read() if os.path.exists(os.path.join(root, "scripts", "ovn_mutation_supply.py")) else ""
            if g["env"] not in txt:
                probs.append("supply_mutation: env not in ovn_mutation_supply.py")
    return probs


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# promote / demote / rollback commands
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def find_gate(reg, gid):
    for g in reg["gates"]:
        if g["id"] == gid:
            return g
    raise KeyError(gid)


def strip_private(rep):
    return {k: v for k, v in rep.items() if not k.startswith("_")}


def cmd_promote(reg, args):
    g = find_gate(reg, args.gate)
    flags = read_flags()[0]
    cur, _ = effective(g, flags)
    to = args.to or "enforce"
    if to not in gate_modes(g):
        print("REFUSED: %s supports modes %s, not %s" % (g["id"], "/".join(gate_modes(g)), to))
        return 1
    if g["channel"] != "pilot_env":
        print("REFUSED: " + owner_hint(g, to))
        return 1
    if RANK[to] <= RANK[cur]:
        print("%s is already %s (target %s): not a promotion. Use `demote` to lower it." % (g["id"], cur, to))
        return 1
    override = bool(args.i_checked_the_samples)
    rep = gate_report(reg, g, Ctx(days=fnum("OVN_GG_PROMO_DAYS", 30)), flags)
    unmet = [c for c in rep["criteria"] if not c["ok"]]
    # shadow<-off is the harmless direction (cost only) and needs no evidence
    if cur == "off" and to == "shadow":
        unmet = []
    print("gate %s: %s -> %s   (%s=%s)" % (g["id"], cur, to, g["env"], mode_value(g, to) if g["kind"] != "member" else "list+%s" % g["member"]))
    for c in rep["criteria"]:
        print("  [%s] %-22s %s" % ("ok" if c["ok"] else "NO", c["name"], c["detail"]))
    if unmet and not override:
        print("REFUSED: %d promotion criteria not met. Nothing written. (Override only after reading the samples: --i-checked-the-samples --reason TEXT; it is logged.)" % len(unmet))
        audit(action="promote-refused", gate=g["id"], to=to, unmet=[c["name"] for c in unmet], who=who())
        return 1
    if unmet and override:
        if not (args.reason or "").strip():
            print("REFUSED: --i-checked-the-samples requires --reason TEXT (what you checked)")
            return 1
        print("OVERRIDE: promoting with %d unmet criteria on your word (logged): %s" % (len(unmet), ", ".join(c["name"] for c in unmet)))
    if g["kind"] == "member":
        updates = lambda fl: {g["env"]: ",".join(sorted(set(member_list(g, fl)) | {g["member"]}))}
        shown = {g["env"]: ",".join(sorted(set(member_list(g, flags)) | {g["member"]}))}
    else:
        updates = shown = {g["env"]: mode_value(g, to)}
    if not args.apply:
        print("DRY-RUN (no --apply): would write %s to %s" % (shown, flags_path()))
        return 0
    if governor_mode() == "off":
        print("OVN_GATE_GOVERNOR=off: refusing to write")
        return 1
    bid, _ = write_flags(updates, who(), "promote", args.reason or "")
    audit(action="promote", gate=g["id"], env=g["env"], frm=cur, to=to, override=bool(unmet), unmet=[c["name"] for c in unmet], reason=args.reason or "", backup=bid, who=who())
    print("PROMOTED %s to %s (live from the next run_overnight.sh start). Rollback, one line: python3 scripts/ovn_gate_governor.py rollback --to %s --apply" % (g["id"], to, bid))
    return 0


def cmd_demote(reg, args):
    g = find_gate(reg, args.gate)
    flags = read_flags()[0]
    cur, _ = effective(g, flags)
    to = args.to or ("shadow" if "shadow" in gate_modes(g) else "off")
    if to not in gate_modes(g):
        print("REFUSED: %s supports modes %s" % (g["id"], "/".join(gate_modes(g))))
        return 1
    if g["channel"] != "pilot_env":
        print("REFUSED: " + owner_hint(g, to))
        return 1
    cx = [c for c in complex_flag_lines() if g["env"] in c[2]]
    if RANK[to] >= RANK[cur] and not cx:
        print("%s is already %s: nothing to demote" % (g["id"], cur))
        return 1
    if cx:
        print("WARNING: pilot_flags.env line %d is not a plain assignment but mentions %s (`%s`): the mode shown (%s) may be wrong. Writing a governed line and VERIFYING it survives sourcing." % (cx[0][0], g["env"], cx[0][1], cur))
    if g["kind"] == "member":
        updates = lambda fl: {g["env"]: ",".join(m for m in member_list(g, fl) if m != g["member"])}
        shown = {g["env"]: ",".join(m for m in member_list(g, flags) if m != g["member"])}
    else:
        updates = shown = {g["env"]: mode_value(g, to)}
    print("gate %s: %s -> %s" % (g["id"], cur, to))
    if not args.apply:
        print("DRY-RUN (no --apply): would write %s to %s" % (shown, flags_path()))
        return 0
    # NOTE: OVN_GATE_GOVERNOR=off does NOT block this: the off switch stops AUTOMATION, and lowering a gate by hand is the emergency path.
    bid, _ = write_flags(updates, who(), "demote", args.reason or "")
    audit(action="demote", gate=g["id"], env=g["env"], frm=cur, to=to, reason=args.reason or "", backup=bid, who=who())
    print("DEMOTED %s to %s. Rollback, one line: python3 scripts/ovn_gate_governor.py rollback --to %s --apply" % (g["id"], to, bid))
    return 0


def restored_marker(bid):
    return os.path.join(backup_dir(), bid + ".restored")


def cmd_rollback(args):
    """Default target = the backup of the MOST RECENT promote / demote / auto-demote (the state before that change). Idempotent: once it has been restored, a retried `rollback --apply`
    is a no-op (rc 0) instead of re-applying the change that was just rolled back; older states need an explicit --to ID. The state a rollback replaces is kept as a `rollback-pre` backup."""
    ids = list_backups()
    kinds = backup_kinds()
    if args.list:
        for i in ids:
            print("%s  %s%s" % (i, kinds.get(i, "change"), "  (restored)" if os.path.exists(restored_marker(i)) else ""))
        return 0
    if not ids:
        print("no backups under %s" % backup_dir())
        return 1
    if args.to:
        bid = args.to
        if bid not in ids:
            print("unknown backup %s (see --list)" % bid)
            return 1
    else:
        changes = [i for i in ids if kinds.get(i, "change") == "change"]
        if not changes:
            print("nothing to roll back: no promote / demote backup exists (see --list)")
            return 1
        bid = changes[-1]
        if os.path.exists(restored_marker(bid)):
            print("nothing to roll back: the most recent change (backup %s) was already rolled back; pilot_flags.env is at its pre-change state. Older states: rollback --list, then --to ID" % bid)
            return 0
    print("rollback target: %s  (pilot_flags.env %s)" % (bid, "absent in that state" if os.path.exists(os.path.join(backup_dir(), bid + ".absent")) else "restored from backups/%s.env" % bid))
    if not args.apply:
        print("DRY-RUN (no --apply)")
        return 0
    with Lock("write"):
        pre = make_backup("rollback-pre")   # the state we are replacing stays recoverable
        ok = restore_backup(bid)
        if ok:
            atomic_write(restored_marker(bid), iso(now()) + "\n")
    audit(action="rollback", to_backup=bid, pre_rollback_backup=pre, verified=ok, who=who())
    print("ROLLED BACK to %s: %s (previous state kept as %s)" % (bid, "VERIFIED byte-identical" if ok else "VERIFY FAILED - pilot_flags.env does not match the backup, check by hand", pre))
    return 0 if ok else 1


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# rendering
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def render_md(reps, days):
    L = ["# Gate governor evidence report", "", "Generated %s, window %g days. Read-only: nothing here changed a switch." % (iso(now()), days), ""]
    prom = [r for r in reps if r["promotable"] and RANK.get(r["effective"], 0) < RANK["enforce"]]
    L += ["**%d gate(s) meet every promotion criterion; %d gates tracked.**" % (len(prom), len(reps)), ""]
    L += ["| gate | mode | would-block | credited anyway | confirmed bad | labelled (fp) | promotable |", "|---|---|---:|---:|---:|---:|---|"]
    for r in reps:
        L.append("| %s | %s (%s) | %s | %s | %s | %d (%d) | %s |" % (r["id"], r["effective"], r["source"], r.get("would_block", 0), r.get("credited_despite_would_block", "-"),
                                                               r.get("false_credits_confirmed", "-"), r.get("labelled", 0), r.get("labelled_fp", 0), "YES" if r["promotable"] else "no"))
    for r in reps:
        L += ["", "## %s - %s" % (r["id"], r["title"]), "", "- env `%s` default `%s` effective `%s` (from %s); channel %s" % (r["env"], r["default"], r["effective"], r["source"], r["channel"]),
              "- journals: " + ("; ".join("%s (%d file(s), newest %s)" % (j["path"], j["files"], j["newest"]) for j in r["journals"]) or "none")]
        if r.get("evidence_note"):
            L.append("- evidence: " + r["evidence_note"])
        L.append("- shadow records %d, would-block %d (by repo %s), enforced blocks %d, flagged %d, unverified %d" % (r["records"], r["would_block"], r["by_repo"] or "{}", r["enforced_blocks"], r["flagged"], r["unverified"]))
        if "credited_despite_would_block" in r:
            L.append("- credited despite a would-block: **%d**; blocked anyway (run already failed): %d; later turned out bad: %d (commit reverted in git / labelled tp) + %d (same item re-opened); same feature reverted later (informational): %d" % (
                r["credited_despite_would_block"], r["blocked_anyway"], r["later_bad_strong"], r["later_bad_reopened"], r["feature_later_reverted"]))
        L += ["", "Promotion criteria:"] + ["- [%s] `%s` - %s" % ("x" if c["ok"] else " ", c["name"], c["detail"]) for c in r["criteria"]]
        if r["fp_candidates"]:
            L += ["", "FP candidates for a human spot-check (label with `ovn_gate_governor.py label <gate> <key> tp|fp`):"]
            L += ["- `%s` %s %s credited=%s :: %s" % (c["key"], c["repo"], c["ts"] or "undated", c["credited"], c["text"]) for c in r["fp_candidates"][:8]]
        L += ["", "Promote: `%s`   Rollback: `%s`" % (r["promote_cmd"], r["rollback_cmd"])]
    return "\n".join(L) + "\n"


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def build_parser():
    p = argparse.ArgumentParser(prog="ovn_gate_governor.py", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd")
    sub.add_parser("list")
    sub.add_parser("status")
    r = sub.add_parser("report")
    r.add_argument("--gate")
    r.add_argument("--days", type=float, default=7.0)
    r.add_argument("--json", action="store_true")
    r.add_argument("--write", action="store_true")
    r.add_argument("--note", action="store_true", help="also queue ONE hourly-update note (weekly cron)")
    r.add_argument("--candidates", type=int, default=15, help="max FP candidates listed per gate (default 15)")
    lb = sub.add_parser("label")
    lb.add_argument("gate")
    lb.add_argument("key")
    lb.add_argument("label", choices=["tp", "fp"])
    lb.add_argument("--note", default="")
    at = sub.add_parser("attest")
    at.add_argument("gate")
    at.add_argument("what", choices=["replay", "cost"])
    at.add_argument("--ref", required=True)
    at.add_argument("--p90-s", type=float)
    for name in ("promote", "demote"):
        c = sub.add_parser(name)
        c.add_argument("gate")
        c.add_argument("--to")
        c.add_argument("--apply", action="store_true")
        c.add_argument("--reason", default="")
        if name == "promote":
            c.add_argument("--i-checked-the-samples", action="store_true")
    rb = sub.add_parser("rollback")
    rb.add_argument("--list", action="store_true")
    rb.add_argument("--to")
    rb.add_argument("--apply", action="store_true")
    wd = sub.add_parser("watchdog")
    wd.add_argument("--json", action="store_true")
    sub.add_parser("selfcheck")
    md = sub.add_parser("mode")
    md.add_argument("value", nargs="?", choices=["off", "shadow", "enforce"])
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    if not args.cmd:
        build_parser().print_help()
        return 2
    mode = governor_mode()
    if args.cmd == "mode":
        if args.value:
            with Lock("write"):
                prev = governor_mode()
                atomic_write(mode_file(), args.value + "\n")
            audit(action="mode", frm=prev, to=args.value, who=who())
            print("governor mode: %s -> %s (state/gate_governor/mode; env OVN_GATE_GOVERNOR overrides). Rollback: ovn_gate_governor.py mode shadow" % (prev, args.value))
        else:
            print("governor mode: %s%s" % (mode, " (env override)" if os.environ.get("OVN_GATE_GOVERNOR") else ""))
        return 0
    # off stops AUTOMATION and promotion, never the manual way DOWN: demote / rollback must keep working in an incident. A disabled command that would have CHANGED something
    # (promote / label / attest) exits 1 so a caller checking only the exit code is not told it worked; report / watchdog (cron) stay rc 0.
    if mode == "off" and args.cmd not in ("list", "status", "selfcheck", "demote", "rollback"):
        print("OVN_GATE_GOVERNOR=off: gate governor disabled (list/status/selfcheck/demote/rollback still work)")
        return 1 if args.cmd in ("promote", "label", "attest") else 0
    try:
        reg = load_registry()
    except RegistryError as e:
        print("REGISTRY ERROR: %s" % e, file=sys.stderr)
        return 2
    try:
        if args.cmd in ("list", "status"):
            flags = read_flags()[0]
            print("%-26s %-9s %-16s %-9s %s" % ("gate", "effective", "source", "default", "env"))
            for g in reg["gates"]:
                m, s = effective(g, flags)
                print("%-26s %-9s %-16s %-9s %s%s" % (g["id"], m, s, g["default"], g["env"], {"pilot_env": "", "qa_modes": "   [qa_modes: qa/qa_enforce.sh]", "cron_env": "   [cron_env: set in the cron line, not pilot_flags.env]"}[g["channel"]]))
            print("pilot_flags.env: %s (%s)   governor mode: %s" % (flags_path(), "present" if os.path.exists(flags_path()) else "absent", mode))
            known = {x["env"] for x in reg["gates"]}
            for n, txt, names in complex_flag_lines():
                hit = sorted(set(names) & known)
                if hit:
                    print("WARNING: pilot_flags.env line %d is not a plain assignment and mentions %s: `%s` - the modes above may be wrong for those gates" % (n, ",".join(hit), txt))
            return 0
        if args.cmd == "selfcheck":
            probs = selfcheck(reg)
            for p in probs:
                print("MISMATCH:", p)
            print("selfcheck: %d gate(s), %d problem(s)" % (len(reg["gates"]), len(probs)))
            return 1 if probs else 0
        if args.cmd == "report":
            gates = [find_gate(reg, args.gate)] if args.gate else reg["gates"]
            ctx = Ctx(days=args.days)
            reps = [gate_report(reg, g, ctx, max_candidates=args.candidates) for g in gates]
            clean = [strip_private(r) for r in reps]
            if args.json:
                print(json.dumps(clean, indent=1, sort_keys=True))
            else:
                print(render_md(clean, args.days))
            if args.write:
                d = os.path.join(gg_dir(), "reports")
                stamp = time.strftime("%Y-%m-%d", time.gmtime(now()))
                atomic_write(os.path.join(d, stamp + ".md"), render_md(clean, args.days))
                atomic_write(os.path.join(d, stamp + ".json"), json.dumps(clean, indent=1, sort_keys=True) + "\n")
                audit(action="report", gates=len(clean), path=os.path.join(d, stamp + ".md"), who=who())
            if args.note:
                n_prom = len([r for r in clean if r["promotable"] and RANK.get(r["effective"], 0) < RANK["enforce"]])
                n_cred = sum(r.get("credited_despite_would_block", 0) for r in clean)
                with open(os.path.join(state_dir(), "notify_notes.jsonl"), "a") as f:
                    f.write(json.dumps({"ts": now(), "title": "Gate evidence: %d gate(s) promotable, %d shadow would-block(s) credited anyway" % (n_prom, n_cred),
                                        "text": "Weekly gate-governor report written to state/gate_governor/reports/.", "prio": "default", "source": "gate_governor"}) + "\n")
            return 0
        if args.cmd == "label":
            g = find_gate(reg, args.gate)
            rec = {"ts": iso(now()), "gate": g["id"], "key": args.key, "label": args.label, "note": args.note[:200], "who": who()}
            with Lock("write"):
                append_jsonl(os.path.join(gg_dir(), "labels.jsonl"), rec)
            audit(action="label", gate=g["id"], key=args.key, label=args.label, who=who())
            print("labelled %s %s = %s" % (g["id"], args.key, args.label))
            return 0
        if args.cmd == "attest":
            g = find_gate(reg, args.gate)
            with Lock("write"):
                a = attestations()
                e = a.setdefault(g["id"], {})
                e[args.what] = {"ref": args.ref[:300], "ts": iso(now()), "who": who()}
                if args.what == "cost":
                    if args.p90_s is None:
                        print("attest cost needs --p90-s N")
                        return 2
                    e["cost"]["p90_s"] = args.p90_s
                atomic_write(attest_path(), json.dumps(a, indent=1, sort_keys=True) + "\n")
            audit(action="attest", gate=g["id"], what=args.what, ref=args.ref[:200], who=who())
            print("attested %s for %s" % (args.what, g["id"]))
            return 0
        if args.cmd == "promote":
            return cmd_promote(reg, args)
        if args.cmd == "demote":
            return cmd_demote(reg, args)
        if args.cmd == "rollback":
            return cmd_rollback(args)
        if args.cmd == "watchdog":
            with Lock("watchdog", wait=False) as lk:
                if not lk.held:
                    print("watchdog: another run holds the lock; skipping")
                    return 0
                res = run_watchdog(reg, mode == "enforce")   # auto-demote ONLY in enforce; shadow reports + alerts once
            if args.json:
                print(json.dumps(res, indent=1, sort_keys=True))
            else:
                if not res:
                    print("watchdog: no enforced gate is stalling a lane (mode=%s)" % mode)
                for r in res:
                    print("%s %s lane=%s -> %s%s" % (r["gate"], r["trigger"], r["lane"], r["action"], " [APPLIED]" if r["applied"] else ""))
                    print("    " + r["evidence"])
            return 0
    except KeyError as e:
        print("unknown gate %s (try `list`)" % e, file=sys.stderr)
        return 2
    except RuntimeError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
