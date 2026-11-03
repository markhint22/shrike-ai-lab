#!/usr/bin/env python3
"""ovn_supply_filter.py - the ONE definition of a "doable" open item (package P5-supply-truth, 2026-11-02).

Before: ovn_notify._doable (excluded AUTO-SKIP/HUMAN-ONLY/human//[CLAUDE]/BLOCKED ITEM/(retired-), fleet_stats.queue_counts (no [CLAUDE] exclusion) and
ovn_stats.runway each carried their own regex, so the same repo showed doable 0 in one place and 3 in another, and 'pullable' (open backlog lines the lane may pull,
ovn_supply_ledger.current_pullable) was read as 'the lane has work' although 13 of billwatch's open lines were [CLAUDE]-routed and 14 AUTO-SKIP (pullable 52 vs doable 19).

An open item is a progress-file line starting with '- [ ]'. It is doable unless it matches an exclusion; each excluded line is counted under the FIRST matching reason
(order below), so open == doable + sum(excluded.values()).
"""
import os
import re

# (reason, regex) in priority order. Same alternation the old ovn_notify._doable used (case-insensitive; a bare 'human' is NOT an exclusion).
REASONS = (
    ("auto-skip", re.compile(r"AUTO-SKIP", re.I)),
    ("claude", re.compile(r"\[CLAUDE\]", re.I)),
    ("human-only", re.compile(r"HUMAN-ONLY|human/", re.I)),
    ("blocked", re.compile(r"BLOCKED ITEM", re.I)),
    ("retired", re.compile(r"\(retired-", re.I)),
)


def is_open(line):
    return line.startswith("- [ ]")


def exclusion(line):
    """Reason an OPEN line is not doable, or None when it is doable (or not an open line at all)."""
    if not is_open(line):
        return None
    for name, rx in REASONS:
        if rx.search(line):
            return name
    return None


def count_text(text):
    """{open, doable, excluded:{reason:n}} for the text of an OVERNIGHT_PROGRESS.md."""
    open_n = 0
    exc = {}
    for l in text.split("\n"):
        if not is_open(l):
            continue
        open_n += 1
        r = exclusion(l)
        if r:
            exc[r] = exc.get(r, 0) + 1
    return {"open": open_n, "doable": open_n - sum(exc.values()), "excluded": exc}


def count_repo(repo_dir):
    """count_text of <repo_dir>/OVERNIGHT_PROGRESS.md, or None when the file cannot be read."""
    try:
        text = open(os.path.join(repo_dir, "OVERNIGHT_PROGRESS.md"), errors="replace").read()
    except OSError:
        return None
    return count_text(text)


def excluded_str(exc):
    """'claude=13 auto-skip=14' (largest first, stable), '' when nothing is excluded."""
    return " ".join("%s=%d" % kv for kv in sorted(exc.items(), key=lambda kv: (-kv[1], kv[0])))


# ---------------------------------------------------------------- eligible backlog (P5 FX-P5, 2026-11-02)
_OPEN_T = re.compile(r"^- \[ \] \[T[1-5]\]")


def _load_sibling(name):
    """Load a sibling module by path (None when it cannot be loaded): eligibility (parked/norm/target) and work_supply (frozen list)."""
    import importlib.util
    try:
        spec = importlib.util.spec_from_file_location(name + "_for_filter", os.path.join(os.path.dirname(os.path.abspath(__file__)), name + ".py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception:
        return None


def eligible_backlog(backlog_text, progress_text="", done_text="", repo_root=None):
    """Distinct open backlog T-lines the lane could still be fed: not excluded by the shared doable filter (AUTO-SKIP, [CLAUDE], HUMAN-ONLY, BLOCKED ITEM, (retired-),
    not parked (ovn_backlog_eligibility.is_parked), not on the repo's AGENTS.md frozen list (when repo_root is given) and not already queued/done in the progress/done files."""
    elig = _load_sibling("ovn_backlog_eligibility")
    ws = _load_sibling("ovn_work_supply") if repo_root else None
    frozen = []
    if ws is not None:
        try:
            frozen = ws.frozen_paths(repo_root)
        except Exception:
            frozen = []

    def norm(l):
        if elig is not None:
            try:
                return elig.norm_line(l)
            except Exception:
                pass
        return re.sub(r"\s+", " ", l.strip().lower())
    queued = {norm(l) for l in (progress_text + "\n" + done_text).split("\n") if l.lstrip().startswith("- [")}
    seen, out = set(), []
    for l in backlog_text.split("\n"):
        if not _OPEN_T.match(l) or exclusion(l):
            continue
        if elig is not None:
            try:
                if elig.is_parked(l):
                    continue
            except Exception:
                pass
        if frozen and elig is not None:
            tgt = elig.item_target(l)
            if tgt and ws.frozen_hit(tgt, frozen, repo_root):
                continue
        k = norm(l)
        if k in queued or k in seen:
            continue
        seen.add(k)
        out.append(l)
    return out


def eligible_supply(root, repo, doable=None):
    """(eligible, doable_used, eligible_backlog_n) for <root>/repos/<repo> + <root>/backlog/<repo>.md; eligible is None when the progress file is unreadable."""
    rd = os.path.join(root, "repos", repo)

    def rd_(p):
        try:
            return open(p, errors="replace").read()
        except OSError:
            return ""
    det = count_repo(rd)
    if det is None:
        return None, doable, 0
    dn = det["doable"] if doable is None else doable
    n = len(eligible_backlog(rd_(os.path.join(root, "backlog", repo + ".md")), rd_(os.path.join(rd, "OVERNIGHT_PROGRESS.md")), rd_(os.path.join(rd, "OVERNIGHT_DONE.md")), rd))
    return dn + n, dn, n
