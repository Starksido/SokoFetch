import re
import time
import logging
from fastapi import Request
from fastapi.responses import JSONResponse

logger = logging.getLogger("alphabet.access")

# Patterns that indicate malicious payloads
_SUSPICIOUS = [
    re.compile(r"(<script|javascript:|data:text/html)", re.IGNORECASE),  # XSS
    re.compile(r"\b(UNION\s+SELECT|DROP\s+TABLE|INSERT\s+INTO)\b", re.IGNORECASE),  # SQLi
    re.compile(r"(\.\./|\.\.\\)", re.IGNORECASE),                          # Path traversal
]

# Fields that must NEVER appear in logs
_SENSITIVE_FIELDS = {"otp", "otp_code", "password", "token", "card_number", "cvv", "pin"}

# Only text bodies are scanned. Binary uploads (multipart images) are close to
# random bytes and would match the short patterns above by chance.
_SCANNED_CONTENT_TYPES = ("application/json", "application/x-www-form-urlencoded")


def _is_scanned(request: Request) -> bool:
    content_type = request.headers.get("content-type", "").split(";")[0].strip().lower()
    return content_type in _SCANNED_CONTENT_TYPES


async def security_middleware(request: Request, call_next):
    start = time.perf_counter()

    # ── 1. Inspect text request bodies for attack patterns ────────────────────
    body_str = ""
    if _is_scanned(request):
        body_bytes = await request.body()
        body_str = body_bytes.decode("utf-8", errors="replace")

    for pattern in _SUSPICIOUS:
        if body_str and pattern.search(body_str):
            logger.warning(
                "Suspicious payload blocked | path=%s | ip=%s",
                request.url.path, request.client.host if request.client else "unknown",
            )
            return JSONResponse(
                {"detail": {"code": "INVALID_REQUEST", "message": "Request contains invalid content."}},
                status_code=400,
            )

    # ── 2. Process request ────────────────────────────────────────────────────
    response = await call_next(request)
    duration_ms = (time.perf_counter() - start) * 1000

    # ── 3. Security response headers ──────────────────────────────────────────
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=()"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    # Remove server fingerprint
    if "server" in response.headers: del response.headers["server"]
    if "x-powered-by" in response.headers: del response.headers["x-powered-by"]

    # ── 4. Access log (never logs sensitive fields) ───────────────────────────
    logger.info(
        "%s %s | %d | %.1fms",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )

    return response


