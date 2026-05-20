# SpecPilot Local LLM Integration

Connect SpecPilot (Test Automation Agent) to Shrike AI Lab for intelligent test automation.

## Overview

SpecPilot uses AI for:
- **Selector Optimization**: Find stable element selectors
- **Test Generation**: Convert natural language to Playwright code
- **Failure Analysis**: Diagnose and fix test failures

Using local models reduces API costs by ~90% for routine operations.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   SpecPilot     │────▶│    LiteLLM      │────▶│    Ollama       │
│   Backend       │     │   Proxy :4000   │     │  specpilot-*    │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                     ┌───────────┴───────────┐
                     ▼                       ▼
              ┌─────────────┐         ┌─────────────┐
              │ Claude Flash│         │Claude Sonnet│
              │ (fast ops)  │         │ (complex)   │
              └─────────────┘         └─────────────┘
```

## Task-Specific Models

| Task | Local Model | Fallback | When to Use Local |
|------|-------------|----------|-------------------|
| Selector Optimization | specpilot-selector-v1 | Claude Flash | Simple HTML, <500 chars |
| Test Generation | specpilot-tests-v1 | Claude Haiku | Single-step tests |
| Failure Analysis | specpilot-analyzer-v1 | Claude Sonnet | Common error patterns |

## Backend Service Code

Add to `test-automation-agent/backend/app/services/llm_service.py`:

```python
"""
Local LLM service for SpecPilot.
Routes through LiteLLM to Ollama or Claude fallback.
"""

from openai import AsyncOpenAI
from typing import Optional, Dict, Any, List
import os
import base64


class LLMService:
    """LLM service with local model routing."""
    
    def __init__(self):
        self.client = AsyncOpenAI(
            base_url=os.getenv("LLM_BASE_URL", "http://localhost:4000"),
            api_key=os.getenv("LLM_API_KEY", "sk-shrike-local"),
        )
        
        # Model routing by tier
        self.tier_models = {
            "starter": {
                "selector": os.getenv("LLM_SELECTOR_MODEL", "specpilot-selector-v1"),
                "tests": os.getenv("LLM_TESTS_MODEL", "claude-flash"),
                "analyzer": os.getenv("LLM_ANALYZER_MODEL", "claude-flash"),
            },
            "pro": {
                "selector": os.getenv("LLM_SELECTOR_MODEL", "specpilot-selector-v1"),
                "tests": os.getenv("LLM_TESTS_MODEL", "specpilot-tests-v1"),
                "analyzer": os.getenv("LLM_ANALYZER_MODEL", "claude-haiku"),
            },
            "enterprise": {
                "selector": os.getenv("LLM_SELECTOR_MODEL", "specpilot-selector-v1"),
                "tests": os.getenv("LLM_TESTS_MODEL", "specpilot-tests-v1"),
                "analyzer": os.getenv("LLM_ANALYZER_MODEL", "claude-sonnet"),
            },
        }
    
    def get_model(self, task: str, tier: str = "pro") -> str:
        """Get model for task based on user tier."""
        return self.tier_models.get(tier, self.tier_models["pro"]).get(task)
    
    async def optimize_selector(
        self,
        html: str,
        failing_selector: str,
        tier: str = "pro",
    ) -> Dict[str, Any]:
        """Find better selector for element."""
        
        model = self.get_model("selector", tier)
        
        prompt = f"""Given this HTML and a failing selector, suggest a better selector.

HTML:
```html
{html[:2000]}
```

Failing selector: {failing_selector}

Return JSON:
{{
  "selector": "better-selector",
  "strategy": "css|xpath|text|testid",
  "confidence": 0.0-1.0,
  "reason": "why this is better"
}}"""
        
        response = await self.client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a Playwright selector expert. Return valid JSON only."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=200,
            temperature=0.2,
        )
        
        import json
        try:
            return json.loads(response.choices[0].message.content)
        except json.JSONDecodeError:
            return {
                "selector": failing_selector,
                "strategy": "original",
                "confidence": 0.0,
                "reason": "Could not parse response",
            }
    
    async def generate_test(
        self,
        instruction: str,
        context: Optional[str] = None,
        tier: str = "pro",
    ) -> str:
        """Generate Playwright test code from instruction."""
        
        model = self.get_model("tests", tier)
        
        context_text = f"\n\nPage context: {context}" if context else ""
        
        prompt = f"""Generate Playwright test code for this instruction:

{instruction}{context_text}

Return only valid Playwright/TypeScript code, no explanation."""
        
        response = await self.client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a Playwright test automation expert. Generate clean, working test code."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=500,
            temperature=0.3,
        )
        
        return response.choices[0].message.content.strip()
    
    async def analyze_failure(
        self,
        error_message: str,
        screenshot_base64: Optional[str] = None,
        test_code: Optional[str] = None,
        tier: str = "pro",
    ) -> Dict[str, Any]:
        """Analyze test failure and suggest fix."""
        
        model = self.get_model("analyzer", tier)
        
        messages = [
            {"role": "system", "content": "You are a test failure analyst. Diagnose issues and suggest fixes."},
        ]
        
        # Build user message with optional screenshot
        content = []
        
        prompt = f"""Analyze this test failure:

Error: {error_message}
"""
        if test_code:
            prompt += f"\nTest code:\n```\n{test_code}\n```"
        
        prompt += "\n\nReturn JSON: {\"diagnosis\": \"...\", \"category\": \"selector|timing|logic|data|environment\", \"fix\": \"...\", \"confidence\": 0.0-1.0}"
        
        content.append({"type": "text", "text": prompt})
        
        # Add screenshot if available and using vision-capable model
        if screenshot_base64 and "sonnet" in model:
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{screenshot_base64}"}
            })
        
        messages.append({"role": "user", "content": content if screenshot_base64 else prompt})
        
        response = await self.client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=300,
            temperature=0.2,
        )
        
        import json
        try:
            return json.loads(response.choices[0].message.content)
        except json.JSONDecodeError:
            return {
                "diagnosis": response.choices[0].message.content,
                "category": "unknown",
                "fix": "Review error message manually",
                "confidence": 0.5,
            }


# Singleton
_llm_service: Optional[LLMService] = None

def get_llm_service() -> LLMService:
    global _llm_service
    if _llm_service is None:
        _llm_service = LLMService()
    return _llm_service
```

## Agent Integration

Update `test-automation-agent/backend/app/agents/optimizer.py`:

```python
from app.services.llm_service import get_llm_service

class SelectorOptimizer:
    def __init__(self, tier: str = "pro"):
        self.llm = get_llm_service()
        self.tier = tier
    
    async def find_better_selector(
        self,
        html: str,
        failing_selector: str,
    ) -> Dict[str, Any]:
        """Use LLM to find better selector."""
        
        # Try local model first
        result = await self.llm.optimize_selector(
            html=html,
            failing_selector=failing_selector,
            tier=self.tier,
        )
        
        # Log for training data collection
        logger.info("selector_optimization", extra={
            "html_length": len(html),
            "failing_selector": failing_selector,
            "suggested_selector": result["selector"],
            "confidence": result["confidence"],
            "model": self.llm.get_model("selector", self.tier),
        })
        
        return result
```

## Environment Variables

Add to SpecPilot backend `.env`:

```env
# Shrike AI Lab connection
LLM_BASE_URL=http://192.168.1.xxx:4000  # Your Windows PC IP
LLM_API_KEY=sk-shrike-local

# Model overrides (optional)
LLM_SELECTOR_MODEL=specpilot-selector-v1
LLM_TESTS_MODEL=specpilot-tests-v1
LLM_ANALYZER_MODEL=claude-haiku

# For Claude fallback
ANTHROPIC_API_KEY=sk-ant-xxx
```

## LiteLLM Configuration

Add to `shrike-ai-lab/configs/litellm_config.yaml`:

```yaml
model_list:
  - model_name: specpilot-selector-v1
    litellm_params:
      model: ollama/specpilot-selector-v1
      api_base: http://ollama:11434
    model_info:
      description: "Fine-tuned selector optimization"
  
  - model_name: specpilot-tests-v1
    litellm_params:
      model: ollama/specpilot-tests-v1
      api_base: http://ollama:11434
    model_info:
      description: "Fine-tuned test generation"
  
  - model_name: specpilot-analyzer-v1
    litellm_params:
      model: ollama/specpilot-analyzer-v1
      api_base: http://ollama:11434
    model_info:
      description: "Fine-tuned failure analysis"
```

## Training Data Collection

SpecPilot can automatically collect training data from production:

```python
# In optimizer.py - after successful selector fix

async def log_successful_optimization(
    self,
    html: str,
    bad_selector: str,
    good_selector: str,
    success: bool,
):
    """Log successful optimizations for training."""
    if success:
        training_example = {
            "html": html[:1000],  # Truncate
            "bad_selector": bad_selector,
            "good_selector": good_selector,
            "timestamp": datetime.now().isoformat(),
        }
        
        # Append to training data file
        with open("/var/log/specpilot/training_data.jsonl", "a") as f:
            f.write(json.dumps(training_example) + "\n")
```

Then periodically sync to shrike-ai-lab for retraining:

```bash
# On Windows PC
scp specpilot-server:/var/log/specpilot/training_data.jsonl \
    training/specpilot/data/selector_optimization_production.jsonl
```

## Cost Comparison

| Operation | Claude API | Local Model | Savings |
|-----------|-----------|-------------|---------|
| Selector optimization | $0.0003 | ~$0.00002 | 93% |
| Test generation | $0.001 | ~$0.0001 | 90% |
| Failure analysis (no image) | $0.002 | ~$0.0002 | 90% |
| Failure analysis (with image) | $0.01 | N/A* | 0% |

*Image analysis requires Claude Sonnet - keep for enterprise tier.

At 10,000 optimizations/month: Save ~$3/month on selectors alone.

## Monitoring

Track local model performance vs Claude:

```python
# Metrics to track
metrics = {
    "local_model_calls": Counter(),
    "fallback_calls": Counter(),
    "local_success_rate": Gauge(),
    "avg_latency_ms": Histogram(),
}
```

Dashboard query example:
```sql
SELECT 
  model,
  COUNT(*) as calls,
  AVG(latency_ms) as avg_latency,
  SUM(CASE WHEN success THEN 1 ELSE 0 END) / COUNT(*) as success_rate
FROM llm_calls
WHERE timestamp > NOW() - INTERVAL '7 days'
GROUP BY model
```

## Rollback

If local models underperform:

```env
# Force all operations to Claude
LLM_SELECTOR_MODEL=claude-flash
LLM_TESTS_MODEL=claude-haiku
LLM_ANALYZER_MODEL=claude-sonnet
```
