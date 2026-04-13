from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..models import User, Event, Venue, RSVP, RSVPStatusEnum, SavedEvent
from ..schemas import EventOut, EventCreate, RSVPOut, RSVPBody, FeedResponse
from ..auth import get_current_user
from ..services.feed import build_feed_event_out

router = APIRouter(prefix="/events", tags=["events"])


@router.get("/search", response_model=list[EventOut])
async def search_events(
    q: str = Query(..., min_length=1),
    lat: float = Query(None),
    lng: float = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    stmt = select(Event).options(selectinload(Event.venue)).where(
        func.lower(Event.title).contains(q.lower())
    ).limit(20)
    result = await db.execute(stmt)
    events = result.scalars().all()
    return [await build_feed_event_out(e, current_user, db) for e in events]


@router.get("/map", response_model=list[EventOut])
async def events_for_map(
    min_lat: float, max_lat: float,
    min_lng: float, max_lng: float,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    stmt = (
        select(Event)
        .options(selectinload(Event.venue))
        .join(Event.venue)
        .where(
            and_(
                Venue.latitude.between(min_lat, max_lat),
                Venue.longitude.between(min_lng, max_lng),
            )
        )
        .limit(100)
    )
    result = await db.execute(stmt)
    events = result.scalars().all()
    return [await build_feed_event_out(e, current_user, db) for e in events]


@router.get("/{event_id}", response_model=EventOut)
async def get_event(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Event).options(selectinload(Event.venue)).where(Event.id == event_id)
    )
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    return await build_feed_event_out(event, current_user, db)


@router.post("", response_model=EventOut, status_code=201)
async def create_event(
    body: EventCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    venue_result = await db.execute(select(Venue).where(Venue.id == body.venue_id))
    if not venue_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Venue not found")

    event = Event(**body.model_dump())
    db.add(event)
    await db.commit()
    await db.refresh(event)

    result = await db.execute(
        select(Event).options(selectinload(Event.venue)).where(Event.id == event.id)
    )
    event = result.scalar_one()
    return await build_feed_event_out(event, current_user, db)


@router.post("/{event_id}/rsvp", response_model=RSVPOut)
async def rsvp_event(
    event_id: str,
    body: RSVPBody,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Check event exists
    result = await db.execute(select(Event).where(Event.id == event_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Event not found")

    # Upsert
    existing = await db.execute(
        select(RSVP).where(RSVP.user_id == current_user.id, RSVP.event_id == event_id)
    )
    rsvp = existing.scalar_one_or_none()
    if rsvp:
        rsvp.status = body.status
    else:
        rsvp = RSVP(user_id=current_user.id, event_id=event_id, status=body.status)
        db.add(rsvp)

    await db.commit()
    await db.refresh(rsvp)
    return rsvp


@router.post("/{event_id}/save")
async def save_event(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = await db.execute(
        select(SavedEvent).where(
            SavedEvent.user_id == current_user.id,
            SavedEvent.event_id == event_id,
        )
    )
    if not existing.scalar_one_or_none():
        db.add(SavedEvent(user_id=current_user.id, event_id=event_id))
        await db.commit()
    return {}


@router.delete("/{event_id}/save")
async def unsave_event(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = await db.execute(
        select(SavedEvent).where(
            SavedEvent.user_id == current_user.id,
            SavedEvent.event_id == event_id,
        )
    )
    saved = existing.scalar_one_or_none()
    if saved:
        await db.delete(saved)
        await db.commit()
    return {}
