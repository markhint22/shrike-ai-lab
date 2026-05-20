# GitLark Training - AI Code Understanding

Train models to understand, explain, and work with code for the GitLark AI code workspace.

## Training Tasks

### 1. Code Explanation
Convert code snippets to plain English explanations.

```json
{"code": "...", "explanation": "This function does X by..."}
```

### 2. PR Description Generation
Generate PR descriptions from diffs.

```json
{"diff": "...", "title": "feat(auth): add OAuth", "description": "..."}
```

### 3. Code Review
Identify issues and suggest improvements.

```json
{"code": "...", "issues": [{"line": 5, "severity": "high", "message": "..."}]}
```

### 4. Commit Message Generation
Generate semantic commit messages from diffs.

```json
{"diff": "...", "commit_message": "fix(api): handle null response"}
```

### 5. Architecture Analysis
Analyze repository structure and explain architecture.

```json
{"file_tree": "...", "analysis": "This is a FastAPI backend with..."}
```

### 6. Feature Planning
Break down feature requests into implementation steps.

```json
{"request": "Add dark mode", "plan": ["1. Create theme context", "2. ..."]}
```

## Data Collection

Run the data collection script to extract training examples from your repos:

```bash
python scripts/data-collection/collect_gitlark_data.py \
    --repos ~/LocalProjects/billwatch ~/LocalProjects/gitlark \
    --output training/gitlark/data/
```

## Fine-tuning

```bash
python training/gitlark/finetune.py \
    --data data/code_explanation.jsonl \
    --task code_explanation \
    --output ../../models/gitlark-v1
```

## Evaluation

Test the model on held-out examples:

```bash
python training/gitlark/evaluate.py \
    --model ../../models/gitlark-v1 \
    --test-data data/code_explanation_test.jsonl
```

## Integration with GitLark

See `docs/integrations/GITLARK_INTEGRATION.md` for connecting to GitLark backend.
