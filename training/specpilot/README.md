# SpecPilot Training - Fine-tuning for UI Test Automation

This directory contains training data and scripts for fine-tuning local LLMs to understand and automate UI test flows end-to-end.

## Training Tasks

### Phase 1 (Original)
1. **Selector Optimization** - Finding reliable CSS/XPath selectors
2. **Test Step Generation** - Converting natural language to Playwright actions
3. **Failure Analysis** - Diagnosing why tests fail from screenshots/HTML

### Phase 2 (New Capsules)
4. **Flow Analysis** - Understanding the full test flow: detect auth requirements, identify prerequisites, recognize multi-step patterns
5. **Test Building** - Composing complete test suites: assertions, error state coverage, pagination, optimistic UI updates

## Data Files

```
data/
├── selector_optimization.jsonl    # Good selector → better selector pairs
├── test_generation.jsonl          # Natural language → Playwright code
├── failure_analysis.jsonl         # Screenshot + error → diagnosis
├── flow_analysis.jsonl            # Test plan → auth/setup requirements (NEW)
└── test_building.jsonl            # Test goal → full assertion suite (NEW)
```

## Flow Analysis Format

```json
{
  "test_plan_step": "Navigate to /dashboard",
  "page_html_snippet": "...",
  "requires_auth": true,
  "auth_detection_signals": ["URL path is /dashboard", "No login form visible"],
  "recommended_setup": {
    "create_user": true,
    "user_config": {"email": "...", "password": "...", "role": "standard"},
    "login_steps": [...]
  },
  "flow_type": "authenticated_page"
}
```

## Test Building Format

```json
{
  "test_goal": "Verify login form shows error for invalid email",
  "flow_type": "form_validation",
  "assertions": [
    {"type": "element_visible", "selector": "[data-testid='email-error']",
     "playwright": "await expect(page.locator('...')).toBeVisible()"}
  ],
  "full_test": "// complete Playwright test code"
}
```

## Training Commands

```bash
# Phase 1
make train-specpilot-selector
make train-specpilot-tests
make train-specpilot-analyzer

# Phase 2
make train-specpilot-flow
make train-specpilot-build
```

## Fine-tune with QLoRA

```bash
pip install unsloth transformers datasets peft
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
