import json, os, sys
TMP, QA = os.environ["TQD_TMP"], os.environ["TQD_QA"]
os.environ["OVN_DIR"] = os.path.join(TMP, "ovn"); os.makedirs(os.path.join(TMP, "ovn", "state"))
for v in ("QA_STATE_DIR", "OVN_QA_TOOL_HEALTH_NOTE", "OVN_QA_TOOL_HEALTH_NOTE_REPEAT_H", "OVN_QA_TOOL_HEALTH_MIN_PASSES"):
    os.environ.pop(v, None)
sys.path.insert(0, QA)
import qa_tool_health as th  # noqa: E402
P = F = 0
def ok(n, c, x=""):
    global P, F
    if c: P += 1
    else: F += 1; print("  FAIL " + n + " :: " + str(x)[:300])
NP = os.path.join(TMP, "ovn", "state", "notify_notes.jsonl")
def notes():
    try: return [json.loads(l) for l in open(NP).read().splitlines() if l.strip()]
    except OSError: return []
def fnd(*ks): return [{"key": k, "gate": "g", "problem": "p"} for k in ks]
T0 = 1000000
th.update_and_alert(fnd("tool:a", "cron:b"), T0)                 # pass 1: below the bar (MIN_PASSES=2)
ok("B0: below the bar -> no note", len(notes()) == 0)
th.update_and_alert(fnd("tool:a", "cron:b"), T0 + 3600)
ok("B1: first pass over the bar -> 1 note", len(notes()) == 1, notes())
for i in range(2, 8): th.update_and_alert(fnd("tool:a", "cron:b"), T0 + 3600 * i)
ok("B2: identical finding set for 6 more hourly runs -> still 1 note", len(notes()) == 1, len(notes()))
th.update_and_alert(fnd("tool:a", "cron:b", "state:c"), T0 + 3600 * 8)
th.update_and_alert(fnd("tool:a", "cron:b", "state:c"), T0 + 3600 * 9)   # state:c reaches the bar on its 2nd pass -> set changed
ok("B3: a changed (crossed) set -> a 2nd note", len(notes()) == 2, len(notes()))
ok("B3b: the new note names the new finding", "state:c" in notes()[-1]["text"], notes()[-1])
th.update_and_alert(fnd("tool:a", "cron:b", "state:c"), T0 + 3600 * 9 + 86400 + 1)
ok("B4: same set after 24 h -> daily repeat note (3rd)", len(notes()) == 3, len(notes()))
th.update_and_alert([], T0 + 3600 * 60)
th.update_and_alert(fnd("tool:a", "cron:b", "state:c"), T0 + 3600 * 61)
th.update_and_alert(fnd("tool:a", "cron:b", "state:c"), T0 + 3600 * 62)
ok("B5: cleared then recurred inside 24 h -> notes at once (4th)", len(notes()) == 4, len(notes()))
os.environ["OVN_QA_TOOL_HEALTH_NOTE"] = "0"
th.update_and_alert(fnd("tool:z"), T0 + 3600 * 70); th.update_and_alert(fnd("tool:z"), T0 + 3600 * 71)
ok("B6: OVN_QA_TOOL_HEALTH_NOTE=0 -> no note", len(notes()) == 4, len(notes()))
print("test_qa_tool_health_note_dedupe: %d passed, %d failed" % (P, F)); sys.exit(1 if F else 0)
