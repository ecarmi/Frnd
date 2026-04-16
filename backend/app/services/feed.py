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
from ..enum_utils import enum_equals, enum_value


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

    # 1. Friend IDs — single query
    f_result = await db.execute(
        select(Friendship).where(
            or_(Friendship.user_a_id == user.id, Friendship.user_b_id == user.id)
        )
    )
    friend_ids: set[str] = set()
    for f in f_result.scalars().all():
        other = f.user_b_id if f.user_a_id == user.id else f.user_a_id
        friend_ids.add(other)

    # 2. Candidate events — single query with bounding box
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
        all_result = await db.execute(
            select(Event).options(selectinload(Event.venue)).where(Event.start_time >= now).limit(50)
        )
        events = all_result.scalars().all()

    if not events:
        return [], None

    event_ids = [e.id for e in events]

    # 3. All friend RSVPs across all candidate events — single batched query
    friend_rsvps_result = await db.execute(
        select(RSVP).where(
            RSVP.event_id.in_(event_ids),
            RSVP.user_id.in_(friend_ids),
        )
    ) if friend_ids else None

    friend_rsvps = friend_rsvps_result.scalars().all() if friend_rsvps_result else []

    # 4. Load the friend users referenced by those RSVPs — single batched query
    friend_user_ids = {r.user_id for r in friend_rsvps}
    friend_users: dict[str, User] = {}
    if friend_user_ids:
        users_result = await db.execute(
            select(User)
            .options(selectinload(User.taste_profile))
            .where(User.id.in_(friend_user_ids))
        )
        for u in users_result.scalars().all():
            friend_users[u.id] = u

    # 5. Build per-event social data from batched results
    going_map: dict[str, list[User]] = {eid: [] for eid in event_ids}
    interested_map: dict[str, list[User]] = {eid: [] for eid in event_ids}
    for rsvp in friend_rsvps:
        u = friend_users.get(rsvp.user_id)
        if not u:
            continue
        if enum_equals(rsvp.status, RSVPStatusEnum.going):
            going_map[rsvp.event_id].append(u)
        elif enum_equals(rsvp.status, RSVPStatusEnum.interested):
            interested_map[rsvp.event_id].append(u)

    # 6. User's own saved events and RSVPs — two queries (not per-event)
    saved_result = await db.execute(
        select(SavedEvent.event_id).where(SavedEvent.user_id == user.id)
    )
    saved_ids = {row[0] for row in saved_result.all()}

    rsvp_result = await db.execute(
        select(RSVP).where(RSVP.user_id == user.id)
    )
    user_rsvps = {r.event_id: r.status for r in rsvp_result.scalars().all()}

    # 7. Total interested counts — single batched query
    total_result = await db.execute(
        select(RSVP.event_id, RSVP.user_id).where(
            RSVP.event_id.in_(event_ids),
            RSVP.status.in_([RSVPStatusEnum.going.value, RSVPStatusEnum.interested.value]),
        )
    )
    total_map: dict[str, int] = {}
    for event_id, _ in total_result.all():
        total_map[event_id] = total_map.get(event_id, 0) + 1

    # 8. Score and rank
    user_vector = user.taste_vector or []
    scored = []
    for event in events:
        going = going_map.get(event.id, [])
        interested = interested_map.get(event.id, [])
        n_going, n_interested = len(going), len(interested)

        t_score = temporal_score(event.start_time)
        soc_score = min(1.0, (n_going * 1.0 + n_interested * 0.5) / 5.0)
        ev_vector = event.attribute_vector or []
        t_sim = cosine_similarity(user_vector, ev_vector) if user_vector and ev_vector else 0.0

        final = (
            0.40 * t_sim +
            0.35 * soc_score +
            0.15 * t_score +
            0.10 * min(1.0, event.trending_score or 0.0)
        )
        scored.append((final, event, going, interested))

    scored.sort(key=lambda x: x[0], reverse=True)

    # 9. Build output
    out = []
    for _, event, going, interested in scored[:limit]:
        ai_reason = _ai_reason(event, going, user)
        out.append(EventOut(
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
            trending_score=event.trending_score or 0.0,
            friends_going=[UserOut.model_validate(u) for u in going],
            friends_interested=[UserOut.model_validate(u) for u in interested],
            total_interested=total_map.get(event.id, 0),
            user_rsvp_status=user_rsvps.get(event.id),
            ai_reason_chip=ai_reason,
            is_saved=event.id in saved_ids,
        ))

    return out, None


def _ai_reason(event: Event, friends_going: list[User], user: User) -> str:
    category = enum_value(event.category)

    if friends_going:
        names = [f.name.split()[0] for f in friends_going[:2]]
        extra = len(friends_going) - 2
        if extra > 0:
            return f"{', '.join(names)} + {extra} friends going"
        return f"{', '.join(names)} going"
    if event.trending_score > 0.8:
        return f"Trending in Chicago"
    if category == "music":
        return "Based on your music taste"
    if category == "nightlife":
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
    # Load all RSVP state for this event so detail/saved/plan screens get the same
    # social payload shape as the main feed.
    rows = await db.execute(
        select(RSVP.event_id, RSVP.user_id, RSVP.status).where(
            RSVP.event_id == event.id,
        )
    )
    all_rsvps = rows.all()

    my_rsvp_status = None
    total = 0
    friend_status_by_id: dict[str, str] = {}
    for _, uid, status in all_rsvps:
        if uid == user.id:
            my_rsvp_status = status
        if enum_equals(status, RSVPStatusEnum.going) or enum_equals(status, RSVPStatusEnum.interested):
            total += 1
            friend_status_by_id[uid] = status

    saved_result = await db.execute(
        select(SavedEvent.event_id).where(
            SavedEvent.user_id == user.id,
            SavedEvent.event_id == event.id,
        )
    )
    is_saved = saved_result.scalar_one_or_none() is not None

    friendships_result = await db.execute(
        select(Friendship).where(
            or_(Friendship.user_a_id == user.id, Friendship.user_b_id == user.id)
        )
    )
    friend_ids: set[str] = set()
    for friendship in friendships_result.scalars().all():
        other_id = friendship.user_b_id if friendship.user_a_id == user.id else friendship.user_a_id
        if other_id in friend_status_by_id:
            friend_ids.add(other_id)

    friend_users: dict[str, User] = {}
    if friend_ids:
        users_result = await db.execute(
            select(User)
            .options(selectinload(User.taste_profile))
            .where(User.id.in_(friend_ids))
        )
        for friend in users_result.scalars().all():
            friend_users[friend.id] = friend

    friends_going_models: list[User] = []
    friends_interested_models: list[User] = []
    for uid, status in friend_status_by_id.items():
        friend = friend_users.get(uid)
        if not friend:
            continue
        if enum_equals(status, RSVPStatusEnum.going):
            friends_going_models.append(friend)
        elif enum_equals(status, RSVPStatusEnum.interested):
            friends_interested_models.append(friend)

    friends_going = [UserOut.model_validate(friend) for friend in friends_going_models]
    friends_interested = [UserOut.model_validate(friend) for friend in friends_interested_models]

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
        friends_going=friends_going,
        friends_interested=friends_interested,
        total_interested=total,
        user_rsvp_status=my_rsvp_status,
        ai_reason_chip=_ai_reason(event, friends_going_models, user),
        is_saved=is_saved,
    )
