#!/usr/bin/env python3
"""Z2 (2026-11-07): ovn_scout_ground.py fixture grounding. A DB-fixture test must be shown the model files it builds rows from.
Evidence: billwatch test_bill_chat_filter_cap.py ~12 rows / 2.5h (users.password_hash, 'username' invalid kwarg, bills.congress_number) because only bill_chat.py was loaded;
gitlark Workspace(id='<str>') UUID column + async mocks. Module under test: $OVN_SCOUT_GROUND_PY (default: ../ovn_scout_ground.py) so the .sh wrapper can run it against a mutant."""
import atexit
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PY = os.environ.get("OVN_SCOUT_GROUND_PY") or os.path.join(HERE, "..", "..", "ovn_scout_ground.py")
if not os.path.isfile(PY):
    PY = os.path.join(HERE, "..", "ovn_scout_ground.py")
sys.path.insert(0, os.path.dirname(os.path.abspath(PY)))
spec = importlib.util.spec_from_file_location("ovn_scout_ground_under_test", PY)
sg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sg)

P = F = 0


def ok(label, cond):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: " + label)


def mkrepo(files):
    d = tempfile.mkdtemp(prefix="z2sg.")
    atexit.register(shutil.rmtree, d, True)
    for p, txt in files.items():
        fp = os.path.join(d, p)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "w").write(txt)
    subprocess.run(["git", "init", "-q", d], check=True)
    subprocess.run(["git", "-C", d, "add", "-A"], check=True)
    subprocess.run(["git", "-C", d, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "i"], check=True)
    return d


USER = 'from app.db import Base\nclass User(Base):\n    __tablename__ = "users"\n    id = Column(Integer, primary_key=True)\n    password_hash = Column(String, nullable=False)\n'
BILL = 'from app.db import Base\nclass Bill(Base):\n    __tablename__ = "bills"\n    id = Column(Integer, primary_key=True)\n    congress_number = Column(Integer, nullable=False)\n'
CHAT = ('from app.db import Base\nclass BillChat(Base):\n    __tablename__ = "bill_chats"\n    id = Column(Integer, primary_key=True)\n'
        '    user_id = Column(Integer, ForeignKey("users.id"))\n    bill_id = Column(Integer, ForeignKey("bills.id"))\n')
BASE = {"app/models/user.py": USER, "app/models/bill.py": BILL, "app/models/bill_chat.py": CHAT,
        "app/utils.py": "def cap(n):\n    return min(n, 3)\n",
        "tests/conftest.py": "import pytest\n@pytest.fixture\ndef db_session():\n    pass\n", "conftest.py": "# root conftest\n",
        "tests/test_other.py": "def test_x():\n    pass\n"}
ITEM = "[T2] tests/test_bill_chat_filter_cap.py — Add test_max_filter_calls asserting the cap. VERIFY: pytest tests/test_bill_chat_filter_cap.py"
LOG = "FILES: app/models/bill_chat.py\n\n"


def adds(rows):
    return {r[1]: r[2] for r in rows if r[0] == "ADD"}


# A: FK parents + nearest/parent conftest are loaded for a DB test
d = mkrepo(BASE)
a = adds(sg.ground(d, LOG, ITEM))
ok("A1 ForeignKey parent users -> app/models/user.py added", "app/models/user.py" in a and "users" in a["app/models/user.py"])
ok("A2 ForeignKey parent bills -> app/models/bill.py added", "app/models/bill.py" in a)
ok("A3 nearest conftest tests/conftest.py added", "tests/conftest.py" in a and "nearest" in a["tests/conftest.py"])
ok("A4 parent conftest.py added", "conftest.py" in a and "parent" in a["conftest.py"])
ok("A5 the planned file is still KEEP and not re-added", "app/models/bill_chat.py" not in a)

# B: bounds - max_extra and byte budget are honoured
b = adds(sg.ground(d, LOG, ITEM, max_extra=2))
ok("B1 max_extra=2 admits at most 2 fixture files", len(b) == 2)
sz = os.path.getsize(os.path.join(d, "app/models/user.py"))
b2 = adds(sg.ground(d, LOG, ITEM, extra_total=sz + 1))
ok("B2 extra_total of one model file admits only what fits", sum(os.path.getsize(os.path.join(d, p)) for p in b2) <= sz + 1 and len(b2) >= 1)
b3 = adds(sg.ground(d, LOG, ITEM, total_budget=1))
ok("B3 a spent total budget admits nothing", not b3)

# C: a non-DB test pulls nothing in
d2 = mkrepo(dict(BASE, **{"app/models/other.py": "x = 1\n"}))
c = adds(sg.ground(d2, "FILES: app/utils.py\n\n", "[T1] tests/test_utils_cap.py — Add test for cap(). VERIFY: pytest tests/test_utils_cap.py"))
ok("C1 pure-function test: no fixture files added", not [w for w in c.values() if w.startswith("fixture:")])

# D: a model class named by the item (gitlark Workspace UUID shape) is loaded even without a FK
WS = 'class Workspace(Base):\n    __tablename__ = "workspaces"\n    id = Column(UUID(as_uuid=True), primary_key=True)\n'
d3 = mkrepo({"app/models/workspace.py": WS, "app/routers/control_plane.py": "def promote():\n    pass\n", "tests/conftest.py": "# c\n"})
dd = adds(sg.ground(d3, "FILES: app/routers/control_plane.py\n\n",
                    "[T2] tests/test_promote_action.py — Add test that inserts a Workspace via db_session then calls promote. VERIFY: pytest tests/test_promote_action.py"))
ok("D1 the named model class Workspace is loaded (UUID column visible)", "app/models/workspace.py" in dd)

# E: kill switch + no workable file = no fixture grounding
os.environ["OVN_SCOUT_FIXTURES"] = "off"
ok("E1 OVN_SCOUT_FIXTURES=off restores the old output (no ADD)", not adds(sg.ground(d, LOG, ITEM)))
os.environ.pop("OVN_SCOUT_FIXTURES")
ok("E2 an empty/fictional plan is never rescued by fixture grounding", not adds(sg.ground(d, "FILES: NONE\n\n", ITEM)))

# F: symbol extras are admitted first and never displaced by fixtures
d4 = mkrepo(dict(BASE, **{"app/svc.py": "def compute_chat_cap():\n    return 3\n"}))
f = sg.ground(d4, LOG, "[T2] tests/test_bill_chat_filter_cap.py — Add test for `compute_chat_cap` db_session. VERIFY: pytest tests/test_bill_chat_filter_cap.py", max_extra=2)
fa = [r for r in f if r[0] == "ADD"]
ok("F1 the symbol-resolved definition file comes first", fa and fa[0][1] == "app/svc.py")
ok("F2 the shared max_extra=2 is not exceeded", len(fa) <= 2)

print("Z2 scout fixture grounding: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
