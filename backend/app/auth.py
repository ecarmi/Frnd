from datetime import datetime, timedelta, timezone
from typing import Optional
import random
import string

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .config import settings
from .database import get_db
from .models import User, OTPCode

bearer_scheme = HTTPBearer()


def create_access_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {"sub": user_id, "exp": expire}
    return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)


def decode_token(token: str) -> str:
    """Returns user_id or raises HTTPException."""
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
        user_id: str = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
        return user_id
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    user_id = decode_token(credentials.credentials)
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def generate_otp() -> str:
    return "".join(random.choices(string.digits, k=6))


# ---------------------------------------------------------------------------
# University domain → name mapping
# ---------------------------------------------------------------------------

UNIVERSITY_DOMAINS: dict[str, str] = {
    "uchicago.edu":      "University of Chicago",
    "mit.edu":           "MIT",
    "harvard.edu":       "Harvard University",
    "stanford.edu":      "Stanford University",
    "yale.edu":          "Yale University",
    "princeton.edu":     "Princeton University",
    "columbia.edu":      "Columbia University",
    "cornell.edu":       "Cornell University",
    "upenn.edu":         "University of Pennsylvania",
    "northwestern.edu":  "Northwestern University",
    "nyu.edu":           "New York University",
    "georgetown.edu":    "Georgetown University",
    "uchicago.edu":      "University of Chicago",
    "umich.edu":         "University of Michigan",
    "berkeley.edu":      "UC Berkeley",
    "ucla.edu":          "UCLA",
    "uchicago.edu":      "University of Chicago",
    "illinois.edu":      "University of Illinois",
    "wisc.edu":          "University of Wisconsin",
    "umn.edu":           "University of Minnesota",
    "purdue.edu":        "Purdue University",
    "nd.edu":            "Notre Dame",
    "duke.edu":          "Duke University",
    "vanderbilt.edu":    "Vanderbilt University",
    "rice.edu":          "Rice University",
    "tufts.edu":         "Tufts University",
    "bu.edu":            "Boston University",
    "bc.edu":            "Boston College",
    "northeastern.edu":  "Northeastern University",
    "emory.edu":         "Emory University",
    "gatech.edu":        "Georgia Tech",
    "cmu.edu":           "Carnegie Mellon University",
}


def university_from_email(email: str) -> Optional[str]:
    """Returns the university name if the email domain is a known .edu."""
    domain = email.lower().split("@")[-1]
    return UNIVERSITY_DOMAINS.get(domain)


def is_edu_email(email: str) -> bool:
    domain = email.lower().split("@")[-1]
    return domain.endswith(".edu")


# ---------------------------------------------------------------------------
# Email OTP sending
# ---------------------------------------------------------------------------

DEV_BYPASS_EMAIL = "ecarmi@uchicago.edu"


async def send_email_otp(email: str, code: str) -> None:
    """Send OTP via email. Prints to console in development."""
    if settings.environment == "development":
        print(f"[DEV] Email OTP for {email}: {code}")
        return

    if not settings.resend_api_key:
        print(f"[WARN] No RESEND_API_KEY set — OTP for {email}: {code}")
        return

    import httpx
    html = f"""
    <div style="font-family:sans-serif;max-width:480px;margin:auto">
      <h2 style="color:#FF6B35">Your Frnd verification code</h2>
      <p style="font-size:48px;font-weight:bold;letter-spacing:8px;color:#0C0C0F;
                background:#f5f5f5;padding:16px 24px;border-radius:8px;display:inline-block">
        {code}
      </p>
      <p style="color:#666">Valid for 10 minutes. Don't share this code.</p>
    </div>
    """
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {settings.resend_api_key}"},
            json={
                "from": "Frnd <noreply@frnd.app>",
                "to": [email],
                "subject": f"{code} is your Frnd code",
                "html": html,
            },
        )
    if resp.status_code not in (200, 201):
        print(f"Resend error {resp.status_code}: {resp.text}")
        raise HTTPException(status_code=500, detail="Failed to send verification email")


async def send_otp(phone: str, code: str) -> None:
    """Legacy phone OTP via Twilio."""
    if settings.environment == "development":
        print(f"[DEV] SMS OTP for {phone}: {code}")
        return
    try:
        from twilio.rest import Client
        client = Client(settings.twilio_account_sid, settings.twilio_auth_token)
        client.messages.create(
            body=f"Your Frnd code is {code}. Valid for 10 minutes.",
            from_=settings.twilio_phone_number,
            to=phone,
        )
    except Exception as e:
        print(f"Failed to send OTP: {e}")
        raise HTTPException(status_code=500, detail="Failed to send verification code")
