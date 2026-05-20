# SpecPilot Training - Fine-tuning for UI Test Automation

This directory contains training data and scripts for fine-tuning local LLMs to be better at:
1. **Selector Optimization** - Finding reliable CSS/XPath selectors
2. **Test Step Generation** - Converting natural language to Playwright actions
3. **Failure Analysis** - Diagnosing why tests fail from screenshots/HTML

## Training Strategy

### Phase 1: Curate Training Data
Collect examples from real SpecPilot usage:

```
data/
├── selector_optimization.jsonl    # Good selector → better selector pairs
├── test_generation.jsonl          # Natural language → Playwright code
├── failure_analysis.jsonl         # Screenshot + error → diagnosis
└── html_understanding.jsonl       # HTML snippets → element identification
```

### Phase 2: Format for Fine-tuning
Convert to instruction format:

```json
{
  "instruction": "Find the most reliable selector for the login button",
  "input": "<button class=\"btn login-btn\" id=\"login\" data-testid=\"auth-login\">Sign In</button>",
  "output": "[data-testid=\"auth-login\"] - data-testid is most stable, won't change with styling updates"
}
```

### Phase 3: Fine-tune with QLoRA
Use Unsloth for memory-efficient training on RTX 2080:

```bash
# Install training dependencies
pip install unsloth transformers datasets peft

# Run fine-tuning
python finetune.py --model codellama-7b --data data/selector_optimization.jsonl
```

## Data Collection

### From SpecPilot Runs
After each successful test run, export:
- Selectors that worked vs. failed
- Retry attempts with corrections
- HTML context for each interaction

### Manual Curation
Add expert-annotated examples:
- Best practices for selector patterns
- Common failure patterns and fixes
- Edge cases and solutions

## File Formats

### selector_optimization.jsonl
```json
{"html": "<button class='submit'>Submit</button>", "bad_selector": ".submit", "good_selector": "button:has-text('Submit')", "reason": "Text-based selector is more stable than class"}
{"html": "<input data-testid='email' type='email'>", "context": "login form", "best_selector": "[data-testid='email']", "alternatives": ["input[type='email']", "#email"]}
```

### test_generation.jsonl
```json
{"instruction": "Click the login button", "playwright_code": "await page.click('[data-testid=\"login-btn\"]')"}
{"instruction": "Fill in email field with test@example.com", "playwright_code": "await page.fill('input[type=\"email\"]', 'test@example.com')"}
```

### failure_analysis.jsonl
```json
{"error": "TimeoutError: waiting for selector", "selector": "#dynamic-content", "diagnosis": "Element loads asynchronously", "fix": "Add explicit wait: await page.waitForSelector('#dynamic-content', {state: 'visible'})"}
```

## Evaluation

After fine-tuning, evaluate on held-out test set:
- Selector accuracy: Does suggested selector work?
- Code correctness: Does generated Playwright code run?
- Diagnosis accuracy: Is failure analysis correct?

Target metrics:
- Selector suggestion accuracy: >85%
- Code generation success: >90%
- Failure diagnosis relevance: >80%

## Integration with SpecPilot

Once trained, deploy the model:

1. Export to Ollama format:
   ```bash
   python export_to_ollama.py --checkpoint checkpoints/best
   ```

2. Update SpecPilot's LLM config:
   ```python
   # In test-automation-agent/backend/app/services/llm_service.py
   SELECTOR_MODEL = "specpilot-finetuned"  # Your trained model
   ```

3. Compare performance:
   - A/B test against base CodeLlama
   - Track selector success rate
   - Measure test pass rate improvement
