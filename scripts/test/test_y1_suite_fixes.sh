#!/usr/bin/env bash
# test_y1_suite_fixes.sh - package Y1-suite-fixes (2026-11-04): regression tests (each with a mutation proof) for the suite-red root causes.
#   A. ops/box_bootstrap.sh qa_tools step passes --apply (K2 made install_qa_tools.sh dry-run by default), never auto-approves semgrep/gitleaks, prints the held commands
#   B. test_run_all_meta.sh must not leak fake failing suites into a real OVN_SUITE_CAPTURE_DIR; ops/suite_run_log.py alerts ignore known fixture suite names
#   C. test_roadmap_floor_alert.sh mutation anchors all exist exactly once in the product file (K5 rename floor_h -> eff_h broke them)
#   D. test_pipeline_lint.sh's stray-.bak walk prunes ./roadmap ./backlog ./state ./logs ./repos (box runtime data)
#   E. lib_stub_server.sh waits for the port (slow start) and re-picks on a bind collision, where the old fixed `sleep 1` raced
# Hermetic: no network, no ntfy (guard sourced), scratch under this test's own safe temp dir.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/ntfy_guard.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
PY="$(command -v python3.12 || command -v python3)"
P=0; F=0
ok(){ if [ "$1" = 1 ]; then P=$((P+1)); echo "  ok   $2"; else F=$((F+1)); echo "  FAIL $2"; fi; }
SB="$(safe_mktemp_dir y1suite)" || exit 1
trap 'safe_rm_rf "$SB"' EXIT

echo "== A. box_bootstrap qa_tools step"
run_bs(){ # $1 = bootstrap script ; extra env passes through ; -> $SB/a/out, $SB/a/args
  local d="$SB/a"; rm -rf "$d"; mkdir -p "$d/ops" "$d/home"
  cp "$1" "$d/ops/box_bootstrap.sh"; cp "$ROOT/ops/box_pins.env" "$d/ops/box_pins.env"
  cat > "$d/ops/install_qa_tools.sh" <<'STUB'
#!/usr/bin/env bash
echo "args=[$*] approved=[${QA_TOOLS_APPROVED:-}]" >> "$(dirname "$0")/../stub.calls"
if [ "$1" = --apply ]; then echo "install_qa_tools: MARK-APPROVAL semgrep, run by hand:"; echo "    python3 -m venv X && pip install semgrep==1"; fi
exit 0
STUB
  BS_HOME="$d/home" BS_OVN="$d" bash "$d/ops/box_bootstrap.sh" --only qa_tools > "$d/out" 2>&1
}
env -u QA_TOOLS_APPROVED bash -c "$(declare -f run_bs); SB='$SB'; ROOT='$ROOT'; run_bs '$ROOT/ops/box_bootstrap.sh'"
ok "$(grep -q 'args=\[--apply\] approved=\[\]' "$SB/stub.calls" 2>/dev/null; [ -f "$SB/a/stub.calls" ] && grep -q 'args=\[--apply\] approved=\[\]' "$SB/a/stub.calls" && echo 1 || echo 0)" "A1 bootstrap calls install_qa_tools.sh --apply and leaves QA_TOOLS_APPROVED empty (no auto-approval)"
ok "$(grep -q 'PENDING.*approval-gated' "$SB/a/out" && grep -q 'pip install semgrep==1' "$SB/a/out" && echo 1 || echo 0)" "A2 held tools are a PENDING human item that prints the exact commands"
QA_TOOLS_APPROVED="semgrep" bash -c "$(declare -f run_bs); SB='$SB'; ROOT='$ROOT'; run_bs '$ROOT/ops/box_bootstrap.sh'"
ok "$(grep -q 'approved=\[semgrep\]' "$SB/a/stub.calls" && echo 1 || echo 0)" "A3 an operator-exported QA_TOOLS_APPROVED is honoured (inherited), not overwritten"
sed 's#install_qa_tools.sh" --apply )#install_qa_tools.sh" )#' "$ROOT/ops/box_bootstrap.sh" > "$SB/bs_mut.sh"
env -u QA_TOOLS_APPROVED bash -c "$(declare -f run_bs); SB='$SB'; ROOT='$ROOT'; run_bs '$SB/bs_mut.sh'"
ok "$(grep -q 'args=\[--apply\]' "$SB/a/stub.calls" && echo 0 || echo 1)" "A4 MUTANT (--apply dropped): A1's check fails"

echo "== B. suite red alert pollution"
B="$SB/b"; mkdir -p "$B/cap" "$B/st"
run_meta(){ ( cd "$1" && OVN_SUITE_CAPTURE_DIR="$B/cap" bash "$2/test_run_all_meta.sh" >/dev/null 2>&1 ); }
rm -f "$B/cap/failed.tsv"; run_meta "$B" "$HERE"
ok "$([ ! -s "$B/cap/failed.tsv" ] && echo 1 || echo 0)" "B1 test_run_all_meta.sh run with a real OVN_SUITE_CAPTURE_DIR writes nothing to failed.tsv"
MT="$SB/meta_mut"; mkdir -p "$MT"; cp "$HERE"/*.sh "$MT/" 2>/dev/null; cp "$HERE"/*.py "$MT/" 2>/dev/null
sed 's/env -u OVN_SUITE_CAPTURE_DIR //' "$HERE/test_run_all_meta.sh" > "$MT/test_run_all_meta.sh"
rm -f "$B/cap/failed.tsv"; run_meta "$B" "$MT"
ok "$([ -s "$B/cap/failed.tsv" ] && echo 1 || echo 0)" "B2 MUTANT (env -u removed): the fixtures DO pollute failed.tsv (B1 would fail)"
printf 'test_fake_a.sh\t  FAIL x\ntest_fail.sh\t  FAIL y\ntest_does_not_exist.sh\t\n' > "$B/f1.tsv"
r="$("$PY" -I "$ROOT/ops/suite_run_log.py" alerts "$B/f1.tsv" "$B/st" "2026-11-04 00:00:00")"
ok "$([ "$r" = none ] && [ ! -s "$B/st/alerts.log" ] && echo 1 || echo 0)" "B3 alerts: a tsv holding only fixture suites is 'none' (no alerts.log line)"
printf 'test_fake_a.sh\t  FAIL x\ntest_real_one.sh\t  FAIL real\n' > "$B/f2.tsv"
"$PY" -I "$ROOT/ops/suite_run_log.py" alerts "$B/f2.tsv" "$B/st" "2026-11-04 00:00:00" >/dev/null
ok "$(grep -q 'suite FAILED test_real_one.sh' "$B/st/alerts.log" && ! grep -q 'test_fake_a' "$B/st/alerts.log" && echo 1 || echo 0)" "B4 alerts: a real red next to a fixture is reported alone"
sed 's/            if os.path.basename(name) in FIXTURE_SUITES:/            if False:/' "$ROOT/ops/suite_run_log.py" > "$B/slog_mut.py"
rm -rf "$B/st2"; mkdir -p "$B/st2"; "$PY" -I "$B/slog_mut.py" alerts "$B/f2.tsv" "$B/st2" "2026-11-04 00:00:00" >/dev/null
ok "$(grep -q 'test_fake_a' "$B/st2/alerts.log" && echo 1 || echo 0)" "B5 MUTANT (filter off): the fixture reaches the alert (B4 would fail)"

echo "== C. roadmap floor test anchors"
anchors_ok(){ "$PY" -I - "$1" "$2" <<'PYEOF'
import re, sys
t = open(sys.argv[1]).read(); prod = open(sys.argv[2]).read()
bad = 0
for m in re.finditer(r"mut\((?:tc|pl), '((?:[^'\\]|\\.)*)'", t):
    a = m.group(1).encode().decode("unicode_escape")
    if "ovn_research_trigger_check" in sys.argv[2] and "_h" in a and prod.count(a) != 1:
        bad += 1
sys.exit(1 if bad else 0)
PYEOF
}
anchors_ok "$HERE/test_roadmap_floor_alert.sh" "$ROOT/scripts/ovn_research_trigger_check.py"; ok "$([ $? = 0 ] && echo 1 || echo 0)" "C1 every trigger_check mutation anchor in the floor test exists exactly once in the product"
sed 's/<= eff_h or (seen/<= floor_h or (seen/' "$HERE/test_roadmap_floor_alert.sh" > "$SB/floor_mut.sh"
anchors_ok "$SB/floor_mut.sh" "$ROOT/scripts/ovn_research_trigger_check.py"; ok "$([ $? != 0 ] && echo 1 || echo 0)" "C2 MUTANT (old floor_h anchor): C1's check fails"

echo "== D. lint stray-.bak walk"
stray_line="$(grep -m1 '^stray="\$(find' "$HERE/test_pipeline_lint.sh")"
run_stray(){ # $1 = line ; builds a tree with box runtime backups ; prints the result
  local t="$SB/d"; rm -rf "$t"; mkdir -p "$t/roadmap" "$t/backlog" "$t/state" "$t/logs" "$t/repos/x" "$t/scripts"
  : > "$t/roadmap/iptv_apps.md.bak.1789430007"; : > "$t/backlog/q.bak"; : > "$t/state/s.bak"; : > "$t/logs/l.bak.1"; : > "$t/repos/x/r.orig"
  ( cd "$t" && eval "$1"; printf '%s' "$stray" )
}
ok "$([ -n "$stray_line" ] && [ -z "$(run_stray "$stray_line")" ] && echo 1 || echo 0)" "D1 roadmap/ backlog/ state/ logs/ repos/ runtime backups are not stray"
mut_line="$(printf '%s' "$stray_line" | sed 's# -o -path ./roadmap -o -path ./backlog##')"
ok "$([ -n "$(run_stray "$mut_line")" ] && echo 1 || echo 0)" "D2 MUTANT (roadmap/backlog not pruned): the box .bak is reported (D1 would fail)"
d3="$(cd "$SB" && mkdir -p d3/scripts && : > d3/scripts/test_x.sh.bak && cd d3 && eval "$stray_line"; printf '%s' "$stray")"
ok "$([ -n "$d3" ] && echo 1 || echo 0)" "D3 a real stray .bak under scripts/ is still caught"

echo "== E. lib_stub_server.sh"
cat > "$SB/slow.py" <<'EOF'
import os, socketserver, sys, time
time.sleep(float(os.environ.get("SLOW_S", "0")))
class H(socketserver.BaseRequestHandler):
    def handle(self): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
reach(){ "$PY" -c "import socket,sys; socket.create_connection(('127.0.0.1',int(sys.argv[1])),1).close()" "$1" 2>/dev/null; }
e_run(){ # $1 = lib file ; env SLOW_S / STUB_FIRST_PORT from the caller ; echoes "rc reachable port"
  ( . "$1"; STUB_PID=""; start_stub_server "$PY" "$SB/slow.py" EPORT; rc=$?; r=0; [ $rc = 0 ] && { reach "$EPORT" && r=1; }; [ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; echo "$rc $r ${EPORT:-}" ); }
r="$(SLOW_S=2 e_run "$HERE/lib_stub_server.sh")"
ok "$([ "${r%% *}" = 0 ] && [ "$(echo "$r" | cut -d' ' -f2)" = 1 ] && echo 1 || echo 0)" "E1 a stub that needs 2s to bind is waited for (a fixed sleep 1 loses)"
cat > "$SB/old_lib.sh" <<'EOF'
start_stub_server(){ local py="$1" script="$2" var="$3" port=$((20000 + RANDOM % 20000)); "$py" "$script" "$port" >/dev/null 2>&1 & STUB_PID=$!; sleep 1; printf -v "$var" '%s' "$port"; return 0; }
EOF
r="$(SLOW_S=2 e_run "$SB/old_lib.sh")"
ok "$([ "$(echo "$r" | cut -d' ' -f2)" = 0 ] && echo 1 || echo 0)" "E2 MUTANT (the old fixed sleep 1): the same slow stub is NOT reachable (E1 would fail)"
OCC="$SB/occ.py"; printf 'import socket,sys,time\ns=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1",int(sys.argv[1]))); s.listen(5); time.sleep(60)\n' > "$OCC"
oport=$((41000 + RANDOM % 8000)); "$PY" "$OCC" "$oport" & OPID=$!; sleep 0.5
r="$(STUB_FIRST_PORT=$oport SLOW_S=0 e_run "$HERE/lib_stub_server.sh")"; kill "$OPID" 2>/dev/null; wait "$OPID" 2>/dev/null
ok "$([ "${r%% *}" = 0 ] && [ "$(echo "$r" | cut -d' ' -f2)" = 1 ] && [ "$(echo "$r" | cut -d' ' -f3)" != "$oport" ] && echo 1 || echo 0)" "E3 first port already taken: the bind failure is detected and another port is picked"
r="$(STUB_TRIES=2 STUB_WAIT_S=1 SLOW_S=5 e_run "$HERE/lib_stub_server.sh")"
ok "$([ "${r%% *}" = 1 ] && echo 1 || echo 0)" "E4 a stub that never listens: bounded, returns 1 (no hang)"
ok "$([ "$(grep -c '^[A-Z_=\"$ ]*start_stub_server ' "$HERE/test_qa_devicelane.sh")" = 2 ] && ! grep -q 'PORT_SEED=\$((PORT_BACKEND + 7))' "$HERE/test_qa_devicelane.sh" && echo 1 || echo 0)" "E5 test_qa_devicelane.sh uses the helper for both stub servers"

echo
echo "  y1 suite fixes: $P passed, $F failed"
[ "$F" = 0 ]
