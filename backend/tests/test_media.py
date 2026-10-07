"""
Public shop and menu photos served at /media.

Run with:
    cd backend && pytest tests/test_media.py -v
"""
import pytest
from httpx import AsyncClient, ASGITransport


@pytest.fixture
async def client():
    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


class TestMedia:
    async def test_demo_photo_is_served(self, client):
        resp = await client.get("/media/demo/tomatoes.jpg")
        assert resp.status_code == 200
        assert resp.headers["content-type"] == "image/jpeg"
        assert resp.content[:2] == b"\xff\xd8"  # JPEG

    async def test_missing_photo_is_404(self, client):
        resp = await client.get("/media/demo/nope.jpg")
        assert resp.status_code == 404

    async def test_files_outside_the_media_folder_are_not_served(self, client):
        resp = await client.get("/media/%2e%2e/app/main.py")
        assert resp.status_code == 404
