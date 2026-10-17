#!/usr/bin/env bash
# test_run_all_sandboxed.sh - run_all_sandboxed.sh (bubblewrap, real HOME read-only). 2026-10-16 home-directory-deletion incident.
# Part A (any host, no bwrap needed): refusal logic, canonical-path validation of every writable bind, /run allowlist validation, and the exact bwrap ARGUMENT
#   composition/order captured through a fake bwrap, each with mutants of the wrapper that must be caught.
# Part B (Linux with a working bwrap only): the incident replay, qtmp writability, /run emptiness, and Linux MUTANT runs (--ro-bind HOME -> --bind, reversed mount
#   order, no tmpfs over /run) that must each be caught by the same checks. On macOS Part B is SKIPPED.
# Inside the real sandbox (OVN_SANDBOXED=1, exported by run_all_sandboxed.sh together with OVN_REQUIRE_LINUX_BWRAP=1) bwrap cannot nest: Part B is replaced by live L1-L6 checks of the
#   enclosing sandbox, and only the nested-only cases are reported as 'NOT VERIFIED INSIDE THE SANDBOX'.
# A SKIP IS NOT A PASS: the summary says "NOT VERIFIED" and lists the skips; OVN_REQUIRE_LINUX_BWRAP=1 turns any skip into a failure (use it wherever the result gates a deploy).
# Everything runs under a private mktemp dir with a DECOY HOME; the real home is never used as a deletion target.
set -uo pipefail
# Hermetic env: a developer / cron / outer-sandbox environment that exports any OVN_SANDBOX_* knob must not leak into the wrapper runs below (it caused false reds: an inherited
# OVN_SANDBOX_TMPBASE moved qtmp away from $DH/qtmp). Each case sets exactly what it needs. OVN_TEST_TMP_BASE / OVN_SANDBOXED / OVN_REQUIRE_LINUX_BWRAP are NOT cleared:
# the outer wrapper sets them and Part B's nested mode needs them.
unset OVN_SANDBOX_TMPBASE OVN_SANDBOX_EXTRA_BIND OVN_SANDBOX_OVERLAY OVN_SANDBOX_RUN_ALLOW OVN_ALLOW_UNSANDBOXED OVN_SANDBOX_BWRAP OVN_SANDBOX_TARGET
export OVN_SANDBOX_TEST_HOOKS=1   # the wrapper honours OVN_SANDBOX_BWRAP / OVN_SANDBOX_TARGET only with this (see 7a-7c below for the proof that it ignores them without)
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/run_all_sandboxed.sh"
P=0; F=0; S=0; SKIPS=""
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
skip(){ S=$((S+1)); SKIPS="$SKIPS
    - $1"; echo "  SKIP $1"; }
NS=0; NSKIPS=""
skip_nested(){ NS=$((NS+1)); NSKIPS="$NSKIPS
    - $1"; echo "  SKIP(nested) $1"; }   # cases that must launch a bwrap of their own: impossible INSIDE the sandbox (bwrap cannot nest)
b(){ if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }   # b cmd args...: 1 when the command succeeds
[ -f "$W" ] || { echo "  FAIL: $W missing"; exit 1; }
SB="$(mktemp -d "${TMPDIR:-/tmp}/rasb.XXXXXX")" || { echo "  FAIL: mktemp"; exit 1; }
case "$SB" in /*/rasb.??????) ;; *) echo "  FAIL: odd mktemp result $SB"; exit 1;; esac
[ -d "$SB" ] && [ "$SB" != "/" ] && [ "$SB" != "${HOME:-/nonexistent}" ] || { echo "  FAIL: unsafe scratch dir"; exit 1; }
TMPX=""   # extra scratch dirs created under /tmp itself (named /tmp/rasb-x.XXXXXX) so cleanup can remove them
cleanup(){
  local d
  for d in $TMPX; do case "$d" in /tmp/rasb-x.??????|/private/tmp/rasb-x.??????) chmod -R u+rwX "$d" 2>/dev/null; find "$d" -mindepth 1 -depth -delete 2>/dev/null; rmdir "$d" 2>/dev/null;; esac; done
  case "$SB" in /*/rasb.??????) chmod -R u+rwX "$SB" 2>/dev/null; find "$SB" -mindepth 1 -depth -delete 2>/dev/null; rmdir "$SB" 2>/dev/null;; esac
}
trap cleanup EXIT
mktmpx(){ XV="$(mktemp -d /tmp/rasb-x.XXXXXX)" || { echo "mktemp failed" >&2; exit 2; }; TMPX="$TMPX $XV"; }   # sets XV (no subshell, so cleanup knows it)
DH="$SB/home"; mkdir -p "$DH/sub"; echo keep > "$DH/sentinel"; echo keep > "$DH/sub/sentinel2"
canon(){ ( cd -P "$1" && pwd -P ); }
DHR="$(canon "$DH")"
STUB="$SB/target.sh"; printf '#!/usr/bin/env bash\necho STUB-RAN\n' > "$STUB"

echo "== 1: refuses without bwrap and without OVN_ALLOW_UNSANDBOXED"
out="$(HOME="$DH" OVN_SANDBOX_BWRAP=/nonexistent/bwrap OVN_SANDBOX_TARGET="$STUB" env -u OVN_ALLOW_UNSANDBOXED bash "$W" 2>&1)"; rc=$?
ok "1a exit 78 (refused)" "$([ $rc -eq 78 ] && echo 1 || echo 0)"
ok "1b clear message names the missing bwrap and REFUSING" "$(printf '%s' "$out" | grep -q 'not installed' && printf '%s' "$out" | grep -q 'REFUSING' && echo 1 || echo 0)"
ok "1c the target did NOT run" "$(printf '%s' "$out" | grep -q STUB-RAN && echo 0 || echo 1)"
echo "== 2: OVN_ALLOW_UNSANDBOXED=0 or empty still refuses"
for v in 0 ""; do
  HOME="$DH" OVN_SANDBOX_BWRAP=/nonexistent/bwrap OVN_SANDBOX_TARGET="$STUB" OVN_ALLOW_UNSANDBOXED="$v" bash "$W" >/dev/null 2>&1; rc=$?
  ok "2 value '$v' refuses (78)" "$([ $rc -eq 78 ] && echo 1 || echo 0)"
done
echo "== 3: explicit OVN_ALLOW_UNSANDBOXED=1 runs the target with a warning"
out="$(HOME="$DH" OVN_SANDBOX_BWRAP=/nonexistent/bwrap OVN_SANDBOX_TARGET="$STUB" OVN_ALLOW_UNSANDBOXED=1 bash "$W" 2>&1)"; rc=$?
ok "3a runs (rc 0, STUB-RAN)" "$([ $rc -eq 0 ] && printf '%s' "$out" | grep -q STUB-RAN && echo 1 || echo 0)"
ok "3b warns UNSANDBOXED" "$(printf '%s' "$out" | grep -q UNSANDBOXED && echo 1 || echo 0)"
echo "== 3c: HOME unset or / is refused (even with bwrap)"
HOME=/ OVN_SANDBOX_TARGET="$STUB" bash "$W" >/dev/null 2>&1; rc=$?
ok "3c HOME=/ refused or bwrap missing (78)" "$([ $rc -eq 78 ] && echo 1 || echo 0)"

# ---------------- Part A: validation + argument composition through a fake bwrap (any host)
FB="$SB/fakebw"; printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARGS_OUT"\nexit 0\n' > "$FB"; chmod +x "$FB"
AO="$SB/args.out"
# rw <wrapper> VAR=val...: run a wrapper copy with the fake bwrap and the decoy HOME; sets RC and removes the args file first
rw(){ local wr="$1"; shift; rm -f "$AO"; env HOME="$DH" OVN_SANDBOX_BWRAP="$FB" OVN_SANDBOX_TARGET="$STUB" ARGS_OUT="$AO" "$@" bash "$wr" >"$SB/rw.out" 2>&1; RC=$?; }
joined(){ tr '\n' ' ' < "$AO"; }
refused(){ local wr="$1"; shift; rw "$wr" "$@"; [ "$RC" = 78 ] && [ ! -e "$AO" ] && grep -q 'REFUSED' "$SB/rw.out"; }   # 78, REFUSED message, bwrap never invoked
accepted(){ local wr="$1"; shift; rw "$wr" "$@"; [ "$RC" = 0 ] && [ -e "$AO" ]; }
echo "== A0: test hooks are ignored unless OVN_SANDBOX_TEST_HOOKS=1 (a stray env var must never force a green run; the fake bwrap is found via PATH, so the real suite is never started)"
mkdir -p "$SB/fakebin"; cp "$FB" "$SB/fakebin/bwrap"
printf '#!/usr/bin/env bash\necho EVIL-TARGET-RAN\n' > "$SB/evil_target.sh"
nohooks(){ rm -f "$AO"; env -u OVN_SANDBOX_TEST_HOOKS PATH="$SB/fakebin:$PATH" HOME="$DH" ARGS_OUT="$AO" OVN_SANDBOX_TARGET="$SB/evil_target.sh" OVN_SANDBOX_BWRAP=/bin/true bash "$1" >"$SB/nh.out" 2>&1; RC=$?; }
nohooks "$W"
ok "A0a without the flag the foreign OVN_SANDBOX_TARGET is NOT the target (the last bwrap args are 'bash <run_all.sh>')" "$([ -e "$AO" ] && tail -2 "$AO" | tr '\n' ' ' | grep -q "bash $HERE/run_all.sh" && ! grep -q evil_target "$AO" && echo 1 || echo 0)"
ok "A0b ... the foreign OVN_SANDBOX_BWRAP=/bin/true was NOT used as the sandbox binary (our PATH bwrap was invoked) and rc is the real bwrap's" "$([ -e "$AO" ] && [ $RC -eq 0 ] && echo 1 || echo 0)"
ok "A0c ... and the ignoring is announced (warning), not silent" "$(grep -q 'ignoring OVN_SANDBOX_BWRAP' "$SB/nh.out" && echo 1 || echo 0)"
rw "$W"; ok "A0d with OVN_SANDBOX_TEST_HOOKS=1 the hooks work (the fake bwrap + STUB target from rw are used)" "$([ -e "$AO" ] && tail -2 "$AO" | tr '\n' ' ' | grep -q "bash $STUB" && echo 1 || echo 0)"
sed 's|^if \[ "\${OVN_SANDBOX_TEST_HOOKS:-}" = "1" \]; then|if true; then|' "$W" > "$SB/mutH.sh"
ok "A0e mutant H (hooks gate removed) differs and parses" "$([ "$(cmp -s "$W" "$SB/mutH.sh"; echo $?)" = 1 ] && bash -n "$SB/mutH.sh" && echo 1 || echo 0)"
nohooks "$SB/mutH.sh"
ok "A0f MUTANT H (gate removed) is CAUGHT: the stray OVN_SANDBOX_BWRAP replaces the sandbox (our bwrap is never invoked)" "$([ ! -e "$AO" ] && echo 1 || echo 0)"


echo "== A1: default composition and mount order (captured from the fake bwrap)"
rw "$W"
J="$(joined)"
ok "A1a default run reaches bwrap (rc 0)" "$([ $RC = 0 ] && [ -e "$AO" ] && echo 1 || echo 0)"
ok "A1b / is read-only and /run is a tmpfs (plus /run/user) BEFORE /tmp is bound" "$(case "$J" in *"--ro-bind / / "*"--tmpfs /run --tmpfs /run/user "*"--bind /tmp /tmp "*) echo 1;; *) echo 0;; esac)"
ok "A1c HOME is bound read-only and NEVER read-write" "$(case "$J" in *"--ro-bind $DH $DH "*) case "$J" in *" --bind $DH $DH "*) echo 0;; *) echo 1;; esac;; *) echo 0;; esac)"
rest="${J#*--ro-bind $DH $DH }"
ok "A1d qtmp is bound writable AFTER the read-only HOME (so it stays writable)" "$(case "$rest" in *"--bind $DHR/qtmp $DHR/qtmp "*) echo 1;; *) echo 0;; esac)"

echo "== A2: private TMPDIR base validation (canonical path)"
mkdir -p "$SB/real_q" "$DH/.ssh"; ln -s "$SB/real_q" "$SB/linkq"
mktmpx; X1="$XV"; mkdir -p "$X1/real" ; ln -s "$X1/real" "$X1/link"
ok "A2a TMPBASE = HOME refused" "$(b refused "$W" OVN_SANDBOX_TMPBASE="$DH")"
ok "A2b TMPBASE = / refused" "$(b refused "$W" OVN_SANDBOX_TMPBASE=/)"
ok "A2c TMPBASE = an ancestor of HOME refused" "$(b refused "$W" OVN_SANDBOX_TMPBASE="$SB")"
ok "A2d TMPBASE = HOME/.ssh (inside HOME, not qtmp) refused" "$(b refused "$W" OVN_SANDBOX_TMPBASE="$DH/.ssh")"
ok "A2e TMPBASE outside qtmp and /tmp (/usr/rasb-nope) refused" "$(b refused "$W" OVN_SANDBOX_TMPBASE=/usr/rasb-nope)"
ok "A2f TMPBASE that is a symlink (even to an allowed /tmp dir) refused" "$(b refused "$W" OVN_SANDBOX_TMPBASE="$X1/link")"
rmdir "$DH/qtmp" 2>/dev/null; ln -s "$SB/real_q" "$DH/qtmp"
ok "A2g the default qtmp being a symlink is refused" "$(b refused "$W")"
find "$DH/qtmp" -maxdepth 0 -type l -delete
ok "A2h TMPBASE strictly under /tmp is accepted and bound writable" "$(b accepted "$W" OVN_SANDBOX_TMPBASE="$X1/real")"
ok "A2i ... and appears as a writable bind of its canonical path" "$(case "$(joined)" in *"--bind $(canon "$X1/real") $(canon "$X1/real") "*) echo 1;; *) echo 0;; esac)"
mkdir -p "$DH/qtmp"
ok "A2j TMPBASE = HOME/qtmp/sub is accepted" "$(b accepted "$W" OVN_SANDBOX_TMPBASE="$DH/qtmp/sub")"

echo "== A3: OVN_SANDBOX_EXTRA_BIND validation"
mkdir -p "$DH/qtmp/okextra"; ln -s "$DH" "$DH/qtmp/to_home"; ln -s / "$DH/qtmp/to_root"
mktmpx; X2="$XV"; mkdir -p "$X2/e"; ln -s "$DH" "$X2/to_home"
ok "A3a extra = HOME refused" "$(b refused "$W" OVN_SANDBOX_EXTRA_BIND="$DH")"
ok "A3b extra = / refused" "$(b refused "$W" OVN_SANDBOX_EXTRA_BIND=/)"
ok "A3c extra = ancestor of HOME refused" "$(b refused "$W" OVN_SANDBOX_EXTRA_BIND="$SB")"
ok "A3d extra = symlink inside qtmp that resolves to HOME refused (canonicalised)" "$(b refused "$W" OVN_SANDBOX_EXTRA_BIND="$DH/qtmp/to_home")"
ok "A3e extra = symlink inside qtmp that resolves to / refused" "$(b refused "$W" OVN_SANDBOX_EXTRA_BIND="$DH/qtmp/to_root")"
ok "A3f extra = symlink under /tmp that resolves to HOME refused" "$(b refused "$W" OVN_SANDBOX_EXTRA_BIND="$X2/to_home")"
ok "A3g extra outside qtmp and /tmp (/usr) refused" "$(b refused "$W" OVN_SANDBOX_EXTRA_BIND=/usr)"
ok "A3h one bad entry among good ones refuses the whole run" "$(b refused "$W" OVN_SANDBOX_EXTRA_BIND="$DH/qtmp/okextra:/usr")"
ok "A3i extras under qtmp and strictly under /tmp are accepted, bound writable by canonical path" "$(b accepted "$W" OVN_SANDBOX_EXTRA_BIND="$DH/qtmp/okextra:$X2/e")"
ok "A3j ... both appear as --bind" "$(case "$(joined)" in *"--bind $DHR/qtmp/okextra $DHR/qtmp/okextra "*"--bind $(canon "$X2/e") $(canon "$X2/e") "*) echo 1;; *) echo 0;; esac)"

echo "== A4: OVN_SANDBOX_OVERLAY validation"
mkdir -p "$DH/qtmp/ov" "$DH/livedir"
ok "A4a overlay without '=' rejected" "$(b refused "$W" OVN_SANDBOX_OVERLAY="$DH/qtmp/ov")"
ok "A4b overlay with an empty side rejected" "$(b refused "$W" OVN_SANDBOX_OVERLAY="$DH/qtmp/ov=")"
ok "A4c overlay with a missing dst rejected (fail closed, no silent ignore)" "$(b refused "$W" OVN_SANDBOX_OVERLAY="$DH/qtmp/ov=$DH/nonexistent")"
ok "A4d overlay src outside qtmp and /tmp rejected" "$(b refused "$W" OVN_SANDBOX_OVERLAY="/usr=$DH/livedir")"
ok "A4e overlay src = HOME rejected" "$(b refused "$W" OVN_SANDBOX_OVERLAY="$DH=$DH/livedir")"
ok "A4f overlay dst = HOME rejected" "$(b refused "$W" OVN_SANDBOX_OVERLAY="$DH/qtmp/ov=$DH")"
ok "A4g overlay dst = an ancestor of HOME rejected" "$(b refused "$W" OVN_SANDBOX_OVERLAY="$DH/qtmp/ov=$SB")"
ok "A4h overlay dst = / rejected" "$(b refused "$W" OVN_SANDBOX_OVERLAY="$DH/qtmp/ov=/")"
ok "A4i overlay src symlink resolving to HOME rejected" "$(b refused "$W" OVN_SANDBOX_OVERLAY="$DH/qtmp/to_home=$DH/livedir")"
ok "A4j a valid overlay (scratch under qtmp over a dir in HOME) is accepted: --bind src dst" "$(b accepted "$W" OVN_SANDBOX_OVERLAY="$DH/qtmp/ov=$DH/livedir")"
ok "A4k ... with the exact canonical src and dst" "$(case "$(joined)" in *"--bind $DHR/qtmp/ov $DHR/livedir "*) echo 1;; *) echo 0;; esac)"

echo "== A5: /run allowlist validation (Linux hosts; /run does not exist on macOS)"
if [ -d /run ]; then
  ok "A5a allow = /run refused" "$(b refused "$W" OVN_SANDBOX_RUN_ALLOW=/run)"
  ok "A5b allow outside /run (/etc) refused" "$(b refused "$W" OVN_SANDBOX_RUN_ALLOW=/etc)"
  ok "A5c relative allow entry refused" "$(b refused "$W" OVN_SANDBOX_RUN_ALLOW=run/lock)"
  [ -d /run/user ] && ok "A5d allow = /run/user refused" "$(b refused "$W" OVN_SANDBOX_RUN_ALLOW=/run/user)" || skip "A5d /run/user does not exist on this host"
  for sock in /run/docker.sock /run/containerd /run/podman /run/dbus; do
    [ -e "$sock" ] && ok "A5e allow = $sock refused" "$(b refused "$W" OVN_SANDBOX_RUN_ALLOW="$sock")"
  done
  okdir=""; for d in /run/*/; do d="${d%/}"; [ -d "$d" ] || continue; case "$d" in *docker*|*containerd*|*podman*|*crio*|*dbus*|*/bus|*agent*|*/ssh*|/run/user) continue;; esac; okdir="$d"; break; done
  if [ -n "$okdir" ]; then
    ok "A5f a plain dir under /run ($okdir) is accepted and bound READ-ONLY after the tmpfs" "$(b accepted "$W" OVN_SANDBOX_RUN_ALLOW="$okdir")"
    OKR="$(canon "$okdir")"
    ok "A5g ... order: tmpfs /run first, then --ro-bind of it, never --bind" "$(case "$(joined)" in *"--tmpfs /run "*"--ro-bind $OKR $OKR "*) case "$(joined)" in *" --bind $OKR "*) echo 0;; *) echo 1;; esac;; *) echo 0;; esac)"
  else if [ "${OVN_SANDBOXED:-}" = 1 ]; then skip_nested "A5f/g no plain directory under /run: inside the sandbox /run is an empty tmpfs by design (the same validation runs on every direct Linux run)"; else skip "A5f/g no suitable plain directory under /run on this host"; fi; fi
else
  skip "A5 /run allowlist validation: this host has no /run (macOS). The Linux box run covers it"
fi

echo "== A6: MUTANTS of the wrapper must be caught by the same checks (argument-level, any host)"
mutant(){ sed "$@" "$W" > "$SB/mut.sh"; }
is_ro_home(){ rw "$1"; local j; j="$(joined)"; [ "$RC" = 0 ] && case "$j" in *"--ro-bind $DH $DH "*) case "$j" in *" --bind $DH $DH "*) return 1;; *) return 0;; esac;; *) return 1;; esac; }
mutant 's|--ro-bind "\$HOME" "\$HOME"|--bind "$HOME" "$HOME"|'; cp "$SB/mut.sh" "$SB/mutA.sh"
ok "real wrapper binds HOME read-only (control)" "$(b is_ro_home "$W")"
ok "mutant A differs and parses" "$([ "$(cmp -s "$W" "$SB/mutA.sh"; echo $?)" = 1 ] && bash -n "$SB/mutA.sh" && echo 1 || echo 0)"
ok "MUTANT A (--ro-bind HOME -> --bind HOME) is CAUGHT" "$(if is_ro_home "$SB/mutA.sh"; then echo 0; else echo 1; fi)"
qtmp_after_home(){ rw "$1"; local j rest; j="$(joined)"; rest="${j#*--ro-bind $DH $DH }"; case "$rest" in *"--bind $DHR/qtmp $DHR/qtmp "*) return 0;; esac; return 1; }
mutant -e '/# MOUNT-HOME$/{h;d;}' -e '/# MOUNT-QBASE$/{G;}'; cp "$SB/mut.sh" "$SB/mutB.sh"
ok "real wrapper mounts qtmp after HOME (control)" "$(b qtmp_after_home "$W")"
ok "mutant B differs and parses" "$([ "$(cmp -s "$W" "$SB/mutB.sh"; echo $?)" = 1 ] && bash -n "$SB/mutB.sh" && echo 1 || echo 0)"
ok "MUTANT B (reversed mount order: qtmp before HOME) is CAUGHT" "$(if qtmp_after_home "$SB/mutB.sh"; then echo 0; else echo 1; fi)"
run_tmpfs(){ rw "$1"; case "$(joined)" in *"--tmpfs /run "*"--bind /tmp /tmp "*) return 0;; esac; return 1; }
mutant '/# MOUNT-RUN$/d'; cp "$SB/mut.sh" "$SB/mutC.sh"
ok "real wrapper puts a tmpfs over /run (control)" "$(b run_tmpfs "$W")"
ok "MUTANT C (no tmpfs over /run) is CAUGHT" "$(if run_tmpfs "$SB/mutC.sh"; then echo 0; else echo 1; fi)"
symq_refused(){ refused "$1" OVN_SANDBOX_TMPBASE="$X1/link"; }
sed '\#\[ -L "\$QBASE_RAW" \]#d' "$W" > "$SB/mut.sh"; cp "$SB/mut.sh" "$SB/mutD.sh"
ok "real wrapper refuses a symlink QBASE that resolves into /tmp (control)" "$(b symq_refused "$W")"
ok "mutant D differs and parses" "$([ "$(cmp -s "$W" "$SB/mutD.sh"; echo $?)" = 1 ] && bash -n "$SB/mutD.sh" && echo 1 || echo 0)"
ok "MUTANT D (symlink-QBASE refusal removed) is CAUGHT" "$(if symq_refused "$SB/mutD.sh"; then echo 0; else echo 1; fi)"
canon_extra_refused(){ refused "$1" OVN_SANDBOX_EXTRA_BIND="$DHR/qtmp/to_home"; }
mutant 's|c="$(canon_dir "$p")"; else c="$(canon_any "$p")"; fi|c="$p"; else c="$p"; fi|'; cp "$SB/mut.sh" "$SB/mutE.sh"
ok "real wrapper canonicalises extras (control)" "$(b canon_extra_refused "$W")"
ok "mutant E differs and parses" "$([ "$(cmp -s "$W" "$SB/mutE.sh"; echo $?)" = 1 ] && bash -n "$SB/mutE.sh" && echo 1 || echo 0)"
ok "MUTANT E (no canonicalisation: a symlink to HOME inside qtmp passes) is CAUGHT" "$(if canon_extra_refused "$SB/mutE.sh"; then echo 0; else echo 1; fi)"

# ---------------- Part B: real bubblewrap (Linux only)
REAL_BW="$(command -v bwrap || true)"
if [ "$(uname -s)" != "Linux" ] || [ -z "$REAL_BW" ] || ! "$REAL_BW" --ro-bind / / true >/dev/null 2>&1; then
  if [ "${OVN_SANDBOXED:-}" = 1 ] && [ "$(uname -s)" = "Linux" ] && [ -n "$REAL_BW" ]; then
    # We are INSIDE the real sandbox (bwrap cannot nest). Verify that enclosing sandbox LIVE instead of skipping: these are the same properties cases 4, 5 and B1 prove with a
    # nested bwrap, checked against the sandbox that is actually running this suite. Forging OVN_SANDBOXED=1 outside a sandbox makes these FAIL (HOME would be writable).
    echo "== L: nested bwrap impossible here (OVN_SANDBOXED=1): the enclosing sandbox is verified live"
    ok "L1 the real HOME ($HOME) is read-only (the incident replay could not delete or create anything in it)" "$([ ! -w "$HOME" ] && echo 1 || echo 0)"
    ok "L2 / is read-only (/etc not writable)" "$([ ! -w /etc ] && echo 1 || echo 0)"
    LQ="${OVN_TEST_TMP_BASE:-}"
    ok "L3 the private TMPDIR base ($LQ) is set, is not HOME, and is writable (a probe dir can be made and removed)" "$([ -n "$LQ" ] && [ "$LQ" != "$HOME" ] && LP="$(mktemp -d "$LQ/lprobe.XXXXXX" 2>/dev/null)" && [ -d "$LP" ] && rmdir "$LP" && echo 1 || echo 0)"
    ok "L4 /tmp is writable" "$(LT="$(mktemp -d /tmp/lprobe.XXXXXX 2>/dev/null)" && [ -d "$LT" ] && rmdir "$LT" && echo 1 || echo 0)"
    if [ -n "${OVN_SANDBOX_RUN_ALLOW:-}" ]; then ok "L5 /run/docker.sock is not reachable (an allowlist is set, so /run is not required to be empty)" "$([ ! -S /run/docker.sock ] && echo 1 || echo 0)"
    else ok "L5 /run is an empty tmpfs: no docker.sock, nothing from the host" "$([ -z "$(ls -A /run 2>/dev/null | grep -v '^user$')" ] && [ ! -S /run/docker.sock ] && echo 1 || echo 0)"; fi
    ok "L6 /run/user is empty (no user dbus/session sockets)" "$([ -z "$(ls -A /run/user 2>/dev/null)" ] && echo 1 || echo 0)"
    skip_nested "4-5,B1-B6 incident replay / mutant runs / failure injection: they launch their own bwrap, which cannot nest inside the sandbox. The sandbox properties they prove are verified live above (L1-L6); the MUTANT runs (test sensitivity) only run when this file is run directly on Linux outside the sandbox: OVN_REQUIRE_LINUX_BWRAP=1 bash test_run_all_sandboxed.sh"
  else
    skip "4-5,B1-B6 real-bwrap cases: need Linux with a working bwrap (uname=$(uname -s), bwrap=${REAL_BW:-none}); macOS has no bubblewrap. NOT VERIFIED on this host"
  fi
else
  cat > "$SB/evil.sh" <<'EOS'
#!/usr/bin/env bash
# replay of the incident (deliberately unsafe; runs ONLY inside the sandbox, on the decoy; RMBIN avoids the unsafe-rm lint on purpose): mktemp fails -> HOME falls back to the parent -> rm -rf $HOME
tmp=$(mktemp -d /nonexistent-dir/x.XXXX 2>/dev/null)
export HOME="${tmp}/home"; [ -n "$tmp" ] || export HOME="$DECOY"
"$RMBIN" -rf "$HOME" 2> "$OUTERR"; echo "rm rc=$?" > "$OUTRC"
"$RMBIN" -rf "$DECOY"/* 2>> "$OUTERR"
: > "$DECOY/newfile" 2>> "$OUTERR"; echo "touch rc=$?" >> "$OUTRC"
EOS
  # fresh decoy per run: mkdecoy sets DD (decoy home) with sentinels
  mkdecoy(){ DD="$SB/decoy.$1"; mkdir -p "$DD/sub"; echo keep > "$DD/sentinel"; echo keep > "$DD/sub/sentinel2"; }
  # incident_safe <wrapper>: 0 only when the replay could NOT destroy or modify the decoy HOME
  incident_safe(){
    mkdecoy "$2"; rm -f "$SB/err.$2" "$SB/rc.$2"
    HOME="$DD" DECOY="$DD" RMBIN="$(command -v rm)" OUTERR="$SB/err.$2" OUTRC="$SB/rc.$2" OVN_SANDBOX_TARGET="$SB/evil.sh" bash "$1" >/dev/null 2>&1
    [ -f "$DD/sentinel" ] && [ -f "$DD/sub/sentinel2" ] && [ ! -e "$DD/newfile" ] && grep -qi 'read-only file system' "$SB/err.$2"
  }
  printf '#!/usr/bin/env bash\ntouch "$OVN_TEST_TMP_BASE/probe" && echo "$OVN_TEST_TMP_BASE" > "$OUT"\n' > "$SB/ok.sh"
  # qtmp_writable <wrapper> <tag>: 0 when qtmp is writable inside AND OVN_TEST_TMP_BASE points at it
  qtmp_writable(){ mkdecoy "q$2"; rm -f "$SB/base.$2"; HOME="$DD" OUT="$SB/base.$2" OVN_SANDBOX_TARGET="$SB/ok.sh" bash "$1" >/dev/null 2>&1; [ -f "$DD/qtmp/probe" ] && [ "$(cat "$SB/base.$2" 2>/dev/null)" = "$(canon "$DD")/qtmp" ]; }
  printf '#!/usr/bin/env bash\nn=$(ls -A /run | grep -v "^user$" | wc -l | tr -d " ")\n{ echo "n=$n"; [ -S /run/docker.sock ] && echo SOCK-VISIBLE; [ -e /run/user ] && echo "runuser=$(ls -A /run/user | wc -l | tr -d " ")"; touch /run/probe && echo RUN-WRITABLE; } > "$OUT"\n' > "$SB/run.sh"
  # run_hidden <wrapper> <tag> [env...]: 0 when /run holds NOTHING from the host (no docker.sock, no user dirs), and is a writable scratch tmpfs
  run_hidden(){ local w="$1" t="$2"; shift 2; mkdecoy "r$t"; rm -f "$SB/run.$t"; env HOME="$DD" OUT="$SB/run.$t" OVN_SANDBOX_TARGET="$SB/run.sh" "$@" bash "$w" >/dev/null 2>&1
    grep -q '^n=0$' "$SB/run.$t" && ! grep -q SOCK-VISIBLE "$SB/run.$t" && ! grep -q 'runuser=[1-9]' "$SB/run.$t" && grep -q RUN-WRITABLE "$SB/run.$t"; }

  echo "== 4: a deletion inside the sandbox fails and the decoy HOME survives (incident replay)"
  mkdecoy 4
  HOME="$DD" DECOY="$DD" RMBIN="$(command -v rm)" OUTERR="$SB/err.4" OUTRC="$SB/rc.4" OVN_SANDBOX_TARGET="$SB/evil.sh" bash "$W" >/dev/null 2>&1
  ok "4a sentinel survives" "$([ -f "$DD/sentinel" ] && [ -f "$DD/sub/sentinel2" ] && echo 1 || echo 0)"
  ok "4b the rm failed with a read-only filesystem error" "$(grep -qi 'read-only file system' "$SB/err.4" && echo 1 || echo 0)"
  ok "4c no new file could be created in the decoy HOME" "$([ ! -e "$DD/newfile" ] && echo 1 || echo 0)"
  echo "== 5: the private TMPDIR base stays writable, and OVN_TEST_TMP_BASE points at it"
  mkdecoy 5; HOME="$DD" OUT="$SB/base.5" OVN_SANDBOX_TARGET="$SB/ok.sh" bash "$W" >/dev/null 2>&1
  ok "5a qtmp base writable inside the sandbox" "$([ -f "$DD/qtmp/probe" ] && echo 1 || echo 0)"
  ok "5b OVN_TEST_TMP_BASE = HOME/qtmp" "$([ "$(cat "$SB/base.5" 2>/dev/null)" = "$(canon "$DD")/qtmp" ] && echo 1 || echo 0)"

  echo "== B1: /run is a tmpfs: docker.sock, the user session dir and every host runtime path are unreachable"
  if [ -z "$(ls -A /run 2>/dev/null)" ]; then skip "B1 the host /run is empty, so hiding it proves nothing here"
  else
    ok "B1a inside the sandbox /run is empty, no docker.sock, /run/user empty, and writable scratch" "$(b run_hidden "$W" 1)"
    ok "B1b the host /run content is unchanged by the sandbox run (probe did not leak out)" "$([ ! -e /run/probe ] && echo 1 || echo 0)"
    RA=""; for d in /run/*/; do d="${d%/}"; case "$d" in *docker*|*containerd*|*podman*|*crio*|*dbus*|*/bus|*agent*|*/ssh*|/run/user) continue;; esac; [ -d "$d" ] && { RA="$d"; break; }; done
    if [ -n "$RA" ]; then
      mkdecoy ra; printf '#!/usr/bin/env bash\n{ [ -d "%s" ] && echo ALLOWED-VISIBLE; touch "%s/probe" 2>/dev/null && echo ALLOWED-WRITABLE; } > "$OUT"\n' "$RA" "$RA" > "$SB/ra.sh"
      HOME="$DD" OUT="$SB/ra.out" OVN_SANDBOX_TARGET="$SB/ra.sh" OVN_SANDBOX_RUN_ALLOW="$RA" bash "$W" >/dev/null 2>&1
      ok "B1c an allowlisted /run path ($RA) is visible inside and READ-ONLY" "$(grep -q ALLOWED-VISIBLE "$SB/ra.out" && ! grep -q ALLOWED-WRITABLE "$SB/ra.out" && echo 1 || echo 0)"
    else skip "B1c no plain /run subdir to use as an allowlist example"; fi
  fi

  echo "== B2-B4: Linux MUTANT runs against real bwrap: each must be caught by the same checks that pass on the real wrapper"
  ok "B2-control real wrapper: incident replay is contained" "$(b incident_safe "$W" c1)"
  ok "B2-control real wrapper: qtmp writable" "$(b qtmp_writable "$W" c1)"
  sed 's|--ro-bind "\$HOME" "\$HOME"|--bind "$HOME" "$HOME"|' "$W" > "$SB/lmutA.sh"
  ok "B2a mutant differs from the original" "$([ "$(cmp -s "$W" "$SB/lmutA.sh"; echo $?)" = 1 ] && echo 1 || echo 0)"
  ok "B2b MUTANT (--ro-bind HOME -> --bind HOME, decoy HOME only) is CAUGHT: the replay now destroys the decoy" "$(if incident_safe "$SB/lmutA.sh" m1; then echo 0; else echo 1; fi)"
  sed -e '/# MOUNT-HOME$/{h;d;}' -e '/# MOUNT-QBASE$/{G;}' "$W" > "$SB/lmutB.sh"
  ok "B3a mutant (reversed mount order) differs from the original" "$([ "$(cmp -s "$W" "$SB/lmutB.sh"; echo $?)" = 1 ] && echo 1 || echo 0)"
  ok "B3b MUTANT (qtmp mounted before the read-only HOME) is CAUGHT: qtmp is no longer writable" "$(if qtmp_writable "$SB/lmutB.sh" m2; then echo 0; else echo 1; fi)"
  if [ -z "$(ls -A /run 2>/dev/null)" ]; then skip "B4 host /run is empty: cannot prove the no-tmpfs mutant leaks"
  else
    sed '/# MOUNT-RUN$/d' "$W" > "$SB/lmutC.sh"
    ok "B4a mutant (no tmpfs over /run) differs from the original" "$([ "$(cmp -s "$W" "$SB/lmutC.sh"; echo $?)" = 1 ] && echo 1 || echo 0)"
    ok "B4b MUTANT (no tmpfs over /run) is CAUGHT: host /run entries are visible inside" "$(if run_hidden "$SB/lmutC.sh" m3; then echo 0; else echo 1; fi)"
  fi
  echo "== B5: refusals hold with the REAL bwrap too (nothing mounted, nothing run)"
  mkdecoy b5; HOME="$DD" OVN_SANDBOX_EXTRA_BIND="$DD" OVN_SANDBOX_TARGET="$STUB" bash "$W" >"$SB/b5.out" 2>&1; rc=$?
  ok "B5a extra bind = HOME refused (78) before bwrap starts, target did not run" "$([ $rc -eq 78 ] && ! grep -q STUB-RAN "$SB/b5.out" && echo 1 || echo 0)"
fi

echo
echo "run_all_sandboxed: $P passed, $F failed, $S skipped, $NS skipped(nested)"
if [ "$S" -gt 0 ]; then
  echo "NOT VERIFIED (a SKIP is NOT a pass):$SKIPS"
  echo "  -> run this test on the Linux box (or any Linux host with bwrap) before trusting the sandbox; OVN_REQUIRE_LINUX_BWRAP=1 makes any skip a failure."
fi
if [ "$NS" -gt 0 ]; then
  echo "NOT VERIFIED INSIDE THE SANDBOX (cannot nest; the sandbox itself was verified live):$NSKIPS"
fi
[ "$F" -eq 0 ] || exit 1
if [ "$S" -gt 0 ] && [ "${OVN_REQUIRE_LINUX_BWRAP:-0}" = 1 ]; then echo "FAIL: $S skipped case(s) and OVN_REQUIRE_LINUX_BWRAP=1"; exit 1; fi
exit 0
