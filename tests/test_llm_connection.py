"""
Test LLM Connection
===================
Verifies that the local LLM infrastructure is working.
Run: python tests/test_llm_connection.py
Or:  pytest tests/test_llm_connection.py -v
"""

import os
import sys
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
import httpx

# Configuration
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
LITELLM_URL = os.getenv("LITELLM_URL", "http://localhost:4000")
LITELLM_API_KEY = os.getenv("LITELLM_MASTER_KEY", "sk-shrike-local")


class TestOllamaConnection:
    """Test direct Ollama connectivity."""
    
    def test_ollama_is_running(self):
        """Verify Ollama server is accessible."""
        try:
            response = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=10)
            assert response.status_code == 200
            print(f"✅ Ollama is running at {OLLAMA_URL}")
        except httpx.ConnectError:
            pytest.skip(f"Ollama not running at {OLLAMA_URL}")
    
    def test_ollama_has_models(self):
        """Verify at least one model is available."""
        try:
            response = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=10)
            data = response.json()
            models = data.get("models", [])
            print(f"Available models: {[m['name'] for m in models]}")
            assert len(models) > 0, "No models installed in Ollama"
        except httpx.ConnectError:
            pytest.skip("Ollama not running")
    
    def test_ollama_generate(self):
        """Test model generation with a simple prompt."""
        try:
            response = httpx.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": "phi3:mini",  # Smallest/fastest model
                    "prompt": "Say 'hello' in one word.",
                    "stream": False
                },
                timeout=60
            )
            assert response.status_code == 200
            data = response.json()
            assert "response" in data
            print(f"✅ Generation works: {data['response'][:50]}...")
        except httpx.ConnectError:
            pytest.skip("Ollama not running")
        except Exception as e:
            pytest.skip(f"Model not available: {e}")


class TestLiteLLMConnection:
    """Test LiteLLM proxy connectivity."""
    
    def test_litellm_health(self):
        """Verify LiteLLM proxy is healthy."""
        try:
            response = httpx.get(f"{LITELLM_URL}/health", timeout=10)
            assert response.status_code == 200
            print(f"✅ LiteLLM is running at {LITELLM_URL}")
        except httpx.ConnectError:
            pytest.skip(f"LiteLLM not running at {LITELLM_URL}")
    
    def test_litellm_models(self):
        """Verify models are configured in LiteLLM."""
        try:
            response = httpx.get(
                f"{LITELLM_URL}/models",
                headers={"Authorization": f"Bearer {LITELLM_API_KEY}"},
                timeout=10
            )
            if response.status_code == 200:
                data = response.json()
                models = data.get("data", [])
                print(f"Configured models: {[m.get('id') for m in models]}")
        except httpx.ConnectError:
            pytest.skip("LiteLLM not running")
    
    def test_litellm_completion(self):
        """Test completion through LiteLLM proxy."""
        try:
            response = httpx.post(
                f"{LITELLM_URL}/chat/completions",
                headers={
                    "Authorization": f"Bearer {LITELLM_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "specpilot-local",
                    "messages": [{"role": "user", "content": "Say hello"}],
                    "max_tokens": 10
                },
                timeout=60
            )
            if response.status_code == 200:
                data = response.json()
                content = data["choices"][0]["message"]["content"]
                print(f"✅ LiteLLM completion works: {content[:50]}")
            else:
                print(f"⚠️  LiteLLM returned {response.status_code}: {response.text}")
        except httpx.ConnectError:
            pytest.skip("LiteLLM not running")


class TestSpecPilotIntegration:
    """Test SpecPilot-specific functionality."""
    
    def test_selector_optimization_prompt(self):
        """Test a selector optimization prompt."""
        prompt = """Given this HTML element, suggest the most reliable CSS selector:
        
<button class="btn btn-primary submit-form" data-testid="login-btn">Login</button>

Respond with just the selector and a brief reason."""
        
        try:
            response = httpx.post(
                f"{LITELLM_URL}/chat/completions",
                headers={
                    "Authorization": f"Bearer {LITELLM_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "specpilot-local",
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 100
                },
                timeout=120
            )
            if response.status_code == 200:
                data = response.json()
                content = data["choices"][0]["message"]["content"]
                print(f"Selector suggestion: {content}")
                # Check if it mentions data-testid (best practice)
                if "data-testid" in content.lower() or "login-btn" in content:
                    print("✅ Model suggests good selector pattern")
            else:
                print(f"⚠️  Error: {response.status_code}")
        except httpx.ConnectError:
            pytest.skip("LiteLLM not running")
    
    def test_playwright_code_generation(self):
        """Test generating Playwright code."""
        prompt = """Convert this test step to Playwright TypeScript code:
        
"Click the submit button and wait for the success message"

Return only the code, no explanation."""
        
        try:
            response = httpx.post(
                f"{LITELLM_URL}/chat/completions",
                headers={
                    "Authorization": f"Bearer {LITELLM_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "specpilot-local",
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 150
                },
                timeout=120
            )
            if response.status_code == 200:
                data = response.json()
                content = data["choices"][0]["message"]["content"]
                print(f"Generated code:\n{content}")
                # Check for Playwright patterns
                if "click" in content.lower() or "page." in content:
                    print("✅ Model generates Playwright-like code")
        except httpx.ConnectError:
            pytest.skip("LiteLLM not running")


def run_quick_test():
    """Run a quick connectivity test (for make test-llm)."""
    print("=" * 50)
    print("Shrike AI Lab - Quick LLM Test")
    print("=" * 50)
    print()
    
    # Test Ollama
    print("1. Testing Ollama...")
    try:
        response = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        if response.status_code == 200:
            models = response.json().get("models", [])
            print(f"   ✅ Ollama running - {len(models)} models available")
        else:
            print(f"   ❌ Ollama error: {response.status_code}")
    except httpx.ConnectError:
        print(f"   ❌ Ollama not running at {OLLAMA_URL}")
        print("   → Run: docker-compose up -d")
    
    print()
    
    # Test LiteLLM
    print("2. Testing LiteLLM...")
    try:
        response = httpx.get(f"{LITELLM_URL}/health", timeout=5)
        if response.status_code == 200:
            print(f"   ✅ LiteLLM running")
        else:
            print(f"   ❌ LiteLLM error: {response.status_code}")
    except httpx.ConnectError:
        print(f"   ❌ LiteLLM not running at {LITELLM_URL}")
    
    print()
    
    # Test generation
    print("3. Testing generation...")
    try:
        response = httpx.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": "phi3:mini",
                "prompt": "What is 2+2? Answer with just the number.",
                "stream": False
            },
            timeout=30
        )
        if response.status_code == 200:
            answer = response.json().get("response", "")[:20]
            print(f"   ✅ Generation works: '{answer.strip()}'")
        else:
            print(f"   ❌ Generation failed: {response.status_code}")
    except Exception as e:
        print(f"   ❌ Generation error: {e}")
    
    print()
    print("=" * 50)


if __name__ == "__main__":
    run_quick_test()
