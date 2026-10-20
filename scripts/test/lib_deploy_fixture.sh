# scripts/test/lib_deploy_fixture.sh - SOURCE from test_box_deploy.sh / test_box_autodeploy.sh / test_suite_candidate.sh (package L4). Needs lib_safe_tmp.sh sourced first.
# Builds, under one safe_mktemp_dir: a fake GitHub remote (bare repo, branch claude/feature, layout scripts/overnight-queue/ like the real repo), a work clone to push commits from,
# a fake LIVE queue tree $DF_Q (marker .deploy_test_tree, state/, logs/), a qtmp dir $DF_QT and the read-only deploy clone path $DF_CL (created by box_autodeploy itself).
# L4_OPS_DIR (default: the ops/ dir of the tree under test) is where the scripts under test are copied from, so a mutated copy can be tested instead.
DF_HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DF_ROOT="${OVN_ROOT:-$(cd "$DF_HERE/../.." && pwd)}"
DF_OPS="${L4_OPS_DIR:-$DF_ROOT/ops}"
df_git(){ command git "$@"; }
df_init(){ # [with-git=1]
  DF_T="$(safe_mktemp_dir dfx)" || return 1
  DF_Q="$DF_T/q"; DF_QT="$DF_T/qt"; DF_CL="$DF_T/deploy-clone"; DF_REMOTE="$DF_T/remote.git"; DF_WK="$DF_T/wk"
  mkdir -p "$DF_Q/state" "$DF_Q/logs" "$DF_QT"; : > "$DF_Q/.deploy_test_tree"
  [ "${1:-1}" = 1 ] || return 0
  df_git init -q --bare "$DF_REMOTE" || return 1
  df_git init -q "$DF_WK" || return 1
  df_git -C "$DF_WK" config user.email t@t; df_git -C "$DF_WK" config user.name t
  df_git -C "$DF_WK" checkout -q -b claude/feature
  local o="$DF_WK/scripts/overnight-queue"
  mkdir -p "$o/ops" "$o/scripts/test" "$o/scripts"
  for f in box_deploy.sh box_autodeploy.sh deploy_manifest.py run_suite_sandboxed_cron.sh; do cp -p "$DF_OPS/$f" "$o/ops/$f"; done
  cp -p "$DF_ROOT/scripts/test/lib_safe_tmp.sh" "$DF_ROOT/scripts/test/lint_unsafe_rm.py" "$o/scripts/test/"
  # the suite stub: the verdict of the CANDIDATE's own tree (OVN_FAKE_SUITE_RC, default 0)
  printf '#!/usr/bin/env bash\nd="$(cd "$(dirname "$0")" && pwd)"\necho "fake suite tree=$(cat "$d/../../VERSION" 2>/dev/null) gone=$([ -e "$d/../gone.sh" ] && echo yes || echo no)"\nsleep "${OVN_FAKE_SUITE_SLEEP:-0}"\necho "fake suite end tree=$(cat "$d/../../VERSION" 2>/dev/null)"\nexit "${OVN_FAKE_SUITE_RC:-0}"\n' > "$o/scripts/test/run_all_sandboxed.sh"
  for f in run_overnight.sh queue.sh branch_hygiene.sh scripts/lib_lock.sh; do printf '#!/usr/bin/env bash\necho v1 %s\n' "$f" > "$o/$f"; done
  echo v1 > "$o/VERSION"
  chmod +x "$o"/*.sh "$o"/ops/*.sh "$o"/scripts/*.sh "$o"/scripts/test/run_all_sandboxed.sh
  df_git -C "$DF_WK" remote add origin "$DF_REMOTE"
  df_commit "base" >/dev/null || return 1
  DF_SHA1="$DF_SHA"
}
df_commit(){ # msg [relpath content [exec]]... -> commits + pushes to the fake remote; sets DF_SHA. relpath is under scripts/overnight-queue/. content "-DELETE-" deletes the file.
  local msg="$1"; shift; local o="$DF_WK/scripts/overnight-queue" p c x
  while [ $# -ge 2 ]; do
    p="$1"; c="$2"; shift 2; x=""
    [ "${1:-}" = "exec" ] && { x=1; shift; }
    if [ "$c" = "-DELETE-" ]; then rm -f "$o/$p"; else mkdir -p "$(dirname "$o/$p")"; printf '%s\n' "$c" > "$o/$p"; [ -n "$x" ] && chmod +x "$o/$p"; fi
  done
  df_git -C "$DF_WK" add -A && df_git -C "$DF_WK" commit -q --allow-empty -m "$msg" && df_git -C "$DF_WK" push -q -f origin claude/feature 2>/dev/null || return 1
  DF_SHA="$(df_git -C "$DF_WK" rev-parse HEAD)"
}
df_install(){ # sha: make the live tree equal to that commit and record it as deployed (state/deployed_sha)
  df_git -C "$DF_WK" archive --format=tar "$1:scripts/overnight-queue" | tar -xf - -C "$DF_Q" || return 1
  echo "$1" > "$DF_Q/state/deployed_sha"
}
df_pass(){ printf 'sha=%s\nrc=0\nts=%s\nmode=candidate\nhost=test\n' "$1" "$(date +%s)" > "$DF_Q/state/suite_pass_$1"; }
df_env(){ # exports the hermetic environment of every deploy test
  export OVN_DEPLOY_TEST_HOOKS=1 OVN_QUEUE_DIR="$DF_Q" OVN_QTMP="$DF_QT" OVN_DEPLOY_CLONE="$DF_CL" OVN_DEPLOY_REMOTE="$DF_REMOTE"
  export OVN_DEPLOY_POLL_S=0 OVN_DEPLOY_SMOKE_WAIT=6 OVN_DEPLOY_SMOKE_OBSERVE_S=0 OVN_DEPLOY_CYCLE_PROBE_CMD=true OVN_DEPLOY_WATCH_S=1 OVN_DEPLOY_ROLLBACK_WAIT_S=2 OVN_DEPLOY_BUSY_PATTERN='' OVN_AUTODEPLOY_SUITE_PATTERN=''
  unset OVN_AUTODEPLOY OVN_AUTODEPLOY_BRANCH OVN_AUTODEPLOY_MIN_HOURS OVN_AUTODEPLOY_RUN_SUITE OVN_AUTODEPLOY_ALLOW_BOX_EDITS OVN_AUTODEPLOY_NOW OVN_AUTODEPLOY_SUITE_CMD OVN_DEPLOY_PROCEED_BUSY \
        OVN_DEPLOY_FAIL_COPY_AT OVN_DEPLOY_FAIL_VERIFY OVN_DEPLOY_FAIL_RESTORE OVN_DEPLOY_HOLD_AT OVN_DEPLOY_HOLD_S OVN_AUTODEPLOY_STALE_H OVN_AUTODEPLOY_BUSY_BACKOFF_H OVN_AUTODEPLOY_MAX_WAIT_MIN OVN_DEPLOY_RUNTIME_EXTRA
}
df_snap(){ # content+mode snapshot of the live tree (deployable files only) + any leftover deploy temp file
  python3 -I "$DF_OPS/deploy_manifest.py" manifest "$DF_Q"; find "$DF_Q" -name '*.new.*' | sort
}
df_json(){ # file key -> value (python json path a.b)
  python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split('.'): d=d[k]
print(d if not isinstance(d,bool) else str(d).lower())" "$1" "$2" 2>/dev/null
}
df_cleanup(){ [ -n "${DF_T:-}" ] && safe_rm_rf "$DF_T"; }
