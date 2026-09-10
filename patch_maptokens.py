#!/usr/bin/env python3
"""Give every repo a real repo-map budget (was unset for 5/7 repos -> aider's tiny default),
so the model gets cross-file signatures for multi-file work. Fleet default via OVN_MAP_TOKENS."""
p = "run_overnight.sh"
s = open(p).read()
if "Fleet map-token default" in s:
    print("already patched"); raise SystemExit
old = ('    if [ -n "$map_tokens" ] && [ "$map_tokens" != "null" ]; then\n'
       '      AIDER_BASE_ARGS+=(--map-tokens "$map_tokens")\n'
       '    fi\n')
new = ('    # Fleet map-token default (2026-09-04): a real repo-map budget gives the model\n'
       '    # cross-file signatures so multi-file work can pick the right files (research: repo-map\n'
       '    # localization beats context-stuffing). Was unset for 5/7 repos -> tiny scaled default.\n'
       '    if [ -z "$map_tokens" ] || [ "$map_tokens" = "null" ]; then map_tokens="${OVN_MAP_TOKENS:-3072}"; fi\n'
       '    AIDER_BASE_ARGS+=(--map-tokens "$map_tokens")\n')
assert s.count(old) == 1, f"anchor count={s.count(old)}"
open(p, "w").write(s.replace(old, new, 1))
print("patched map-tokens fleet default (3072)")
