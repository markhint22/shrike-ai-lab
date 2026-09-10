# Grooming proposal — iptv_apps — 2026-08-31 04:01

## Current Next Steps
```
- [x] [HIGH] `iptv-backend/app/routers/discovery_api.py` — six endpoints have unbounded `limit: int = N` (lines 55, 83, 110, 136, 165, 193). Wrap each in `Query(...)` with `ge=1, le=100` keeping each default, matching line 28's pattern. Only those six params. One file.
- [x] [HIGH] `iptv-web/src/components/PaywallModal.vue` — the icon-only dismiss button at line 77 (`XMarkIcon` only) has no accessible name. Add `aria-label="Close"` to that `<button>`. One file.
- [x] [HIGH] `iptv-backend/app/services/engagement_tracking_service.py` — `track_engagement` output uses naive `datetime.utcnow()` at line 83 (`event_id` f-string) and line 88 (`timestamp` isoformat). Change the import on line 2 to `from datetime import datetime, timezone` and replace both with `datetime.now(timezone.utc)`. One file.
- [x] [MED] `iptv-backend/app/routers/epg_analytics.py` — `/recommendations` has unbounded `limit: int = 10` at line 42. Change to `limit: int = Query(10, ge=1, le=50)` (`Query` already imported). One file.
- [x] [MED] `iptv-web/src/views/HomeView.vue` — the search-clear button at line 238 (`XMarkIcon` only, outside any form) lacks `type` and an accessible name. Add `type="button"` and `aria-label="Clear search"` to that `<button>`. One file.
- [x] [MED] `iptv-web/src/views/SeriesListView.vue` — the favorite-toggle `<button>` at line 207 has no `type` (defaults submit, not in a form). Add `type="button"`, keeping its `@click.stop`/`:title`/`:aria-label`. One file.
- [x] [MED] `iptv-web/src/views/SubscriptionView.vue` — the cancel-modal close button at line 365 (`XMarkIcon` only) has no accessible name. Add `aria-label="Close"` to that `<button>`. One file.
- [x] [MED] `iptv-web/src/stores/epg.ts` — two array refs assigned unguarded: line 38 `sources.value = await api.getEPGSources()` and line 129 `availableChannels.value = await api.getEPGChannels(sourceId)`. Harden both with `const res = await ...; x.value = Array.isArray(res) ? res : []` (mirror content.ts). One file.
- [x] [MED] `iptv-web/src/views/DiscoverView.vue` — eleven `<button>`s lack `type` (lines 281, 317, 352, 370, 379, 399, 429, 476, 486, 502, 517), none in a form. Add `type="button"` to each. Don't change handlers/directives/classes. One file.
- [x] [LOW] `iptv-web/src/views/GuideView.vue` — the program-details close button at line 600 (`XMarkIcon` only) has no accessible name. Add `aria-label="Close program details"`. One file.
- [x] [LOW] `iptv-web/src/views/ParentalView.vue` — two buttons lack `type`: PIN submit (line 504) and block-stream (line 558), neither in a form. Add `type="button"` to both. One file.
- [x] [HIGH] `iptv-backend/app/services/stream_discovery_service.py` — replace `datetime.utcnow()` in the six SERIALIZED-OUTPUT lines ONLY: 54, 91 (`update_time`), 115, 209 (`generated_at`), 237 (`added_at`), 327 (`analyzed_at`) — all `.isoformat()` — with `datetime.now(timezone.utc).isoformat()`, and update the import on line 5 to `from datetime import datetime, timedelta, timezone`. Do NOT touch line 58 `since = datetime.utcnow() - timedelta(...)` (window comparison). One file.
- [x] [MED] `iptv-web/src/views/HomeView.vue` — add `type="button"` to every native `<button>` lacking it (lines 171, 188, 209, 217, 245, 263, 356, 363, 374). No `<form>` in the file. Attribute only. One file.
- [x] [MED] `iptv-web/src/stores/content.ts` — guard line 197 `history.value = result.items` -> `history.value = Array.isArray(result.items) ? result.items : []` (matching line 184). One file.
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [MED] {ts·validation·T2·test-covered} `iptv-web/src/stores/parental.ts` — guard line 145 `blockedStreams.value = result.items` -> `blockedStreams.value = Array.isArray(result.items) ? result.items : []`. One file.
- [x] [MED] `iptv-web/src/views/StreamDetailView.vue` — add `loading="lazy"` to the below-the-fold thumbnail `<img>` starting line 143 (`:src="streamsStore.currentStream.logo_url"`). Attribute only. One file.
- [x] [MED] `iptv-web/src/views/DiscoverView.vue` — add `loading="lazy"` to the below-the-fold channel-logo `<img>` starting line 423 (`:src="channel.logo_url"`). Attribute only. One file.
- [x] [MED] {vue·a11y·T1·test-covered} `iptv-web/src/views/GuideView.vue` — add `aria-label` to two icon-only time-nav buttons: line 407 (`@click="navigateTime(-hoursToShow)"`, add `aria-label="Previous time period"`) and line 411 (`@click="navigateTime(hoursToShow)"`, add `aria-label="Next time period"`). Each has only a Chevron icon. One file.
- [x] [MED] {vue·a11y·T1·test-covered} `iptv-web/src/views/ParentalView.vue` — add `aria-label="Unblock stream"` to the icon-only button on line 360 (`@click="unblockStream(block.id)"`, only a TrashIcon). One file.
- [x] [LOW] {vue·a11y·T1·test-covered} `iptv-web/src/views/LoginView.vue` — add `aria-hidden="true"` to the decorative loading-spinner `<svg>` starting line 121 (`animate-spin ... h-4 w-4` inside the submit button). One file.
- [x] [LOW] {vue·a11y·T1·test-covered} `iptv-web/src/views/RegisterView.vue` — add `aria-hidden="true"` to the decorative loading-spinner `<svg>` starting line 213 (`animate-spin ... h-4 w-4`). One file.
- [x] [LOW] {vue·a11y·T1·test-covered} `iptv-web/src/views/PlayerView.vue` — add `aria-hidden="true"` to the decorative loading-spinner `<svg>` on line 381 (`animate-spin h-12 w-12 text-white mx-auto`). One file.
- [x] [LOW] {vue·a11y·T1·test-covered} `iptv-web/src/views/ImportView.vue` — add `aria-hidden="true"` to the two decorative loading-spinner `<svg>` at line 378 (`v-if="xtreamLoading"`) and line 427 (`v-if="streamsStore.loading"`). One file.
- [x] [LOW] {py·typing·T1·test-covered} `iptv-backend/app/models/stream.py` — change `def __repr__(self):` (line 68) to `def __repr__(self) -> str:`. One file.
- [x] [LOW] {py·typing·T1·test-covered} `iptv-backend/app/models/settings.py` — change `def __repr__(self):` (line 27) to `def __repr__(self) -> str:`. One file.
- [x] [LOW] {py·typing·T1·test-covered} `iptv-backend/app/models/watch_history.py` — change `def __repr__(self):` (line 42) to `def __repr__(self) -> str:`. One file.
- [x] [LOW] {py·typing·T1·test-covered} `iptv-backend/app/models/epg.py` — change the first `def __repr__(self):` (line 30) to `def __repr__(self) -> str:`. One file.
- [x] [LOW] {py·typing·T1·test-covered} `iptv-backend/app/models/subscription.py` — change `def __repr__(self):` (line 80) to `def __repr__(self) -> str:`. One file.
- [x] [LOW] {py·typing·T1·test-covered} `iptv-backend/app/models/content.py` — change `def mark_unwatched(self):` (line 173) to `def mark_unwatched(self) -> None:` (mutates state, returns nothing). One file.
- [x] [LOW] {py·typing·T1·test-covered} `iptv-backend/app/services/epg_analytics_service.py` — change `def __init__(self, db: Session):` (line 19) to `def __init__(self, db: Session) -> None:`. One file.
```

## Proposed (LLM re-evaluation — review before applying)
1. [MED] `iptv-web/src/stores/parental.ts` — guard line 145 `blockedStreams.value = result.items` with `Array.isArray(result.items) ? result.items : []` to prevent runtime errors from malformed API responses.
2. [MED] `iptv-backend/app/routers/epg_analytics.py` — verify the `limit` parameter on `/recommendations` (line 42) is constrained with `Query(10, ge=1, le=50)` and add similar constraints to any other unbounded integer query parameters in the file.
3. [MED] `iptv-web/src/views/StreamDetailView.vue` — add `loading="lazy"` to the thumbnail `<img>` tag (line 143) to improve initial page load performance.
4. [MED] `iptv-web/src/views/DiscoverView.vue` — add `loading="lazy"` to the channel-logo `<img>` tag (line 423) to improve initial page load performance.
5. [LOW] `iptv-backend/app/models/stream.py` — add `-> str` return type annotation to `__repr__` method (line 68) for type consistency.
6. [LOW] `iptv-backend/app/models/settings.py` — add `-> str` return type annotation to `__repr__` method (line 27) for type consistency.
7. [LOW] `iptv-backend/app/models/watch_history.py` — add `-> str` return type annotation to `__repr__` method (line 42) for type consistency.
8. [LOW] `iptv-backend/app/models/epg.py` — add `-> str` return type annotation to `__repr__` method (line 30) for type consistency.
9. [LOW] `iptv-backend/app/models/subscription.py` — add `-> str` return type annotation to `__repr__` method (line 80) for type consistency.
10. [LOW] `iptv-backend/app/models/content.py` — add `-> None` return type annotation to `mark_unwatched` method (line 173) for type consistency.
11. [LOW] `iptv-backend/app/services/epg_analytics_service.py` — add `-> None` return type annotation to `__init__` method (line 19) for type consistency.
