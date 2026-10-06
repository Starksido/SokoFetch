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

    async def getdel(key):
        return store.pop(key, None)

    redis.set = set_
    redis.getdel = getdel
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
        code = await generate_otp("+254712345678", "customer", redis)
        assert len(code) == 6
        assert code.isdigit()
        # Should be stored in Redis
        assert any("otp:customer:" in k for k in store)

    @pytest.mark.asyncio
    async def test_verify_correct_code(self, mock_redis):
        redis, store = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        code = await generate_otp("+254712345678", "customer", redis)
        result = await verify_otp("+254712345678", code, "customer", redis)
        assert result is True

    @pytest.mark.asyncio
    async def test_verify_wrong_code_raises(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        from app.core.exceptions import InvalidOTPError
        await generate_otp("+254712345678", "customer", redis)
        with pytest.raises(InvalidOTPError):
            await verify_otp("+254712345678", "000000", "customer", redis)

    @pytest.mark.asyncio
    async def test_otp_single_use(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        from app.core.exceptions import InvalidOTPError
        code = await generate_otp("+254712345678", "customer", redis)
        await verify_otp("+254712345678", code, "customer", redis)  # First use — OK
        with pytest.raises(InvalidOTPError):
            await verify_otp("+254712345678", code, "customer", redis)  # Second use — fails

    @pytest.mark.asyncio
    async def test_code_burned_after_max_wrong_attempts(self, mock_redis):
        # Regression: verify had no attempt limit, so 6-digit codes were brute-forceable
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        from app.core.exceptions import InvalidOTPError, RateLimitError
        code = await generate_otp("+254712345678", "customer", redis)
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(4):
            with pytest.raises(InvalidOTPError):
                await verify_otp("+254712345678", wrong, "customer", redis)
        with pytest.raises(RateLimitError):
            await verify_otp("+254712345678", wrong, "customer", redis)
        # The real code no longer works — a new one must be requested
        with pytest.raises(InvalidOTPError):
            await verify_otp("+254712345678", code, "customer", redis)

    async def test_new_code_resets_wrong_attempts(self, mock_redis):
        redis, _ = mock_redis
        from app.auth.otp import generate_otp, verify_otp
        from app.core.exceptions import InvalidOTPError
        code = await generate_otp("+254712345678", "customer", redis)
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(4):
            with pytest.raises(InvalidOTPError):
                await verify_otp("+254712345678", wrong, "customer", redis)
        code = await generate_otp("+254712345678", "customer", redis)
        assert await verify_otp("+254712345678", code, "customer", redis) is True

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
    async def test_otp_request_invalid_role(self, client):
        c, _ = client
        resp = await c.post("/auth/otp/request", json={
            "phone": "0712345678",
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


