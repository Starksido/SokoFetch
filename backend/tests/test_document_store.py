"""
Document store tests — the local folder used in development.

Run with:
    cd backend && pytest tests/test_document_store.py -v
"""
import pytest

from app.core import document_store
from app.core.config import settings
from app.core.document_store import DocumentStoreError


@pytest.fixture
def local_store(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "DOCUMENT_STORAGE", "local")
    monkeypatch.setattr(settings, "LOCAL_DOCUMENTS_DIR", str(tmp_path))
    return tmp_path


def test_put_then_get(local_store):
    document_store.put("courier-docs/c1/selfie_with_id/abc", b"encrypted")
    assert document_store.get("courier-docs/c1/selfie_with_id/abc") == b"encrypted"
    assert (local_store / "courier-docs" / "c1" / "selfie_with_id" / "abc").exists()


def test_missing_document_is_a_store_error(local_store):
    with pytest.raises(DocumentStoreError):
        document_store.get("courier-docs/nobody/selfie_with_id/x")


@pytest.mark.parametrize("key", ["../outside", "courier-docs/../../outside"])
def test_keys_cannot_leave_the_folder(local_store, key):
    with pytest.raises(DocumentStoreError):
        document_store.put(key, b"x")
    assert not (local_store.parent / "outside").exists()


async def test_admin_reads_what_the_courier_upload_stored(local_store):
    # End to end through the real helpers: encrypt, store, fetch, decrypt
    from unittest.mock import AsyncMock, MagicMock
    from app.admin import service
    from app.core.encryption import encrypt_document

    png = b"\x89PNG\r\n\x1a\n" + b"pixels"
    document_store.put("courier-docs/c1/national_id_front/k", encrypt_document(png))

    result = MagicMock()
    result.scalar_one_or_none.return_value = MagicMock(s3_key="courier-docs/c1/national_id_front/k")
    db = MagicMock(execute=AsyncMock(return_value=result))

    data, content_type = await service.get_courier_document("c1", "national_id_front", db)
    assert data == png
    assert content_type == "image/png"
