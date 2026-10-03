import logging
import httpx
from app.core.config import settings

logger = logging.getLogger("alphabet.auth.sms")

AT_SMS_URL = "https://api.africastalking.com/version1/messaging"
AT_SANDBOX_URL = "https://api.sandbox.africastalking.com/version1/messaging"


async def send_otp_sms(phone: str, otp_code: str) -> bool:
    """
    Send OTP via Africa's Talking SMS gateway.
    In sandbox mode (AT_USERNAME='sandbox'), no real SMS is sent.
    Returns True on success, False on failure.
    """
    message = f"Your Soko Fetch verification code is: {otp_code}. Valid for 5 minutes. Do not share this code."

    url = AT_SANDBOX_URL if settings.AT_USERNAME == "sandbox" else AT_SMS_URL

    # In development, just log the OTP instead of sending SMS
    if settings.ENVIRONMENT == "development":
        logger.info("DEV MODE — OTP for %s: %s", phone[-4:], otp_code)
        return True

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                url,
                headers={
                    "Accept": "application/json",
                    "Content-Type": "application/x-www-form-urlencoded",
                    "apiKey": settings.AT_API_KEY,
                },
                data={
                    "username": settings.AT_USERNAME,
                    "to":       phone,
                    "message":  message,
                    "from":     settings.AT_SENDER_ID,
                },
            )
            response.raise_for_status()
            data = response.json()

            recipients = data.get("SMSMessageData", {}).get("Recipients", [])
            if recipients and recipients[0].get("status") == "Success":
                logger.info("OTP SMS sent | phone_tail=%s", phone[-4:])
                return True

            logger.warning("OTP SMS delivery uncertain | response=%s", data)
            return False

    except httpx.HTTPError as exc:
        logger.error("OTP SMS failed | error=%s", exc)
        return False
