#!/usr/bin/env python3
"""Verify local LiteLLM/Ollama setup for Cline usage."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

import requests


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify Cline local model connectivity")
    parser.add_argument("--litellm-url", default="http://localhost:4000", help="LiteLLM base URL")
    parser.add_argument("--ollama-url", default="http://localhost:11434", help="Ollama base URL")
    parser.add_argument("--api-key", default="sk-shrike-local", help="LiteLLM bearer key")
    parser.add_argument(
        "--models",
        default="mistral-local,phi3-local",
        help="Comma-separated model aliases to test via LiteLLM",
    )
    parser.add_argument("--timeout", type=float, default=20.0, help="HTTP timeout seconds")
    return parser.parse_args()


def _ok(label: str, detail: str) -> None:
    print(f"[OK] {label}: {detail}")


def _fail(label: str, detail: str) -> None:
    print(f"[FAIL] {label}: {detail}")


def _request_json(method: str, url: str, timeout: float, **kwargs: Any) -> tuple[int, Any]:
    response = requests.request(method, url, timeout=timeout, **kwargs)
    payload = None
    if response.text.strip():
        try:
            payload = response.json()
        except json.JSONDecodeError:
            payload = response.text[:300]
    return response.status_code, payload


def main() -> int:
    args = parse_args()
    headers = {"Authorization": f"Bearer {args.api_key}"}
    failures = 0

    # 1) Ollama health-ish check via tags endpoint.
    try:
        status, payload = _request_json("GET", f"{args.ollama_url}/api/tags", timeout=args.timeout)
        if status == 200:
            models = [m.get("name", "") for m in (payload or {}).get("models", [])]
            _ok("Ollama", f"reachable; models={models[:8]}")
        else:
            failures += 1
            _fail("Ollama", f"unexpected status {status}")
    except Exception as exc:  # pragma: no cover - defensive connectivity handling
        failures += 1
        _fail("Ollama", str(exc))

    # 2) LiteLLM health with auth.
    try:
        status, payload = _request_json(
            "GET",
            f"{args.litellm_url}/health",
            headers=headers,
            timeout=args.timeout,
        )
        if status == 200:
            healthy = (payload or {}).get("healthy_endpoints", [])
            _ok("LiteLLM health", f"reachable; healthy_endpoints={len(healthy)}")
        else:
            failures += 1
            _fail("LiteLLM health", f"unexpected status {status} payload={payload}")
    except Exception as exc:  # pragma: no cover
        failures += 1
        _fail("LiteLLM health", str(exc))

    # 3) Available models.
    model_ids: list[str] = []
    try:
        status, payload = _request_json(
            "GET",
            f"{args.litellm_url}/v1/models",
            headers=headers,
            timeout=args.timeout,
        )
        if status == 200:
            model_ids = [m.get("id", "") for m in (payload or {}).get("data", []) if isinstance(m, dict)]
            _ok("LiteLLM models", ", ".join(model_ids))
        else:
            failures += 1
            _fail("LiteLLM models", f"unexpected status {status} payload={payload}")
    except Exception as exc:  # pragma: no cover
        failures += 1
        _fail("LiteLLM models", str(exc))

    # 4) Chat completion smoke checks for requested models.
    requested = [m.strip() for m in args.models.split(",") if m.strip()]
    for model in requested:
        if model_ids and model not in model_ids:
            failures += 1
            _fail("Model present", f"{model} not in LiteLLM model list")
            continue
        try:
            status, payload = _request_json(
                "POST",
                f"{args.litellm_url}/v1/chat/completions",
                headers={**headers, "Content-Type": "application/json"},
                json={
                    "model": model,
                    "messages": [{"role": "user", "content": "Reply with only: OK"}],
                    "max_tokens": 10,
                    "temperature": 0,
                },
                timeout=args.timeout,
            )
            if status == 200:
                content = ""
                try:
                    content = payload["choices"][0]["message"]["content"]
                except Exception:
                    content = str(payload)[:120]
                _ok(f"Completion {model}", content.strip().replace("\n", " ")[:80])
            else:
                failures += 1
                _fail(f"Completion {model}", f"unexpected status {status} payload={payload}")
        except Exception as exc:  # pragma: no cover
            failures += 1
            _fail(f"Completion {model}", str(exc))

    print("\nSummary:")
    if failures:
        print(f"  {failures} check(s) failed.")
        return 1
    print("  All checks passed. Cline can use local models via LiteLLM.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
