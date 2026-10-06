import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.core.config import settings
from app.core.middleware import security_middleware
from app.core.redis import close_redis
from app.auth.router import router as auth_router
from app.orders.router import router as orders_router
from app.payments.router import router as payments_router
from app.merchant.router import router as merchant_router
from app.courier.router import router as courier_router
from app.customer.router import router as customer_router
from app.admin.router import router as admin_router

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
logger = logging.getLogger("alphabet")


# ── Lifespan: startup / shutdown hooks ────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Soko Fetch API starting up | env=%s", settings.ENVIRONMENT)
    yield
    logger.info("Soko Fetch API shutting down")
    await close_redis()


# ── App instance ──────────────────────────────────────────────────────────────
app = FastAPI(
    title="Soko Fetch API",
    version="1.0.0",
    description="Soko Fetch On-Demand Delivery Platform",
    lifespan=lifespan,
    # Disable interactive docs in production
    docs_url="/docs" if not settings.is_production else None,
    redoc_url="/redoc" if not settings.is_production else None,
)

# ── CORS ──────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if not settings.is_production else [settings.BASE_URL],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Security middleware ────────────────────────────────────────────────────────
app.middleware("http")(security_middleware)

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(auth_router,     prefix="/auth",     tags=["Authentication"])
app.include_router(orders_router,   prefix="/orders",   tags=["Orders"])
app.include_router(payments_router, prefix="/payments", tags=["Payments"])
app.include_router(merchant_router, prefix="/merchant", tags=["Merchant"])
app.include_router(courier_router,  prefix="/courier",  tags=["Courier"])
app.include_router(customer_router, prefix="/customer", tags=["Customer"])
app.include_router(admin_router,    prefix="/admin",    tags=["Admin"])


# ── Health check ──────────────────────────────────────────────────────────────
@app.get("/health", tags=["System"])
async def health():
    return {"status": "ok", "environment": settings.ENVIRONMENT}


# ── Global exception handler ──────────────────────────────────────────────────
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error("Unhandled exception: %s", exc, exc_info=True)
    return JSONResponse(
        {"detail": {"code": "INTERNAL_ERROR", "message": "An unexpected error occurred."}},
        status_code=500,
    )


