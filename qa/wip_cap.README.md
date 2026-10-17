# qa/wip_cap.py - Phase 5 WIP-cap observer (SHADOW)

Plan reference: `docs/QA_PLAN_2026-10-01.md` section 6 policy 2 ("WIP caps on features landed but not yet through their class's gates") and Phase 5 ("caps go alert, then soft, then hard").

## What it does today
Reads `state/qa_ledger.jsonl`, groups landed records into features (repo + feat tag), drops the ones already in prod, and for every repo reports the count by risk class (A/B/C), the median and
oldest age of the BEHAVIORAL (A+B) ones, and a state against the cap: `UNDER` (< cap), `AT` (== cap), `OVER` (> cap). Rows go to `state/qa_shadow/wip_cap.jsonl` (kinds `repo`, `global`, `area`).
The only other effect is ONE `alerts.log` WARN line per over-cap scope per UTC day (`wip-cap:repo:<repo>`, `wip-cap:global`, `wip-cap:area:<repo>:<area>`). Nothing throttles anything.

| scope | starting cap (plan guesses) | override |
|---|---|---|
| billwatch, iptv_apps, gitlark | 8 | `OVN_QA_WIP_CAP_REPOS="billwatch=6,xlite=20"` |
| test-automation-agent | 12 | same |
| every other repo | 15 | `OVN_QA_WIP_CAP_DEFAULT` |
| global (A+B, all repos) | 40 | `OVN_QA_WIP_CAP_GLOBAL` |
| one class A area (first two path components of the feature's first non-test, non-doc file) | 8 | `OVN_QA_WIP_CAP_AREA` |

"Not yet through the gates" = not yet an ancestor of the repo's prod ref (`origin/main`, env `OVN_QA_WIP_PROD_REF`) and no ledger event `gated` / `promoted` for it. Features with no attributed commit are
`unattributed`, repos with no clone / prod ref are `unknown`: both are listed, never counted, never alerted. Class C (tests/docs/deletes) is reported but never counted ("test-hardening, bug and QA-lane items continue").

## Commands
```
python3 qa/wip_cap.py report [--days 30] [--json]     # table, writes nothing
python3 qa/wip_cap.py run    [--no-record]            # rows + alert (what cron runs, via qa/phase5_cron.sh)
python3 qa/wip_cap.py eligible --repo R [--class A|B|C] [--area app/auth]   # last line ELIGIBLE or HOLD
```

## Flag `OVN_QA_WIP_CAP=off|shadow|soft|hard` (default `shadow`; an unknown value, including `enforce`, falls back to `shadow`)
* `off` - nothing computed, written or alerted.
* `shadow` - rows + alert; `eligible` always answers ELIGIBLE (and reports `would_hold`).
* `soft`, `hard` - parsed, **not wired to the dispatcher in this package**. Only `eligible` honours them (soft: hold class A/B items of a repo AT or OVER its own cap; hard: also hold when the global cap
  or the item's class A area cap is reached; class C is never held; `state/wip_cap_override_<repo>` lifts the hold). Nothing calls `eligible` yet.

## Dispatcher hook point (ships later; this is the exact place)
`scripts/lib_item_select.sh`: every selector that answers "which open item is next" pipes its doable lines through `ovn_bug_first_order` (run_overnight.sh peek, delete-executor peek, the "Doable Next Steps"
slice, the inline T3+ trigger, the stage runner's pick, `ovn_resolve_top_item`). The cap belongs in the same chokepoint, immediately AFTER `ovn_bug_first_order` and BEFORE the line is returned:
drop behavioral lines (not bug / EMERGENCY / QA-lane / test-hardening lines) when `python3 qa/wip_cap.py eligible --repo "$repo" --class "$cls"` prints exactly `HOLD`. Any other output, an error or a
timeout MUST mean "eligible" (an observer bug must never freeze development). Throttle by item eligibility, never by pausing the fleet.

## How to promote to enforce (do NOT do this before the shadow evidence is in)
1. Run `qa/phase5_cron.sh` hourly for >= 1 week; read `wip_cap.jsonl` and the alert lines: is OVER real (a QA stage is stalled) or noise (the prod ref is stale in a clone, a gate never clears)? Tune the caps from the data.
2. Wire the hook above behind `OVN_QA_WIP_CAP=soft` on ONE repo first (set it in that repo's cron/env only), watch that bug and test-hardening lines keep flowing and that the manual override works.
3. Only then `hard`. Rollback = `OVN_QA_WIP_CAP=shadow` (or `off`); no deploy needed because the hook only asks `eligible`.
Tests: `scripts/test/test_qa_wip_cap.py` (73+ checks incl. under/at/over, global, class A area, mutants: raised cap, weakened comparison, dropped scopes).

## Review fix (2026-10-17): docstring churn is not WIP
A feature whose every commit subject is `docs`/`style`/`test`/`chore`/`ci`/`build` (or, with no subjects, whose category is docs-like) is class C whatever its file paths, so `docs: add docstring to ...` batches no longer push a repo OVER its cap. Any real `feat`/`fix` commit in the feature keeps it behavioral.
