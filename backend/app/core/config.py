from pydantic import model_validator
from pydantic_settings import BaseSettings
from functools import lru_cache
from typing import Literal


class Settings(BaseSettings):
    # ── App ───────────────────────────────────────────────────────────────────
    APP_NAME: str = "Soko Fetch"
    BASE_URL: str = "http://localhost:8000"
    # Required, no default: a forgotten setting must not silently put
    # production into development mode (OTPs logged, /docs public, CORS *)
    ENVIRONMENT: Literal["development", "staging", "production"]
    DEBUG: bool = False

    # ── Database ──────────────────────────────────────────────────────────────
    DATABASE_URL: str
    REDIS_URL: str = "redis://localhost:6379/0"

    # ── Security ──────────────────────────────────────────────────────────────
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30
    FIELD_ENCRYPTION_KEY: str
    DOCUMENT_ENCRYPTION_KEY: str

    # ── OTP ───────────────────────────────────────────────────────────────────
    OTP_EXPIRE_SECONDS: int = 300       # 5 minutes
    OTP_MAX_ATTEMPTS: int = 5           # per hour per phone
    OTP_RATE_WINDOW_SECONDS: int = 3600 # 1 hour
    OTP_MAX_VERIFY_ATTEMPTS: int = 5    # wrong codes before the OTP is burned

    # ── M-Pesa ────────────────────────────────────────────────────────────────
    MPESA_CONSUMER_KEY: str = ""
    MPESA_CONSUMER_SECRET: str = ""
    MPESA_SHORTCODE: str = "174379"
    MPESA_PASSKEY: str = ""
    MPESA_ENVIRONMENT: str = "sandbox"
    # Secret path segment on the STK callback URL (Daraja does not sign callbacks)
    MPESA_CALLBACK_TOKEN: str = ""

    # ── Flutterwave ───────────────────────────────────────────────────────────
    FLUTTERWAVE_SECRET_KEY: str = ""
    FLUTTERWAVE_PUBLIC_KEY: str = ""
    # "Secret hash" set in the Flutterwave dashboard; sent back as the verif-hash header
    FLUTTERWAVE_SECRET_HASH: str = ""

    # ── Africa's Talking ──────────────────────────────────────────────────────
    AT_USERNAME: str = "sandbox"
    AT_API_KEY: str = ""
    AT_SENDER_ID: str = "ALPHABET"

    # ── Firebase ──────────────────────────────────────────────────────────────
    FIREBASE_CREDENTIALS_PATH: str = "firebase-service-account.json"

    # ── AWS ───────────────────────────────────────────────────────────────────
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_REGION: str = "af-south-1"
    DOCUMENTS_BUCKET: str = "alphabet-courier-docs"

    # ── Google Maps ───────────────────────────────────────────────────────────
    GOOGLE_MAPS_API_KEY: str = ""

    # -- Google Sign-In --------------------------------------------------------
    GOOGLE_OAUTH_CLIENT_ID: str = "148030160920-2r3umll1quj3k9sfhnajm588edspnfsn.apps.googleusercontent.com"

    @model_validator(mode="after")
    def _require_production_secrets(self) -> "Settings":
        if self.ENVIRONMENT != "production":
            return self
        missing = [
            name for name in (
                "AT_API_KEY", "MPESA_CONSUMER_KEY", "MPESA_CONSUMER_SECRET",
                "MPESA_PASSKEY", "MPESA_CALLBACK_TOKEN",
            )
            if not getattr(self, name)
        ]
        if self.AT_USERNAME == "sandbox":
            missing.append("AT_USERNAME (still 'sandbox')")
        if len(self.JWT_SECRET) < 32 or self.JWT_SECRET.startswith("REPLACE_"):
            missing.append("JWT_SECRET (placeholder or shorter than 32 characters)")
        if missing:
            raise ValueError(
                "ENVIRONMENT=production but these settings are missing or unsafe: "
                + ", ".join(missing)
            )
        return self

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT == "production"

    @property
    def mpesa_base_url(self) -> str:
        if self.MPESA_ENVIRONMENT == "production":
            return "https://api.safaricom.co.ke"
        return "https://sandbox.safaricom.co.ke"

    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
