# GitLark Local LLM Integration

Connect GitLark to Shrike AI Lab for AI-powered code understanding.

## Overview

GitLark uses AI to help developers understand and work with code. Instead of expensive Claude API calls for routine tasks, use fine-tuned local models.

## Use Cases

| Feature | Local Model | Claude Fallback |
|---------|-------------|-----------------|
| Code explanation | ✅ gitlark-explain | Complex code |
| Commit messages | ✅ gitlark-commit | Multi-file changes |
| PR descriptions | ✅ gitlark-pr | Large PRs |
| Code review | ⚠️ Future | ✅ claude-sonnet |
| Architecture analysis | ❌ | ✅ claude-sonnet |

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   GitLark       │────▶│    LiteLLM      │────▶│    Ollama       │
│   Backend       │     │   Proxy :4000   │     │  gitlark-xxx    │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                     ┌───────────┴───────────┐
                     ▼                       ▼
              ┌─────────────┐         ┌─────────────┐
              │ Claude Haiku│         │Claude Sonnet│
              │ (fallback)  │         │ (complex)   │
              └─────────────┘         └─────────────┘
```

## Backend Service Code

Add to `gitlark/backend/app/services/ai_service.py`:

```python
"""
AI service for code understanding tasks.
Routes to local models or Claude based on complexity.
"""

from openai import AsyncOpenAI
from typing import Optional, List, Dict
import os


class AIService:
    def __init__(self):
        self.client = AsyncOpenAI(
            base_url=os.getenv("LLM_BASE_URL", "http://localhost:4000"),
            api_key=os.getenv("LLM_API_KEY", "sk-shrike-local"),
        )
        
        # Task-specific models
        self.models = {
            "explain": os.getenv("LLM_EXPLAIN_MODEL", "gitlark-explain"),
            "commit": os.getenv("LLM_COMMIT_MODEL", "gitlark-commit"),
            "pr": os.getenv("LLM_PR_MODEL", "gitlark-pr"),
            "review": os.getenv("LLM_REVIEW_MODEL", "claude-sonnet"),
            "fallback": os.getenv("LLM_FALLBACK_MODEL", "claude-haiku"),
        }
    
    async def explain_code(self, code: str, language: str) -> str:
        """Generate plain English explanation of code."""
        
        # Use local model for small snippets, Claude for large
        model = self.models["explain"] if len(code) < 500 else self.models["fallback"]
        
        response = await self.client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a senior software engineer. Explain code clearly and concisely."},
                {"role": "user", "content": f"Explain this {language} code:\n\n```{language}\n{code}\n```"},
            ],
            max_tokens=300,
            temperature=0.3,
        )
        
        return response.choices[0].message.content.strip()
    
    async def generate_commit_message(self, diff: str) -> str:
        """Generate semantic commit message from diff."""
        
        response = await self.client.chat.completions.create(
            model=self.models["commit"],
            messages=[
                {"role": "system", "content": "Generate a conventional commit message. Format: type(scope): description"},
                {"role": "user", "content": f"Generate commit message for:\n\n```diff\n{diff[:1000]}\n```"},
            ],
            max_tokens=100,
            temperature=0.2,
        )
        
        return response.choices[0].message.content.strip()
    
    async def generate_pr_description(
        self,
        title: str,
        diff: str,
        commits: List[str],
    ) -> str:
        """Generate PR description from diff and commits."""
        
        commits_text = "\n".join(f"- {c}" for c in commits[:10])
        
        response = await self.client.chat.completions.create(
            model=self.models["pr"],
            messages=[
                {"role": "system", "content": "Write clear PR descriptions with ## sections for Changes, Testing, and Breaking Changes."},
                {"role": "user", "content": f"Title: {title}\n\nCommits:\n{commits_text}\n\nDiff:\n```diff\n{diff[:2000]}\n```"},
            ],
            max_tokens=500,
            temperature=0.3,
        )
        
        return response.choices[0].message.content.strip()
    
    async def review_code(
        self,
        code: str,
        language: str,
        context: Optional[str] = None,
    ) -> List[Dict]:
        """Review code for issues. Uses Claude for accuracy."""
        
        context_text = f"\n\nContext: {context}" if context else ""
        
        response = await self.client.chat.completions.create(
            model=self.models["review"],  # Use Claude for reviews
            messages=[
                {"role": "system", "content": "You are a code reviewer. Return issues as JSON array with line, severity, type, and message."},
                {"role": "user", "content": f"Review this {language} code:{context_text}\n\n```{language}\n{code}\n```"},
            ],
            max_tokens=1000,
            temperature=0.2,
        )
        
        # Parse JSON response
        import json
        try:
            return json.loads(response.choices[0].message.content)
        except json.JSONDecodeError:
            return [{"line": 0, "severity": "info", "message": response.choices[0].message.content}]


# Singleton
_ai_service: Optional[AIService] = None

def get_ai_service() -> AIService:
    global _ai_service
    if _ai_service is None:
        _ai_service = AIService()
    return _ai_service
```

## Conversation Integration

For GitLark's AI conversation feature:

```python
# In gitlark/backend/app/routers/conversations.py

@router.post("/conversations/{id}/messages")
async def send_message(
    id: str,
    message: MessageCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    conversation = await db.get(Conversation, id)
    ai_service = get_ai_service()
    
    # Route based on conversation agent type
    if conversation.agent_type == "code-explain":
        response = await ai_service.explain_code(
            message.content,
            message.language or "python"
        )
    elif conversation.agent_type == "code-review":
        response = await ai_service.review_code(
            message.content,
            message.language or "python"
        )
    else:
        # General conversation - use Claude
        response = await ai_service.general_chat(message.content)
    
    # Save and return
    # ...
```

## Environment Variables

Add to GitLark backend `.env`:

```env
# Shrike AI Lab connection
LLM_BASE_URL=http://192.168.1.xxx:4000
LLM_API_KEY=sk-shrike-local

# Task-specific models
LLM_EXPLAIN_MODEL=gitlark-explain
LLM_COMMIT_MODEL=gitlark-commit
LLM_PR_MODEL=gitlark-pr
LLM_REVIEW_MODEL=claude-sonnet
LLM_FALLBACK_MODEL=claude-haiku

# For Claude fallback
ANTHROPIC_API_KEY=sk-ant-xxx
```

## LiteLLM Configuration

Add to `shrike-ai-lab/configs/litellm_config.yaml`:

```yaml
model_list:
  - model_name: gitlark-explain
    litellm_params:
      model: ollama/gitlark-explain-v1
      api_base: http://ollama:11434
  
  - model_name: gitlark-commit
    litellm_params:
      model: ollama/gitlark-commit-v1
      api_base: http://ollama:11434
  
  - model_name: gitlark-pr
    litellm_params:
      model: ollama/gitlark-pr-v1
      api_base: http://ollama:11434
```

## Training Pipeline

1. **Collect data** from your repos:
   ```bash
   python scripts/data-collection/collect_gitlark_data.py \
       --repos ~/LocalProjects/billwatch ~/LocalProjects/gitlark \
       --output training/gitlark/data/
   ```

2. **Review and clean** the `*_raw.jsonl` files

3. **Fine-tune** models:
   ```bash
   # Code explanation
   python training/gitlark/finetune.py \
       --data data/code_explanation.jsonl \
       --task code_explanation \
       --output ../../models/gitlark-explain-v1
   
   # Commit messages
   python training/gitlark/finetune.py \
       --data data/commit_messages.jsonl \
       --task commit_message \
       --output ../../models/gitlark-commit-v1
   ```

4. **Export to Ollama**:
   ```bash
   python training/specpilot/export_to_ollama.py \
       --model models/gitlark-explain-v1 \
       --name gitlark-explain-v1
   ```

## Quality Metrics

Track model performance:

| Metric | Target | Monitoring |
|--------|--------|------------|
| Latency | <2s | Log p50/p99 |
| User satisfaction | >80% 👍 | Feedback buttons |
| Fallback rate | <20% | Log model used |
| Error rate | <1% | Exception tracking |

## Rollback

If local models underperform:

```env
# Force all tasks to Claude
LLM_EXPLAIN_MODEL=claude-haiku
LLM_COMMIT_MODEL=claude-haiku
LLM_PR_MODEL=claude-haiku
```
