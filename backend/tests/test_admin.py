"""
Admin approval tests — shops and riders.

Run with:
    cd backend && pytest tests/test_admin.py -v
"""
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4
from httpx import AsyncClient, ASGITransport


def _repo(**methods):
    r = MagicMock()
    for name, value in methods.items():
        setattr(r, name, AsyncMock(return_value=value))
    return r


def _db():
    db = MagicMock()
    db.flush = AsyncMock()
    return db


def _courier(status, doc_types=()):
    from app.models.courier import CourierStatus, DocumentType
    docs = [MagicMock(doc_type=DocumentType(t), is_verified=False) for t in doc_types]
    return MagicMock(id=uuid4(), status=CourierStatus(status), documents=docs,
                     documents_verified_at=None, rejection_reason=None)


ALL_DOCS = ["national_id_front", "national_id_back", "driving_license",
            "vehicle_photo", "selfie_with_id"]


# ── Only admins get in ────────────────────────────────────────────────────────
class TestAdminAccess:
    @pytest.fixture
    async def client_as(self):
        from app.main import app
        from app.auth.guards import get_current_user

        async def make(role):
            app.dependency_overrides[get_current_user] = lambda: {"sub": str(uuid4()), "role": role}
            return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")

        yield make
        app.dependency_overrides.clear()

    @pytest.mark.parametrize("role", ["customer", "merchant", "courier"])
    @pytest.mark.parametrize("method,path", [
        ("get", "/admin/merchants"),
        ("post", f"/admin/merchants/{uuid4()}/approve"),
        ("get", "/admin/couriers"),
        ("post", f"/admin/couriers/{uuid4()}/approve"),
        ("get", f"/admin/couriers/{uuid4()}/documents/selfie_with_id"),
    ])
    async def test_non_admin_forbidden(self, client_as, role, method, path):
        async with await client_as(role) as c:
            resp = await getattr(c, method)(path)
        assert resp.status_code == 403
        assert resp.json()["detail"]["code"] == "INSUFFICIENT_ROLE"

    async def test_malformed_id_is_422_not_500(self, client_as):
        async with await client_as("admin") as c:
            resp = await c.post("/admin/couriers/not-a-uuid/approve")
        assert resp.status_code == 422


# ── Shops ─────────────────────────────────────────────────────────────────────
class TestMerchantApproval:
    async def _call(self, fn, merchant, *args):
        from app.admin import service
        repo = _repo(get_or_404=merchant, update=merchant)
        with patch("app.admin.service.MerchantRepo", return_value=repo):
            await getattr(service, fn)(str(merchant.id), *args, "admin-1", _db())
        return repo

    async def test_approve_pending_shop(self):
        from app.models.merchant import MerchantStatus
        merchant = MagicMock(id=uuid4(), status=MerchantStatus.pending_review)
        repo = await self._call("approve_merchant", merchant)
        assert repo.update.await_args.kwargs == {"status": MerchantStatus.active}

    async def test_cannot_approve_deactivated_shop(self):
        from app.models.merchant import MerchantStatus
        from app.core.exceptions import SokoFetchException
        merchant = MagicMock(id=uuid4(), status=MerchantStatus.deactivated)
        with pytest.raises(SokoFetchException) as exc:
            await self._call("approve_merchant", merchant)
        assert exc.value.detail["code"] == "INVALID_STATE"

    async def test_reject_pending_shop(self):
        from app.models.merchant import MerchantStatus
        merchant = MagicMock(id=uuid4(), status=MerchantStatus.pending_review)
        repo = await self._call("reject_merchant", merchant, "Blurry business permit")
        assert repo.update.await_args.kwargs == {"status": MerchantStatus.deactivated}

    async def test_cannot_reject_live_shop(self):
        from app.models.merchant import MerchantStatus
        from app.core.exceptions import SokoFetchException
        merchant = MagicMock(id=uuid4(), status=MerchantStatus.active)
        with pytest.raises(SokoFetchException):
            await self._call("reject_merchant", merchant, "reason")


# ── Riders ────────────────────────────────────────────────────────────────────
class TestCourierApproval:
    async def _call(self, fn, courier, *args):
        from app.admin import service
        with patch("app.admin.service.get_courier", new=AsyncMock(return_value=courier)):
            return await getattr(service, fn)(str(courier.id), *args, "admin-1", _db())

    async def test_approve_with_all_documents(self):
        from app.models.courier import CourierStatus
        courier = _courier("documents_submitted", ALL_DOCS)
        await self._call("approve_courier", courier)
        assert courier.status == CourierStatus.active
        assert courier.documents_verified_at is not None
        assert all(d.is_verified and d.verified_by == "admin-1" for d in courier.documents)

    async def test_approved_rider_is_dispatchable_once_online(self):
        from app.models.courier import Courier, CourierStatus, DocumentType
        courier = Courier(status=CourierStatus.documents_submitted, is_online=True)
        courier.documents = [MagicMock(doc_type=DocumentType(t)) for t in ALL_DOCS]
        await self._call("approve_courier", courier)
        assert courier.is_dispatchable is True

    async def test_approve_refused_with_missing_documents(self):
        from app.core.exceptions import SokoFetchException
        from app.models.courier import CourierStatus
        courier = _courier("documents_submitted", ALL_DOCS[:3])
        with pytest.raises(SokoFetchException) as exc:
            await self._call("approve_courier", courier)
        assert exc.value.detail["code"] == "DOCUMENTS_MISSING"
        assert "selfie_with_id" in exc.value.detail["message"]
        assert courier.status == CourierStatus.documents_submitted

    async def test_cannot_approve_deactivated_rider(self):
        from app.core.exceptions import SokoFetchException
        courier = _courier("deactivated", ALL_DOCS)
        with pytest.raises(SokoFetchException) as exc:
            await self._call("approve_courier", courier)
        assert exc.value.detail["code"] == "INVALID_STATE"

    async def test_reject_records_reason(self):
        from app.models.courier import CourierStatus
        courier = _courier("documents_submitted", ALL_DOCS)
        await self._call("reject_courier", courier, "ID photo unreadable")
        assert courier.status == CourierStatus.rejected
        assert courier.rejection_reason == "ID photo unreadable"


# ── Rider documents ───────────────────────────────────────────────────────────
class TestCourierDocument:
    def _db_with_doc(self, doc):
        result = MagicMock()
        result.scalar_one_or_none.return_value = doc
        db = MagicMock()
        db.execute = AsyncMock(return_value=result)
        return db

    async def test_returns_decrypted_image(self):
        from app.admin import service
        from app.core.encryption import encrypt_document
        jpeg = b"\xff\xd8\xff\xe0" + b"photo-bytes"
        doc = MagicMock(s3_key="courier-docs/x/selfie_with_id/abc")
        with patch("app.admin.service._download", return_value=encrypt_document(jpeg)):
            data, content_type = await service.get_courier_document(
                str(uuid4()), "selfie_with_id", self._db_with_doc(doc))
        assert data == jpeg
        assert content_type == "image/jpeg"

    async def test_unknown_doc_type_is_404(self):
        from app.admin import service
        from app.core.exceptions import NotFoundError
        with pytest.raises(NotFoundError):
            await service.get_courier_document(str(uuid4()), "passport", MagicMock())

    async def test_missing_document_is_404(self):
        from app.admin import service
        from app.core.exceptions import NotFoundError
        with pytest.raises(NotFoundError):
            await service.get_courier_document(str(uuid4()), "selfie_with_id", self._db_with_doc(None))
