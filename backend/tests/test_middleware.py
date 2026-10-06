"""
Security middleware tests.

Run with:
    cd backend && pytest tests/test_middleware.py -v
"""
import pytest
from fastapi import FastAPI, Request
from httpx import AsyncClient, ASGITransport


@pytest.fixture
async def client():
    from app.core.middleware import security_middleware

    app = FastAPI()
    app.middleware("http")(security_middleware)

    @app.post("/echo")
    async def echo(request: Request):
        return {"size": len(await request.body())}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


class TestSecurityMiddleware:
    async def test_binary_upload_with_traversal_bytes_is_accepted(self, client):
        # Regression: image bytes were scanned as text, and any "../" sequence
        # in compressed data got the upload rejected at random
        image = b"\xff\xd8\xff\xe0" + b"\x00\x13../\x9a\x7f" + b"\x00" * 64
        resp = await client.post("/echo", files={"photo": ("p.jpg", image, "image/jpeg")})
        assert resp.status_code == 200

    async def test_json_with_script_tag_still_rejected(self, client):
        resp = await client.post("/echo", json={"notes": "<script>alert(1)</script>"})
        assert resp.status_code == 400
        assert resp.json()["detail"]["code"] == "INVALID_REQUEST"

    async def test_clean_json_passes(self, client):
        resp = await client.post("/echo", json={"notes": "Leave at the gate"})
        assert resp.status_code == 200
