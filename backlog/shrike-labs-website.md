# shrike-labs-website — next-year backlog (27B-friendly). NOTE: not currently in the fleet;
# onboard the repo to work these, else route to Claude.
# --- next-year roadmap decomposition (2026-09-05) ---
- [ ] [T2] src/data/work.ts — add a getFeaturedProjects() pure helper returning projects.filter(p => p.status === 'Live'). VERIFY: grep -n "getFeaturedProjects" src/data/work.ts and npm run test:run -- work passes. (roadmap:showcase)
- [ ] [T2] src/data/__tests__/work.test.ts — add asserting every project has non-empty slug/name/tagline/overview and unique slugs. VERIFY: npx vitest --run work green. (roadmap:showcase)
- [ ] [T2] src/components/__tests__/CaseStudies.test.ts — extend to assert one rendered card per projects entry (count-driven, not hardcoded). VERIFY: npx vitest --run CaseStudies green. (roadmap:showcase)
- [ ] [T2] src/composables/__tests__/useAnalytics.test.ts — add a case asserting the remote script is NOT loaded when consent is denied or unset. VERIFY: npx vitest --run useAnalytics green. (roadmap:analytics)
- [ ] [T2] src/test/reduced-motion.test.ts — NEW vitest reading style.css and asserting a @media (prefers-reduced-motion: reduce) block exists. VERIFY: grep -n "prefers-reduced-motion" src/style.css and test green. (roadmap:a11y)
- [ ] [T2] api/__tests__/subscribe.test.ts — add cases for invalid-email (400) and honeypot-filled (silent drop). VERIFY: npx vitest --run subscribe green. (roadmap:newsletter)
- [ ] [T2] public/robots.txt — add explicit Disallow: /api/ line (serverless endpoints shouldn't be indexed). VERIFY: grep -n "Disallow: /api" public/robots.txt. (roadmap:sitemap)
- [ ] [T2] vite.config.ts — add <lastmod> (build date) and per-route <changefreq>/<priority> to the generated sitemap <url> blocks. VERIFY: grep -n "lastmod\|changefreq" vite.config.ts and npm run build writes dist/sitemap.xml. (roadmap:sitemap)
- [ ] [T2] src/composables/useAnalytics.ts — add a resetConsent() exported fn that clears the stored consent key. VERIFY: grep -n "resetConsent" src/composables/useAnalytics.ts + a unit test asserting state returns to unset. (roadmap:analytics)
- [ ] [T2] src/components/__tests__/FooterSection.test.ts — add a test asserting the newsletter form posts to /api/subscribe and shows a success state on 200. VERIFY: npx vitest --run FooterSection green. (roadmap:newsletter)
