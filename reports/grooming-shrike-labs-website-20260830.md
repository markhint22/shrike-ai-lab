# Grooming proposal — shrike-labs-website — 2026-08-30 04:00

## Deterministically stale (target file already gone — safe to drop)
```
7. Remove dead/duplicate files: relocate or delete the stray Python under `src/` (`src/api/routers/blog.py`, `src/services/blog_manager.py`, `src/services/blog_service.py`) into `backend/` or drop it; and delete the orphan Vue pages not in the router (`src/pages/PrivacyPage.vue`, `src/pages/TestimonialsPage.vue`, `src/pages/BlogPage.vue`).
```

## Current Next Steps
```
1. Register `@unhead/vue` in `src/main.ts`: `import { createHead } from '@unhead/vue'`, `const head = createHead()`, `.use(head)` before `.mount('#app')`. This unblocks all per-page SEO — `src/composables/useSEO.ts` already calls `useHead` but there is no head instance, so every SEO call is a silent no-op today. Add a smoke test asserting the app mounts without throwing.
2. Add the missing `public/og-image.png` (1200×630). It's the default `image` in `src/composables/useSEO.ts` (`${baseUrl}/og-image.png`) and is referenced by `index.html` meta tags — currently 404s.
3. Fix `vercel.json` so the SPA catch-all rewrite stops swallowing API calls: `ContactSection.vue` POSTs to `/api/contact`, but `{ "source": "/(.*)", "destination": "/index.html" }` rewrites that to HTML. Change the source to a negative-lookahead that excludes `/api/` (or add an explicit `/api/*` passthrough), and confirm a real `/api/contact` target exists (repo root has no `/api` dir; `backend/` is separate) — document the resolution.
4. Wire `useSEO` into the four routed pages (`src/pages/Home.vue`, `src/pages/AboutPage.vue`, `src/pages/Privacy.vue`, `src/pages/Terms.vue`) with page-specific title/description/canonical. Add a test asserting `document.title` updates on navigation. (Depends on #1.)
5. Rebuild a browser-safe blog loader `src/composables/useBlogPosts.ts` using `import.meta.glob('../blog/posts/*.md', { eager: true, query: '?raw', import: 'default' })`, parsing front-matter (title/description/date/author/tags) + body from the 2 real posts in `src/blog/posts/`. Unit-test that it returns both posts. (Replaces the hardcoded mock arrays in `BlogSection.vue`/`BlogPostView.vue`.)
6. Wire real blog data + detail routing: add `/blog` and `/blog/:slug` to `src/router.ts`; rebuild `src/components/BlogPostView.vue` to resolve a post by slug from `useBlogPosts` (delete its mock array and move the `useSEO(type:'article')` call inside the resolved post — it's currently at top-level with a null `post`, so it never runs); point `src/components/BlogSection.vue` at `useBlogPosts`; add a Blog link to the nav in `src/App.vue`. Test that a known slug route resolves. (Depends on #1, #5.)
7. Remove dead/duplicate files: relocate or delete the stray Python under `src/` (`src/api/routers/blog.py`, `src/services/blog_manager.py`, `src/services/blog_service.py`) into `backend/` or drop it; and delete the orphan Vue pages not in the router (`src/pages/PrivacyPage.vue`, `src/pages/TestimonialsPage.vue`, `src/pages/BlogPage.vue`).
8. Regenerate or prune `public/sitemap.xml` (stale, dated 2026-05-05) so it reflects the real routes `/`, `/about`, `/privacy`, `/terms` (plus `/blog` once #6 lands) — either a build-time generator wired into `vite.config.ts` or a hand-updated static file.
9. Accessibility + coverage pass: axe/Lighthouse audit (contrast, focus-visible, heading order, aria) and add component tests toward the 80% gate — `ContactSection.vue` validation paths, `FooterSection.vue` newsletter states, `CareersSection.vue`.
```

## Proposed (LLM re-evaluation — review before applying)
1. Register `@unhead/vue` in `src/main.ts` and add a smoke test asserting the app mounts without throwing.
2. Add the missing `public/og-image.png` (1200×630) to resolve 404s in `index.html` and `useSEO.ts`.
3. Fix `vercel.json` to exclude `/api/` from the SPA catch-all rewrite and document the API target resolution.
4. Wire `useSEO` into `src/pages/Home.vue` and `src/pages/AboutPage.vue` with page-specific metadata.
5. Wire `useSEO` into `src/pages/Privacy.vue` and `src/pages/Terms.vue` with page-specific metadata.
6. Create `src/composables/useBlogPosts.ts` using `import.meta.glob` to parse front-matter from `src/blog/posts/*.md` and add unit tests.
7. Add `/blog` and `/blog/:slug` routes to `src/router.ts` and update `src/App.vue` navigation.
8. Rebuild `src/components/BlogPostView.vue` to resolve posts by slug from `useBlogPosts` and remove mock data.
9. Update `src/components/BlogSection.vue` to use `useBlogPosts` and remove hardcoded mock arrays.
10. Delete orphan Vue pages (`src/pages/PrivacyPage.vue`, `src/pages/TestimonialsPage.vue`, `src/pages/BlogPage.vue`) not present in the router.
11. Relocate or delete stray Python files (`src/api/routers/blog.py`, `src/services/blog_manager.py`, `src/services/blog_service.py`) from the frontend `src/` directory.
12. Update `public/sitemap.xml` to reflect current routes (`/`, `/about`, `/privacy`, `/terms`, `/blog`) and remove stale dates.
13. Add component tests for `ContactSection.vue` validation paths to improve coverage.
14. Add component tests for `FooterSection.vue` newsletter states to improve coverage.
15. Run an accessibility audit (axe/Lighthouse) on `HeroSection.vue` and `AboutSection.vue` to fix contrast and focus issues.
