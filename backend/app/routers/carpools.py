from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..models import Carpool, CarpoolPassenger, CarpoolStatusEnum, User
from ..schemas import CarpoolOut, CarpoolCreate, CarpoolPassengerOut, UserOut
from ..auth import get_current_user

router = APIRouter(prefix="/carpools", tags=["carpools"])


def _passenger_out(p: CarpoolPassenger) -> CarpoolPassengerOut:
    return CarpoolPassengerOut(
        id=p.id,
        carpool_id=p.carpool_id,
        user_id=p.user_id,
        status=p.status,
        created_at=p.created_at,
        user=UserOut.model_validate(p.user) if p.user else None,
    )


def _carpool_out(carpool: Carpool) -> CarpoolOut:
    passengers = [_passenger_out(p) for p in carpool.passengers]
    confirmed = [p for p in passengers if p.status == "confirmed"]
    seats_available = max(0, carpool.total_seats - len(confirmed))
    return CarpoolOut(
        id=carpool.id,
        plan_id=carpool.plan_id,
        driver_id=carpool.driver_id,
        departure_location=carpool.departure_location,
        departure_latitude=carpool.departure_latitude,
        departure_longitude=carpool.departure_longitude,
        departure_time=carpool.departure_time,
        total_seats=carpool.total_seats,
        notes=carpool.notes,
        status=carpool.status,
        created_at=carpool.created_at,
        driver=UserOut.model_validate(carpool.driver) if carpool.driver else None,
        passengers=passengers,
        seats_available=seats_available,
    )


async def _load_carpool(carpool_id: str, db: AsyncSession) -> Carpool | None:
    result = await db.execute(
        select(Carpool)
        .options(
            selectinload(Carpool.driver),
            selectinload(Carpool.passengers).selectinload(CarpoolPassenger.user),
        )
        .where(Carpool.id == carpool_id)
    )
    return result.scalar_one_or_none()


@router.get("/plan/{plan_id}", response_model=list[CarpoolOut])
async def list_plan_carpools(
    plan_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Carpool)
        .options(
            selectinload(Carpool.driver),
            selectinload(Carpool.passengers).selectinload(CarpoolPassenger.user),
        )
        .where(Carpool.plan_id == plan_id)
        .order_by(Carpool.created_at.asc())
    )
    carpools = result.scalars().unique().all()
    return [_carpool_out(c) for c in carpools]


@router.post("", response_model=CarpoolOut, status_code=201)
async def offer_carpool(
    body: CarpoolCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    carpool = Carpool(
        plan_id=body.plan_id,
        driver_id=current_user.id,
        departure_location=body.departure_location,
        departure_latitude=body.departure_latitude,
        departure_longitude=body.departure_longitude,
        departure_time=body.departure_time,
        total_seats=body.total_seats,
        notes=body.notes,
        status=CarpoolStatusEnum.open,
    )
    db.add(carpool)
    await db.commit()

    loaded = await _load_carpool(carpool.id, db)
    return _carpool_out(loaded)


@router.post("/{carpool_id}/request", response_model=CarpoolOut)
async def request_seat(
    carpool_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    carpool = await _load_carpool(carpool_id, db)
    if not carpool:
        raise HTTPException(status_code=404, detail="Carpool not found")
    if carpool.status != CarpoolStatusEnum.open:
        raise HTTPException(status_code=400, detail="Carpool is not open")
    if carpool.driver_id == current_user.id:
        raise HTTPException(status_code=400, detail="Driver cannot request a seat")

    already = any(p.user_id == current_user.id for p in carpool.passengers)
    if already:
        raise HTTPException(status_code=400, detail="Already requested")

    confirmed_count = sum(1 for p in carpool.passengers if p.status == "confirmed")
    if confirmed_count >= carpool.total_seats:
        raise HTTPException(status_code=400, detail="Carpool is full")

    db.add(CarpoolPassenger(carpool_id=carpool_id, user_id=current_user.id, status="pending"))
    await db.commit()

    loaded = await _load_carpool(carpool_id, db)
    return _carpool_out(loaded)


@router.patch("/{carpool_id}/passengers/{passenger_user_id}", response_model=CarpoolOut)
async def update_passenger_status(
    carpool_id: str,
    passenger_user_id: str,
    status: str,  # "confirmed" | "rejected"
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    carpool = await _load_carpool(carpool_id, db)
    if not carpool:
        raise HTTPException(status_code=404, detail="Carpool not found")
    if carpool.driver_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the driver can update passenger status")
    if status not in ("confirmed", "rejected"):
        raise HTTPException(status_code=400, detail="Status must be 'confirmed' or 'rejected'")

    result = await db.execute(
        select(CarpoolPassenger).where(
            CarpoolPassenger.carpool_id == carpool_id,
            CarpoolPassenger.user_id == passenger_user_id,
        )
    )
    passenger = result.scalar_one_or_none()
    if not passenger:
        raise HTTPException(status_code=404, detail="Passenger not found")

    passenger.status = status
    await db.commit()

    loaded = await _load_carpool(carpool_id, db)
    return _carpool_out(loaded)


@router.delete("/{carpool_id}/leave", status_code=204)
async def leave_carpool(
    carpool_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(CarpoolPassenger).where(
            CarpoolPassenger.carpool_id == carpool_id,
            CarpoolPassenger.user_id == current_user.id,
        )
    )
    passenger = result.scalar_one_or_none()
    if not passenger:
        raise HTTPException(status_code=404, detail="Not in this carpool")

    await db.delete(passenger)
    await db.commit()
