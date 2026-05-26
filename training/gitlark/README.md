# GitLark Training - AI Code Understanding & Repo Intelligence

Train models to understand, explain, and work with code for the GitLark AI code workspace, including deep repo analysis and smart memory retrieval.

## Training Tasks

### Phase 1 (Original)

#### 1. Code Explanation
Convert code snippets to plain English explanations.

```json
{"code": "...", "explanation": "This function does X by..."}
```

#### 2. PR Description Generation
Generate PR descriptions from diffs.

```json
{"diff": "...", "title": "feat(auth): add OAuth", "description": "..."}
```

#### 3. Code Review
Identify issues and suggest improvements.

```json
{"code": "...", "issues": [{"line": 5, "severity": "high", "message": "..."}]}
```

#### 4. Commit Message Generation
Generate semantic commit messages from diffs.

```json
{"diff": "...", "commit_message": "fix(api): handle null response"}
```

### Phase 2 (New Capsules)

#### 5. Repo Intelligence
Analyze a repository's file tree, dependencies, and structure to produce structured metadata: tech stack, architecture patterns, suggested features, and learning paths.

```json
{
  "repo_name": "...",
  "file_tree": "...",
  "sample_files": {...},
  "metadata": {
    "primary_language": "Python",
    "framework": "FastAPI",
    "architecture_pattern": "Layered",
    ...
  },
  "suggested_features": [...],
  "learning_path": [...]
}
```

#### 6. MemDiff — Smart Memory & Pull Decisions
Decide when to pull fresh data from the repo vs. use cached knowledge, based on context, staleness, and the nature of the question.

```json
{
  "scenario": "stale_cache_after_commit",
  "user_query": "Does the bills router handle pagination?",
  "memory_state": {"has_prior_snapshot": true, "last_seen": "48 hours ago"},
  "decision": "pull_fresh",
  "action": "re_read_file",
  "files_to_read": ["app/routers/bills.py"],
  "reasoning": "48 hours is too stale for an active repo. Must re-read."
}
```

## Training Commands

```bash
# Phase 1
make train-gitlark-explain
make train-gitlark-review
make train-gitlark-pr
make train-gitlark-commit

# Phase 2
make train-gitlark-repo-intel
make train-gitlark-memdiff
```

## Data Collection

```bash
python scripts/data-collection/collect_gitlark_data.py \
    --repos ~/LocalProjects/billwatch ~/LocalProjects/gitlark \
    --output training/gitlark/data/
```

## Integration with GitLark

See `docs/integrations/GITLARK_INTEGRATION.md`.

