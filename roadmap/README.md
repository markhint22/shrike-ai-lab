# Roadmaps — the top of the self-sustaining planning pipeline

Each `<repo>.md` is a **priority-ordered, 2-year feature plan**. It is the SOURCE the fleet plans
from. Flow:

```
roadmap/<repo>.md  (Claude writes; prioritized features)
   │  feature status:  needs-research → ready → decomposed → done
   ▼
[needs-research]  → Claude (web/market research) turns it into [ready] with a design note
[ready]          → 27B planner (ovn_planner.sh) reads the repo + decomposes into tiered,
                    categorized backlog items → backlog/<repo>.md, marks feature [decomposed]
   ▼
backlog/<repo>.md → queue_refill pulls items into OVERNIGHT_PROGRESS.md when the queue is low
   ▼
run_overnight works the items; gate lands/reverts; outcome logged
```

**Feature line format** (the planner + Claude both read/write these):
`- [ ] [P<1-4>] [<status>] <feature> — <what/why>  {cat: <backend|web|mobile|game|infra|test>; size: <S|M|L>; multifile: <yes|no>; research: <none|repo|web>}`

- **P1** = do next · **P4** = someday. **status**: `needs-research` (Claude) | `ready` (decompose) | `decomposed` | `done`.
- **research**: `none` (just decompose) | `repo` (27B reads the codebase first) | `web` (Claude researches first → sets `ready`).

**Stopping points matter.** Infra bricks (shrike-notify, shrike-monitor) and mature apps
(Chickadee, BillWatch) reach a defined "complete — maintain only" line; don't invent features past it.
gitlark v2 has the most runway (it's an active build-out).
