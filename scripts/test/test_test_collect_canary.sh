#!/usr/bin/env bash
# Tests for scripts/ovn_test_collect_canary.sh (ghost-test canary). Fake pytest / godot shims, temp git repos, no network. Every alert case has a benign control.
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
CAN="$ROOT/scripts/ovn_test_collect_canary.sh"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export NTFY_SERVER="http://127.0.0.1:9/x" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$T/repos" "$T/state" "$T/logs" "$T/bin"
mkrepo(){ # name files...   (file contents: test_ => python test / .gd => GUT)
  local n="$1"; shift; local d="$T/repos/$n"; rm -rf "$d"; mkdir -p "$d"; git -C "$d" init -q
  for f in "$@"; do mkdir -p "$d/$(dirname "$f")"; case "$f" in *.gd) printf 'extends GutTest\n\nfunc test_a():\n\tassert_true(true)\n' > "$d/$f";; *) printf 'def test_a():\n    assert 1\n' > "$d/$f";; esac; done
  touch "$d/project.godot"; mkdir -p "$d/addons/gut"; touch "$d/addons/gut/gut_cmdln.gd"
  git -C "$d" add -A >/dev/null 2>&1; git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init
}
cat > "$T/bin/fakepytest" <<'EOS'
#!/usr/bin/env bash
[ -f "${FAKE_COLLECTED:-/nonexistent}" ] && cat "$FAKE_COLLECTED"
exit "${FAKE_RC:-0}"
EOS
cat > "$T/bin/fakegodot" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in -gjunit_xml_file=*) x="${a#-gjunit_xml_file=}";; esac; done
[ -n "${x:-}" ] && [ -n "${GODOT_SUITES:-}" ] && { echo '<testsuites failures="0" tests="1">' > "$x"; for s in $GODOT_SUITES; do echo "<testsuite name=\"$s\" tests=\"1\" failures=\"0\"></testsuite>" >> "$x"; done; echo '</testsuites>' >> "$x"; }
exit 0
EOS
chmod +x "$T/bin/fakepytest" "$T/bin/fakegodot"
run(){ env OVN_DIR="$T" OVN_REPOS_DIR="$T/repos" OVN_STATE_DIR="$T/state" OVN_CANARY_LOG="$T/logs/c.log" OVN_CANARY_REF=HEAD OVN_CANARY_PYTEST="$T/bin/fakepytest" OVN_CANARY_GODOT="$T/bin/fakegodot" OVN_CANARY_GODOT_NOIMPORT=1 "$@" bash "$CAN" >/dev/null 2>&1; echo $?; }
alerts(){ grep -c "test-collect-canary:$1" "$T/state/alerts.log" 2>/dev/null || true; }
reset(){ : > "$T/state/alerts.log"; rm -f "$T/state/test_collect_canary_seen.txt"; }

# ---- python ----
mkrepo ipy iptv-backend/tests/test_a.py iptv-backend/tests/test_b.py iptv-backend/app/s/test_c.py iptv-backend/app/s/test_d.py iptv-backend/app/j/test_e.py iptv-backend/app/j/test_f.py iptv-backend/conftest.py
printf 'tests/test_a.py::test_a\ntests/test_b.py::test_a\n\n2 tests collected\n' > "$T/c1"
reset; rc="$(run FAKE_COLLECTED="$T/c1" OVN_CANARY_REPOS="ipy:py:iptv-backend")"
ok "python: exits 0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "python NEGATIVE: 4 test files never collected (>3) => exactly one alerts.log warn naming them" "$([ "$(alerts ipy)" = 1 ] && grep -q 'app/s/test_c.py' "$T/state/alerts.log" && echo 1 || echo 0)"
run FAKE_COLLECTED="$T/c1" OVN_CANARY_REPOS="ipy:py:iptv-backend" >/dev/null
ok "python: same missing set again is deduped (still one line)" "$([ "$(alerts ipy)" = 1 ] && echo 1 || echo 0)"
printf 'tests/test_a.py::t\ntests/test_b.py::t\napp/s/test_c.py::t\napp/s/test_d.py::t\napp/j/test_e.py::t\n' > "$T/c2"
reset; run FAKE_COLLECTED="$T/c2" OVN_CANARY_REPOS="ipy:py:iptv-backend" >/dev/null
ok "python BENIGN: 1 uncollected file (<=3) => no alert" "$([ "$(alerts ipy)" = 0 ] && echo 1 || echo 0)"
printf 'tests/test_a.py::t\ntests/test_b.py::t\napp/s/test_c.py::t\napp/s/test_d.py::t\napp/j/test_e.py::t\napp/j/test_f.py::t\n' > "$T/c3"
reset; run FAKE_COLLECTED="$T/c3" OVN_CANARY_REPOS="ipy:py:iptv-backend" >/dev/null
ok "python BENIGN: everything collected => no alert" "$([ "$(alerts ipy)" = 0 ] && echo 1 || echo 0)"
printf 'ERROR tests/test_a.py\nERROR tests/test_b.py\nERROR app/s/test_c.py\nERROR app/s/test_d.py\nERROR app/j/test_e.py\nERROR app/j/test_f.py\n' > "$T/c4"
reset; run FAKE_COLLECTED="$T/c4" FAKE_RC=2 OVN_CANARY_REPOS="ipy:py:iptv-backend" >/dev/null
ok "python BENIGN: files that fail at collection count as collected (red in the gate, not ghosts)" "$([ "$(alerts ipy)" = 0 ] && echo 1 || echo 0)"
reset; run FAKE_COLLECTED="$T/c1" FAKE_RC=3 OVN_CANARY_REPOS="ipy:py:iptv-backend" >/dev/null
ok "python INFRA: pytest internal error (rc=3) => no alert, log says infra" "$([ "$(alerts ipy)" = 0 ] && grep -q 'infra (pytest rc=3)' "$T/logs/c.log" && echo 1 || echo 0)"
reset; run OVN_CANARY_PYTEST="$T/bin/nonexistent" OVN_CANARY_REPOS="ipy:py:iptv-backend" >/dev/null
ok "python INFRA: no pytest binary => no alert" "$([ "$(alerts ipy)" = 0 ] && echo 1 || echo 0)"
reset; run OVN_TEST_COLLECT_CANARY=off FAKE_COLLECTED="$T/c1" OVN_CANARY_REPOS="ipy:py:iptv-backend" >/dev/null
ok "kill switch OVN_TEST_COLLECT_CANARY=off => no alert" "$([ "$(alerts ipy)" = 0 ] && echo 1 || echo 0)"
reset; run FAKE_COLLECTED="$T/c1" OVN_CANARY_MAX=10 OVN_CANARY_REPOS="ipy:py:iptv-backend" >/dev/null
ok "OVN_CANARY_MAX raises the limit (4 missing <= 10) => no alert" "$([ "$(alerts ipy)" = 0 ] && echo 1 || echo 0)"
reset; run FAKE_COLLECTED="$T/c1" OVN_CANARY_REPOS="nosuchrepo:py:." >/dev/null
ok "missing clone => skipped, exit 0, no alert" "$([ "$(alerts nosuchrepo)" = 0 ] && echo 1 || echo 0)"
ok "no stray worktrees left behind" "$([ -z "$(git -C "$T/repos/ipy" worktree list | grep collectcanary)" ] && echo 1 || echo 0)"

# ---- GUT ----
mkrepo xl tests/test_a.gd tests/test_b.gd tests/battle/test_c.gd tests/release/test_d.gd tests/steam/test_e.gd test/battle/aoe_falloff_test.gd
reset; run GODOT_SUITES="tests/test_a.gd tests/test_b.gd" OVN_CANARY_REPOS="xl:gd:." >/dev/null
ok "GUT NEGATIVE: 4 test scripts on disk never run (subdirs/test dir) => one alert" "$([ "$(alerts xl)" = 1 ] && grep -q 'tests/battle/test_c.gd' "$T/state/alerts.log" && echo 1 || echo 0)"
reset; run GODOT_SUITES="tests/test_a.gd tests/test_b.gd tests/battle/test_c.gd tests/release/test_d.gd tests/steam/test_e.gd test/battle/aoe_falloff_test.gd" OVN_CANARY_REPOS="xl:gd:." >/dev/null
ok "GUT BENIGN: every test script collected => no alert" "$([ "$(alerts xl)" = 0 ] && echo 1 || echo 0)"
reset; run OVN_CANARY_REPOS="xl:gd:." >/dev/null
ok "GUT INFRA: no junit xml produced => no alert" "$([ "$(alerts xl)" = 0 ] && grep -q 'infra (GUT produced no junit' "$T/logs/c.log" && echo 1 || echo 0)"
mkrepo xl2 tests/test_a.gd tests/helpers/builder.gd
printf 'extends RefCounted\nfunc build():\n\tpass\n' > "$T/repos/xl2/tests/helpers/builder.gd"; git -C "$T/repos/xl2" add -A >/dev/null; git -C "$T/repos/xl2" -c user.name=t -c user.email=t@t commit -q -m h
reset; run GODOT_SUITES="tests/test_a.gd" OVN_CANARY_REPOS="xl2:gd:." >/dev/null
ok "GUT BENIGN: a non-test helper under tests/ (no func test_) is not counted as a ghost" "$([ "$(alerts xl2)" = 0 ] && echo 1 || echo 0)"
echo; echo "collect canary tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
