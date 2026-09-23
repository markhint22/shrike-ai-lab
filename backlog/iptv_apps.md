# iptv_apps (Chickadee) — pre-decomposed release-polish backlog (27B-friendly)
# queue_refill.py pulls [T1-T5] items from here into OVERNIGHT_PROGRESS.md when doable is low.
# Each item is ONE file, a spec (not a goal), and self-verifying. Add more over time.


# --- next-year roadmap decomposition (2026-09-05): downloads / EPG-push / recommendations ---

# --- COMPETITIVE 2026-09-06: Chickadee vs Fubo/YouTubeTV/Sling — close DVR/multi-stream/VOD gaps + beat their gripes ---
# Cloud DVR (EVERY competitor has it; Chickadee lacks it — the #1 gap)
# Multiple simultaneous streams (Fubo 10, YouTube TV 3; Chickadee should expose a plan limit)
# VOD / on-demand (Sling Freestream advertises 40k titles; Chickadee is live-only)
# Beat their gripes: buffering (Fubo/Sling) + billing-cancellation friction (Fubo)

# --- 27B-decomposed from roadmap [2026-09-08]: Cloud DVR — record/list/delete, retention policy, RecordingsView — every rival has it {cat (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-08]: VOD / on-demand catalog + tab — Sling Freestream angle {cat: backend+web; size: M; multifi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-08]: Multiple simultaneous streams (plan-based limit + 409 guard) {cat: backend; size: S; multi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: Reliable playback: rebuffer backoff, error recovery, cast/AirPlay hardening {cat: web+mobi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: Easy self-serve cancellation + billing transparency (beat competitor gripes) {cat: web+bac (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: App Store + Play Store submission blockers — RevenueCat is already SDK-wired for iOS/Andro (review + tweak) ---
- [ ] [T2] iptv-backend/app/routers/streams.py — Update stream import endpoint to enforce `validate_content_rights` before processing M3U/Xtream imports. VERIFY: pytest tests/test_streams_import_guard.py::test_unlicensed_import_blocked -q (cat:endpoint; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-10]: YouTube support follow-through — an MVP already exists (curated news/government/space/loca (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Watchlist/Continue-watching parity across web + mobile {cat: web+mobile; size: M; multifil (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Profiles + parental controls depth; kids mode — Chickadee already has `Profile`/`ParentalS (review + tweak) ---
- [ ] [T1] iptv-backend/app/services/parental_rating_gate.py — Implement `is_content_allowed(rating: str, kid_max_rating: str, blocked_categories: list[str]) -> bool` using the existing hierarchy map. VERIFY: python -m pytest iptv-backend/tests/test_parental_rating_gate.py::test_is_content_allowed_blocks_higher_rating -q. (cat:python; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-10]: Profiles + parental controls depth; kids mode — Chickadee already has `Profile`/`ParentalS (review + tweak) ---
- [ ] [T1] iptv-backend/app/services/parental_rating_gate.py — Add `is_content_allowed(rating: str, kid_max_rating: str, blocked_categories: list[str])` pure function that returns False if rating exceeds max or category is blocked. VERIFY: pytest iptv-backend/tests/test_parental_rating_gate.py::test_is_content_allowed_blocks_higher_rating -q. (cat:python; multifile:no)
- [ ] [T2] iptv-backend/app/services/parental_rating_gate.py — Add `filter_streams_for_profile(streams: list[dict], profile: dict)` pure function that applies rating and category filters to a stream list. VERIFY: pytest iptv-backend/tests/test_parental_rating_gate.py::test_filter_streams_for_profile_excludes_blocked -q. (cat:python; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-10]: Personalized discover/recommendations — Chickadee's `StreamDiscoveryService` already expos (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Personalized discover/recommendations — Chickadee's `StreamDiscoveryService` already expos (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Fix admin YouTube-channels endpoint reading from the wrong, dead model — iptv-backend/app/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Add dialog semantics + Escape-close to DiscoverView's YouTube playback modal — iptv-web/sr (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add test coverage for StreamFilterBar's country/category auto-clear logic — iptv-web/src/c (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire the already-implemented download-quota helper into the real quota check instead of a  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Cap unbounded watch-history row growth using the existing (never-called) trim helper — ipt (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire the already-implemented reminder fire-time helper into the real due-reminder check —  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire the already-implemented, already-tested search tokenizer into the real search endpoin (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Surface the stream-fetch error instead of silently swallowing it in tvOS Guide/History — i (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add unit tests for Android's WatchlistViewModel — iptv-android/app/src/main/java/com/chick (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Dedupe the duplicated `order_groups` function in playlist_group_order.py and wire it into  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-15]: Wire the already-implemented, already-tested display-title cleaner into the actual stream- (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-15]: Wire the already-implemented, already-tested exponential-backoff helper into the player's  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-16]: Add unit tests for Android's revenue-critical PaywallViewModel — iptv-android/app/src/main (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-16]: Make iOS WatchlistViewModel dependency-injectable and add its first unit tests — iptv-ios/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Wire the backend's already-implemented EPG auto-map endpoint into Android and iOS's EPG "A (review + tweak) ---
- [ ] [T3] iptv-ios/ChickadeeStreams/Services/APIService+Extended.swift — Modify `addEPGSource()` to call `autoMap(sourceId:)` in a `Task` or `fire-and-forget` manner after successful source addition, ensuring the main flow is not blocked by potential auto-map latency. VERIFY: `grep -A 10 "func addEPGSource" iptv-ios/ChickadeeStreams/Services/APIService+Extended.swift | grep -q "autoMap"`. (cat:ios; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-17]: Wire the already-implemented, already-tested favorites/watchlist ordering helper into a re (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Finish the partially-landed cleanDisplayTitle wiring — HomeView.vue still shows raw M3U-im (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Android targetSdk is still 34; Google Play requires 36 for new-app submissions as of a dea (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: tvOS paywall (TVPaywallView.swift) can never show real subscription offerings — RevenueCat (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Populate or remove the empty, dead `stream_resilience.py` stub left by a failed staged fle (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Fix the orphaned empty `app/schemas/discovery.py` and give the personalized/similar/genre/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Handle the unhandled `IntegrityError` race on concurrent favorite/watchlist adds instead o (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: iOS live-TV forward/back-10s skip buttons are silently broken — seekForward always seeks t (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Profile-switch PIN unlock has no brute-force lockout, unlike the parallel parental-control (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Delete dead, untested, duplicate download-expiry helper functions left in `app/jobs/downlo (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: The search endpoint completely bypasses the per-kid-profile parental rating ceiling that e (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Three independently-maintained adult/mature keyword lists have drifted apart, so the gener (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: `iptv-backend/app/utils/playback.py`'s `calculate_backoff_delay()` is dead code — zero cal (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-21]: iOS and Android's "Favorites" screens still write to the legacy per-STREAM `is_favorite` f (review + tweak) [feat:iptv_apps-20260921-ios-and-android-s-favorites-screens-stil] ---

# --- 27B-decomposed from roadmap [2026-09-21]: iOS and Android's "Favorites" screens still write to the legacy per-STREAM `is_favorite` f (review + tweak) [feat:iptv_apps-20260921-ios-and-android-s-favorites-screens-stil] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `add_to_watchlist()` and `mark_watchlist_watched()` still return a raw 409 on a concurrent (review + tweak) [feat:iptv_apps-20260921-add-to-watchlist-and-mark-watchlist-watc] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Two unused, never-imported stall-retry duplicates were left behind after `PlayerView.vue`' (review + tweak) [feat:iptv_apps-20260921-two-unused-never-imported-stall-retry-du] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `auth.py` has two back-to-back `_resolve_secret_key` definitions — the first is a docstrin (review + tweak) [feat:iptv_apps-20260921-auth-py-has-two-back-to-back-resolve-sec] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `test_health.py` has two functions both named `test_status_endpoint` — Python silently kee (review + tweak) [feat:iptv_apps-20260921-test-health-py-has-two-functions-both-na] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `test_metrics.py` is the literal concatenation of 3 separate regenerated versions of itsel (review + tweak) [feat:iptv_apps-20260921-test-metrics-py-is-the-literal-concatena] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `test_parental_controls.py` defines the exact same test function three times back-to-back  (review + tweak) [feat:iptv_apps-20260922-test-parental-controls-py-defines-the-ex] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `test_stream_analytics_aggregation.py` defines `class TestEdgeCases` twice — the entire fi (review + tweak) [feat:iptv_apps-20260922-test-stream-analytics-aggregation-py-def] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `stream_import_guard.py` is an orphaned demo stub with hardcoded fake licensed-source IDs, (review + tweak) [feat:iptv_apps-20260922-stream-import-guard-py-is-an-orphaned-de] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Concurrent-stream-limit enforcement — the P1 roadmap item "Multiple simultaneous streams (plan-based limit + 409 guard)" is still unimplemented. `iptv-backend/app/services/stream_limit.py`'s `can_start(active_count, plan_max)`/`remaining(active_count, plan_max)` are fully implemented and unit-tested but have ZERO call sites anywhere in app/ (confirmed via `grep -rn 'can_start\b' app/` matching only the module itself) — there is no active-playback-session tracking anywhere in the backend and no endpoint ever returns 409 for exceeding a concurrent-stream cap; `get_stream_limit()` in app/services/premium.py is only used today to cap how many streams a user can ADD to their library (app/routers/discover.py ~line 873, a 403), a completely different concept from concurrently PLAYING streams. (review + tweak) [feat:iptv_apps-20260922-concurrent-stream-limit-enforcement] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Chromecast failures are silently swallowed on web — `iptv-web/src/composables/useChromecast.ts`'s `castMedia()` sets `error.value` on a caught exception (e.g. "Failed to start casting"), but `grep -n "chromecast.error" iptv-web/src/views/PlayerView.vue` returns nothing — the composable's `error` ref is never read/displayed anywhere, so a failed cast attempt just does nothing visible to the user. This is the concrete remaining gap behind the roadmap's still-open "cast/AirPlay hardening" P2 item. (review + tweak) [feat:iptv_apps-20260922-chromecast-error-surfacing] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Replace leftover `print()` startup/shutdown logging in `iptv-backend/app/main.py` with the app's real `logging` module — the file already imports and configures logging elsewhere in the codebase, but `startup_check`-equivalent lifecycle code (confirmed via `grep -n '^\s*print(' app/main.py`, 16 call sites e.g. lines 39/74/87/109/162) uses bare `print()` for init/shutdown status messages instead, so none of this ever reaches real log aggregation/log level filtering in production. (review + tweak) [feat:iptv_apps-20260922-replace-print-with-logging-in-main-py] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Replace a leftover `console.log` debug statement in the player's CORS-proxy retry path — `iptv-web/src/views/PlayerView.vue` line 300 has `console.log('Stream failed, automatically retrying with CORS proxy...')`, the only production `console.log` call in `src/views` (confirmed via `grep -rln 'console\.log(' src --include='*.vue' --include='*.ts' | grep -v __tests__ | grep -v '.test.ts'` returning only this file). (review + tweak) [feat:iptv_apps-20260922-remove-console-log-in-playerview] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Add unit tests for Android's TvDeviceCodeViewModel — the only ViewModel in `iptv-android/app/src/main/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/TvDeviceCodeViewModel.kt` without a matching test file (confirmed via `find iptv-android/app/src/main -iname '*ViewModel.kt'` vs `find iptv-android/app/src/test -iname '*ViewModelTest.kt'` — every other ViewModel in this directory has one). (review + tweak) [feat:iptv_apps-20260922-tvdevicecodeviewmodel-tests] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Add missing test coverage for ChannelLogo.vue and countryUtils.ts — the only component under src/components with no matching test file, and the only utils module with no matching test file (both confirmed via a find-based diff against their sibling directories' test coverage). (review + tweak) [feat:iptv_apps-20260922-channellogo-and-countryutils-tests] ---

# --- 27B-decomposed from roadmap [2026-09-22]: The VOD catalog endpoint completely bypasses the per-kid-profile parental rating ceiling that streams.py and (now) search.py both enforce — `iptv-backend/app/routers/content.py`'s `get_vod_catalog()` (~line 492) and `GET /vod` (`get_vod_streams`, ~line 523) filter only by `Stream.user_id`/`stream_type == "vod"` with NO `MATURE_CATEGORY_KEYWORDS`/`profile_rating_ceiling`/`include_adult` logic anywhere in the function (confirmed via direct read — zero such references exist in this file, unlike `app/routers/streams.py` which applies both an adult-keyword filter and a `profile_rating_ceiling()`-gated mature-category filter). A kid profile that's correctly blocked from mature content in the live-TV grid can browse the VOD/movie catalog and see the exact same mature-rated titles unfiltered. (review + tweak) [feat:iptv_apps-20260922-vod-catalog-parental-gate] ---

# --- 27B-decomposed from roadmap [2026-09-22]: All ten discovery-engine endpoints (trending/personalized/similar/genre/feed/etc.) completely bypass the per-kid-profile parental rating ceiling too — `iptv-backend/app/routers/discovery_api.py` (confirmed via `grep -n 'MATURE_CATEGORY\|profile_rating_ceiling\|include_adult\|active_profile'`, zero hits across all 10 route handlers) never filters recommendations by rating or category at all, the same root-cause pattern already found and fixed once for search.py and once above for content.py's VOD catalog. A kid profile's "For You"/trending/similar-channel recommendations can surface mature-rated content that the same profile is blocked from browsing directly. (review + tweak) [feat:iptv_apps-20260922-discovery-api-parental-gate] ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: content.py service dead get_vod_catalog stub ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: continue_watching_filter.py dead calculate_continue_watching_threshold ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: triple-duplicate unwired stream/session concurrency-limit implementations ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: wire cleanDisplayTitle into 6 remaining raw-title display sites ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: cleanDisplayTitle Hello->Hey bug ---
- [ ] [T2] iptv-web/src/utils/__tests__/cleanDisplayTitle.test.ts — Add a second case asserting a "Hello"-prefixed title still gets its OTHER real transformations applied, e.g. `cleanDisplayTitle('Hello.Channel.720p.HDTV')` equals `'Hello Channel'`. VERIFY: `cd iptv-web && npx vitest run cleanDisplayTitle`. (cat:test; multifile:no) [feat:iptv_apps-20260922-clean-display-title-hello-hey-bug]
- [ ] [T3] iptv-web — Run the full vitest suite once to confirm zero regressions from removing the Hello/Hey block. VERIFY: `cd iptv-web && npx vitest run`. (cat:test; multifile:no) [feat:iptv_apps-20260922-clean-display-title-hello-hey-bug]

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: paywallFeatures.ts empty-array edge case ---
- [ ] [T1] iptv-web/src/utils/__tests__/paywallFeatures.test.ts — Add `it('falls back to defaults when config.features is an empty array', ...)` asserting `getFeatures({ features: [] })` equals `DEFAULT_PAYWALL_FEATURES`, documenting the desired (fixed) behavior. VERIFY: `cd iptv-web && npx vitest run paywallFeatures -t "empty array"`. (cat:test; multifile:no) [feat:iptv_apps-20260922-paywall-features-empty-array-edge-case]
- [ ] [T1] iptv-web/src/utils/paywallFeatures.ts — Fix `getFeatures()` so an empty `config.features` array falls back to `DEFAULT_PAYWALL_FEATURES` the same as null/undefined: change `config?.features?.slice(0, 4) ?? DEFAULT_PAYWALL_FEATURES` to check `config?.features?.length ? config.features.slice(0, 4) : DEFAULT_PAYWALL_FEATURES`. VERIFY: `cd iptv-web && npx vitest run paywallFeatures`. (cat:typescript; multifile:no) [feat:iptv_apps-20260922-paywall-features-empty-array-edge-case]
- [ ] [T2] iptv-web/src/utils/paywallFeatures.ts — Update the `getFeatures` docstring to document the new empty-array fallback behavior explicitly. VERIFY: `grep -q "empty" iptv-web/src/utils/paywallFeatures.ts`. (cat:docs; multifile:no) [feat:iptv_apps-20260922-paywall-features-empty-array-edge-case]

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: ChannelLogo.vue missing test coverage ---
- [ ] [T1] iptv-web/src/components/__tests__/ChannelLogo.test.ts — Create new test file; add `it('renders the img when src is provided', ...)` mounting with a valid `src` prop and asserting an `<img>` is present. VERIFY: `cd iptv-web && npx vitest run ChannelLogo`. (cat:test; multifile:no) [feat:iptv_apps-20260922-channellogo-test-coverage]
- [ ] [T2] iptv-web/src/components/__tests__/ChannelLogo.test.ts — Add `it('falls back to TvIcon when src is null', ...)` mounting with `src: null` and asserting no `<img>` renders. VERIFY: `cd iptv-web && npx vitest run ChannelLogo`. (cat:test; multifile:no) [feat:iptv_apps-20260922-channellogo-test-coverage]
- [ ] [T2] iptv-web/src/components/__tests__/ChannelLogo.test.ts — Add `it('falls back to TvIcon after the img error handler fires', ...)` triggering the `@error` event on the `<img>` and asserting it is then hidden. VERIFY: `cd iptv-web && npx vitest run ChannelLogo`. (cat:test; multifile:no) [feat:iptv_apps-20260922-channellogo-test-coverage]
- [ ] [T3] iptv-web/src/components/__tests__/ChannelLogo.test.ts — Add `it('resets failed state and re-shows the img when src changes after a prior failure', ...)` triggering `@error` then updating the `src` prop, asserting the `<img>` reappears. VERIFY: `cd iptv-web && npx vitest run ChannelLogo`. (cat:test; multifile:no) [feat:iptv_apps-20260922-channellogo-test-coverage]
- [ ] [T3] iptv-web/src/components/__tests__/ChannelLogo.test.ts — Add `it('applies the custom size class prop, defaulting to w-9 h-9', ...)` asserting the root div's class list. VERIFY: `cd iptv-web && npx vitest run ChannelLogo`. (cat:test; multifile:no) [feat:iptv_apps-20260922-channellogo-test-coverage]
- [ ] [T4] iptv-web — Run the full vitest suite once to confirm the new test file causes zero regressions elsewhere. VERIFY: `cd iptv-web && npx vitest run`. (cat:test; multifile:no) [feat:iptv_apps-20260922-channellogo-test-coverage]

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: EngagementTrackingService.track_engagement orphaned static method ---
- [ ] [T1] iptv-backend/app/services/engagement_tracking_service.py — Add a module/method-level note above `track_engagement()` documenting that it currently has zero router callers (confirmed via `grep -rn "track_engagement" app/routers`) so a future reader knows this is a deliberately-flagged gap, not an oversight, pending a product decision on whether to wire or delete it. VERIFY: `grep -q "zero router callers" iptv-backend/app/services/engagement_tracking_service.py`. (cat:docs; multifile:no) [feat:iptv_apps-20260922-orphaned-track-engagement-method]
- [ ] [T2] iptv-backend/tests/test_engagement_tracking_service.py — Run to confirm the existing direct-call tests for `track_engagement` still pass unaffected by the docstring addition. VERIFY: `cd iptv-backend && pytest tests/test_engagement_tracking_service.py -v`. (cat:test; multifile:no) [feat:iptv_apps-20260922-orphaned-track-engagement-method]
- [ ] [T2] iptv-backend/tests/test_analytics_services.py — Run to confirm `test_track_engagement_returns_ack` still passes unaffected. VERIFY: `cd iptv-backend && pytest tests/test_analytics_services.py -k track_engagement -v`. (cat:test; multifile:no) [feat:iptv_apps-20260922-orphaned-track-engagement-method]
- [ ] [T3] iptv-backend/app/routers/engagement.py — Add a router-file-level comment listing the two currently-wired GET endpoints and noting `EngagementTrackingService.track_engagement()` exists but is intentionally not yet exposed here pending a product decision. VERIFY: `grep -q "track_engagement" iptv-backend/app/routers/engagement.py`. (cat:docs; multifile:no) [feat:iptv_apps-20260922-orphaned-track-engagement-method]

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: analytics content_id UUID/int type mismatch (broken endpoint) ---
- [ ] [T1] iptv-backend/app/routers/stream_analytics.py — Change `get_content_performance()`'s `content_id: UUID` path parameter to `content_id: int`, matching `Stream.id`'s real Integer primary key. VERIFY: `! grep -q "content_id: UUID" iptv-backend/app/routers/stream_analytics.py`. (cat:python; multifile:no) [feat:iptv_apps-20260922-analytics-content-uuid-int-mismatch]
- [ ] [T1] iptv-backend/app/routers/stream_analytics.py — Update the `.get_content_performance(str(content_id))` call to pass the now-int `content_id` consistently (still stringified for the service's `str`-typed parameter, matching `stream_discovery_service.py`'s existing `str(channel_id)` convention). VERIFY: `grep -n "get_content_performance(str(content_id))" iptv-backend/app/routers/stream_analytics.py`. (cat:python; multifile:no) [feat:iptv_apps-20260922-analytics-content-uuid-int-mismatch]
- [ ] [T2] iptv-backend/tests/test_stream_analytics_router.py — Create new test file with `test_get_content_performance_accepts_integer_stream_id` using FastAPI `TestClient` to call `GET /api/analytics/content/1` for real through the router (not the service directly) and assert the response is NOT a 422. VERIFY: `cd iptv-backend && pytest tests/test_stream_analytics_router.py -v`. (cat:test; multifile:no) [feat:iptv_apps-20260922-analytics-content-uuid-int-mismatch]
- [ ] [T3] iptv-backend/tests/test_stream_analytics_router.py — Add `test_get_content_performance_rejects_non_numeric_id` asserting a non-numeric path segment (e.g. `/api/analytics/content/abc`) still correctly 422s (the fix narrows the accepted type, it should not silently accept everything). VERIFY: `cd iptv-backend && pytest tests/test_stream_analytics_router.py -v`. (cat:test; multifile:no) [feat:iptv_apps-20260922-analytics-content-uuid-int-mismatch]
- [ ] [T3] iptv-backend/tests/test_stream_analytics_aggregation.py — Run the existing service-level tests to confirm they remain valid and unaffected (they call the service directly with string IDs, unaffected by the router-level type change). VERIFY: `cd iptv-backend && pytest tests/test_stream_analytics_aggregation.py -v`. (cat:test; multifile:no) [feat:iptv_apps-20260922-analytics-content-uuid-int-mismatch]
- [ ] [T4] iptv-backend — Run the full backend test suite once to confirm zero regressions from the router-level type-signature fix. VERIFY: `cd iptv-backend && pytest tests/ -q`. (cat:test; multifile:no) [feat:iptv_apps-20260922-analytics-content-uuid-int-mismatch]

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: discovery add-channel UUID/int type mismatch ---
- [ ] [T1] iptv-backend/app/routers/discovery_api.py — Change `AddChannelRequest.channel_id: UUID` to `channel_id: int`, matching the sibling `/similar/{channel_id}: int` endpoint in the same file. VERIFY: `! grep -q "channel_id: UUID" iptv-backend/app/routers/discovery_api.py`. (cat:python; multifile:no) [feat:iptv_apps-20260922-discovery-add-channel-uuid-int-mismatch]
- [ ] [T1] iptv-backend/app/services/stream_discovery_service.py — Change `add_channel_to_recommendations()`'s `channel_id: UUID` parameter to `channel_id: int` to match the router-level fix. VERIFY: `! grep -q "channel_id: UUID" iptv-backend/app/services/stream_discovery_service.py`. (cat:python; multifile:no) [feat:iptv_apps-20260922-discovery-add-channel-uuid-int-mismatch]
- [ ] [T2] iptv-backend/tests/test_discovery_api.py — Create or extend with `test_add_channel_accepts_integer_channel_id` posting `{"channel_id": 1, "genres": ["news"]}` to `POST /api/discovery/channels/add` via FastAPI `TestClient` and asserting no 422. VERIFY: `cd iptv-backend && pytest tests/test_discovery_api.py -v`. (cat:test; multifile:no) [feat:iptv_apps-20260922-discovery-add-channel-uuid-int-mismatch]
- [ ] [T3] iptv-backend/tests/test_discovery_api.py — Add `test_add_channel_requires_genres_list` asserting the existing `Field(..., max_length=50)` genres-list requirement still 422s when omitted (regression guard that the type fix didn't loosen other validation). VERIFY: `cd iptv-backend && pytest tests/test_discovery_api.py -v`. (cat:test; multifile:no) [feat:iptv_apps-20260922-discovery-add-channel-uuid-int-mismatch]
- [ ] [T4] iptv-backend — Run the full backend test suite once to confirm zero regressions from the two type-signature fixes. VERIFY: `cd iptv-backend && pytest tests/ -q`. (cat:test; multifile:no) [feat:iptv_apps-20260922-discovery-add-channel-uuid-int-mismatch]

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: orphaned duplicate youtube_admin.py router file ---
- [ ] [T1] iptv-backend/app/routers/youtube_admin.py — Delete this entire file; it is never imported/registered in `app/main.py` (only `app/routers/admin_youtube.py`'s `admin_youtube_router` is), has no tests, and is a confusingly-near-identically-named dead duplicate of the real, wired admin YouTube router. VERIFY: `test ! -f iptv-backend/app/routers/youtube_admin.py`. (cat:python; multifile:no) [feat:iptv_apps-20260922-orphaned-youtube-admin-router-dupe]
- [ ] [T2] iptv-backend/app/main.py — Confirm `admin_youtube_router` is still imported exactly once (from `app.routers.admin_youtube`, the real one) and the app still starts. VERIFY: `grep -c "admin_youtube_router" iptv-backend/app/main.py` returns 1. (cat:python; multifile:no) [feat:iptv_apps-20260922-orphaned-youtube-admin-router-dupe]
- [ ] [T2] iptv-backend — Run the full backend test suite once to confirm deleting the never-imported orphan causes zero regressions. VERIFY: `cd iptv-backend && pytest tests/ -q`. (cat:test; multifile:no) [feat:iptv_apps-20260922-orphaned-youtube-admin-router-dupe]
