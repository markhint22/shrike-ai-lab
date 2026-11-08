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

# --- 27B-decomposed from roadmap [2026-09-10]: YouTube support follow-through — an MVP already exists (curated news/government/space/loca (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Watchlist/Continue-watching parity across web + mobile {cat: web+mobile; size: M; multifil (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Profiles + parental controls depth; kids mode — Chickadee already has `Profile`/`ParentalS (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Profiles + parental controls depth; kids mode — Chickadee already has `Profile`/`ParentalS (review + tweak) ---

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

# --- research pass [2026-09-23 round 2]: native-client (Android/iOS) API-parity sweep + backend dead-table/dead-model sweep, grounded via direct grep across iptv-backend/iptv-android/iptv-ios (no coverage tooling this round) ---








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

# --- 27B-decomposed from roadmap [2026-09-30]: RevenueCat webhook has no idempotency or ordering protection, so a delayed older EXPIRATIO (review + tweak) [feat:iptv_apps-20260930-revenuecat-webhook-has-no-idempotency-or] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Expired device-pairing rows and email-verification tokens are never purged — iptv-backend/ (review + tweak) [feat:iptv_apps-20260930-expired-device-pairing-rows-and-email-ve] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Fix vod.py double module body — iptv-backend/app/routers/vod.py contains two concatenated  (review + tweak) [feat:iptv_apps-20261001-fix-vod-py-double-module-body-iptv-backe] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Fix EPG XMLTV import N+1 queries — _import_xmltv_for_source() in iptv-backend/app/routers/ (review + tweak) [feat:iptv_apps-20261001-fix-epg-xmltv-import-n-1-queries-import-] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Scrub LLM reasoning comments from discover.py — iptv-backend/app/routers/discover.py lines (review + tweak) [feat:iptv_apps-20261001-scrub-llm-reasoning-comments-from-discov] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Remove 4th dead stream-limit implementation — iptv-backend/app/services/playlist.py:79 def (review + tweak) [feat:iptv_apps-20261002-remove-4th-dead-stream-limit-implementat] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Eliminate aiohttp from playlist.py — iptv-backend/app/services/playlist.py line 14 imports (review + tweak) [feat:iptv_apps-20261002-eliminate-aiohttp-from-playlist-py-iptv-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Wire token_version session invalidation — `create_access_token` (iptv-backend/app/services (review + tweak) [feat:iptv_apps-20261003-wire-token-version-session-invalidation-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Fix xmltv_parser crash on invalid env var values — iptv-backend/app/services/xmltv_parser. (review + tweak) [feat:iptv_apps-20261003-fix-xmltv-parser-crash-on-invalid-env-va] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Complete aiohttp→httpx migration beyond playlist.py — the existing "Eliminate aiohttp from (review + tweak) [feat:iptv_apps-20261003-complete-aiohttp-httpx-migration-beyond-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Bound XMLTV download at the network layer before parsing — iptv-backend/app/services/xmltv (review + tweak) [feat:iptv_apps-20261003-bound-xmltv-download-at-the-network-laye] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Scrub "Hey!" LLM artifact docstrings from stream_limit.py — iptv-backend/app/services/stre (review + tweak) [feat:iptv_apps-20261003-scrub-hey-llm-artifact-docstrings-from-s] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Fix `update_watch_position` silently 404-ing for global/Discover streams — `iptv-backend/a (review + tweak) [feat:iptv_apps-20261003-fix-update-watch-position-silently-404-i] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Wire `watchlist_dedupe.dedupe_watchlist()` into the favorites GET endpoint — `iptv-backend (review + tweak) [feat:iptv_apps-20261003-wire-watchlist-dedupe-dedupe-watchlist-i] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Replace `datetime.utcnow()` with `datetime.now(timezone.utc)` across 15 app files — `grep  (review + tweak) [feat:iptv_apps-20261003-replace-datetime-utcnow-with-datetime-no] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Scrub "Hey!" LLM artifact from `normalization.py` module docstring — `iptv-backend/app/ser (review + tweak) [feat:iptv_apps-20261003-scrub-hey-llm-artifact-from-normalizatio] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Fix `check_all_streams` silently dropping health state on gather exceptions — `iptv-backen (review + tweak) [feat:iptv_apps-20261003-fix-check-all-streams-silently-dropping-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Fix `url_safety.assert_public_url` blocking event loop via synchronous `socket.getaddrinfo (review + tweak) [feat:iptv_apps-20261003-fix-url-safety-assert-public-url-blockin] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Replace `discover.py` unbounded process-global `_cache` dict with a TTLCache — `iptv-backe (review + tweak) [feat:iptv_apps-20261003-replace-discover-py-unbounded-process-gl] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Fix `get_content_engagement` type mismatch silently returning zero results — `iptv-backend (review + tweak) [feat:iptv_apps-20261004-fix-get-content-engagement-type-mismatch] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Fix PIN lockout bypass in parental `unblock_stream` endpoint — `DELETE /api/parental/block (review + tweak) [feat:iptv_apps-20261004-fix-pin-lockout-bypass-in-parental-unblo] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Fix `run_cleanup` crash + add tests — `iptv-backend/app/jobs/cleanup_job.py:79` uses `Watc (review + tweak) [feat:iptv_apps-20261004-fix-run-cleanup-crash-add-tests-iptv-bac] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Wire `track_engagement` POST endpoint — `iptv-backend/app/routers/engagement.py` docstring (review + tweak) [feat:iptv_apps-20261004-wire-track-engagement-post-endpoint-iptv] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Add rate limiting to engagement scan endpoints — `iptv-backend/app/routers/engagement.py`  (review + tweak) [feat:iptv_apps-20261004-add-rate-limiting-to-engagement-scan-end] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Fix apply_trial_expiry querying wrong/dead table — `iptv-backend/app/services/premium.py:2 (review + tweak) [feat:iptv_apps-20261004-fix-apply-trial-expiry-querying-wrong-de] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Wrap email-send failures in auth.py so registration can't leave users in unverifiable limb (review + tweak) [feat:iptv_apps-20261004-wrap-email-send-failures-in-auth-py-so-r] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Wire epg_now_next.pick_now_next() into the now-playing endpoint and eliminate its 2N query (review + tweak) [feat:iptv_apps-20261004-wire-epg-now-next-pick-now-next-into-the] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Delete or wire dead subscription_tier_rank helpers — `iptv-backend/app/services/subscripti (review + tweak) [feat:iptv_apps-20261004-delete-or-wire-dead-subscription-tier-ra] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Add missing request: Request param to get_content_engagement to fix AUTO-SKIP rate-limit l (review + tweak) [feat:iptv_apps-20261004-add-missing-request-request-param-to-get] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Move 2 ghost auth resilience tests from app/jobs/ to tests/ and delete 4 dead stubs — `ipt (review + tweak) [feat:iptv_apps-20261004-move-2-ghost-auth-resilience-tests-from-] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Delete dead `validate_content_rights()` and its ghost test `tests/test_playlist_rights.py` (review + tweak) [feat:iptv_apps-20261004-delete-dead-validate-content-rights-and-] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Delete `test_content_service_cleanup.py` — it asserts `validate_content_rights` EXISTS (li (review + tweak) [feat:iptv_apps-20261004-delete-test-content-service-cleanup-py-i] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Delete orphaned fleet-added referral stubs — `iptv-backend/app/services/referral_service.p (review + tweak) [feat:iptv_apps-20261004-delete-orphaned-fleet-added-referral-stu] ---

# --- 27B-decomposed from roadmap [2026-10-04]: Fix `test_vod_api.py` doubled module body — `iptv-backend/tests/test_vod_api.py` (48 lines (review + tweak) [feat:iptv_apps-20261004-fix-test-vod-api-py-doubled-module-body-] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Fix unauthenticated `GET /api/epg/analytics/trending` leaking all-user watch data — `iptv- (review + tweak) [feat:iptv_apps-20261005-fix-unauthenticated-get-api-epg-analytic] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Move 2 ghost tests from `app/routers/` to `tests/` and delete originals — `iptv-backend/ap (review + tweak) [feat:iptv_apps-20261005-move-2-ghost-tests-from-app-routers-to-t] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Delete dead web utility `dedupe.ts` and its test — `iptv-web/src/utils/dedupe.ts`'s `dedup (review + tweak) [feat:iptv_apps-20261005-delete-dead-web-utility-dedupe-ts-and-it] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Delete misleading `playback.ts` stub that generates a fake UUID instead of calling the rea (review + tweak) [feat:iptv_apps-20261005-delete-misleading-playback-ts-stub-that-] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Fix wrong `UUID` annotation on all three `EPGAnalyticsService` methods and remove unused r (review + tweak) [feat:iptv_apps-20261005-fix-wrong-uuid-annotation-on-all-three-e] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Add missing auth guard to `GET /api/discovery/trending` — `iptv-backend/app/routers/discov (review + tweak) [feat:iptv_apps-20261005-add-missing-auth-guard-to-get-api-discov] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Delete `iptv-backend/app/routers/test_epg_analytics_import.py` ghost test — file exists at (review + tweak) [feat:iptv_apps-20261005-delete-iptv-backend-app-routers-test-epg] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Delete `iptv-backend/app/services/test_epg_analytics_service.py` empty placeholder — file  (review + tweak) [feat:iptv_apps-20261005-delete-iptv-backend-app-services-test-ep] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Rate-limit the unauthenticated device-pairing endpoints — `iptv-backend/app/routers/device (review + tweak) [feat:iptv_apps-20261005-rate-limit-the-unauthenticated-device-pa] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Route the stream proxy and health check through the SSRF guard — `iptv-backend/app/service (review + tweak) [feat:iptv_apps-20261005-route-the-stream-proxy-and-health-check-] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Make logout and password change actually revoke tokens — `iptv-backend/app/routers/auth.py (review + tweak) [feat:iptv_apps-20261005-make-logout-and-password-change-actually] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Rate-limit the public feedback and discovery endpoints — `iptv-backend/app/routers/feedbac (review + tweak) [feat:iptv_apps-20261005-rate-limit-the-public-feedback-and-disco] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Stop exposing process internals on the public `/metrics` endpoint — `iptv-backend/app/main (review + tweak) [feat:iptv_apps-20261005-stop-exposing-process-internals-on-the-p] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Remove the hardcoded stub `GET /api/vod` route — `iptv-backend/app/routers/vod.py:24` serv (review + tweak) [feat:iptv_apps-20261005-remove-the-hardcoded-stub-get-api-vod-ro] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Add the missing `type="button"` to two web buttons so they cannot submit a surrounding for (review + tweak) [feat:iptv_apps-20261005-add-the-missing-type-button-to-two-web-b] ---

# --- 27B-decomposed from roadmap [2026-10-05]: Replace the stray `console.log` in the player's CORS-retry path with the app's logger or r (review + tweak) [feat:iptv_apps-20261005-replace-the-stray-console-log-in-the-pla] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Fix unauthenticated `POST /api/subscription/init` — `iptv-backend/app/routers/subscription (review + tweak) [feat:iptv_apps-20261007-fix-unauthenticated-post-api-subscriptio] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Gate admin YouTube channel mutations behind `ADMIN_SECRET` — `iptv-backend/app/routers/adm (review + tweak) [feat:iptv_apps-20261007-gate-admin-youtube-channel-mutations-beh] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Rate-limit reminders router — Add `@limiter.limit` decorators to the 5 routes in `iptv-bac (review + tweak) [feat:iptv_apps-20261007-rate-limit-reminders-router-add-limiter-] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Rate-limit content router — Add `@limiter.limit` decorators to the 13 routes in `iptv-back (review + tweak) [feat:iptv_apps-20261007-rate-limit-content-router-add-limiter-li] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Log swallowed exception in favorites idempotency — Replace bare `pass` with `logger.except (review + tweak) [feat:iptv_apps-20261007-log-swallowed-exception-in-favorites-ide] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Test youtube channel accurate job — Add a test for `youtube_channel_accurate_check_job` in (review + tweak) [feat:iptv_apps-20261007-test-youtube-channel-accurate-job-add-a-] ---


# --- 27B-decomposed from roadmap [2026-10-07]: Rate-limit downloads router — Add `@limiter.limit` decorators to the 6 routes in `iptv-bac (review + tweak) [feat:iptv_apps-20261007-rate-limit-downloads-router-add-limiter-] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Log swallowed exception in tmdb service — Replace bare `pass` with `logger.exception` in ` (review + tweak) [feat:iptv_apps-20261007-log-swallowed-exception-in-tmdb-service-] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Rate-limit account router — Add `@limiter.limit` decorators to the 2 routes in `iptv-backe (review + tweak) [feat:iptv_apps-20261007-rate-limit-account-router-add-limiter-li] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Test create_download endpoint — Add tests for `create_download` in `iptv-backend/app/route (review + tweak) [feat:iptv_apps-20261007-test-create-download-endpoint-add-tests-] ---

# --- hand-written by Claude 2026-10-07 (Mark: make /api/vod real; Qwen's own decomposition had VERIFYs that could never pass) [feat:iptv_apps-20261007-make-get-api-vod-a-real-catalog-instead-] ---

# --- hand-written by Claude 2026-10-07 (web referral UI; backend already shipped) [feat:iptv_apps-20261007-add-the-web-client-for-referra] ---

# --- 27B-decomposed from roadmap [2026-10-07]: Rate-limit notifications router — Add `@limiter.limit` decorators to the 5 routes in `iptv (review + tweak) [feat:iptv_apps-20261007-rate-limit-notifications-router-add-limi] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Log swallowed exception in push_sender — Replace bare `pass` with `logger.exception` in `i (review + tweak) [feat:iptv_apps-20261008-log-swallowed-exception-in-push-sender-r] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Test notifications device endpoints — Add tests for `register_device`, `list_devices`, `re (review + tweak) [feat:iptv_apps-20261008-test-notifications-device-endpoints-add-] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Implement recordings API calls — Replace TODOs in `iptv-web/src/stores/recordings.ts:13` a (review + tweak) [feat:iptv_apps-20261008-implement-recordings-api-calls-replace-t] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Rate-limit stream analytics endpoints — Add `@limiter.limit` decorators to the 3 routes in (review + tweak) [feat:iptv_apps-20261008-rate-limit-stream-analytics-endpoints-ad] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Rate-limit content groups endpoints — Add `@limiter.limit` decorators to the 4 routes in ` (review + tweak) [feat:iptv_apps-20261008-rate-limit-content-groups-endpoints-add-] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Test content groups endpoints — Add tests for `get_group`, `get_alternates`, `set_preferre (review + tweak) [feat:iptv_apps-20261008-test-content-groups-endpoints-add-tests-] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Test referrals endpoints — Add tests for `create_referral_code`, `list_my_referrals`, and  (review + tweak) [feat:iptv_apps-20261008-test-referrals-endpoints-add-tests-for-c] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Test `check_discover_denylist` — Add unit tests for `iptv-backend/app/services/discover.py (review + tweak) [feat:iptv_apps-20261008-test-check-discover-denylist-add-unit-te] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Test `extract_stream_id_from_query` — Add unit tests for `iptv-backend/app/services/discov (review + tweak) [feat:iptv_apps-20261008-test-extract-stream-id-from-query-add-un] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Test `recompute_representative` — Add unit tests for `iptv-backend/app/services/content_de (review + tweak) [feat:iptv_apps-20261008-test-recompute-representative-add-unit-t] ---

# --- 27B-decomposed from roadmap [2026-10-08]: Test `register_device_token` — Add unit tests for `iptv-backend/app/services/notifications (review + tweak) [feat:iptv_apps-20261008-test-register-device-token-add-unit-test] ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-08 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-09]: Test profile CRUD endpoints — Add tests for `list_profiles`, `create_profile`, `get_profil (review + tweak) [feat:iptv_apps-20261009-test-profile-crud-endpoints-add-tests-fo] ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-09]: Test watch history enrichment — Add tests for `enrich_watch_history`, `enrich_continue_wat (review + tweak) [feat:iptv_apps-20261009-test-watch-history-enrichment-add-tests-] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Test stream model validation — Add tests for `validate_cast_device_info` in `iptv-backend/ (review + tweak) [feat:iptv_apps-20261009-test-stream-model-validation-add-tests-f] ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-09]: Test watch history progress and position updates — Add tests for `update_watch_progress` a (review + tweak) [feat:iptv_apps-20261009-test-watch-history-progress-and-position] ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-09]: Test continue watching CRUD operations — Add tests for `get_continue_watching`, `add_to_co (review + tweak) [feat:iptv_apps-20261009-test-continue-watching-crud-operations-a] ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-09 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-09]: Test EPG source management endpoints — Add tests for `list_epg_sources`, `create_epg_sourc (review + tweak) [feat:iptv_apps-20261009-test-epg-source-management-endpoints-add] ---

# --- 27B-decomposed from roadmap [2026-10-09]: Test system status and version endpoints — Add tests for `status_endpoint` and `version_en (review + tweak) [feat:iptv_apps-20261009-test-system-status-and-version-endpoints] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Test `metrics_endpoint` — Add tests for `metrics_endpoint` in `iptv-backend/app/main.py:32 (review + tweak) [feat:iptv_apps-20261010-test-metrics-endpoint-add-tests-for-metr] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Fix `/version` endpoint to read from `build_info.__version__` — `app/main.py:374` returns  (review + tweak) [feat:iptv_apps-20261010-fix-version-endpoint-to-read-from-build-] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Fix `device_auth.py` `VERIFICATION_URI` wrong domain shown on TV — `app/routers/device_aut (review + tweak) [feat:iptv_apps-20261010-fix-device-auth-py-verification-uri-wron] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Fix inline stream health check using naive `datetime.utcnow()` for `DateTime(timezone=True (review + tweak) [feat:iptv_apps-20261010-fix-inline-stream-health-check-using-nai] ---

# --- 27B-decomposed from roadmap [2026-10-10]: Fix misleading SSRF debug log in `url_safety.py::resolve_public_sync` — `app/services/url_ (review + tweak) [feat:iptv_apps-20261010-fix-misleading-ssrf-debug-log-in-url-saf] ---

# --- deterministic work supply 2026-10-10 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-10]: Move ghost test `app/jobs/test_auth_change_email_resilience.py` to `iptv-backend/tests/` — (review + tweak) [feat:iptv_apps-20261010-move-ghost-test-app-jobs-test-auth-chang] ---

# --- deterministic work supply 2026-10-10 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-10 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-11]: `notifications.py` and `content.py` rate-limiting is silently broken — both import `from a (review + tweak) [feat:iptv_apps-20261011-notifications-py-and-content-py-rate-lim] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Android FavoritesRepository.kt landed in wrong package — per-profile favorites never wired (review + tweak) [feat:iptv_apps-20261011-android-favoritesrepository-kt-landed-in] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Delete orphaned `content_rights.py` — a third `validate_content_rights()` not tracked in t (review + tweak) [feat:iptv_apps-20261011-delete-orphaned-content-rights-py-a-thir] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Replace hardcoded RevenueCat API key placeholder — `iptv-android/app/src/main/java/com/chi (review + tweak) [feat:iptv_apps-20261011-replace-hardcoded-revenuecat-api-key-pla] ---

# --- 27B-decomposed from roadmap [2026-10-11]: Test `unlock_profile` endpoint — Add a test for `unlock_profile` in `iptv-backend/app/rout (review + tweak) [feat:iptv_apps-20261011-test-unlock-profile-endpoint-add-a-test-] ---

# --- deterministic work supply 2026-10-11 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-12]: Fix wrong `@limiter.limit` decorator order — rate limiting on content.py and reminders.py  (review + tweak) [feat:iptv_apps-20261012-fix-wrong-limiter-limit-decorator-order-] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Fix `POST /api/discover/cache/clear` silently clearing dead `_cache` dict instead of live  (review + tweak) [feat:iptv_apps-20261012-fix-post-api-discover-cache-clear-silent] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Profile-PIN `_unlock_lockout_tracker` loses all lockout state on every process restart — ` (review + tweak) [feat:iptv_apps-20261012-profile-pin-unlock-lockout-tracker-loses] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Test `retry_after_seconds` and `rate_limit_exceeded_handler` — Add unit tests for `retry_a (review + tweak) [feat:iptv_apps-20261012-test-retry-after-seconds-and-rate-limit-] ---

# --- 27B-decomposed from roadmap [2026-10-12]: Test `submit_feedback` endpoint — Add tests for `submit_feedback` in `iptv-backend/app/rou (review + tweak) [feat:iptv_apps-20261012-test-submit-feedback-endpoint-add-tests-] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Test `list_profiles` endpoint — Add a test for `list_profiles` in `iptv-backend/app/router (review + tweak) [feat:iptv_apps-20261013-test-list-profiles-endpoint-add-a-test-f] ---

# --- 27B-decomposed from roadmap [2026-10-13]: `VodView.vue` always silently shows empty — `api.get()` returns the response body directly (review + tweak) [feat:iptv_apps-20261013-vodview-vue-always-silently-shows-empty-] ---

# --- 27B-decomposed from roadmap [2026-10-13]: `recordings.ts` store calls three wrong API paths, breaking `RecordingsView.vue` — `iptv-w (review + tweak) [feat:iptv_apps-20261013-recordings-ts-store-calls-three-wrong-ap] ---

# --- 27B-decomposed from roadmap [2026-10-13]: `GET /api/vod/genres` loads the entire VOD catalog (up to 100,000 rows) to derive genres i (review + tweak) [feat:iptv_apps-20261013-get-api-vod-genres-loads-the-entire-vod-] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Delete the dead `ParentalControlsService` class from `parental_controls.py` — `iptv-backen (review + tweak) [feat:iptv_apps-20261013-delete-the-dead-parentalcontrolsservice-] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Rate-limit `POST /api/subscription/cancel` and `GET /api/subscription/billing-history` — ` (review + tweak) [feat:iptv_apps-20261013-rate-limit-post-api-subscription-cancel-] ---

# --- deterministic work supply 2026-10-13 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-13 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-14]: Fix RecordingsView blank titles — `iptv-web/src/stores/recordings.ts:6` defines `Recording (review + tweak) [feat:iptv_apps-20261014-fix-recordingsview-blank-titles-iptv-web] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Fix VodView images always hidden — `iptv-web/src/types/vod.ts:5` declares `poster?: string (review + tweak) [feat:iptv_apps-20261014-fix-vodview-images-always-hidden-iptv-we] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Fix VodView genre filter using only first-page items — `VodView.vue:11-14` derives genres  (review + tweak) [feat:iptv_apps-20261014-fix-vodview-genre-filter-using-only-firs] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Fix stream ownership bypass in update_watch_progress — `watch_history.py:251` fetches `db. (review + tweak) [feat:iptv_apps-20261014-fix-stream-ownership-bypass-in-update-wa] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Rate-limit watch-history write endpoints — `iptv-backend/app/routers/watch_history.py` has (review + tweak) [feat:iptv_apps-20261014-rate-limit-watch-history-write-endpoints] ---

# --- 27B-decomposed from roadmap [2026-10-14]: Remove orphaned denylist helpers with mismatched signature — `iptv-backend/app/services/di (review + tweak) [feat:iptv_apps-20261014-remove-orphaned-denylist-helpers-with-mi] ---

# --- deterministic work supply 2026-10-14 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-15]: Rate-limit `GET /subscription/status` and `GET /subscription/paywall` — both handlers in ` (review + tweak) [feat:iptv_apps-20261015-rate-limit-get-subscription-status-and-g] ---

# --- 27B-decomposed from roadmap [2026-10-15]: Fix `update_continue_watching` exposing stream URL without ownership check — `iptv-backend (review + tweak) [feat:iptv_apps-20261015-fix-update-continue-watching-exposing-st] ---

# --- 27B-decomposed from roadmap [2026-10-15]: `GET /streams/series` bypasses the per-kid-profile parental rating ceiling — `iptv-backend (review + tweak) [feat:iptv_apps-20261015-get-streams-series-bypasses-the-per-kid-] ---

# --- 27B-decomposed from roadmap [2026-10-15]: Series-view `favorite_show()` writes `Stream.is_favorite` (account-wide), not per-profile  (review + tweak) [feat:iptv_apps-20261015-series-view-favorite-show-writes-stream-] ---

# --- deterministic work supply 2026-10-15 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-15 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-16]: Fix `GET /api/streams/{stream_id}` returning stale `is_favorite: true` when legacy DB colu (review + tweak) [feat:iptv_apps-20261016-fix-get-api-streams-stream-id-returning-] ---

# --- 27B-decomposed from roadmap [2026-10-16]: Fix `data_retention_job.py` passing deprecated naive `datetime.utcnow()` to the auth-row p (review + tweak) [feat:iptv_apps-20261016-fix-data-retention-job-py-passing-deprec] ---

# --- 27B-decomposed from roadmap [2026-10-16]: Fix _extract_year to return correct 4-digit year from title — `iptv-backend/app/services/t (review + tweak) [feat:iptv_apps-20261016-fix-extract-year-to-return-correct-4-dig] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `apply_continue_watching_boost` int/str type mismatch: personalized recommendations bo (review + tweak) [feat:iptv_apps-20261017-fix-apply-continue-watching-boost-int-st] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `discovery_api.py` wrongly annotates all 10 `db` parameters as `AsyncSession` while `g (review + tweak) [feat:iptv_apps-20261017-fix-discovery-api-py-wrongly-annotates-a] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix 6 naive `datetime.utcnow()` writes to timezone-aware `WatchHistory.last_watched_at` in (review + tweak) [feat:iptv_apps-20261017-fix-6-naive-datetime-utcnow-writes-to-ti] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `parental_lockout.py:28` naive datetime against timezone-aware `PINAttempt.attempted_a (review + tweak) [feat:iptv_apps-20261017-fix-parental-lockout-py-28-naive-datetim] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `trending.py:22` naive `datetime.utcnow()` against timezone-aware `Stream.created_at`  (review + tweak) [feat:iptv_apps-20261017-fix-trending-py-22-naive-datetime-utcnow] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `stream_discovery_service.py:60` naive `datetime.utcnow()` against timezone-aware `Wat (review + tweak) [feat:iptv_apps-20261017-fix-stream-discovery-service-py-60-naive] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Wire `search_query_tokenize.normalize_query()` into `build_token_filters` to consolidate t (review + tweak) [feat:iptv_apps-20261017-wire-search-query-tokenize-normalize-que] ---

# --- 27B-decomposed from roadmap [2026-10-17]: fix naive datetime in get_trending_channels — `stream_discovery_service.py:60` calls `date (review + tweak) [feat:iptv_apps-20261017-fix-naive-datetime-in-get-trending-chann] ---

# --- 27B-decomposed from roadmap [2026-10-17]: fix naive datetime in cleanup_job run_cleanup — `cleanup_job.py:67` uses `datetime.utcnow( (review + tweak) [feat:iptv_apps-20261017-fix-naive-datetime-in-cleanup-job-run-cl] ---

# --- 27B-decomposed from roadmap [2026-10-17]: genres endpoint always returns zero channel counts — `discovery_api.py:288-312` `GET /api/ (review + tweak) [feat:iptv_apps-20261017-genres-endpoint-always-returns-zero-chan] ---

# --- 27B-decomposed from roadmap [2026-10-17]: fix naive datetime in get_watch_statistics filters — `watch_history.py:612` uses `datetime (review + tweak) [feat:iptv_apps-20261017-fix-naive-datetime-in-get-watch-statisti] ---

# --- deterministic work supply 2026-10-17 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-17]: rewire Android FavoritesRepository into correct package — `FavoritesRepository.kt` was gen (review + tweak) [feat:iptv_apps-20261017-rewire-android-favoritesrepository-into-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: parental pin-session check crashes on Postgres with naive/aware TypeError — `iptv-backend/ (review + tweak) [feat:iptv_apps-20261018-parental-pin-session-check-crashes-on-po] ---

# --- 27B-decomposed from roadmap [2026-10-18]: parental time-restriction enforcement uses UTC clock instead of user local time — `iptv-ba (review + tweak) [feat:iptv_apps-20261018-parental-time-restriction-enforcement-us] ---

# --- 27B-decomposed from roadmap [2026-10-18]: VOD progress model assigns naive datetime to timezone-aware completed_at column — `iptv-ba (review + tweak) [feat:iptv_apps-20261018-vod-progress-model-assigns-naive-datetim] ---

# --- 27B-decomposed from roadmap [2026-10-18]: delete dead concurrent-stream-limit helpers and their false-confidence tests — `iptv-backe (review + tweak) [feat:iptv_apps-20261018-delete-dead-concurrent-stream-limit-help] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Roku channel hardcodes production API base URL with no staging path — `iptv-roku/source/Co (review + tweak) [feat:iptv_apps-20261018-roku-channel-hardcodes-production-api-ba] ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test parental time-window logic — Add unit tests for `get_local_hour` and `is_within_time_ (review + tweak) [feat:iptv_apps-20261018-test-parental-time-window-logic-add-unit] ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix `check_time_restrictions` never enforcing hours when `restricted_days=[]` — `iptv-back (review + tweak) [feat:iptv_apps-20261018-fix-check-time-restrictions-never-enforc] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix `check_content_allowed` never checking time restrictions — `iptv-backend/app/routers/p (review + tweak) [feat:iptv_apps-20261018-fix-check-content-allowed-never-checking] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Wire `timezone_offset_minutes` into daily-limit date bucketing — `iptv-backend/app/routers (review + tweak) [feat:iptv_apps-20261018-wire-timezone-offset-minutes-into-daily-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix `check_time_restrictions` always using UTC hour rather than user's local hour — `iptv- (review + tweak) [feat:iptv_apps-20261018-fix-check-time-restrictions-always-using] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test `validate_cast_device_info` — Add unit tests for `validate_cast_device_info` in `iptv (review + tweak) [feat:iptv_apps-20261018-test-validate-cast-device-info-add-unit-] ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test `update_watch_progress` endpoint — Add a test for `update_watch_progress` in `iptv-ba (review + tweak) [feat:iptv_apps-20261018-test-update-watch-progress-endpoint-add-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix parental daily-limit timezone mismatch in report_usage — `iptv-backend/app/routers/par (review + tweak) [feat:iptv_apps-20261018-fix-parental-daily-limit-timezone-mismat] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix broken region filter in get_trending_streams — `iptv-backend/app/services/trending.py: (review + tweak) [feat:iptv_apps-20261018-fix-broken-region-filter-in-get-trending] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix stream credentials leaked in proxy error logs — `iptv-backend/app/routers/streams.py:2 (review + tweak) [feat:iptv_apps-20261018-fix-stream-credentials-leaked-in-proxy-e] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix relay endpoint not forwarding Range header for VOD byte-range seeking — `iptv-backend/ (review + tweak) [feat:iptv_apps-20261018-fix-relay-endpoint-not-forwarding-range-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Add tests for get_trending_streams region filter and day-window — `iptv-backend/app/servic (review + tweak) [feat:iptv_apps-20261018-add-tests-for-get-trending-streams-regio] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix N+1 queries in get_continue_watching by batching lookups — `iptv-backend/app/routers/c (review + tweak) [feat:iptv_apps-20261018-fix-n-1-queries-in-get-continue-watching] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test `create_profile` and `update_profile` — Add tests for `create_profile` in `iptv-backe (review + tweak) [feat:iptv_apps-20261018-test-create-profile-and-update-profile-a] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `get_profile` and `delete_profile` — Add tests for `get_profile` in `iptv-backend/app (review + tweak) [feat:iptv_apps-20261019-test-get-profile-and-delete-profile-add-] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test watch-history mutation and state endpoints — Add tests for `update_watch_position`, ` (review + tweak) [feat:iptv_apps-20261019-test-watch-history-mutation-and-state-en] ---

# --- 27B-decomposed from roadmap [2026-10-19]: `GET /api/content/continue-watching` bypasses kid-profile parental rating ceiling — `iptv- (review + tweak) [feat:iptv_apps-20261019-get-api-content-continue-watching-bypass] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Android `EpgViewModel.toggleChannelFavorite()` uses legacy account-wide `is_favorite` API, (review + tweak) [feat:iptv_apps-20261019-android-epgviewmodel-togglechannelfavori] ---

# --- 27B-decomposed from roadmap [2026-10-19]: iOS `MainTabView.swift` tab items have no `.accessibilityIdentifier(...)`, forcing E2E tab (review + tweak) [feat:iptv_apps-20261019-ios-maintabview-swift-tab-items-have-no-] ---

# --- 27B-decomposed from roadmap [2026-10-19]: `downloads.py`'s `_visible_stream_or_404` skips parental rating ceiling — `iptv-backend/ap (review + tweak) [feat:iptv_apps-20261019-downloads-py-s-visible-stream-or-404-ski] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `list_epg_sources` and `create_epg_source` — Add unit tests for `list_epg_sources` in (review + tweak) [feat:iptv_apps-20261019-test-list-epg-sources-and-create-epg-sou] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `enrich_watch_history` and `enrich_continue_watching` — Add unit tests for the untest (review + tweak) [feat:iptv_apps-20261019-test-enrich-watch-history-and-enrich-con] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `list_epg_source_runs`, `update_epg_source`, and `activate_epg_source` — Add unit tes (review + tweak) [feat:iptv_apps-20261019-test-list-epg-source-runs-update-epg-sou] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `delete_epg_source` and `refresh_epg_source` — Add tests for `delete_epg_source` in ` (review + tweak) [feat:iptv_apps-20261019-test-delete-epg-source-and-refresh-epg-s] ---

# --- deterministic work supply 2026-10-19 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-20]: `clear_watch_history` silently leaves ContinueWatching rows — `DELETE /api/history` in `wa (review + tweak) [feat:iptv_apps-20261020-clear-watch-history-silently-leaves-cont] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `GET /api/history/continue` (watch_history.py) exposes mature content to kid profiles — `g (review + tweak) [feat:iptv_apps-20261020-get-api-history-continue-watch-history-p] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Discovery continue-watching recommendations not profile-scoped — `stream_discovery_service (review + tweak) [feat:iptv_apps-20261020-discovery-continue-watching-recommendati] ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-20]: `SearchHistory` model lacks `profile_id` — `models/search.py:14-28` defines `SearchHistory (review + tweak) [feat:iptv_apps-20261020-searchhistory-model-lacks-profile-id-mod] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `update_reminder` accepts past `program_start` dates — `reminders.py:152-181` calls `setat (review + tweak) [feat:iptv_apps-20261020-update-reminder-accepts-past-program-sta] ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: `Download` interface in `api.ts` missing `is_dvr` field — both `DownloadsView` and `Record (review + tweak) [feat:iptv_apps-20261021-download-interface-in-api-ts-missing-is-] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Add `/recordings` route and backend DVR-list endpoint so the DVR feature is actually reach (review + tweak) [feat:iptv_apps-20261021-add-recordings-route-and-backend-dvr-lis] ---

# --- 27B-decomposed from roadmap [2026-10-21]: VodView.vue genre dropdown shows only genres from the first 20 items; wire it to the dedic (review + tweak) [feat:iptv_apps-20261021-vodview-vue-genre-dropdown-shows-only-ge] ---

# --- 27B-decomposed from roadmap [2026-10-21]: SeriesListView.vue is also orphaned — exists as a built view with no route or nav link — ` (review + tweak) [feat:iptv_apps-20261021-serieslistview-vue-is-also-orphaned-exis] ---

# --- 27B-decomposed from roadmap [2026-10-21]: `get_continue_watching` endpoint leaks mature-rated VOD entries to kid profiles — the `fil (review + tweak) [feat:iptv_apps-20261021-get-continue-watching-endpoint-leaks-mat] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `get_resume_state` and `delete_watch_history` — Add unit tests for the untested publi (review + tweak) [feat:iptv_apps-20261022-test-get-resume-state-and-delete-watch-h] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `get_epg_import_status` and `list_epg_channels` — Add unit tests for the untested pub (review + tweak) [feat:iptv_apps-20261022-test-get-epg-import-status-and-list-epg-] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `get_now_playing_all` and `get_now_playing_for_stream` — Add unit tests for the untes (review + tweak) [feat:iptv_apps-20261022-test-get-now-playing-all-and-get-now-pla] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `auto_map_streams` — Add unit tests for the untested public function `auto_map_stream (review + tweak) [feat:iptv_apps-20261022-test-auto-map-streams-add-unit-tests-for] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Fix open redirect vulnerability in LoginView — `iptv-web/src/views/LoginView.vue:25` (`han (review + tweak) [feat:iptv_apps-20261023-fix-open-redirect-vulnerability-in-login] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `update_continue_watching` endpoint — Add unit tests for the untested public function (review + tweak) [feat:iptv_apps-20261023-test-update-continue-watching-endpoint-a] ---

# --- 27B-decomposed from roadmap [2026-10-23]: LinkTvView onInput shifts digits into the letter slot when 5+ letters are typed — `iptv-we (review + tweak) [feat:iptv_apps-20261023-linktvview-oninput-shifts-digits-into-th] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `create_mapping` endpoint — Add unit tests for the untested public function `create_m (review + tweak) [feat:iptv_apps-20261023-test-create-mapping-endpoint-add-unit-te] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_stream_content` endpoint — Add unit tests for the untested public function `get_ (review + tweak) [feat:iptv_apps-20261023-test-get-stream-content-endpoint-add-uni] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_resume_position` — Add unit tests for the untested public function `get_resume_p (review + tweak) [feat:iptv_apps-20261023-test-get-resume-position-add-unit-tests-] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `vod_genre_expr` — Add unit tests for the untested public function `vod_genre_expr` i (review + tweak) [feat:iptv_apps-20261023-test-vod-genre-expr-add-unit-tests-for-t] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `vod_visible_query` — Add unit tests for the untested public function `vod_visible_qu (review + tweak) [feat:iptv_apps-20261023-test-vod-visible-query-add-unit-tests-fo] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `exclude_mature_streams` — Add unit tests for the untested public function `exclude_m (review + tweak) [feat:iptv_apps-20261023-test-exclude-mature-streams-add-unit-tes] ---

# --- deterministic work supply 2026-10-23 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_vod_streams` endpoint — Add unit tests for the untested public function `get_vod (review + tweak) [feat:iptv_apps-20261023-test-get-vod-streams-endpoint-add-unit-t] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_watch_history` endpoint — Add unit tests for the untested public function `get_w (review + tweak) [feat:iptv_apps-20261023-test-get-watch-history-endpoint-add-unit] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_letter_offset` — Add unit tests for the untested public function `get_letter_off (review + tweak) [feat:iptv_apps-20261024-test-get-letter-offset-add-unit-tests-fo] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `reclassify_stream_types` — Add unit tests for the untested public function `reclassi (review + tweak) [feat:iptv_apps-20261024-test-reclassify-stream-types-add-unit-te] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_categories` endpoint — Add unit tests for the untested public function `get_cate (review + tweak) [feat:iptv_apps-20261024-test-get-categories-endpoint-add-unit-te] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `list_series_shows` endpoint — Add unit tests for the untested public function `list_ (review + tweak) [feat:iptv_apps-20261024-test-list-series-shows-endpoint-add-unit] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `favorite_show` endpoint — Add unit tests for the untested public function `favorite_ (review + tweak) [feat:iptv_apps-20261024-test-favorite-show-endpoint-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_cast_metadata` — Add unit tests for the untested public function `get_cast_metad (review + tweak) [feat:iptv_apps-20261024-test-get-cast-metadata-add-unit-tests-fo] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `create_stream` endpoint — Add unit tests for the untested public function `create_st (review + tweak) [feat:iptv_apps-20261024-test-create-stream-endpoint-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Add aria-labels to icon-only profile edit and delete buttons — `iptv-web/src/views/Profile (review + tweak) [feat:iptv_apps-20261024-add-aria-labels-to-icon-only-profile-edi] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Fix rate limit IP spoofing via X-Forwarded-For — `iptv-backend/app/core/limiter.py:31` (`g (review + tweak) [feat:iptv_apps-20261025-fix-rate-limit-ip-spoofing-via-x-forward] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Add keyboard navigation to OnboardingWalkthrough progress dots — `iptv-web/src/components/ (review + tweak) [feat:iptv_apps-20261025-add-keyboard-navigation-to-onboardingwal] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `update_stream_source` and `list_stream_source_runs` — Add unit tests for the unteste (review + tweak) [feat:iptv_apps-20261025-test-update-stream-source-and-list-strea] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `refresh_stream_source` and `delete_stream_source` — Add unit tests for the untested  (review + tweak) [feat:iptv_apps-20261025-test-refresh-stream-source-and-delete-st] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Fix N+1 device token query in flush_pending — `iptv-backend/app/services/notifications.py: (review + tweak) [feat:iptv_apps-20261025-fix-n-1-device-token-query-in-flush-pend] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `export_playlist` and `bulk_action` endpoints — Add unit tests for the untested publi (review + tweak) [feat:iptv_apps-20261025-test-export-playlist-and-bulk-action-end] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `create_playback_token` — Add unit tests for the untested public function `create_pla (review + tweak) [feat:iptv_apps-20261025-test-create-playback-token-add-unit-test] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `proxy_options` endpoint — Add unit tests for the untested public function `proxy_opt (review + tweak) [feat:iptv_apps-20261025-test-proxy-options-endpoint-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `deactivate_epg_source` endpoint — Add unit tests for the untested public function `d (review + tweak) [feat:iptv_apps-20261025-test-deactivate-epg-source-endpoint-add-] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `create_device_code` endpoint — Add unit tests for the untested public function `crea (review + tweak) [feat:iptv_apps-20261025-test-create-device-code-endpoint-add-uni] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `delete_epg_mapping` endpoint — Add unit tests for the untested public function `dele (review + tweak) [feat:iptv_apps-20261026-test-delete-epg-mapping-endpoint-add-uni] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `exchange_device_token` — Add unit tests for the untested public function `exchange_d (review + tweak) [feat:iptv_apps-20261026-test-exchange-device-token-add-unit-test] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `get_current_user_info` — Add unit tests for the untested public function `get_curren (review + tweak) [feat:iptv_apps-20261026-test-get-current-user-info-add-unit-test] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `forgot_password` endpoint — Add unit tests for the untested public function `forgot_ (review + tweak) [feat:iptv_apps-20261026-test-forgot-password-endpoint-add-unit-t] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Fix TTLCache.get_or_set to handle None cached values — `iptv-backend/app/services/cache.py (review + tweak) [feat:iptv_apps-20261026-fix-ttlcache-get-or-set-to-handle-none-c] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `verify_email` endpoint — Add unit tests for the untested public function `verify_ema (review + tweak) [feat:iptv_apps-20261026-test-verify-email-endpoint-add-unit-test] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `resend_verification_email` — Add unit tests for the untested public function `resend (review + tweak) [feat:iptv_apps-20261026-test-resend-verification-email-add-unit-] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `add_channel_to_engine` — Add unit tests for the untested public function `add_channe (review + tweak) [feat:iptv_apps-20261026-test-add-channel-to-engine-add-unit-test] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `get_available_genres` — Add unit tests for the untested public function `get_availab (review + tweak) [feat:iptv_apps-20261026-test-get-available-genres-add-unit-tests] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Polling loop in SourcesView makes redundant full-source fetches — `iptv-web/src/views/Sour (review + tweak) [feat:iptv_apps-20261027-polling-loop-in-sourcesview-makes-redund] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_or_create_settings` — Add unit tests for the untested public function `get_or_cr (review + tweak) [feat:iptv_apps-20261027-test-get-or-create-settings-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `update_stream` and `delete_stream` endpoints — Add unit tests for the untested publi (review + tweak) [feat:iptv_apps-20261027-test-update-stream-and-delete-stream-end] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_import_status` and `list_stream_sources` — Add unit tests for the untested publi (review + tweak) [feat:iptv_apps-20261027-test-get-import-status-and-list-stream-s] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test `update_settings` endpoint — Add unit tests for the untested public function `update_ (review + tweak) [feat:iptv_apps-20261028-test-update-settings-endpoint-add-unit-t] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Downgrade-on-expiry sweep for lapsed paid subscriptions (roadmap C4) — entitlement is alre (review + tweak) [feat:iptv_apps-20261028-downgrade-on-expiry-sweep-for-lapsed-pai] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Server-side feature flags for optional surfaces, backend half (roadmap C5) — NEW `iptv-bac (review + tweak) [feat:iptv_apps-20261028-server-side-feature-flags-for-optional-s] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Server-side feature flags, client half (roadmap C5, depends on `iptv-backend/app/services/ (review + tweak) [feat:iptv_apps-20261028-server-side-feature-flags-client-half-ro] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Onboarding funnel stats query (roadmap C7) — NEW `iptv-backend/app/services/funnel_stats.p (review + tweak) [feat:iptv_apps-20261028-onboarding-funnel-stats-query-roadmap-c7] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Source health flag on tracked playlist sources (roadmap C8) — NEW pure function `classify_ (review + tweak) [feat:iptv_apps-20261028-source-health-flag-on-tracked-playlist-s] ---

# --- 27B-decomposed from roadmap [2026-10-28]: EPG auto-map suggestions with a confidence value (roadmap C2) — the matching inside `_exec (review + tweak) [feat:iptv_apps-20261028-epg-auto-map-suggestions-with-a-confiden] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Reject whitespace-only feedback messages server-side — `FeedbackCreate.message` in `iptv-b (review + tweak) [feat:iptv_apps-20261028-reject-whitespace-only-feedback-messages] ---

# --- 27B-decomposed from roadmap [2026-10-28]: FeedbackView accessibility fixes — in `iptv-web/src/views/FeedbackView.vue` the Bug/Featur (review + tweak) [feat:iptv_apps-20261028-feedbackview-accessibility-fixes-in-iptv] ---

# --- 27B-decomposed from roadmap [2026-10-28]: RecordingsView delete failure handling and accessible delete buttons — in `iptv-web/src/vi (review + tweak) [feat:iptv_apps-20261028-recordingsview-delete-failure-handling-a] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Optional pagination for the downloads and DVR list endpoints — `list_downloads` and `list_ (review + tweak) [feat:iptv_apps-20261028-optional-pagination-for-the-downloads-an] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Direct unit tests for the URL syntax guard — `check_url_syntax` in `iptv-backend/app/servi (review + tweak) [feat:iptv_apps-20261028-direct-unit-tests-for-the-url-syntax-gua] ---
- [ ] [T1] iptv-backend/tests/test_url_safety_syntax.py — Add test `test_localhost_blocked` asserting `check_url_syntax("http://localhost/")` and `check_url_syntax("http://foo.localhost/")` raise `SSRFError` with `e.code == "URL_BLOCKED"`. VERIFY: `cd iptv-backend && python3 -m pytest tests/test_url_safety_syntax.py::test_localhost_blocked -q`. (cat:test; multifile:no) [feat:iptv_apps-20261028-direct-unit-tests-for-the-url-syntax-gua]

# --- 27B-decomposed from roadmap [2026-10-28]: Query tests for import run history helpers — `latest_runs_by_source` and `list_runs` in `i (review + tweak) [feat:iptv_apps-20261028-query-tests-for-import-run-history-helpe] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Direct test for the ApiError exception handler — `api_error_handler` in `iptv-backend/app/ (review + tweak) [feat:iptv_apps-20261028-direct-test-for-the-apierror-exception-h] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Tests for notification preference defaults and per-profile isolation — `get_or_create_pref (review + tweak) [feat:iptv_apps-20261029-tests-for-notification-preference-defaul] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Tests for referral configuration helpers — the env readers `reward_days`, `max_open_codes` (review + tweak) [feat:iptv_apps-20261029-tests-for-referral-configuration-helpers] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test the Google Play restore route — `restore_google_purchase` (`POST /api/subscription/go (review + tweak) [feat:iptv_apps-20261029-test-the-google-play-restore-route-resto] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `validate_stream_url` schema — Add unit tests for the untested public function `valid (review + tweak) [feat:iptv_apps-20261029-test-validate-stream-url-schema-add-unit] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `list_profiles` and `create_profile` endpoints — Add unit tests for the untested publ (review + tweak) [feat:iptv_apps-20261029-test-list-profiles-and-create-profile-en] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `list_epg_mappings` endpoint — Add unit tests for the untested public function `list_ (review + tweak) [feat:iptv_apps-20261029-test-list-epg-mappings-endpoint-add-unit] ---

# --- deterministic work supply 2026-10-30 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_features` endpoint — Add unit tests for the untested public function `get_featur (review + tweak) [feat:iptv_apps-20261030-test-get-features-endpoint-add-unit-test] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `search_history` endpoint — Add unit tests for the untested public function `search_h (review + tweak) [feat:iptv_apps-20261030-test-search-history-endpoint-add-unit-te] ---

# --- deterministic work supply 2026-10-30 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `resolve_stream_name` endpoint — Add unit tests for the untested public function `res (review + tweak) [feat:iptv_apps-20261030-test-resolve-stream-name-endpoint-add-un] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `list_downloads` endpoint — Add unit tests for the untested public function `list_dow (review + tweak) [feat:iptv_apps-20261030-test-list-downloads-endpoint-add-unit-te] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `list_dvr_recordings` and `delete_dvr_recording` — Add unit tests for the untested pu (review + tweak) [feat:iptv_apps-20261030-test-list-dvr-recordings-and-delete-dvr-] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `verify_pin` endpoint — Add unit tests for the untested public function `verify_pin`  (review + tweak) [feat:iptv_apps-20261030-test-verify-pin-endpoint-add-unit-tests-] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Show error banner when guide fails to load — `iptv-web/src/views/GuideView.vue:77` (`loadG (review + tweak) [feat:iptv_apps-20261030-show-error-banner-when-guide-fails-to-lo] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_parental_settings` endpoint — Add unit tests for the untested public function `g (review + tweak) [feat:iptv_apps-20261030-test-get-parental-settings-endpoint-add-] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `list_blocked_streams` endpoint — Add unit tests for the untested public function `li (review + tweak) [feat:iptv_apps-20261031-test-list-blocked-streams-endpoint-add-u] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Fix N+1 queries in detach_streams_from_groups loop — `iptv-backend/app/services/content_de (review + tweak) [feat:iptv_apps-20261031-fix-n-1-queries-in-detach-streams-from-g] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `block_stream` — Add unit tests for the untested public function `block_stream` in `i (review + tweak) [feat:iptv_apps-20261031-test-block-stream-add-unit-tests-for-the] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `report_usage` endpoint — Add unit tests for the untested public function `report_usa (review + tweak) [feat:iptv_apps-20261031-test-report-usage-endpoint-add-unit-test] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_daily_limit` endpoint — Add unit tests for the untested public function `get_dai (review + tweak) [feat:iptv_apps-20261031-test-get-daily-limit-endpoint-add-unit-t] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `check_time_restrictions_endpoint` — Add unit tests for the untested public function  (review + tweak) [feat:iptv_apps-20261031-test-check-time-restrictions-endpoint-ad] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_subscription` endpoint — Add unit tests for the untested public function `get_su (review + tweak) [feat:iptv_apps-20261031-test-get-subscription-endpoint-add-unit-] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `compare_plans` endpoint — Add unit tests for the untested public function `compare_p (review + tweak) [feat:iptv_apps-20261031-test-compare-plans-endpoint-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `check_feature` endpoint — Add unit tests for the untested public function `check_fea (review + tweak) [feat:iptv_apps-20261031-test-check-feature-endpoint-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `create_stripe_checkout` and `create_stripe_portal` — Add unit tests for the untested (review + tweak) [feat:iptv_apps-20261031-test-create-stripe-checkout-and-create-s] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `stripe_webhook` and `revenuecat_webhook` — Add unit tests for the untested public fu (review + tweak) [feat:iptv_apps-20261031-test-stripe-webhook-and-revenuecat-webho] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `restore_apple_purchase` — Add unit tests for the untested public function in `iptv-b (review + tweak) [feat:iptv_apps-20261031-test-restore-apple-purchase-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_countries` endpoint — Add unit tests for the untested public function `get_count (review + tweak) [feat:iptv_apps-20261031-test-get-countries-endpoint-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_curated_youtube_channels` endpoint — Add unit tests for the untested public func (review + tweak) [feat:iptv_apps-20261031-test-get-curated-youtube-channels-endpoi] ---

# --- deterministic work supply 2026-10-31 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-11-01]: Eliminate N+1 user lookups in win-back email dispatch — `iptv-backend/app/services/win_bac (review + tweak) [feat:iptv_apps-20261101-eliminate-n-1-user-lookups-in-win-back-e] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Test `export_playlist` endpoint — Add unit tests for the untested public function `export_ (review + tweak) [feat:iptv_apps-20261101-test-export-playlist-endpoint-add-unit-t] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Win-back must only mark `win_back_sent_at` when the email actually sent — `iptv-backend/ap (review + tweak) [feat:iptv_apps-20261101-win-back-must-only-mark-win-back-sent-at] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Cap win-back emails per sweep — `dispatch_win_back_emails` in `iptv-backend/app/services/w (review + tweak) [feat:iptv_apps-20261101-cap-win-back-emails-per-sweep-dispatch-w] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Expire stale pending push notifications instead of delivering them days late — `flush_pend (review + tweak) [feat:iptv_apps-20261101-expire-stale-pending-push-notifications-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Per-user daily cap on queued push notifications — `enqueue_notification` in `iptv-backend/ (review + tweak) [feat:iptv_apps-20261101-per-user-daily-cap-on-queued-push-notifi] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Prune delivered/old `QueuedNotification` rows in the daily retention job — nothing deletes (review + tweak) [feat:iptv_apps-20261101-prune-delivered-old-queuednotification-r] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Cap pending EPG reminders per user — `create_reminder` in `iptv-backend/app/routers/remind (review + tweak) [feat:iptv_apps-20261101-cap-pending-epg-reminders-per-user-creat] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Narrow `find_due_reminders` to a SQL time window instead of loading every pending reminder (review + tweak) [feat:iptv_apps-20261101-narrow-find-due-reminders-to-a-sql-time-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Import run counts must not include the batch that was rolled back — in `iptv-backend/app/r (review + tweak) [feat:iptv_apps-20261101-import-run-counts-must-not-include-the-b] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Large-playlist parse test at 100k entries with capped error details — `parse_m3u_content`  (review + tweak) [feat:iptv_apps-20261101-large-playlist-parse-test-at-100k-entrie] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Cap push device tokens per user — `register_device_token` in `iptv-backend/app/services/no (review + tweak) [feat:iptv_apps-20261101-cap-push-device-tokens-per-user-register] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Show an error state with retry in FavoritesView when the load fails — `iptv-web/src/views/ (review + tweak) [feat:iptv_apps-20261101-show-an-error-state-with-retry-in-favori] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Test `get_mapping_suggestions` endpoint — Add unit tests for the untested public function  (review + tweak) [feat:iptv_apps-20261101-test-get-mapping-suggestions-endpoint-ad] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Test `add_channel_to_library` endpoint — Add unit tests for the untested public function ` (review + tweak) [feat:iptv_apps-20261101-test-add-channel-to-library-endpoint-add] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Test `clear_cache` endpoint — Add unit tests for the untested public function `clear_cache (review + tweak) [feat:iptv_apps-20261101-test-clear-cache-endpoint-add-unit-tests] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `get_funnel` endpoint — Add unit tests for the untested public function `get_funnel`  (review + tweak) [feat:iptv_apps-20261102-test-get-funnel-endpoint-add-unit-tests-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test continue watching management endpoints — Add unit tests for the untested public funct (review + tweak) [feat:iptv_apps-20261102-test-continue-watching-management-endpoi] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `notification_pending_max_age_hours` and `notification_max_per_user_per_day` — Add un (review + tweak) [feat:iptv_apps-20261102-test-notification-pending-max-age-hours-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `get_feature` endpoint — Add unit tests for the untested public function in `iptv-bac (review + tweak) [feat:iptv_apps-20261102-test-get-feature-endpoint-add-unit-tests] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `list_favorites` endpoint — Add unit tests for the untested public function `list_fav (review + tweak) [feat:iptv_apps-20261102-test-list-favorites-endpoint-add-unit-te] ---

# --- deterministic work supply 2026-11-02 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `remove_favorite` endpoint — Add unit tests for the untested public function `remove_ (review + tweak) [feat:iptv_apps-20261102-test-remove-favorite-endpoint-add-unit-t] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Public `GET /api/discover/trending` leaks every user's private streams, including provider (review + tweak) [feat:iptv_apps-20261102-public-get-api-discover-trending-leaks-e] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Public `GET /api/discovery/search` searches every user's private, inactive and adult strea (review + tweak) [feat:iptv_apps-20261102-public-get-api-discovery-search-searches] ---

# --- 27B-decomposed from roadmap [2026-11-02]: `POST /api/streams/bulk` with `action: "delete"` skips the dependent-row cleanup, so delet (review + tweak) [feat:iptv_apps-20261102-post-api-streams-bulk-with-action-delete] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Removing a Discover channel from the library has the same missing-dependents FK failure —  (review + tweak) [feat:iptv_apps-20261102-removing-a-discover-channel-from-the-lib] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Discover read endpoints return raw exception text (upstream URLs, DB errors) to clients —  (review + tweak) [feat:iptv_apps-20261102-discover-read-endpoints-return-raw-excep] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Discover personalized/similar/add/remove endpoints also echo exception text — in `iptv-bac (review + tweak) [feat:iptv_apps-20261102-discover-personalized-similar-add-remove] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Any logged-in user can wipe the shared iptv-org catalog cache — `clear_cache` (`POST /api/ (review + tweak) [feat:iptv_apps-20261102-any-logged-in-user-can-wipe-the-shared-i] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Profile create accepts a non-numeric PIN that update rejects — `ProfileCreate.pin` in `ipt (review + tweak) [feat:iptv_apps-20261102-profile-create-accepts-a-non-numeric-pin] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Profile names can become empty after trimming — `ProfileCreate.name` / `ProfileUpdate.name (review + tweak) [feat:iptv_apps-20261102-profile-names-can-become-empty-after-tri] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Rate-limit the outbound-fetch stream endpoints — `iptv-backend/app/routers/streams.py` has (review + tweak) [feat:iptv_apps-20261102-rate-limit-the-outbound-fetch-stream-end] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Rate-limit EPG source mutations — `iptv-backend/app/routers/epg.py` has no `@limiter.limit (review + tweak) [feat:iptv_apps-20261102-rate-limit-epg-source-mutations-iptv-bac] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Rate-limit profile writes (each one bcrypt-hashes a PIN) — `iptv-backend/app/routers/profi (review + tweak) [feat:iptv_apps-20261102-rate-limit-profile-writes-each-one-bcryp] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Rate-limit favorites/watchlist writes — `iptv-backend/app/routers/favorites.py` has no `@l (review + tweak) [feat:iptv_apps-20261102-rate-limit-favorites-watchlist-writes-ip] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Rate-limit Discover library writes — `iptv-backend/app/routers/discover.py` has no `@limit (review + tweak) [feat:iptv_apps-20261102-rate-limit-discover-library-writes-iptv-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Bound the bulk-action request body — `StreamBulkAction` in `iptv-backend/app/schemas/strea (review + tweak) [feat:iptv_apps-20261102-bound-the-bulk-action-request-body-strea] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Search history grows without bound — `search_streams` in `iptv-backend/app/routers/search. (review + tweak) [feat:iptv_apps-20261102-search-history-grows-without-bound-searc] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Parental content check reads other users' streams — `check_content_allowed` (`POST /api/pa (review + tweak) [feat:iptv_apps-20261102-parental-content-check-reads-other-users] ---

# --- 27B-decomposed from roadmap [2026-11-02]: GuideView swallows EPG-source removal failures and its error banner is not announced — in  (review + tweak) [feat:iptv_apps-20261102-guideview-swallows-epg-source-removal-fa] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Test `list_show_episodes` — Add unit tests for the untested public function `list_show_epi (review + tweak) [feat:iptv_apps-20261104-test-list-show-episodes-add-unit-tests-f] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Test `update_download_status` and `delete_download` — Add unit tests for the untested publ (review + tweak) [feat:iptv_apps-20261104-test-update-download-status-and-delete-d] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Test `create_dvr_recording` — Add unit tests for the untested public function `create_dvr_ (review + tweak) [feat:iptv_apps-20261104-test-create-dvr-recording-add-unit-tests] ---

# --- 27B-decomposed from roadmap [2026-11-04]: A `null` in `PUT /api/settings` permanently breaks the user's settings endpoints (500 on e (review + tweak) [feat:iptv_apps-20261104-a-null-in-put-api-settings-permanently-b] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `PUT /api/history/{stream_id}` 500s on the first progress write that carries `watch_durati (review + tweak) [feat:iptv_apps-20261104-put-api-history-stream-id-500s-on-the-fi] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `PUT /api/streams/{id}` with a `null` field corrupts the stream or 500s — `update_stream`  (review + tweak) [feat:iptv_apps-20261104-put-api-streams-id-with-a-null-field-cor] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Profile `is_kids_mode` is accepted by the API but never stored or returned — `ProfileCreat (review + tweak) [feat:iptv_apps-20261104-profile-is-kids-mode-is-accepted-by-the-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `PATCH /api/epg/reminders/{id}` 500s on explicit nulls — `ReminderUpdate` in `iptv-backend (review + tweak) [feat:iptv_apps-20261104-patch-api-epg-reminders-id-500s-on-expli] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `PUT /api/parental/settings` accepts nulls (settings row poisoned, every later call 500s)  (review + tweak) [feat:iptv_apps-20261104-put-api-parental-settings-accepts-nulls-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: EPG source create/update has no field validation and `PUT /api/epg/sources/{id}` 500s on ` (review + tweak) [feat:iptv_apps-20261104-epg-source-create-update-has-no-field-va] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `GET /api/epg/guide` has no upper bound on the requested time window — `get_epg_guide` in  (review + tweak) [feat:iptv_apps-20261104-get-api-epg-guide-has-no-upper-bound-on-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Device pairing: dashless user codes are rejected and `platform` is unbounded — in `iptv-ba (review + tweak) [feat:iptv_apps-20261104-device-pairing-dashless-user-codes-are-r] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Passwords longer than 72 bytes are silently truncated, so two different long passwords log (review + tweak) [feat:iptv_apps-20261104-passwords-longer-than-72-bytes-are-silen] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Profile and Parental PIN/form errors are not announced to screen readers — in `iptv-web/sr (review + tweak) [feat:iptv_apps-20261104-profile-and-parental-pin-form-errors-are] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Import and Guide add-source error messages are not announced — `xtreamError` div in `iptv- (review + tweak) [feat:iptv_apps-20261104-import-and-guide-add-source-error-messag] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Player stream-error overlay and Chromecast error banner are not announced — in `iptv-web/s (review + tweak) [feat:iptv_apps-20261104-player-stream-error-overlay-and-chromeca] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Mobile nav toggle in AppHeader does not expose its expanded state — the hamburger `<button (review + tweak) [feat:iptv_apps-20261104-mobile-nav-toggle-in-appheader-does-not-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Test parental blocking endpoints — Add unit tests for the untested public functions `block (review + tweak) [feat:iptv_apps-20261104-test-parental-blocking-endpoints-add-uni] ---
- [ ] [T1] iptv-backend/tests/test_parental_block_stream.py — Add unit test for `block_stream` verifying that unauthorized access (missing/invalid token) returns 401 Unauthorized. VERIFY: `pytest iptv-backend/tests/test_parental_block_stream.py::test_block_stream_unauthorized -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-blocking-endpoints-add-uni]
- [ ] [T1] iptv-backend/tests/test_parental_list_blocked_streams.py — Add unit test for `list_blocked_streams` verifying that it returns a list of blocked stream IDs for the authenticated profile. VERIFY: `pytest iptv-backend/tests/test_parental_list_blocked_streams.py::test_list_blocked_streams_returns_ids -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-blocking-endpoints-add-uni]
- [ ] [T1] iptv-backend/tests/test_parental_list_blocked_streams.py — Add unit test for `list_blocked_streams` verifying that it returns an empty list when no streams are blocked for the profile. VERIFY: `pytest iptv-backend/tests/test_parental_list_blocked_streams.py::test_list_blocked_streams_empty -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-blocking-endpoints-add-uni]
- [ ] [T1] iptv-backend/tests/test_parental_list_blocked_streams.py — Add unit test for `list_blocked_streams` verifying that it returns 401 Unauthorized for invalid or missing authentication. VERIFY: `pytest iptv-backend/tests/test_parental_list_blocked_streams.py::test_list_blocked_streams_unauthorized -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-blocking-endpoints-add-uni]

# --- 27B-decomposed from roadmap [2026-11-04]: Test parental usage reporting endpoints — Add unit tests for the untested public functions (review + tweak) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-] ---
- [ ] [T1] iptv-backend/tests/test_parental_usage.py — Add unit test for `report_usage` verifying that a valid usage event increments the daily counter in the mock database session and returns 200 OK. VERIFY: `pytest iptv-backend/tests/test_parental_usage.py::test_report_usage_increments_counter -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-]
- [ ] [T1] iptv-backend/tests/test_parental_usage.py — Add unit test for `report_usage` verifying that an invalid profile ID returns 404 Not Found and does not modify the database. VERIFY: `pytest iptv-backend/tests/test_parental_usage.py::test_report_usage_invalid_profile -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-]
- [ ] [T1] iptv-backend/tests/test_parental_usage.py — Add unit test for `report_usage` verifying that exceeding the daily limit triggers a 429 Too Many Requests response and blocks further usage. VERIFY: `pytest iptv-backend/tests/test_parental_usage.py::test_report_usage_exceeds_limit -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-]
- [ ] [T1] iptv-backend/tests/test_parental_usage.py — Add unit test for `get_daily_limit` verifying that it returns the correct limit value from the parental settings model for an active profile. VERIFY: `pytest iptv-backend/tests/test_parental_usage.py::test_get_daily_limit_returns_correct_value -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-]
- [ ] [T1] iptv-backend/tests/test_parental_usage.py — Add unit test for `get_daily_limit` verifying that it returns a default limit value when no specific parental setting exists for the profile. VERIFY: `pytest iptv-backend/tests/test_parental_usage.py::test_get_daily_limit_default_value -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-]
- [ ] [T1] iptv-backend/tests/test_parental_usage.py — Add unit test for `get_daily_limit` verifying that it returns 404 Not Found when the profile does not exist. VERIFY: `pytest iptv-backend/tests/test_parental_usage.py::test_get_daily_limit_invalid_profile -v` (cat:test; multifile:no) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-]
- [ ] [T2] iptv-backend/app/routers/parental.py — Refactor `report_usage` to extract limit checking logic into a private helper `_check_daily_limit` to improve testability and clarity. VERIFY: `python -m py_compile iptv-backend/app/routers/parental.py` (cat:python; multifile:no) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-]
- [ ] [T2] iptv-backend/app/routers/parental.py — Refactor `get_daily_limit` to use a consistent error handling pattern with `api_errors` for missing profiles. VERIFY: `python -m py_compile iptv-backend/app/routers/parental.py` (cat:python; multifile:no) [feat:iptv_apps-20261104-test-parental-usage-reporting-endpoints-]

# --- 27B-decomposed from roadmap [2026-11-06]: Test subscription plan endpoints — Add unit tests for the untested public functions `get_s (review + tweak) [feat:iptv_apps-20261106-test-subscription-plan-endpoints-add-uni] ---
- [ ] [T1] iptv-backend/tests/test_subscription_router.py — Add `test_get_plans_returns_list_of_plans` mocking `get_db` and verifying the response contains plan objects with expected keys. VERIFY: `cd iptv-backend && python -m pytest tests/test_subscription_router.py::test_get_plans_returns_list_of_plans -v`. (cat:test; multifile:no) [feat:iptv_apps-20261106-test-subscription-plan-endpoints-add-uni]
- [ ] [T1] iptv-backend/tests/test_subscription_router.py — Add `test_get_subscription_returns_active_plan` mocking a user with an active subscription and verifying the returned plan matches the expected tier. VERIFY: `cd iptv-backend && python -m pytest tests/test_subscription_router.py::test_get_subscription_returns_active_plan -v`. (cat:test; multifile:no) [feat:iptv_apps-20261106-test-subscription-plan-endpoints-add-uni]
- [ ] [T1] iptv-backend/tests/test_subscription_router.py — Add `test_get_subscription_returns_none_for_no_sub` mocking a user without an active subscription and verifying the response is null or 404 as per implementation. VERIFY: `cd iptv-backend && python -m pytest tests/test_subscription_router.py::test_get_subscription_returns_none_for_no_sub -v`. (cat:test; multifile:no) [feat:iptv_apps-20261106-test-subscription-plan-endpoints-add-uni]
- [ ] [T1] iptv-backend/tests/test_subscription_router.py — Add `test_compare_plans_returns_differences` mocking two distinct plans and verifying the comparison logic highlights feature deltas correctly. VERIFY: `cd iptv-backend && python -m pytest tests/test_subscription_router.py::test_compare_plans_returns_differences -v`. (cat:test; multifile:no) [feat:iptv_apps-20261106-test-subscription-plan-endpoints-add-uni]
- [ ] [T1] iptv-backend/tests/test_subscription_router.py — Add `test_compare_plans_same_plan_returns_empty_diff` mocking identical plans and verifying the comparison returns an empty difference set. VERIFY: `cd iptv-backend && python -m pytest tests/test_subscription_router.py::test_compare_plans_same_plan_returns_empty_diff -v`. (cat:test; multifile:no) [feat:iptv_apps-20261106-test-subscription-plan-endpoints-add-uni]
- [ ] [T2] iptv-backend/tests/test_subscription_router.py — Add `test_get_plans_filters_inactive_plans` mocking a mix of active and inactive plans and verifying only active ones are returned. VERIFY: `cd iptv-backend && python -m pytest tests/test_subscription_router.py::test_get_plans_filters_inactive_plans -v`. (cat:test; multifile:no) [feat:iptv_apps-20261106-test-subscription-plan-endpoints-add-uni]

# --- 27B-decomposed from roadmap [2026-11-06]: Test webhook handlers — Add unit tests for the untested public functions `stripe_webhook`  (review + tweak) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for] ---
- [ ] [T1] iptv-backend/tests/test_subscription_webhooks.py — Add test `test_stripe_webhook_valid_signature` mocking `stripe.Webhook.construct_event` to return a valid event and assert 200 response. VERIFY: `pytest iptv-backend/tests/test_subscription_webhooks.py::test_stripe_webhook_valid_signature -v` (cat:test; multifile:no) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for]
- [ ] [T1] iptv-backend/tests/test_subscription_webhooks.py — Add test `test_stripe_webhook_invalid_signature` mocking `stripe.Webhook.construct_event` to raise `stripe.error.SignatureVerificationError` and assert 400 response. VERIFY: `pytest iptv-backend/tests/test_subscription_webhooks.py::test_stripe_webhook_invalid_signature -v` (cat:test; multifile:no) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for]
- [ ] [T1] iptv-backend/tests/test_subscription_webhooks.py — Add test `test_stripe_webhook_invoice_paid` mocking event type `invoice.payment_succeeded` and verifying subscription status update logic is triggered. VERIFY: `pytest iptv-backend/tests/test_subscription_webhooks.py::test_stripe_webhook_invoice_paid -v` (cat:test; multifile:no) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for]
- [ ] [T1] iptv-backend/tests/test_subscription_webhooks.py — Add test `test_stripe_webhook_customer_deleted` mocking event type `customer.deleted` and verifying subscription cancellation logic. VERIFY: `pytest iptv-backend/tests/test_subscription_webhooks.py::test_stripe_webhook_customer_deleted -v` (cat:test; multifile:no) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for]
- [ ] [T1] iptv-backend/tests/test_subscription_webhooks.py — Add test `test_revenuecat_webhook_valid_payload` mocking valid RevenueCat payload and asserting 200 response with correct processing. VERIFY: `pytest iptv-backend/tests/test_subscription_webhooks.py::test_revenuecat_webhook_valid_payload -v` (cat:test; multifile:no) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for]
- [ ] [T1] iptv-backend/tests/test_subscription_webhooks.py — Add test `test_revenuecat_webhook_invalid_signature` mocking invalid RevenueCat signature and asserting 401/403 response. VERIFY: `pytest iptv-backend/tests/test_subscription_webhooks.py::test_revenuecat_webhook_invalid_signature -v` (cat:test; multifile:no) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for]
- [ ] [T1] iptv-backend/tests/test_subscription_webhooks.py — Add test `test_revenuecat_webhook_app_store_notification` mocking App Store notification type and verifying subscription activation. VERIFY: `pytest iptv-backend/tests/test_subscription_webhooks.py::test_revenuecat_webhook_app_store_notification -v` (cat:test; multifile:no) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for]
- [ ] [T1] iptv-backend/tests/test_subscription_webhooks.py — Add test `test_revenuecat_webhook_play_store_notification` mocking Play Store notification type and verifying subscription activation. VERIFY: `pytest iptv-backend/tests/test_subscription_webhooks.py::test_revenuecat_webhook_play_store_notification -v` (cat:test; multifile:no) [feat:iptv_apps-20261106-test-webhook-handlers-add-unit-tests-for]

# --- 27B-decomposed from roadmap [2026-11-06]: M3U import mangles the channel name whenever a quoted attribute contains a comma (`group-t (review + tweak) [feat:iptv_apps-20261106-m3u-import-mangles-the-channel-name-when] ---
- [ ] [T1] iptv-backend/app/routers/streams.py — Add module-level function `_extinf_title(line: str) -> str | None` that scans characters to find the first comma outside double quotes and returns the stripped text after it, or None if no such comma exists. VERIFY: `cd iptv-backend && python -c "from app.routers.streams import _extinf_title; assert _extinf_title('#EXTINF:-1 group-title=\"Movies, Action\" tvg-logo=\"http://l/x.png\",Die Hard') == 'Die Hard'; assert _extinf_title('NoComma') is None; print('OK')"`. (cat:python; multifile:no) [feat:iptv_apps-20261106-m3u-import-mangles-the-channel-name-when]
- [ ] [T2] iptv-backend/tests/test_m3u_extinf_title.py — Add test file verifying `_extinf_title` handles quoted commas, unquoted commas, and missing commas correctly. VERIFY: `cd iptv-backend && pytest tests/test_m3u_extinf_title.py -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-m3u-import-mangles-the-channel-name-when]
- [ ] [T3] iptv-backend/app/routers/streams.py — Modify `parse_m3u_content` to use `_extinf_title(line)` instead of the regex `re.search(r',(.+)$', line)` for extracting the channel name. VERIFY: `cd iptv-backend && python -c "from app.routers.streams import parse_m3u_content; r = parse_m3u_content('#EXTINF:-1 group-title=\"Movies, Action\" tvg-logo=\"http://l/x.png\",Die Hard\n'); assert r['name'] == 'Die Hard', r; print('OK')"`. (cat:python; multifile:no) [feat:iptv_apps-20261106-m3u-import-mangles-the-channel-name-when]
- [ ] [T4] iptv-backend/tests/test_m3u_extinf_title.py — Add test case asserting `parse_m3u_content` returns name `Die Hard`, category `Movies, Action`, and correct logo URL for the specific quoted-comma line. VERIFY: `cd iptv-backend && pytest tests/test_m3u_extinf_title.py::test_parse_m3u_content_quoted_comma -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-m3u-import-mangles-the-channel-name-when]
- [ ] [T5] iptv-backend/tests/test_m3u_extinf_title.py — Add test case asserting `parse_m3u_content` preserves a title containing its own comma (e.g., `,Comma, Name`) as the full name. VERIFY: `cd iptv-backend && pytest tests/test_m3u_extinf_title.py::test_parse_m3u_content_title_with_comma -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-m3u-import-mangles-the-channel-name-when]

# --- 27B-decomposed from roadmap [2026-11-06]: Provider username/password are interpolated into URLs without percent-encoding, so any cre (review + tweak) [feat:iptv_apps-20261106-provider-username-password-are-interpola] ---
- [ ] [T1] iptv-backend/app/services/url_credentials.py — Add `append_credentials(url: str, username: str, password: str) -> str` that appends `username` and `password` query params using `urllib.parse.quote(..., safe="")`, switching from `?` to `&` if the URL already contains a query string. VERIFY: `cd iptv-backend && python -c "from app.services.url_credentials import append_credentials; assert append_credentials('http://h/get.php', 'u', 'p&w#1 x') == 'http://h/get.php?username=u&password=p%26w%231%20x'; assert append_credentials('http://h/get.php?x=1', 'u', 'p&w') == 'http://h/get.php?x=1&username=u&password=p%26w'". (cat:python; multifile:no) [feat:iptv_apps-20261106-provider-username-password-are-interpola]
- [ ] [T1] iptv-backend/app/services/url_credentials.py — Add `xtream_play_url(server_url: str, username: str, password: str, stream_id: int, ext: str) -> str` that constructs the path `/{username}/{password}/{stream_id}.{ext}` with `urllib.parse.quote(..., safe="")` applied to `username` and `password`. VERIFY: `cd iptv-backend && python -c "from app.services.url_credentials import xtream_play_url; assert xtream_play_url('http://h', 'u/p', 'p@w', 123, 'mp4') == 'http://h/u%2Fp/p%40w/123.mp4'". (cat:python; multifile:no) [feat:iptv_apps-20261106-provider-username-password-are-interpola]
- [ ] [T2] iptv-backend/tests/test_url_credentials.py — Add unit tests for `append_credentials` verifying percent-encoding of special characters (`&`, `#`, `+`, `%`, space, `/`) and correct separator logic (`?` vs `&`), and for `xtream_play_url` verifying path segment quoting. VERIFY: `cd iptv-backend && pytest tests/test_url_credentials.py -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-provider-username-password-are-interpola]
- [ ] [T3] iptv-backend/app/routers/streams.py — Import `append_credentials` and replace manual f-string credential interpolation in `import_xtream` (line ~2245), pasted-URL import (~1706), `refresh_source` (~2032), and `check_stream_health` (~2492) with calls to `append_credentials`, preserving existing `has_embedded_credentials` guards. VERIFY: `cd iptv-backend && grep -n "username={data.username}" app/routers/streams.py | wc -l` returns 0. (cat:python; multifile:no) [feat:iptv_apps-20261106-provider-username-password-are-interpola]
- [ ] [T3] iptv-backend/app/routers/streams.py — Import `xtream_play_url` and replace manual path/query construction in `proxy_stream` (lines ~2701, ~2708, ~2794) with calls to `xtream_play_url`, preserving existing guards. VERIFY: `cd iptv-backend && grep -n "xtream_username}/{xtream_password}" app/routers/streams.py | wc -l` returns 0. (cat:python; multifile:no) [feat:iptv_apps-20261106-provider-username-password-are-interpola]
- [ ] [T2] iptv-backend/tests/test_xtream_credentials_encoding.py — Add integration tests using `origin.route` fixtures to assert that `POST /api/streams/import/xtream` with password `p&w#1 x` results in the provider handler receiving `req.query_params["password"] == "p&w#1 x"`. VERIFY: `cd iptv-backend && pytest tests/test_xtream_credentials_encoding.py -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-provider-username-password-are-interpola]

# --- 27B-decomposed from roadmap [2026-11-06]: An empty `tvg-name=""` makes the importer drop a perfectly named channel — in `parse_m3u_c (review + tweak) [feat:iptv_apps-20261106-an-empty-tvg-name-makes-the-importer-dro] ---
- [ ] [T1] iptv-backend/app/routers/streams.py — In `parse_m3u_content`, modify the `tvg-name` regex handling to only assign `current_info['name']` if `m.group(1).strip()` is non-empty, storing the stripped value. VERIFY: `cd iptv-backend && pytest tests/test_m3u_empty_tvg_name.py -q`. (cat:python; multifile:no) [feat:iptv_apps-20261106-an-empty-tvg-name-makes-the-importer-dro]
- [ ] [T2] iptv-backend/tests/test_m3u_empty_tvg_name.py — Add a test case asserting that an M3U line with `tvg-name=""` and a trailing title "Real Name" results in the stream being imported with name "Real Name". VERIFY: `cd iptv-backend && pytest tests/test_m3u_empty_tvg_name.py::test_empty_tvg_name_falls_back_to_trailing_title -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-an-empty-tvg-name-makes-the-importer-dro]
- [ ] [T2] iptv-backend/tests/test_m3u_empty_tvg_name.py — Add a test case asserting that an M3U line with `tvg-name="   "` (whitespace only) and a trailing title "Real Name" results in the stream being imported with name "Real Name". VERIFY: `cd iptv-backend && pytest tests/test_m3u_empty_tvg_name.py::test_whitespace_tvg_name_falls_back_to_trailing_title -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-an-empty-tvg-name-makes-the-importer-dro]
- [ ] [T2] iptv-backend/tests/test_m3u_empty_tvg_name.py — Add a test case asserting that an M3U line with `tvg-name="Explicit Name"` and a trailing title "Real Name" results in the stream being imported with name "Explicit Name". VERIFY: `cd iptv-backend && pytest tests/test_m3u_empty_tvg_name.py::test_non_empty_tvg_name_beats_trailing_title -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-an-empty-tvg-name-makes-the-importer-dro]
- [ ] [T2] iptv-backend/tests/test_m3u_empty_tvg_name.py — Add a test case asserting that an M3U line with `tvg-name=""` and no trailing title (or empty trailing title) is dropped and reported in the `ErrorCollector` with the message "Stream URL has an #EXTINF entry with no channel name". VERIFY: `cd iptv-backend && pytest tests/test_m3u_empty_tvg_name.py::test_both_blank_dropped_with_error -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-an-empty-tvg-name-makes-the-importer-dro]

# --- 27B-decomposed from roadmap [2026-11-06]: `POST /api/streams/import/xtream` echoes the provider password back in its 400 detail — `i (review + tweak) [feat:iptv_apps-20261106-post-api-streams-import-xtream-echoes-th] ---
- [ ] [T1] iptv-backend/app/services/import_errors.py — Add `redact_text` function that masks URLs and common credential patterns in input strings. VERIFY: `cd iptv-backend && python -c "from app.services.import_errors import redact_text; assert 'password' not in redact_text('http://user:S3cr3tPw@host/path')"`. (cat:python; multifile:no) [feat:iptv_apps-20261106-post-api-streams-import-xtream-echoes-th]
- [ ] [T2] iptv-backend/tests/test_import_errors.py — Add unit tests for `redact_text` verifying it masks passwords in URLs and preserves non-sensitive text. VERIFY: `cd iptv-backend && pytest tests/test_import_errors.py -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-post-api-streams-import-xtream-echoes-th]
- [ ] [T3] iptv-backend/app/routers/streams.py — Import `redact_text` from `app.services.import_errors` and update `import_xtream` error handling to use `detail=f"Failed to connect to Xtream server: {redact_text(str(exc))}"`. VERIFY: `cd iptv-backend && grep -n "redact_text" app/routers/streams.py | grep -q "import_xtream" || exit 1`. (cat:python; multifile:no) [feat:iptv_apps-20261106-post-api-streams-import-xtream-echoes-th]
- [ ] [T4] iptv-backend/tests/test_xtream_error_redaction.py — Create test file with fake origin fixture returning 401, asserting `S3cr3tPw` is not in response detail and detail starts with "Failed to connect to Xtream server". VERIFY: `cd iptv-backend && pytest tests/test_xtream_error_redaction.py -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-post-api-streams-import-xtream-echoes-th]
- [ ] [T5] iptv-backend/tests/test_streams_router_gaps.py — Ensure existing tests still pass with the redacted error message format. VERIFY: `cd iptv-backend && pytest tests/test_streams_router_gaps.py -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-post-api-streams-import-xtream-echoes-th]

# --- 27B-decomposed from roadmap [2026-11-06]: A missing or non-numeric `expires_in` turns the playback-token refresh into a tight loop — (review + tweak) [feat:iptv_apps-20261106-a-missing-or-non-numeric-expires-in-turn] ---
- [ ] [T1] iptv-web/src/utils/playbackToken.ts — Add `!Number.isFinite(expiresInSeconds)` guard in `playbackRefreshDelayMs` to return `MIN_PLAYBACK_REFRESH_MS`. VERIFY: `cd iptv-web && npx vitest run src/utils/__tests__/playbackToken.test.ts -t "non-finite"`. (cat:typescript; multifile:no) [feat:iptv_apps-20261106-a-missing-or-non-numeric-expires-in-turn]
- [ ] [T1] iptv-web/src/utils/playbackRetry.ts — Add `!Number.isFinite(stall)` guard in `retryDelayMs` to treat input as 0. VERIFY: `cd iptv-web && npx vitest run src/utils/__tests__/playbackRetry.test.ts -t "non-finite"`. (cat:typescript; multifile:no) [feat:iptv_apps-20261106-a-missing-or-non-numeric-expires-in-turn]
- [ ] [T2] iptv-web/src/utils/__tests__/playbackToken.test.ts — Add test cases for `undefined`, `NaN`, and `Infinity` inputs to `playbackRefreshDelayMs` expecting `MIN_PLAYBACK_REFRESH_MS`. VERIFY: `cd iptv-web && npx vitest run src/utils/__tests__/playbackToken.test.ts`. (cat:test; multifile:no) [feat:iptv_apps-20261106-a-missing-or-non-numeric-expires-in-turn]
- [ ] [T2] iptv-web/src/utils/__tests__/playbackRetry.test.ts — Add test case for `NaN` input to `retryDelayMs` expecting equality with `retryDelayMs(0)`. VERIFY: `cd iptv-web && npx vitest run src/utils/__tests__/playbackRetry.test.ts`. (cat:test; multifile:no) [feat:iptv_apps-20261106-a-missing-or-non-numeric-expires-in-turn]

# --- 27B-decomposed from roadmap [2026-11-06]: Failed Settings toggles are silent and leave the checkbox showing a value that was never s (review + tweak) [feat:iptv_apps-20261106-failed-settings-toggles-are-silent-and-l] ---
- [ ] [T1] iptv-web/src/views/SettingsView.vue — Add `saveError` ref and `saveSetting(fn, revert)` helper that awaits store call in try/catch, clears `saveError` on success, sets `saveError.value = settingsStore.error || 'Failed to save setting'` and calls `revert()` on failure. VERIFY: `grep -q "const saveSetting" iptv-web/src/views/SettingsView.vue && grep -q "saveError" iptv-web/src/views/SettingsView.vue` (cat:vue; multifile:no) [feat:iptv_apps-20261106-failed-settings-toggles-are-silent-and-l]
- [ ] [T2] iptv-web/src/views/SettingsView.vue — Update `@change` handlers for Closed captions, Autoplay, Muted-by-default checkboxes and default-quality select to use `saveSetting` with appropriate revert logic restoring `event.target.checked` or `.value` to store state. VERIFY: `grep -q "saveSetting" iptv-web/src/views/SettingsView.vue && grep -c "saveSetting" iptv-web/src/views/SettingsView.vue | grep -q "4"` (cat:vue; multifile:no) [feat:iptv_apps-20261106-failed-settings-toggles-are-silent-and-l]
- [ ] [T3] iptv-web/src/views/SettingsView.vue — Render `<p v-if="saveError" role="alert" data-testid="settings-save-error">{{ saveError }}</p>` near the top of the settings form. VERIFY: `grep -q 'data-testid="settings-save-error"' iptv-web/src/views/SettingsView.vue` (cat:vue; multifile:no) [feat:iptv_apps-20261106-failed-settings-toggles-are-silent-and-l]
- [ ] [T4] iptv-web/src/views/__tests__/SettingsView.behavior.test.ts — Add test case where `setAutoplay` rejects, trigger change on autoplay checkbox, assert alert text is displayed and checkbox is reverted to `mockSettings.autoplay`. VERIFY: `cd iptv-web && npx vitest run src/views/__tests__/SettingsView.behavior.test.ts -t "reverts checkbox on failure"` (cat:test; multifile:no) [feat:iptv_apps-20261106-failed-settings-toggles-are-silent-and-l]
- [ ] [T5] iptv-web/src/views/__tests__/SettingsView.behavior.test.ts — Add test case where a subsequent successful setting change clears the `saveError` alert. VERIFY: `cd iptv-web && npx vitest run src/views/__tests__/SettingsView.behavior.test.ts -t "clears error on success"` (cat:test; multifile:no) [feat:iptv_apps-20261106-failed-settings-toggles-are-silent-and-l]

# --- 27B-decomposed from roadmap [2026-11-06]: A refresh-token rejection leaves the previous account's `active_profile_id` behind, so the (review + tweak) [feat:iptv_apps-20261106-a-refresh-token-rejection-leaves-the-pre] ---
- [ ] [T1] iptv-web/src/services/api.ts — Add `localStorage.removeItem('active_profile_id')` inside the `endSession` function immediately after removing `access_token` and `refresh_token`. VERIFY: `cd iptv-web && npx vitest run src/services/__tests__/api.refreshInterceptor.test.ts -t "clears active_profile_id on endSession"`. (cat:typescript; multifile:no) [feat:iptv_apps-20261106-a-refresh-token-rejection-leaves-the-pre]
- [ ] [T1] iptv-web/src/services/api.ts — Add `localStorage.removeItem('active_profile_id')` in the 401 refresh handler branch before calling `redirectToLogin()` when no valid refresh token is present. VERIFY: `cd iptv-web && npx vitest run src/services/__tests__/api.refreshInterceptor.test.ts -t "clears active_profile_id on 401 refresh"`. (cat:typescript; multifile:no) [feat:iptv_apps-20261106-a-refresh-token-rejection-leaves-the-pre]
- [ ] [T2] iptv-web/src/services/__tests__/api.refreshInterceptor.test.ts — Add a test case that seeds `localStorage.setItem('active_profile_id', '7')`, mocks `/auth/refresh` to return 401, triggers the interceptor, and asserts `localStorage.getItem('active_profile_id')` is null. VERIFY: `cd iptv-web && npx vitest run src/services/__tests__/api.refreshInterceptor.test.ts`. (cat:test; multifile:no) [feat:iptv_apps-20261106-a-refresh-token-rejection-leaves-the-pre]
- [ ] [T2] iptv-web/src/services/__tests__/api.refreshInterceptor.test.ts — Add a test case that seeds `localStorage.setItem('active_profile_id', '7')`, mocks the absence of a refresh token, triggers the interceptor, and asserts `localStorage.getItem('active_profile_id')` is null. VERIFY: `cd iptv-web && npx vitest run src/services/__tests__/api.refreshInterceptor.test.ts`. (cat:test; multifile:no) [feat:iptv_apps-20261106-a-refresh-token-rejection-leaves-the-pre]

# --- 27B-decomposed from roadmap [2026-11-06]: Blocked or unavailable localStorage crashes the web app at startup — `iptv-web/src/stores/ (review + tweak) [feat:iptv_apps-20261106-blocked-or-unavailable-localstorage-cras] ---
- [ ] [T1] iptv-web/src/stores/theme.ts — Wrap `localStorage.getItem('theme')` and `localStorage.setItem('theme', ...)` in try/catch blocks within `getInitialTheme` and `applyTheme`, returning/setting the system default on failure. VERIFY: `cd iptv-web && npx vitest run src/stores/__tests__/theme.test.ts` (cat:typescript; multifile:no) [feat:iptv_apps-20261106-blocked-or-unavailable-localstorage-cras]
- [ ] [T1] iptv-web/src/stores/preferences.ts — Wrap `localStorage.getItem` calls in `ref` initializers and `localStorage.setItem` calls in `setPreferredCountry`/`setShowAdultContent` with try/catch, falling back to empty string/false defaults on error. VERIFY: `cd iptv-web && npx vitest run src/stores/__tests__/preferences.test.ts` (cat:typescript; multifile:no) [feat:iptv_apps-20261106-blocked-or-unavailable-localstorage-cras]
- [ ] [T2] iptv-web/src/stores/__tests__/theme.test.ts — Add test case stubbing `localStorage` to throw `SecurityError` on all methods, asserting store creation succeeds with default theme and `applyTheme` does not throw. VERIFY: `cd iptv-web && npx vitest run src/stores/__tests__/theme.test.ts` (cat:test; multifile:no) [feat:iptv_apps-20261106-blocked-or-unavailable-localstorage-cras]
- [ ] [T2] iptv-web/src/stores/__tests__/preferences.test.ts — Add test case stubbing `localStorage` to throw `SecurityError`, asserting store creation succeeds with defaults and setters update in-memory state without throwing. VERIFY: `cd iptv-web && npx vitest run src/stores/__tests__/preferences.test.ts` (cat:test; multifile:no) [feat:iptv_apps-20261106-blocked-or-unavailable-localstorage-cras]

# --- 27B-decomposed from roadmap [2026-11-06]: Same blocked-storage crash for locale, onboarding and the active profile — `detectInitialL (review + tweak) [feat:iptv_apps-20261106-same-blocked-storage-crash-for-locale-on] ---
- [ ] [T2] iptv-web/src/i18n/index.ts — Wrap `localStorage.getItem` and `localStorage.setItem` calls inside `detectInitialLocale` and `setLocale` in try/catch blocks, returning `navigator.language` fallback for reads and ignoring errors for writes. VERIFY: `cd iptv-web && npx vitest run src/i18n/__tests__/i18n.test.ts -t "detectInitialLocale"`. (cat:typescript; multifile:no) [feat:iptv_apps-20261106-same-blocked-storage-crash-for-locale-on]
- [ ] [T2] iptv-web/src/i18n/__tests__/i18n.test.ts — Add test cases mocking `localStorage` to throw, asserting `detectInitialLocale()` returns a supported locale and `setLocale('es')` does not throw while updating internal state. VERIFY: `cd iptv-web && npx vitest run src/i18n/__tests__/i18n.test.ts`. (cat:test; multifile:no) [feat:iptv_apps-20261106-same-blocked-storage-crash-for-locale-on]
- [ ] [T2] iptv-web/src/stores/onboarding.ts — Wrap `localStorage.getItem(DONE_KEY)` in the store initializer and `localStorage.setItem` in `finish()` with try/catch, defaulting to `completed: false` on read failure and ignoring write errors. VERIFY: `cd iptv-web && npx vitest run src/stores/__tests__/onboarding.test.ts -t "constructs"`. (cat:typescript; multifile:no) [feat:iptv_apps-20261106-same-blocked-storage-crash-for-locale-on]
- [ ] [T2] iptv-web/src/stores/__tests__/onboarding.test.ts — Add tests verifying the store constructs with `completed === false` when `localStorage` throws, and that `finish()` updates state without throwing. VERIFY: `cd iptv-web && npx vitest run src/stores/__tests__/onboarding.test.ts`. (cat:test; multifile:no) [feat:iptv_apps-20261106-same-blocked-storage-crash-for-locale-on]
- [ ] [T2] iptv-web/src/stores/profiles.ts — Wrap `localStorage.getItem` in `readStoredActiveId` and `localStorage.setItem` in `setActiveProfile` with try/catch, returning `null` on read failure and ignoring write errors while updating the in-memory ref. VERIFY: `cd iptv-web && npx vitest run src/stores/__tests__/profiles.test.ts -t "setActiveProfile"`. (cat:typescript; multifile:no) [feat:iptv_apps-20261106-same-blocked-storage-crash-for-locale-on]
- [ ] [T2] iptv-web/src/stores/__tests__/profiles.test.ts — Add tests verifying `setActiveProfile(3)` does not throw when `localStorage` is broken and results in `activeProfileId === 3`. VERIFY: `cd iptv-web && npx vitest run src/stores/__tests__/profiles.test.ts`. (cat:test; multifile:no) [feat:iptv_apps-20261106-same-blocked-storage-crash-for-locale-on]

# --- 27B-decomposed from roadmap [2026-11-06]: `#EXTGRP:` group lines are ignored, so playlists that use them import everything as "Impor (review + tweak) [feat:iptv_apps-20261106-extgrp-group-lines-are-ignored-so-playli] ---
- [ ] [T1] iptv-backend/app/routers/streams.py — Add `has_group_title` flag to `current_info` dict initialization and set it to `True` when `group-title` attribute is parsed in `#EXTINF` line. VERIFY: `cd iptv-backend && python -c "from app.routers.streams import parse_m3u_content; print('ok')"` (cat:python; multifile:no) [feat:iptv_apps-20261106-extgrp-group-lines-are-ignored-so-playli]
- [ ] [T2] iptv-backend/app/routers/streams.py — Add `elif line.startswith('#EXTGRP:') and current_info:` branch to `parse_m3u_content` that sets `current_info['category']` and `current_info['group']` from stripped text after colon, only if `has_group_title` is False. VERIFY: `cd iptv-backend && python -c "from app.routers.streams import parse_m3u_content; print('ok')"` (cat:python; multifile:no) [feat:iptv_apps-20261106-extgrp-group-lines-are-ignored-so-playli]
- [ ] [T3] iptv-backend/tests/test_m3u_extgrp.py — Create new test file with cases: EXTGRP sets category/group when no group-title, group-title wins over EXTGRP, stray EXTGRP before EXTINF is ignored, blank EXTGRP leaves 'Imported'. VERIFY: `cd iptv-backend && pytest tests/test_m3u_extgrp.py -q` (cat:test; multifile:no) [feat:iptv_apps-20261106-extgrp-group-lines-are-ignored-so-playli]
- [ ] [T4] iptv-backend/tests/test_streams_m3u_import.py — Verify existing M3U import tests still pass with new EXTGRP logic, ensuring no regression in standard `#EXTINF` parsing without EXTGRP lines. VERIFY: `cd iptv-backend && pytest tests/test_streams_m3u_import.py -q` (cat:test; multifile:no) [feat:iptv_apps-20261106-extgrp-group-lines-are-ignored-so-playli]

# --- 27B-decomposed from roadmap [2026-11-06]: `iptv-backend/API.md` documents eight endpoints that do not exist and a dead base URL — `G (review + tweak) [feat:iptv_apps-20261106-iptv-backend-api-md-documents-eight-endp] ---
- [ ] [T1] iptv-backend/tests/test_api_md_drift.py — Add `extract_endpoints` function to parse API.md for method/path pairs and normalize path parameters. VERIFY: `cd iptv-backend && pytest tests/test_api_md_drift.py::test_extract_endpoints -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-iptv-backend-api-md-documents-eight-endp]
- [ ] [T1] iptv-backend/tests/test_api_md_drift.py — Add `test_api_md_drift` function to assert all extracted endpoints exist in `app.openapi()["paths"]`. VERIFY: `cd iptv-backend && pytest tests/test_api_md_drift.py::test_api_md_drift -q`. (cat:test; multifile:no) [feat:iptv_apps-20261106-iptv-backend-api-md-documents-eight-endp]
- [ ] [T2] iptv-backend/API.md — Update Base URL to `https://chickadeestream-production.up.railway.app/api` and remove "(admin only)" from Streams section. VERIFY: `grep -q "https://chickadeestream-production.up.railway.app/api" iptv-backend/API.md && ! grep -q "(admin only)" iptv-backend/API.md`. (cat:docs; multifile:no) [feat:iptv_apps-20261106-iptv-backend-api-md-documents-eight-endp]
- [ ] [T2] iptv-backend/API.md — Replace stale endpoint bullets with real routes (`GET /api/epg/now-playing/{stream_id}`, `GET /api/epg/guide`, `GET /api/history`, `PUT /api/history/{stream_id}`, `GET /api/discover/trending`, `GET /api/discovery/trending`). VERIFY: `cd iptv-backend && pytest tests/test_api_md_drift.py -q`. (cat:docs; multifile:no) [feat:iptv_apps-20261106-iptv-backend-api-md-documents-eight-endp]
