#!/usr/bin/env bash
# Wave-3 extra coverage for ovn_tsc_gate.sh tc_cmd(): the `npm run type-check` fallback and the `tsc --noEmit` fallback
# (stub npm/npx on PATH print a controllable number of "error TS" lines; no real toolchain needed).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../ovn_tsc_gate.sh"; [ -f "$GATE" ] || GATE="$HERE/ovn_tsc_gate.sh"
[ -f "$GATE" ] || { echo "  SKIP: gate not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
for tool in npm npx; do
cat > "$tmp/bin/$tool" <<STUB
#!/usr/bin/env bash
echo "$tool \$*" >> "$tmp/tool.calls"
n=\$(cat "$tmp/errcount" 2>/dev/null || echo 0); i=1
while [ "\$i" -le "\$n" ]; do echo "src/a.ts(\$i,1): error TS2322: fake \$i"; i=\$((i+1)); done
exit 0
STUB
chmod +x "$tmp/bin/$tool"; done
export PATH="$tmp/bin:$PATH"

mkrepo(){ # $1=name  -> repo with web/src/a.ts committed twice (a TS-touching diff)
  local r="$tmp/$1"; mkdir -p "$r/web/src"; echo '{}' > "$r/web/tsconfig.json"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t
    echo "export const a = 1;" > web/src/a.ts; git add -A; git commit -q -m one; echo "export const a = 2;" > web/src/a.ts; git add -A; git commit -q -m two )
  echo "$r"
}
gate(){ bash "$GATE" "$1" "$tmp/bl" "$2" "HEAD~1" HEAD 2>&1; }

echo "== package.json type-check script (no vue-tsc)"
R="$(mkrepo r1)"; echo '{"scripts":{"type-check":"tsc -p ."}}' > "$R/web/package.json"
echo 2 > "$tmp/errcount"; out="$(gate "$R" r1)"
ok "uses npm run type-check and seeds the baseline" "echo '$out' | grep -q 'TSC-RATCHET-SEED r1/./web: baseline=2 (via: npm run --silent type-check)' || echo '$out' | grep -q 'TSC-RATCHET-SEED.*npm run --silent type-check'"
ok "npm was invoked" "grep -q 'npm run --silent type-check' '$tmp/tool.calls'"
echo 4 > "$tmp/errcount"; out="$(gate "$R" r1)"; rc=$?
ok "more errors than baseline -> REGRESSION naming the command" "echo '$out' | grep -q 'TSC-RATCHET-REGRESSION' && echo '$out' | grep -q 'npm run --silent type-check'"

echo "== typescript installed (no vue-tsc, no type-check script)"
R="$(mkrepo r2)"; mkdir -p "$R/web/node_modules/typescript"; echo '{"name":"x"}' > "$R/web/package.json"
echo 1 > "$tmp/errcount"; : > "$tmp/tool.calls"; out="$(gate "$R" r2)"
ok "falls back to npx tsc --noEmit" "echo '$out' | grep -q 'TSC-RATCHET-SEED' && grep -q 'npx --no-install tsc --noEmit' '$tmp/tool.calls'"

echo "== tsc binary present"
R="$(mkrepo r3)"; mkdir -p "$R/web/node_modules/.bin"; printf '#!/bin/sh\nexit 0\n' > "$R/web/node_modules/.bin/tsc"; chmod +x "$R/web/node_modules/.bin/tsc"
echo 0 > "$tmp/errcount"; : > "$tmp/tool.calls"; out="$(gate "$R" r3)"
ok "tsc bin -> npx tsc path, clean seed at 0" "echo '$out' | grep -q 'baseline=0' && grep -q 'tsc --noEmit' '$tmp/tool.calls'"
out="$(gate "$R" r3)"
ok "second run holds -> OK" "echo '$out' | grep -q 'TSC-RATCHET-OK'"

echo "== nothing installed"
R="$(mkrepo r4)"
out="$(gate "$R" r4)"
ok "no type-checker -> SKIP with the dir named" "echo '$out' | grep -q 'no type-checker installed'"

echo "$P passed, $F failed"; [ "$F" -eq 0 ]
