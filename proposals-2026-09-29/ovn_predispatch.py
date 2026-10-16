#!/usr/bin/env python3
"""ovn_predispatch.py - cheap, LLM-free pre-dispatch checks for the overnight queue.

Decide, from the top open item's TEXT and the repo working tree only, whether spending a
scout+implement cycle on it can possibly help.  Returns one of:

    ("ok", "")                       -> dispatch as usual
    ("delete", "<path>")             -> deterministic `git rm` + verify (no LLM)
    ("credit", "<reason>")           -> item is already satisfied; tick the checkbox (no LLM)
    ("skip", "<reason>")             -> unachievable/stale; park it with the reason (no LLM)

Rules (all pure functions of item text + tree, so they can be replayed on history):
  R1 delete-file      item is 'Delete/Remove <file>' (or VERIFY is `test ! -f X`) and X exists
                      -> udiff cannot express deletion here ("'/dev/null' is not in the subpath");
                      do it with git rm.  Never an LLM job.
  R2 moot-removal     item is 'Remove/Delete ... `ident` ...' and the target exists but none of
                      the backticked identifiers occur in it -> already satisfied -> credit.
  R3 stale-alembic    item creates alembic/versions/NNNN_*.py but another NNNN_* file exists (the
                      numbering in the item text is stale) -> skip+flag (or rewrite NNNN).
  R4 ad-repeat        the scout already answered ALREADY-DONE for this (repo,target) since the
                      target's last change and credit did not stick -> credit directly.
Usage (live):  ovn_predispatch.py --repo repos/iptv_apps --item "<line>" [--ad-seen state/ad_seen.txt]
"""
import argparse, os, re, subprocess, sys

PATH = re.compile(r"[A-Za-z0-9_.@-]+(?:/[A-Za-z0-9_.@\[\]-]+)*\.[A-Za-z0-9]{1,8}")
DEL = re.compile(r"^\s*(delete|remove)\b", re.I)
DELFILE = re.compile(r"^\s*(delete|remove)\b[^.`]{0,40}\b(file|module|class file|test file)\b", re.I)


def head_desc(item):
    t = re.sub(r"^- \[[ xX]\]\s*", "", item)
    t = re.sub(r"^(\[[^\]]*\]\s*|\([^)]*\)\s*)+", "", t)
    h, _, d = t.partition(" — ")
    return h, d


def primary(item):
    h, _ = head_desc(item)
    m = PATH.search(h)
    return m.group(0) if m else None


def item_key(item):
    """identity of an item independent of checkbox/tags: normalized description head."""
    _, d = head_desc(item)
    return (primary(item) or "") + "|" + re.sub(r"[^a-z0-9]+", " ", d.lower()).strip()[:100]


def decide(item, exists, read, ad_seen=()):
    """exists(path)->bool ; read(path)->str|None ; ad_seen: set of item_key()s the scout already called ALREADY-DONE."""
    if not item:
        return ("ok", "")
    prim = primary(item)
    _, desc = head_desc(item)
    verify = (re.search(r"VERIFY:\s*(.*?)(?:\(cat:|$)", item) or [None, ""])[1]
    if prim and exists(prim):
        # R1: whole-file deletion
        if DELFILE.match(desc) or re.search(r"test\s+!\s+-f\s+" + re.escape(prim), verify) \
           or re.search(r"test\s+-f\s+" + re.escape(prim) + r".*FAIL", verify):
            return ("delete", prim)
        # R2: removal item whose identifiers are already gone from the target
        if DEL.match(desc):
            ids = [i for i in re.findall(r"`([A-Za-z_][A-Za-z0-9_]*)(?:\(\))?`", desc)]
            body = read(prim) or ""
            if ids and not any(i in body for i in ids):
                return ("credit", "removal target identifiers %s absent from %s" % (ids[:3], prim))
    # R3: stale alembic numbering
    if prim:
        m = re.search(r"alembic/versions/(\d{4})_", prim)
        if m and not exists(prim):
            d = os.path.dirname(prim)
            # exists() is per-path; callers may pass an object with .listdir for the dir scan
            lister = getattr(exists, "listdir", None)
            if lister and any(f.startswith(m.group(1) + "_") for f in lister(d)):
                return ("skip", "alembic revision %s already taken - item text is stale" % m.group(1))
    # R4: scout already said ALREADY-DONE for this target
    if item_key(item) in ad_seen:
        return ("credit", "scout previously ALREADY-DONE for this exact item (%s)" % prim)
    return ("ok", "")


class FsTree:
    def __init__(self, root):
        self.root = root
    def __call__(self, p):
        return os.path.isfile(os.path.join(self.root, p))
    def listdir(self, d):
        try:
            return os.listdir(os.path.join(self.root, d))
        except OSError:
            return []
    def read(self, p):
        try:
            return open(os.path.join(self.root, p), errors="replace").read()
        except OSError:
            return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--item", required=True)
    ap.add_argument("--ad-seen")
    a = ap.parse_args()
    seen = set(open(a.ad_seen).read().split()) if a.ad_seen and os.path.exists(a.ad_seen) else set()
    t = FsTree(a.repo)
    act, why = decide(a.item, t, t.read, seen)
    print("%s\t%s" % (act, why))


if __name__ == "__main__":
    main()
