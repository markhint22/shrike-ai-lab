# SpecPilot Integration Guide

This guide explains how to connect SpecPilot (test-automation-agent) to the local LLM infrastructure.

## Overview

```
┌─────────────────────────────────────┐
│         SpecPilot Backend           │
│    (test-automation-agent)          │
│                                     │
│  ┌─────────────────────────────┐   │
│  │      LLM Service            │   │
│  │  app/services/llm_service   │   │
│  └──────────────┬──────────────┘   │
└─────────────────┼───────────────────┘
                  │ HTTP (OpenAI API format)
                  ▼
┌─────────────────────────────────────┐
│         LiteLLM Proxy               │
│     http://localhost:4000           │
│                                     │
│  Routes to:                         │
│  • specpilot-local → Ollama         │
│  • claude-fallback → Anthropic      │
└─────────────────────────────────────┘
```

## Step 1: Update SpecPilot's LLM Service

Edit `test-automation-agent/backend/app/services/llm_service.py`:

```python
import os
from openai import OpenAI

class LLMService:
    def __init__(self):
        # Use local LLM via LiteLLM proxy
        self.client = OpenAI(
            base_url=os.getenv("LLM_BASE_URL", "http://localhost:4000"),
            api_key=os.getenv("LLM_API_KEY", "sk-shrike-local")
        )
        
        # Model selection based on task complexity
        self.models = {
            "simple": "specpilot-local",      # Fast, local (CodeLlama 7B)
            "medium": "mistral-local",         # Better reasoning
            "complex": "claude-fallback",      # Cloud fallback
        }
    
    def get_completion(
        self,
        prompt: str,
        complexity: str = "simple",
        max_tokens: int = 500,
        temperature: float = 0.7
    ) -> str:
        """Get completion from appropriate model."""
        model = self.models.get(complexity, "specpilot-local")
        
        response = self.client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
            temperature=temperature
        )
        
        return response.choices[0].message.content
    
    def optimize_selector(self, html: str, current_selector: str) -> dict:
        """Optimize a CSS selector for reliability."""
        prompt = f"""Given this HTML element and current selector, suggest a more reliable selector.

HTML:
{html}

Current selector: {current_selector}

Respond in JSON format:
{{"selector": "...", "reason": "...", "alternatives": ["...", "..."]}}"""

        response = self.get_completion(prompt, complexity="simple")
        
        # Parse JSON response
        import json
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            return {"selector": current_selector, "reason": "Parse error", "alternatives": []}
    
    def generate_playwright_code(self, instruction: str) -> str:
        """Convert natural language to Playwright code."""
        prompt = f"""Convert this test step to Playwright TypeScript code.
Return only the code, no explanation.

Instruction: {instruction}"""

        return self.get_completion(prompt, complexity="simple", max_tokens=200)
    
    def analyze_failure(self, error: str, html: str = None, screenshot_url: str = None) -> dict:
        """Analyze a test failure and suggest fixes."""
        prompt = f"""Analyze this test failure and suggest a fix.

Error: {error}
"""
        if html:
            prompt += f"\nHTML context:\n{html[:500]}..."
        
        prompt += """

Respond in JSON format:
{"diagnosis": "...", "fix": "...", "confidence": 0.0-1.0}"""

        # Use more capable model for complex analysis
        complexity = "complex" if screenshot_url else "medium"
        response = self.get_completion(prompt, complexity=complexity)
        
        import json
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            return {"diagnosis": response, "fix": "See diagnosis", "confidence": 0.5}
```

## Step 2: Update Environment Variables

Add to `test-automation-agent/backend/.env`:

```env
# Local LLM Configuration
LLM_BASE_URL=http://localhost:4000
LLM_API_KEY=sk-shrike-local

# Optional: Anthropic fallback (for complex tasks)
ANTHROPIC_API_KEY=your-key-here
```

## Step 3: Start the Infrastructure

On your Windows PC with the RTX GPU:

```bash
cd shrike-ai-lab
make setup   # First time only
make start   # Start Ollama + LiteLLM
make status  # Verify everything is running
```

## Step 4: Test the Connection

```bash
# From SpecPilot directory
cd test-automation-agent/backend

# Quick test
python -c "
from app.services.llm_service import LLMService
llm = LLMService()
result = llm.optimize_selector(
    '<button class=\"btn\">Submit</button>',
    '.btn'
)
print(result)
"
```

## Model Selection Strategy

| Task | Model | Why |
|------|-------|-----|
| Selector optimization | `specpilot-local` | Fast, good at patterns |
| Code generation | `specpilot-local` | CodeLlama trained on code |
| Simple failure analysis | `mistral-local` | Better reasoning |
| Complex failure (with screenshots) | `claude-fallback` | Vision capabilities |

## Continuous Improvement Loop

### 1. Collect Training Data

As SpecPilot runs, save successful interactions:

```python
# In your selector optimizer, after a successful optimization:
def log_training_example(html, bad_selector, good_selector, reason):
    import json
    from pathlib import Path
    
    example = {
        "html": html,
        "bad_selector": bad_selector,
        "good_selector": good_selector,
        "reason": reason
    }
    
    # Append to training data
    data_file = Path("path/to/shrike-ai-lab/training/specpilot/data/selector_optimization.jsonl")
    with open(data_file, "a") as f:
        f.write(json.dumps(example) + "\n")
```

### 2. Periodically Fine-tune

When you have 100+ new examples:

```bash
cd shrike-ai-lab
make train   # Fine-tune on updated data
make export  # Deploy to Ollama
```

### 3. A/B Test

Compare fine-tuned model vs base:

```python
# In LLMService
def optimize_selector_ab_test(self, html, selector):
    # Get results from both models
    base_result = self._optimize_with_model("specpilot-local", html, selector)
    tuned_result = self._optimize_with_model("specpilot-finetuned", html, selector)
    
    # Log both for comparison
    self._log_ab_result(html, selector, base_result, tuned_result)
    
    # Use fine-tuned by default
    return tuned_result
```

## Troubleshooting

### "Connection refused"

```bash
# Check services are running
cd shrike-ai-lab
make status

# If not running:
make start
```

### "Model not found"

```bash
# List available models
docker exec shrike-ollama ollama list

# Pull missing model
docker exec shrike-ollama ollama pull codellama:7b-instruct
```

### "Slow responses"

- Check GPU is being used: `nvidia-smi`
- Reduce `max_tokens` for faster responses
- Use `phi3-local` for quick tasks

### "Poor quality responses"

- Try `mistral-local` or `claude-fallback`
- Add more context to prompts
- Consider fine-tuning with more examples

## Network Configuration

If SpecPilot and shrike-ai-lab run on different machines:

```env
# On SpecPilot machine, point to Windows PC
LLM_BASE_URL=http://192.168.1.100:4000  # Your Windows PC IP
```

On Windows PC, update `docker-compose.yml` to expose ports:

```yaml
services:
  litellm:
    ports:
      - "0.0.0.0:4000:4000"  # Allow external connections
```

## Cost Savings

Using local LLM vs Claude API:

| Scenario | Claude API Cost | Local Cost |
|----------|-----------------|------------|
| 1,000 selector optimizations | ~$2-5 | $0 |
| 10,000 test generations | ~$20-50 | $0 |
| 24/7 autonomous agent | ~$100/day | ~$0.50/day |

Break-even: After ~500 requests, local pays for electricity costs.
