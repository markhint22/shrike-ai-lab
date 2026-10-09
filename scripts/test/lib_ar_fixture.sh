#!/usr/bin/env bash
# lib_ar_fixture.sh - hermetic fixture for tests of ovn_auto_research.sh (the MAC-side launchd research job). Sourced by
# test_auto_research_roundrobin.sh and test_auto_research_lock.sh.
#
# The script under test talks to the GPU box over ssh/scp and to the real `claude` CLI and keeps its state in ~/.ovn_auto_research. This fixture makes
# all three harmless: a temp HOME + temp state dir, stub ssh/scp/claude first on PATH (the "box" is a temp dir), env -i so the caller's OVN_* variables
# cannot leak in (HOME and OVN_AUTO_RESEARCH_STATE both point into the temp dir, so ~/.ovn_auto_research is never written; the real launchd job writes
# that log hourly, so a before/after checksum of it would be a flaky guard and is deliberately not used).
#
#   ar_setup <script> [validator]   create T (physical path, so /private/var vs /var cannot differ), stubs, clones, a fake box; copy the script (+validator)
#   ar_starving repo:hours[:pullable] ...   write the box's research_trigger_starving.json (fresh snapshot)
#   ar_roadmap <repo> <text>        write the fake box's roadmap/<repo>.md ; ar_backlog likewise
#   ar_runlog <secs_ago> <repo> <text>   append a run.log line with a timestamp relative to now
#   ar_run [VAR=val ...]            run the script (DRY_RUN is NOT set here); output in $T/out.txt, exit code in $AR_RC
#   ar_cleanup                      remove T and check the real state dir was untouched

ar_setup(){
  local script="$1" validator="${2:-}" here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  T="$(cd "$(mktemp -d)" && pwd -P)"
  STATE="$T/state"; CLONES="$T/clones"; FAKEBIN="$T/bin"; BOX="$T/box"; CAP="$T/capture"; SHARED_T="$T/shared"
  mkdir -p "$STATE" "$CLONES" "$FAKEBIN" "$BOX/roadmap" "$BOX/backlog" "$CAP" "$T/home" "$T/tmp" "$SHARED_T/scripts/overnight-queue"
  AR_SCRIPT="$SHARED_T/scripts/overnight-queue/ovn_auto_research.sh"
  cp "$script" "$AR_SCRIPT"
  cp "${validator:-$here/../../ovn_auto_research_validate.py}" "$SHARED_T/scripts/overnight-queue/ovn_auto_research_validate.py"
  PYDIR="$(dirname "$(command -v python3)")"
  for r in iptv_apps xlite billwatch shrike-notify shrike-monitor; do mkdir -p "$CLONES/$r"; git init -q "$CLONES/$r" 2>/dev/null; done
  cat > "$FAKEBIN/ssh" <<'EOS'
#!/usr/bin/env bash
cmd="${@: -1}"
echo "ssh: $cmd" >> "$FAKEBOX/ssh.log"
[ -n "${LOCK_PEEK:-}" ] && [ ! -f "$FAKEBOX/lock_peek.txt" ] && cp "$LOCK_PEEK" "$FAKEBOX/lock_peek.txt" 2>/dev/null   # lets a test see the lock content while the script runs
case "$cmd" in
  "cat ~/overnight-queue/state/research_trigger_starving.json") cat "$FAKEBOX/starving.json" ;;
  "grep -cE"*) echo "${FAKE_READY_N:-0}" ;;
  "cd ~/"*"git log"*) echo "abc123 fake commit" ;;
  *) : ;;
esac
exit 0
EOS
  cat > "$FAKEBIN/scp" <<'EOS'
#!/usr/bin/env bash
src="${@: -2:1}"; dest="${@: -1}"
echo "scp: $src" >> "$FAKEBOX/ssh.log"
path="${src#*:}"; path="${path#overnight-queue/}"
[ -f "$FAKEBOX/$path" ] && cp "$FAKEBOX/$path" "$dest" || exit 1
EOS
  cat > "$FAKEBIN/claude" <<'EOS'
#!/usr/bin/env bash
# stub claude: capture the prompt (the argument after -p) per repo, reply NONE
prompt=""; while [ $# -gt 0 ]; do case "$1" in -p) prompt="$2"; shift;; esac; shift; done
repo="$(printf '%s\n' "$prompt" | sed -n 's/.*REPO: \([A-Za-z0-9_-]*\)\..*/\1/p' | head -1)"
printf '%s' "$prompt" > "$CAPTURE/prompt_${repo:-unknown}.txt"
echo "${repo:-unknown}" >> "$CAPTURE/calls.log"
echo NONE
EOS
  chmod +x "$FAKEBIN/ssh" "$FAKEBIN/scp" "$FAKEBIN/claude"
  : > "$BOX/ssh.log"
  # the stubs must be what the script's PATH resolves (never the real ssh/scp/claude)
  [ "$(PATH="$FAKEBIN:$PYDIR:/usr/bin:/bin" command -v ssh)" = "$FAKEBIN/ssh" ] || { echo "FATAL: stub ssh is not first on PATH"; exit 2; }
}

ar_starving(){   # repo:hours ...
  python3 - "$BOX/starving.json" "$@" <<'PY'
import json, sys, time
rows = [a.split(":") for a in sys.argv[2:]]
recs = []
for row in rows:   # repo:hours[:pullable]  (the trigger check writes `pullable` into each record)
    rec = {"repo": row[0], "starving_since": time.time() - float(row[1]) * 3600, "hours": float(row[1])}
    if len(row) > 2:
        rec["pullable"] = int(row[2])
    recs.append(rec)
json.dump({"checked_at": time.time(), "starving": recs}, open(sys.argv[1], "w"))
PY
}
ar_roadmap(){ printf '%s\n' "$2" > "$BOX/roadmap/$1.md"; }
ar_backlog(){ printf '%s\n' "$2" > "$BOX/backlog/$1.md"; }
ar_runlog(){   # <secs_ago> <repo> <text>  (text is what follows "<repo>: ")
  python3 - "$STATE/run.log" "$1" "$2" "$3" <<'PY'
import sys, time
p, ago, repo, text = sys.argv[1:5]
open(p, "a").write("%s %s: %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - float(ago))), repo, text))
PY
}
ar_run(){
  env -i HOME="$T/home" PATH="$FAKEBIN:$PYDIR:/usr/bin:/bin" SHARED_DIR="$SHARED_T" OVN_AUTO_RESEARCH_STATE="$STATE" OVN_CLONES_DIR="$CLONES" \
     OVN_SSH=stub@box OVN_AR_CLAUDE="$FAKEBIN/claude" FAKEBOX="$BOX" CAPTURE="$CAP" TMPDIR="$T/tmp" "$@" "$BASH" "$AR_SCRIPT" > "$T/out.txt" 2>&1
  AR_RC=$?
}
ar_cleanup(){ rm -rf "$T"; }
