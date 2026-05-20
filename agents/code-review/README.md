# Code Review Agent

Universal code review agent for all Shrike Labs repositories.

## Overview

This agent performs automated code reviews on PRs, identifying:
- 🔒 Security vulnerabilities
- 📝 Style and best practice issues
- ⚡ Performance problems

## Architecture

```
┌─────────────────┐
│  GitHub Webhook │
│   (PR opened)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Review Agent   │
│   Coordinator   │
└────────┬────────┘
         │
    ┌────┼────┬────────┐
    ▼    ▼    ▼        ▼
┌──────┐┌──────┐┌──────┐┌──────┐
│Secur-││Style ││Perf  ││Summa-│
│ity   ││Agent ││Agent ││ry    │
└──────┘└──────┘└──────┘└──────┘
         │
         ▼
┌─────────────────┐
│  PR Comment     │
└─────────────────┘
```

## Usage

### Standalone

```python
from agents.code_review.review_agent import CodeReviewCrew

crew = CodeReviewCrew()
result = crew.review_code(
    diff="...",
    file_path="app/routes/users.py",
    language="python",
)
print(result["summary"])
```

### As GitHub Action

```yaml
# .github/workflows/ai-review.yml
name: AI Code Review

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Get PR diff
        run: |
          gh pr diff ${{ github.event.pull_request.number }} > diff.txt
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Run AI Review
        run: |
          python -m agents.code_review.review_agent \
            --diff diff.txt \
            --output review.md
        env:
          LLM_BASE_URL: ${{ secrets.LLM_BASE_URL }}
      
      - name: Post Review Comment
        run: |
          gh pr comment ${{ github.event.pull_request.number }} \
            --body-file review.md
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Configuration

### Environment Variables

```env
LLM_BASE_URL=http://localhost:11434  # Ollama URL
LLM_SECURITY_MODEL=codellama:7b
LLM_STYLE_MODEL=codellama:7b
LLM_PERF_MODEL=mistral:7b
```

### Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| critical | Security vulnerability | Block merge |
| high | Likely bug or major issue | Should fix |
| medium | Best practice violation | Recommend fix |
| low | Minor improvement | Optional |
| info | Informational only | FYI |

## Adding Custom Rules

Add project-specific rules in `configs/review_rules/`:

```yaml
# configs/review_rules/billwatch.yaml
rules:
  - name: "congress-api-key"
    pattern: "CONGRESS_API_KEY|congress.gov"
    severity: "high"
    message: "Ensure Congress API key is from environment"
  
  - name: "rate-limiting"
    pattern: "def (get|post|put|delete)_"
    check: "has_rate_limit_decorator"
    severity: "medium"
    message: "API endpoints should have rate limiting"
```

## Supported Languages

| Language | Security | Style | Performance |
|----------|----------|-------|-------------|
| Python | ✅ | ✅ | ✅ |
| TypeScript | ✅ | ✅ | ✅ |
| JavaScript | ✅ | ✅ | ✅ |
| Swift | ⚠️ | ✅ | ✅ |
| Kotlin | ⚠️ | ✅ | ✅ |
| Go | ✅ | ✅ | ✅ |

## Training Data

The review agent improves over time. Add examples to:

```
training/shared/data/code_review.jsonl
```

Format:
```json
{"code": "...", "issues": [{"line": 5, "severity": "high", ...}], "approved": true}
```
