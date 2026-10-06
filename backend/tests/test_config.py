"""
Settings tests — production must be chosen explicitly and fully configured.

Run with:
    cd backend && pytest tests/test_config.py -v
"""
import pytest
from pydantic import ValidationError

_BASE = {
    "DATABASE_URL": "postgresql+asyncpg://u:p@localhost/db",
    "JWT_SECRET": "x" * 40,
    "FIELD_ENCRYPTION_KEY": "k",
    "DOCUMENT_ENCRYPTION_KEY": "k",
}

_PROD_SECRETS = {
    "AT_USERNAME": "sokofetch",
    "AT_API_KEY": "key",
    "MPESA_CONSUMER_KEY": "ck",
    "MPESA_CONSUMER_SECRET": "cs",
    "MPESA_PASSKEY": "pk",
    "MPESA_CALLBACK_TOKEN": "tok",
}


def _settings(monkeypatch, **values):
    from app.core.config import Settings
    monkeypatch.delenv("ENVIRONMENT", raising=False)
    return Settings(_env_file=None, **values)


class TestEnvironmentSetting:
    def test_missing_environment_fails(self, monkeypatch):
        # Regression: ENVIRONMENT defaulted to "development", so a production
        # server without it logged OTPs instead of sending them and exposed /docs
        with pytest.raises(ValidationError):
            _settings(monkeypatch, **_BASE)

    def test_unknown_environment_fails(self, monkeypatch):
        with pytest.raises(ValidationError):
            _settings(monkeypatch, ENVIRONMENT="prod", **_BASE)

    def test_debug_defaults_off(self, monkeypatch):
        s = _settings(monkeypatch, ENVIRONMENT="development", **_BASE)
        assert s.DEBUG is False
        assert s.is_production is False

    def test_production_without_secrets_fails(self, monkeypatch):
        with pytest.raises(ValidationError, match="AT_API_KEY"):
            _settings(monkeypatch, ENVIRONMENT="production", **_BASE)

    def test_production_with_placeholder_jwt_secret_fails(self, monkeypatch):
        values = {**_BASE, **_PROD_SECRETS, "JWT_SECRET": "REPLACE_WITH_256_BIT_RANDOM_STRING"}
        with pytest.raises(ValidationError, match="JWT_SECRET"):
            _settings(monkeypatch, ENVIRONMENT="production", **values)

    def test_production_fully_configured(self, monkeypatch):
        s = _settings(monkeypatch, ENVIRONMENT="production", **_BASE, **_PROD_SECRETS)
        assert s.is_production is True
