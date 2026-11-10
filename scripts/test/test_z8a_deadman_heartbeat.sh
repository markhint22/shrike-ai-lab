#!/usr/bin/env bash
# test_z8a_deadman_heartbeat.sh - Z8a (2026-11-10): the Mac supervisor showed box-deadman STALE although the job ran every 10 min (`probe: ... llm=200 | bad=[]` in its log). Two causes:
#   1. the deployed ~/fleet_review/box_deadman.py is built from ops/fleet_review/box_deadman.py, which had no heartbeat (scripts/box_deadman.py did): both copies now write hb/box-deadman on a completed non-dry run;
#   2. the manifest's hbalt= fallback pointed at /tmp/box-deadman.launchd.log, which is cleared at every reboot (and the installed plist logs elsewhere): it now points at ~/.box_deadman/deadman.log, the persistent
#      file the script appends to on EVERY run (also the old deployed copy).
# Hermetic: temp HOME + OVN_MAC_STATE + DEADMAN_STATE_DIR, run() stubbed (no ssh, no network, never the real box); mutants (manifest back on /tmp, heartbeat call removed) must FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
SC="$(cd "$HERE/../../.." && pwd)"
MAN="$SC/mac_jobs.manifest"; SRC="$HERE/../box_deadman.py"; OPS="$HERE/../../ops/fleet_review/box_deadman.py"
[ -f "$MAN" ] && [ -f "$SC/mac_jobs_health.py" ] || { echo "  SKIP: Mac job files not present (queue-only tree)"; exit 0; }
[ -f "$SRC" ] || { echo "  SKIP: scripts/box_deadman.py not present"; exit 0; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
T="$(safe_mktemp_dir z8adm)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: Z10 mac test sandbox"; exit 1; }   # Z10: real ssh/curl/ntfy delivery impossible from this test
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }

# check_manifest <manifest-file> -> prints the resolved hbalt, rc 0 only when persistent (not under a temp dir) and equal to the deadman's own log path under HOME
check_manifest(){
  HOME="$T/home" "$PY" - "$SC" "$1" <<'PYEOF'
import os, sys, importlib.util
sc, man = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("hp", os.path.join(sc, "mac_jobs_health.py")); hp = importlib.util.module_from_spec(spec); spec.loader.exec_module(hp)
j = [x for x in hp.parse_manifest(man) if x["label"] == "com.shrike.box-deadman"][0]
a = j["hbalt"] or ""
print(a)
bad = a.startswith(("/tmp/", "/private/tmp/", "/var/tmp/", "/var/folders/", "/dev/shm/"))
want = os.path.join(os.environ["HOME"], ".box_deadman", "deadman.log")
sys.exit(1 if bad or a != want else 0)
PYEOF
}
mkdir -p "$T/home"
out="$(check_manifest "$MAN")"; rc=$?
ok "A1 real manifest: box-deadman hbalt is the persistent deadman.log under \$HOME ($out)" "$([ $rc = 0 ] && echo 1 || echo 0)"
printf 'com.shrike.box-deadman | 1800 | ~/x.log | hb/box-deadman | critical,hbalt=/tmp/box-deadman.launchd.log\n' > "$T/old.manifest"
check_manifest "$T/old.manifest" >/dev/null; ok "A2 the old manifest entry (/tmp/box-deadman.launchd.log) is rejected by the same check" "$([ $? = 1 ] && echo 1 || echo 0)"

# heartbeat + persistent log behaviour of a deadman copy: $1 = path to box_deadman.py
dm_check(){ # prints "hb=<0|1> hbdry=<0|1> log=<0|1> state=<mac state dir>"
  local src="$1" d="$T/dm.$RANDOM"; mkdir -p "$d/home" "$d/mac" "$d/dstate"
  HOME="$d/home" OVN_MAC_STATE="$d/mac" DEADMAN_STATE_DIR="$d/dstate" DEADMAN_NOW= "$PY" - "$src" "$d" <<'PYEOF'
import importlib.util, os, sys
src, d = sys.argv[1], sys.argv[2]
os.environ.pop("DEADMAN_NOW", None)
spec = importlib.util.spec_from_file_location("dm", src); dm = importlib.util.module_from_spec(spec); spec.loader.exec_module(dm)
dm.run = lambda dry=False: "ok"          # no probe, no ssh
hbp = os.path.join(d, "mac", "hb", "box-deadman")
dm.main(["--dry-run"]); hbdry = os.path.exists(hbp)
dm.main([]); hb = os.path.exists(hbp)
# persistent log: log() writes under DEADMAN_STATE_DIR (here) / ~/.box_deadman (default) - check the default path too
os.environ.pop("DEADMAN_STATE_DIR", None); os.environ.pop("DEADMAN_LOG", None)
dm.log("probe: test | bad=[]")
lg = os.path.exists(os.path.join(d, "home", ".box_deadman", "deadman.log"))
print("hb=%d hbdry=%d log=%d" % (hb, hbdry, lg))
PYEOF
}
for c in "scripts/box_deadman.py:$SRC" "ops/fleet_review/box_deadman.py:$OPS"; do
  name="${c%%:*}"; f="${c#*:}"
  [ -f "$f" ] || { echo "  (skipped: $name absent here)"; continue; }
  r="$(dm_check "$f" 2>&1 | tail -1)"
  ok "B $name: a completed run writes hb/box-deadman ($r)" "$(case "$r" in "hb=1 hbdry=0 log=1") echo 1;; *) echo 0;; esac)"
done
# mutant: heartbeat call removed => must be detected
sed 's/^            _mac_hb("box-deadman").*$/            pass/' "$SRC" > "$T/mut_dm.py"
cmp -s "$SRC" "$T/mut_dm.py" && ok "C0 mutant differs from the real script" 0
r="$(dm_check "$T/mut_dm.py" 2>&1 | tail -1)"
ok "C1 MUTANT without the heartbeat call is detected (hb=0): $r" "$(case "$r" in hb=0*) echo 1;; *) echo 0;; esac)"
echo "Z8a deadman heartbeat: $P passed, $F failed"; [ "$F" = 0 ]
