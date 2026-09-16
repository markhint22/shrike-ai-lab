# iptv_apps (Chickadee) — pre-decomposed release-polish backlog (27B-friendly)
# queue_refill.py pulls [T1-T5] items from here into OVERNIGHT_PROGRESS.md when doable is low.
# Each item is ONE file, a spec (not a goal), and self-verifying. Add more over time.

- [ ] [T2] iptv-web/src/components/PaywallModal.vue — add role="dialog" and aria-modal="true" to the modal container div (v-if="show" class="fixed inset-0 ..."), plus aria-labelledby pointing at the title element (give the title an id). VERIFY: a vitest mount with show:true asserts wrapper.get('[role=dialog]').attributes('aria-modal') === 'true'. (polish:a11y)
- [ ] [T2] iptv-web/src/views/ProfilesView.vue — add role="dialog" + aria-modal="true" + aria-labelledby to the fixed inset-0 add/edit-profile modal container. VERIFY: view test with the modal open asserts one [role=dialog][aria-modal=true] exists. (polish:a11y)
- [ ] [T2] iptv-web/src/views/SubscriptionView.vue — add role="dialog" + aria-modal="true" + aria-labelledby to the cancel-subscription modal (fixed inset-0 container). VERIFY: test opens the cancel modal and asserts [role=dialog] present with aria-modal="true". (polish:a11y)
- [ ] [T2] iptv-web/src/views/ParentalView.vue — add role="dialog" + aria-modal="true" + aria-labelledby to the PIN/settings modal fixed inset-0 container. VERIFY: test asserts the opened modal root has role="dialog" and aria-modal="true". (polish:a11y)
- [ ] [T2] iptv-web/src/views/StreamDetailView.vue — add role="dialog" + aria-modal="true" + aria-labelledby to the fixed inset-0 modal/overlay container. VERIFY: test asserts [role=dialog][aria-modal=true] present when the modal is shown. (polish:a11y)
- [ ] [T2] iptv-web/src/components/PaywallModal.vue — add a @keydown.esc handler that calls handleClose() so the modal is dismissible by keyboard (today it only closes on @click.self), gated on dismissible. VERIFY: mount test triggers keydown.esc and asserts a close event was emitted; with dismissible:false asserts none emitted. (polish:a11y)
- [ ] [T2] iptv-web/src/views/ProfilesView.vue — add Escape-key-to-close to the add/edit-profile modal (currently closable only by button/backdrop). VERIFY: view test dispatches keydown Escape and asserts the modal v-if state becomes false. (polish:a11y)
- [ ] [T2] iptv-web/src/views/SubscriptionView.vue — add Escape-key-to-close to the cancel-subscription modal. VERIFY: test opens the modal, dispatches Escape, asserts showCancelModal is false. (polish:a11y)
- [ ] [T1] iptv-backend/app/schemas/subscription.py — add Field(ge=0) to SubscriptionPlanBase.price_cents and Field(ge=0) to SubscriptionPlanCreate.trial_days. VERIFY: a pytest constructs SubscriptionPlanCreate(name="x", price_cents=-1) and asserts pydantic.ValidationError; price_cents=0 is accepted. (polish:validation)

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
- [ ] [T4] iptv-web/src/views/__tests__/PlayerView.stall.test.ts — Create a Vitest suite that mocks the video.js player instance and simulates 'waiting' events to assert that `player.load` is called after a delay matching `retryDelayMs(N)` for N=1,2,3. VERIFY: `npx vitest run iptv-web/src/views/__tests__/PlayerView.stall.test.ts` passes. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-16]: Add unit tests for Android's revenue-critical PaywallViewModel — iptv-android/app/src/main (review + tweak) ---
- [ ] [T1] iptv-android/app/src/test/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/PaywallViewModelTest.kt — Create test class with MockK setup for RevenueCatManager and UnconfinedTestDispatcher, verifying loadOfferings() auto-selects yearlyPackage when available. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.chickadeestreams.iptv.ui.mobile.viewmodels.PaywallViewModelTest.testLoadOfferingsSelectsYearly"` passes. (cat:test; multifile:no)
- [ ] [T1] iptv-android/app/src/test/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/PaywallViewModelTest.kt — Add test verifying loadOfferings() falls back to monthlyPackage when yearlyPackage is null. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.chickadeestreams.iptv.ui.mobile.viewmodels.PaywallViewModelTest.testLoadOfferingsFallsBackToMonthly"` passes. (cat:test; multifile:no)
- [ ] [T1] iptv-android/app/src/test/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/PaywallViewModelTest.kt — Add test verifying selectPackage() updates the selectedPackage state correctly. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.chickadeestreams.iptv.ui.mobile.viewmodels.PaywallViewModelTest.testSelectPackageUpdatesState"` passes. (cat:test; multifile:no)
- [ ] [T1] iptv-android/app/src/test/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/PaywallViewModelTest.kt — Add test verifying purchase() sets purchaseSuccess=true only when result is success and isPremium=true. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.chickadeestreams.iptv.ui.mobile.viewmodels.PaywallViewModelTest.testPurchaseSuccessSetsFlag"` passes. (cat:test; multifile:no)
- [ ] [T1] iptv-android/app/src/test/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/PaywallViewModelTest.kt — Add test verifying purchase() does NOT set purchaseSuccess=true when result is failure. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.chickadeestreams.iptv.ui.mobile.viewmodels.PaywallViewModelTest.testPurchaseFailureDoesNotSetFlag"` passes. (cat:test; multifile:no)
- [ ] [T1] iptv-android/app/src/test/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/PaywallViewModelTest.kt — Add test verifying purchase() does NOT set purchaseSuccess=true when isPremium=false. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.chickadeestreams.iptv.ui.mobile.viewmodels.PaywallViewModelTest.testPurchaseNonPremiumDoesNotSetFlag"` passes. (cat:test; multifile:no)
- [ ] [T1] iptv-android/app/src/test/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/PaywallViewModelTest.kt — Add test verifying restorePurchases() sets purchaseSuccess=true on success with isPremium=true. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.chickadeestreams.iptv.ui.mobile.viewmodels.PaywallViewModelTest.testRestorePurchasesSuccessSetsFlag"` passes. (cat:test; multifile:no)
- [ ] [T1] iptv-android/app/src/test/java/com/chickadeestreams/iptv/ui/mobile/viewmodels/PaywallViewModelTest.kt — Add test verifying restorePurchases() does NOT set purchaseSuccess=true on failure or isPremium=false. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.chickadeestreams.iptv.ui.mobile.viewmodels.PaywallViewModelTest.testRestorePurchasesFailureDoesNotSetFlag"` passes. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-16]: Make iOS WatchlistViewModel dependency-injectable and add its first unit tests — iptv-ios/ (review + tweak) ---
- [ ] [T3] iptv-ios/ChickadeeStreams/ViewModels/WatchlistViewModel.swift — Add `init(apiService: APIService = .shared)` and replace hardcoded `APIService.shared` with the injected property. VERIFY: `grep -q "init(apiService: APIService" iptv-ios/ChickadeeStreams/ViewModels/WatchlistViewModel.swift`. (cat:refactor; multifile:no)
- [ ] [T1] iptv-ios/ChickadeeStreams/ChickadeeTests/WatchlistViewModelTests.swift — Create test file with `MockURLProtocol` setup and a test verifying `load()` populates `items` on 200 response. VERIFY: `xcodebuild test -scheme ChickadeeStreams -only-testing:ChickadeeTests/WatchlistViewModelTests/testLoadPopulatesItemsOnSuccess`. (cat:test; multifile:no)
- [ ] [T1] iptv-ios/ChickadeeStreams/ChickadeeTests/WatchlistViewModelTests.swift — Add test verifying `load()` sets `errorMessage` on non-2xx or thrown error. VERIFY: `xcodebuild test -scheme ChickadeeStreams -only-testing:ChickadeeTests/WatchlistViewModelTests/testLoadSetsErrorMessageOnFailure`. (cat:test; multifile:no)
- [ ] [T1] iptv-ios/ChickadeeStreams/ChickadeeTests/WatchlistViewModelTests.swift — Add test verifying `remove()` optimistically removes item then rolls back on API failure. VERIFY: `xcodebuild test -scheme ChickadeeStreams -only-testing:ChickadeeTests/WatchlistViewModelTests/testRemoveRollsBackOnFailure`. (cat:test; multifile:no)
- [ ] [T2] iptv-ios/ChickadeeStreams/ChickadeeTests/WatchlistViewModelTests.swift — Add test verifying `remove()` successfully removes item and does not roll back on 200 response. VERIFY: `xcodebuild test -scheme ChickadeeStreams -only-testing:ChickadeeTests/WatchlistViewModelTests/testRemoveSucceedsOnSuccess`. (cat:test; multifile:no)
