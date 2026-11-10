#!/usr/bin/env bash
# scripts/lib_landing_gates.sh - package Z3 (2026-11-07) shell glue for scripts/ovn_landing_gates.py. Source-only. Every function is fail-open: a missing python/git/module, a
# crash or a timeout answers "no finding" and the caller keeps the OLD behaviour. Nothing here changes a decision unless the gate's own flag is `enforce`.
#
# Per-gate flags (off | shadow | enforce; default SHADOW = journal to $STATE/landing_gates_shadow.log, change nothing):
#   OVN_Z3_STEP_DIFF      B1  step-diff-mismatch   quoted tokens of the step text must appear in the step diff
#   OVN_Z3_TONE           B2  tone-lint            Hey/Yo/Buzz/... newly added to a file (OVN_Z3_TONE_TOKENS="Hey|Yo|..." overrides the list)
#   OVN_Z3_REPAIR_ROUTE   B3  repair-new-route     a repair-to-pass-verification round may not add a route/endpoint
#   OVN_Z3_TEST_SRC       B4  test-item-src-edit   a test-creation item may not touch non-test source
#   OVN_Z3_CALL_DROP      B5  call-dropped         FLAG ONLY: `enforce` is accepted but behaves as shadow (a heuristic, never a veto)
#   (Z7, 2026-11-09: B7 also reports polarity-flip / status-flip-src / literal-swap / assertion-deleted / orphan-assert-deleted, each with src_changed + tier strong|weak; OVN_Z7_ASSERT_RECALL=off drops them)
#   OVN_Z3_ASSERT_WEAKEN  B7  assert-weaken       FLAG ONLY (Z5): a test diff removed a negative assert / flipped 4xx->2xx / compare->`is not None` / duplicated a positive assert / deleted parametrize cases; `enforce` behaves as shadow
#   OVN_Z3_LANDING_CAP    B6  landing-cap          item landed >= OVN_Z3_LANDING_CAP_N (3) times in OVN_Z3_LANDING_CAP_H (24) h, keyed on the item LINE hash -> park (AUTO-SKIP)
#   OVN_Z3_EDITOR_LEAK    B0  editor-example-leak  aider's built-in "Change the greeting to be more casual" example replayed by the editor (root cause of Hey/Yo/Buzz copy)
#   OVN_STAGE_EDITOR_FORMAT   (not a gate) when set (e.g. editor-diff) the staged runner passes --editor-edit-format <v> to aider; empty = aider's default editor-whole
#
# z3_step_gate <wt> <kind: step|repair> <desc> <item> <files> <atmp-log-or-empty> <state-dir> <label>
#   Looks at the UNCOMMITTED change in <wt> (git diff HEAD incl. new files). Sets Z3_REFUSE (empty or "<rule>: <msg>") for the first ENFORCED gate that fired; returns 1 then, else 0.
#   Shadow findings are appended to <state-dir>/landing_gates_shadow.log (one JSON object per line) and never refuse.
type ovn_gitb >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/lib_push_bound.sh" 2>/dev/null || ovn_gitb(){ git "$@"; }   # Z7-B: bounded, non-interactive git for the park push/fetch below

type ovn_hto >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/lib_helper_timeout.sh" 2>/dev/null || { ovn_hto(){ shift 2; "$@"; }; ovn_hto_open(){ shift 2; "$@"; }; }   # helper wall-clock cap (hotfix-scout-hang)
_z3_py() { local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; printf '%s/ovn_landing_gates.py' "$d"; }

_z3_mode() {  # _z3_mode <rule-flag-name> -> off|shadow|enforce (invalid => shadow)
  local v; eval "v=\${$1:-shadow}"
  case "$v" in off|shadow|enforce) printf '%s' "$v";; *) printf 'shadow';; esac
}

# z3_leak_gate <attempt-log> <state-dir> <label> <kind>   B0 on one attempt log. Journals (shadow/enforce) and, when OVN_Z3_EDITOR_LEAK=enforce, sets Z3_REFUSE and returns 1.
# Called by z3_step_gate for a post-edit step AND by the stage runner for every NON-successful attempt (no-edit / empty-file / reverted ... ending on a non-actionable architect
# message), so the replay rate is measured on all attempts, not only the ones that produced an edit.
z3_leak_gate() {
  local alog="${1:-}" sd="${2:-${STATE_DIR:-state}}" label="${3:-?}" kind="${4:-step}" mode py out to=""
  [ -f "$alog" ] || return 0
  mode="$(_z3_mode OVN_Z3_EDITOR_LEAK)"; [ "$mode" = off ] && return 0
  py="$(_z3_py)"; [ -f "$py" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  command -v timeout >/dev/null 2>&1 && to="timeout 60"
  out="$($to python3 "$py" leak-check --log "$alog" 2>/dev/null)"
  case "$out" in *editor-example-leak*)
    mkdir -p "$sd" 2>/dev/null; _z3_rotate "$sd/landing_gates_shadow.log"
    printf '%s' "$out" | python3 -c '
import json,sys,time
mode,label,kind=sys.argv[1:4]
for f in json.load(sys.stdin).get("findings",[]):
    f=dict(f); f.update(ts=time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),mode=mode,label=label,kind=kind); print(json.dumps(f))
' "$mode" "$label" "$kind" >> "$sd/landing_gates_shadow.log" 2>/dev/null
    if [ "$mode" = enforce ]; then Z3_REFUSE="editor-example-leak: the aider editor replayed its built-in greeting example"; return 1; fi ;;
  esac
  return 0
}

# D3: size-based journal rotation. Over OVN_Z3_JOURNAL_MAX_BYTES (default 5 MB) keep the LAST half of the file (whole lines), swapped in atomically (tmp + mv). Fail-open.
_z3_rotate() {
  local f="${1:-}" max="${OVN_Z3_JOURNAL_MAX_BYTES:-5242880}" sz t
  case "$max" in ''|*[!0-9]*) max=5242880;; esac
  [ -f "$f" ] || return 0
  sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
  [ "${sz:-0}" -gt "$max" ] 2>/dev/null || return 0
  t="$f.rot.$$"
  if tail -c $((max / 2)) "$f" 2>/dev/null | sed 1d > "$t" 2>/dev/null; then mv -f "$t" "$f" 2>/dev/null || rm -f "$t"; else rm -f "$t"; fi
  return 0
}

# D3/index: the UNCOMMITTED change of <wt> as a diff on stdout, capped at OVN_Z3_MAX_DIFF_BYTES (default 2 MB). New files are made visible with intent-to-add in a TEMPORARY index
# (GIT_INDEX_FILE), so the worktree's real index is never touched (shadow mode changes nothing).
_z3_worktree_diff() {
  local wt="$1" cap="${OVN_Z3_MAX_DIFF_BYTES:-2097152}" ti
  case "$cap" in ''|*[!0-9]*) cap=2097152;; esac
  ti="$(mktemp -u "${TMPDIR:-/tmp}/z3_idx.XXXXXX" 2>/dev/null)" || return 0
  if GIT_INDEX_FILE="$ti" git -C "$wt" read-tree HEAD >/dev/null 2>&1; then
    GIT_INDEX_FILE="$ti" git -C "$wt" add -N . >/dev/null 2>&1
    GIT_INDEX_FILE="$ti" git -C "$wt" diff HEAD -U1 --no-color 2>/dev/null | head -c "$cap"
  fi
  rm -f "$ti" "$ti.lock" 2>/dev/null
  return 0
}

z3_step_gate() {
  local wt="${1:-}" kind="${2:-step}" desc="${3:-}" item="${4:-}" files="${5:-}" alog="${6:-}" sd="${7:-${STATE_DIR:-state}}" label="${8:-?}"
  local py out f rule mode msg tmp to="" rc=0
  Z3_REFUSE=""
  [ -d "$wt" ] || return 0
  py="$(_z3_py)"; [ -f "$py" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  command -v timeout >/dev/null 2>&1 && to="timeout 60"
  tmp="$(mktemp "${TMPDIR:-/tmp}/z3_diff.XXXXXX" 2>/dev/null)" || return 0
  _z3_worktree_diff "$wt" > "$tmp" 2>/dev/null
  out="$($to python3 "$py" step-check --kind "$kind" --desc "$desc" --item "$item" --files "$files" --diff "$tmp" --repo "$wt" --base HEAD --head WORKTREE 2>/dev/null)"
  rm -f "$tmp"
  [ -n "$out" ] || out='{"findings":[]}'
  if [ "$kind" = repair ]; then :; fi
  # per-rule decision
  while IFS=$'\t' read -r rule msg; do
    [ -z "$rule" ] && continue
    case "$rule" in
      step-diff-mismatch) mode="$(_z3_mode OVN_Z3_STEP_DIFF)";;
      tone-lint) mode="$(_z3_mode OVN_Z3_TONE)";;
      repair-new-route) mode="$(_z3_mode OVN_Z3_REPAIR_ROUTE)";;
      test-item-src-edit) mode="$(_z3_mode OVN_Z3_TEST_SRC)";;
      call-dropped) mode="$(_z3_mode OVN_Z3_CALL_DROP)"; [ "$mode" = enforce ] && mode=shadow;;
      assert-weaken) mode="$(_z3_mode OVN_Z3_ASSERT_WEAKEN)"; [ "$mode" = enforce ] && mode=shadow;;
      *) mode=shadow;;
    esac
    [ "$mode" = off ] && continue
    mkdir -p "$sd" 2>/dev/null; _z3_rotate "$sd/landing_gates_shadow.log"
    printf '%s\n' "$(printf '%s' "$out" | python3 -c '
import json,sys
rule,mode,label,kind=sys.argv[1:5]
d=json.load(sys.stdin)
for f in d.get("findings",[]):
    if f.get("rule")==rule:
        f=dict(f); f["rule_kind"]=f.get("kind","")   # Z8b: the findings own sub-kind (assert-weaken: expectation-trivial ...) used to be overwritten by the step/repair label below
        f.update(ts=__import__("time").strftime("%Y-%m-%dT%H:%M:%SZ",__import__("time").gmtime()),mode=mode,label=label,kind=kind)
        print(json.dumps(f))
' "$rule" "$mode" "$label" "$kind" 2>/dev/null)" >> "$sd/landing_gates_shadow.log" 2>/dev/null
    if [ "$mode" = enforce ] && [ -z "$Z3_REFUSE" ]; then Z3_REFUSE="$rule: $msg"; rc=1; fi
  done < <(printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin); seen=set()
for f in d.get("findings",[]):
    if f["rule"] not in seen:
        seen.add(f["rule"]); print(f["rule"]+"\t"+f.get("msg","").replace("\t"," ").replace("\n"," ")[:200])
' 2>/dev/null)
  # B0: the aider editor replayed its example (only checked when the attempt log is given)
  if [ -n "$alog" ] && [ -f "$alog" ]; then
    z3_leak_gate "$alog" "$sd" "$label" "$kind" || rc=1
  fi
  return $rc
}

# z3_landing_cap <state-dir> <repo-dir> <item-LINE-hash (ovn_item_line_hash; legacy item_hash accepted)> <item-text> <label> [pending=0]   (pending=0 from ovn_item_guard.sh: run_overnight.sh runs record_outcome BEFORE the guard, so this cycle's landing is ALREADY a row in outcomes.jsonl and counts exactly once; pass 1 only for a caller that runs before its row is written)
#   B6: after a LANDING of item <item-hash>: count its landed* rows in the trailing window (the current row is already in outcomes.jsonl). >= N: shadow = journal, enforce = tag the open
#   progress line with AUTO-SKIP (reversible) and commit it like the other item guards. Prints "PARKED <n>" when it parked something.
z3_landing_cap() {
  local sd="${1:-}" rd="${2:-}" h="${3:-}" text="${4:-}" label="${5:-?}" mode py out over cnt n k br
  mode="$(_z3_mode OVN_Z3_LANDING_CAP)"; [ "$mode" = off ] && return 0
  [ -n "$h" ] && [ -f "$sd/outcomes.jsonl" ] || return 0
  py="$(_z3_py)"; [ -f "$py" ] || return 0
  n="${OVN_Z3_LANDING_CAP_N:-3}"; case "$n" in ''|*[!0-9]*|0|1) n=3;; esac
  out="$(OVN_Z3_LANDING_CAP_H="${OVN_Z3_LANDING_CAP_H:-24}" ovn_hto 60 landing_cap_check python3 "$py" cap-check --outcomes "$sd/outcomes.jsonl" --hash "$h" --n "$n" --pending "${6:-0}" 2>/dev/null)" || return 0
  case "$out" in *'"over": true'*) ;; *) return 0;; esac
  cnt="$(printf '%s' "$out" | sed -E 's/.*"count": ([0-9]+).*/\1/')"
  _z3_rotate "$sd/landing_gates_shadow.log"
  printf '%s\n' "{\"ts\":\"$(date -u +%FT%TZ)\",\"rule\":\"landing-cap\",\"mode\":\"$mode\",\"label\":\"$label\",\"hash\":\"$h\",\"count\":$cnt,\"n\":$n,\"item\":\"$(printf '%s' "$text" | tr -d '"\\' | cut -c1-120)\"}" >> "$sd/landing_gates_shadow.log" 2>/dev/null
  if [ "$mode" = enforce ] && [ -n "$rd" ] && [ -f "$rd/OVERNIGHT_PROGRESS.md" ] && [ -n "$text" ]; then
    k="$(ovn_hto 60 landing_cap_park python3 "$py" cap-park --progress "$rd/OVERNIGHT_PROGRESS.md" --text "$text" --count "$cnt" 2>/dev/null)"
    if [ "${k:-0}" -gt 0 ] 2>/dev/null; then
      git -C "$rd" add OVERNIGHT_PROGRESS.md >/dev/null 2>&1
      git -C "$rd" commit -q -m "chore(queue): park item after ${cnt} landings in 24h (landing cap)" -- OVERNIGHT_PROGRESS.md >/dev/null 2>&1
      # D2: push like every sibling guard (ovn_item_guard.sh credit-refusal / no-op / fail parks): the stage runner does `git reset --hard origin/overnight/feature`, which would erase an unpushed park
      if git -C "$rd" remote get-url origin >/dev/null 2>&1; then
        br="$(git -C "$rd" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        if [ -n "$br" ] && [ "$br" != HEAD ]; then
          if ! ovn_gitb -C "$rd" push -q origin "$br" >/dev/null 2>&1; then
            # non-fast-forward (the branch moved): merge (never rebase) and retry once
            if ovn_gitb -C "$rd" fetch -q origin "$br" >/dev/null 2>&1 && git -C "$rd" merge -q --no-edit "origin/$br" >/dev/null 2>&1; then
              ovn_gitb -C "$rd" push -q origin "$br" >/dev/null 2>&1 || echo "z3: landing-cap park committed but NOT pushed ($br)" >&2
            else
              git -C "$rd" merge --abort >/dev/null 2>&1
              echo "z3: landing-cap park committed but NOT pushed ($br)" >&2
            fi
          fi
        fi
      fi
      echo "z3: landing-cap parked $k item line(s) after ${cnt} landings in ${OVN_Z3_LANDING_CAP_H:-24}h [${label}]" >&2
      printf 'PARKED %s\n' "$k"
    fi
  fi
  return 0
}

# z3_commit_audit <repo-dir> <base-sha> <head-sha> <item-text> <state-dir> <label>   (Z8b-B, 2026-11-10)  SHADOW ONLY, always returns 0.
#   The Z3/Z5/Z7 gates above only ever saw STAGED steps and staged repair rounds. The 2026-11-10 audit's silent-gate landings (shrike-notify ae714d7, gitlark 0b77a340, iptv 619612ad/bab0a91f) were plain
#   aider auto-commits of the NON-staged path (author = the operator + `Co-authored-by: aider`), which never reached z3_step_gate. run_overnight.sh now calls this on the cycle's own commit range
#   (BEFORE_SHA..AFTER_SHA) before the push; findings are journaled to <state-dir>/landing_gates_shadow.log with kind=commit and mode=shadow, nothing is refused or changed.
#   OVN_Z8_COMMIT_AUDIT=off disables it. Bounded by `timeout 60`; any failure = no row.
z3_commit_audit() {
  local rd="${1:-}" base="${2:-}" head="${3:-}" item="${4:-}" sd="${5:-${STATE_DIR:-state}}" label="${6:-?}" py out to=""
  [ "${OVN_Z8_COMMIT_AUDIT:-on}" = off ] && return 0
  [ -d "$rd" ] && [ -n "$base" ] && [ -n "$head" ] && [ "$base" != "$head" ] || return 0
  py="$(_z3_py)"; [ -f "$py" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  command -v timeout >/dev/null 2>&1 && to="timeout 60"
  out="$($to python3 "$py" step-check --kind step --item "$item" --repo "$rd" --base "$base" --head "$head" 2>/dev/null)" || return 0
  case "$out" in *'"rule"'*) ;; *) return 0;; esac
  mkdir -p "$sd" 2>/dev/null; _z3_rotate "$sd/landing_gates_shadow.log"
  printf '%s' "$out" | OVN_Z3_ENV_STEP_DIFF="${OVN_Z3_STEP_DIFF:-shadow}" OVN_Z3_ENV_TONE="${OVN_Z3_TONE:-shadow}" OVN_Z3_ENV_TEST_SRC="${OVN_Z3_TEST_SRC:-shadow}" OVN_Z3_ENV_ASSERT="${OVN_Z3_ASSERT_WEAKEN:-shadow}" OVN_Z3_ENV_CALL="${OVN_Z3_CALL_DROP:-shadow}" python3 -c '
import json,sys,os,time
label=sys.argv[1]
flag={"step-diff-mismatch":"OVN_Z3_ENV_STEP_DIFF","tone-lint":"OVN_Z3_ENV_TONE","test-item-src-edit":"OVN_Z3_ENV_TEST_SRC","assert-weaken":"OVN_Z3_ENV_ASSERT","call-dropped":"OVN_Z3_ENV_CALL"}
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for f in d.get("findings",[]):
    if f.get("rule")=="repair-new-route": continue
    if os.environ.get(flag.get(f.get("rule"),""),"shadow")=="off": continue
    f=dict(f); f["rule_kind"]=f.get("kind",""); f.update(ts=time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),mode="shadow",label=label,kind="commit"); print(json.dumps(f))
' "$label" >> "$sd/landing_gates_shadow.log" 2>/dev/null
  return 0
}
