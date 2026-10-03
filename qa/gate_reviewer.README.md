# Gate S8 - advisory Qwen reviewer + refuter (`qa/gate_reviewer.py`, `qa/qa_reviewer_label.py`)

A local Qwen reads the **product-code** part of each merged range, proposes a few concrete defects, and the harness then tries hard to throw
every proposal away: mechanically (is the quoted code really in the diff?) and with a second Qwen call that is asked to *refute* the claim.
What survives is recorded as a **FLAG** with its evidence. It uses the GPU the QA gates otherwise leave idle (the box's 27B, via the local
litellm at `127.0.0.1:4000`, alias `qwen-dflash-27B`).

**It is advisory and influences nothing.** It never returns `FAIL`, never exits non-zero, never blocks a merge, a promote, a queue item or
an alert. The plan's bar before that may change: **>= 50 labelled findings from our own repos AND >= 60% precision** (docs/QA_PLAN section 7,
Phase 3). Until the label CLI says that bar is met, a FLAG is a hint for a human, nothing more. Wording is "evidence found", never "verified bug".

`qa_run_shadow.sh` already runs every `qa/gate_*.py` over each merged range; this file needs no wiring. Mode: `OVN_QA_REVIEWER=off|shadow|enforce`
or `state/qa_modes.json` (`off` = NA with no model call; `enforce` changes nothing, there is nothing to enforce).

## CLI

    python3 qa/gate_reviewer.py check --repo <name|path> --base <ref> --head <ref> [--no-record] [--llm-url URL] [--model NAME] [--trace FILE]

`--trace FILE` appends one JSON line per proposal with its disposition (`dropped:<reason>`, `refuted`, `survived`) - redacted, for measurement only.

| env | default | meaning |
|---|---|---|
| `QA_REVIEWER_DEADLINE` | 120 | wall-clock seconds for the WHOLE run (all chunks + refuter calls) |
| `QA_REVIEWER_CALL_TIMEOUT` | 60 | cap for one request (also enforced with SIGALRM against a server that trickles bytes forever) |
| `QA_REVIEWER_MAX_CALLS` | 16 | request cap per run |
| `QA_REVIEWER_LANGS` | `py,js,kt,gd` | which languages are reviewed (`js` = ts/tsx/js/jsx/vue). Kotlin and GDScript were enabled 2026-10-03 (xlite was 100% NA); `swift` is listed as skipped until its quality is measured |
| `QA_REVIEWER_URL` / `_MODEL` | `127.0.0.1:4000` / `qwen-dflash-27B` | loopback only (the reused client refuses anything else) |

## What it does, in order

1. **Select**: `git diff --name-only` -> keep code files that are not tests, not generated (`*_pb2.py`, `generated/`, "DO NOT EDIT" headers,
   migrations/versions dirs), not lockfiles/vendored/dist. Path rules are `gate_antigaming.is_test_path/ignorable/lang_of` (reused, one source of truth).
2. **Chunk** per file at hunk boundaries, each chunk <= ~8.5k tokens of diff (pessimistic estimate: 2.8 chars/token), so a request stays <= ~12k tokens
   of the 65,536 context. A file whose diff is > ~17k tokens, or one hunk that alone exceeds a chunk, is **skipped and listed** in `details.skipped`.
   Smallest diffs are reviewed first (reviewer accuracy collapses on large diffs, plan section 4; more files fit in the deadline).
3. **Review call**: at most 3 defects per chunk as strict JSON `{file,line,quote,claim,severity}`; `quote` must be one verbatim `+` line. The prompt says
   "an empty list is the expected answer" and bans style/speculation/missing-tests.
4. **Harness verification** (each failure is dropped and counted in `details.dropped`): schema (`malformed`), the file is the chunk's file (`wrong_file`),
   the quote has >= 6 chars (`quote_too_short`), the cited `line` is **inside a hunk** (`line_outside_hunk`), and the quote exists **verbatim in an ADDED line
   of that same hunk** (`quote_not_found`; a context or removed line does not count). The recorded line is the quote's real line. Over-cap (`over_cap`)
   and `duplicate` findings are counted too.
5. **Refuter call**: sees only the claim, the quote and +-20 lines of the head file, and is told to refute; `refuted` is the default for a missing,
   unparseable or non-boolean answer. Only `refuted:false` survives.
6. **Record**: survivors go into `details.findings` (`id`, file, line, quote, claim, severity, the refuter's reason) with `details.counts` =
   `proposed / verified / refuted / refute_unavailable / survived`. All free text is **redacted**: known secret shapes (AWS, `sk_`, GitHub, Slack, JWT,
   private keys, URL credentials, `password=...`), long random-looking tokens, and every secret-like literal that appears in the chunk's added lines
   even when the claim repeats it in prose.

## Verdicts

| verdict | when |
|---|---|
| `FLAG` | >= 1 finding survived the refuter. Summary carries the counts and says `PARTIAL` when not every chunk was reviewed. |
| `PASS` | every chunk was reviewed, no refuter call was lost, nothing survived. "Nothing survived" is **not** "no defects": a quantized 27B reviewer misses most real bugs. |
| `NA` | no product code in the diff (docs/tests/lockfiles/generated/disabled language), mode `off`, or empty diff. No model call is made. Skipped files are listed. |
| `UNVERIFIED` | model dead / hung / too slow (circuit breaker: the first failed call stops the run; one timeout is the most a hung model can cost), model answered garbage for every chunk, or the range was only **partly** reviewed (deadline / call cap) with nothing to show. Never PASS on partial coverage. |

A verified finding whose refuter call failed is **not** recorded as a survivor (it was never tested): it is counted as `refute_unavailable` and makes the run
`UNVERIFIED` unless other findings survived.

## Labelling and precision (`qa/qa_reviewer_label.py`)

    python3 qa/qa_reviewer_label.py list --unlabelled          # ids + file:line + claim, newest first
    python3 qa/qa_reviewer_label.py label --id <id> --label TP|FP|unclear [--note "..."]   # -> state/qa_reviewer_labels.jsonl (latest label per id wins)
    python3 qa/qa_reviewer_label.py report [--json]

`report` prints run totals (proposed/verified/survived), labelled counts, and **precision = TP / (TP+FP)** with a 95% Wilson interval and the sample size -
but **refuses to print a percentage under 50 decisive (TP or FP) labels**. `unclear` counts toward neither side. It also joins unlabelled findings with later
`qa_ledger.jsonl` events: a `revert`, `hotfix` or `escape` in the same repo touching the same file within 7 days **after** the finding is listed as a
*suggested* TP (reverts carry no files, so they take the files of the landed record they undid). Suggestions are never counted as labels; a human confirms
them with `label`. A hotfix on the same file is weak evidence (the file may simply be churny): the ledger's own `confidence` is shown next to it.

## Tests

`scripts/test/test_qa_reviewer.py` (registered in `run_all.sh`): the real entry point under `env -i` + minimal PATH, absolute and relative path, against a stub
model server started by the test (a thread, shut down at the end; no network). Cases: hallucinated quote, line outside hunk, context-line quote, wrong file,
bad severity, short quote, over-cap, garbled model output, refuter kills a finding (+ three default-to-refuted shapes), survivor recorded as FLAG and exit 0
even in enforce mode, dead model, hung model (within the deadline, exactly one call), refuter call failing, huge / mid-size / partial-coverage chunking,
test-only / docs-only / generated / swift diffs -> NA with no model call, secret redaction in findings, stdout and the shadow record, no leftover worktrees,
and the labelling CLI + ledger join (positive and negative controls). `QA_REVIEWER_TEST_GATE=<path>` runs the suite against a mutated copy of the gate - that is how
each check was proven to fail when its code is broken.

## Measured on real history (2026-10-02, box GPU shared with the live dev loop at ~96% utilisation; 32 model calls in total)

Method: the real gate, scratch `OVN_DIR` (nothing written to live state), `OVN_REPOS_DIR` pointing at the box clones (read-only git), `--no-record`, one
run at a time, niced. Ranges are `first-parent..merge` of recent `develop` merges (what the hygiene hook hands the shadow runner).

| set | runs | chunks | proposed | verified | survived | seconds per run |
|---|---|---|---|---|---|---|
| 8 small real ranges (1-72 added lines; billwatch, gitlark x2, iptv_apps x2, test-automation-agent x3) | 8 | 11 | 0 | 0 | 0 | 2.7 - 8.1 (median 3.9) |
| 4 larger real ranges (92-351 added lines; billwatch, gitlark, iptv_apps, test-automation-agent) | 4 | 9 | 0 | 0 | 0 | 5.5 - 14.4 (median 8.6) |
| 5 seeded synthetic defects (inverted ownership check, swallowed verify error, off-by-one slice, inverted expiry, divide-by-zero) + 1 clean control, throwaway repos (swallowed-error repo run twice: before and after the severity fix) | 7 | 7 | 7 | 6 | 5 (all 5 defects; 0 on the clean control) | 2.0 - 33.7 |

- On the **real** ranges the reviewer proposed **nothing** (20 chunks, 20 calls, every answer `{"findings": []}`), so there are **no survivors to label and no precision
  figure**. That is a yield of zero, not evidence of zero defects. These merges are small, tests-green-gated fleet commits, which is the population where a
  reviewer is least likely to find anything; the plan expected low yield. Whether it ever finds a real defect on this fleet's output is exactly what shadow
  recording over weeks will show.
- The **seeded** runs only prove the pipeline end to end (a real defect passes verification and the refuter; clean code stays quiet). They are my own bugs and
  say nothing about real precision. One seeded run exposed a harness bug that is now fixed: the model returned a correct finding without `severity` and strict
  validation discarded it (see `severity_defaulted`).
- Cost per run is 1-3 requests of 0.9-2.5k prompt tokens (6k for the 351-line range), 2-13 GPU seconds; the first seeded run's refuter call took ~30 s when the GPU was
  busy, which is why the per-run deadline (120 s) and the breaker exist.

## Limits (read before trusting a number)

- Survivors are **unlabelled** until a human labels them. `survived` is not a precision.
- The refuter is the same model as the reviewer: shared blind spots. It lowers noise; it does not add independence.
- Only the changed hunks plus the refuter's +-20 lines are seen: cross-file defects (missing wiring, wrong caller) are mostly out of reach.
- With the live dev loop on the GPU, calls queue behind the 27B's other work; the 120 s deadline then makes some runs `UNVERIFIED` rather than late.
- Merge-commit ranges are the unit (what `branch_hygiene.sh` hands the shadow runner), not individual feature commits.

## 2026-10-03 additions (QA diagnosis F6)

* **Kotlin + GDScript** are reviewed by default (`QA_REVIEWER_LANGS=py,js,kt,gd`).
* **Severity floor**: a verified finding whose claim/quote reads as an auth bypass (unauthenticated, no auth/token/ownership check, "anyone can", account
  takeover ...) or a secret exposure (hardcoded secret, key logged/leaked ...) is never below `high`; the finding carries `severity_raised: true`. A label is
  not evidence, so this only raises the label of a finding that already survived verification and the refuter. Still advisory: never FAIL, never blocks.
* **Model-free pattern pass** (`pattern_findings`, `source: "pattern"`, `details.pattern_findings`): (1) a new `@router.post|put|patch|delete("<sensitive path>")`
  (reset/change/forgot password, delete account/user, admin, impersonate, grant/revoke, api-key, role/password/email of a user) whose signature has no
  authentication/authorization/token parameter; (2) a hardcoded default for a secret-named variable whose value says change/default/dev/local/example
  (pydantic `Field(default="...")` included). Only ADDED lines of the reviewed files count. These need no GPU and cannot be refuted by a model (the summary
  says how many came from this pass); they are what `qa_replay.py --gold` exercises for the billwatch reset-password and gitlark default-key incidents.
