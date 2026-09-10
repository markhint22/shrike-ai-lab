# Grooming proposal — billwatch — 2026-08-25 15:10

## Current Next Steps
```
- [x] Add unit tests for backend `CongressClient` service to mock API responses. (Done 2024-05-22)
- [x] Implement "Bill Background" feature using local LLM capsule integration in backend. (Done 2024-05-23)
- [x] Add missing Android UI tests for LegislatorSearchScreen. (Done 2024-05-24)
- [x] Add missing Android UI tests for LegislatorSearchScreen. (Done 2024-05-24)
- [x] Update iOS `KeychainService` to handle keychain errors gracefully. (Done 2024-05-25)
- [x] Add integration tests for `/api/bills` endpoint with database fixtures. (Done 2024-05-26)
- [x] Implement "Article Relevance" ranking logic in backend service. (Done 2024-05-26)
- [ ] Add E2E tests for user login flow in Web app.
- [ ] Refactor Android `FindRepsViewModel` to use StateFlow consistently.
- [ ] Add rate limiting tests for feedback endpoint.
- [ ] Add documentation for Congress.gov API client usage in backend.
- [ ] Fix potential race condition in background bill sync job.
- [ ] Add documentation for local LLM capsule training commands in README.
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix potential race condition in background bill sync job
2. Refactor Android `FindRepsViewModel` to use StateFlow consistently
3. Add E2E tests for user login flow in Web app
4. Add rate limiting tests for feedback endpoint
5. Add documentation for Congress.gov API client usage in backend
6. Add documentation for local LLM capsule training commands in README
7. Add unit tests for `bill_background_service.py` to verify LLM fallback logic
8. Add integration tests for `LegislatorsRepository` in Android app
9. Add unit tests for `AuthViewModel` in Android app
