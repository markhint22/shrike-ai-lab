#!/usr/bin/env python3
"""Mid-cycle: prefer `vue-tsc --noEmit` directly over the npm type-check script (which can
be broken). Keep tsc as the last fallback."""
p = "scripts/ovn_autotest.sh"
s = open(p).read()
old = (
    '      _tcmd="npx --no-install tsc --noEmit"\n'
    '      [ -x node_modules/.bin/vue-tsc ] && _tcmd="npx --no-install vue-tsc --noEmit"\n'
    '      grep -q \'"type-check"\' package.json 2>/dev/null && _tcmd="npm run --silent type-check"\n'
    '      _tscout="$(timeout 120 $_tcmd 2>&1)"'
)
new = (
    '      if [ -x node_modules/.bin/vue-tsc ]; then _tcmd="npx --no-install vue-tsc --noEmit"\n'
    '      elif grep -q \'"type-check"\' package.json 2>/dev/null; then _tcmd="npm run --silent type-check"\n'
    '      else _tcmd="npx --no-install tsc --noEmit"; fi\n'
    '      _tscout="$(timeout 120 $_tcmd 2>&1)"'
)
assert s.count(old) == 1, f"anchor count={s.count(old)}"
open(p, "w").write(s.replace(old, new, 1))
print("ovn_autotest.sh mid-cycle -> prefer vue-tsc")
