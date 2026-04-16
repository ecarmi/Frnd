import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import User, OTPCode, TasteProfile
from ..schemas import OTPRequest, OTPVerify, AuthResponse
from ..auth import (
    generate_otp, send_email_otp, send_otp,
    create_access_token, university_from_email, is_allowed_email,
    DEV_BYPASS_EMAIL,
)
from ..config import settings

router = APIRouter(prefix="/auth", tags=["auth"])


# ---------------------------------------------------------------------------
# Email-based auth (primary)
# ---------------------------------------------------------------------------

@router.post("/email/request")
async def request_email_otp(body: OTPRequest, db: AsyncSession = Depends(get_db)):
    email = (body.email or "").strip().lower()

    if not email:
        raise HTTPException(status_code=400, detail="Email is required")
    if not is_allowed_email(email):
        raise HTTPException(status_code=400, detail=settings.launch_access_message)

    # Dev bypass — don't send an email, just return success
    if email == DEV_BYPASS_EMAIL:
        return {"message": "Dev bypass active — use code 000000"}

    code = generate_otp()
    expires = datetime.now(timezone.utc) + timedelta(minutes=10)

    # Invalidate existing unused codes for this email
    existing = await db.execute(
        select(OTPCode).where(OTPCode.email == email, OTPCode.used == False)
    )
    for old in existing.scalars().all():
        old.used = True

    db.add(OTPCode(email=email, code=code, expires_at=expires))
    await db.commit()

    await send_email_otp(email, code)
    return {"message": "Verification code sent"}


@router.post("/email/verify", response_model=AuthResponse)
async def verify_email_otp(body: OTPVerify, db: AsyncSession = Depends(get_db)):
    email = (body.email or "").strip().lower()

    if not email:
        raise HTTPException(status_code=400, detail="Email is required")

    # Dev bypass
    if email == DEV_BYPASS_EMAIL and body.code == "000000":
        user_result = await db.execute(select(User).where(User.email == email))
        user = user_result.scalar_one_or_none()
        if not user:
            user_id = str(uuid.uuid4())
            user = User(id=user_id, email=email, name="", university=university_from_email(email))
            db.add(user)
            db.add(TasteProfile(user_id=user_id))
        await db.commit()
        user_result = await db.execute(
            select(User).where(User.email == email).options(selectinload(User.taste_profile))
        )
        user = user_result.scalar_one()
        return AuthResponse(access_token=create_access_token(user.id), user=user)

    # Normal flow
    result = await db.execute(
        select(OTPCode).where(
            OTPCode.email == email,
            OTPCode.code == body.code,
            OTPCode.used == False,
        )
    )
    otp_record = result.scalar_one_or_none()

    if not otp_record:
        raise HTTPException(status_code=400, detail="Invalid code")
    if otp_record.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Code expired")

    otp_record.used = True

    user_result = await db.execute(select(User).where(User.email == email))
    user = user_result.scalar_one_or_none()

    if not user:
        user_id = str(uuid.uuid4())
        user = User(id=user_id, email=email, name="", university=university_from_email(email))
        db.add(user)
        db.add(TasteProfile(user_id=user_id))

    await db.commit()
    user_result = await db.execute(
        select(User).where(User.email == email).options(selectinload(User.taste_profile))
    )
    user = user_result.scalar_one()

    return AuthResponse(access_token=create_access_token(user.id), user=user)


# ---------------------------------------------------------------------------
# Legacy phone OTP (kept for seed data / testing)
# ---------------------------------------------------------------------------

@router.post("/otp/request")
async def request_otp(body: OTPRequest, db: AsyncSession = Depends(get_db)):
    phone = (body.phone or "").strip()
    if not phone:
        raise HTTPException(status_code=400, detail="Phone is required")

    code = generate_otp()
    expires = datetime.now(timezone.utc) + timedelta(minutes=10)

    existing = await db.execute(
        select(OTPCode).where(OTPCode.email == phone, OTPCode.used == False)
    )
    for old in existing.scalars().all():
        old.used = True

    db.add(OTPCode(email=phone, code=code, expires_at=expires))
    await db.commit()

    await send_otp(phone, code)
    return {"message": "Code sent"}


@router.post("/otp/verify", response_model=AuthResponse)
async def verify_otp(body: OTPVerify, db: AsyncSession = Depends(get_db)):
    phone = (body.phone or "").strip()

    # Dev bypass
    if settings.environment == "development" and body.code == "000000":
        user_result = await db.execute(select(User).where(User.phone == phone))
        user = user_result.scalar_one_or_none()
        if not user:
            user_id = str(uuid.uuid4())
            user = User(id=user_id, phone=phone, name="")
            db.add(user)
            db.add(TasteProfile(user_id=user_id))
        await db.commit()
        await db.refresh(user)
        return AuthResponse(access_token=create_access_token(user.id), user=user)

    result = await db.execute(
        select(OTPCode).where(
            OTPCode.email == phone,
            OTPCode.code == body.code,
            OTPCode.used == False,
        )
    )
    otp_record = result.scalar_one_or_none()

    if not otp_record:
        raise HTTPException(status_code=400, detail="Invalid code")
    if otp_record.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Code expired")

    otp_record.used = True

    user_result = await db.execute(select(User).where(User.phone == phone))
    user = user_result.scalar_one_or_none()

    if not user:
        user_id = str(uuid.uuid4())
        user = User(id=user_id, phone=phone, name="")
        db.add(user)
        db.add(TasteProfile(user_id=user_id))

    await db.commit()
    await db.refresh(user)

    return AuthResponse(access_token=create_access_token(user.id), user=user)
