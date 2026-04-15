from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..models import User, Friendship, TasteProfile, SavedEvent, Event, RSVP, RSVPStatusEnum
from ..schemas import UserOut, UserUpdate, FriendshipOut, OnboardingBody, EventOut
from ..services.feed import build_feed_event_out
from ..auth import get_current_user

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserOut)
async def get_me(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User)
        .options(selectinload(User.taste_profile))
        .where(User.id == current_user.id)
    )
    return result.scalar_one()


@router.patch("/me", response_model=UserOut)
async def update_me(
    body: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if body.name is not None:
        current_user.name = body.name
    await db.commit()
    result = await db.execute(
        select(User).where(User.id == current_user.id).options(selectinload(User.taste_profile))
    )
    return result.scalar_one()


@router.post("/me/onboarding", response_model=UserOut)
async def complete_onboarding(
    body: OnboardingBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Map vibe tag names → category affinities
    category_map = {
        "Live Music": "music", "DJ / Dance": "music", "Jazz & Soul": "music",
        "Party": "nightlife", "Bar Hopping": "nightlife", "Rooftops": "nightlife",
        "Comedy": "arts", "Art & Design": "arts", "Film & Theater": "arts",
        "Brunch": "food_drink", "Food Pop-ups": "food_drink",
        "Sports": "sports", "Fitness": "sports",
        "Study": "other", "Networking": "other",
    }
    affinities: dict[str, float] = {}
    for tag in body.vibe_tag_names:
        cat = category_map.get(tag)
        if cat:
            affinities[cat] = affinities.get(cat, 0.0) + 1.0

    # Normalize
    max_val = max(affinities.values(), default=1.0)
    affinities = {k: v / max_val for k, v in affinities.items()}

    result = await db.execute(
        select(TasteProfile).where(TasteProfile.user_id == current_user.id)
    )
    taste = result.scalar_one_or_none()
    if taste:
        taste.category_affinities = affinities
        summary_cats = sorted(affinities.items(), key=lambda x: x[1], reverse=True)[:3]
        taste.human_readable_summary = "You lean toward: " + ", ".join(
            c.replace("_", " & ") for c, _ in summary_cats
        )
    current_user.onboarding_complete = True

    await db.commit()
    result = await db.execute(
        select(User).where(User.id == current_user.id).options(selectinload(User.taste_profile))
    )
    return result.scalar_one()


@router.get("/me/friends", response_model=list[FriendshipOut])
async def get_friends(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Friendship).where(
            or_(
                Friendship.user_a_id == current_user.id,
                Friendship.user_b_id == current_user.id,
            )
        )
    )
    friendships = result.scalars().all()

    out = []
    for f in friendships:
        other_id = f.user_b_id if f.user_a_id == current_user.id else f.user_a_id
        other_result = await db.execute(select(User).where(User.id == other_id).options(selectinload(User.taste_profile)))
        other = other_result.scalar_one_or_none()
        item = FriendshipOut.model_validate(f)
        item.other_user = UserOut.model_validate(other) if other else None
        out.append(item)
    return out


@router.get("/me/saved", response_model=list[EventOut])
async def get_saved_events(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Event)
        .options(selectinload(Event.venue))
        .join(SavedEvent, SavedEvent.event_id == Event.id)
        .where(SavedEvent.user_id == current_user.id)
        .order_by(SavedEvent.created_at.desc())
    )
    events = result.scalars().all()
    return [await build_feed_event_out(e, current_user, db) for e in events]


@router.get("/me/attended", response_model=list[EventOut])
async def get_attended_events(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(Event)
        .options(selectinload(Event.venue))
        .join(RSVP, RSVP.event_id == Event.id)
        .where(
            RSVP.user_id == current_user.id,
            RSVP.status == RSVPStatusEnum.going.value,
            Event.start_time < now,
        )
        .order_by(Event.start_time.desc())
    )
    events = result.scalars().all()
    return [await build_feed_event_out(e, current_user, db) for e in events]


@router.get("/me/events", response_model=list[EventOut])
async def get_my_created_events(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Event)
        .options(selectinload(Event.venue))
        .where(Event.creator_id == current_user.id)
        .order_by(Event.start_time.desc())
    )
    events = result.scalars().all()
    return [await build_feed_event_out(e, current_user, db) for e in events]
