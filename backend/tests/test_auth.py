"""
Auth test suite.

Run with:
    cd backend
    pytest tests/test_auth.py -v
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from httpx import AsyncClient, ASGITransport
from uuid import uuid4


# ── Fixtures ──────────────────────────────────────────────────────────────────
@pytest.fixture
def mock_redis():
    """In-memory fake Redis for tests."""
    store = {}

    redis = AsyncMock()

    async def get(key):
        return store.get(key)

    async def setex(key, ttl, value):
        store[key] = value

    async def delete(*keys):
        for k in keys:
            store.pop(k, None)

    async def incr(key):
        store[key] = int(store.get(key, 0)) + 1
        return store[key]

    async def expire(key, ttl):
        pass  # No-op for tests

    async def ttl(key):
        return 3600

    async def set_(key, value, nx=False, ex=None):
        if nx and key in store:
            return None
        store[key] = value
        return True

    class Pipeline:
        """MULTI/EXEC: queue commands, run them together on execute()."""
        def __init__(self):
            self.ops = []

        async def __aenter__(self):
            return self

        async def __aexit__(self, *exc):
            return False

        def get(self, key):
            self.ops.append(lambda: store.get(key))
            return self

        def delete(self, *keys):
            self.ops.append(lambda: sum(store.pop(k, None) is not None for k in keys))
            return self

        async def execute(self):
            return [op() for op in self.ops]

    redis.set = set_
    redis.pipeline = lambda transaction=True: Pipeline()
    redis.get = get
    redis.setex = setex
    redis.delete = delete
    redis.incr = incr
    redis.expire = expire
    redis.ttl = ttl
    return redis, store


@pytest.fixture
@pytest.mark.asyncio
async def client(mock_redis):
    """Test HTTP client with mocked dependencies."""
    redis_mock, store = mock_redis

    with patch("app.core.redis.redis_client", redis_mock):
        from app.main import app
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as c:
            yield c, store


# ── Phone validation tests ────────────────────────────────────────────────────
class TestPhoneValidation:
    def test_valid_kenyan_safaricom(self):
        from app.auth.otp import validate_phone
        assert validate_phone("0712345678") == "+254712345678"

    def test_valid_with_country_code(self):
        from app.auth.otp import validate_phone
        assert validate_phone("+254712345678") == "+254712345678"

    def test_valid_airtel(self):
        from app.auth.otp import validate_phone
        assert validate_phone("0712345678") == "+254712345678"

    def test_invalid_short_number(self):
        from app.auth.otp import validate_phone
        from app.core.exceptions import InvalidPhoneError
        with pytest.raises(InvalidPhoneError):
            validate_phone("071234")

    def test_invalid_non_kenyan(self):
        from app.auth.otp import validate_phone
        from app.core.exceptions import InvalidPhoneError
        with pytest.raises(InvalidPhoneError):
            validate_phone("+12025551234")


# ── OTP generation and verification tests ─────────────────────────────────────
class TestOTP:
    @pytest.mark.asyncio
    async def test_generate_stores_in_redis(self, mock_redis):
        redis, store = mock_redis
        from app.auth.otp import generate_otp
        code = await generate_otp("+254712345678", redis)
        assert len(code) == 6
        assert code.isdigit()
        # Should be stored in Redis
        assert any(k.startswith("otp:") for k in store)

    @pytest.mark.asyncio
    async def test_verify_correct_code(self, mock_redis):
        redis, store = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        code = await generate_otp("+254712345678", redis)
        result = await verify_otp("+254712345678", code, redis)
        assert result is True

    @pytest.mark.asyncio
    async def test_verify_wrong_code_raises(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        from app.core.exceptions import InvalidOTPError
        await generate_otp("+254712345678", redis)
        with pytest.raises(InvalidOTPError):
            await verify_otp("+254712345678", "000000", redis)

    @pytest.mark.asyncio
    async def test_otp_single_use(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        from app.core.exceptions import InvalidOTPError
        code = await generate_otp("+254712345678", redis)
        await verify_otp("+254712345678", code, redis)  # First use — OK
        with pytest.raises(InvalidOTPError):
            await verify_otp("+254712345678", code, redis)  # Second use — fails

    @pytest.mark.asyncio
    async def test_code_burned_after_max_wrong_attempts(self, mock_redis):
        # Regression: verify had no attempt limit, so 6-digit codes were brute-forceable
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        from app.core.exceptions import InvalidOTPError, RateLimitError
        code = await generate_otp("+254712345678", redis)
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(4):
            with pytest.raises(InvalidOTPError):
                await verify_otp("+254712345678", wrong, redis)
        with pytest.raises(RateLimitError):
            await verify_otp("+254712345678", wrong, redis)
        # The real code no longer works — a new one must be requested
        with pytest.raises(InvalidOTPError):
            await verify_otp("+254712345678", code, redis)

    async def test_new_code_resets_wrong_attempts(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        from app.core.exceptions import InvalidOTPError
        code = await generate_otp("+254712345678", redis)
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(4):
            with pytest.raises(InvalidOTPError):
                await verify_otp("+254712345678", wrong, redis)
        code = await generate_otp("+254712345678", redis)
        assert await verify_otp("+254712345678", code, redis) is True

    async def test_rate_limit_exceeded(self, mock_redis):
        redis, store = mock_redis
        from app.auth.otp import check_rate_limit
        from app.core.exceptions import RateLimitError

        # Simulate 5 previous attempts
        phone_hash = __import__("hashlib").sha256(b"+254712345678").hexdigest()[:32]
        store[f"otp_rate:{phone_hash}"] = "5"

        with pytest.raises(RateLimitError):
            await check_rate_limit("+254712345678", redis)


# ── JWT tests ─────────────────────────────────────────────────────────────────
class TestJWT:
    def test_create_access_token(self):
        from app.auth.jwt import create_access_token
        token = create_access_token("user-123", "customer")
        assert isinstance(token, str)
        assert len(token) > 0

    def test_create_refresh_token(self):
        from app.auth.jwt import create_refresh_token
        token = create_refresh_token("user-123", "merchant")
        assert isinstance(token, str)

    @pytest.mark.asyncio
    async def test_decode_valid_token(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import create_access_token, decode_token
        token = create_access_token("user-123", "customer")
        payload = await decode_token(token, redis, "access")
        assert payload["sub"] == "user-123"
        assert payload["role"] == "customer"

    @pytest.mark.asyncio
    async def test_decode_wrong_type_fails(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import create_refresh_token, decode_token
        from app.core.exceptions import InvalidTokenError
        token = create_refresh_token("user-123", "customer")
        with pytest.raises(InvalidTokenError):
            await decode_token(token, redis, expected_type="access")

    @pytest.mark.asyncio
    async def test_revoked_token_rejected(self, mock_redis):
        redis, store = mock_redis
        from app.auth.jwt import create_access_token, decode_token, revoke_token
        from app.core.exceptions import RevokedTokenError

        token = create_access_token("user-123", "customer")
        await revoke_token(token, redis)

        with pytest.raises(RevokedTokenError):
            await decode_token(token, redis, "access")

    def test_invalid_role_raises(self):
        from app.auth.jwt import create_access_token
        with pytest.raises(ValueError):
            create_access_token("user-123", "hacker")


# ── API endpoint integration tests ────────────────────────────────────────────
class TestAuthEndpoints:
    @pytest.mark.asyncio
    async def test_health_check(self, client):
        c, _ = client
        resp = await c.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    @pytest.mark.asyncio
    async def test_otp_request_invalid_phone(self, client):
        c, _ = client
        with patch("app.auth.service.send_otp_sms", new_callable=AsyncMock) as mock_sms:
            resp = await c.post("/auth/otp/request", json={
                "phone": "not-a-phone",
                "role": "customer",
            })
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_otp_verify_invalid_role(self, client):
        c, _ = client
        resp = await c.post("/auth/otp/verify", json={
            "phone": "0712345678",
            "otp_code": "123456",
            "role": "superuser",   # Invalid
        })
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_otp_verify_wrong_code(self, client):
        c, _ = client
        with patch("app.auth.service.send_otp_sms", new_callable=AsyncMock):
            await c.post("/auth/otp/request", json={
                "phone": "0712345678",
                "role": "customer",
            })
        resp = await c.post("/auth/otp/verify", json={
            "phone": "0712345678",
            "otp_code": "000000",
            "role": "customer",
        })
        assert resp.status_code == 400
        assert resp.json()["detail"]["code"] == "INVALID_OTP"

    @pytest.mark.asyncio
    async def test_me_without_token(self, client):
        c, _ = client
        resp = await c.get("/auth/me")
        assert resp.status_code == 403   # HTTPBearer returns 403 when no token


# ── Refresh-token rotation and disabled accounts ─────────────────────────────
def _user(role="customer", is_active=True):
    from app.models.user import UserRole
    return MagicMock(id=uuid4(), role=UserRole(role), is_active=is_active)


def _db_with_user(user):
    db = MagicMock()
    db.get = AsyncMock(return_value=user)
    return db


def _db_returning(value):
    result = MagicMock()
    result.scalar_one_or_none.return_value = value
    db = MagicMock()
    db.execute = AsyncMock(return_value=result)
    db.flush = AsyncMock()
    return db


def _bearer(user_id: str, role: str = "customer"):
    from fastapi.security import HTTPAuthorizationCredentials
    from app.auth.jwt import create_access_token
    return HTTPAuthorizationCredentials(
        scheme="Bearer", credentials=create_access_token(user_id, role),
    )


class TestRefreshRotation:
    async def test_refresh_returns_new_pair(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import create_refresh_token
        from app.auth.service import refresh_access_token
        user = _user()
        old = create_refresh_token(str(user.id), "customer")
        tokens = await refresh_access_token(old, _db_with_user(user), redis)
        assert tokens["refresh_token"] != old
        assert tokens["access_token"]

    async def test_refresh_token_is_single_use(self, mock_redis):
        # Regression: one refresh token could mint new pairs for 30 days
        redis, _ = mock_redis
        from app.auth.jwt import create_refresh_token
        from app.auth.service import refresh_access_token
        from app.core.exceptions import RevokedTokenError
        user = _user()
        db = _db_with_user(user)
        old = create_refresh_token(str(user.id), "customer")
        await refresh_access_token(old, db, redis)
        with pytest.raises(RevokedTokenError):
            await refresh_access_token(old, db, redis)

    async def test_reuse_revokes_whole_session(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import create_refresh_token, decode_token
        from app.auth.service import refresh_access_token
        from app.core.exceptions import RevokedTokenError
        user = _user()
        db = _db_with_user(user)
        old = create_refresh_token(str(user.id), "customer")
        new = await refresh_access_token(old, db, redis)
        with pytest.raises(RevokedTokenError):
            await refresh_access_token(old, db, redis)   # Replay detected
        # The pair issued by the first refresh is dead too
        with pytest.raises(RevokedTokenError):
            await decode_token(new["access_token"], redis, "access")
        with pytest.raises(RevokedTokenError):
            await refresh_access_token(new["refresh_token"], db, redis)

    async def test_role_comes_from_database(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import create_refresh_token, decode_token
        from app.auth.service import refresh_access_token
        user = _user(role="merchant")
        old = create_refresh_token(str(user.id), "customer")
        tokens = await refresh_access_token(old, _db_with_user(user), redis)
        payload = await decode_token(tokens["access_token"], redis, "access")
        assert payload["role"] == "merchant"

    async def test_refresh_blocked_for_disabled_user(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import create_refresh_token
        from app.auth.service import refresh_access_token
        from app.core.exceptions import AccountDisabledError
        user = _user(is_active=False)
        old = create_refresh_token(str(user.id), "customer")
        with pytest.raises(AccountDisabledError):
            await refresh_access_token(old, _db_with_user(user), redis)

    async def test_refresh_rejected_for_deleted_user(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import create_refresh_token
        from app.auth.service import refresh_access_token
        from app.core.exceptions import InvalidTokenError
        old = create_refresh_token(str(uuid4()), "customer")
        with pytest.raises(InvalidTokenError):
            await refresh_access_token(old, _db_with_user(None), redis)


class TestDisabledAccounts:
    async def test_otp_login_blocked_for_disabled_user(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.service import verify_and_authenticate
        from app.core.exceptions import AccountDisabledError
        db = _db_returning(_user(is_active=False))
        with patch("app.auth.service.verify_otp", new_callable=AsyncMock):
            with pytest.raises(AccountDisabledError):
                await verify_and_authenticate("+254712345678", "123456", "customer", db, redis)

    async def test_protected_route_blocked_for_disabled_user(self, mock_redis):
        # Regression: guards only checked the JWT, never users.is_active
        redis, _ = mock_redis
        from app.auth.guards import get_current_user
        from app.core.exceptions import AccountDisabledError
        with pytest.raises(AccountDisabledError):
            await get_current_user(_bearer(str(uuid4())), redis, _db_returning(False))

    async def test_protected_route_rejects_deleted_user(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.guards import get_current_user
        from app.core.exceptions import InvalidTokenError
        with pytest.raises(InvalidTokenError):
            await get_current_user(_bearer(str(uuid4())), redis, _db_returning(None))

    async def test_active_user_passes_guard(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.guards import get_current_user
        uid = str(uuid4())
        user = await get_current_user(_bearer(uid), redis, _db_returning(True))
        assert user["sub"] == uid


class TestLogout:
    async def test_logout_with_only_refresh_token(self, client):
        # Regression: logout needed a valid access token, so once it expired
        # the app could never revoke its refresh token
        c, store = client
        from app.auth.jwt import create_refresh_token
        refresh = create_refresh_token(str(uuid4()), "customer")
        resp = await c.post("/auth/logout", json={"refresh_token": refresh})
        assert resp.status_code == 200
        assert any(k.startswith("revoked_token:") for k in store)

    async def test_logout_without_any_token(self, client):
        c, _ = client
        resp = await c.post("/auth/logout")
        assert resp.status_code == 401




# ── Sign-up: the role is picked before the account exists ────────────────────
def _signup_db(existing=None):
    """Fake session: execute() finds `existing`; flush() fills in new users' ids."""
    from datetime import datetime, timezone
    added = []
    result = MagicMock()
    result.scalar_one_or_none.return_value = existing
    result.first.return_value = (existing.id,) if existing else None
    db = MagicMock()
    db.execute = AsyncMock(return_value=result)

    async def flush():
        for obj in added:
            obj.id = obj.id or uuid4()
            obj.created_at = obj.created_at or datetime.now(timezone.utc)

    db.add = MagicMock(side_effect=added.append)
    db.flush = AsyncMock(side_effect=flush)
    return db, added


class TestSignupFlow:
    PHONE = "+254712345678"

    async def _verify(self, mock_redis, db, role=None):
        redis, _ = mock_redis
        from app.auth.service import verify_and_authenticate
        with patch("app.auth.service.verify_otp", new_callable=AsyncMock):
            return await verify_and_authenticate(self.PHONE, "123456", role, db, redis)

    async def test_existing_user_logs_in_with_own_role(self, mock_redis):
        from app.models.user import UserRole
        user = _user(role="merchant")
        user.email, user.created_at = None, MagicMock(isoformat=lambda: "2026-10-01")
        db, _ = _signup_db(existing=user)
        resp = await self._verify(mock_redis, db)
        assert resp.user.role == "merchant"
        assert resp.user.is_new is False
        assert user.role == UserRole.merchant

    async def test_existing_user_with_other_role_rejected(self, mock_redis):
        from app.core.exceptions import InsufficientRoleError
        db, _ = _signup_db(existing=_user(role="customer"))
        with pytest.raises(InsufficientRoleError):
            await self._verify(mock_redis, db, role="courier")

    async def test_new_number_without_role_gets_signup_token(self, mock_redis):
        _, store = mock_redis
        db, added = _signup_db()
        resp = await self._verify(mock_redis, db)
        assert resp.needs_role is True
        assert added == []                               # No account yet
        assert f"signup:{resp.signup_token}" in store

    async def test_new_number_with_role_created_directly(self, mock_redis):
        db, added = _signup_db()
        resp = await self._verify(mock_redis, db, role="courier")
        assert resp.user.role == "courier" and resp.user.is_new is True
        assert len(added) == 1

    async def test_signup_creates_account_with_chosen_role(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.service import complete_signup
        db, added = _signup_db()
        pending = await self._verify(mock_redis, db)
        resp = await complete_signup(pending.signup_token, "merchant", db, redis)
        assert resp.user.role == "merchant"
        assert resp.user.phone == self.PHONE
        assert resp.user.is_new is True
        assert added[0].role.value == "merchant"

    async def test_signup_token_is_single_use(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.service import complete_signup
        from app.core.exceptions import SokoFetchException
        db, _ = _signup_db()
        pending = await self._verify(mock_redis, db)
        await complete_signup(pending.signup_token, "customer", db, redis)
        with pytest.raises(SokoFetchException) as exc:
            await complete_signup(pending.signup_token, "courier", db, redis)
        assert exc.value.detail["code"] == "INVALID_SIGNUP_TOKEN"

    async def test_signup_refused_if_account_appeared_meanwhile(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.service import complete_signup
        from app.core.exceptions import AlreadyExistsError
        db, _ = _signup_db()
        pending = await self._verify(mock_redis, db)
        db_now, _ = _signup_db(existing=_user())
        with pytest.raises(AlreadyExistsError):
            await complete_signup(pending.signup_token, "customer", db_now, redis)

    async def test_google_new_user_without_role_gets_signup_token(self, mock_redis):
        redis, store = mock_redis
        from app.auth.service import verify_google_and_authenticate, complete_signup
        db, added = _signup_db()
        idinfo = {"sub": "google-123", "email": "a@example.com"}
        with patch("google.oauth2.id_token.verify_oauth2_token", return_value=idinfo):
            pending = await verify_google_and_authenticate("tok", None, db, redis)
        assert pending.needs_role is True and added == []
        resp = await complete_signup(pending.signup_token, "courier", db, redis)
        assert resp.user.role == "courier"
        assert resp.user.email == "a@example.com"
        assert added[0].google_sub == "google-123"

    async def test_signup_cannot_choose_admin(self, client):
        c, _ = client
        resp = await c.post("/auth/signup", json={"signup_token": "x", "role": "admin"})
        assert resp.status_code == 422

    async def test_otp_not_tied_to_a_role(self, mock_redis):
        # The OTP proves the phone; the role is decided after verification
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        code = await generate_otp(self.PHONE, redis)
        assert await verify_otp(self.PHONE, code, redis) is True


# ── Admin panel login is separate from the public app ────────────────────────
def _admin(is_active=True):
    from datetime import datetime, timezone
    user = _user("admin", is_active)
    user.email = None
    user.created_at = datetime.now(timezone.utc)
    return user


class TestAdminLoginSeparation:
    PHONE = "+254746396717"

    async def test_public_otp_login_refuses_admins(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.service import verify_and_authenticate
        from app.core.exceptions import UseAdminPanelError
        with patch("app.auth.service.verify_otp", new_callable=AsyncMock):
            with pytest.raises(UseAdminPanelError):
                await verify_and_authenticate(self.PHONE, "123456", None, _db_returning(_admin()), redis)

    async def test_admin_code_only_sent_to_admins(self, mock_redis):
        redis, store = mock_redis
        from app.auth.service import request_admin_otp
        with patch("app.auth.service.send_otp_sms", new_callable=AsyncMock) as sms:
            not_admin = await request_admin_otp(self.PHONE, _db_returning(_user("merchant")), redis)
            nobody = await request_admin_otp(self.PHONE, _db_returning(None), redis)
            sms.assert_not_awaited()
            admin = await request_admin_otp(self.PHONE, _db_returning(_admin()), redis)
            sms.assert_awaited_once()
        # Same answer either way, so admin numbers can't be discovered
        assert not_admin == nobody == admin
        assert any(k.startswith("admin_otp:") for k in store)
        assert not any(k.startswith("otp:") for k in store)

    async def test_admin_login_issues_admin_panel_tokens(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import decode_token
        from app.auth.service import request_admin_otp, verify_admin_otp
        db = _db_returning(_admin())
        with patch("app.auth.service.send_otp_sms", new_callable=AsyncMock) as sms:
            await request_admin_otp(self.PHONE, db, redis)
        code = sms.await_args.args[1]
        tokens = await verify_admin_otp(self.PHONE, code, db, redis)
        payload = await decode_token(tokens.access_token, redis, "access")
        assert payload["client"] == "admin"
        assert payload["role"] == "admin"

    async def test_public_code_does_not_work_on_admin_login(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.otp import generate_otp
        from app.auth.service import verify_admin_otp
        from app.core.exceptions import InvalidOTPError
        code = await generate_otp(self.PHONE, redis)          # Public-app code
        with pytest.raises(InvalidOTPError):
            await verify_admin_otp(self.PHONE, code, _db_returning(_admin()), redis)

    async def test_admin_login_refuses_non_admins(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.otp import generate_otp
        from app.auth.service import verify_admin_otp
        from app.core.exceptions import InvalidOTPError
        code = await generate_otp(self.PHONE, redis, scope="admin_otp")
        with pytest.raises(InvalidOTPError):
            await verify_admin_otp(self.PHONE, code, _db_returning(_user("courier")), redis)

    async def test_refresh_stays_with_its_own_client(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.jwt import create_refresh_token
        from app.auth.service import refresh_access_token
        from app.core.exceptions import InvalidTokenError
        admin = _admin()
        db = _db_with_user(admin)
        panel_token = create_refresh_token(str(admin.id), "admin", "admin")
        with pytest.raises(InvalidTokenError):
            await refresh_access_token(panel_token, db, redis)            # Public refresh
        # Rejected before being claimed, so it still works where it belongs
        tokens = await refresh_access_token(panel_token, db, redis, client="admin")
        assert tokens["refresh_token"] != panel_token

    async def test_old_admin_session_on_the_phone_is_ended(self, mock_redis):
        # An admin logged in to the phone app before the split: its refresh
        # token has no client claim and must not keep working there
        redis, _ = mock_redis
        from jose import jwt
        from app.auth.jwt import create_refresh_token
        from app.auth.service import refresh_access_token
        from app.core.config import settings
        from app.core.exceptions import UseAdminPanelError
        admin = _admin()
        payload = jwt.decode(create_refresh_token(str(admin.id), "admin"),
                             settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
        payload.pop("client")
        legacy = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
        with pytest.raises(UseAdminPanelError):
            await refresh_access_token(legacy, _db_with_user(admin), redis)

    async def test_admin_login_routes_registered(self):
        from app.main import app
        paths = app.openapi()["paths"]
        for path in ("/admin/auth/otp/request", "/admin/auth/otp/verify",
                     "/admin/auth/token/refresh", "/admin/auth/logout"):
            assert "post" in paths[path]
