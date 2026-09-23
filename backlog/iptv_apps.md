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

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: paywallFeatures.ts empty-array edge case ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: ChannelLogo.vue missing test coverage ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: EngagementTrackingService.track_engagement orphaned static method ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: analytics content_id UUID/int type mismatch (broken endpoint) ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: discovery add-channel UUID/int type mismatch ---

# --- Claude-decomposed from roadmap [2026-09-22 refuel round 3]: orphaned duplicate youtube_admin.py router file ---

# --- research pass [2026-09-23]: coverage-gap + dead-code sweep, grounded via pytest --cov (backend) and npm run test:coverage (web) ---
- [ ] [T1] iptv-backend/app/jobs/notifications_job.py — Add `iptv-backend/tests/test_notifications_job.py` covering the happy path of `notification_enqueue_job()` and `notification_flush_job()` (0% coverage per `pytest --cov=app --cov-report=term-missing`; both are thin wrappers over the already-unit-tested `app.services.notifications.enqueue_renewal_reminders`/`flush_pending`, but the wrapper functions themselves have zero direct test coverage). VERIFY: cd iptv-backend && python -m pytest tests/test_notifications_job.py -v. (cat:test; multifile:no) [feat:iptv_apps-20260923-backend-coverage-sweep]
- [ ] [T1] iptv-backend/app/jobs/downloads_job.py — Add `iptv-backend/tests/test_downloads_job.py` covering `downloads_expiry_sweep_job()`'s happy path (mock `sweep_expired_downloads` to return a count and assert the job returns it and closes the session) — 42% coverage per `pytest --cov=app --cov-report=term-missing`, only the defensive except-branch is `# pragma: no cover`'d, the actual happy path has no test. VERIFY: cd iptv-backend && python -m pytest tests/test_downloads_job.py -v. (cat:test; multifile:no) [feat:iptv_apps-20260923-backend-coverage-sweep]
- [ ] [T1] iptv-backend/app/jobs/youtube_channel_job.py — Add `iptv-backend/tests/test_youtube_channel_job.py` covering `youtube_channel_check_job()`'s happy path (mock `YouTubeChannelChecker.check_all_channels` to return a summary dict, assert the job returns it) — 46% coverage per `pytest --cov=app --cov-report=term-missing`; the underlying checker is unit-tested but this thin wrapper is not. VERIFY: cd iptv-backend && python -m pytest tests/test_youtube_channel_job.py -v. (cat:test; multifile:no) [feat:iptv_apps-20260923-backend-coverage-sweep]
- [ ] [T1] iptv-backend/app/jobs/youtube_channel_accurate_job.py — Add `iptv-backend/tests/test_youtube_channel_accurate_job.py` covering `youtube_channel_accurate_check_job()`'s happy path (mock `YouTubeChannelChecker.check_all_channels_accurate`) — same 46%-coverage gap as the sibling `youtube_channel_job.py`. VERIFY: cd iptv-backend && python -m pytest tests/test_youtube_channel_accurate_job.py -v. (cat:test; multifile:no) [feat:iptv_apps-20260923-backend-coverage-sweep]
- [ ] [T3] iptv-backend/app/routers/discover.py — `get_personalized_recommendations()`'s genre-matching/scoring block (~lines 534-598: skip NSFW/closed/malformed channels, skip denylisted names, skip Xtream-session URLs and channels already in the user's library, match against `top_genre_set`, sort by matched-genre count) is completely untested — `pytest --cov=app --cov-report=term-missing` shows lines 534-610 uncovered even though the endpoint's caching/auth paths are tested elsewhere. Add `test_recommends_channel_matching_top_genre`, `test_excludes_denylisted_or_nsfw_channel`, and `test_excludes_channel_already_in_library` to `iptv-backend/tests/test_discover_personalized_cache.py`. VERIFY: cd iptv-backend && python -m pytest tests/test_discover_personalized_cache.py -k "matching_top_genre or denylisted_or_nsfw or already_in_library" -v. (cat:test; multifile:no) [feat:iptv_apps-20260923-backend-coverage-sweep]
- [ ] [T2] iptv-backend/app/services/parental.py — `extract_test_function_names()`, `compare_test_functions()`, and `verify_test_integrity()` (lines 43-88) have nothing to do with parental-rating logic (the module's own docstring says its purpose is just the `is_rating_allowed()` wrapper) and are not called by any script or CI gate anywhere in the repo — confirmed via `grep -rn 'extract_test_function_names\|compare_test_functions\|verify_test_integrity' app/ tests/`, the only hits besides the 3 definitions are their own tests in the unrelated `tests/test_parental_controls.py`. Move them to a dedicated module (e.g. `app/services/test_integrity.py`, updating the two call sites in `tests/test_parental_controls.py`) or delete if this test-tooling was abandoned. VERIFY: ! grep -q "def extract_test_function_names" iptv-backend/app/services/parental.py. (cat:python; multifile:yes) [feat:iptv_apps-20260923-backend-coverage-sweep]

# --- research pass [2026-09-23]: web Pinia store coverage gaps, grounded via npm run test:coverage ---
- [ ] [T1] iptv-web/src/stores/content.ts — `removeFromHistory(contentId)` (lines 207-217, called live from `HistoryView.vue`) has zero test coverage in `iptv-web/src/stores/__tests__/content.test.ts` — file is 50.53% covered per `npm run test:coverage`, and its sibling actions `fetchHistory`/`clearHistory` both already have tests but this one doesn't. Add a test asserting it calls `api.deleteContentFromHistory`, removes the matching item from `history` and `continueWatching`, and decrements `historyTotal`. VERIFY: cd iptv-web && npx vitest run src/stores/__tests__/content.test.ts -t "removeFromHistory". (cat:test; multifile:no) [feat:iptv_apps-20260923-web-store-coverage]
- [ ] [T2] iptv-web/src/stores/parental.ts — `setupPIN()`, `removePIN()`, `blockStream()`, `unblockStream()`, and `fetchBlockedStreams()` (all called live from `ParentalView.vue`) are only referenced as `vi.fn()` mocks of the `api` module in `iptv-web/src/stores/__tests__/parental.test.ts` — none of the store actions themselves are ever invoked in a test, leaving this security-relevant PIN/blocking logic at 62.13% coverage per `npm run test:coverage`. Add tests that call each store action directly and assert on resulting state (`blockedStreams`, `error`) and the API call args. VERIFY: cd iptv-web && npx vitest run src/stores/__tests__/parental.test.ts -t "setupPIN|blockStream|unblockStream". (cat:test; multifile:no) [feat:iptv_apps-20260923-web-store-coverage]
- [ ] [T2] iptv-web/src/stores/epg.ts — `refreshSource()`, `createMapping()`, `removeMapping()`, `autoMapSource()`, and `fetchAvailableChannels()` (all called live from `GuideView.vue`) have no direct test in `iptv-web/src/stores/__tests__/epg.test.ts` — only `fetchSources`/`addSource`/`removeSource`/`getCurrentProgram`/`reset` are tested, leaving the file at 62.71% coverage per `npm run test:coverage`. Add tests invoking each of the five untested actions and asserting the resulting store state / API call. VERIFY: cd iptv-web && npx vitest run src/stores/__tests__/epg.test.ts -t "refreshSource|createMapping|autoMapSource". (cat:test; multifile:no) [feat:iptv_apps-20260923-web-store-coverage]
