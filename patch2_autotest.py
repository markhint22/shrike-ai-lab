#!/usr/bin/env python3
"""Patch ovn_autotest.sh mid-cycle type-check to use the repo's CANONICAL command
(npm run type-check -> vue-tsc --noEmit -> tsc --noEmit), not raw tsc."""
p = "scripts/ovn_autotest.sh"
s = open(p).read()
old = (
    '    if [ -n "$_chset" ] && { [ -x node_modules/.bin/tsc ] || [ -d node_modules/typescript ]; }; then\n'
    '      _tscout="$(timeout 90 npx --no-install tsc --noEmit 2>&1)"'
)
new = (
    '    if [ -n "$_chset" ] && { [ -x node_modules/.bin/vue-tsc ] || [ -x node_modules/.bin/tsc ] || [ -d node_modules/typescript ]; }; then\n'
    '      _tcmd="npx --no-install tsc --noEmit"\n'
    '      [ -x node_modules/.bin/vue-tsc ] && _tcmd="npx --no-install vue-tsc --noEmit"\n'
    '      grep -q \'"type-check"\' package.json 2>/dev/null && _tcmd="npm run --silent type-check"\n'
    '      _tscout="$(timeout 120 $_tcmd 2>&1)"'
)
assert s.count(old) == 1, f"anchor count={s.count(old)}"
open(p, "w").write(s.replace(old, new, 1))
print("ovn_autotest.sh mid-cycle -> canonical type-check command")
