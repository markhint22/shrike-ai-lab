#!/usr/bin/env bash
# lib_bug_escalate.sh - the ONE place a manual-test bug is escalated to a Claude fix session (2026-10-02, branch qa/h8-bug-first).
# Sourced by scripts/ovn_item_guard.sh (the per-cycle cap) AND ovn_stage_runner.sh (the staged runner parks its own items; before this lib it
# stamped '[AUTO-SKIP staged ...]' on a bug after ONE cycle, bypassing the 2-attempt cap and leaving no escalation record - review blocker).
# A bug is never silently AUTO-SKIPped: AUTO-SKIP parks it where nobody looks (how 3 of 7 real Chickadee bugs sat as needs-human). Instead:
#   1. every still-open line of the bug (the item + the sibling steps of its brief, same [feat:] tag) becomes '[CLAUDE] [bug-escalated: <reason>]'
#      (every loop selector already ignores [CLAUDE] lines, so the lane moves on);
#   2. one JSON line goes to <state>/bug_escalations.jsonl (repo, note, item hash, attempts, last failure, brief location);
#   3. ONE low-priority relay note 'Manual bug escalated: <repo>' (buffered by the notification policy, never urgent).
# 2 and 3 happen at most once per item hash.
#
#   ovn_bug_escalate <repo_dir> <progress_file> <lineno> <line_text> <item_hash> <lane_id> <attempts> <last_status> <state_dir> <why> [<push_ref>]
#     <push_ref>   when set, commit+push goes to origin HEAD:<push_ref> with a pull --rebase retry (the runner's worktree-less clone); when empty the
#                  guard's behaviour is kept: push the repo's current branch. OVN_ESC_GIT_IDENTITY=fleet commits as the fleet noreply identity.
# Needs GNU sed (-i), python3, curl (only when NTFY_SERVER + a topic are set). Always returns 0.
ovn_bug_escalate() {
  local repo="$1" prog="$2" lineno="$3" text="$4" h="$5" id="$6" bc="$7" status="$8" state="$9" why="${10}" push_ref="${11:-}"
  local lastst lastwhy bug_feat esc_why lns _n _t branch esc_log repo_name bug_brief _bd _bf _srv _top _msg
  local -a _gid=()
  [ "${OVN_ESC_GIT_IDENTITY:-}" = fleet ] && _gid=(-c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet)
  lastst="$(printf '%s' "$status" | tr -c 'A-Za-z0-9 ()_:.-' '_' | cut -c1-60)"
  lastwhy=""
  [ -f "$state/item_fails/${id}.${h}.lastfail" ] && lastwhy="$(cut -d'|' -f2- "$state/item_fails/${id}.${h}.lastfail" 2>/dev/null | tr '\n\r\t' '   ' | tr -c 'A-Za-z0-9 ()_:.,=/-' '_' | cut -c1-200)"
  # 2026-10-03 (A8/BUG-9): optional OVN_ESC_VERIFY_ERR (first compile/test error line) + OVN_ESC_RUN_ID (stage run id) from the caller: they go into the jsonl row
  # (verify_error, run, flow) and the relay body, so the hand-off names the flow and the real cause instead of only 'staged landed 0 of 2'.
  local _verr _runid
  _verr="$(printf '%s' "${OVN_ESC_VERIFY_ERR:-}" | tr '\n\r\t' '   ' | tr -c 'A-Za-z0-9 ()_:.,=/-' '_' | cut -c1-200)"
  _runid="$(printf '%s' "${OVN_ESC_RUN_ID:-}" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-60)"
  bug_feat="$(printf '%s' "$text" | grep -oE '\[feat:[^]]+\]' | head -1)"
  esc_why="$(printf '%s' "$why, last: ${lastst:-?}" | tr -c 'A-Za-z0-9 ()_:.,=/-' '_')"
  lns=""
  [ -n "$bug_feat" ] && lns="$(grep -nF -- "$bug_feat" "$prog" 2>/dev/null | grep -E '^[0-9]+:- \[ \] ' | grep -viE 'HUMAN-ONLY|AUTO-SKIP|BLOCKED|\[CLAUDE\]' | cut -d: -f1)"
  [ -n "$lns" ] || lns="$lineno"
  for _n in $lns; do
    if [ "$_n" = "$lineno" ]; then _t="[CLAUDE] [bug-escalated: ${esc_why}]"; else _t="[CLAUDE] [bug-escalated: sibling step of this bug escalated]"; fi
    sed -i "${_n}s#^- \[ \] #- [ ] ${_t} #" "$prog"
  done
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if ! git -C "$repo" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
    git -C "$repo" add OVERNIGHT_PROGRESS.md 2>/dev/null
    git -C "$repo" ${_gid[@]+"${_gid[@]}"} commit -q -m "chore(queue): escalate manual-test bug to a Claude session after ${bc} failed fleet attempts" 2>/dev/null
    if [ -n "$push_ref" ]; then
      git -C "$repo" push -q origin "HEAD:${push_ref}" 2>/dev/null || { git -C "$repo" pull -q --rebase origin "$push_ref" 2>/dev/null && git -C "$repo" push -q origin "HEAD:${push_ref}" 2>/dev/null; }
    else
      [ -n "$branch" ] && git -C "$repo" push -q origin "$branch" 2>/dev/null
    fi
  fi
  echo "ESCALATED manual bug after ${why}: ${text:0:70}"
  esc_log="$state/bug_escalations.jsonl"; repo_name="$(basename "$repo")"
  if ! grep -qF "\"item_hash\":\"${h}\"" "$esc_log" 2>/dev/null; then
    bug_brief=""
    _bd="${OVN_BUG_BRIEF_DIR:-$state/bug_briefs}"; _bf="$(printf '%s' "$bug_feat" | sed -E 's/^\[feat://; s/\]$//')"
    [ -n "$_bf" ] && [ -d "$_bd" ] && bug_brief="$(ls -d "$_bd/$_bf"* 2>/dev/null | head -1)"
    ESC_REPO="$repo_name" ESC_ID="$id" ESC_TEXT="$text" ESC_HASH="$h" ESC_FEAT="$bug_feat" ESC_ATT="$bc" ESC_STATUS="$lastst" \
    ESC_WHY="${lastwhy:-$esc_why}${_verr:+ | verify: $_verr}" ESC_VERR="$_verr" ESC_RUN="$_runid" ESC_BRIEF="$bug_brief" ESC_LINE="$lineno" python3 - "$esc_log" <<'PYEOF' 2>/dev/null
import json, os, re, sys, time
e = os.environ
note = re.sub(r"^\s*- \[ \]\s*", "", e.get("ESC_TEXT", ""))
note = re.sub(r"\s+", " ", note).strip()[:300]
rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "event": "escalated", "repo": e.get("ESC_REPO", ""), "lane": e.get("ESC_ID", ""),
       "note": note, "item_hash": e.get("ESC_HASH", ""), "feat": e.get("ESC_FEAT", ""), "attempts": int(e.get("ESC_ATT", "0") or 0),
       "last_status": e.get("ESC_STATUS", ""), "last_failure": e.get("ESC_WHY", ""), "brief": e.get("ESC_BRIEF", ""), "line": e.get("ESC_LINE", "")}
_fl = re.search(r"flow ([^,)]+)", e.get("ESC_TEXT", ""))
if _fl:
    rec["flow"] = _fl.group(1).strip()[:60]
if e.get("ESC_VERR"):
    rec["verify_error"] = e["ESC_VERR"]
if e.get("ESC_RUN"):
    rec["run"] = e["ESC_RUN"]
with open(sys.argv[1], "a", encoding="utf-8") as f:
    f.write(json.dumps(rec, sort_keys=True, separators=(",", ":")) + "\n")
PYEOF
    _srv="${NTFY_SERVER:-}"; _top="${NTFY_TOPIC:-}"
    [ -z "$_top" ] && [ -f "$state/ntfy_topic" ] && _top="$(tr -d '[:space:]' < "$state/ntfy_topic" 2>/dev/null)"
    if [ -n "$_srv" ] && [ -n "$_top" ]; then
      _msg="Fleet gave up after ${bc} attempt(s); a Claude fix session should take it. Flow note: $(printf '%s' "$text" | sed -E 's/^- \[ \] //; s/.*Manual-test bug \(reported by Mark, //; s/ First write a failing test.*//' | cut -c1-110)${_verr:+ | Last error: ${_verr:0:100}}${_runid:+ | run $_runid}"
      curl -fsS --max-time 8 -H "Title: Manual bug escalated: ${repo_name}" -H "Priority: default" -H "Tags: memo" \
        -d "$_msg" "${_srv%/}/${_top}" >/dev/null 2>&1 || true
    fi
  fi
  return 0
}
