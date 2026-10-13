#!/usr/bin/env python3
"""ovn_progress_merge.py - deterministic 3-way merge for the fleet's line-oriented progress files
(OVERNIGHT_PROGRESS.md / OVERNIGHT_DONE.md), plus the git plumbing around it. (2026-10-12, package conflict)

WHY
  Every lane's OVERNIGHT_PROGRESS.md is edited by several writers at once: the 27B fleet (overnight/feature), interactive Claude sessions
  (claude/feature, hand-ticking items), reconcile_branches.sh (develop -> feature merges) and branch_hygiene.sh (feature -> develop). A plain
  text merge conflicts as soon as two writers touch the same line or append at the same end of the file. 2026-10-12 04:02-07:02 UTC: iptv_apps
  overnight/feature -> develop CONFLICTED in 5 consecutive hygiene passes (a claude/feature session had ticked the limiter.py item [x] while the
  fleet appended 10 commits of new items and added a tag to the same line); the whole lane sat blocked until a human resolved it (c7be7d3c).
  The resolution is mechanical, so it is done by code.

RULES (item = a line starting '- [ ] ' / '- [x] ' / '- [X] '; identity = ovn_item_hash semantics, see item_hash())
  * per item: if either side has it CHECKED the merged item is checked ([x] beats [ ]); the checked side's whole line is kept
  * both sides changed an item and neither checked it: ours' line (ours = the branch being merged INTO), unless one side left it equal to base
  * items present on both sides are never dropped; an item new on either side is kept (union); an item is never duplicated
  * an item deleted on ONE side (archived into OVERNIGHT_DONE.md, parked out of the flow, retired) is deleted in the result - also when the other
    side merely edited it (a deliberate move/removal beats a tag edit; the item still lives wherever it was moved to)
  * order: ours' order is kept; items/lines only theirs has go right before the next line they precede in theirs that survives, else at the end
  * identity falls back to a 'core' key (the item text after its leading [tag] / (note) groups) when the item hash differs because the text of
    an item without a [feat:...] tag was rewritten - without it a rewritten item would show up twice (old text + new text)
  * a REOPEN CANNOT WIN (documented behaviour): [x] beats [ ] always, so an item ticked on one side and deliberately un-ticked on the other stays ticked
  * an item REWRITTEN on one side whose other copy is CHECKED is not paired by the rules above (text changed -> different identity); rather than drop the
    checked work the merge DECLINES (plain text merge = a normal conflict for a human)
  * MODERATE reword (review M2): base item unchecked, one side ticked it, the other side deleted it and has an unpaired new item in the same gap (a reword
    below REWRITE_SIM) -> BOTH lines are kept (ticked old + new text): a duplicate is safer than a silently lost tick
  * a non-item line (status line, section header) edited on BOTH sides is paired by similarity to the base line they both changed and ours' version wins
    (no 'Status: 6 done' + 'Status: 7 done'); lines new on one side only are kept
  * pairing a both-edited non-item line needs a UNIQUE best match (a tie pairs nothing, both are kept); lines < 20 chars also pair on a common prefix
  * ALL modes run under a wall-clock alarm (OVN_PM_ALARM_S; driver 20s, others 45s) and _pair_both_edited declines above PAIR_CAP evaluations: a decline = plain
    text merge / abort, never a half-merged index (results are computed for every file before anything is written)
  * declines (plain text merge) when any input has more than MAX_LINES lines (the alignment is quadratic) or contains a committed conflict-marker line
    (<<<<<<< / ======= / >>>>>>>); the git driver additionally runs under a wall-clock alarm (DRIVER_ALARM_S) so it can never hang a merge
  Anything the rules cannot place safely is not guessed: a post-merge self-check (no item present on both sides lost, no duplicate, checked stays
  checked, for items whose hash is unique in every version) raising -> the caller falls back to the plain git text merge = a normal conflict.

USAGE (all modes: --log FILE appends one line per resolution, --tag TEXT labels it; default log = <this dir>/../state/progress_merge.log)
  ovn_progress_merge.py --driver %O %A %B [%L [%P]]   git merge driver: result is written into %A, exit 0 = resolved (always, by design)
  ovn_progress_merge.py --merge BASE OURS THEIRS [--out FILE]   merge three files (stdout when no --out), exit 1 when it declines
  ovn_progress_merge.py --resolve-index WORKTREE      a `git merge` stopped with conflicts: when EVERY unmerged path is one of the two progress files
                                                      at the repo root, resolve them from the index stages and `git add` them (exit 0); anything
                                                      else (other conflicted file, delete/modify, error) -> touch nothing, exit 1 (caller aborts)
  ovn_progress_merge.py --check-index WORKTREE        like --resolve-index but read-only: exit 0 = it WOULD resolve (nothing written/added), else 1
  ovn_progress_merge.py --setup-clone REPO            per-clone wiring: $GIT_DIR/info/attributes 'OVERNIGHT_PROGRESS.md merge=ovn-progress' (+DONE) and
                                                      `git config merge.ovn-progress.driver`. Never global config. OVN_PROGRESS_MERGE=off removes it.
FILES
  PROGRESS_FILES = OVERNIGHT_PROGRESS.md, OVERNIGHT_DONE.md, CLAUDE_QUEUE.md (all '- [ ] item' line-oriented; CLAUDE_QUEUE.md items carry [feat:...] tags and
  long VERIFY clauses, the item-hash/core-key logic is shape-agnostic). The git driver attributes have no slash so git applies them to a file of that name at ANY depth;
  --resolve-index (the gated hygiene path) only resolves them at the REPO ROOT - a progress file in a subdirectory conflicting declines (human).
UNGATED RESOLUTIONS (read this)
  The driver is wired PER CLONE (--setup-clone), so ANY `git merge` / `git pull --rebase` in a wired clone that runs WITHOUT OVN_PM_DEFER=1 resolves these files
  silently and WITHOUT the build/test gate: interactive sessions, headless Claude, ad-hoc merges in the box clones. The fleet's own landing paths set OVN_PM_DEFER=1
  (branch_hygiene.sh: main merge, QA-clean-prefix re-merge, push-retry pull --rebase; reconcile_branches.sh: feature sync merge + push-retry). Every driver resolution
  is logged to state/progress_merge.log with the marker 'ungated' so it can be audited. reconcile does NOT gate or land progress-only conflicts at all: it flags/logs
  them (--check-index) and hygiene lands them under its gate.
ENV
  OVN_PROGRESS_MERGE=off   kill switch: driver falls back to the plain text merge, --resolve-index declines, --setup-clone unwires the clone
  OVN_PM_DEFER=1           the driver behaves as the plain text merge (conflict markers + exit 1). branch_hygiene.sh / reconcile_branches.sh set it
                           on their FIRST merge attempt so a progress-file conflict surfaces and is resolved by --resolve-index UNDER the build/test
                           gate (resolve -> gate -> commit) instead of silently inside `git merge`.
"""
import difflib
import hashlib
import os
import re
import signal
import subprocess
import sys
import time

DRIVER_NAME = "ovn-progress"
PROGRESS_FILES = ("OVERNIGHT_PROGRESS.md", "OVERNIGHT_DONE.md", "CLAUDE_QUEUE.md")
MAX_LINES = 6000        # per input; the alignment is quadratic on pathological (many identical lines) files
DRIVER_ALARM_S = 20     # wall-clock cap for driver mode
MARKER_RE = re.compile(r"^(<{7}( .*)?|={7}|>{7}( .*)?)$")
REWRITE_SIM = 0.85      # similarity for 'this new item is a rewrite of that checked base item'
SIM_MIN = 0.6           # similarity for pairing a non-item line both sides edited
SHORT_LEN = 20          # a non-item line shorter than this also pairs on a common prefix (a short header scores < SIM_MIN on difflib alone)
PAIR_CAP = 250000       # max (unmatched base lines x new lines) similarity evaluations in _pair_both_edited; above it the merge DECLINES (no half merge)
MODE_ALARM_S = 45       # wall-clock cap for --merge / --resolve-index / --check-index (hygiene gives resolve 120s, reconcile gives check 60s)

ITEM_RE = re.compile(r"^- \[([ xX])\] ")
FEAT_RE = re.compile(r"\[feat:[^\]]+\]")
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))


# ----------------------------------------------------------------------------------------------------------------------------------
# identity
# ----------------------------------------------------------------------------------------------------------------------------------
def item_hash(line):
    """Python twin of lib_item_select.sh::ovn_item_hash (the identity the item guard, queue_refill and the stage runner use):
    strip the checkbox; a [feat:...] tag (first one) with its embedded date stamp removed is the key, else the whole text."""
    text = ITEM_RE.sub("", line, count=1)
    m = FEAT_RE.search(text)
    if m:
        key = m.group(0)
        key = re.sub(r"-[0-9]{8}-", "-", key, count=1)
        key = re.sub(r"-[0-9]{6}-", "-", key, count=1)
        return hashlib.md5(key.encode("utf-8", "surrogateescape")).hexdigest()
    return hashlib.md5(text.encode("utf-8", "surrogateescape")).hexdigest()


def _skip_groups(text):
    """Strip leading [tag] / (note) / {meta} groups (balanced, nested ok) and whitespace."""
    pairs = {"[": "]", "(": ")", "{": "}"}
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i] in " \t":
            i += 1
        if i >= n or text[i] not in pairs:
            break
        op, cl = text[i], pairs[text[i]]
        depth, j = 0, i
        while j < n:
            if text[j] == op:
                depth += 1
            elif text[j] == cl:
                depth -= 1
                if depth == 0:
                    break
            j += 1
        if depth != 0:  # unbalanced -> stop stripping, keep the rest as is
            break
        i = j + 1
    return text[i:]


def core_key(line):
    """Fallback identity for an item whose hash changed because its text was rewritten (no [feat:] tag): the text after the leading
    tag/note groups, whitespace-collapsed, lower-cased. None when too short to identify anything. Two cores are the same item when equal or
    when one is a prefix of the other (a trailing '(cat:..)' / VERIFY clause was added or dropped) - see same_core()."""
    text = ITEM_RE.sub("", line, count=1)
    core = re.sub(r"\s+", " ", _skip_groups(text)).strip().lower()
    return core if len(core) >= 12 else None


def same_core(a, b):
    if a is None or b is None:
        return False
    if a == b:
        return True
    return min(len(a), len(b)) >= 40 and (a.startswith(b) or b.startswith(a))


class Line(object):
    __slots__ = ("text", "is_item", "checked", "sig", "core", "blank")

    def __init__(self, text):
        self.text = text
        m = ITEM_RE.match(text)
        self.is_item = bool(m)
        self.checked = bool(m) and m.group(1) in "xX"
        self.blank = text.strip() == ""
        if self.is_item:
            self.sig = ("I", item_hash(text))
            self.core = core_key(text)
        else:
            self.sig = ("L", text)
            self.core = None


# ----------------------------------------------------------------------------------------------------------------------------------
# alignment
# ----------------------------------------------------------------------------------------------------------------------------------
def _match_gap(A, B, ai, bi, out):
    """Tier 2 inside one unmatched gap: pair leftover items by core key, in order, never crossing."""
    jptr = bi[0] if bi else 0
    bend = (bi[-1] + 1) if bi else 0
    used = set(out.values())
    for i in ai:
        c = A[i].core
        if c is None:
            continue
        for j in range(jptr, bend):
            if same_core(B[j].core, c) and j not in used:
                out[i] = j
                used.add(j)
                jptr = j + 1
                break


def align(A, B, allow_blank=True, allow_nonitem=True):
    """Order-preserving matching of two line lists -> dict {index in A: index in B}. Tier 1: equal signature (item hash / identical text);
    tier 2: equal core key among the items left over in the same gap. allow_* restrict which non-item lines may pair up."""
    def sig_of(L, k):
        x = L[k]
        if x.is_item:
            return x.sig
        if (x.blank and not allow_blank) or (not allow_nonitem):
            return ("U", id(x))  # unique -> never matches
        return x.sig

    sa = [sig_of(A, i) for i in range(len(A))]
    sb = [sig_of(B, j) for j in range(len(B))]
    sm = difflib.SequenceMatcher(None, sa, sb, autojunk=False)
    res = {}
    pa = pb = 0
    for a, b, n in sm.get_matching_blocks():
        ai = [i for i in range(pa, a) if A[i].is_item and A[i].core is not None]
        bi = [j for j in range(pb, b) if B[j].is_item and B[j].core is not None]
        if ai and bi:
            _match_gap(A, B, ai, bi, res)
        for k in range(n):
            res[a + k] = b + k
        pa, pb = a + n, b + n
    _global_pass(A, B, res, sa, sb)
    return res


def _global_pass(A, B, res, sa, sb):
    """Order-free pass over what the ordered matching left over (an item moved to another section, or two independent additions of the
    same item in a different order on the two sides): equal signature first (non-blank lines too), then same_core among items."""
    used_b = set(res.values())
    left_a = [i for i in range(len(A)) if i not in res]
    left_b = [j for j in range(len(B)) if j not in used_b]
    if not left_a or not left_b:
        return
    by_sig = {}
    for j in left_b:
        if sb[j][0] != "U" and not B[j].blank:
            by_sig.setdefault(sb[j], []).append(j)
    for i in left_a:
        if sa[i][0] != "U" and not A[i].blank and by_sig.get(sa[i]):
            j = by_sig[sa[i]].pop(0)
            res[i] = j
            used_b.add(j)
    left_a = [i for i in left_a if i not in res and A[i].is_item and A[i].core is not None]
    left_b = [j for j in left_b if j not in used_b and B[j].is_item and B[j].core is not None]
    if len(left_a) * len(left_b) > 4000000:
        return
    for i in left_a:
        for j in left_b:
            if j not in used_b and same_core(A[i].core, B[j].core):
                res[i] = j
                used_b.add(j)
                break


# ----------------------------------------------------------------------------------------------------------------------------------
# the merge
# ----------------------------------------------------------------------------------------------------------------------------------
def split_text(data):
    """bytes -> (list of line strings, ends_with_newline). utf-8 with surrogateescape: any byte sequence round-trips."""
    text = data.decode("utf-8", "surrogateescape")
    if text == "":
        return [], False
    nl = text.endswith("\n")
    lines = text.split("\n")
    if nl:
        lines.pop()
    return lines, nl


def join_text(lines, nl):
    if not lines:
        return b""
    return ("\n".join(lines) + ("\n" if nl else "")).encode("utf-8", "surrogateescape")


class _Deadline(object):
    """SIGALRM wall-clock cap around the pure-computation part of a mode: raises TimeoutError, which every mode turns into a decline (plain text merge /
    abort, nothing written). env OVN_PM_ALARM_S overrides; no-op where SIGALRM does not exist."""
    def __init__(self, default_s):
        self.s = int(os.environ.get("OVN_PM_ALARM_S", default_s))
        self.old = None

    def __enter__(self):
        if hasattr(signal, "SIGALRM") and self.s > 0:
            def _on_alarm(signum, frame):
                raise TimeoutError("merge exceeded %ds" % self.s)
            self.old = signal.signal(signal.SIGALRM, _on_alarm)
            signal.alarm(self.s)
        return self

    def __exit__(self, *exc):
        if hasattr(signal, "SIGALRM") and self.s > 0:
            signal.alarm(0)
            if self.old is not None:
                signal.signal(signal.SIGALRM, self.old)
        return False


class MergeStats(dict):
    def __missing__(self, k):
        return 0


def _short_prefix_pair(a, b):
    """Short lines (headers like '## S' vs '## S (edit1)') score < SIM_MIN on difflib alone: one being a prefix of the other (>= 4 chars) is a pair."""
    a, b = a.strip(), b.strip()
    return min(len(a), len(b)) >= 4 and max(len(a), len(b)) < SHORT_LEN * 2 and (a.startswith(b) or b.startswith(a))


def _pair_both_edited(B, sub_o, sub_t, m_bo, m_bt, m_ot):
    """A non-item base line that BOTH sides edited (so it matches neither): pair the most similar new line of each side so only ours' edit is kept.
    The best match must be UNIQUE (a tie = ambiguous = no pairing: both lines are kept, a duplicate status line is safer than dropping an unrelated one).
    Raises ValueError (decline) when the work exceeds PAIR_CAP so a pathological file cannot run for minutes."""
    used_o, used_t = set(m_ot), set(m_ot.values())
    in_bo, in_bt = set(m_bo), set(m_bt)
    cands = [i for i, bl in enumerate(B) if not (bl.is_item or bl.blank or i in in_bo or i in in_bt)]
    cap = int(os.environ.get("OVN_PM_PAIR_CAP", PAIR_CAP))
    if len(cands) * (len(sub_o) + len(sub_t)) > cap:
        raise ValueError("both-edited pairing too large (%d base x %d+%d new lines > %d): declined" % (len(cands), len(sub_o), len(sub_t), cap))

    def best(bl, sub, used):
        top, pick, tie = SIM_MIN, None, False
        for k, x in enumerate(sub):
            if k in used or x.is_item or x.blank:
                continue
            if len(bl.text) < SHORT_LEN and _short_prefix_pair(bl.text, x.text):
                r = 0.9
            else:
                sm = difflib.SequenceMatcher(None, bl.text, x.text, autojunk=False)
                if not (sm.real_quick_ratio() >= top and sm.quick_ratio() >= top):
                    continue
                r = sm.ratio()
                if r < top:
                    continue
            if pick is not None and r == top:
                tie = True
            elif r > top or pick is None:
                top, pick, tie = r, k, False
        return None if tie else pick

    for i in cands:
        bl = B[i]
        a, b = best(bl, sub_o, used_o), best(bl, sub_t, used_t)
        if a is not None and b is not None:
            m_ot[a] = b
            used_o.add(a)
            used_t.add(b)


def _rewrite_drops_checked(base_line, surviving, other_new):
    """base item deleted on one side while the OTHER side kept it CHECKED (and base was unchecked): if the deleting side has a new unpaired item that
    reads like a rewrite of it, the tick would be lost silently -> True (caller declines)."""
    if not (surviving.checked and not base_line.checked and base_line.is_item):
        return False
    bc = base_line.core
    if bc is None:
        return False
    for x in other_new:
        if x.is_item and x.core and difflib.SequenceMatcher(None, bc, x.core, autojunk=False).ratio() >= REWRITE_SIM:
            return True
    return False


def _tick_kept(base_line, surviving):
    return base_line.is_item and not base_line.checked and surviving.checked


def _gap_has_new(g, nbase, gid_x, in_x, X, in_other):
    """Does side X have an UNPAIRED new/rewritten item in the gap where base line g used to be (between the nearest base lines before/after g that X
    still has)? Used for 'base item unchecked, the other side ticked it, this side deleted it': an unpaired new item right there is probably its rewrite."""
    lo, hi = -1, len(X)
    for b in range(g - 1, -1, -1):
        if b in in_x:
            lo = in_x[b]
            break
    for b in range(g + 1, nbase):
        if b in in_x:
            hi = in_x[b]
            break
    return any(X[p].is_item and gid_x[p] >= nbase and gid_x[p] not in in_other for p in range(lo + 1, hi))


def merge_lines(base_l, ours_l, theirs_l):
    """3-way merge of three line lists by item identity -> (merged lines, stats)."""
    B = [Line(t) for t in base_l]
    O = [Line(t) for t in ours_l]
    T = [Line(t) for t in theirs_l]
    st = MergeStats()
    m_bo = align(B, O)
    m_bt = align(B, T)
    gid_o = {j: i for i, j in m_bo.items()}
    gid_t = {k: i for i, k in m_bt.items()}
    nxt = len(B)
    # lines new on BOTH sides that are the same thing (both added the same item / the same header)
    o_new = [j for j in range(len(O)) if j not in gid_o]
    t_new = [k for k in range(len(T)) if k not in gid_t]
    sub_o = [O[j] for j in o_new]
    sub_t = [T[k] for k in t_new]
    m_ot = align(sub_o, sub_t, allow_blank=False)
    _pair_both_edited(B, sub_o, sub_t, m_bo, m_bt, m_ot)
    for a, b in m_ot.items():
        gid_o[o_new[a]] = nxt
        gid_t[t_new[b]] = nxt
        nxt += 1
    for j in range(len(O)):
        if j not in gid_o:
            gid_o[j] = nxt
            nxt += 1
    for k in range(len(T)):
        if k not in gid_t:
            gid_t[k] = nxt
            nxt += 1
    new_o = [O[j] for j in range(len(O)) if gid_o[j] >= len(B)]
    new_t = [T[k] for k in range(len(T)) if gid_t[k] >= len(B)]
    in_o = {gid_o[j]: j for j in range(len(O))}
    in_t = {gid_t[k]: k for k in range(len(T))}

    def pick(g):
        """-> line text to output for a group present in at least one side, or None to drop it."""
        jo, kt, ib = in_o.get(g), in_t.get(g), g if g < len(B) else None
        if jo is not None and kt is not None:
            lo, lt = O[jo], T[kt]
            if lo.text == lt.text:
                return lo.text
            st["both_changed"] += 1
            if lo.checked != lt.checked:
                st["checked_wins"] += 1
                return lo.text if lo.checked else lt.text
            if ib is not None:
                if lo.text == B[ib].text:
                    return lt.text
                if lt.text == B[ib].text:
                    return lo.text
            return lo.text
        if ib is not None:  # one side deleted it
            if jo is not None and _rewrite_drops_checked(B[ib], O[jo], new_t):
                raise ValueError("checked item rewritten on theirs would lose its tick: %r" % O[jo].text[:60])
            if kt is not None and _rewrite_drops_checked(B[ib], T[kt], new_o):
                raise ValueError("checked item rewritten on ours would lose its tick: %r" % T[kt].text[:60])
            # moderate reword (below REWRITE_SIM): keep the ticked old line AND the other side's new line - a duplicate beats a silently lost tick
            if jo is not None and _tick_kept(B[ib], O[jo]) and _gap_has_new(ib, len(B), gid_t, in_t, T, in_o):
                st["kept_checked_reword"] += 1
                return O[jo].text
            st["deleted"] += 1
            if (jo is not None and O[jo].text != B[ib].text) or (kt is not None and T[kt].text != B[ib].text):
                st["delete_beats_edit"] += 1
            return None
        # new on one side only -> union
        if jo is not None:
            st["new_ours"] += 1
            return O[jo].text
        st["new_theirs"] += 1
        return T[kt].text

    out, out_pos_gid = [], {}
    for j in range(len(O)):
        g = gid_o[j]
        txt = pick(g)
        if txt is None:
            continue
        out_pos_gid[g] = len(out)
        out.append((g, txt))
    # theirs-only (new) groups: before the next theirs line whose group survives from ours' sequence, else at the end
    before = {}
    tail = []
    for k in range(len(T)):
        g = gid_t[k]
        if g in in_o:
            continue  # shared with ours (placed above) or deleted
        if g < len(B):  # a base line ours deleted (theirs kept or edited it)
            if _rewrite_drops_checked(B[g], T[k], new_o):
                raise ValueError("checked item rewritten on ours would lose its tick: %r" % T[k].text[:60])
            if _tick_kept(B[g], T[k]) and _gap_has_new(g, len(B), gid_o, in_o, O, in_t):
                st["kept_checked_reword"] += 1
                txt = T[k].text   # placed like any theirs-only line below
            else:
                st["deleted"] += 1
                if T[k].text != B[g].text:
                    st["delete_beats_edit"] += 1
                continue
        else:
            txt = pick(g)
        if txt is None:
            continue
        succ = None
        for k2 in range(k + 1, len(T)):
            if gid_t[k2] in out_pos_gid:
                succ = gid_t[k2]
                break
        if succ is None:
            tail.append(txt)
        else:
            before.setdefault(succ, []).append(txt)
    merged = []
    for g, txt in out:
        for x in before.get(g, ()):
            merged.append(x)
        merged.append(txt)
    merged.extend(tail)
    st["lines_out"] = len(merged)
    return merged, st


def _hash_counts(lines):
    c = {}
    for t in lines:
        if ITEM_RE.match(t):
            h = item_hash(t)
            c[h] = c.get(h, 0) + 1
    return c


def _checked_counts(lines):
    c = {}
    for t in lines:
        m = ITEM_RE.match(t)
        if m and m.group(1) in "xX":
            h = item_hash(t)
            c[h] = c.get(h, 0) + 1
    return c


def self_check(base_l, ours_l, theirs_l, merged_l):
    """Post-conditions for items whose hash is unique in every version (the cases where line semantics and hash semantics coincide).
    Returns an error string or None."""
    cb, co, ct, cm = map(_hash_counts, (base_l, ours_l, theirs_l, merged_l))
    ko, kt, km = map(_checked_counts, (ours_l, theirs_l, merged_l))
    for h in set(co) | set(ct):
        if max(cb.get(h, 0), co.get(h, 0), ct.get(h, 0)) > 1:
            continue
        n_o, n_t, n_m = co.get(h, 0), ct.get(h, 0), cm.get(h, 0)
        if n_o and n_t and not n_m:
            return "item %s present on both sides was dropped" % h
        if n_m > max(n_o, n_t):
            return "item %s duplicated (%d > max(%d,%d))" % (h, n_m, n_o, n_t)
        if n_m and (ko.get(h, 0) or kt.get(h, 0)) and not km.get(h, 0):
            return "item %s was checked on one side but is unchecked in the result" % h
    for h in cm:  # an item can never appear that neither side has
        if h not in co and h not in ct:
            return "item %s appeared from nowhere" % h
    return None


def merge_bytes(base_b, ours_b, theirs_b):
    """-> (merged bytes, stats). Raises ValueError when the self-check fails."""
    bl, _ = split_text(base_b)
    ol, onl = split_text(ours_b)
    tl, tnl = split_text(theirs_b)
    for nm, ls in (("base", bl), ("ours", ol), ("theirs", tl)):
        if len(ls) > MAX_LINES:
            raise ValueError("%s has %d lines (> %d): declined, the alignment is quadratic" % (nm, len(ls), MAX_LINES))
        for x in ls:
            if MARKER_RE.match(x):
                raise ValueError("%s contains a committed conflict-marker line %r: declined" % (nm, x[:20]))
    merged, st = merge_lines(bl, ol, tl)
    err = self_check(bl, ol, tl, merged)
    if err:
        raise ValueError(err)
    return join_text(merged, onl or tnl), st


# ----------------------------------------------------------------------------------------------------------------------------------
# logging / helpers
# ----------------------------------------------------------------------------------------------------------------------------------
def default_log():
    return os.environ.get("OVN_PM_LOG") or os.path.join(os.path.dirname(_THIS_DIR), "state", "progress_merge.log")


def log_line(path, tag, msg):
    try:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
        with open(path, "a") as f:
            f.write("%s | %s | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), tag or "-", msg))
    except Exception:
        pass  # logging must never fail a merge


def fmt_stats(st):
    keys = ("both_changed", "checked_wins", "new_ours", "new_theirs", "deleted", "delete_beats_edit", "kept_checked_reword", "lines_out")
    return " ".join("%s=%d" % (k, st[k]) for k in keys)


def killed():
    return os.environ.get("OVN_PROGRESS_MERGE", "on").strip().lower() == "off"


def read_bytes(p):
    try:
        with open(p, "rb") as f:
            return f.read()
    except (IOError, OSError):
        return b""


def git(args, cwd=None, inp=None, check=False):
    p = subprocess.run(["git"] + args, cwd=cwd, input=inp, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    if check and p.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (" ".join(args), p.stderr.decode("utf-8", "replace").strip()))
    return p


# ----------------------------------------------------------------------------------------------------------------------------------
# modes
# ----------------------------------------------------------------------------------------------------------------------------------
def text_merge_fallback(base, ours, theirs, marker=None):
    """The plain git text merge (what git does with no driver): writes the result into <ours>, returns 0 clean / 1 conflicted-or-error."""
    args = ["merge-file", "-L", "ours", "-L", "base", "-L", "theirs"]
    if marker:
        args += ["--marker-size=%s" % marker]
    p = git(args + [ours, base, theirs])
    return 0 if p.returncode == 0 else 1


def mode_driver(argv, log, tag):
    if len(argv) < 3:
        sys.stderr.write("driver mode needs BASE OURS THEIRS\n")
        return 2
    base, ours, theirs = argv[0], argv[1], argv[2]
    marker = argv[3] if len(argv) > 3 and argv[3].isdigit() else None
    path = argv[4] if len(argv) > 4 else "?"
    if killed():
        log_line(log, tag or "driver", "%s | OVN_PROGRESS_MERGE=off -> plain text merge" % path)
        return text_merge_fallback(base, ours, theirs, marker)
    if os.environ.get("OVN_PM_DEFER", "") not in ("", "0"):
        return text_merge_fallback(base, ours, theirs, marker)  # caller resolves under its gate (see module docstring)
    def _on_alarm(signum, frame):
        raise TimeoutError("merge exceeded %ds" % DRIVER_ALARM_S)

    try:
        ob = read_bytes(ours)
        if hasattr(signal, "SIGALRM"):
            signal.signal(signal.SIGALRM, _on_alarm)
            signal.alarm(int(os.environ.get("OVN_PM_ALARM_S", DRIVER_ALARM_S)))
        try:
            merged, st = merge_bytes(read_bytes(base), ob, read_bytes(theirs))
        finally:
            if hasattr(signal, "SIGALRM"):
                signal.alarm(0)
    except BaseException as e:  # never leave git with a half result (also on the alarm): plain merge, a normal conflict
        log_line(log, tag or "driver", "%s | FALLBACK to text merge: %s" % (path, e))
        return text_merge_fallback(base, ours, theirs, marker)
    with open(ours, "wb") as f:
        f.write(merged)
    log_line(log, tag or "driver", "%s | mode=driver | ungated (no build/test gate ran; caller did not set OVN_PM_DEFER=1) | %s" % (path, fmt_stats(st)))
    return 0


def mode_merge(argv, log, tag, out):
    if len(argv) != 3:
        sys.stderr.write("--merge needs BASE OURS THEIRS\n")
        return 2
    try:
        with _Deadline(MODE_ALARM_S):
            merged, st = merge_bytes(read_bytes(argv[0]), read_bytes(argv[1]), read_bytes(argv[2]))
    except Exception as e:
        sys.stderr.write("declined: %s\n" % e)
        return 1
    if out:
        with open(out, "wb") as f:
            f.write(merged)
    else:
        sys.stdout.buffer.write(merged)
    log_line(log, tag or "merge", "mode=merge | %s" % fmt_stats(st))
    return 0


def mode_resolve_index(wt, log, tag, dry=False):
    if killed():
        return 1
    try:
        p = git(["ls-files", "-u", "-z"], cwd=wt, check=True)
    except Exception as e:
        sys.stderr.write("%s\n" % e)
        return 1
    stages = {}
    for rec in p.stdout.split(b"\0"):
        if not rec:
            continue
        meta, _, path = rec.partition(b"\t")
        parts = meta.split()
        if len(parts) != 3:
            return 1
        stages.setdefault(path.decode("utf-8", "surrogateescape"), {})[int(parts[2])] = parts[1].decode()
    if not stages:
        return 1
    for path, st in stages.items():
        if path not in PROGRESS_FILES:
            log_line(log, tag or "index", "declined: %s is conflicted too (not a progress file)" % path)
            return 1
        if 2 not in st or 3 not in st:
            log_line(log, tag or "index", "declined: %s is a delete/modify conflict" % path)
            return 1
    results = {}
    try:
        with _Deadline(MODE_ALARM_S):   # ONE budget for all files; every result is computed BEFORE anything is written/added (never a half-merged index)
            for path, st in stages.items():
                def blob(n):
                    if n not in st:
                        return b""
                    return git(["cat-file", "blob", st[n]], cwd=wt, check=True).stdout
                try:
                    results[path] = merge_bytes(blob(1), blob(2), blob(3))
                except TimeoutError:
                    raise
                except Exception as e:
                    log_line(log, tag or "index", "declined: %s: %s" % (path, e))
                    return 1
    except TimeoutError as e:
        log_line(log, tag or "index", "declined: %s" % e)
        return 1
    if dry:  # --check-index: report that it WOULD resolve, touch nothing
        for path, (merged, stats) in sorted(results.items()):
            log_line(log, tag or "index", "%s | mode=check-index (nothing written) | %s" % (path, fmt_stats(stats)))
        sys.stdout.write("resolvable: %s\n" % " ".join(sorted(results)))
        return 0
    for path, (merged, stats) in results.items():
        with open(os.path.join(wt, path), "wb") as f:
            f.write(merged)
    try:
        git(["add", "--"] + list(results), cwd=wt, check=True)
    except Exception as e:
        sys.stderr.write("%s\n" % e)
        return 1
    for path, (merged, stats) in sorted(results.items()):
        log_line(log, tag or "index", "%s | mode=resolve-index | %s" % (path, fmt_stats(stats)))
    sys.stdout.write("resolved: %s\n" % " ".join(sorted(results)))
    return 0


def mode_setup_clone(repo, script):
    p = git(["rev-parse", "--git-path", "info/attributes"], cwd=repo)
    if p.returncode != 0:
        sys.stderr.write("not a git repo: %s\n" % repo)
        return 1
    attr = p.stdout.decode().strip()
    if not os.path.isabs(attr):
        attr = os.path.join(repo, attr)
    lines = {"%s merge=%s" % (f, DRIVER_NAME) for f in PROGRESS_FILES}
    try:
        cur = open(attr).read().splitlines() if os.path.exists(attr) else []
    except (IOError, OSError):
        cur = []
    if killed():  # kill switch: unwire the clone
        keep = [l for l in cur if l.strip() not in lines and not l.startswith("# ovn-progress-merge")]
        if keep != cur:
            with open(attr, "w") as f:
                f.write("\n".join(keep) + ("\n" if keep else ""))
        git(["config", "--local", "--remove-section", "merge.%s" % DRIVER_NAME], cwd=repo)
        return 0
    want = ["# ovn-progress-merge (managed by ovn_progress_merge.py --setup-clone)"] + sorted(lines)
    if not all(l in cur for l in want):
        os.makedirs(os.path.dirname(attr), exist_ok=True)
        keep = [l for l in cur if l.strip() not in lines and not l.startswith("# ovn-progress-merge")]
        with open(attr, "w") as f:
            f.write("\n".join(keep + want) + "\n")
    cmd = "python3 '%s' --driver %%O %%A %%B %%L %%P" % script.replace("'", "'\\''")
    have = git(["config", "--local", "--get", "merge.%s.driver" % DRIVER_NAME], cwd=repo).stdout.decode().strip()
    if have != cmd:
        git(["config", "--local", "merge.%s.name" % DRIVER_NAME, "fleet progress-file merge (ovn_progress_merge.py)"], cwd=repo, check=True)
        git(["config", "--local", "merge.%s.driver" % DRIVER_NAME, cmd], cwd=repo, check=True)
    return 0


def main(argv):
    log = default_log()
    tag = ""
    out = None
    mode = None
    rest = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--log", "--tag", "--out", "--script") and i + 1 < len(argv):
            v = argv[i + 1]
            if a == "--log":
                log = v
            elif a == "--tag":
                tag = v
            elif a == "--out":
                out = v
            else:
                os.environ["_OVN_PM_SCRIPT"] = v
            i += 2
            continue
        if a in ("--driver", "--merge", "--resolve-index", "--check-index", "--setup-clone") and mode is None:
            mode = a
        else:
            rest.append(a)
        i += 1
    if mode == "--driver":
        return mode_driver(rest, log, tag)
    if mode == "--merge":
        return mode_merge(rest, log, tag, out)
    if mode == "--resolve-index" and len(rest) == 1:
        return mode_resolve_index(rest[0], log, tag)
    if mode == "--check-index" and len(rest) == 1:
        return mode_resolve_index(rest[0], log, tag, dry=True)
    if mode == "--setup-clone" and len(rest) == 1:
        return mode_setup_clone(rest[0], os.environ.get("_OVN_PM_SCRIPT") or os.path.abspath(__file__))
    sys.stderr.write(__doc__.split("USAGE")[1].split("ENV")[0] + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
