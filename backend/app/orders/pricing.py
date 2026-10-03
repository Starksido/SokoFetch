"""
Delivery fee and surge pricing calculator.

Rules:
  - Base fee is distance-variable: KES 60 + KES 15 per km
  - Minimum fee: KES 60
  - Maximum fee: KES 300 (before surge)
  - Surge multipliers activate on demand signals from Redis
  - Platform retains 18% of delivery fee; rest goes to courier
"""
import math
import logging
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, timezone

import redis.asyncio as aioredis

log = logging.getLogger("alphabet.orders.pricing")

# ── Constants ─────────────────────────────────────────────────────────────────
BASE_FEE_KES        = Decimal("60")
FEE_PER_KM          = Decimal("15")
MIN_FEE             = Decimal("60")
MAX_BASE_FEE        = Decimal("300")
PLATFORM_RETAINER   = Decimal("0.18")   # 18% of delivery fee
MAX_SURGE           = Decimal("2.0")

SURGE_THRESHOLDS = {
    "high_demand":   Decimal("1.3"),
    "bad_weather":   Decimal("1.5"),
    "low_couriers":  Decimal("1.8"),
}

# Earth radius in km
_EARTH_R = 6371.0


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Straight-line distance between two GPS points in kilometres."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi       = math.radians(lat2 - lat1)
    dlambda    = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * _EARTH_R * math.asin(math.sqrt(a))


async def get_surge_multiplier(redis: aioredis.Redis) -> Decimal:
    """
    Read surge signals from Redis and return the highest applicable multiplier.

    Signals are set by background workers (e.g. weather monitor, demand tracker).
    Keys:
      surge:high_demand  → "1" when active order rate exceeds threshold
      surge:bad_weather  → "1" when rain detected
      surge:low_couriers → "1" when active couriers < 3
    """
    multiplier = Decimal("1.0")
    for signal, value in SURGE_THRESHOLDS.items():
        flag = await redis.get(f"surge:{signal}")
        if flag == "1":
            multiplier = max(multiplier, value)
            log.info("Surge active: %s (×%s)", signal, value)

    # Cap at MAX_SURGE
    return min(multiplier, MAX_SURGE)


def calculate_base_fee(distance_km: float) -> Decimal:
    """Distance-variable fee before surge."""
    raw = BASE_FEE_KES + FEE_PER_KM * Decimal(str(round(distance_km, 2)))
    clamped = max(MIN_FEE, min(raw, MAX_BASE_FEE))
    return clamped.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def split_delivery_fee(delivery_fee: Decimal) -> tuple[Decimal, Decimal]:
    """
    Split delivery fee into platform retainer and courier payout.
    Returns (platform_fee, courier_payout).
    """
    platform = (delivery_fee * PLATFORM_RETAINER).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )
    courier = delivery_fee - platform
    return platform, courier


async def calculate_order_pricing(
    merchant_lat: float,
    merchant_lon: float,
    delivery_lat: float,
    delivery_lon: float,
    subtotal: Decimal,
    commission_rate: Decimal,
    redis: aioredis.Redis,
) -> dict:
    """
    Full pricing calculation for an order.

    Returns a dict with all financial fields needed by the Order model.
    """
    # Distance
    distance_km = _haversine_km(merchant_lat, merchant_lon, delivery_lat, delivery_lon)

    # Fees
    base_fee         = calculate_base_fee(distance_km)
    surge            = await get_surge_multiplier(redis)
    delivery_fee     = (base_fee * surge).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    platform_fee, courier_payout = split_delivery_fee(delivery_fee)

    # Commission
    merchant_commission = (subtotal * commission_rate / 100).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )

    total = subtotal + delivery_fee

    return {
        "subtotal":            subtotal,
        "delivery_fee":        delivery_fee,
        "surge_multiplier":    surge,
        "platform_fee":        platform_fee,
        "merchant_commission": merchant_commission,
        "courier_payout":      courier_payout,
        "total":               total,
        "distance_km":         round(distance_km, 2),
    }
