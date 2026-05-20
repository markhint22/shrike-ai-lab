# BillWatch Training - AI Bill Summarization

Train models to summarize federal legislation in plain English.

## Use Case

BillWatch needs to generate user-friendly summaries of Congressional bills. Instead of expensive Claude API calls, we can use a fine-tuned local model for basic summarization.

## Training Tasks

### 1. Bill Summary Generation
Convert legal bill text to plain English summaries.

```json
{"bill_text": "...", "summary": "This bill would..."}
```

### 2. Policy Area Classification
Categorize bills by topic.

```json
{"bill_text": "...", "policy_area": "Healthcare"}
```

### 3. Impact Analysis
Explain who the bill affects and how.

```json
{"bill_text": "...", "impact": {"groups": ["farmers", "consumers"], "effects": [...]}}
```

## Data Collection

Run the data collection script to extract training examples:

```bash
python scripts/data-collection/collect_billwatch_data.py \
    --congress-api-key $CONGRESS_API_KEY \
    --output training/billwatch/data/
```

## Fine-tuning

```bash
python training/billwatch/finetune.py \
    --data data/bill_summaries.jsonl \
    --task summarization \
    --output ../../models/billwatch-v1
```

## Integration with BillWatch

See `docs/integrations/BILLWATCH_INTEGRATION.md` for connecting to BillWatch backend.

## Model Selection

| Model | VRAM | Speed | Quality |
|-------|------|-------|---------|
| Phi-3-mini | 4GB | Fast | Good for short bills |
| Mistral-7B | 8GB | Medium | Better comprehension |
| CodeLlama-7B | 8GB | Medium | If bills contain legal code |

Recommend **Mistral-7B** for bill summarization due to its strong instruction-following.

## Quality Assurance

Compare local model output to Claude Haiku for quality validation:

```bash
python training/billwatch/evaluate.py \
    --model ../../models/billwatch-v1 \
    --test-data data/bill_summaries_test.jsonl \
    --compare-to claude-haiku
```
