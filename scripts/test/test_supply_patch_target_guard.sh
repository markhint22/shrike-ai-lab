#!/usr/bin/env bash
# ovn_work_supply.c_unused_imports must not emit an F401 item for an import that tests patch as `<module>.<Name>` (2026-10-20 gitlark workspaces.py GitHubClient loop).
# Mutant: guard condition broken -> the on-mode check must FAIL, proving the test bites.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPTS="$HERE/.."
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
SB="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$SB"' EXIT
python3 -I - "$SCRIPTS" "$SB" <<'PY'
import importlib.util, os, sys, shutil
scripts, sb = sys.argv[1], os.path.realpath(sys.argv[2])
P = F = 0
def ok(n, c):
    global P, F
    if c: P += 1; print("  ok   " + n)
    else: F += 1; print("  FAIL " + n)
repo = os.path.join(sb, "repo"); os.makedirs(repo + "/backend/app/routers"); os.makedirs(repo + "/backend/tests")
open(repo + "/backend/app/routers/workspaces.py", "w").write("from app.services.github import GitHubClient\n\ndef f():\n    return 1\n")
open(repo + "/backend/app/routers/other.py", "w").write("import json\n\ndef g():\n    return 1\n")
open(repo + "/backend/tests/conftest.py", "w").write('def fx(monkeypatch):\n    monkeypatch.setattr("app.routers.workspaces.GitHubClient", object)\n')
fake = [{"filename": repo + "/backend/app/routers/workspaces.py", "message": "`app.services.github.GitHubClient` imported but unused"},
        {"filename": repo + "/backend/app/routers/other.py", "message": "`json` imported but unused"}]
def load(src, tag):
    d = os.path.join(sb, tag); os.makedirs(d)
    for f in os.listdir(scripts):
        if f.endswith(".py"): shutil.copy(os.path.join(scripts, f), d)
    open(os.path.join(d, "ovn_work_supply.py"), "w").write(src)
    sp = importlib.util.spec_from_file_location("m_" + tag, os.path.join(d, "ovn_work_supply.py"))
    m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
    m._venv_python = lambda root: "py"; m._ruff_json = lambda py, root, args: fake
    return m
def files(m, mode):
    os.environ["OVN_SUPPLY_PATCH_TARGET_GUARD"] = mode
    return sorted(s["file"] for s in m.c_unused_imports(repo))
src = open(os.path.join(scripts, "ovn_work_supply.py")).read()
R = load(src, "real")
both = ["backend/app/routers/other.py", "backend/app/routers/workspaces.py"]
ok("on: patched-name file skipped, other file kept", files(R, "on") == ["backend/app/routers/other.py"])
ok("shadow (default): both emitted", files(R, "shadow") == both)
ok("off: both emitted", files(R, "off") == both)
anchor = '            if mode == "on":'
assert src.count(anchor) == 1
M = load(src.replace(anchor, '            if mode == "never":'), "mut")
ok("MUTANT (guard disabled) is caught by the on-mode check", files(M, "on") != ["backend/app/routers/other.py"])
print("%d passed, %d failed" % (P, F)); sys.exit(1 if F else 0)
PY
