# Roadmap — gitlark v2 (mobile plan-and-dispatch command center)
**Maturity:** LOW — active rebuild (P0-P6). Most runway in the portfolio. **NOT a PR-review tool.** **Stopping point:** far off — this is the flagship build-out.

## P1 — the core loop (make it testable)
- [ ] [P1] [decomposed] Planner backend: goal → routed task plan (schemas, plan state machine) {cat: backend; size: L; multifile: yes; research: repo}
- [ ] [P1] [decomposed] PWA: conversation-first mobile UI (talk to repos, see plans) {cat: web; size: L; multifile: yes; research: repo}
- [ ] [P1] [decomposed] Git-mediated dispatch: plan → commit tasks to the fleet's OVERNIGHT_PROGRESS {cat: backend; size: M; multifile: yes; research: repo}
## P2 — the full loop
- [ ] [P2] [decomposed] Review loop: see + merge what the fleet built (PR/diff surfaces, big-diff pagination) {cat: web+backend; size: L; multifile: yes; research: repo}
- [ ] [P2] [decomposed] Conversational control plane: fleet events in chat, add-to-queue from chat, gated ops {cat: backend+web; size: M; multifile: yes; research: repo}
## P3 — Agent Connectors (the differentiator)
- [ ] [P3] [needs-research] Connector abstraction: drive external CLI agents (Claude Code, aider, cursor) not just the 27B fleet {cat: backend; size: L; research: web}
- [ ] [P3] [decomposed] Connector registry + event normalization + picker UI {cat: backend+web; size: M; multifile: yes; research: repo}
## P4 — native
- [ ] [P4] [needs-research] Native iOS + Android after the PWA validates the loop {cat: mobile; size: L; research: web}
## Stopping point
Not near. Revisit priorities once the PWA loop (P1+P2) is testable end-to-end.

## P1 — Command Center v1 (greenlit 2026-09-09) — 27B-buildable backend foundations
- [ ] [P1] [decomposed] LocalLLMClient service: OpenAI-compatible streaming client for the LiteLLM box, mirroring ClaudeClient.stream_message signature (httpx SSE), + LOCAL_LLM_* settings in core/config {cat: backend; size: M; multifile: no; research: repo}
- [ ] [P1] [decomposed] Repo-file GET/PUT endpoint: thin wrapper over github get_file_content/create_or_update_file returning content+sha (powers the doc viewer/editor) {cat: backend; size: S; multifile: no; research: repo}
- [ ] [P1] [decomposed] Single ad-hoc task enqueue endpoint: append one backlog line to a repo queue file, reusing task_to_backlog_line + dispatch dedup {cat: backend; size: S; multifile: no; research: repo}
- [ ] [P1] [decomposed] Stage-run stats aggregator: pure module parsing stage_runs jsonl -> by-tier verified counts, tok totals, tok/s, median/max step, fail histogram (ports ovn_stage_stats.py, unit-tested) {cat: backend; size: M; multifile: no; research: repo}
- [ ] [P1] [decomposed] Packaging enablers: extract the backlog item-line grammar into a versioned serialize/parse module + de-hardcode status_reader staging branch/keywords via config {cat: backend; size: S; multifile: no; research: repo}
