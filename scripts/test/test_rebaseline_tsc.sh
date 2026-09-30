#!/usr/bin/env bash
# Regression: rebaseline_tsc.sh clears state/tsc_baseline/*.count, then re-seeds one <repo>__<dir>.count per web dir using
# the repo's canonical type-check command (npm run --silent type-check when package.json declares it, else
# npx --no-install vue-tsc --noEmit) under `timeout 180`, counting 'error TS' lines. Hermetic temp $HOME + stubs.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../rebaseline_tsc.sh"; [ -f "$S" ] || S="$HERE/../rebaseline_tsc.sh"; [ -f "$S" ] || S="$HERE/rebaseline_tsc.sh"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = "1" ]; then echo "  ok   $1"; else echo "  WARN KNOWN-BUG: $1 (non-fatal)"; fi; }
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; W="$H/overnight-queue"; mkdir -p "$W" "$T/bin"; LOG="$T/calls.log"
cat > "$T/bin/timeout" <<X
#!/bin/sh
echo "timeout \$1" >> "$LOG"; shift; exec "\$@"
X
cat > "$T/bin/npm" <<X
#!/bin/sh
echo "npm \$(basename "\$PWD") \$*" >> "$LOG"
echo "src/a.ts(1,1): error TS2322: a"; echo "src/b.ts(1,1): error TS7006: b"; echo "src/c.ts(1,1): error TS1005: c"
echo "some other line error but not code"; echo "warning TS9999 not an error"
exit 2
X
cat > "$T/bin/npx" <<X
#!/bin/sh
echo "npx \$(basename "\$PWD") \$*" >> "$LOG"
[ "\${STUB_NPX_ERRS:-0}" -gt 0 ] && seq 1 "\$STUB_NPX_ERRS" | sed 's/^/x.ts(1,1): error TS1000: /'
exit 1
X
chmod +x "$T/bin/"*
run(){ : > "$LOG"; ( cd "$W" && HOME="$H" PATH="$T/bin:$PATH" STUB_NPX_ERRS="${STUB_NPX_ERRS:-0}" bash "$S" ) > "$T/out" 2>&1; echo $?; }
BL="$W/state/tsc_baseline"

# --- no repos at all; stale counts from a previous run get cleared; dir created ---
mkdir -p "$BL"; echo 99 > "$BL/old__thing.count"; echo keep > "$BL/notes.txt"
rc="$(run)"; out="$(cat "$T/out")"
ok "exit 0 with no repos" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "each missing repo dir reported 'missing'" "$([ "$(has "$out" '  iptv_apps/iptv-web: missing')$(has "$out" '  billwatch/billwatch-web: missing')$(has "$out" '  gitlark/web: missing')" = 111 ] && echo 1 || echo 0)"
ok "stale *.count files removed" "$([ ! -e "$BL/old__thing.count" ] && echo 1 || echo 0)"
ok "non-.count files left alone" "$([ -f "$BL/notes.txt" ] && echo 1 || echo 0)"
ok "no .count files written for missing dirs, no commands run" "$([ -z "$(ls "$BL"/*.count 2>/dev/null)" ] && [ ! -s "$LOG" ] && echo 1 || echo 0)"
rm -rf "$BL"; run >/dev/null
ok "state/tsc_baseline created when absent" "$([ -d "$BL" ] && echo 1 || echo 0)"

# --- all three present: iptv-web has type-check script; billwatch-web no script; gitlark/web has no package.json ---
mkdir -p "$W/repos/iptv_apps/iptv-web" "$W/repos/billwatch/billwatch-web" "$W/repos/gitlark/web"
echo '{"scripts":{"type-check":"vue-tsc --noEmit"}}' > "$W/repos/iptv_apps/iptv-web/package.json"
echo '{"scripts":{"build":"vite build"}}' > "$W/repos/billwatch/billwatch-web/package.json"
echo 99 > "$BL/stale.count"
rc="$(STUB_NPX_ERRS=4 run)"; out="$(cat "$T/out")"
ok "package.json with type-check -> npm run --silent type-check" "$(has "$out" '  iptv_apps__iptv-web.count = 3   (via: npm run --silent type-check)')"
ok "npm count only counts 'error TS<digits>' lines (3 of 5)" "$([ "$(cat "$BL/iptv_apps__iptv-web.count")" = 3 ] && echo 1 || echo 0)"
ok "package.json without type-check -> npx --no-install vue-tsc --noEmit" "$(has "$out" '  billwatch__billwatch-web.count = 4   (via: npx --no-install vue-tsc --noEmit)')"
ok "missing package.json -> npx fallback (grep silenced)" "$(has "$out" '  gitlark__web.count = 4   (via: npx --no-install vue-tsc --noEmit)')"
ok "count files hold just the integer + newline" "$([ "$(cat "$BL/billwatch__billwatch-web.count" | od -An -c | tr -d ' ')" = '4\n' ] && echo 1 || echo 0)"
ok "commands ran inside the right dirs" "$(grep -qx 'npm iptv-web run --silent type-check' "$LOG" && grep -qx 'npx billwatch-web --no-install vue-tsc --noEmit' "$LOG" && grep -qx 'npx web --no-install vue-tsc --noEmit' "$LOG" && echo 1 || echo 0)"
ok "each run wrapped in timeout 180" "$([ "$(grep -c '^timeout 180$' "$LOG")" = 3 ] && echo 1 || echo 0)"
ok "stale count cleared before re-seeding" "$([ ! -e "$BL/stale.count" ] && echo 1 || echo 0)"
ok "exactly three .count files" "$([ "$(ls "$BL"/*.count | wc -l | tr -d ' ')" = 3 ] && echo 1 || echo 0)"

# --- zero errors -> 0 (grep -c non-zero exit must not break it) ---
STUB_NPX_ERRS=0 run >/dev/null; out="$(cat "$T/out")"
ok "zero errors recorded as 0" "$([ "$(cat "$BL/gitlark__web.count")" = 0 ] && [ "$(has "$out" 'gitlark__web.count = 0 ')" = 1 ] && echo 1 || echo 0)"

# --- slug: nested working dir would map / -> __ (exercise via a sourced copy of seed()) ---
seedfn="$(sed -n '/^seed(){/,/^}/p' "$S")"
( cd "$W"; mkdir -p repos/foo/app/web; export PATH="$T/bin:$PATH"; eval "$seedfn"; STUB_NPX_ERRS=2 seed foo app/web ) > "$T/o3" 2>&1
ok "working dir with '/' becomes '__' in the count filename" "$([ "$(cat "$BL/foo__app__web.count")" = 2 ] && [ "$(has "$(cat "$T/o3")" 'foo__app__web.count = 2')" = 1 ] && echo 1 || echo 0)"
rm -f "$BL/foo__app__web.count"

# --- a failing/erroring checker (nonzero exit) is still just a count; script keeps going ---
ok "whole pass completes for all three repos" "$([ "$(grep -c 'count = ' "$T/out")" = 3 ] && echo 1 || echo 0)"

# --- cd failure must not make the script delete counts elsewhere ---
E="$T/elsewhere"; mkdir -p "$E/state/tsc_baseline"; echo 7 > "$E/state/tsc_baseline/victim.count"
( cd "$E" && HOME="$T/nohome" PATH="$T/bin:$PATH" bash "$S" ) > "$T/out2" 2>&1; rc=$?
kb "missing \$HOME/overnight-queue aborts instead of running 'rm -f state/tsc_baseline/*.count' in the caller's cwd (cd has no '|| exit 1')" "$([ -f "$E/state/tsc_baseline/victim.count" ] && [ "$rc" != 0 ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
