import secrets

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..database import get_db
from ..models import Group, GroupMembership, GroupRoleEnum, User
from ..schemas import GroupOut, GroupCreate, GroupJoin, GroupMemberOut, UserOut
from ..auth import get_current_user

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
        .options(selectinload(Group.memberships).selectinload(GroupMembership.user))
        .where(Group.id == group_id)
    )
    return result.scalar_one_or_none()


def _group_out(group: Group) -> GroupOut:
    members = [_member_out(m) for m in group.memberships]
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


@router.get("", response_model=list[GroupOut])
async def list_my_groups(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Group)
        .options(selectinload(Group.memberships).selectinload(GroupMembership.user))
        .join(Group.memberships)
        .where(GroupMembership.user_id == current_user.id)
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
    invite_code = secrets.token_urlsafe(8) if body.is_private else None
    group = Group(
        name=body.name,
        description=body.description,
        creator_id=current_user.id,
        is_private=body.is_private,
        invite_code=invite_code,
    )
    db.add(group)
    await db.flush()

    db.add(GroupMembership(group_id=group.id, user_id=current_user.id, role=GroupRoleEnum.owner))
    await db.commit()

    loaded = await _load_group(group.id, db)
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

    member_ids = {m.user_id for m in group.memberships}
    if group.is_private and current_user.id not in member_ids:
        raise HTTPException(status_code=403, detail="Private group")

    return _group_out(group)


@router.post("/join", response_model=GroupOut)
async def join_by_invite(
    body: GroupJoin,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Group)
        .options(selectinload(Group.memberships).selectinload(GroupMembership.user))
        .where(Group.invite_code == body.invite_code)
    )
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Invalid invite code")

    member_ids = {m.user_id for m in group.memberships}
    if current_user.id not in member_ids:
        db.add(GroupMembership(group_id=group.id, user_id=current_user.id, role=GroupRoleEnum.member))
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
    if membership.role == GroupRoleEnum.owner:
        raise HTTPException(status_code=400, detail="Owner cannot leave; delete the group instead")

    await db.delete(membership)
    await db.commit()
