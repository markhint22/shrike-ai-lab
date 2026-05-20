#!/usr/bin/env python3
"""
GitLark Training Data Collector

Extracts training examples from local repositories:
- Code snippets with explanations from docstrings
- Git commit history for commit message training
- PR descriptions from GitHub
"""

import os
import json
import argparse
import subprocess
from pathlib import Path
from typing import List, Dict, Any


def extract_functions_with_docstrings(file_path: Path) -> List[Dict[str, Any]]:
    """Extract functions/methods with docstrings for code explanation training."""
    examples = []
    
    # Determine language from extension
    ext = file_path.suffix.lower()
    language_map = {
        '.py': 'python',
        '.ts': 'typescript',
        '.tsx': 'typescript',
        '.js': 'javascript',
        '.jsx': 'javascript',
        '.swift': 'swift',
        '.kt': 'kotlin',
        '.go': 'go',
        '.rs': 'rust',
    }
    
    language = language_map.get(ext)
    if not language:
        return []
    
    content = file_path.read_text(encoding='utf-8', errors='ignore')
    
    # Simple heuristic extraction (for production, use AST parsing)
    if language == 'python':
        examples.extend(_extract_python_functions(content, language))
    elif language in ('typescript', 'javascript'):
        examples.extend(_extract_js_functions(content, language))
    
    return examples


def _extract_python_functions(content: str, language: str) -> List[Dict[str, Any]]:
    """Extract Python functions with docstrings."""
    import re
    examples = []
    
    # Match function definitions with docstrings
    pattern = r'((?:async\s+)?def\s+\w+[^:]+:)\s*\n\s*"""([^"]+)"""'
    
    for match in re.finditer(pattern, content):
        func_def = match.group(1)
        docstring = match.group(2).strip()
        
        # Get the full function body (simplified)
        start = match.start()
        lines = content[start:].split('\n')
        func_lines = [lines[0]]
        indent = len(lines[1]) - len(lines[1].lstrip()) if len(lines) > 1 else 4
        
        for line in lines[1:]:
            if line.strip() and not line.startswith(' ' * indent) and not line.strip().startswith('"""'):
                break
            func_lines.append(line)
        
        code = '\n'.join(func_lines[:20])  # Limit size
        
        if len(code) > 50 and len(docstring) > 20:
            examples.append({
                'code': code,
                'language': language,
                'explanation': docstring,
            })
    
    return examples


def _extract_js_functions(content: str, language: str) -> List[Dict[str, Any]]:
    """Extract JavaScript/TypeScript functions with JSDoc comments."""
    import re
    examples = []
    
    # Match JSDoc + function
    pattern = r'/\*\*\s*\n([^*]+(?:\*[^/][^*]*)*)\*/\s*\n\s*((?:export\s+)?(?:async\s+)?(?:function|const)\s+\w+[^{]+\{)'
    
    for match in re.finditer(pattern, content):
        jsdoc = match.group(1).strip()
        # Clean JSDoc asterisks
        jsdoc = re.sub(r'^\s*\*\s?', '', jsdoc, flags=re.MULTILINE).strip()
        
        func_start = match.group(2)
        start = match.start(2)
        
        # Get function body (simplified)
        brace_count = 1
        end = content.find('{', start) + 1
        while brace_count > 0 and end < len(content):
            if content[end] == '{':
                brace_count += 1
            elif content[end] == '}':
                brace_count -= 1
            end += 1
        
        code = content[start:min(end, start + 500)]
        
        if len(code) > 50 and len(jsdoc) > 20:
            examples.append({
                'code': code,
                'language': language,
                'explanation': jsdoc,
            })
    
    return examples


def extract_commits(repo_path: Path, limit: int = 100) -> List[Dict[str, str]]:
    """Extract commit messages with diffs for commit message training."""
    examples = []
    
    try:
        # Get recent commits
        result = subprocess.run(
            ['git', 'log', f'-{limit}', '--pretty=format:%H|%s'],
            cwd=repo_path,
            capture_output=True,
            text=True,
        )
        
        for line in result.stdout.strip().split('\n'):
            if '|' not in line:
                continue
            
            commit_hash, message = line.split('|', 1)
            
            # Skip merge commits and version bumps
            if message.startswith('Merge') or 'bump version' in message.lower():
                continue
            
            # Get diff (simplified - just files changed)
            diff_result = subprocess.run(
                ['git', 'show', '--stat', commit_hash, '--format='],
                cwd=repo_path,
                capture_output=True,
                text=True,
            )
            
            diff = diff_result.stdout.strip()
            
            if diff and len(message) > 10:
                examples.append({
                    'diff': diff[:500],  # Limit size
                    'commit_message': message,
                })
    
    except Exception as e:
        print(f"Error extracting commits from {repo_path}: {e}")
    
    return examples


def collect_from_repo(repo_path: Path, output_dir: Path):
    """Collect all training data from a repository."""
    print(f"Collecting from {repo_path}")
    
    # Code explanations
    code_examples = []
    for ext in ['.py', '.ts', '.tsx', '.js', '.swift', '.kt']:
        for file_path in repo_path.rglob(f'*{ext}'):
            # Skip node_modules, venv, etc.
            if any(skip in str(file_path) for skip in ['node_modules', 'venv', '.git', 'dist', 'build']):
                continue
            
            examples = extract_functions_with_docstrings(file_path)
            code_examples.extend(examples)
    
    if code_examples:
        output_file = output_dir / 'code_explanation_raw.jsonl'
        with open(output_file, 'a') as f:
            for example in code_examples:
                f.write(json.dumps(example) + '\n')
        print(f"  Wrote {len(code_examples)} code explanations")
    
    # Commit messages
    commit_examples = extract_commits(repo_path)
    if commit_examples:
        output_file = output_dir / 'commit_messages_raw.jsonl'
        with open(output_file, 'a') as f:
            for example in commit_examples:
                f.write(json.dumps(example) + '\n')
        print(f"  Wrote {len(commit_examples)} commit messages")


def main():
    parser = argparse.ArgumentParser(description="Collect GitLark training data")
    parser.add_argument("--repos", nargs='+', required=True, 
                       help="Paths to repositories to collect from")
    parser.add_argument("--output", required=True, help="Output directory")
    
    args = parser.parse_args()
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    for repo_path in args.repos:
        collect_from_repo(Path(repo_path).expanduser(), output_dir)
    
    print(f"\nData collected to {output_dir}")
    print("Review and clean the *_raw.jsonl files before training.")


if __name__ == "__main__":
    main()
