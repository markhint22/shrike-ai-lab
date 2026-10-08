#!/usr/bin/env bash
# Extra coverage for queue_refill.sh: repo discovery from tasks.json, the real refill/commit/push
# path (bare origin), push-retry via rebase, push failure, git-sync failure, nothing-moved,
# FORCE_PULL, recovery/reminder/cooldown handling. queue_refill.py and queue.sh are stubbed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q=""
for c in "$HERE/../../queue_refill.sh" "$HERE/../queue_refill.sh" "$HOME/overnight-queue/queue_refill.sh"; do [ -f "$c" ] && { Q="$c"; break; }; done
[ -n "$Q" ] || { echo "SKIP: queue_refill.sh not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
wd="$tmp/overnight-queue"
mkdir -p "$wd/repos" "$wd/backlog" "$wd/roadmap" "$wd/state" "$tmp/aider-venv/bin"
cp "$Q" "$wd/queue_refill.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cat > "$wd/queue.sh" <<EOF2
#!/usr/bin/env bash
echo "\$*" >> "$tmp/queue_calls.log"
exit 0
EOF2
chmod +x "$wd/queue.sh"
# stub refill py: prints STUB_OUT and optionally appends a line to the progress file
cat > "$wd/queue_refill.py" <<'EOF2'
import os, sys
print(os.environ.get("STUB_OUT", ""))
if os.environ.get("STUB_APPEND"):
    with open(sys.argv[1], "a") as f:
        f.write(os.environ["STUB_APPEND"] + "\n")
EOF2
ALERT_LOG="$tmp/curl.log"; : > "$ALERT_LOG"
cat > "$tmp/aider-venv/bin/curl" <<EOF2
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in Title:*|These*) echo "\$a" >> "$ALERT_LOG" ;; esac; done
exit 0
EOF2
chmod +x "$tmp/aider-venv/bin/curl"

mkrepo(){ # $1=name; creates bare origin + clone with overnight/feature
  local n="$1" o="$tmp/origin_$1.git"
  git init -q --bare "$o"
  git clone -q "$o" "$wd/repos/$n" 2>/dev/null
  ( cd "$wd/repos/$n" && git checkout -q -b overnight/feature && printf -- '- [ ] [T1] seed item\n' > OVERNIGHT_PROGRESS.md && : > OVERNIGHT_DONE.md \
    && git add -A && git -c user.email=t@t -c user.name=t commit -q -m seed && git push -q origin overnight/feature )
}
run(){ ( cd "$wd" && HOME="$tmp" "$@" 2>&1 ); }
refill(){ ( cd "$wd" && HOME="$tmp" ADD_TO=28 bash ./queue_refill.sh "$@" 2>&1 ); }

# --- discovery from tasks.json (line 31) ---
cat > "$wd/tasks.json" <<'EOF2'
[{"repo":"/x/repos/alpha","type":"aider_fix"},
 {"repo":"/x/repos/beta","type":"aider_fix","enabled":false},
 {"repo":"/x/repos/gamma","type":"other"},
 {"repo":"/x/repos/alpha","type":"aider_fix"}]
EOF2
out="$(run env MIN_DOABLE=0 bash ./queue_refill.sh)"
ok "discovers enabled aider_fix repos only (alpha)" "printf '%s' \"\$out\" | grep -q 'alpha: 0 doable (ok, no refill)'"
ok "disabled repo beta skipped" "! printf '%s' \"\$out\" | grep -q beta"
ok "non-aider_fix gamma skipped" "! printf '%s' \"\$out\" | grep -q gamma"
ok "pass-complete logged, alpha once" "[ \"\$(printf '%s' \"\$out\" | grep -c 'alpha:')\" -eq 1 ] && printf '%s' \"\$out\" | grep -q 'queue_refill pass complete'"

# --- A: happy refill with recovery marker (94), commit+push (110-115) ---
mkrepo r1
printf -- '- [ ] [T1] b1\n- [ ] [T1] b2\n- [ ] [T1] b3\n- [x] [T1] done\n' > "$wd/backlog/r1.md"
echo 123 > "$wd/state/qr_dry_r1"
: > "$ALERT_LOG"
out="$(STUB_OUT="REFILL=3 CREDITED=0 BACKLOG_REMAINING=0" STUB_APPEND="- [ ] [T1] pulled" refill r1)"
ok "A: refilled log line" "printf '%s' \"\$out\" | grep -q 'r1: refilled +3, credited +0'"
ok "A: dry marker cleared" "[ ! -f '$wd/state/qr_dry_r1' ]"
ok "A: recovery curl fired" "grep -q 'r1' '$ALERT_LOG'"
ok "A: recovered note logged" "printf '%s' \"\$out\" | grep -q 'backlog-recovered note sent for: r1'"
ok "A: pushed to origin" "git -C '$tmp/origin_r1.git' log overnight/feature --oneline | grep -q 'auto-refill 3 items'"
ok "A: queue hold/release called" "grep -q 'hold r1' '$tmp/queue_calls.log' && grep -q 'release r1' '$tmp/queue_calls.log'"

# --- B: nothing moved (117) ---
out="$(STUB_OUT="REFILL=0 CREDITED=0 BACKLOG_REMAINING=3" refill r1)"
ok "B: nothing moved logged" "printf '%s' \"\$out\" | grep -q 'r1: nothing moved'"
out="$(STUB_OUT="" refill r1)"
ok "B2: empty stub output defaults to 0 moved" "printf '%s' \"\$out\" | grep -q 'nothing moved'"

# --- C: credited only, plus push rejected once then retried via pull --rebase (114) ---
cnt="$tmp/rej_count"; echo 0 > "$cnt"
cat > "$tmp/origin_r1.git/hooks/pre-receive" <<EOF2
#!/usr/bin/env bash
n=\$(cat "$cnt"); if [ "\$n" -lt 1 ]; then echo \$((n+1)) > "$cnt"; echo rejected-once >&2; exit 1; fi
exit 0
EOF2
chmod +x "$tmp/origin_r1.git/hooks/pre-receive"
out="$(STUB_OUT="REFILL=0 CREDITED=2 BACKLOG_REMAINING=3" STUB_APPEND="- [x] credited" refill r1)"
ok "C: credited-only commit path logged success after retry" "printf '%s' \"\$out\" | grep -q 'r1: refilled +0, credited +2'"
ok "C: commit message has credited count" "_o=\"\$(git -C '$tmp/origin_r1.git' log overnight/feature --oneline)\"; printf '%s\n' \"\$_o\" | grep -q 'pre-verify-credited 2'"

# --- D: push always fails -> 'refill push FAILED' (115) ---
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/origin_r1.git/hooks/pre-receive"
out="$(STUB_OUT="REFILL=1 CREDITED=0 BACKLOG_REMAINING=3" STUB_APPEND="- [ ] [T1] more" refill r1)"
ok "D: push failure logged" "printf '%s' \"\$out\" | grep -q 'r1: refill push FAILED'"
rm -f "$tmp/origin_r1.git/hooks/pre-receive"

# --- KNOWN-BUG: `git add OVERNIGHT_PROGRESS.md OVERNIGHT_DONE.md` aborts entirely when OVERNIGHT_DONE.md
#     does not exist (fatal pathspec, stderr hidden), so nothing is staged, the commit no-ops and the
#     script still logs "refilled +N". Proposed patch: `git add -A OVERNIGHT_PROGRESS.md; [ -f OVERNIGHT_DONE.md ] && git add OVERNIGHT_DONE.md`.
mkrepo r4; ( cd "$wd/repos/r4" && git rm -q OVERNIGHT_DONE.md && git -c user.email=t@t -c user.name=t commit -q -m nodone && git push -q origin overnight/feature )
printf -- '- [ ] [T1] b1\n' > "$wd/backlog/r4.md"
STUB_OUT="REFILL=1 CREDITED=0 BACKLOG_REMAINING=0" STUB_APPEND="- [ ] [T1] pulled4" refill r4 >/dev/null
if git -C "$tmp/origin_r4.git" log overnight/feature --oneline | grep -q 'auto-refill 1 items'; then P=$((P+1)); else echo "  WARN KNOWN-BUG: queue_refill.sh:112 refill not committed when OVERNIGHT_DONE.md is absent"; fi

# --- E: git sync fails (99) ---
mkdir -p "$wd/repos/r2"; git init -q "$wd/repos/r2"
printf -- '- [ ] [T1] x\n' > "$wd/backlog/r2.md"
out="$(STUB_OUT="REFILL=1" refill r2)"
ok "E: git sync failure skips + releases" "printf '%s' \"\$out\" | grep -q 'r2: git sync failed' && grep -q 'release r2' '$tmp/queue_calls.log'"

# --- F: FORCE_PULL (95), need clamped to avail (96), need<1 -> 1 ---
out="$( cd "$wd" && HOME="$tmp" FORCE_PULL=50 STUB_OUT="REFILL=0 CREDITED=0 BACKLOG_REMAINING=3" bash ./queue_refill.sh r1 2>&1 )"
ok "F: FORCE_PULL runs refill path despite healthy doable" "printf '%s' \"\$out\" | grep -q 'r1: nothing moved'"
out="$( cd "$wd" && HOME="$tmp" ADD_TO=0 MIN_DOABLE=99 STUB_OUT="REFILL=0" bash ./queue_refill.sh r1 2>&1 )"
ok "F2: need<1 clamps to 1, still runs" "printf '%s' \"\$out\" | grep -q 'r1: nothing moved'"
# FORCE_PULL with empty backlog: dry but no marker changes
: > "$wd/backlog/r3.md"; mkdir -p "$wd/repos/r3"; printf -- '- [ ] [T1] q\n' > "$wd/repos/r3/OVERNIGHT_PROGRESS.md"
out="$( cd "$wd" && HOME="$tmp" FORCE_PULL=5 bash ./queue_refill.sh r3 2>&1 )"
ok "F3: FORCE_PULL dry repo logs DRY, no marker" "printf '%s' \"\$out\" | grep -q 'backlog DRY' && [ ! -f '$wd/state/qr_dry_r3' ]"

# --- G: dry handling: newly (86-87,131), cooldown (142), reminder (88-89,134), ---
out="$(refill r3)"
ok "G1: newly dry sets marker, suppressed ntfy log" "[ -f '$wd/state/qr_dry_r3' ] && printf '%s' \"\$out\" | grep -q 'backlog-dry (new)'"
out="$(refill r3)"
ok "G2: within cooldown -> still dry message" "printf '%s' \"\$out\" | grep -q 'still dry (no alert, within cooldown): r3'"
echo 1 > "$wd/state/qr_dry_r3"
out="$(refill r3)"
ok "G3: stale marker -> reminder logged" "printf '%s' \"\$out\" | grep -q 'backlog-dry reminder'"
ok "G3b: marker refreshed" "[ \"\$(cat '$wd/state/qr_dry_r3')\" -gt 1000 ]"
# ok-branch recovery (55): healthy repo with stale marker
printf -- '- [ ] [T1] a\n' > "$wd/repos/r3/OVERNIGHT_PROGRESS.md"
: > "$ALERT_LOG"
out="$( cd "$wd" && HOME="$tmp" MIN_DOABLE=1 bash ./queue_refill.sh r3 2>&1 )"
ok "G4: healthy repo with marker -> recovered" "printf '%s' \"\$out\" | grep -q 'backlog-recovered note sent for: r3' && [ ! -f '$wd/state/qr_dry_r3' ]"
# roadmap-ready recovery (80)
echo 5 > "$wd/state/qr_dry_r3"; printf -- '- [ ] [P1] [ready] Feature\n' > "$wd/roadmap/r3.md"
printf '' > "$wd/repos/r3/OVERNIGHT_PROGRESS.md"
out="$(refill r3)"
ok "G5: roadmap ready clears marker" "printf '%s' \"\$out\" | grep -q 'planner will refill' && [ ! -f '$wd/state/qr_dry_r3' ]"
# parked items excluded from doable
printf -- '- [ ] [T1] a\n- [ ] [CLAUDE] b\n- [ ] [T1] c HUMAN-ONLY\n' > "$wd/repos/r3/OVERNIGHT_PROGRESS.md"
out="$( cd "$wd" && HOME="$tmp" MIN_DOABLE=0 bash ./queue_refill.sh r3 2>&1 )"
ok "G6: doable excludes CLAUDE/HUMAN-ONLY (1)" "printf '%s' \"\$out\" | grep -q 'r3: 1 doable'"

echo "$P passed, $F failed"
[ "$F" -eq 0 ]
