import secrets
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..enum_utils import enum_equals
from ..models import Group, GroupMembership, GroupRoleEnum, User, Event, ActivityPost
from ..schemas import (
    GroupOut, GroupCreate, GroupJoin, GroupUpdate, GroupMemberRoleUpdate,
    GroupMemberOut, UserOut,
)
from ..auth import get_current_user
from ..services.social import recompute_affinities

router = APIRouter(prefix="/groups", tags=["groups"])


def _member_out(m: GroupMembership) -> GroupMemberOut:
    return GroupMemberOut(
        id=m.id,
        group_id=m.group_id,
        user_id=m.user_id,
        role=m.role,
        created_at=m.created_at,
        user=UserOut.model_validate(m.user) if m.user else None,
    )


async def _load_group(group_id: str, db: AsyncSession) -> Group | None:
    result = await db.execute(
        select(Group)
        .options(selectinload(Group.members).selectinload(GroupMembership.user).selectinload(User.taste_profile))
        .where(Group.id == group_id)
    )
    return result.scalar_one_or_none()


def _group_out(group: Group) -> GroupOut:
    members = [_member_out(m) for m in group.members]
    return GroupOut(
        id=group.id,
        name=group.name,
        description=group.description,
        creator_id=group.creator_id,
        is_private=group.is_private,
        image_url=group.image_url,
        invite_code=group.invite_code,
        created_at=group.created_at,
        members=members,
        member_count=len(members),
    )


def _membership_for_user(group: Group, user_id: str) -> GroupMembership | None:
    for membership in group.members:
        if membership.user_id == user_id:
            return membership
    return None


def _require_group_role(group: Group, user_id: str, allowed_roles: set[GroupRoleEnum]) -> GroupMembership:
    membership = _membership_for_user(group, user_id)
    if not membership or membership.role not in allowed_roles:
        raise HTTPException(status_code=403, detail="Insufficient group permissions")
    return membership


@router.get("", response_model=list[GroupOut])
async def list_my_groups(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Group)
        .options(selectinload(Group.members).selectinload(GroupMembership.user).selectinload(User.taste_profile))
        .join(Group.members)
        .where(GroupMembership.user_id == current_user.id)
        .order_by(Group.created_at.desc())
    )
    groups = result.scalars().unique().all()
    return [_group_out(g) for g in groups]


@router.get("/public", response_model=list[GroupOut])
async def list_public_groups(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Group)
        .options(selectinload(Group.members).selectinload(GroupMembership.user).selectinload(User.taste_profile))
        .where(Group.is_private == False)
        .order_by(Group.created_at.desc())
    )
    groups = result.scalars().unique().all()
    return [_group_out(g) for g in groups]


@router.post("", response_model=GroupOut, status_code=201)
async def create_group(
    body: GroupCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    group_id = str(uuid.uuid4())
    invite_code = secrets.token_urlsafe(8) if body.is_private else None
    db.add(Group(
        id=group_id,
        name=body.name,
        description=body.description,
        creator_id=current_user.id,
        is_private=body.is_private,
        invite_code=invite_code,
    ))
    db.add(GroupMembership(group_id=group_id, user_id=current_user.id, role=GroupRoleEnum.owner))
    await db.commit()

    loaded = await _load_group(group_id, db)
    return _group_out(loaded)


@router.get("/{group_id}", response_model=GroupOut)
async def get_group(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    group = await _load_group(group_id, db)
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    member_ids = {m.user_id for m in group.members}
    if group.is_private and current_user.id not in member_ids:
        raise HTTPException(status_code=403, detail="Private group")

    return _group_out(group)


@router.post("/join", response_model=GroupOut)
async def join_by_invite(
    body: GroupJoin,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Group)
        .options(selectinload(Group.members).selectinload(GroupMembership.user).selectinload(User.taste_profile))
        .where(Group.invite_code == body.invite_code)
    )
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Invalid invite code")

    member_ids = {m.user_id for m in group.members}
    if current_user.id not in member_ids:
        db.add(GroupMembership(group_id=group.id, user_id=current_user.id, role=GroupRoleEnum.member))
        await db.commit()
        group = await _load_group(group.id, db)
        background_tasks.add_task(recompute_affinities, current_user.id)

    return _group_out(group)


@router.post("/{group_id}/join", response_model=GroupOut)
async def join_public_group(
    group_id: str,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    group = await _load_group(group_id, db)
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    if group.is_private:
        raise HTTPException(status_code=400, detail="Private groups require an invite code")

    if not _membership_for_user(group, current_user.id):
        db.add(GroupMembership(group_id=group.id, user_id=current_user.id, role=GroupRoleEnum.member))
        await db.commit()
        group = await _load_group(group.id, db)
        background_tasks.add_task(recompute_affinities, current_user.id)

    return _group_out(group)


@router.patch("/{group_id}", response_model=GroupOut)
async def update_group(
    group_id: str,
    body: GroupUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    group = await _load_group(group_id, db)
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    _require_group_role(group, current_user.id, {GroupRoleEnum.owner, GroupRoleEnum.admin})

    if body.name is not None:
        trimmed_name = body.name.strip()
        if trimmed_name:
            group.name = trimmed_name
    if body.description is not None:
        group.description = body.description.strip()

    await db.commit()
    group = await _load_group(group.id, db)
    return _group_out(group)


@router.patch("/{group_id}/members/{user_id}", response_model=GroupOut)
async def update_group_member_role(
    group_id: str,
    user_id: str,
    body: GroupMemberRoleUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    group = await _load_group(group_id, db)
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    owner_membership = _require_group_role(group, current_user.id, {GroupRoleEnum.owner})
    target_membership = _membership_for_user(group, user_id)
    if not target_membership:
        raise HTTPException(status_code=404, detail="Member not found")

    if body.role == GroupRoleEnum.owner:
        if target_membership.user_id == current_user.id:
            raise HTTPException(status_code=400, detail="You already own this group")
        owner_membership.role = GroupRoleEnum.admin
        target_membership.role = GroupRoleEnum.owner
        group.creator_id = target_membership.user_id
    else:
        if target_membership.user_id == current_user.id:
            raise HTTPException(status_code=400, detail="Use ownership transfer instead")
        if enum_equals(target_membership.role, GroupRoleEnum.owner):
            raise HTTPException(status_code=400, detail="Transfer ownership before changing the owner role")
        target_membership.role = body.role

    await db.commit()
    group = await _load_group(group.id, db)
    return _group_out(group)


@router.delete("/{group_id}/leave", status_code=204)
async def leave_group(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(GroupMembership).where(
            GroupMembership.group_id == group_id,
            GroupMembership.user_id == current_user.id,
        )
    )
    membership = result.scalar_one_or_none()
    if not membership:
        raise HTTPException(status_code=404, detail="Not a member")
    if enum_equals(membership.role, GroupRoleEnum.owner):
        raise HTTPException(status_code=400, detail="Owner cannot leave; delete the group instead")

    await db.delete(membership)
    await db.commit()


@router.delete("/{group_id}", status_code=204)
async def delete_group(
    group_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    group = await _load_group(group_id, db)
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")

    _require_group_role(group, current_user.id, {GroupRoleEnum.owner})

    events_result = await db.execute(select(Event).where(Event.group_id == group.id))
    for event in events_result.scalars().all():
        event.group_id = None

    activities_result = await db.execute(select(ActivityPost).where(ActivityPost.group_id == group.id))
    for activity in activities_result.scalars().all():
        activity.group_id = None

    await db.delete(group)
    await db.commit()
