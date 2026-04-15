import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..models import ActivityPost, ActivityParticipant, ActivityStatusEnum, User
from ..schemas import ActivityPostOut, ActivityPostCreate, ActivityParticipantOut, UserOut
from ..auth import get_current_user

router = APIRouter(prefix="/activities", tags=["activities"])


def _participant_out(p: ActivityParticipant) -> ActivityParticipantOut:
    return ActivityParticipantOut(
        id=p.id,
        activity_id=p.activity_id,
        user_id=p.user_id,
        created_at=p.created_at,
        user=UserOut.model_validate(p.user) if p.user else None,
    )


def _post_out(post: ActivityPost, current_user_id: str) -> ActivityPostOut:
    participants = [_participant_out(p) for p in post.participants]
    is_joined = any(p.user_id == current_user_id for p in post.participants)
    return ActivityPostOut(
        id=post.id,
        creator_id=post.creator_id,
        title=post.title,
        description=post.description,
        activity_type=post.activity_type,
        location=post.location,
        latitude=post.latitude,
        longitude=post.longitude,
        scheduled_time=post.scheduled_time,
        max_participants=post.max_participants,
        group_id=post.group_id,
        status=post.status,
        created_at=post.created_at,
        creator=UserOut.model_validate(post.creator) if post.creator else None,
        participants=participants,
        participant_count=len(participants),
        is_joined=is_joined,
    )


async def _load_post(post_id: str, db: AsyncSession) -> ActivityPost | None:
    result = await db.execute(
        select(ActivityPost)
        .options(
            selectinload(ActivityPost.creator).selectinload(User.taste_profile),
            selectinload(ActivityPost.participants).selectinload(ActivityParticipant.user).selectinload(User.taste_profile),
        )
        .where(ActivityPost.id == post_id)
    )
    return result.scalar_one_or_none()


@router.get("", response_model=list[ActivityPostOut])
async def list_activities(
    group_id: str | None = Query(default=None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = (
        select(ActivityPost)
        .options(
            selectinload(ActivityPost.creator).selectinload(User.taste_profile),
            selectinload(ActivityPost.participants).selectinload(ActivityParticipant.user).selectinload(User.taste_profile),
        )
        .where(ActivityPost.status == ActivityStatusEnum.open)
        .order_by(ActivityPost.scheduled_time.asc())
    )
    if group_id:
        q = q.where(ActivityPost.group_id == group_id)
    else:
        # Public feed: no group_id
        q = q.where(ActivityPost.group_id.is_(None))

    result = await db.execute(q)
    posts = result.scalars().unique().all()
    return [_post_out(p, current_user.id) for p in posts]


@router.post("", response_model=ActivityPostOut, status_code=201)
async def create_activity(
    body: ActivityPostCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    post_id = str(uuid.uuid4())
    db.add(ActivityPost(
        id=post_id,
        creator_id=current_user.id,
        title=body.title,
        description=body.description,
        activity_type=body.activity_type,
        location=body.location,
        latitude=body.latitude,
        longitude=body.longitude,
        scheduled_time=body.scheduled_time,
        max_participants=body.max_participants,
        group_id=body.group_id,
        status=ActivityStatusEnum.open,
    ))
    # Creator auto-joins
    db.add(ActivityParticipant(activity_id=post_id, user_id=current_user.id))
    await db.commit()

    loaded = await _load_post(post_id, db)
    return _post_out(loaded, current_user.id)


@router.get("/{post_id}", response_model=ActivityPostOut)
async def get_activity(
    post_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    post = await _load_post(post_id, db)
    if not post:
        raise HTTPException(status_code=404, detail="Activity not found")
    return _post_out(post, current_user.id)


@router.post("/{post_id}/join", response_model=ActivityPostOut)
async def join_activity(
    post_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    post = await _load_post(post_id, db)
    if not post:
        raise HTTPException(status_code=404, detail="Activity not found")
    if post.status != ActivityStatusEnum.open:
        raise HTTPException(status_code=400, detail="Activity is not open")

    already = any(p.user_id == current_user.id for p in post.participants)
    if already:
        raise HTTPException(status_code=400, detail="Already joined")

    if post.max_participants and len(post.participants) >= post.max_participants:
        raise HTTPException(status_code=400, detail="Activity is full")

    db.add(ActivityParticipant(activity_id=post_id, user_id=current_user.id))
    await db.commit()

    post = await _load_post(post_id, db)
    return _post_out(post, current_user.id)


@router.delete("/{post_id}/leave", status_code=204)
async def leave_activity(
    post_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(ActivityParticipant).where(
            ActivityParticipant.activity_id == post_id,
            ActivityParticipant.user_id == current_user.id,
        )
    )
    participant = result.scalar_one_or_none()
    if not participant:
        raise HTTPException(status_code=404, detail="Not joined")

    await db.delete(participant)
    await db.commit()


@router.delete("/{post_id}", status_code=204)
async def delete_activity(
    post_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    post = await _load_post(post_id, db)
    if not post:
        raise HTTPException(status_code=404, detail="Activity not found")
    if post.creator_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not the creator")

    post.status = ActivityStatusEnum.cancelled
    await db.commit()
