# Roadmap — Chickadee / iptv_apps
**Maturity:** HIGH (~95% — live, multi-platform). **Stopping point:** once DVR+VOD+multistream ship and it's in both app stores, it's feature-complete → maintenance + content-ops only. Don't chase Fubo's channel count.

## P1 — competitive parity + store launch (next ~2 quarters)
- [ ] [P1] [decomposed] Cloud DVR — record/list/delete, retention policy, RecordingsView — every rival has it {cat: backend+web; size: L; multifile: yes; research: repo}
- [ ] [P1] [decomposed] VOD / on-demand catalog + tab — Sling Freestream angle {cat: backend+web; size: M; multifile: yes; research: repo}
- [ ] [P1] [decomposed] Multiple simultaneous streams (plan-based limit + 409 guard) {cat: backend; size: S; multifile: no; research: repo}
- [ ] [P1] [needs-research] App Store + Play Store submission blockers (Stripe prod key, RevenueCat, content-rights) {cat: infra; size: M; research: web}
## P2 — retention + polish (~q3-4)
- [ ] [P2] [decomposed] Reliable playback: rebuffer backoff, error recovery, cast/AirPlay hardening {cat: web+mobile; size: M; multifile: yes; research: repo}
- [ ] [P2] [decomposed] Easy self-serve cancellation + billing transparency (beat competitor gripes) {cat: web+backend; size: S; multifile: no; research: repo}
- [ ] [P2] [ready] Watchlist/Continue-watching parity across web + mobile {cat: web+mobile; size: M; multifile: yes; research: repo}
## P3 — differentiation (~year 2)
- [ ] [P3] [needs-research] Profiles + parental controls depth; kids mode {cat: backend+web; size: M; research: web}
- [ ] [P3] [needs-research] Personalized discover/recommendations {cat: backend; size: M; research: web}
## Stopping point
When P1+P2 ship and stores accept it: FEATURE-COMPLETE. After that, only content/EPG ops, bug-fixes, and OS-version upkeep. Do NOT add live-TV-provider-scale features.
