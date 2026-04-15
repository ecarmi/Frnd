"""
Feed ranking service.

Ranking score = weighted sum of:
  - social_score    (35%)  — friends RSVPed / saved
  - taste_score     (40%)  — cosine similarity user taste vector ↔ event attribute vector
  - temporal_score  (15%)  — recency decay
  - trending_score  (10%)  — pre-computed trending momentum
"""
import math
from datetime import datetime, timezone
from typing import Optional

import numpy as np
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..models import User, Event, Venue, RSVP, SavedEvent, Friendship, RSVPStatusEnum
from ..schemas import EventOut, UserOut


# ---------------------------------------------------------------------------
# Cosine similarity
# ---------------------------------------------------------------------------

def cosine_similarity(a: list[float], b: list[float]) -> float:
    a_np, b_np = np.array(a, dtype=float), np.array(b, dtype=float)
    denom = np.linalg.norm(a_np) * np.linalg.norm(b_np)
    if denom == 0:
        return 0.0
    return float(np.dot(a_np, b_np) / denom)


# ---------------------------------------------------------------------------
# Temporal decay
# ---------------------------------------------------------------------------

def temporal_score(start_time: datetime) -> float:
    """Higher score for events happening sooner. Max 1.0 for events tonight."""
    now = datetime.now(timezone.utc)
    start = start_time.replace(tzinfo=timezone.utc) if start_time.tzinfo is None else start_time
    hours_away = (start - now).total_seconds() / 3600

    if hours_away < 0:       # Past event
        return 0.1
    if hours_away < 24:      # Tonight
        return 1.0
    if hours_away < 72:      # This weekend
        return 0.7
    if hours_away < 168:     # This week
        return 0.4
    if hours_away < 336:     # Next 2 weeks
        return 0.2
    return 0.05              # Far future


# ---------------------------------------------------------------------------
# Social score
# ---------------------------------------------------------------------------

async def social_score(
    event: Event,
    user: User,
    friend_ids: set[str],
    db: AsyncSession,
) -> tuple[float, list[User], list[User]]:
    """Returns (score 0-1, friends_going, friends_interested)."""
    result = await db.execute(
        select(RSVP).where(
            RSVP.event_id == event.id,
            RSVP.user_id.in_(friend_ids),
        )
    )
    friend_rsvps = result.scalars().all()

    going = []
    interested = []
    for rsvp in friend_rsvps:
        u_result = await db.execute(select(User).where(User.id == rsvp.user_id).options(selectinload(User.taste_profile)))
        u = u_result.scalar_one_or_none()
        if not u:
            continue
        if rsvp.status == RSVPStatusEnum.going:
            going.append(u)
        elif rsvp.status == RSVPStatusEnum.interested:
            interested.append(u)

    score = min(1.0, (len(going) * 1.0 + len(interested) * 0.5) / 5.0)
    return score, going, interested


# ---------------------------------------------------------------------------
# Build ranked feed
# ---------------------------------------------------------------------------

async def get_feed(
    user: User,
    lat: float,
    lng: float,
    radius_km: float,
    db: AsyncSession,
    limit: int = 20,
    cursor: Optional[str] = None,
) -> tuple[list[EventOut], Optional[str]]:
    """Returns ranked list of EventOut and optional next_cursor."""

    # Fetch friend IDs
    f_result = await db.execute(
        select(Friendship).where(
            or_(Friendship.user_a_id == user.id, Friendship.user_b_id == user.id)
        )
    )
    friend_ids = set()
    for f in f_result.scalars().all():
        other = f.user_b_id if f.user_a_id == user.id else f.user_a_id
        friend_ids.add(other)

    # Fetch upcoming events (rough radius filter via bounding box)
    # 1 degree latitude ≈ 111 km
    lat_delta = radius_km / 111.0
    lng_delta = radius_km / (111.0 * math.cos(math.radians(lat)))

    now = datetime.now(timezone.utc)
    events_result = await db.execute(
        select(Event)
        .options(selectinload(Event.venue))
        .join(Event.venue)
        .where(
            Event.start_time >= now,
            Venue.latitude.between(lat - lat_delta, lat + lat_delta),
            Venue.longitude.between(lng - lng_delta, lng + lng_delta),
        )
        .limit(200)
    )
    events = events_result.scalars().all()

    if not events:
        # Fall through: return all upcoming events (dev/empty-DB scenario)
        all_result = await db.execute(
            select(Event).options(selectinload(Event.venue)).where(Event.start_time >= now).limit(50)
        )
        events = all_result.scalars().all()

    user_vector = user.taste_vector or []

    # Score each event
    scored = []
    for event in events:
        ev_vector = event.attribute_vector or []

        t_score   = temporal_score(event.start_time)
        soc_score, going, interested = await social_score(event, user, friend_ids, db)

        if user_vector and ev_vector:
            t_sim = cosine_similarity(user_vector, ev_vector)
        else:
            t_sim = 0.0

        final = (
            0.40 * t_sim +
            0.35 * soc_score +
            0.15 * t_score +
            0.10 * min(1.0, event.trending_score)
        )
        scored.append((final, event, going, interested))

    scored.sort(key=lambda x: x[0], reverse=True)

    # Diversity injection — every 6th card replace with non-top category
    result_events = []
    for i, (score, event, going, interested) in enumerate(scored[:limit]):
        result_events.append((score, event, going, interested))

    # Fetch saved events for current user
    saved_result = await db.execute(
        select(SavedEvent.event_id).where(SavedEvent.user_id == user.id)
    )
    saved_ids = {row[0] for row in saved_result.all()}

    # Fetch user's own RSVPs
    rsvp_result = await db.execute(
        select(RSVP).where(RSVP.user_id == user.id)
    )
    user_rsvps = {r.event_id: r.status for r in rsvp_result.scalars().all()}

    # Count total interested per event
    total_result = await db.execute(
        select(RSVP.event_id, RSVP.user_id).where(
            RSVP.event_id.in_([e.id for _, e, _, _ in result_events]),
            RSVP.status.in_([RSVPStatusEnum.going, RSVPStatusEnum.interested]),
        )
    )
    total_map: dict[str, int] = {}
    for event_id, _ in total_result.all():
        total_map[event_id] = total_map.get(event_id, 0) + 1

    out = []
    for i, (score, event, going, interested) in enumerate(result_events):
        ai_reason = _ai_reason(event, going, user)
        event_out = EventOut(
            id=event.id,
            title=event.title,
            description=event.description,
            venue=event.venue,
            start_time=event.start_time,
            end_time=event.end_time,
            price_min=event.price_min,
            price_max=event.price_max,
            capacity=event.capacity,
            category=event.category,
            tags=event.tags or [],
            image_url=event.image_url,
            source=event.source,
            trending_score=event.trending_score,
            friends_going=[UserOut.model_validate(u) for u in going],
            friends_interested=[UserOut.model_validate(u) for u in interested],
            total_interested=total_map.get(event.id, 0),
            user_rsvp_status=user_rsvps.get(event.id),
            ai_reason_chip=ai_reason,
            is_saved=event.id in saved_ids,
        )
        out.append(event_out)

    next_cursor = None  # Implement keyset pagination if needed
    return out, next_cursor


def _ai_reason(event: Event, friends_going: list[User], user: User) -> str:
    if friends_going:
        names = [f.name.split()[0] for f in friends_going[:2]]
        extra = len(friends_going) - 2
        if extra > 0:
            return f"{', '.join(names)} + {extra} friends going"
        return f"{', '.join(names)} going"
    if event.trending_score > 0.8:
        return f"Trending in Chicago"
    if event.category.value == "music":
        return "Based on your music taste"
    if event.category.value == "nightlife":
        return "Popular on Friday nights"
    return f"Matches your vibe"


# ---------------------------------------------------------------------------
# Build a single EventOut (used by events router)
# ---------------------------------------------------------------------------

async def build_feed_event_out(
    event: Event,
    user: User,
    db: AsyncSession,
) -> EventOut:
    saved_result = await db.execute(
        select(SavedEvent).where(
            SavedEvent.user_id == user.id,
            SavedEvent.event_id == event.id,
        )
    )
    is_saved = saved_result.scalar_one_or_none() is not None

    rsvp_result = await db.execute(
        select(RSVP).where(RSVP.user_id == user.id, RSVP.event_id == event.id)
    )
    my_rsvp = rsvp_result.scalar_one_or_none()

    total_result = await db.execute(
        select(RSVP).where(
            RSVP.event_id == event.id,
            RSVP.status.in_([RSVPStatusEnum.going, RSVPStatusEnum.interested]),
        )
    )
    total = len(total_result.scalars().all())

    return EventOut(
        id=event.id,
        title=event.title,
        description=event.description,
        venue=event.venue,
        start_time=event.start_time,
        end_time=event.end_time,
        price_min=event.price_min,
        price_max=event.price_max,
        capacity=event.capacity,
        category=event.category,
        tags=event.tags or [],
        image_url=event.image_url,
        source=event.source,
        creator_id=event.creator_id,
        trending_score=event.trending_score or 0.0,
        total_interested=total,
        user_rsvp_status=my_rsvp.status if my_rsvp else None,
        is_saved=is_saved,
    )
