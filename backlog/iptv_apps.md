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
- [ ] [T2] iptv-backend/app/services/stream_discovery_service.py — Implement `get_similar_to(stream_id: int, user_id: int) -> list[dict]` by fetching the target stream's genres and applying `score_genre_overlap` to other streams in the same category. VERIFY: python -m pytest iptv-backend/tests/test_discovery_service.py::test_get_similar_to_returns_related -v. (cat:python; multifile:no)
- [ ] [T3] iptv-backend/app/routers/discover.py — Update `/personalized` endpoint to accept optional `limit` query param and pass it to `StreamDiscoveryService.get_personalized`, defaulting to 10. VERIFY: python -m pytest iptv-backend/tests/test_discover_router.py::test_personalized_endpoint_limit_param -v. (cat:endpoint; multifile:no)
- [ ] [T3] iptv-backend/app/routers/discover.py — Update `/similar` endpoint to accept `stream_id` path parameter and call `StreamDiscoveryService.get_similar_to`, returning 404 if stream not found. VERIFY: python -m pytest iptv-backend/tests/test_discover_router.py::test_similar_endpoint_valid_id -v. (cat:endpoint; multifile:no)
- [ ] [T2] iptv-backend/app/schemas/discovery.py — Create Pydantic schemas `PersonalizedStreamResponse` and `SimilarStreamResponse` with fields for id, title, thumbnail_url, and score. VERIFY: python -c "from iptv_backend.app.schemas.discovery import PersonalizedStreamResponse; print('OK')". (cat:schema; multifile:no)
- [ ] [T3] iptv-backend/app/routers/discover.py — Update response models for `/personalized` and `/similar` to use the new Pydantic schemas from `app.schemas.discovery`. VERIFY: python -m pytest iptv-backend/tests/test_discover_router.py::test_personalized_response_schema -v. (cat:endpoint; multifile:no)
- [ ] [T4] iptv-backend/app/services/stream_discovery_service.py — Integrate `continue_watching_filter` service to boost scores of streams related to the user's last watched items in `get_personalized`. VERIFY: python -m pytest iptv-backend/tests/test_discovery_service.py::test_personalized_boosts_continue_watching -v. (cat:python; multifile:yes)
