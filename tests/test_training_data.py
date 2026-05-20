"""
Test Training Data
==================
Validates training data format and content.
"""

import json
import pytest
from pathlib import Path

TRAINING_DATA_DIR = Path(__file__).parent.parent / "training" / "specpilot" / "data"


class TestTrainingDataFormat:
    """Test training data files are properly formatted."""
    
    def test_selector_optimization_format(self):
        """Validate selector_optimization.jsonl format."""
        data_file = TRAINING_DATA_DIR / "selector_optimization.jsonl"
        assert data_file.exists(), f"Missing {data_file}"
        
        with open(data_file) as f:
            for i, line in enumerate(f, 1):
                item = json.loads(line.strip())
                # Must have HTML
                assert "html" in item, f"Line {i}: missing 'html'"
                # Must have either good_selector or best_selector
                assert "good_selector" in item or "best_selector" in item, \
                    f"Line {i}: missing selector output"
        
        print(f"✅ selector_optimization.jsonl: {i} valid examples")
    
    def test_test_generation_format(self):
        """Validate test_generation.jsonl format."""
        data_file = TRAINING_DATA_DIR / "test_generation.jsonl"
        assert data_file.exists(), f"Missing {data_file}"
        
        with open(data_file) as f:
            for i, line in enumerate(f, 1):
                item = json.loads(line.strip())
                assert "instruction" in item, f"Line {i}: missing 'instruction'"
                assert "playwright_code" in item, f"Line {i}: missing 'playwright_code'"
        
        print(f"✅ test_generation.jsonl: {i} valid examples")
    
    def test_failure_analysis_format(self):
        """Validate failure_analysis.jsonl format."""
        data_file = TRAINING_DATA_DIR / "failure_analysis.jsonl"
        assert data_file.exists(), f"Missing {data_file}"
        
        with open(data_file) as f:
            for i, line in enumerate(f, 1):
                item = json.loads(line.strip())
                assert "error" in item, f"Line {i}: missing 'error'"
                assert "diagnosis" in item, f"Line {i}: missing 'diagnosis'"
        
        print(f"✅ failure_analysis.jsonl: {i} valid examples")


class TestTrainingDataQuality:
    """Test training data quality."""
    
    def test_selector_examples_use_best_practices(self):
        """Check that good selectors follow best practices."""
        data_file = TRAINING_DATA_DIR / "selector_optimization.jsonl"
        
        best_practice_patterns = [
            "data-testid",
            "data-test",
            ":has-text",
            "[role=",
            "aria-label",
        ]
        
        uses_best_practice = 0
        total = 0
        
        with open(data_file) as f:
            for line in f:
                item = json.loads(line.strip())
                total += 1
                selector = item.get("good_selector", item.get("best_selector", ""))
                if any(pattern in selector for pattern in best_practice_patterns):
                    uses_best_practice += 1
        
        ratio = uses_best_practice / total if total > 0 else 0
        print(f"Best practice usage: {uses_best_practice}/{total} ({ratio:.0%})")
        # At least 50% should use best practices
        assert ratio >= 0.5, "Training data should emphasize best practice selectors"
    
    def test_playwright_code_is_valid_syntax(self):
        """Check that generated Playwright code looks valid."""
        data_file = TRAINING_DATA_DIR / "test_generation.jsonl"
        
        playwright_patterns = [
            "await page.",
            "await expect(",
            ".click(",
            ".fill(",
            ".locator(",
        ]
        
        with open(data_file) as f:
            for i, line in enumerate(f, 1):
                item = json.loads(line.strip())
                code = item.get("playwright_code", "")
                has_playwright = any(p in code for p in playwright_patterns)
                assert has_playwright, f"Line {i}: doesn't look like Playwright code: {code[:50]}"
        
        print(f"✅ All {i} code examples contain valid Playwright patterns")


class TestTrainingDataCompleteness:
    """Test that training data covers key scenarios."""
    
    def test_has_minimum_examples(self):
        """Ensure each dataset has minimum examples."""
        min_examples = {
            "selector_optimization.jsonl": 3,
            "test_generation.jsonl": 5,
            "failure_analysis.jsonl": 3,
        }
        
        for filename, minimum in min_examples.items():
            data_file = TRAINING_DATA_DIR / filename
            with open(data_file) as f:
                count = sum(1 for _ in f)
            assert count >= minimum, f"{filename} has {count} examples, need at least {minimum}"
            print(f"✅ {filename}: {count} examples (min: {minimum})")
    
    def test_diverse_error_types(self):
        """Check failure analysis covers different error types."""
        data_file = TRAINING_DATA_DIR / "failure_analysis.jsonl"
        
        error_types_seen = set()
        with open(data_file) as f:
            for line in f:
                item = json.loads(line.strip())
                error = item.get("error", "")
                # Extract error type
                if "Timeout" in error:
                    error_types_seen.add("timeout")
                elif "not visible" in error.lower():
                    error_types_seen.add("visibility")
                elif "strict mode" in error.lower():
                    error_types_seen.add("ambiguous")
                elif "closed" in error.lower():
                    error_types_seen.add("navigation")
                elif "viewport" in error.lower():
                    error_types_seen.add("viewport")
        
        print(f"Error types covered: {error_types_seen}")
        assert len(error_types_seen) >= 3, "Should cover at least 3 different error types"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
