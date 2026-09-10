# Roadmap — shrike-notify (pub/sub notification brick)
**Maturity:** MEDIUM (publish/subscribe/messages wired). **Stopping point:** a COMPLETE, dogfooded v1. This is INFRASTRUCTURE — do NOT overbuild. Reach v1-complete and freeze to maintenance.

## P1 — complete v1 (next quarter, then STOP)
- [ ] [P1] [decomposed] Tokens endpoint + scoped auth (require_auth path) {cat: backend; size: M; multifile: yes; research: repo}
- [ ] [P1] [decomposed] Retention caps + message TTL + topic list/stats endpoints {cat: backend; size: M; multifile: yes; research: repo}
- [ ] [P1] [decomposed] Priority/tag validation + quiet-hours delivery gating {cat: backend; size: S; multifile: no; research: repo}
- [ ] [P1] [decomposed] Health details + rate-limit headers + a publish client helper (dogfood) {cat: backend; size: S; multifile: no; research: repo}
## Stopping point (HARD)
Once the above ships and the fleet + shrike-monitor dogfood it in prod: **v1 COMPLETE — freeze.** No dashboards, no multi-tenant, no fancy routing. It's a notification brick; keep it small and reliable.
