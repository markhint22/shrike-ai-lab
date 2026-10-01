#!/usr/bin/env bash
# branch_hygiene.sh launches the QA shadow runner after a successful merge - detached, guarded, and unable to affect the merge.
Q="$(cd "$(dirname "$0")/../.." && pwd)"
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
H="$Q/branch_hygiene.sh"
ok "hook exists right after the MERGED log line" "$(grep -A12 'MERGED \$name \$FEAT' "$H" | grep -q 'qa_run_shadow.sh' && echo 1 || echo 0)"
ok "hook is guarded by OVN_QA_SHADOW != off and by the runner file existing" "$(grep -B3 'qa_run_shadow.sh" "\$name"' "$H" | grep -q 'OVN_QA_SHADOW' && grep -q '\-f "\$SCRIPT_DIR/qa/qa_run_shadow.sh"' "$H" && echo 1 || echo 0)"
ok "hook is detached (nohup, & , stdin/stdout/stderr closed) and ends in || true" "$(grep 'nohup bash "\$SCRIPT_DIR/qa/qa_run_shadow.sh"' "$H" | grep -q '< /dev/null &' && grep 'nohup bash "\$SCRIPT_DIR/qa/qa_run_shadow.sh"' "$H" | grep -q '|| true' && echo 1 || echo 0)"
ok "hook uses the merge commit and its first parent as head/base" "$(grep -q "rev-parse 'HEAD^1'" "$H" && grep -q '_qa_head=.*rev-parse HEAD' "$H" && echo 1 || echo 0)"
ok "branch_hygiene.sh still parses" "$(bash -n "$H" && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
