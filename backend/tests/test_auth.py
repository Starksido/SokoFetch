"""
Auth test suite.

Run with:
    cd backend
    pytest tests/test_auth.py -v
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from httpx import AsyncClient, ASGITransport


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


