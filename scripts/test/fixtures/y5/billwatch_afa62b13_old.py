"""Tests for SecurityHeadersMiddleware."""
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.security_headers import SecurityHeadersMiddleware


def _make_app() -> FastAPI:
    """Build a minimal FastAPI app with SecurityHeadersMiddleware for testing."""
    test_app = FastAPI()
    test_app.add_middleware(SecurityHeadersMiddleware)

    @test_app.get("/ok")
    async def ok():
        return {"status": "ok"}

    @test_app.get("/custom-frame")
    async def custom_frame():
        from fastapi.responses import JSONResponse
        resp = JSONResponse({"status": "custom"})
        resp.headers["X-Frame-Options"] = "SAMEORIGIN"
        return resp

    @test_app.get("/error")
    async def error():
        raise ValueError("boom")

    return test_app


class TestSecurityHeadersMiddleware:
    """Verify that SecurityHeadersMiddleware sets baseline headers correctly."""

    def test_headers_present_on_200(self):
        app = _make_app()
        client = TestClient(app)
        resp = client.get("/ok")
        assert resp.status_code == 200
        assert resp.headers["X-Content-Type-Options"] == "nosniff"
        assert resp.headers["X-Frame-Options"] == "DENY"
        assert resp.headers["Permissions-Policy"] == "geolocation=(), microphone=(), camera=()"
        assert resp.headers["Referrer-Policy"] == "no-referrer"

    def test_headers_present_on_404(self):
        app = _make_app()
        client = TestClient(app)
        resp = client.get("/nonexistent")
        assert resp.status_code == 404
        assert resp.headers["X-Content-Type-Options"] == "nosniff"
        assert resp.headers["X-Frame-Options"] == "DENY"
        assert resp.headers["Permissions-Policy"] == "geolocation=(), microphone=(), camera=()"
        assert resp.headers["Referrer-Policy"] == "no-referrer"

    def test_headers_present_on_500(self):
        app = _make_app()
        client = TestClient(app, raise_server_exceptions=False)
        resp = client.get("/error")
        assert resp.status_code == 500
        assert resp.headers["X-Content-Type-Options"] == "nosniff"
        assert resp.headers["X-Frame-Options"] == "DENY"
        assert resp.headers["Permissions-Policy"] == "geolocation=(), microphone=(), camera=()"
        assert resp.headers["Referrer-Policy"] == "no-referrer"

    def test_handler_set_x_frame_options_preserved(self):
        """If a handler explicitly sets X-Frame-Options, the middleware must not override it."""
        app = _make_app()
        client = TestClient(app)
        resp = client.get("/custom-frame")
        assert resp.status_code == 200
        # The handler set SAMEORIGIN; middleware should NOT overwrite it
        assert resp.headers["X-Frame-Options"] == "SAMEORIGIN"
        # Other headers should still be added by the middleware
        assert resp.headers["X-Content-Type-Options"] == "nosniff"
        assert resp.headers["Referrer-Policy"] == "no-referrer"

    def test_does_not_duplicate_existing_headers(self):
        """Middleware should not add a header if it's already present."""
        app = _make_app()
        client = TestClient(app)
        resp = client.get("/custom-frame")
        # X-Frame-Options was set by handler, so middleware skipped it.
        # Verify it appears exactly once (no duplication).
        xfo_values = resp.headers.getlist("X-Frame-Options")
        assert len(xfo_values) == 1
        assert xfo_values[0] == "SAMEORIGIN"
