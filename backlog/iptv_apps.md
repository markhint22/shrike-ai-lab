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
