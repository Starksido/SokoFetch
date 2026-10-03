from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy import TypeDecorator, String
from app.core.config import settings


# ── Fernet cipher instances ───────────────────────────────────────────────────
_field_cipher = Fernet(settings.FIELD_ENCRYPTION_KEY.encode())
_document_cipher = Fernet(settings.DOCUMENT_ENCRYPTION_KEY.encode())


# ── Field helpers ─────────────────────────────────────────────────────────────
def encrypt_field(value: str) -> str:
    """Encrypt a string field before storing in DB."""
    return _field_cipher.encrypt(value.encode()).decode()


def decrypt_field(encrypted: str) -> str:
    """Decrypt a string field when reading from DB."""
    try:
        return _field_cipher.decrypt(encrypted.encode()).decode()
    except (InvalidToken, Exception):
        raise ValueError("Failed to decrypt field — key mismatch or corrupted data")


# ── Document helpers ──────────────────────────────────────────────────────────
def encrypt_document(data: bytes) -> bytes:
    """Encrypt raw file bytes before S3 upload."""
    return _document_cipher.encrypt(data)


def decrypt_document(encrypted: bytes) -> bytes:
    """Decrypt raw file bytes after S3 download."""
    try:
        return _document_cipher.decrypt(encrypted)
    except (InvalidToken, Exception):
        raise ValueError("Failed to decrypt document — key mismatch or corrupted data")


# ── SQLAlchemy custom type ────────────────────────────────────────────────────
class EncryptedString(TypeDecorator):
    """
    Transparently encrypts/decrypts string columns.

    Usage in models:
        phone = Column(EncryptedString(255))
    """
    impl = String
    cache_ok = True

    def process_bind_param(self, value: str | None, dialect) -> str | None:
        """Encrypt before writing to DB."""
        if value is None:
            return None
        return encrypt_field(str(value))

    def process_result_value(self, value: str | None, dialect) -> str | None:
        """Decrypt after reading from DB."""
        if value is None:
            return None
        return decrypt_field(value)
