import hashlib
import secrets
import logging
import pyotp
import redis.asyncio as aioredis

from app.core.config import settings
from app.core.exceptions import InvalidOTPError, RateLimitError, InvalidPhoneError

logger = logging.getLogger("alphabet.auth.otp")

# ── Phone validation ──────────────────────────────────────────────────────────
import re
_PHONE_RE = re.compile(r"^\+254[17]\d{8}$")   # Kenyan mobile numbers

def validate_phone(phone: str) -> str:
    """
    Normalise and validate Kenyan phone number.
    Accepts: 0712345678 → +254712345678
             +254712345678 → +254712345678
    """
    phone = phone.strip().replace(" ", "").replace("-", "")
    if phone.startswith("07") or phone.startswith("01"):
        phone = "+254" + phone[1:]
    if not _PHONE_RE.match(phone):
        raise InvalidPhoneError()
    return phone


# ── Redis key helpers ─────────────────────────────────────────────────────────
def _phone_hash(phone: str) -> str:
    """SHA-256 hash of phone — never store raw phone in Redis keys."""
    return hashlib.sha256(phone.encode()).hexdigest()[:32]

def _otp_key(phone: str, role: str) -> str:
    return f"otp:{role}:{_phone_hash(phone)}"

def _rate_key(phone: str) -> str:
    return f"otp_rate:{_phone_hash(phone)}"

def _fail_key(phone: str, role: str) -> str:
    return f"otp_fail:{role}:{_phone_hash(phone)}"


# ── Rate limiting ─────────────────────────────────────────────────────────────
async def check_rate_limit(phone: str, redis: aioredis.Redis) -> None:
    """
    Allow max OTP_MAX_ATTEMPTS OTP requests per phone per hour.
    Raises RateLimitError if exceeded.
    """
    key = _rate_key(phone)
    count = await redis.incr(key)
    if count == 1:
        # First request — set expiry window
        await redis.expire(key, settings.OTP_RATE_WINDOW_SECONDS)
    if count > settings.OTP_MAX_ATTEMPTS:
        ttl = await redis.ttl(key)
        minutes = max(1, ttl // 60)
        raise RateLimitError(
            f"Too many OTP requests. Try again in {minutes} minute(s)."
        )


# ── OTP generation ────────────────────────────────────────────────────────────
async def generate_otp(phone: str, role: str, redis: aioredis.Redis) -> str:
    """
    Generate a 6-digit TOTP code, store secret+code in Redis with TTL.
    Returns the plaintext OTP code (to be sent via SMS).
    """
    secret = pyotp.random_base32()
    totp = pyotp.TOTP(secret, interval=settings.OTP_EXPIRE_SECONDS)
    code = totp.now()

    key = _otp_key(phone, role)
    # Store as "secret:code" — single-use
    await redis.setex(key, settings.OTP_EXPIRE_SECONDS, f"{secret}:{code}")
    # Fresh code → fresh wrong-guess budget
    await redis.delete(_fail_key(phone, role))

    logger.info("OTP generated | role=%s | phone_hash=%s", role, _phone_hash(phone))
    return code


# ── OTP verification ──────────────────────────────────────────────────────────
async def verify_otp(phone: str, code: str, role: str, redis: aioredis.Redis) -> bool:
    """
    Verify OTP code. Deletes it on success (single-use).
    Raises InvalidOTPError on failure. After OTP_MAX_VERIFY_ATTEMPTS wrong
    guesses the code is burned (RateLimitError) and a new one must be requested.
    """
    key = _otp_key(phone, role)
    entry = await redis.get(key)

    if not entry:
        logger.warning(
            "OTP not found or expired | role=%s | phone_hash=%s",
            role, _phone_hash(phone)
        )
        raise InvalidOTPError()

    stored_secret, stored_code = entry.split(":", 1)

    # Constant-time comparison — prevents timing attacks
    if not secrets.compare_digest(stored_code, code.strip()):
        logger.warning(
            "OTP mismatch | role=%s | phone_hash=%s",
            role, _phone_hash(phone)
        )
        fail_key = _fail_key(phone, role)
        fails = await redis.incr(fail_key)
        if fails == 1:
            await redis.expire(fail_key, settings.OTP_EXPIRE_SECONDS)
        if fails >= settings.OTP_MAX_VERIFY_ATTEMPTS:
            # Burn the code so it cannot be brute-forced
            await redis.delete(key, fail_key)
            logger.warning("OTP burned after %d wrong attempts | phone_hash=%s", fails, _phone_hash(phone))
            raise RateLimitError("Too many incorrect codes. Please request a new code.")
        raise InvalidOTPError()

    # Invalidate immediately — single use
    await redis.delete(key, _fail_key(phone, role))

    # Also clear the rate limit counter on success
    await redis.delete(_rate_key(phone))

    logger.info("OTP verified | role=%s | phone_hash=%s", role, _phone_hash(phone))
    return True
