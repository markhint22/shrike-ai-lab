# Patch description: write a promote manifest from `daily_promote.sh` (Phase 5)

Status: documented only. **NOT applied.** `daily_promote.sh` and `promote_to_prod.sh` are byte-identical to what they were before the Phase 5 package; a test
(`scripts/test/test_qa_promote_manifest.py`) asserts neither mentions `promote_manifest` or `rollback_drill`. Apply this only after `qa/promote_manifest.py` has produced
shadow manifests for at least one week and Mark has looked at them (the decision field is advisory until then).

Built against the live scripts as of 2026-10-17 (the same base as `daily_promote_release_flow.md`, which this patch is independent of: it works with today's merge-style promote
and with the release-branch flow).

## What the manifest adds

`qa/promote_manifest.py generate --repo R` writes `state/promote_manifests/<repo>-<YYYYMMDD-HHMMSS>.json` and ONE ledger event (`type: promote_manifest`) with:
repo, candidate SHA, release branch (a `release/*` branch pointing at the candidate, else null), main SHA, the PRIOR prod tag (rollback anchor), batch size, the QA gate verdicts
whose head commit is in `prior_tag..candidate`, the staging match + soak hours (live only), a `decision` (HOLD | PROCEED | PROCEED-UNVERIFIED) and a `summary` that starts with the
decision. A candidate with a FAIL gate says `HOLD` in the summary. It is read-only on the clone, never fetches, and always exits 0.

## Edit 1 (shadow): write the manifest next to the promote, change nothing about what is promoted

In `daily_promote.sh`, in the per-repo loop, immediately BEFORE `out="$(./promote_to_prod.sh ...)"`:

```bash
# Phase 5 (shadow): one manifest per repo per promote attempt. Never blocks, never changes the promote. Kill switch: OVN_QA_PROMOTE_MANIFEST=off.
if [ "${OVN_QA_PROMOTE_MANIFEST:-shadow}" != "off" ] && [ -f "$DIR/qa/promote_manifest.py" ]; then
  mf="$(timeout 120 python3 "$DIR/qa/promote_manifest.py" generate --repo "$r" 2>/dev/null | tail -n 1)"
  echo "  [manifest] $(echo "$mf" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read() or "{}"); print((d.get("summary") or d.get("error") or "no manifest")[:300])' 2>/dev/null)"
fi
```

and add `manifest` to the two `grep -E '^  \[(candidate|staging-gate|...)\]'` alternations so the line reaches the daily log.

Without `--candidate` the manifest asks `release_candidate.compute_plan` for the candidate (the same call `promote_gate.py` makes), so the manifest names the SHA the promote would pick.

## Edit 2 (later, only after the shadow week and a decision by Mark): act on HOLD

Not shipped. The shape is: when `OVN_QA_PROMOTE_MANIFEST=enforce` (a value this package deliberately does not wire; today any value other than `off` behaves as `shadow`) and the manifest
`decision` is `HOLD`, skip that repo with the manifest summary as the reason, exactly like the existing staging-evidence block. PROCEED-UNVERIFIED must keep promoting (infra gaps never block).

## Rollback drill

`qa/rollback_drill.py run --repo R` restores the previous `prod-<ts>-R` tag in a scratch `git clone --shared`, verifies the restore byte for byte and runs the offline build smoke. It is NOT in
any cron: run it once per promoted repo by hand (QA plan 5A: "one rollback drill per promoted repo") and a weekly cron line is optional:

```
17 6 * * 1 cd $HOME/overnight-queue && for r in billwatch iptv_apps shrike-labs-website; do python3 qa/rollback_drill.py run --repo $r >> logs/rollback_drill.log 2>&1; done
```

Results land in `state/qa_shadow/rollback_drill.jsonl` (verdicts PASS / FAIL / UNVERIFIED). A DB downgrade is out of scope.

## History

`qa/promote_manifest.py history --repo R --n 1` rebuilds the manifest of the last real promote from the `prod-<ts>-<repo>` tags (gate verdicts from whatever shadow rows still
resolve into that range; staging evidence is marked "history: not reconstructible").
