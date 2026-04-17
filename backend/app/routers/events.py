import logging
import traceback
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, Query, HTTPException
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)
from sqlalchemy import select, and_, or_, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..models import (
    User, Event, Venue, RSVP, RSVPStatusEnum, SavedEvent, ActivityPost,
    Group, GroupMembership, GroupRoleEnum,
)
from ..schemas import EventOut, EventCreate, RSVPOut, RSVPBody, FeedResponse
from ..schemas import UserOut
from ..auth import get_current_user
from ..services.feed import build_feed_event_out
from ..services.social import recompute_affinities

router = APIRouter(prefix="/events", tags=["events"])


async def _can_manage_event(event: Event, current_user: User, db: AsyncSession) -> bool:
    if event.creator_id == current_user.id:
        return True

    if not event.group_id:
        return False

    membership_result = await db.execute(
        select(GroupMembership).where(
            GroupMembership.group_id == event.group_id,
            GroupMembership.user_id == current_user.id,
        )
    )
    membership = membership_result.scalar_one_or_none()
    return bool(membership and membership.role in {GroupRoleEnum.owner, GroupRoleEnum.admin})


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


@router.get("/{event_id}/attendees", response_model=list[UserOut])
async def get_event_attendees(
    event_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event_result = await db.execute(select(Event).where(Event.id == event_id))
    event = event_result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    result = await db.execute(
        select(User)
        .join(RSVP, RSVP.user_id == User.id)
        .options(selectinload(User.taste_profile))
        .where(
            RSVP.event_id == event_id,
            RSVP.status == RSVPStatusEnum.going.value,
        )
        .order_by(RSVP.created_at.asc())
    )
    attendees = result.scalars().unique().all()
    return [UserOut.model_validate(attendee) for attendee in attendees]


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
    if not await _can_manage_event(event, current_user, db):
        raise HTTPException(status_code=403, detail="You can only manage events you created or group events you administer")
    await db.delete(event)
    await db.commit()


@router.patch("/{event_id}", response_model=EventOut)
async def update_event(
    event_id: str,
    body: EventCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Event)
        .options(selectinload(Event.venue))
        .where(Event.id == event_id)
    )
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    if not await _can_manage_event(event, current_user, db):
        raise HTTPException(status_code=403, detail="You can only manage events you created or group events you administer")

    if body.venue_id:
        venue_result = await db.execute(select(Venue).where(Venue.id == body.venue_id))
        venue = venue_result.scalar_one_or_none()
        if not venue:
            raise HTTPException(status_code=404, detail="Venue not found")
        event.venue_id = body.venue_id
    elif body.venue:
        if event.venue is None:
            venue_id = str(uuid.uuid4())
            db.add(Venue(
                id=venue_id,
                name=body.venue.name,
                address=body.venue.address,
                latitude=body.venue.latitude,
                longitude=body.venue.longitude,
            ))
            event.venue_id = venue_id
        else:
            event.venue.name = body.venue.name
            event.venue.address = body.venue.address
            event.venue.latitude = body.venue.latitude
            event.venue.longitude = body.venue.longitude

    event.title = body.title
    event.description = body.description
    event.start_time = body.start_time
    event.end_time = body.end_time
    event.price_min = body.price_min
    event.price_max = body.price_max
    event.capacity = body.capacity
    event.category = body.category
    event.tags = body.tags
    event.image_url = body.image_url
    event.group_id = body.group_id if body.group_id is not None else event.group_id

    await db.commit()

    refreshed_result = await db.execute(
        select(Event)
        .options(selectinload(Event.venue))
        .where(Event.id == event_id)
    )
    refreshed = refreshed_result.scalar_one()
    return await build_feed_event_out(refreshed, current_user, db)


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
    if event_id.startswith("activity:"):
        activity_id = event_id.removeprefix("activity:")
        activity = await db.execute(select(ActivityPost).where(ActivityPost.id == activity_id))
        if not activity.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Activity not found")

        existing = await db.execute(
            select(SavedEvent).where(
                SavedEvent.user_id == current_user.id,
                SavedEvent.activity_id == activity_id,
            )
        )
        if not existing.scalar_one_or_none():
            db.add(SavedEvent(user_id=current_user.id, activity_id=activity_id))
            await db.commit()
        return {}

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
    if event_id.startswith("activity:"):
        activity_id = event_id.removeprefix("activity:")
        existing = await db.execute(
            select(SavedEvent).where(
                SavedEvent.user_id == current_user.id,
                SavedEvent.activity_id == activity_id,
            )
        )
        saved = existing.scalar_one_or_none()
        if saved:
            await db.delete(saved)
            await db.commit()
        return {}

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
