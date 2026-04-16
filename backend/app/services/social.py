"""
Implicit social graph — computes pairwise affinity scores from in-app behaviour
and upserts them into the friendships table.

Affinity formula (90-day window):
  score = shared_plans × 3 + shared_rsvps × 1 + shared_groups × 0.5

Tier thresholds:
  inner_circle  ≥ 8
  friend        ≥ 3
  connection    ≥ 1  (below 1 → row deleted)

Always called as a FireAndForget background task — never blocks a request.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, or_, delete
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import AsyncSessionLocal
from ..models import (
    Friendship,
    FriendshipTierEnum,
    GroupMembership,
    PlanMember,
    PlanMemberStatusEnum,
    RSVP,
    RSVPStatusEnum,
)

logger = logging.getLogger(__name__)

_WINDOW_DAYS = 90
_PLAN_WEIGHT = 3.0
_RSVP_WEIGHT = 1.0
_GROUP_WEIGHT = 0.5

_TIER_INNER = 8.0
_TIER_FRIEND = 3.0
_TIER_CONNECTION = 1.0


def _tier(score: float) -> FriendshipTierEnum:
    if score >= _TIER_INNER:
        return FriendshipTierEnum.inner_circle
    if score >= _TIER_FRIEND:
        return FriendshipTierEnum.friend
    return FriendshipTierEnum.connection


def _canonical(a: str, b: str) -> tuple[str, str]:
    """Ensure user_a_id < user_b_id so each pair has exactly one row."""
    return (a, b) if a < b else (b, a)


async def recompute_affinities(user_id: str) -> None:
    """Recompute affinity scores for all users who share activity with user_id."""
    try:
        async with AsyncSessionLocal() as db:
            await _recompute(user_id, db)
    except Exception:
        logger.exception("recompute_affinities failed for user %s", user_id)


async def _recompute(user_id: str, db: AsyncSession) -> None:
    cutoff = datetime.now(timezone.utc) - timedelta(days=_WINDOW_DAYS)
    scores: dict[str, float] = {}

    # --- Co-plan members ---
    my_plan_rows = await db.execute(
        select(PlanMember.plan_id).where(
            PlanMember.user_id == user_id,
            PlanMember.status.in_([
                PlanMemberStatusEnum.going.value,
                PlanMemberStatusEnum.maybe.value,
            ]),
        )
    )
    my_plan_ids = [r[0] for r in my_plan_rows.all()]

    if my_plan_ids:
        co_plan_rows = await db.execute(
            select(PlanMember.user_id).where(
                PlanMember.plan_id.in_(my_plan_ids),
                PlanMember.user_id != user_id,
                PlanMember.status.in_([
                    PlanMemberStatusEnum.going.value,
                    PlanMemberStatusEnum.maybe.value,
                ]),
            )
        )
        for (uid,) in co_plan_rows.all():
            scores[uid] = scores.get(uid, 0.0) + _PLAN_WEIGHT

    # --- Co-RSVP (both going or interested to same event, within window) ---
    my_rsvp_rows = await db.execute(
        select(RSVP.event_id).where(
            RSVP.user_id == user_id,
            RSVP.status.in_([RSVPStatusEnum.going.value, RSVPStatusEnum.interested.value]),
            RSVP.created_at >= cutoff,
        )
    )
    my_event_ids = [r[0] for r in my_rsvp_rows.all()]

    if my_event_ids:
        co_rsvp_rows = await db.execute(
            select(RSVP.user_id).where(
                RSVP.event_id.in_(my_event_ids),
                RSVP.user_id != user_id,
                RSVP.status.in_([RSVPStatusEnum.going.value, RSVPStatusEnum.interested.value]),
            )
        )
        for (uid,) in co_rsvp_rows.all():
            scores[uid] = scores.get(uid, 0.0) + _RSVP_WEIGHT

    # --- Co-group members ---
    my_group_rows = await db.execute(
        select(GroupMembership.group_id).where(GroupMembership.user_id == user_id)
    )
    my_group_ids = [r[0] for r in my_group_rows.all()]

    if my_group_ids:
        co_group_rows = await db.execute(
            select(GroupMembership.user_id).where(
                GroupMembership.group_id.in_(my_group_ids),
                GroupMembership.user_id != user_id,
            )
        )
        for (uid,) in co_group_rows.all():
            scores[uid] = scores.get(uid, 0.0) + _GROUP_WEIGHT

    if not scores:
        return

    # Load existing friendship rows for this user
    existing_rows = await db.execute(
        select(Friendship).where(
            or_(Friendship.user_a_id == user_id, Friendship.user_b_id == user_id)
        )
    )
    existing: dict[tuple[str, str], Friendship] = {}
    for f in existing_rows.scalars().all():
        existing[_canonical(f.user_a_id, f.user_b_id)] = f

    # Upsert / delete
    touched_pairs: set[tuple[str, str]] = set()
    for other_id, score in scores.items():
        pair = _canonical(user_id, other_id)
        touched_pairs.add(pair)

        if score < _TIER_CONNECTION:
            # Below threshold — remove if present
            if pair in existing:
                await db.delete(existing[pair])
            continue

        tier = _tier(score)
        if pair in existing:
            f = existing[pair]
            f.affinity_score = score
            f.tier = tier
        else:
            a, b = pair
            db.add(Friendship(user_a_id=a, user_b_id=b, tier=tier, affinity_score=score))

    # Remove rows for pairs no longer in the score set (stale)
    for pair, f in existing.items():
        if pair not in touched_pairs:
            await db.delete(f)

    await db.commit()
