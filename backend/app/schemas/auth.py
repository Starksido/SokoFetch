from pydantic import BaseModel, field_validator
from typing import Literal, Optional
import re

PHONE_RE = re.compile(r"^\+254[17]\d{8}$")
ROLES = Literal["customer", "merchant", "courier"]


# ── Request schemas ───────────────────────────────────────────────────────────
class OTPRequestSchema(BaseModel):
    phone: str

    @field_validator("phone")
    @classmethod
    def normalise_phone(cls, v: str) -> str:
        v = v.strip().replace(" ", "").replace("-", "")
        if v.startswith("07") or v.startswith("01"):
            v = "+254" + v[1:]
        if not PHONE_RE.match(v):
            raise ValueError("Invalid Kenyan phone number. Format: +254712345678 or 0712345678")
        return v


class OTPVerifySchema(BaseModel):
    phone:    str
    otp_code: str
    # Omit to log in as whatever role the account has. A new number without
    # a role gets a signup_token and picks the role via POST /auth/signup.
    role:     Optional[ROLES] = None

    @field_validator("phone")
    @classmethod
    def normalise_phone(cls, v: str) -> str:
        v = v.strip().replace(" ", "").replace("-", "")
        if v.startswith("07") or v.startswith("01"):
            v = "+254" + v[1:]
        if not PHONE_RE.match(v):
            raise ValueError("Invalid phone number format")
        return v

    @field_validator("otp_code")
    @classmethod
    def validate_otp(cls, v: str) -> str:
        v = v.strip()
        if not v.isdigit() or len(v) != 6:
            raise ValueError("OTP must be exactly 6 digits")
        return v


class TokenRefreshSchema(BaseModel):
    refresh_token: str


class SignupSchema(BaseModel):
    signup_token: str
    role:         ROLES   # admin can never be chosen


# ── Response schemas ──────────────────────────────────────────────────────────
class OTPRequestResponse(BaseModel):
    message:    str = "OTP sent successfully"
    expires_in: int = 300   # seconds


class UserProfile(BaseModel):
    user_id:    str
    phone:      Optional[str] = None
    email:      Optional[str] = None
    role:       str
    is_new:     bool    # True if account was created on this OTP verify
    created_at: str


class TokenResponse(BaseModel):
    access_token:  str
    refresh_token: str
    token_type:    str = "bearer"
    expires_in:    int = 1800   # 30 minutes in seconds
    user:          UserProfile


class SignupRequiredResponse(BaseModel):
    """Identity verified, but no account exists yet: the user must pick a role."""
    needs_role:   Literal[True] = True
    signup_token: str
    expires_in:   int = 600   # seconds


class LogoutResponse(BaseModel):
    message: str = "Logged out successfully"


class GoogleLoginSchema(BaseModel):
    id_token: str
    role:     Optional[ROLES] = None


class GoogleUserProfile(BaseModel):
    user_id:    str
    email:      str | None
    role:       str
    is_new:     bool
    created_at: str


class GoogleTokenResponse(BaseModel):
    access_token:  str
    refresh_token: str
    token_type:    str = "bearer"
    expires_in:    int = 1800
    user:          GoogleUserProfile
