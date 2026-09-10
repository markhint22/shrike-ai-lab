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
- [ ] [P3] [decomposed] Connector abstraction for external coding agents — Normalize on a `Connector` interface with `build_command(task) -> argv`, `parse_output(stream) -> {diff, cost, tokens}`, and `extract_diff(workdir) -> git patch`, since all three targets are shell-invocable today: Claude Code via `claude -p "<prompt>" --output-format json --allowedTools "Read,Edit,Bash" --max-turns N` (JSON reply includes `session_id`, `total_cost_usd`, resumable via session id); aider via `aider --message "<task>" --yes-always --auto-test --test-cmd "..."` (already used by gitlark's fleet, git-diff comes free from aider's own commits); Cursor now ships a genuinely headless path too via `cursor-agent` CLI plus its Background Agent API (as of 2026 it's no longer purely IDE-bound), so it slots into the same interface rather than needing to be excluded. Git-diff extraction is the one step to standardize outside each tool (`git diff` post-run) since only aider auto-commits. {cat: backend; size: L; multifile: yes; research: none — completed 2026-09-10, sources: code.claude.com/docs/en/headless, aider.chat/docs/scripting.html, cursor.com/docs/cli/overview}
- [ ] [P3] [decomposed] Connector registry + event normalization + picker UI {cat: backend+web; size: M; multifile: yes; research: repo}
## P4 — native
- [ ] [P4] [decomposed] Native iOS + Android via Capacitor wrap of the PWA — gitlark's web app is Vue 3 + Vite (confirmed in `web/package.json`), which is exactly Capacitor's sweet spot: point `capacitor.config.ts`'s `webDir` at the existing Vite `dist` output and ship the same code to iOS/Android with near-zero rewrite, adding native shells only for push notifications, biometric approve-and-dispatch, and app-store presence. Avoid React Native/Flutter (would mean a parallel codebase) and a from-scratch native rewrite (not justified pre-PMF); the main non-trivial work is stripping PWA-only install-prompt logic and wiring an OTA update strategy (e.g. Capgo/OtaKit) so approve/dispatch fixes don't wait on app-store review cycles. {cat: mobile; size: L; multifile: yes; research: none — completed 2026-09-10, sources: capgo.app/blog/transform-pwa-to-native-app-with-capacitor, ajmani.dev/how-to-use-capacitor-with-vue-js}
## Stopping point
Not near. Revisit priorities once the PWA loop (P1+P2) is testable end-to-end.

## P1 — Command Center v1 (greenlit 2026-09-09) — 27B-buildable backend foundations
- [ ] [P1] [decomposed] LocalLLMClient service: OpenAI-compatible streaming client for the LiteLLM box, mirroring ClaudeClient.stream_message signature (httpx SSE), + LOCAL_LLM_* settings in core/config {cat: backend; size: M; multifile: no; research: repo}
- [ ] [P1] [decomposed] Repo-file GET/PUT endpoint: thin wrapper over github get_file_content/create_or_update_file returning content+sha (powers the doc viewer/editor) {cat: backend; size: S; multifile: no; research: repo}
- [ ] [P1] [decomposed] Single ad-hoc task enqueue endpoint: append one backlog line to a repo queue file, reusing task_to_backlog_line + dispatch dedup {cat: backend; size: S; multifile: no; research: repo}
- [ ] [P1] [decomposed] Stage-run stats aggregator: pure module parsing stage_runs jsonl -> by-tier verified counts, tok totals, tok/s, median/max step, fail histogram (ports ovn_stage_stats.py, unit-tested) {cat: backend; size: M; multifile: no; research: repo}
- [ ] [P1] [decomposed] Packaging enablers: extract the backlog item-line grammar into a versioned serialize/parse module + de-hardcode status_reader staging branch/keywords via config {cat: backend; size: S; multifile: no; research: repo}
