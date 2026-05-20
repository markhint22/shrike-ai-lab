# BillWatch Local LLM Integration

Connect BillWatch backend to Shrike AI Lab for cheap bill summarization.

## Overview

Instead of using Claude API for every bill summary (expensive at scale), BillWatch can use a local fine-tuned model for basic summarization and fall back to Claude for complex cases.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   BillWatch     │────▶│    LiteLLM      │────▶│    Ollama       │
│   Backend       │     │   Proxy :4000   │     │  billwatch-v1   │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │ fallback
                                 ▼
                        ┌─────────────────┐
                        │  Claude Haiku   │
                        │  (Anthropic)    │
                        └─────────────────┘
```

## Backend Service Code

Add this to `billwatch-backend/app/services/llm_service.py`:

```python
"""
Local LLM service for bill summarization.
Routes through LiteLLM to Ollama or Claude fallback.
"""

from openai import AsyncOpenAI
from typing import Optional
import os


class LLMService:
    def __init__(self):
        # Connect to LiteLLM proxy
        self.client = AsyncOpenAI(
            base_url=os.getenv("LLM_BASE_URL", "http://localhost:4000"),
            api_key=os.getenv("LLM_API_KEY", "sk-shrike-local"),
        )
        
        # Model routing
        self.summary_model = os.getenv("LLM_SUMMARY_MODEL", "billwatch-local")
        self.fallback_model = os.getenv("LLM_FALLBACK_MODEL", "claude-fallback")
    
    async def summarize_bill(
        self,
        title: str,
        bill_text: str,
        use_fallback: bool = False,
    ) -> str:
        """Generate plain English summary of a bill."""
        
        model = self.fallback_model if use_fallback else self.summary_model
        
        prompt = f"""Summarize this bill in plain English for a general audience.
Keep it under 200 words.

Title: {title}

{bill_text[:3000]}"""
        
        try:
            response = await self.client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": "You are a policy analyst who explains legislation in plain English."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=300,
                temperature=0.3,
            )
            
            return response.choices[0].message.content.strip()
        
        except Exception as e:
            if not use_fallback:
                # Try fallback model
                return await self.summarize_bill(title, bill_text, use_fallback=True)
            raise
    
    async def classify_bill(self, title: str, bill_text: str) -> str:
        """Classify bill into policy area."""
        
        prompt = f"""Classify this bill into ONE policy area.
Options: Healthcare, Energy, Education, Defense, Economy, Immigration, Environment, Government Operations, Transportation, Other

Title: {title}

{bill_text[:1000]}

Policy Area:"""
        
        response = await self.client.chat.completions.create(
            model=self.summary_model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=20,
            temperature=0,
        )
        
        return response.choices[0].message.content.strip()


# Singleton instance
_llm_service: Optional[LLMService] = None

def get_llm_service() -> LLMService:
    global _llm_service
    if _llm_service is None:
        _llm_service = LLMService()
    return _llm_service
```

## Usage in Bill Router

```python
# In billwatch-backend/app/routers/bills.py

from app.services.llm_service import get_llm_service

@router.get("/bills/{bill_id}/summary")
async def get_bill_summary(
    bill_id: str,
    db: AsyncSession = Depends(get_db),
):
    bill = await db.get(Bill, bill_id)
    if not bill:
        raise HTTPException(404)
    
    # Check cache first
    if bill.ai_summary and bill.summary_updated_at > datetime.now() - timedelta(days=7):
        return {"summary": bill.ai_summary}
    
    # Generate new summary
    llm = get_llm_service()
    summary = await llm.summarize_bill(bill.title, bill.full_text)
    
    # Cache it
    bill.ai_summary = summary
    bill.summary_updated_at = datetime.now()
    await db.commit()
    
    return {"summary": summary}
```

## Environment Variables

Add to BillWatch backend `.env`:

```env
# Local LLM (Shrike AI Lab)
LLM_BASE_URL=http://192.168.1.xxx:4000  # Your Windows PC IP
LLM_API_KEY=sk-shrike-local
LLM_SUMMARY_MODEL=billwatch-local
LLM_FALLBACK_MODEL=claude-fallback

# For fallback to work, also need:
ANTHROPIC_API_KEY=sk-ant-xxx
```

## LiteLLM Configuration

Add to `shrike-ai-lab/configs/litellm_config.yaml`:

```yaml
model_list:
  - model_name: billwatch-local
    litellm_params:
      model: ollama/billwatch-v1
      api_base: http://ollama:11434
    model_info:
      description: "Fine-tuned bill summarization model"
```

## Network Setup

For BillWatch backend on Railway to reach your Windows PC:

### Option A: Tailscale (Recommended)
1. Install Tailscale on Windows PC and Mac
2. Use Tailscale IP for LLM_BASE_URL
3. No port forwarding needed

### Option B: ngrok
```bash
# On Windows PC
ngrok http 4000
```
Use ngrok URL for LLM_BASE_URL

### Option C: Local Development Only
If running BillWatch locally:
```env
LLM_BASE_URL=http://localhost:4000
```

## Cost Comparison

| Approach | Cost per 1000 summaries |
|----------|------------------------|
| Claude Haiku (API) | ~$0.25 |
| Local Mistral-7B | ~$0.02 (electricity) |
| Savings | ~92% |

At 10,000 bills/month: Save ~$23/month

## Quality Monitoring

Track summary quality:

```python
# In llm_service.py

async def summarize_bill_with_metrics(self, title: str, bill_text: str):
    start = time.time()
    summary = await self.summarize_bill(title, bill_text)
    duration = time.time() - start
    
    # Log for quality review
    logger.info(f"Summary generated", extra={
        "model": self.summary_model,
        "duration_ms": duration * 1000,
        "input_length": len(bill_text),
        "output_length": len(summary),
    })
    
    return summary
```

Periodically review generated summaries and add good/bad examples to training data.

## Rollback Plan

If local model quality is poor:

```python
# Force Claude for all summaries
LLM_SUMMARY_MODEL=claude-fallback
```

Or in code:
```python
summary = await llm.summarize_bill(title, text, use_fallback=True)
```
