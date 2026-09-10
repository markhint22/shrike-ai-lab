# Grooming proposal — gitlark — 2026-08-31 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [HIGH] `backend/app/services/analytics.py` — serialized outputs `generated_at=datetime.utcnow().isoformat()` (line 168) and `"timestamp": datetime.utcnow().isoformat()` (line 209). Change both to `datetime.now(timezone.utc).isoformat()` and update the import on line 9 to `from datetime import datetime, timedelta, timezone`. One file.
- [x] [HIGH] `backend/app/services/ml_code_insights.py` — every `datetime.utcnow().isoformat()` (lines 92, 108, 124, 140, 184). Change to `datetime.now(timezone.utc).isoformat()` and update the import on line 1 to `from datetime import datetime, timedelta, timezone`. One file.
- [x] (already-satisfied in code, implement-verified) [HIGH] `backend/app/services/conversation.py` — ONLY the two serialized outputs `"timestamp": datetime.utcnow().isoformat()` (line 317) and `edited_at = datetime.utcnow().isoformat()` (line 523). Change to `datetime.now(timezone.utc).isoformat()` and change the import on line 4 to `from datetime import datetime, timezone`. DO NOT change line 524 `updated_at = datetime.utcnow()` (DB column). One file.
- [x] [HIGH] `backend/app/models/audit.py` — line 359 `"exported_at": datetime.utcnow().isoformat()` (JSON export). Change to `datetime.now(timezone.utc).isoformat()` and change the local import on line 350 to `from datetime import datetime, timezone`. One file.
- [x] [MED] `backend/app/services/metadata.py` — line 55 `"analysis_timestamp": datetime.utcnow().isoformat()`. Change to `datetime.now(timezone.utc).isoformat()` and change the import on line 3 to `from datetime import datetime, timezone`. One file.
- [x] [MED] `backend/app/services/repo_analyzer.py` — line 155 `analyzed_at=datetime.utcnow().isoformat()`. Change to `datetime.now(timezone.utc).isoformat()` and change the import on line 17 to `from datetime import datetime, timezone`. One file.
- [x] [MED] `backend/app/services/review.py` — line 101 `self.created_at = datetime.utcnow().isoformat()`. Change to `datetime.now(timezone.utc).isoformat()` and change the import on line 11 to `from datetime import datetime, timezone`. One file.
- [x] [MED] `backend/app/services/review_collaboration.py` — every `datetime.utcnow().isoformat()` (lines 64, 97, 132, 159, 171, 194, 211, 221, 237, 257, 277). Change to `datetime.now(timezone.utc).isoformat()` and add `timezone` to the top `from datetime import ...`. Don't alter the `UUID(...)` on line 78. One file.
- [x] [MED] `web/src/components/MessageActions.vue` — emoji-only Edit (✏️ ~line 37) and Delete (🗑️ ~line 47) buttons have `title` but no `aria-label`. Add `aria-label="Edit message"` and `aria-label="Delete message"` to the respective `<button>`s. One file.
- [x] [MED] `web/src/components/ConversationActions.vue` — four emoji-only buttons (📌 line 44, 📦 line 54, ⭐ line 64, 🔗 line 74) have `title` but no `aria-label`. Add `aria-label` to each matching its `title`. One file.
- [x] [LOW] `backend/app/services/export_service.py` — implement the stubbed `_export_csv(self, data: List[Dict]) -> bytes` (`# TODO`, returns `b""`). Use stdlib `csv`+`io.StringIO`: header from union of keys, one row per dict, return `output.getvalue().encode()`; empty `data` -> `b""`. One file.
- [x] [LOW] `backend/app/services/conversation_analytics.py` — `extract_key_points` (line 22) returns hardcoded `["Key point 1", "Key point 2"]`. Replace with a heuristic: first sentence of each `role == "user"` message, dedupe, up to 5; `[]` when none. Keep the signature. One file.
- [x] [HIGH] `backend/app/routers/review.py` — `get_quality_trend` (line 260) has `days: int = 30` with no bounds. `Query` already imported. Change to `days: int = Query(30, ge=1, le=365),`. One file.
- [x] [HIGH] `web/src/pages/DashboardPage.vue` — two `target="_blank"` anchors lack `rel`: GitHub link (line 86) and repo View link (line 142). Add `rel="noopener noreferrer"` to both `<a>` tags. One file.
- [x] [MED] `backend/app/services/operational_transform.py` — four op timestamps `datetime.utcnow()` (lines 44, 59, 184, 209) are serialized via `.isoformat()` and only compared to each other (safe). Change the import line 10 to `from datetime import datetime, timezone` and replace `datetime.utcnow()` on those 4 lines ONLY. Don't touch `timestamp=operation.timestamp` lines. One file.
- [x] [MED] `backend/app/services/conversation.py` — line 317 timestamp and line 523 edited_at (both `datetime.utcnow().isoformat()`) are output. Change import line 4 to `from datetime import datetime, timezone` and replace on lines 317 and 523 ONLY. Leave every `updated_at = datetime.utcnow()` DB assignment (325, 388, 412, 436, 466, 494, 525, 553, 597, 627) naive. One file.
- [x] [MED] `web/src/components/ShareDialog.vue` — icon-only close button line 40 has no name/type. Add `type="button" aria-label="Close dialog"`. Only line 40. One file.
- [x] [MED] `web/src/pages/AgentChatPage.vue` — icon-only error-dismiss button line 196 has no name/type. Add `type="button" aria-label="Dismiss error"`. Only line 196. One file.
- [x] [MED] `web/src/components/ExportMenu.vue` — icon-only close button line 70 has no name/type. Add `type="button" aria-label="Close menu"`. Only line 70. One file.
- [x] [MED] `web/src/components/TemporalNavigation.vue` — two icon-only slider buttons: line 240 (rewind) and line 243 (forward). Add `type="button" aria-label="Step backward"` to the first and `type="button" aria-label="Step forward"` to the second. Leave Start/End buttons alone. One file.
- [x] [MED] {vue·a11y·T1·test-covered} `web/src/components/ReactionButtons.vue` — the per-emoji reaction buttons in the v-for (line 52) render only the emoji, no type/aria-label. Add `type="button"` and an `:aria-label` binding using the emoji (e.g. React with that emoji) to that button. One file.
- [x] [MED] {vue·a11y·T1·test-covered} `web/src/components/ConversationSearch.vue` — Search button (line 114) and Clear button (line 122) have no `type` (could submit a form). Add `type="button"` to both. One file.
- [x] [MED] {vue·a11y·T1·test-covered} `web/src/components/ExportConversationDialog.vue` — three action buttons (lines 80 close, 86 export, 93 archive) have no `type`. Add `type="button"` to each. One file.
- [x] [MED] {vue·a11y·T1·test-covered} `web/src/components/RealtimeCollaboration.vue` — three conflict-resolution buttons (lines 109, 121, 130) have no `type`. Add `type="button"` to each. One file.
- [x] [MED] {vue·a11y·T1·test-covered} `web/src/components/ConversationPanel.vue` — send button line 53 has no `type`. Add `type="button"`. Only line 53. One file.
- [x] [LOW] {vue·a11y·T1·test-covered} `web/src/components/CodeReviewPanel.vue` — decorative glyph line 69 (success-icon div) is read aloud. Add `aria-hidden="true"`. Only line 69. One file.
- [x] [LOW] {vue·a11y·T1·test-covered} `web/src/components/AgentLibrary.vue` — decorative glyph line 234 (template-icon div). Add `aria-hidden="true"`. Only line 234. One file.
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [LOW] {vue·a11y·T1·test-covered} `web/src/components/CollaborativeWorkspace.vue` — three avatar `<img>` (lines 44, 149, 220) have `:src`/`:alt` but no `loading`, below the fold. Add `loading="lazy"` to each. One file.
- [x] [HIGH] {py·bugfix·T2·test-covered} `backend/app/services/notification_service.py` — REAL CRASH: `UUID()` is called with no args at lines 29, 49, 64 (TypeError on every notification). Change the import to `from uuid import UUID, uuid4` and replace each bare `UUID()` with `uuid4()`. One file.
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [MED] {py·other·T2·test-covered} `backend/app/services/distributed_tracing.py` — `get_trace` (~line 46) returns `{'traceId':trace_id,'spans':[]}` despite spans being held in memory. Return the in-memory spans whose `trace_id` matches instead of an empty list. One file.
```

## Proposed (LLM re-evaluation — review before applying)
1. [HIGH] `backend/app/services/distributed_tracing.py` — Fix `get_trace` to return in-memory spans matching `trace_id` instead of an empty list (currently returns `{'spans': []}` despite holding data).
2. [MED] `backend/app/services/notification_service.py` — Verify `UUID()` crash fix: ensure `uuid4()` is used at lines 29, 49, 64 and import is `from uuid import UUID, uuid4` (marked done but high-risk crash).
3. [MED] `backend/app/routers/review.py` — Add bounds to `get_quality_trend` `days` parameter: change `days: int = 30` to `days: int = Query(30, ge=1, le=365)` (marked done, verify implementation).
4. [LOW] `backend/app/services/export_service.py` — Implement `_export_csv` stub using stdlib `csv` and `io.StringIO` to generate CSV bytes from list of dicts (marked done, verify implementation).
5. [LOW] `backend/app/services/conversation_analytics.py` — Replace hardcoded `extract_key_points` with heuristic: extract first sentence of user messages, dedupe, limit to 5 (marked done, verify implementation).
6. [MED] `web/src/components/MessageActions.vue` — Add `aria-label` to Edit and Delete buttons (marked done, verify implementation).
7. [MED] `web/src/components/ConversationActions.vue` — Add `aria-label` to four emoji-only buttons (Pin, Archive, Star, Link) (marked done, verify implementation).
8. [MED] `web/src/pages/DashboardPage.vue` — Add `rel="noopener noreferrer"` to GitHub and repo View links (marked done, verify implementation).
9. [MED] `web/src/components/ShareDialog.vue` — Add `type="button" aria-label="Close dialog"` to close button (marked done, verify implementation).
10. [MED] `web/src/pages/AgentChatPage.vue` — Add `type="button" aria-label="Dismiss error"` to error-dismiss button (marked done, verify implementation).
11. [MED] `web/src/components/ExportMenu.vue` — Add `type="button" aria-label="Close menu"` to close button (marked done, verify implementation).
12. [MED] `web/src/components/TemporalNavigation.vue` — Add `type="button"` and `aria-label` to rewind and forward slider buttons (marked done, verify implementation).
13. [MED] `web/src/components/ReactionButtons.vue` — Add `type="button"` and dynamic `aria-label` to reaction buttons (marked done, verify implementation).
14. [MED] `web/src/components/ConversationSearch.vue` — Add `type="button"` to Search and Clear buttons (marked done, verify implementation).
15. [MED] `web/src/components/ExportConversationDialog.vue` — Add `type="button"` to close, export, and archive buttons (marked done, verify implementation).
16. [MED] `web/src/components/RealtimeCollaboration.vue` — Add `type="button"` to three conflict-resolution buttons (marked done, verify implementation).
17. [MED] `web/src/components/ConversationPanel.vue` — Add `type="button"` to send button (marked done, verify implementation).
18. [LOW] `web/src/components/CodeReviewPanel.vue` — Add `aria-hidden="true"` to decorative success-icon div (marked done, verify implementation).
19. [LOW] `web/src/components/AgentLibrary.vue` — Add `aria-hidden="true"` to decorative template-icon div (marked done,
