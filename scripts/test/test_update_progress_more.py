#!/usr/bin/env python3
"""Extra branch coverage for update_progress.py: executes the REAL script in place (subprocess; coverage.py picks the child up via
sitecustomize) against temp docs. Covers usage/unreadable errors, every classify tier, recorded-completed placements, NEW and
DECISION append/dedupe/create paths."""
import datetime, os, subprocess, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("OVN_ROOT") or os.path.dirname(os.path.dirname(HERE))
SCRIPT = os.path.join(ROOT, "update_progress.py")
TODAY = datetime.date.today().isoformat()
P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond: P += 1
    else:
        F += 1; print("  FAIL: %s  %s" % (name, extra))

TMP = tempfile.mkdtemp()
def run(doc, commits, raw=None):
    p = os.path.join(TMP, "P.md")
    if raw is not False:
        open(p, "w", encoding="utf-8").write(doc)
    r = subprocess.run([sys.executable, SCRIPT, p], input=commits, capture_output=True, text=True)
    return r, (open(p, encoding="utf-8").read() if os.path.exists(p) else None)

# usage / unreadable
r = subprocess.run([sys.executable, SCRIPT], input="", capture_output=True, text=True)
ok("no args -> rc 2 + usage", r.returncode == 2 and "usage:" in r.stderr, r.stderr)
r = subprocess.run([sys.executable, SCRIPT, os.path.join(TMP, "nope.md")], input="DONE: x\n", capture_output=True, text=True)
ok("unreadable doc -> rc 2", r.returncode == 2 and "cannot read" in r.stderr, r.stderr)
r, _ = run("# P\n", "just a normal commit message\n")
ok("no trailers -> unchanged", r.stdout.strip() == "unchanged" and r.returncode == 0)

# trailer parsing: '- DONE:' tolerated, case-insensitive
DOC = "# P\n\n## Next Steps\n- [ ] Wire the retry budget into the client\n1. Add the audit log export endpoint\n- Remove legacy cron shim\n\n## Completed\n- [x] scaffold\n"
r, out = run(DOC, "- done: Wire the retry budget into the client\nsome text\n")
ok("'- done:' lower-case trailer marks checkbox item", "- [x] Wire the retry budget into the client" in out and "marked done" in r.stdout, out)
r, out = run(DOC, "DONE: Add the audit log export endpoint\n")
ok("numbered item -> strikethrough + date", "1. ~~Add the audit log export endpoint~~ ✅ Done " + TODAY in out, out)
r, out = run(DOC, "DONE: Remove legacy cron shim\n")
ok("bare bullet -> strikethrough", "- ~~Remove legacy cron shim~~ ✅ Done " + TODAY in out, out)
r, out = run(DOC, "DONE: !!!\n")
ok("DONE with empty normalized key is skipped -> unchanged", r.stdout.strip() == "unchanged", r.stdout)

# exact-many
D2 = "# P\n\n## Next Steps\n- [ ] Delete app/old/a.py dead module\n- [ ] Delete app/old/a.py dead module copy\n"
r, out = run(D2, "DONE: Delete app/old/a.py dead module\n")
ok("ambiguous exact match skipped (doc untouched, prints unchanged)", r.stdout.strip() == "unchanged" and out == D2, r.stdout)

# fuzzy token-overlap tier (no substring relation, >=0.75 jaccard, clear margin)
D3 = "# P\n\n## Next Steps\n- [ ] alpha beta gamma delta epsilon zeta iota kappa\n- [ ] totally different words here now\n"
r, out = run(D3, "DONE: alpha beta gamma delta epsilon zeta iota lambda\n")
ok("fuzzy token-overlap match marks the winner", "- [x] alpha beta gamma delta epsilon zeta iota kappa" in out and "marked done" in r.stdout, r.stdout + out)
# fuzzy tier but two close items -> not fuzzy (margin) -> falls to weak/SKIPPED
D3b = "# P\n\n## Next Steps\n- [ ] alpha beta gamma delta epsilon zeta iota kappa\n- [ ] alpha beta gamma delta epsilon zeta iota sigma\n"
r, out = run(D3b, "DONE: alpha beta gamma delta epsilon zeta iota lambda\n")
ok("tied fuzzy candidates -> not guessed, doc untouched", r.stdout.strip() == "unchanged" and out == D3b, r.stdout)

# containment tier: short DONE words all inside one verbose item
D4 = ("# P\n\n## Next Steps\n- [ ] Refactor the billing reconciliation pipeline so invoices settle overnight and retries back off exponentially with jitter\n"
      "- [ ] Something else entirely unrelated to that\n")
r, out = run(D4, "DONE: billing reconciliation invoices jitter retries\n")
ok("containment tier marks the verbose item done", "- [x] Refactor the billing reconciliation" in out, r.stdout + out)
# containment with two contenders inside margin -> not chosen
D4b = "# P\n\n## Next Steps\n- [ ] billing reconciliation invoices jitter retries extra words one two three four five six\n- [ ] billing reconciliation invoices jitter retries more words seven eight nine ten eleven twelve\n"
r, out = run(D4b, "DONE: billing reconciliation invoices jitter retries\n")
ok("two equal containment contenders -> exact-many skip (substring)", "SKIPPED" in r.stdout or out == D4b, r.stdout)

# already done item -> no-op (exact, many, fuzzy) ; doc unchanged
D5 = "# P\n\n## Next Steps\n- [x] Ship the thing already\n- [ ] Other open work\n"
r, out = run(D5, "DONE: Ship the thing already\n")
ok("re-declared already-done item is a no-op", r.stdout.strip() == "unchanged" and out == D5, r.stdout)
D5b = "# P\n\n## Next Steps\n- [x] Ship the thing already\n- [x] Ship the thing already again\n- [ ] Other open work\n"
r, out = run(D5b, "DONE: Ship the thing already\n")
ok("already-done with several matches is a no-op", r.stdout.strip() == "unchanged", r.stdout)

# weak match >= NEWWORK -> SKIPPED unmatched (ambiguous)
D6 = "# P\n\n## Next Steps\n- [ ] alpha beta gamma delta\n"
r, out = run(D6, "DONE: alpha beta gamma zzz\n")
ok("middling score skipped (doc untouched)", r.stdout.strip() == "unchanged" and out == D6, r.stdout)

# genuinely new: inserted before the next '## ' of Completed / at Completed end
D7 = "# P\n\n## Next Steps\n- [ ] alpha beta gamma delta\n\n## Completed\n- [x] scaffold\n\n## Notes\nn\n"
r, out = run(D7, "DONE: zzz unrelated brand new thing\n")
ok("recorded under Completed", "recorded completed (no prior item)" in r.stdout and out.index("brand new thing") < out.index("## Notes") and out.index("brand new thing") > out.index("## Completed"), out)
D7b = "# P\n\n## Next Steps\n- [ ] alpha beta gamma delta\n\n## Notes\nn\n"
r, out = run(D7b, "DONE: zzz unrelated brand new thing\n")
ok("no Completed section -> appended at end of Next Steps", out.index("brand new thing") < out.index("## Notes"), out)
D7c = "# P\n\nno sections here\n"
r, out = run(D7c, "DONE: zzz unrelated brand new thing\n")
ok("no Next Steps and no Completed -> dropped, unchanged", r.stdout.strip() == "unchanged" and out == D7c, r.stdout)
# two new-work DONEs in one run: second insert must see refreshed bounds
r, out = run(D7, "DONE: zzz unrelated brand new thing\nDONE: qqq second wholly novel thing\n")
ok("two recorded completions both land", "brand new thing" in out and "second wholly novel thing" in out, out)

# NEW
D8 = "# P\n\n## Next Steps\n- [ ] existing item one\n\n## Completed\n- [x] scaffold\n"
r, out = run(D8, "NEW: fresh item two\nNEW: existing item one\nNEW: fresh item two\n")
ok("NEW appended once, existing/dup skipped", out.count("fresh item two") == 1 and out.count("existing item one") == 1 and "added item: fresh item two" in r.stdout, out)
r, out = run(D8, "NEW: existing item one\n")
ok("NEW that only duplicates -> unchanged", r.stdout.strip() == "unchanged", r.stdout)
r, out = run("# P\n\nnothing\n", "NEW: item with no Next Steps section\n")
ok("NEW with no Next Steps section is ignored", r.stdout.strip() == "unchanged", r.stdout)
r, out = run(D8, "NEW: a\nNEW: b\n")
ok("two NEW items keep order", out.index("- [ ] a") < out.index("- [ ] b"), out)

# DECISION
r, out = run(D8, "DECISION: use sqlite for the queue\n")
ok("decision section created with dated bullet", "## Decisions Made" in out and ("- %s: use sqlite for the queue" % TODAY) in out, out)
r, out2 = run(out, "DECISION: use sqlite for the queue\nDECISION: second call\n")
ok("decision dedup + append", out2.count("use sqlite for the queue") == 1 and "second call" in out2, out2)
r, out = run("# P\n\n## Next Steps\n- [ ] x item\n\n", "DECISION: d1\n")
ok("decision appended when doc ends with blank line", "## Decisions Made" in out and "d1" in out, repr(out))
r, out = run("", "DECISION: d-empty-doc\n")
ok("decision on an empty doc", "## Decisions Made" in out and "d-empty-doc" in out, repr(out))
r, out = run(D8, "DECISION: !!!\n")
ok("decision normalizing to empty creates the heading only -> 'updated'", r.stdout.strip() == "updated" and "## Decisions Made" in out, r.stdout + out)
# all kinds in one go, semicolon-joined summary
r, out = run(D8, "DONE: existing item one\nNEW: n1\nDECISION: dd\n")
ok("combined summary joined with '; '", r.stdout.count(";") == 2, r.stdout)

# item whose normalized text is empty is ignored by classify (line: skip) in both passes
r, out = run("# P\n\n## Next Steps\n- [ ] !!!\n- [ ] real target item text\n", "DONE: real target item text\n")
ok("empty-normalized sibling item ignored", "- [x] real target item text" in out and "- [ ] !!!" in out, out)
r, out = run("# P\n\n## Next Steps\n- [ ] !!!\n- [ ] alpha beta gamma delta\n", "DONE: alpha beta gamma zzz\n")
ok("empty-normalized sibling ignored in containment pass too", r.stdout.strip() == "unchanged", r.stdout)
# decisions on a doc with no trailing newline -> blank separator line inserted before the new heading
r, out = run("# P\n\n## Next Steps\n- [ ] x item", "DECISION: no trailing newline doc\n")
ok("decision heading separated by blank line when doc lacks final newline", "- [ ] x item\n\n## Decisions Made" in out, repr(out))

shutil.rmtree(TMP, ignore_errors=True)
print("update_progress more: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
