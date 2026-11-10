_NEG_ASSERT_RE = re.compile(
    r"\bassert\b[^#\n]*?\bnot\s+in\b|\bassert\s+not\b|\bassertNotIn\b|\bassertNotEqual\b|\bassertFalse\b|\bassertNotIsInstance\b|\bassert_not_called\b|\bassert_not_called_with\b|\brefute\b|"
    r"\bassert_not\w*\b|\bassert_false\b|\bassert_ne\b|\.not\.(?:toContain|toBe|toEqual|toHaveProperty|toMatch|toHaveBeenCalled\w*|toBeInTheDocument|toBeVisible|toThrow\w*|toHaveLength|toStrictEqual)\b|"
    r"\btoBeFalsy\(|\bassertNotRegex\b")
_ASSERTISH_RE = re.compile(r"\bassert\w*\b|\bexpect\s*\(|\bshould\b|\brefute\b|\bverify\b")
_STATUS_RE = re.compile(r"\b([1-5]\d\d)\b")
_WEAK_RE = re.compile(r"\bis\s+not\s+None\b|\bassertIsNotNone\b|\bassertTrue\(\s*True\s*\)|\bassert\s+True\b|\.toBeDefined\(\)|\.toBeTruthy\(\)|\.not\.toBeNull\(\)|\.not\.toBeUndefined\(\)|\bassert\s+\w+\s*$|\bassert_not_null\b|\bassert_true\(\s*true\s*\)")
_STRONG_RE = re.compile(r"\bassert\b[^#\n]*?(?:==|\bin\b)|\bassertEqual\b|\bassertIn\b|\.toBe\((?!\s*(?:true|false)\s*\))|\.toEqual\(|\.toStrictEqual\(|\.toContain\(|\.toHaveLength\(|\.toMatch\(|\bassert_eq\b|\bassert_equal\b")  # toBe(true/false) = existence check, not a comparison
_TESTDEF_RE = re.compile(r"^\s*(?:async\s+)?def\s+test_|^\s*func\s+test_|^\s*(?:it|test|describe)(?:\.\w+)?\s*\(|^\s*@Test\b|^\s*fun\s+`?test")
_PARAM_RE = re.compile(r"parametrize|\b(?:it|test|describe)\.each\b|\bwith_data\b|@(?:pytest\.)?fixture\(.*params")
_CASE_RE = re.compile(r"^\s*(?:pytest\.param\(|\(.*\)\s*,?\s*(?:#.*)?$|\[.*\]\s*,?\s*(?:#.*)?$|[\"'`][^\"'`]*[\"'`]\s*,?\s*(?:#.*)?$|\{.*\}\s*,?\s*(?:#.*)?$)")
_NO_ASSERT_WORDS_RE = re.compile(r"^\s*(?:#|//|\*|/\*)")


def _norm_line(t):
    return re.sub(r"\s+", " ", (t or "").strip()).rstrip(";,")


def _is_comment(t):
    return bool(_NO_ASSERT_WORDS_RE.match(t or ""))


def _status_shape(t):
    return _STATUS_RE.sub("N", _norm_line(t))


def _status_codes(t):
    return [int(x) for x in _STATUS_RE.findall(t or "")]


_EMPTY_ASSERT_RE = re.compile(r"==\s*(?:\[\]|\{\}|\(\)|\"\"|''|0\b|None\b)|\blen\([^)]*\)\s*==\s*0|toHaveLength\(0\)|toEqual\(\[\]\)|toBe\(0\)|\bis\s+None\b")
_SUBJ_TOKEN_RE = re.compile(r"[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)*(?:\(\))?")
_SUBJ_STOP = {"assert", "not", "in", "is", "None", "True", "False", "and", "or", "expect", "toBe", "toEqual", "toContain", "self", "len", "str", "set", "list", "dict"}


def _polarity_key(t):
    t = re.sub(r"\bnot\s+in\b", "in", t)
    t = re.sub(r"\bassert\s+not\b", "assert", t)
    t = t.replace(".not.", ".").replace("assertNotIn", "assertIn").replace("assertFalse", "assertTrue").replace("assertNotEqual", "assertEqual")
    return _norm_line(t)


def _subject_tokens(t):
    t = re.sub(r"\"[^\"]*\"|'[^']*'", " ", t)
    return set(x for x in _SUBJ_TOKEN_RE.findall(t) if x not in _SUBJ_STOP and len(x) > 1)


def check_assert_weaken(diff_files, old_text_fn=None):
    """B7. Deterministic per-hunk heuristics (see above). old_text_fn(path) -> pre-image text, only needed for the deleted-parametrize-case check."""
    out = []
    for fd in diff_files:
        if fd.is_deleted or fd.is_new or not is_test_path(fd.path):
            continue
        if not (fd.removed and fd.added) and not fd.removed:
            continue
        src_touched = any(is_source_path(o.path) and not o.is_deleted and (o.added or o.removed) for o in diff_files)
        file_added_norm = set(_norm_line(t) for _, t in fd.added)
        file_ctx_neg = [t for t in fd.context if _NEG_ASSERT_RE.search(t)]
        old_text = None
        found = {}   # kind -> (lineno, text)

        def hit(kind, ln, txt):
            found.setdefault(kind, (ln, _norm_line(txt)[:120]))
        for h in fd.hunks:
            rem = [(ln, t) for ln, t in h["rem"] if not _is_comment(t)]
            add = [(ln, t) for ln, t in h["add"] if not _is_comment(t)]
            if not rem:
                continue
            add_norm = set(_norm_line(t) for _, t in add)
            rem_testdef = any(_TESTDEF_RE.match(t) for _, t in rem)
            add_testdef = any(_TESTDEF_RE.match(t) for _, t in add)
            # a test whose `def`/`it(` line is itself edited or removed is a rewritten / retired test (its intent changed), not an in-place weakening of one that stays
            retired = rem_testdef
            # (1) a negative assertion removed (not merely moved/reworded to another negative one)
            if not retired:
                add_neg = sum(1 for _, t in add if _NEG_ASSERT_RE.search(t))
                add_pk = set(_polarity_key(t) for _, t in add)
                add_subj = set()
                for _, t in add:
                    if (_STRONG_RE.search(t) or _EMPTY_ASSERT_RE.search(t)) and not _WEAK_RE.search(t):
                        add_subj |= _subject_tokens(t)
                add_empty = any(_EMPTY_ASSERT_RE.search(t) and _ASSERTISH_RE.search(t) for _, t in add)
                for ln, t in rem:
                    if _NEG_ASSERT_RE.search(t) and _norm_line(t) not in file_added_norm and _ASSERTISH_RE.search(t):
                        if _polarity_key(t) in add_pk:
                            continue      # expectation flipped (`assert not x` -> `assert x`): the behaviour under test changed, not weakened
                        if _subject_tokens(t) & add_subj and not any(_norm_line(x) == _norm_line(y) for (_, x), (_, y) in zip(add, add[1:])):
                            continue      # replaced by a stronger comparison on the same subject
                        if add_empty:
                            continue      # replaced by an emptiness check
                        if any(_subject_tokens(c) & _subject_tokens(t) for c in file_ctx_neg):
                            continue      # a sibling negative assertion on the same subject is still there
                        rem_neg = sum(1 for _, x in rem if _NEG_ASSERT_RE.search(x))
                        if rem_neg > add_neg:
                            hit("negative-removed", ln, t)
                            break
            # (2) status expectation flipped from an error code to a success code. Only for a TEST-ONLY change: a commit that also edits app source changed the behaviour on purpose.
            for ln, t in ([] if src_touched else rem):
                if not _ASSERTISH_RE.search(t):
                    continue
                oc = [c for c in _status_codes(t) if 400 <= c <= 499]
                if not oc:
                    continue
                shape = _status_shape(t)
                for _, a in add:
                    ac = [c for c in _status_codes(a) if 200 <= c <= 299]
                    if ac and _status_shape(a) == shape:
                        hit("status-flip", ln, t + "  ->  " + a)
                        break
            # (3) strong comparison replaced by an existence check
            if not retired:
                strong_rem = sum(1 for _, t in rem if _STRONG_RE.search(t) and not _WEAK_RE.search(t))
                strong_add = sum(1 for _, t in add if _STRONG_RE.search(t) and not _WEAK_RE.search(t))
                weak_add = [(ln, t) for ln, t in add if _WEAK_RE.search(t) and _ASSERTISH_RE.search(t)]
                if strong_rem > strong_add and weak_add and not any(_WEAK_RE.search(t) for _, t in rem):
                    hit("compare-to-weak", weak_add[0][0], weak_add[0][1])
            # (4) identical consecutive positive assertions in the replacement while the hunk removed a different assertion
            ad = [t for _, t in h["add"]]
            for i in range(len(ad) - 1):
                if h["add"][i + 1][0] == h["add"][i][0] + 1 and _norm_line(ad[i]) == _norm_line(ad[i + 1]) and _ASSERTISH_RE.search(ad[i]) and not _is_comment(ad[i]):
                    if any(_ASSERTISH_RE.search(t) and _norm_line(t) != _norm_line(ad[i]) for _, t in rem):
                        hit("duplicate-assert", h["add"][i][0], ad[i])
                        break
            # (5) parametrize / each cases deleted (their values vanish; removed with the test itself is retirement)
            if old_test_ok(old_text_fn) and not retired:
                if old_text is None:
                    old_text = old_text_fn(fd.old_path) or ""
                old_lines = old_text.split("\n")
                gone = [(ln, t) for ln, t in rem if _CASE_RE.match(t) and _norm_line(t) not in add_norm and not _ASSERTISH_RE.search(t) and not _TESTDEF_RE.match(t)]
                if gone:
                    ln0 = gone[0][0]
                    window = old_lines[max(0, ln0 - 25):max(0, ln0 - 1)]
                    if any(_PARAM_RE.search(w) for w in window):
                        hit("case-deleted", ln0, gone[0][1])
        for kind, (ln, txt) in sorted(found.items()):
            out.append({"rule": "assert-weaken", "sev": "FLAG", "kind": kind, "file": fd.path, "line": ln, "text": txt,
                        "msg": "test %s weakened (%s) at %s:%s: %s" % ("assertions", kind, fd.path, ln, txt[:80])})
    return out


