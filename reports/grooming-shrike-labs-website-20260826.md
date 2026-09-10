# Grooming proposal — shrike-labs-website — 2026-08-26 04:00

## Deterministically stale (target file already gone — safe to drop)
```
10. Regenerate sitemap.xml at build time (real scripts/generate-sitemap.ts + a vite closeBundle plugin covering /, /about, /privacy, /terms, /blog, /blog/:slug) or delete the stale public/sitemap.xml.
12. Resolve orphan pages (PrivacyPage.vue, TestimonialsPage.vue, BlogPage.vue — keep+route or delete).
```

## Current Next Steps
```
1. Register @unhead/vue in src/main.ts (import createHead, .use(head) before mount) — unblocks all per-page SEO. Add a smoke test that mount doesn't throw.
2. Wire useSEO into each routed page (Home, About, Privacy, Terms) with page-specific title/description/canonical; add a test asserting document.title updates. (Depends on #1.)
3. Add the missing public/og-image.png (1200x630) referenced by the meta tags — currently 404s.
4. Rebuild a browser-safe blog loader: new src/composables/useBlogPosts.ts using import.meta.glob('./blog/posts/*.md', ...) returning parsed front-matter + content (replaces the deleted Node-fs blog.config.ts). Unit-test against the 2 existing posts in src/blog/posts/.
5. Rebuild a Blog listing page from #4 (tags/pagination); test it renders both sample posts. (Depends on #4.)
6. Wire blog detail routing: add /blog and /blog/:slug to router.ts, un-orphan/rebuild BlogPostView.vue to render a post by slug from #4 and call useSEO (type=article); test the route resolves a known slug. (Depends on #1, #4.)
7. Add a nav/route link to the blog in App.vue.
8. Wire the Footer newsletter to a real endpoint — replace the setTimeout simulation in FooterSection.vue with fetch('/api/newsletter', ...) + success/error states test.
9. Verify + document the contact backend — confirm /api/contact resolves in production (add a vercel.json rewrite if missing); integration-verify one POST.
10. Regenerate sitemap.xml at build time (real scripts/generate-sitemap.ts + a vite closeBundle plugin covering /, /about, /privacy, /terms, /blog, /blog/:slug) or delete the stale public/sitemap.xml.
11. Relocate stray Python out of src/ (src/api/routers/blog.py, src/services/blog_*.py) into backend/ or delete if superseded.
12. Resolve orphan pages (PrivacyPage.vue, TestimonialsPage.vue, BlogPage.vue — keep+route or delete).
13. Accessibility audit pass (axe/Lighthouse): contrast, focus-visible, heading order, aria-expanded/labels — WCAG 2.1 AA.
14. Add component tests to reach the 80% coverage gate (ContactSection validation paths, CareersSection, TestimonialsSection, FooterSection).
```

## Proposed (LLM re-evaluation — review before applying)
1. Add the missing public/og-image.png (1200x630) referenced by the meta tags — currently 404s.
2. Rebuild a browser-safe blog loader: new src/composables/useBlogPosts.ts using import.meta.glob('./blog/posts/*.md', ...) returning parsed front-matter + content (replaces the deleted Node-fs blog.config.ts). Unit-test against the 2 existing posts in src/blog/posts/.
3. Rebuild a Blog listing page from #2 (tags/pagination); test it renders both sample posts.
4. Wire blog detail routing: add /blog and /blog/:slug to router.ts, un-orphan/rebuild BlogPostView.vue to render a post by slug from #2 and call useSEO (type=article); test the route resolves a known slug.
5. Add a nav/route link to the blog in App.vue.
6. Wire the Footer newsletter to a real endpoint — replace the setTimeout simulation in FooterSection.vue with fetch('/api/newsletter', ...) + success/error states test.
7. Verify + document the contact backend — confirm /api/contact resolves in production (add a vercel.json rewrite if missing); integration-verify one POST.
8. Regenerate sitemap.xml at build time (real scripts/generate-sitemap.ts + a vite closeBundle plugin covering /, /about, /privacy, /terms, /blog, /blog/:slug) or delete the stale public/sitemap.xml.
9. Resolve orphan pages (PrivacyPage.vue, TestimonialsPage.vue, BlogPage.vue — keep+route or delete).
10. Accessibility audit pass (axe/Lighthouse): contrast, focus-visible, heading order, aria-expanded/labels — WCAG 2.1 AA.
11. Add component tests to reach the 80% coverage gate (ContactSection validation paths, CareersSection, TestimonialsSection, FooterSection).
12. Relocate stray Python out of src/ (src/api/routers/blog.py, src/services/blog_*.py) into backend/ or delete if superseded.
13. Create a new test suite for the ContactSection component to validate all form submission paths and error states.
14. Implement a responsive design fix for the HeroSection.vue to ensure proper rendering on mobile devices.
15. Add a new blog post template in src/blog/posts/ with proper front-matter structure for future posts.
