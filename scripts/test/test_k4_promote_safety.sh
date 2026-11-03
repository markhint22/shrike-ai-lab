#!/usr/bin/env bash
# K4 promote safety: hermetic run + MUTATION PROOF (each rule broken in a temp copy of qa/ must make the scenarios fail).
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
PY="$(command -v python3.12 || command -v python3)"
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1
T="$(safe_mktemp_dir k4)" || exit 1
export K4_TMP="$T"
QA="$(cd "$HERE/../../qa" && pwd)"
rc=0
"$PY" "$HERE/test_k4_promote_safety.py" || rc=1
# mutation proof: file|old|new
mut(){  # $1=label $2=file $3=old $4=new
  local d="$T/mut_$1"; mkdir -p "$d"; cp "$QA"/*.py "$QA"/*.conf "$d"/ 2>/dev/null
  "$PY" - "$d/$2" "$3" "$4" <<'PYEOF' || { echo "  FAIL mutant $1: pattern not found"; rc=1; return; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  if "$PY" "$HERE/test_k4_promote_safety.py" --qa "$d" >/dev/null 2>&1; then echo "  FAIL mutant $1 SURVIVED (tests did not notice)"; rc=1; else echo "  ok mutant $1 killed"; fi
}
mut vercel_error_ignored vercel_prod_state.py 'BAD = {"ERROR"}' 'BAD = {"NEVER"}'
mut health_commit_ignored promote_postcheck.py 'if not match(commit, sha):' 'if False:'
mut alembic_match_wrong prod_alembic_check.py 'return "MATCH", head' 'return "BEHIND", head'
mut migration_regex promote_gate.py 'VERSIONS_RE = re.compile(r"(^|/)(alembic|migrations)/versions/' 'VERSIONS_RE = re.compile(r"(^|/)(alembic|migrations)/nope/'
mut staging_note_every_run promote_gate.py '    if os.path.exists(mk):
        return False, ""' '    if False:
        return False, ""'
mut url_block_always promote_gate.py 'return bool(required and not present and repo in repos)' 'return bool(not present and repo in repos)'
mut no_skip_reason prod_alembic_snapshot.py 'health-has-no-revision (no /health' 'no revision (no /health'
mut vercel_not_deduped promote_postcheck.py 'if os.path.exists(mk):
        log(repo, sha, "VERCEL_SKIP"' 'if False:
        log(repo, sha, "VERCEL_SKIP"'
mut vercel_since_stage_start promote_postcheck.py '(PROCESS_START if PROCESS_START is not None else t0) - SKEW_S' 't0 - SKEW_S'
mut vercel_stage_dropped promote_postcheck.py '("vercel", lambda: vercel_stage(repo, sha, once=once))' '("noop", lambda: "x")'
safe_rm_rf "$T"
echo "test_k4_promote_safety.sh rc=$rc"
exit $rc
