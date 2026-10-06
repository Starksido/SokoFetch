"""
Create an admin account, or promote an existing one.

Admins can never be created through the app's sign-up. Run this against the
database in your .env, then log in to the app with the same phone number.

    cd backend
    poetry run python -m scripts.create_admin --phone 0712345678
    poetry run python -m scripts.create_admin --phone 0712345678 --promote
"""
import argparse
import asyncio
import sys

from sqlalchemy import select

from app.auth.otp import validate_phone
from app.auth.service import _phone_hash
from app.core.database import AsyncSessionLocal
from app.core.exceptions import InvalidPhoneError
from app.models.user import User, UserRole


async def main(phone: str, promote: bool) -> int:
    try:
        phone = validate_phone(phone)
    except InvalidPhoneError:
        print(f"Not a valid Kenyan mobile number: {phone}")
        return 1

    async with AsyncSessionLocal() as db:
        user = (await db.execute(
            select(User).where(User.phone_hash == _phone_hash(phone))
        )).scalar_one_or_none()

        if user is None:
            db.add(User(phone=phone, phone_hash=_phone_hash(phone),
                        role=UserRole.admin, is_verified=True))
            print(f"Created admin account for {phone}.")
        elif user.role == UserRole.admin:
            print(f"{phone} is already an admin.")
            return 0
        elif not promote:
            print(f"{phone} already has a {user.role.value} account. "
                  "Re-run with --promote to turn it into an admin account.")
            return 1
        else:
            print(f"Promoting {phone} from {user.role.value} to admin.")
            user.role = UserRole.admin
        await db.commit()
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("--phone", required=True, help="e.g. 0712345678 or +254712345678")
    parser.add_argument("--promote", action="store_true",
                        help="turn an existing customer/merchant/courier account into an admin")
    args = parser.parse_args()
    sys.exit(asyncio.run(main(args.phone, args.promote)))
