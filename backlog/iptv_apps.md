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

# --- research pass [2026-09-23]: web Pinia store coverage gaps, grounded via npm run test:coverage ---
- [ ] [T2] iptv-web/src/stores/parental.ts — `setupPIN()`, `removePIN()`, `blockStream()`, `unblockStream()`, and `fetchBlockedStreams()` (all called live from `ParentalView.vue`) are only referenced as `vi.fn()` mocks of the `api` module in `iptv-web/src/stores/__tests__/parental.test.ts` — none of the store actions themselves are ever invoked in a test, leaving this security-relevant PIN/blocking logic at 62.13% coverage per `npm run test:coverage`. Add tests that call each store action directly and assert on resulting state (`blockedStreams`, `error`) and the API call args. VERIFY: cd iptv-web && npx vitest run src/stores/__tests__/parental.test.ts -t "setupPIN|blockStream|unblockStream". (cat:test; multifile:no) [feat:iptv_apps-20260923-web-store-coverage]

# --- research pass [2026-09-23 round 2]: native-client (Android/iOS) API-parity sweep + backend dead-table/dead-model sweep, grounded via direct grep across iptv-backend/iptv-android/iptv-ios (no coverage tooling this round) ---







- [ ] [T3] iptv-android/app/src/main/java/com/chickadeestreams/iptv/data/api/ChickadeeApi.kt — Android's parental-controls surface is read/PIN-only and missing most of the backend's actual enforcement API: only `GET /settings`, `GET /pin/session`, `POST /pin/setup`, `POST /pin/verify` are declared (4 of 13 routes on `iptv-backend/app/routers/parental.py`). Missing entirely: `PUT /settings` (update restriction config), `DELETE /pin` (remove PIN), `GET/POST /blocked` + `DELETE /blocked/{stream_id}` (per-stream blocking — the actual parental block/unblock feature), `POST /check` (content-rating check), `POST /usage` + `GET /limit` + `GET /time-check` (daily screen-time limits). Android users can set up a parental PIN but can never block/unblock an individual stream or have daily time limits enforced client-side. VERIFY: `grep -c "api/parental/" iptv-android/app/src/main/java/com/chickadeestreams/iptv/data/api/ChickadeeApi.kt` (currently 4; backend has 13 distinct `@router.` routes in `parental.py`). (cat:android; multifile:yes) [feat:iptv_apps-20260923-android-parental-endpoints-gap]

# --- research pass [2026-09-24]: 3rd starvation streak, grounded via fresh pytest --cov (backend) + direct grep across iptv-backend/iptv-ios (iOS given deeper look per instructions) ---

# --- 27B-decomposed from roadmap [2026-09-25]: Self-service password-reset flow — `iptv-backend/app/routers/auth.py` exposes exactly five (review + tweak) [feat:iptv_apps-20260925-self-service-password-reset-flow-iptv-ba] ---

# --- 27B-decomposed from roadmap [2026-09-25]: Account data export + self-service account deletion — confirmed via repo-wide grep that ze (review + tweak) [feat:iptv_apps-20260925-account-data-export-self-service-account] ---

# --- 27B-decomposed from roadmap [2026-09-25]: iOS Privacy Manifest (`PrivacyInfo.xcprivacy`) is missing entirely — a real, current App S (review + tweak) [feat:iptv_apps-20260925-ios-privacy-manifest-privacyinfo-xcpriva] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Failed-payment dunning + subscription win-back emails — confirmed via grep that zero `dunn (review + tweak) [feat:iptv_apps-20260926-failed-payment-dunning-subscription-win-] ---

# --- 27B-decomposed from roadmap [2026-09-26]: In-app store-rating prompt — confirmed via grep that no `SKStoreReviewController`/`request (review + tweak) [feat:iptv_apps-20260926-in-app-store-rating-prompt-confirmed-via] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Email verification on registration — `iptv-backend/app/models/user.py`'s `User` model has  (review + tweak) [feat:iptv_apps-20260926-email-verification-on-registration-iptv-] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Self-service change-email — `iptv-backend/app/routers/settings.py`'s `GET`/`PUT /api/setti (review + tweak) [feat:iptv_apps-20260926-self-service-change-email-iptv-backend-a] ---

# --- 27B-decomposed from roadmap [2026-09-27]: [NEEDS HUMAN/CLAUDE PRODUCT DESIGN — do not decompose to 27B as-is] Referral / invite-a-fr (review + tweak) [feat:iptv_apps-20260927-needs-human-claude-product-design-do-not] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Add an SSRF guard for every server-side fetch of user-supplied URLs — iptv-backend/app/rou (review + tweak) [feat:iptv_apps-20260930-add-an-ssrf-guard-for-every-server-side-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: RevenueCat webhook strips Premium from a paying user the moment they turn off auto-renew,  (review + tweak) [feat:iptv_apps-20260930-revenuecat-webhook-strips-premium-from-a] ---

# --- 27B-decomposed from roadmap [2026-09-30]: DELETE /api/account/me will fail with an FK IntegrityError (HTTP 500) on Postgres for any  (review + tweak) [feat:iptv_apps-20260930-delete-api-account-me-will-fail-with-an-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: The slowapi rate limiter is created but never applied, so login, register, password reset, (review + tweak) [feat:iptv_apps-20260930-the-slowapi-rate-limiter-is-created-but-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Stop putting the full 8-hour access JWT in playback URLs — iptv-web/src/views/PlayerView.v (review + tweak) [feat:iptv_apps-20260930-stop-putting-the-full-8-hour-access-jwt-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Password reset/change cannot revoke existing sessions, and logout is a no-op — iptv-backen (review + tweak) [feat:iptv_apps-20260930-password-reset-change-cannot-revoke-exis] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Bound downloaded playlist/EPG size and XML/gzip expansion — iptv-backend/app/services/xmlt (review + tweak) [feat:iptv_apps-20260930-bound-downloaded-playlist-epg-size-and-x] ---
- [ ] [T1] iptv-backend/app/services/xmltv_parser.py — Add `MAX_EPG_BYTES` and `MAX_PLAYLIST_BYTES` environment variable loading with defaults (50MB) and a helper function `get_max_bytes(env_var, default)` to centralize limit retrieval. VERIFY: python -c "from app.services.xmltv_parser import get_max_bytes; assert get_max_bytes('MAX_EPG_BYTES', 100) == 100" (cat:python; multifile:no) [feat:iptv_apps-20260930-bound-downloaded-playlist-epg-size-and-x]
- [ ] [T2] iptv-backend/app/services/xmltv_parser.py — Refactor `parse_xmltv_bytes` to accept a `max_size` parameter and implement chunked reading for gzip streams that raises `ValueError` if decompressed size exceeds the limit, replacing unbounded `gz.read()`. VERIFY: python -m pytest tests/test_xmltv_parser.py::test_gzip_bomb_protection -v (cat:python; multifile:no) [feat:iptv_apps-20260930-bound-downloaded-playlist-epg-size-and-x]
- [ ] [T3] iptv-backend/app/services/xmltv_parser.py — Replace `xml.etree.ElementTree` imports and usage with `defusedxml.ElementTree` in `parse_xmltv_bytes` to mitigate entity expansion attacks. VERIFY: grep -q "defusedxml" iptv-backend/app/services/xmltv_parser.py && python -c "import defusedxml.ElementTree" (cat:python; multifile:no) [feat:iptv_apps-20260930-bound-downloaded-playlist-epg-size-and-x]
- [ ] [T4] iptv-backend/requirements.txt — Add `defusedxml` dependency to the requirements file. VERIFY: grep -q "^defusedxml" iptv-backend/requirements.txt (cat:refactor; multifile:no) [feat:iptv_apps-20260930-bound-downloaded-playlist-epg-size-and-x]
- [ ] [T5] iptv-backend/app/routers/epg.py — Update the EPG source creation/import endpoint to catch `ValueError` from `parse_xmltv_bytes` and return HTTP 413 with a descriptive message when size limits are exceeded. VERIFY: python -m pytest tests/test_epg_router.py::test_epg_size_limit_413 -v (cat:endpoint; multifile:no) [feat:iptv_apps-20260930-bound-downloaded-playlist-epg-size-and-x]

# --- 27B-decomposed from roadmap [2026-09-30]: RevenueCat webhook has no idempotency or ordering protection, so a delayed older EXPIRATIO (review + tweak) [feat:iptv_apps-20260930-revenuecat-webhook-has-no-idempotency-or] ---
- [ ] [T1] iptv-backend/app/models/subscription.py — Add `last_event_ms` column (BigInteger, nullable) to Subscription model. VERIFY: python -c "from iptv_backend.app.models.subscription import Subscription; assert hasattr(Subscription, 'last_event_ms')" (cat:schema; multifile:no) [feat:iptv_apps-20260930-revenuecat-webhook-has-no-idempotency-or]
- [ ] [T2] iptv-backend/alembic/versions/0011_subscription_last_event_ms.py — Create migration to add `last_event_ms` column to subscriptions table. VERIFY: alembic upgrade head && alembic downgrade -1 (cat:schema; multifile:no) [feat:iptv_apps-20260930-revenuecat-webhook-has-no-idempotency-or]
- [ ] [T3] iptv-backend/app/services/revenuecat.py — Update `parse_webhook_event` to extract and return `event_timestamp_ms` and `id` from payload. VERIFY: pytest tests/test_revenuecat_parse.py::test_parse_extracts_timestamp (cat:python; multifile:no) [feat:iptv_apps-20260930-revenuecat-webhook-has-no-idempotency-or]
- [ ] [T4] iptv-backend/app/services/revenuecat.py — Implement `is_stale_event(subscription, event_ts)` helper returning True if event_ts < subscription.last_event_ms. VERIFY: pytest tests/test_revenuecat_stale.py::test_is_stale_logic (cat:python; multifile:no) [feat:iptv_apps-20260930-revenuecat-webhook-has-no-idempotency-or]
- [ ] [T5] iptv-backend/app/routers/subscription.py — Modify `revenuecat_webhook` to check staleness before applying state and return `{"status":"ignored","reason":"stale"}` if stale. VERIFY: pytest tests/test_subscription_webhook.py::test_stale_event_ignored (cat:endpoint; multifile:no) [feat:iptv_apps-20260930-revenuecat-webhook-has-no-idempotency-or]

# --- 27B-decomposed from roadmap [2026-09-30]: Expired device-pairing rows and email-verification tokens are never purged — iptv-backend/ (review + tweak) [feat:iptv_apps-20260930-expired-device-pairing-rows-and-email-ve] ---
- [ ] [T1] iptv-backend/app/jobs/cleanup_job.py — Create module with pure function `purge_expired_auth_rows(db: Session, now: datetime) -> int` that deletes `DevicePairing` rows where `expires_at < now` and expired verification tokens from the table used by `services/auth.py`, returning total count deleted. VERIFY: `python -c "from iptv_backend.app.jobs.cleanup_job import purge_expired_auth_rows; print('ok')"` succeeds. (cat:python; multifile:no) [feat:iptv_apps-20260930-expired-device-pairing-rows-and-email-ve]
- [ ] [T2] iptv-backend/tests/test_cleanup_job.py — Create unit test file mocking DB session to verify `purge_expired_auth_rows` deletes only expired `DevicePairing` and verification tokens, leaving live rows intact, and returns correct count. VERIFY: `pytest iptv-backend/tests/test_cleanup_job.py -v` passes. (cat:test; multifile:no) [feat:iptv_apps-20260930-expired-device-pairing-rows-and-email-ve]
- [ ] [T3] iptv-backend/app/jobs/health_check.py — Import `purge_expired_auth_rows` from `cleanup_job` and add a scheduled task in `start_scheduler()` that runs hourly, guarded by `ENABLE_AUTH_CLEANUP` env var (default true), calling the function with current UTC time. VERIFY: `grep -n "purge_expired_auth_rows" iptv-backend/app/jobs/health_check.py` shows the import and usage. (cat:python; multifile:no) [feat:iptv_apps-20260930-expired-device-pairing-rows-and-email-ve]
- [ ] [T4] iptv-backend/app/models/__init__.py — Ensure `DevicePairing` model is exported if not already, and verify the verification token model/table name matches what `services/auth.py` uses for purging. VERIFY: `python -c "from iptv_backend.app.models import DevicePairing; print(DevicePairing.__tablename__)"` prints the correct table name. (cat:schema; multifile:no) [feat:iptv_apps-20260930-expired-device-pairing-rows-and-email-ve]
- [ ] [T5] iptv-backend/app/jobs/cleanup_job.py — Add logging statements to `purge_expired_auth_rows` to log the number of purged rows and any exceptions, ensuring silent failures are visible in job logs. VERIFY: `grep -n "logger\|logging" iptv-backend/app/jobs/cleanup_job.py` shows logging calls. (cat:python; multifile:no) [feat:iptv_apps-20260930-expired-device-pairing-rows-and-email-ve]
