"""
Give the test shops and their menu items demo photos (development only).

    cd backend
    poetry run python -m scripts.seed_demo_photos

Points banner_url / logo_url / photo_url at the files in media/demo (see
media/demo/CREDITS.md), matched by shop and item name. Safe to run again.
"""
import asyncio
import sys

from sqlalchemy import select

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.merchant import Merchant, MenuItem

MEDIA = "/media/demo"

# Shop name (contains) -> file prefix for <prefix>-banner.jpg / <prefix>-logo.jpg
SHOPS = {
    "Mama Njeri Kitchen": "mama-njeri-kitchen",
    "Kibanda Grill": "kibanda-grill",
    "Mama Mboga Greens": "mama-mboga-greens",
}

# Menu item name (starts with) -> file
ITEMS = {
    "Sukuma wiki": "sukuma-wiki.jpg",
    "Tomatoes": "tomatoes.jpg",
    "Avocados": "avocados.jpg",
    "Bananas": "bananas.jpg",
    "Chicken shawarma": "chicken-shawarma.jpg",
}


async def main() -> None:
    if settings.is_production:
        sys.exit("Refusing to run in production.")

    async with AsyncSessionLocal() as db:
        for shop in (await db.execute(select(Merchant))).scalars():
            prefix = next((p for name, p in SHOPS.items() if name in shop.shop_name), None)
            if prefix:
                shop.banner_url = f"{MEDIA}/{prefix}-banner.jpg"
                shop.logo_url = f"{MEDIA}/{prefix}-logo.jpg"
                print(f"shop  {shop.shop_name}: banner and logo")

        for item in (await db.execute(select(MenuItem))).scalars():
            file = next((f for name, f in ITEMS.items() if item.name.startswith(name)), None)
            if file:
                item.photo_url = f"{MEDIA}/{file}"
                print(f"item  {item.name}: {file}")

        await db.commit()


if __name__ == "__main__":
    asyncio.run(main())
