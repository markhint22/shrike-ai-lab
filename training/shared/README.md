# Shared Training - Cross-Project Skill Capsules

These capsules are designed to be reused across all Shrike Labs projects. Any product can load them independently.

## Training Tasks

### 1. Code Review (Original)
Identify security, performance, and reliability issues in code.

```json
{
  "code": "...",
  "issues": [{"line": 1, "severity": "critical", "type": "security", "message": "..."}]
}
```

### 2. Moderation Capsule (New)
Classify user-generated messages and decide whether to allow, flag, or remove them. Trained entirely on **synthetic and abstract examples** — no real harmful content appears in the training data.

```json
{
  "message": "...",
  "context": "bill discussion",
  "decision": "flag",
  "category": "unverified_defamation",
  "confidence": 0.82,
  "action": "add_disclaimer",
  "rewrite": "...",
  "explanation": "..."
}
```

#### Decision Types
| Decision | Meaning |
|----------|---------|
| `allow` | Message is fine, no action needed |
| `flag` | Needs attention — add context, warn, or rewrite |
| `remove` | Must be deleted immediately |

#### Category Examples (Safe for Repo)
- `friendly_greeting` — no concerns
- `civil_disagreement` — healthy debate
- `personal_attack_mild` — redirect toward substance
- `targeted_harassment_severe` — remove
- `unverified_defamation` — add fact-check context
- `conspiracy_theory` — add authoritative sources
- `personal_data_exposure` — redact to protect user
- `electoral_promotion` — add non-endorsement disclaimer
- `doxxing` — immediate removal

#### Usable In
- BillWatch — bill discussion threads
- GitLark — workspace chat
- SpecPilot — support/debugging chat
- Any future Shrike Labs social feature

## Training Commands

```bash
make train-shared-review
make train-shared-moderation
```

## Safety Notes

The moderation training data uses **abstracted descriptions** of harmful content categories, never example harmful text. This keeps the repo safe for work and compliant with hosting policies while still teaching the model what to detect.
