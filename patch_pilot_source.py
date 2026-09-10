#!/usr/bin/env python3
"""Source an optional pilot-flags file (OVN_ARCHITECT / OVN_BESTOF_N / OVN_EDIT_FORMAT) right
after SCRIPT_DIR is defined, so pilots can be toggled without restarting anything."""
p = "run_overnight.sh"
s = open(p).read()
if "pilot_flags.env" in s:
    print("already sources pilot flags"); raise SystemExit
a = 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'
assert s.count(a) == 1, "SCRIPT_DIR anchor not unique"
add = a + ('# optional pilot flags (OVN_ARCHITECT / OVN_BESTOF_N / OVN_EDIT_FORMAT) — toggle without restarts\n'
           '[ -f "$SCRIPT_DIR/state/pilot_flags.env" ] && . "$SCRIPT_DIR/state/pilot_flags.env" || true\n')
open(p, "w").write(s.replace(a, add, 1))
print("added pilot-flags sourcing")
