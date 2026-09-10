# Grooming proposal — social-media-manager — 2026-08-25 15:19

## Current Next Steps
```
0. [test infrastructure gap + 2 real test failures found via automated test run, 2026-08-14 -
1. Implement OAuth integration for social media platforms (requires API credentials - check
2. Create FastAPI endpoint to expose the content generation service.
3. Add input validation for AI content generation requests.
4. Implement caching for frequently requested topics to reduce API costs.
5. Implement a scheduler service to publish scheduled posts at their scheduled time.
6. Add endpoints to manage post statuses (publish, fail, retry).
7. Create a dashboard view for scheduled posts in the web frontend.
8. Add integration tests for the post scheduling flow.
9. Implement password reset functionality.
10. Create a profile update endpoint for authenticated users.
11. Add email verification flow for new user registrations.
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix the 2 real test failures identified in the automated test run (2026-08-14) to restore CI green status.
2. Implement input validation for AI content generation requests in `app/api/routes/posts.py`.
3. Create FastAPI endpoint to expose the content generation service in `app/api/routes/posts.py`.
4. Add endpoints to manage post statuses (publish, fail, retry) in `app/api/routes/posts.py`.
5. Implement a scheduler service to publish scheduled posts at their scheduled time (backend logic only).
6. Add integration tests for the post scheduling flow.
7. Create a dashboard view for scheduled posts in the web frontend.
8. Implement OAuth integration for social media platforms (backend logic only, excluding UI).
9. Add email verification flow for new user registrations.
10. Create a profile update endpoint for authenticated users in `app/api/routes/profiles.py`.
11. Implement password reset functionality in `app/api/routes/auth.py`.
12. Add caching for frequently requested topics to reduce API costs.
13. Implement rate limiting for public API endpoints to prevent abuse.
14. Add structured logging middleware for request tracing and error monitoring.
15. Create a health check endpoint for dependency services (database, external APIs).
