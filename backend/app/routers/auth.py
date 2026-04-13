from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import User, OTPCode, TasteProfile
from ..schemas import OTPRequest, OTPVerify, AuthResponse
from ..auth import generate_otp, send_otp, create_access_token

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/otp/request")
async def request_otp(body: OTPRequest, db: AsyncSession = Depends(get_db)):
    code = generate_otp()
    expires = datetime.now(timezone.utc) + timedelta(minutes=10)

    # Invalidate any existing OTPs for this phone
    existing = await db.execute(
        select(OTPCode).where(OTPCode.phone == body.phone, OTPCode.used == False)
    )
    for old in existing.scalars().all():
        old.used = True

    otp_record = OTPCode(phone=body.phone, code=code, expires_at=expires)
    db.add(otp_record)
    await db.commit()

    await send_otp(body.phone, code)
    return {"message": "Code sent"}


@router.post("/otp/verify", response_model=AuthResponse)
async def verify_otp(body: OTPVerify, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(OTPCode).where(
            OTPCode.phone == body.phone,
            OTPCode.code == body.code,
            OTPCode.used == False,
        )
    )
    otp_record = result.scalar_one_or_none()

    if not otp_record:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid code")
    if otp_record.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Code expired")

    otp_record.used = True

    # Get or create user
    user_result = await db.execute(select(User).where(User.phone == body.phone))
    user = user_result.scalar_one_or_none()

    if not user:
        user = User(phone=body.phone, name="")
        db.add(user)
        await db.flush()

        taste = TasteProfile(user_id=user.id)
        db.add(taste)

    await db.commit()
    await db.refresh(user)

    token = create_access_token(user.id)
    return AuthResponse(access_token=token, user=user)
