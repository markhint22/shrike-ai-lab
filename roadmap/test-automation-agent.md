# Roadmap — SpecPilot / test-automation-agent
**Maturity:** MEDIUM (backend + frontend exist; Fly deploy). **Stopping point:** a solid test-run + flake-management product; don't over-expand into a full observability suite.

## P1 — core test-run product (next ~2 quarters)
- [ ] [P1] [decomposed] Test-run summaries, status, retry/rerun decisions, flake ratios (pure logic + endpoints) {cat: backend; size: M; multifile: yes; research: repo}
- [ ] [P1] [decomposed] Run dashboard UI: status colors, durations, pass/flake surfaces {cat: web; size: M; multifile: yes; research: repo}
- [x] [P1] [resolved 2026-09-09] Fix the Fly deploy (specpilot routes) — VERIFIED live: https://specpilot.fly.dev/health -> 200 and / -> 200 with a real API response ({"name":"Test Automation Agent API",...}). This was already fixed (see shared/CLAUDE.md's 2026-09-01 full re-verification) but the roadmap never got updated, so it kept showing as the #1 blocker with nothing left to actually research. {cat: infra; size: S; research: web}
## P2 — integrations (~q3-4)
- [ ] [P2] [decomposed] CI integrations (GitHub Actions/Jenkins) result ingestion — researched 2026-09-09: GitHub needs a GitHub App (checks:write scope — plain OAuth apps/PATs can't create check runs) that POSTs to /repos/{owner}/{repo}/check-runs on push/PR and updates it to completed+conclusion when the SpecPilot run finishes (docs.github.com "Building CI checks with a GitHub App"). Jenkins side: the Outbound Webhook plugin (NOT Generic Webhook Trigger, which triggers INTO Jenkins, the wrong direction) sends build-event payloads OUT to an external endpoint. Decomposes into: (1) a generic `POST /api/ci/webhook` ingestion endpoint accepting {provider, repo, commit_sha, status, run_id}, (2) a GitHub-specific outbound path using the Checks API to report SpecPilot's own run status back onto the PR, (3) a docs page with copy-paste GitHub Actions YAML + Jenkins plugin config. {cat: backend; size: M; research: web; sources: docs.github.com/en/free-pro-team@latest/developers/apps/creating-ci-tests-with-the-checks-api, plugins.jenkins.io/outbound-webhook}
- [ ] [P2] [decomposed] Knowledge-base / test-selection helpers {cat: backend; size: M; multifile: no; research: repo}
## Stopping point
Test-run tracking + flake detection + CI ingestion + a clean dashboard = COMPLETE. Maintain.
