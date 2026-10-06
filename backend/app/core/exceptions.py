from fastapi import HTTPException, status


class SokoFetchException(HTTPException):
    """Base exception with a structured error body."""
    def __init__(self, status_code: int, code: str, message: str):
        super().__init__(
            status_code=status_code,
            detail={"code": code, "message": message},
        )


# ── 400 Bad Request ───────────────────────────────────────────────────────────
class InvalidOTPError(SokoFetchException):
    def __init__(self):
        super().__init__(400, "INVALID_OTP", "OTP is invalid or has expired.")

class InvalidPhoneError(SokoFetchException):
    def __init__(self):
        super().__init__(400, "INVALID_PHONE", "Phone number format is invalid. Use +254XXXXXXXXX.")


# ── 401 Unauthorised ──────────────────────────────────────────────────────────
class InvalidTokenError(SokoFetchException):
    def __init__(self):
        super().__init__(401, "INVALID_TOKEN", "Token is invalid or has expired.")

class RevokedTokenError(SokoFetchException):
    def __init__(self):
        super().__init__(401, "REVOKED_TOKEN", "Token has been revoked. Please log in again.")


# ── 403 Forbidden ─────────────────────────────────────────────────────────────
class InsufficientRoleError(SokoFetchException):
    def __init__(self, required: str | list):
        roles = required if isinstance(required, str) else " or ".join(required)
        super().__init__(403, "INSUFFICIENT_ROLE", f"Access denied. Requires role: {roles}.")

class AccountDisabledError(SokoFetchException):
    def __init__(self):
        super().__init__(403, "ACCOUNT_DISABLED", "This account has been disabled. Contact support.")

class ObjectAccessDeniedError(SokoFetchException):
    def __init__(self):
        super().__init__(403, "ACCESS_DENIED", "You do not have access to this resource.")


# ── 404 Not Found ─────────────────────────────────────────────────────────────
class NotFoundError(SokoFetchException):
    def __init__(self, resource: str = "Resource"):
        super().__init__(404, "NOT_FOUND", f"{resource} not found.")


# ── 409 Conflict ──────────────────────────────────────────────────────────────
class AlreadyExistsError(SokoFetchException):
    def __init__(self, resource: str = "Resource"):
        super().__init__(409, "ALREADY_EXISTS", f"{resource} already exists.")


# ── 422 Unprocessable ─────────────────────────────────────────────────────────
class CourierNotApprovedError(SokoFetchException):
    def __init__(self):
        super().__init__(422, "COURIER_NOT_APPROVED", "Courier account is not approved yet.")


# ── 429 Rate Limit ────────────────────────────────────────────────────────────
class RateLimitError(SokoFetchException):
    def __init__(self, message: str = "Too many requests. Please try again later."):
        super().__init__(429, "RATE_LIMITED", message)


# ── 402 Payment ───────────────────────────────────────────────────────────────
class PaymentBlockedError(SokoFetchException):
    def __init__(self, reason: str):
        super().__init__(402, "PAYMENT_BLOCKED", f"Payment blocked: {reason}")
