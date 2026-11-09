#!/usr/bin/env bash
# scripts/lib_helper_timeout.sh - SOURCE this. Wall-clock cap for every helper the run loop shells out to (2026-11-08, hotfix-scout-hang).
# Incident: ovn_scout_ground.py spun at 100% CPU for 4h52m with no `timeout` around it; the single run loop (and so the whole fleet) waited on it.
#
#   ovn_hto      SECS LABEL cmd args...   run cmd under `timeout -k 5 SECS`; the command's own rc is returned, 124 on a timeout (callers' `|| fallback` paths fire).
#   ovn_hto_open SECS LABEL cmd args...   same, but a TIMEOUT returns 0 with whatever stdout the helper had flushed (fail-OPEN: gates whose non-zero rc means "revert"
#                                         must read a hung checker as "no verdict", never as a failed commit).
#
# On a timeout one line is appended to $OVN_HTO_CYCLE_LOG / $task_log / $TASK_LOG (the TEXT cycle log) and to $OVN_HTO_LOG (default <state>/helper_timeouts.log), so a
# hang is visible instead of silent. $SLOG is NOT a text log in the stage runner (it is the JSONL journal that jq -s reads): a target ending in .jsonl only ever gets a
# valid one-line JSON object, never plain text. Recovery helpers for callers whose wrapped helper mutates the tree: ovn_hto_restore_file, ovn_hto_git_recover. OVN_HTO=off runs the helper directly (kill switch); no timeout/gtimeout binary => runs directly (the run loop is Linux on the box).
# stdin/stdout pass through unchanged, so it works at either end of a pipeline and inside $( ).
_ovn_hto_bin(){ type -P timeout 2>/dev/null || type -P gtimeout 2>/dev/null; }
_ovn_hto_note(){  # $1 label $2 secs $3 rc
  local msg ts log cyc
  ts="$(date '+%F %T' 2>/dev/null)"
  msg="--- helper-timeout: $1 exceeded ${2}s (rc=$3); killed, proceeding without it (fail-open) ---"
  cyc="${OVN_HTO_CYCLE_LOG:-${task_log:-${TASK_LOG:-}}}"
  [ -z "$cyc" ] && case "${SLOG:-}" in *.jsonl) cyc="$SLOG";; esac   # journal-only fallback: written as JSON below, never as text
  if [ -n "$cyc" ] && [ -w "$(dirname "$cyc")" ]; then
    case "$cyc" in
      *.jsonl) printf '{"event":"helper_timeout","label":"%s","secs":%s,"rc":%s}\n' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_')" "${2:-0}" "${3:-0}" >> "$cyc" 2>/dev/null;;
      *) printf '%s\n' "$msg" >> "$cyc" 2>/dev/null;;
    esac
  fi
  log="${OVN_HTO_LOG:-${STATE_DIR:-${OVN_STATE_DIR:-}}/helper_timeouts.log}"
  case "$log" in /helper_timeouts.log) return 0;; esac
  [ -d "$(dirname "$log")" ] && printf '%s %s\n' "$ts" "$msg" >> "$log" 2>/dev/null
  return 0
}
_ovn_hto_run(){  # $1 open(1)/closed(0) $2 secs $3 label, rest = cmd
  local open="$1" secs="$2" label="$3" tb rc t0; shift 3
  tb="$(_ovn_hto_bin)"
  if [ "${OVN_HTO:-on}" = off ] || [ -z "$tb" ]; then "$@"; return $?; fi
  case "$secs" in ''|*[!0-9]*) secs=60;; esac
  case "${OVN_HTO_MAX:-}" in ''|*[!0-9]*) ;; *) [ "$secs" -gt "$OVN_HTO_MAX" ] && secs="$OVN_HTO_MAX";; esac   # OVN_HTO_MAX: lower every cap (tests / an emergency lever)
  t0=$SECONDS
  "$tb" -k 5 "$secs" "$@"; rc=$?
  # 124 = timeout fired. 137 = KILL after the -k grace (timeout fired) OR the helper's own OOM-kill: only the first counts, so require the cap to have elapsed.
  if [ "$rc" -eq 124 ] || { [ "$rc" -eq 137 ] && [ $((SECONDS - t0)) -ge "$secs" ]; }; then
    _ovn_hto_note "$label" "$secs" "$rc"
    [ "$open" = 1 ] && return 0
    return 124
  fi
  return "$rc"
}
ovn_hto(){ _ovn_hto_run 0 "$@"; }
ovn_hto_open(){ _ovn_hto_run 1 "$@"; }

# Recovery after a TIMED-OUT helper that mutates the tree (callers: `ovn_hto ...; [ $? -eq 124 ] && ovn_hto_...`).
ovn_hto_restore_file(){  # FILE: drop uncommitted edits a killed helper left in a tracked file (they are re-derived next cycle; the caller skipped its commit)
  git checkout -q -- "$1" 2>/dev/null; return 0
}
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------
# Recovery after a TIMED-OUT helper that mutates a stage worktree. FINAL SEMANTICS (r3 review, 2026-11-08): recovery NEVER modifies or deletes a tracked, staged or
# pre-existing file. No reset / checkout / clean / stash, no mtime gate on files. It does exactly two things:
#   1. removes .git/index.lock (linked worktrees: `git rev-parse --git-path index.lock`), only if it is STRICTLY NEWER than a sub-second SENTINEL file made right before
#      the call (an older lock, even by 1 ms, is not ours and is kept);
#   2. deletes untracked files under the pathspec that did NOT exist in a snapshot taken before the call and are still untracked (e.g. a new alembic revision the killed
#      call wrote before `git add`). Whole-second clocks, re-saved files and old-mtime debris cannot confuse this: it compares names against the snapshot, not times.
# Debris of a killed call that is STAGED-new or a MODIFIED-tracked file is deliberately LEFT: the verify/commit logic and the item's own failure path deal with it.
# Rationale: destroying the uncommitted landing candidate is worse than leaving some debris. Both helpers refuse (return 0, change nothing, log a line) unless the
# worktree is an existing dir that looks like /tmp/stage-* and is not under */overnight-queue/repos/.
# Use (call sites in ovn_stage_runner.sh):
#   snap="$(ovn_hto_snapshot_untracked "$wt" PATHSPEC...)"; sent="$(ovn_hto_sentinel)"      # immediately before the call (snapshot first, sentinel last)
#   ovn_hto N label cmd...; [ $? -eq 124 ] && ovn_hto_git_recover "$wt" "$snap" "$sent"
#   ovn_hto_recover_done "$snap" "$sent"                                                    # remove the temp files
# ovn_hto_git_recover WT SNAPSHOT_OR_EMPTY SENTINEL: an empty/missing snapshot means locks only; a missing sentinel means NOTHING is removed (cannot prove the lock is ours).
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------
_ovn_hto_refuse(){  # $1 helper $2 wt $3 reason: log one line, never fail
  local msg="--- helper-recover: $1 refused for '$2' ($3); nothing changed ---" cyc log
  cyc="${OVN_HTO_CYCLE_LOG:-${task_log:-${TASK_LOG:-}}}"
  case "$cyc" in ''|*.jsonl) ;; *) [ -w "$(dirname "$cyc")" ] && printf '%s\n' "$msg" >> "$cyc" 2>/dev/null;; esac
  log="${OVN_HTO_LOG:-${STATE_DIR:-${OVN_STATE_DIR:-}}/helper_timeouts.log}"
  case "$log" in /helper_timeouts.log) return 0;; esac
  [ -d "$(dirname "$log")" ] && printf '%s %s\n' "$(date '+%F %T' 2>/dev/null)" "$msg" >> "$log" 2>/dev/null
  return 0
}
_ovn_hto_wt_ok(){  # $1 helper $2 wt: rc 0 only for an existing /tmp/stage-* dir that is not a fleet repo clone
  local who="$1" wt="$2" real
  [ -n "$wt" ] || { _ovn_hto_refuse "$who" "$wt" "empty worktree"; return 1; }
  [ -d "$wt" ] || { _ovn_hto_refuse "$who" "$wt" "not a directory"; return 1; }
  real="$(cd "$wt" 2>/dev/null && pwd -P)"
  [ -n "$real" ] || { _ovn_hto_refuse "$who" "$wt" "cannot resolve"; return 1; }
  case "$wt" in */overnight-queue/repos/*|*/overnight-queue/repos) _ovn_hto_refuse "$who" "$wt" "under overnight-queue/repos"; return 1;; esac
  case "$real" in */overnight-queue/repos/*|*/overnight-queue/repos) _ovn_hto_refuse "$who" "$wt" "resolves under overnight-queue/repos"; return 1;; esac
  case "$real" in /tmp/stage-*|/private/tmp/stage-*) return 0;; esac
  _ovn_hto_refuse "$who" "$wt" "not a /tmp/stage-* worktree"; return 1
}
_ovn_hto_mt(){  # $1 file -> "SEC FRAC9" (ns where the platform has it), rc 1 when unreadable
  local v i f
  for v in "$(stat -c %.9Y "$1" 2>/dev/null)" "$(stat -f %Fm "$1" 2>/dev/null)"; do
    case "$v" in
      [0-9]*.[0-9]*) i="${v%%.*}"; f="${v#*.}"; case "$i$f" in *[!0-9]*) continue;; esac
        f="${f}000000000"; echo "$i ${f:0:9}"; return 0;;
    esac
  done
  v="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)"
  case "$v" in ''|*[!0-9]*) return 1;; esac
  echo "$v 000000000"
}
_ovn_hto_newer(){  # rc 0 only when file $1 is STRICTLY newer than file $2 (equal = not newer = kept)
  local a b ai af bi bf
  a="$(_ovn_hto_mt "$1")" && b="$(_ovn_hto_mt "$2")" || { [ "$1" -nt "$2" ]; return $?; }
  ai="${a% *}"; af="${a#* }"; bi="${b% *}"; bf="${b#* }"
  [ "$ai" -gt "$bi" ] && return 0
  [ "$ai" -lt "$bi" ] && return 1
  [ "$((10#$af))" -gt "$((10#$bf))" ]
}
ovn_hto_sentinel(){  # prints the path of a fresh sentinel file (private mktemp dir); empty on failure
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/ovn_hto_s.XXXXXX" 2>/dev/null)" || return 0; [ -n "$d" ] && [ -d "$d" ] || return 0
  touch "$d/sentinel" 2>/dev/null && echo "$d/sentinel"
  return 0
}
ovn_hto_snapshot_untracked(){  # WT PATHSPEC... -> prints the snapshot file path (NUL-separated untracked files under PATHSPEC); empty when refused
  local wt="$1" d; shift
  [ "$#" -gt 0 ] || return 0
  _ovn_hto_wt_ok ovn_hto_snapshot_untracked "$wt" || return 0
  d="$(mktemp -d "${TMPDIR:-/tmp}/ovn_hto_u.XXXXXX" 2>/dev/null)" || return 0; [ -n "$d" ] && [ -d "$d" ] || return 0
  printf '%s\0' "$@" > "$d/pathspec"
  if git -C "$wt" ls-files -o --exclude-standard -z -- "$@" > "$d/untracked" 2>/dev/null; then echo "$d/untracked"; else rm -f "$d/untracked" "$d/pathspec"; rmdir "$d" 2>/dev/null; fi
  return 0
}
ovn_hto_recover_done(){  # SNAPSHOT SENTINEL: remove the temp files the two helpers made (files only; never anything else)
  local f
  for f in "$@"; do
    case "$(basename "$(dirname "$f" 2>/dev/null)" 2>/dev/null)" in ovn_hto_s.*|ovn_hto_u.*) ;; *) continue;; esac
    rm -f "$f" "$(dirname "$f")/pathspec" 2>/dev/null; rmdir "$(dirname "$f")" 2>/dev/null
  done
  return 0
}
ovn_hto_git_recover(){  # WT SNAPSHOT_OR_EMPTY SENTINEL
  local wt="${1:-}" snap="${2:-}" sent="${3:-}" lk f g seen ps=() cur
  _ovn_hto_wt_ok ovn_hto_git_recover "$wt" || return 0
  if [ -n "$sent" ] && [ -f "$sent" ]; then
    lk="$(git -C "$wt" rev-parse --git-path index.lock 2>/dev/null)"; case "$lk" in '') ;; /*) ;; *) lk="$wt/$lk";; esac
    [ -n "$lk" ] && [ -e "$lk" ] && _ovn_hto_newer "$lk" "$sent" && rm -f "$lk"
  fi
  [ -n "$snap" ] && [ -f "$snap" ] && [ -f "$(dirname "$snap")/pathspec" ] || return 0
  while IFS= read -r -d '' f; do ps+=("$f"); done < "$(dirname "$snap")/pathspec"
  [ "${#ps[@]}" -gt 0 ] || return 0
  while IFS= read -r -d '' f; do   # untracked NOW; delete only names that were not in the pre-call snapshot
    seen=0
    while IFS= read -r -d '' g; do [ "$g" = "$f" ] && { seen=1; break; }; done < "$snap"
    [ "$seen" = 0 ] || continue
    git -C "$wt" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 && continue   # tracked/staged: never touched
    case "$f" in ''|/*|..|../*|*/../*) continue;; esac
    { [ -f "$wt/$f" ] || [ -L "$wt/$f" ]; } && rm -f -- "$wt/$f"
  done < <(git -C "$wt" ls-files -o --exclude-standard -z -- "${ps[@]}" 2>/dev/null)
  return 0
}
