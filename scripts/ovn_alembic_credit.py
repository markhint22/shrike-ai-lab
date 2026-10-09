#!/usr/bin/env python3
"""ovn_alembic_credit.py <progress_file> <generated_migration> <repo_root>

2026-10-02. After ovn_alembic_autogen.sh writes a migration, check off the OPEN backlog item(s) whose
whole job was "create the migration for <columns/tables>" - the T2 half of a T1 model + T2 migration
split. Without this the T2 item stays open, the model re-attempts it under the filename the item names,
and the second migration forks the chain (the exact MIGRATION-SAFETY revert seen on iptv_apps).

Deliberately conservative - an item is credited only when ALL hold:
  * line is an open `- [ ] ` item, not tagged CLAUDE / HUMAN / AUTO-SKIP / BLOCKED;
  * its leading target path is a .py under alembic/versions/ that does NOT exist in the tree;
  * it mentions "migration" or "alembic";
  * the item asks for PLAIN column/table DDL only: text that mentions backfill / data / update / populate /
    seed / constraint / unique / index (anything beyond DDL) is NEVER credited - the generator writes schema
    only, so ticking it would silently drop the data/constraint work (2026-10-02, H6 M2). The skip is logged
    loudly as `NOT credited line N: ... needs a human`;
  * every upgrade() op of the generated file is add_column / create_table / create_index, and
    EVERY column and table name those ops add appears (as a whole word) in the item text.
Prints CREDITED=<n> (and one `credited line N` per item). Always exits 0; edits only the progress file.
Stdlib only (runs under the system python3, not the repo venv).
"""
import os, re, sys

prog, gen, root = sys.argv[1], sys.argv[2], sys.argv[3]
# whole-word-ish: stems for backfill/populate/seed/update/constraint/unique/index, and the bare word "data"
# (so "database"/"metadata" do not trip it). Lower-case match.
BEYOND_DDL = re.compile(r"(?<![a-z0-9_])(backfill\w*|back-fill\w*|data(?![a-z0-9_])|updat\w*|populat\w*|seed\w*|constrain\w*|unique\w*|index\w*|indices|indexes)", re.I)
SKIP = re.compile(r"\[CLAUDE\]|HUMAN|AUTO-SKIP|(?-i:BLOCKED)|HARD FILE BAN", re.I)


def idents(path):
    try:
        src = open(path, encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(r"def upgrade\(\)[^\n]*:\n(.*?)(?:\ndef downgrade|\Z)", src, re.S)
    body = m.group(1) if m else ""
    ops = re.findall(r"\bop\.(\w+)\(", body)
    if not ops or any(o not in ("add_column", "create_table", "create_index") for o in ops):
        return None
    names = set(re.findall(r"op\.add_column\(\s*['\"]\w+['\"]\s*,\s*sa\.Column\(\s*['\"](\w+)['\"]", body))
    names |= set(re.findall(r"op\.create_table\(\s*['\"](\w+)['\"]", body))
    # a migration whose add_column/create_table we could not parse cannot be matched safely
    if len(names) < sum(1 for o in ops if o in ("add_column", "create_table")):
        return None
    return names or None


def main():
    # `gen` is relative to the alembic project's parent (the hook passes proj/alembic/versions/x.py)
    gpath = gen if os.path.isabs(gen) else os.path.join(root, gen)
    names = idents(gpath)
    if not names or not os.path.isfile(prog):
        print("CREDITED=0"); return
    lines = open(prog, encoding="utf-8").read().split("\n")
    n = 0
    for i, ln in enumerate(lines):
        if not ln.startswith("- [ ] ") or SKIP.search(ln):
            continue
        m = re.match(r"- \[ \] (?:\[[^\]]*\] )*([A-Za-z0-9_./-]+\.py)\b", ln)
        if not m or "alembic/versions/" not in m.group(1):
            continue
        if os.path.exists(os.path.join(root, m.group(1))):
            continue          # the file the item names exists: a normal item, not ours to credit
        if not re.search(r"migration|alembic", ln, re.I):
            continue
        text = ln[m.end():]
        _b = BEYOND_DDL.search(text + " " + re.sub(r"[_./-]", " ", m.group(1)))   # filename slug counts too (0009_epg_active_unique.py)
        if _b:
            print("NOT credited line %d: item text mentions %r (work beyond plain column DDL) - needs a human" % (i + 1, _b.group(1)))
            continue
        if all(re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(x), text) for x in names):
            lines[i] = ln.replace("- [ ] ", "- [x] (satisfied by auto-generated migration %s) " % os.path.basename(gpath), 1)
            n += 1
            print("credited line %d" % (i + 1))
    if n:
        open(prog, "w", encoding="utf-8").write("\n".join(lines))
    print("CREDITED=%d" % n)


try:
    main()
except Exception as e:  # never break the cycle
    print("CREDITED=0")
    sys.stderr.write("ovn_alembic_credit: %s: %s\n" % (type(e).__name__, e))
