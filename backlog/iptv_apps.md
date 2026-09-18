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
- [ ] [T1] iptv-ios/ChickadeeStreams/ViewModels/PlayerViewModel.swift — Extract seek target calculation into a pure static function `static func calculateSeekTarget(currentTime: Double, seconds: Int, isForward: Bool, duration: Double, isLive: Bool, seekableStart: Double?, seekableEnd: Double?) -> Double` that returns `max(0, currentTime - seconds)` for backward and `min(currentTime + seconds, seekableEnd ?? duration)` for forward, ensuring it never returns 0 if `currentTime > 0` and `isLive` is true. VERIFY: `swift test --filter PlayerViewModelTests.testCalculateSeekTarget_LiveForwardDoesNotZero`. (cat:ios; multifile:no)
- [ ] [T1] iptv-ios/ChickadeeStreams/ViewModels/PlayerViewModel.swift — Update `seekForward(seconds:)` and `seekBackward(seconds:)` to call the new `calculateSeekTarget` function, passing `player?.currentItem?.seekableTimeRanges` bounds if available for live streams. VERIFY: `swift build`. (cat:ios; multifile:no)
- [ ] [T2] iptv-ios/ChickadeeStreams/Tests/PlayerViewModelTests.swift — Add unit test `testCalculateSeekTarget_LiveForwardDoesNotZero` asserting that with `duration=0`, `isLive=true`, `currentTime=100`, and `seekableEnd=120`, `calculateSeekTarget` returns 110 (not 0). VERIFY: `swift test --filter PlayerViewModelTests.testCalculateSeekTarget_LiveForwardDoesNotZero`. (cat:test; multifile:no)
- [ ] [T2] iptv-ios/ChickadeeStreams/Tests/PlayerViewModelTests.swift — Add unit test `testCalculateSeekTarget_LiveBackwardClampsToStart` asserting that with `duration=0`, `isLive=true`, `currentTime=5`, and `seekableStart=0`, `calculateSeekTarget` for backward 10s returns 0. VERIFY: `swift test --filter PlayerViewModelTests.testCalculateSeekTarget_LiveBackwardClampsToStart`. (cat:test; multifile:no)
- [ ] [T3] iptv-ios/ChickadeeStreams/Views/Player/PlayerView.swift — Add a helper computed property `isForwardSkipEnabled` that returns `!viewModel.isLive || (viewModel.player?.currentItem?.seekableTimeRanges.count ?? 0) > 0` and bind the forward button's `.disabled()` modifier to it. VERIFY: `swift build`. (cat:ios; multifile:no)
- [ ] [T3] iptv-ios/ChickadeeStreams/ViewModels/PlayerViewModel.swift — Add a published property `@Published var isSeekable: Bool = false` and update `setupTimeObserver` to set it based on whether `seekableTimeRanges` are valid for the current item. VERIFY: `swift build`. (cat:ios; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Profile-switch PIN unlock has no brute-force lockout, unlike the parallel parental-control (review + tweak) ---
- [ ] [T1] iptv-backend/app/services/pin_lockout.py — Create new module with `PinLockoutTracker` class implementing `record_attempt(pin_id: str) -> bool` and `is_locked(pin_id: str) -> bool` using in-memory dict for attempts/timestamps, configurable max_attempts=3 and lockout_minutes=15. VERIFY: python -c "from iptv_backend.app.services.pin_lockout import PinLockoutTracker; t=PinLockoutTracker(); [t.record_attempt('p1') for _ in range(3)]; assert t.is_locked('p1') is True". (cat:python; multifile:no)
- [ ] [T2] iptv-backend/tests/test_pin_lockout_service.py — Create unit tests for `PinLockoutTracker` verifying lockout triggers after 3 failures, does not trigger on success, and expires after simulated time passage. VERIFY: pytest iptv-backend/tests/test_pin_lockout_service.py -v. (cat:test; multifile:no)
- [ ] [T3] iptv-backend/app/routers/profiles.py — Import `PinLockoutTracker`, instantiate module-level tracker, modify `unlock_profile()` to check `is_locked(profile_id)` before PIN verification and return 429 if locked, otherwise call `record_attempt` on failure. VERIFY: grep -q "PinLockoutTracker" iptv-backend/app/routers/profiles.py && grep -q "429" iptv-backend/app/routers/profiles.py. (cat:endpoint; multifile:no)
- [ ] [T3] iptv-backend/tests/test_profile_pin_lockout.py — Create integration test mocking DB and auth, asserting that 3 consecutive wrong PIN calls to `POST /profiles/{id}/unlock` result in a 429 response on the 4th call even with correct PIN. VERIFY: pytest iptv-backend/tests/test_profile_pin_lockout.py -v. (cat:test; multifile:no)
- [ ] [T4] iptv-backend/app/services/parental_controls.py — Refactor `__init__` and `verify_pin` to use the new shared `PinLockoutTracker` instead of internal `self.pin_attempts` logic, maintaining backward compatibility for existing tests. VERIFY: pytest iptv-backend/tests/test_parental_verify_pin_lockout.py -v. (cat:refactor; multifile:yes)
- [ ] [T1] iptv-backend/app/schemas/profile.py — Add optional `locked_until` field to profile unlock response schema if 429/lockout message needs structured data, or ensure error response model supports lockout metadata. VERIFY: python -c "from iptv_backend.app.schemas.profile import ProfileUnlockResponse; print('OK')". (cat:schema; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Delete dead, untested, duplicate download-expiry helper functions left in `app/jobs/downlo (review + tweak) ---
- [ ] [T1] iptv-backend/app/jobs/downloads_job.py — Remove the `mark_for_deletion()` function definition and its associated docstring/comments. VERIFY: `grep -n 'def mark_for_deletion' iptv-backend/app/jobs/downloads_job.py` returns no output. (cat:refactor; multifile:no)
- [ ] [T1] iptv-backend/app/jobs/downloads_job.py — Remove the `filter_expired_dloads()` function definition and its associated docstring/comments. VERIFY: `grep -n 'def filter_expired_dloads' iptv-backend/app/jobs/downloads_job.py` returns no output. (cat:refactor; multifile:no)
- [ ] [T1] iptv-backend/app/jobs/downloads_job.py — Remove the `filter_expired_downloads()` function definition and its associated docstring/comments. VERIFY: `grep -n 'def filter_expired_downloads' iptv-backend/app/jobs/downloads_job.py` returns no output. (cat:refactor; multifile:no)
- [ ] [T2] iptv-backend/tests/test_downloads_expiry_sweep_job.py — Create new test file containing only the valid assertions for `downloads_expiry_sweep_job` from the old `test_dvr_sweep_job.py`, removing all tests for deleted functions. VERIFY: `pytest iptv-backend/tests/test_downloads_expiry_sweep_job.py -v` passes and `grep -n 'mark_for_deletion\|filter_expired' iptv-backend/tests/test_downloads_expiry_sweep_job.py` returns no output. (cat:test; multifile:no)
- [ ] [T1] iptv-backend/tests/test_dvr_sweep_job.py — Delete the file entirely as it is replaced by `test_downloads_expiry_sweep_job.py`. VERIFY: `ls iptv-backend/tests/test_dvr_sweep_job.py` returns "No such file or directory". (cat:test; multifile:no)
- [ ] [T3] iptv-backend/app/jobs/downloads_job.py — Verify no remaining imports or references to the deleted functions exist in the module. VERIFY: `python -c "import iptv_backend.app.jobs.downloads_job"` succeeds without ImportError. (cat:refactor; multifile:no)
- [ ] [T4] iptv-backend/tests/ — Run full backend test suite to ensure no regressions from removing dead code and renaming test file. VERIFY: `pytest iptv-backend/tests/ -v` passes with 0 failures. (cat:test; multifile:yes)
- [ ] [T1] iptv-backend/app/jobs/downloads_job.py — Confirm the remaining `downloads_expiry_sweep_job()` function is intact and correctly delegates to `sweep_expired_downloads`. VERIFY: `grep -n 'def downloads_expiry_sweep_job' iptv-backend/app/jobs/downloads_job.py` returns line 16 and `grep -n 'sweep_expired_downloads' iptv-backend/app/jobs/downloads_job.py` confirms delegation. (cat:refactor; multifile:no)
- [ ] [T2] iptv-backend/tests/test_downloads_expiry_sweep_job.py — Add a specific unit test verifying that `downloads_expiry_sweep_job` calls `sweep_expired_downloads` with the correct arguments. VERIFY: `pytest iptv-backend/tests/test_downloads_expiry_sweep_job.py::test_downloads_expiry_sweep_job_delegates -v` passes. (cat:test; multifile:no)
- [ ] [T5] iptv-backend/ — Final verification that no references to deleted functions remain anywhere in the backend codebase or tests. VERIFY: `grep -rn 'filter_expired_dloads\|filter_expired_downloads\|mark_for_deletion' iptv-backend/app/ iptv-backend/tests/` returns no output. (cat:refactor; multifile:yes)
