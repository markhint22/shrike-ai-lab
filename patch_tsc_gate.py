#!/usr/bin/env python3
"""One-shot patcher: wire the TS-ratchet into run_overnight.sh + ovn_autotest.sh.
Idempotent-ish: refuses to double-insert. Run on the server in ~/overnight-queue."""
import sys

# ---- 1. run_overnight.sh: post-commit ratchet revert, right after VERIFY_RESULT ----
p = "run_overnight.sh"
s = open(p).read()
if "TS-RATCHET" in s:
    print("run_overnight.sh already patched — skipping")
else:
    anchor = '      VERIFY_RESULT="$(run_repo_verification)"\n'
    assert s.count(anchor) == 1, f"run_overnight anchor count={s.count(anchor)}"
    block = anchor + (
        '\n'
        '      # TS-RATCHET (2026-09-04): type-check web on TS-touching commits and REVERT if this\n'
        '      # commit raised the tsc error count above the repo baseline (ratchet: only holds or\n'
        '      # improves). Real type feedback WITHOUT reverting the pre-existing type-error backlog\n'
        '      # (iptv-web ~69, billwatch-web ~71). Baselines: state/tsc_baseline/. Toggle OVN_TSC_GATE=0.\n'
        '      if [ "${OVN_TSC_GATE:-1}" = 1 ] && [ -f "$SCRIPT_DIR/scripts/ovn_tsc_gate.sh" ]; then\n'
        '        TSC_OUT="$(bash "$SCRIPT_DIR/scripts/ovn_tsc_gate.sh" "$(pwd)" "$SCRIPT_DIR/state/tsc_baseline" "$repo" "$BEFORE_SHA" "$AFTER_SHA" 2>&1)"\n'
        '        [ -n "$TSC_OUT" ] && echo "$TSC_OUT" >> "$task_log"\n'
        '        if echo "$TSC_OUT" | grep -q "TSC-RATCHET-REGRESSION"; then\n'
        '          echo "--- TS-RATCHET: commit raised type errors above baseline — reverting to ${BEFORE_SHA} ---" >> "$task_log"\n'
        '          git reset --hard "$BEFORE_SHA" --quiet\n'
        '          git clean -fd --quiet 2>/dev/null\n'
        '          emit_alert warn "$id" "ts-ratchet reverted a commit that introduced net-new TypeScript errors"\n'
        '          echo "reverted(ts-regression)"\n'
        '          return\n'
        '        fi\n'
        '      fi\n'
    )
    s = s.replace(anchor, block, 1)
    open(p, "w").write(s)
    print("run_overnight.sh patched")

# ---- 2. ovn_autotest.sh: mid-cycle scoped tsc so the model self-corrects on its own files ----
p2 = "scripts/ovn_autotest.sh"
s2 = open(p2).read()
if "OVN_TSC_MIDCYCLE" in s2:
    print("ovn_autotest.sh already patched — skipping")
else:
    anchor2 = 'if [ -n "$web_dir" ]; then\n  cd "$web_dir"\n'
    assert s2.count(anchor2) == 1, f"autotest anchor count={s2.count(anchor2)}"
    midblock = anchor2 + (
        '  # scoped type-check (2026-09-04): surface type errors in the files THIS edit touched so\n'
        '  # the model self-corrects mid-cycle. Only the model\'s OWN changed files fail the check;\n'
        '  # pre-existing errors elsewhere are ignored. Toggle OVN_TSC_MIDCYCLE=0.\n'
        '  if [ "${OVN_TSC_MIDCYCLE:-1}" = 1 ]; then\n'
        '    _chset="$(printf "%s\\n%s\\n" "$specs" "$srcs" | tr " " "\\n" | sed "/^$/d")"\n'
        '    if [ -n "$_chset" ] && { [ -x node_modules/.bin/tsc ] || [ -d node_modules/typescript ]; }; then\n'
        '      _tscout="$(timeout 90 npx --no-install tsc --noEmit 2>&1)"\n'
        '      _own="$(printf "%s\\n" "$_tscout" | grep -E "error TS[0-9]" | grep -Ff <(printf "%s\\n" "$_chset") || true)"\n'
        '      if [ -n "$_own" ]; then\n'
        '        echo "TYPE ERRORS in files you just edited — fix these before finishing:"\n'
        '        printf "%s\\n" "$_own" | head -20\n'
        '        exit 1\n'
        '      fi\n'
        '    fi\n'
        '  fi\n'
    )
    s2 = s2.replace(anchor2, midblock, 1)
    open(p2, "w").write(s2)
    print("ovn_autotest.sh patched")

print("DONE")
