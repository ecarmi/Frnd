import logging
import traceback
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, Query, HTTPException
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..models import (
    User, Event, Venue, RSVP, RSVPStatusEnum, SavedEvent,
    Group, GroupMembership, GroupRoleEnum,
)
from ..schemas import EventOut, EventCreate, RSVPOut, RSVPBody, FeedResponse
from ..auth import get_current_user
from ..services.feed import build_feed_event_out
from ..services.social import recompute_affinities

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
    if not body.venue_id and not body.venue:
        raise HTTPException(status_code=400, detail="Provide either venue_id or venue details")

    try:
        if body.group_id:
            group_result = await db.execute(
                select(Group)
                .options(selectinload(Group.members))
                .where(Group.id == body.group_id)
            )
            group = group_result.scalar_one_or_none()
            if not group:
                raise HTTPException(status_code=404, detail="Group not found")

            membership = next((m for m in group.members if m.user_id == current_user.id), None)
            if not membership or membership.role not in {GroupRoleEnum.owner, GroupRoleEnum.admin}:
                raise HTTPException(status_code=403, detail="Only group owners or admins can create group events")

        if body.venue_id:
            venue_result = await db.execute(select(Venue).where(Venue.id == body.venue_id))
            if not venue_result.scalar_one_or_none():
                raise HTTPException(status_code=404, detail="Venue not found")
            venue_id = body.venue_id
        else:
            v = body.venue
            venue_id = str(uuid.uuid4())
            db.add(Venue(id=venue_id, name=v.name, address=v.address, latitude=v.latitude, longitude=v.longitude))

        event_id = str(uuid.uuid4())
        db.add(Event(
            id=event_id,
            title=body.title,
            description=body.description,
            venue_id=venue_id,
            start_time=body.start_time,
            end_time=body.end_time,
            price_min=body.price_min,
            price_max=body.price_max,
            capacity=body.capacity,
            category=body.category,
            tags=body.tags,
            image_url=body.image_url,
            group_id=body.group_id,
            source="user_created",
            creator_id=current_user.id,
        ))
        await db.commit()

        result = await db.execute(
            select(Event).options(selectinload(Event.venue)).where(Event.id == event_id)
        )
        event = result.scalar_one()
        return await build_feed_event_out(event, current_user, db)
    except HTTPException:
        raise
    except Exception as exc:
        tb = traceback.format_exc()
        logger.error("create_event failed:\n%s", tb)
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}")


@router.delete("/{event_id}", status_code=204)
async def delete_event(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(Event).where(Event.id == event_id))
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    if event.creator_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can only delete your own events")
    await db.delete(event)
    await db.commit()


@router.post("/{event_id}/rsvp", response_model=RSVPOut)
async def rsvp_event(
    event_id: str,
    body: RSVPBody,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(Event).where(Event.id == event_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Event not found")

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
    background_tasks.add_task(recompute_affinities, current_user.id)
    return rsvp


@router.post("/{event_id}/save")
async def save_event(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = await db.execute(select(Event).where(Event.id == event_id))
    if not event.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Event not found")

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
