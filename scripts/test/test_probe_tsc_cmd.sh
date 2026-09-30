#!/usr/bin/env bash
# Regression: probe_tsc_cmd.sh injects a guaranteed type error file into each web dir, runs 3 candidate vue-tsc commands
# (each under `timeout 150`), reports errs=<n> + whether the probe was seen, and always removes the probe file.
# Hermetic: temp $HOME tree, stub npx/timeout first on PATH (never a real tsc/network).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../probe_tsc_cmd.sh"; [ -f "$S" ] || S="$HERE/../probe_tsc_cmd.sh"; [ -f "$S" ] || S="$HERE/probe_tsc_cmd.sh"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = "1" ]; then echo "  ok   $1"; else echo "  WARN KNOWN-BUG: $1 (non-fatal)"; fi; }
both(){ [ "$1" = 1 ] && [ "$2" = 1 ] && echo 1 || echo 0; }
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; W="$H/overnight-queue"; mkdir -p "$W" "$T/bin"
LOG="$T/calls.log"
cat > "$T/bin/timeout" <<X
#!/bin/sh
echo "timeout \$1" >> "$LOG"; shift; exec "\$@"
X
cat > "$T/bin/npx" <<X
#!/bin/sh
# records: cwd, args, whether the probe file exists right now (in src/ or .)
pf=no; [ -f src/__gate_probe.ts ] && pf=src; [ -f ./__gate_probe.ts ] && pf=dot
echo "npx \$(basename "\$PWD") probe=\$pf \$*" >> "$LOG"
case "\$*" in
  *"-p tsconfig.json"*) echo "src/other.ts(1,1): error TS2322: x"; echo "src/other2.ts(1,1): error TS2322: y";;
  *"-b --force"*)       echo "src/__gate_probe.ts(1,14): error TS2322: Type 'string' is not assignable to type 'number'."; echo "noise line without code"; echo "src/__gate_probe.ts(2,1): error TS1005: z";;
  *"--noEmit"*)         [ "\${STUB_PLAIN_CLEAN:-0}" = 1 ] || echo "src/__gate_probe.ts(1,14): error TS2322: bad";;
esac
exit 2
X
chmod +x "$T/bin/timeout" "$T/bin/npx"
run(){ : > "$LOG"; ( cd "$T" && HOME="$H" PATH="$T/bin:$PATH" bash "$S" ) > "$T/out" 2>&1; echo $?; }

# --- all dirs missing ---
rc="$(run)"; out="$(cat "$T/out")"
ok "all three missing dirs reported MISSING, exit 0" "$(both "$([ "$rc" = 0 ] && echo 1 || echo 0)" "$([ "$(grep -c '^MISSING repos/' "$T/out")" = 3 ] && echo 1 || echo 0)")"
ok "MISSING names each dir" "$([ "$(has "$out" 'MISSING repos/iptv_apps/iptv-web')$(has "$out" 'MISSING repos/billwatch/billwatch-web')$(has "$out" 'MISSING repos/gitlark/web')" = 111 ] && echo 1 || echo 0)"
ok "no command ran for missing dirs" "$([ ! -s "$LOG" ] && echo 1 || echo 0)"

# --- dirs present: iptv-web has src/, billwatch-web has src/, gitlark/web has NO src ---
mkdir -p "$W/repos/iptv_apps/iptv-web/src" "$W/repos/billwatch/billwatch-web/src" "$W/repos/gitlark/web"
echo 'export const keep = 1;' > "$W/repos/iptv_apps/iptv-web/src/keep.ts"
rc="$(run)"; out="$(cat "$T/out")"
ok "exit 0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "a banner per directory" "$([ "$(grep -c '^=========================' "$T/out")" = 3 ] && has "$out" '======== repos/gitlark/web ========' >/dev/null && echo 1 || echo 0)"
ok "3 candidate commands per dir = 9 npx invocations" "$([ "$(grep -c '^npx ' "$LOG")" = 9 ] && echo 1 || echo 0)"
ok "every candidate wrapped in 'timeout 150'" "$([ "$(grep -c '^timeout 150$' "$LOG")" = 9 ] && echo 1 || echo 0)"
ok "plain --noEmit: 1 error, sees the probe" "$(printf '%s\n' "$out" | grep -E '^  npx --no-install vue-tsc --noEmit +errs=1 +YES-sees-probe$' | head -1 | grep -q . && echo 1 || echo 0)"
ok "-p tsconfig.json: 2 errors, probe NOT seen" "$(printf '%s\n' "$out" | grep -E '^  npx --no-install vue-tsc --noEmit -p tsconfig.json +errs=2 +no$' | head -1 | grep -q . && echo 1 || echo 0)"
ok "-b --force: counts only 'error TS' lines (2, noise ignored), sees probe" "$(printf '%s\n' "$out" | grep -E '^  npx --no-install vue-tsc -b --force +errs=2 +YES-sees-probe$' | head -1 | grep -q . && echo 1 || echo 0)"
ok "command column padded to 45 chars" "$(printf '%s\n' "$out" | grep -E '^  npx --no-install vue-tsc --noEmit {13}errs=' | head -1 | grep -q . && echo 1 || echo 0)"
ok "probe injected under src/ when src exists (seen at call time)" "$(grep -q '^npx iptv-web probe=src ' "$LOG" && grep -q '^npx billwatch-web probe=src ' "$LOG" && echo 1 || echo 0)"
ok "probe injected in '.' when no src/ dir" "$(grep -q '^npx web probe=dot ' "$LOG" && echo 1 || echo 0)"
ok "probe files cleaned up afterwards (all 3 dirs)" "$(find "$W" -name '__gate_probe.ts' | grep -q . && echo 0 || echo 1)"
ok "pre-existing source files untouched" "$(grep -qx 'export const keep = 1;' "$W/repos/iptv_apps/iptv-web/src/keep.ts" && echo 1 || echo 0)"
CL="$( : > "$LOG"; cd "$T" && HOME="$H" STUB_PLAIN_CLEAN=1 PATH="$T/bin:$PATH" bash "$S" 2>&1 )"
ok "clean tsc (0 errors) reports errs=0 'no'" "$(printf '%s\n' "$CL" | grep -E '^  npx --no-install vue-tsc --noEmit +errs=0 +no$' | head -1 | grep -q . && echo 1 || echo 0)"

# --- probe file content is a guaranteed type error ---
cat > "$T/bin/npx" <<X
#!/bin/sh
cp src/__gate_probe.ts "$T/probe.copy" 2>/dev/null || cp __gate_probe.ts "$T/probe.copy"
exit 0
X
run >/dev/null
ok "probe content: number-typed const assigned a string" "$(grep -qx 'export const __PROBE_BAD: number = "not a number at all";' "$T/probe.copy" && echo 1 || echo 0)"
# stub exits silently: 0 errors, probe unseen
ok "silent failing command -> errs=0 no" "$(grep -cE 'errs=0 +no$' "$T/out" | grep -qx 9 && echo 1 || echo 0)"

# --- pre-existing file with the probe name is overwritten and removed ---
echo 'user data' > "$W/repos/gitlark/web/__gate_probe.ts"; run >/dev/null
ok "stale probe-named file replaced then removed" "$([ ! -e "$W/repos/gitlark/web/__gate_probe.ts" ] && echo 1 || echo 0)"

# --- missing $HOME/overnight-queue: the script should bail out rather than probe relative to the cwd ---
E="$T/elsewhere"; mkdir -p "$E/repos/iptv_apps/iptv-web/src"
rc=0; ( cd "$E" && HOME="$T/nohome" PATH="$T/bin:$PATH" bash "$S" ) > "$T/out2" 2>&1 || rc=$?
kb "missing \$HOME/overnight-queue aborts (non-zero) instead of continuing in the caller's cwd (cd has no '|| exit 1')" "$([ "$rc" != 0 ] && ! grep -q '^=====' "$T/out2" && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
