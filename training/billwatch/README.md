# BillWatch Training - AI Bill Analysis & Summarization

Train models to summarize federal legislation in plain English, surface background context, and rank relevant articles.

## Use Case

BillWatch users need to understand what a bill does, why it matters, and what expert opinions exist — without reading dozens of news articles themselves. Instead of expensive Claude API calls for every user, fine-tuned local models handle the bulk of analysis.

## Training Tasks

### Phase 1 (Original)

#### 1. Bill Summary Generation
Convert legal bill text to plain English summaries.

```json
{"bill_text": "...", "summary": "This bill would..."}
```

#### 2. Policy Area Classification
Categorize bills by topic.

```json
{"bill_text": "...", "policy_area": "Healthcare"}
```

#### 3. Impact Analysis
Explain who the bill affects and how.

```json
{"bill_text": "...", "impact": {"groups": ["farmers", "consumers"], "effects": [...]}}
```

### Phase 2 (New Capsules)

#### 4. Bill Background Brief
Given a bill, produce a structured background brief: what it does, why it matters, who is affected, expert perspectives, and related legislation.

```json
{
  "bill_id": "hr1234-118",
  "title": "...",
  "bill_text": "...",
  "topics": ["renewable energy", "climate"],
  "background_brief": {
    "what_the_bill_does": "...",
    "why_it_matters": "...",
    "key_stakeholders": [...],
    "policy_context": "...",
    "expert_perspectives": [...],
    "related_bills": [...]
  }
}
```

#### 5. Article Relevance Ranking
Given a bill's topics and a list of candidate articles, rank them by relevance and type (bill_direct, bill_perspective, subject_matter, irrelevant).

```json
{
  "bill_topics": ["AI regulation", "algorithmic accountability"],
  "candidate_articles": [...],
  "ranked_selection": [
    {"rank": 1, "url": "...", "type": "bill_direct", "why_selected": "..."},
    ...
  ]
}
```

## Training Commands

```bash
# Phase 1
make train-billwatch-summary
make train-billwatch-classify

# Phase 2
make train-billwatch-background
make train-billwatch-articles
```

## Data Collection

```bash
python scripts/data-collection/collect_billwatch_data.py \
    --congress-api-key $CONGRESS_API_KEY \
    --output training/billwatch/data/
```

## Integration with BillWatch

See `docs/integrations/BILLWATCH_INTEGRATION.md`.

## Model Selection

| Model | VRAM | Speed | Quality |
|-------|------|-------|---------|
| Phi-3-mini | 4GB | Fast | Good for short bills |
| Mistral-7B | 8GB | Medium | Better comprehension |

Recommend **Mistral-7B** for bill analysis tasks.

