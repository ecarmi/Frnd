import uuid

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
import json

from ..database import get_db
from ..models import User, Plan, PlanMember, PlanMemberStatusEnum, Message, Event
from ..schemas import (
    PlanOut, CreatePlanBody, VoteBody, MsgBody, PlanStatusBody, InviteBody,
    MessageOut, UserOut, EventOut
)
from ..auth import get_current_user, decode_token
from ..services.feed import build_feed_event_out

router = APIRouter(prefix="/plans", tags=["plans"])

# Simple in-memory WebSocket connection registry
# In production use Redis pub/sub
_connections: dict[str, list[WebSocket]] = {}


async def _load_plan_out(plan: Plan, db: AsyncSession, current_user: User) -> PlanOut:
    """Loads event details and member users for a plan."""
    event_outs = []
    for eid in (plan.event_ids or []):
        result = await db.execute(
            select(Event).options(selectinload(Event.venue)).where(Event.id == eid)
        )
        ev = result.scalar_one_or_none()
        if ev:
            event_outs.append(await build_feed_event_out(ev, current_user, db))

    return PlanOut(
        id=plan.id,
        creator_id=plan.creator_id,
        title=plan.title,
        event_options=event_outs,
        status=plan.status,
        meeting_time=plan.meeting_time,
        meeting_location=plan.meeting_location,
        invite_code=plan.invite_code,
        members=[
            _member_out(m) for m in plan.members
        ],
        messages=[
            MessageOut(
                id=m.id, plan_id=m.plan_id, user_id=m.user_id,
                body=m.body, type=m.type, created_at=m.created_at,
                sender=UserOut.model_validate(m.sender) if m.sender else None
            )
            for m in plan.messages
        ],
        created_at=plan.created_at,
        selected_event_id=plan.selected_event_id,
    )


def _member_out(m: PlanMember):
    from ..schemas import PlanMemberOut
    return PlanMemberOut(
        id=m.id, plan_id=m.plan_id, user_id=m.user_id, status=m.status,
        user=UserOut.model_validate(m.user) if m.user else None
    )


@router.get("", response_model=list[PlanOut])
async def list_plans(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .join(Plan.members)
        .where(PlanMember.user_id == current_user.id)
        .order_by(Plan.created_at.desc())
    )
    plans = result.scalars().unique().all()
    return [await _load_plan_out(p, db, current_user) for p in plans]


@router.post("", response_model=PlanOut, status_code=201)
async def create_plan(
    body: CreatePlanBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    plan_id = str(uuid.uuid4())
    db.add(Plan(
        id=plan_id,
        creator_id=current_user.id,
        title=body.title,
        event_ids=body.event_ids,
        status="voting" if len(body.event_ids) > 1 else "proposal",
    ))

    # Add creator as going
    db.add(PlanMember(plan_id=plan_id, user_id=current_user.id, status=PlanMemberStatusEnum.going))

    # Add invitees
    for uid in body.invitee_ids:
        db.add(PlanMember(plan_id=plan_id, user_id=uid, status=PlanMemberStatusEnum.invited))

    # System message
    db.add(Message(
        plan_id=plan_id, user_id=current_user.id,
        body=f"{current_user.name} created this plan",
        type="system"
    ))

    await db.commit()

    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .where(Plan.id == plan_id)
    )
    plan = result.scalar_one()
    return await _load_plan_out(plan, db, current_user)


@router.get("/{plan_id}", response_model=PlanOut)
async def get_plan(
    plan_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .where(Plan.id == plan_id)
    )
    plan = result.scalar_one_or_none()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    # Check membership
    member_ids = {m.user_id for m in plan.members}
    if current_user.id not in member_ids:
        raise HTTPException(status_code=403, detail="Not a member of this plan")

    return await _load_plan_out(plan, db, current_user)


@router.post("/{plan_id}/invite", response_model=PlanOut)
async def invite_to_plan(
    plan_id: str,
    body: InviteBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .where(Plan.id == plan_id)
    )
    plan = result.scalar_one_or_none()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    member_ids = {m.user_id for m in plan.members}
    if current_user.id not in member_ids:
        raise HTTPException(status_code=403, detail="Not a member of this plan")

    added_count = 0
    for uid in body.user_ids:
        if uid not in member_ids:
            db.add(PlanMember(plan_id=plan.id, user_id=uid, status=PlanMemberStatusEnum.invited))
            member_ids.add(uid)
            added_count += 1

    if added_count:
        db.add(Message(
            plan_id=plan.id, user_id=current_user.id,
            body=f"{current_user.name} invited {added_count} person{'s' if added_count > 1 else ''}",
            type="system"
        ))
        await db.commit()

    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .where(Plan.id == plan_id)
    )
    plan = result.scalar_one()
    return await _load_plan_out(plan, db, current_user)


@router.post("/{plan_id}/vote", response_model=PlanOut)
async def vote(
    plan_id: str,
    body: VoteBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages),
        )
        .where(Plan.id == plan_id)
    )
    plan = result.scalar_one_or_none()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")

    # Simple: first event to reach majority wins
    plan.selected_event_id = body.event_id
    plan.status = "locked"

    db.add(Message(
        plan_id=plan.id, user_id=current_user.id,
        body=f"{current_user.name} voted to lock in an event",
        type="system"
    ))

    await db.commit()

    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .where(Plan.id == plan_id)
    )
    plan = result.scalar_one()
    return await _load_plan_out(plan, db, current_user)


@router.post("/{plan_id}/messages", response_model=MessageOut)
async def send_message(
    plan_id: str,
    body: MsgBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    msg = Message(
        plan_id=plan_id,
        user_id=current_user.id,
        body=body.body,
        type="text",
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    # Broadcast to WebSocket connections for this plan
    if plan_id in _connections:
        payload = json.dumps({"type": "message", "user_id": current_user.id, "body": body.body})
        dead = []
        for ws in _connections[plan_id]:
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            _connections[plan_id].remove(ws)

    return MessageOut(
        id=msg.id, plan_id=msg.plan_id, user_id=msg.user_id,
        body=msg.body, type=msg.type, created_at=msg.created_at,
        sender=UserOut.model_validate(current_user),
    )


@router.patch("/{plan_id}/status", response_model=PlanOut)
async def update_status(
    plan_id: str,
    body: PlanStatusBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .where(Plan.id == plan_id)
    )
    plan = result.scalar_one_or_none()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found")
    if plan.creator_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the creator can update status")

    plan.status = body.status
    await db.commit()
    return await _load_plan_out(plan, db, current_user)


@router.post("/join/{invite_code}", response_model=PlanOut)
async def join_plan_by_code(
    invite_code: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .where(Plan.invite_code == invite_code)
    )
    plan = result.scalar_one_or_none()
    if not plan:
        raise HTTPException(status_code=404, detail="Invalid invite code")

    member_ids = {m.user_id for m in plan.members}
    if current_user.id in member_ids:
        return await _load_plan_out(plan, db, current_user)

    db.add(PlanMember(plan_id=plan.id, user_id=current_user.id, status=PlanMemberStatusEnum.invited))
    db.add(Message(
        plan_id=plan.id, user_id=current_user.id,
        body=f"{current_user.name} joined via invite link",
        type="system"
    ))
    await db.commit()

    result = await db.execute(
        select(Plan)
        .options(
            selectinload(Plan.members).selectinload(PlanMember.user).selectinload(User.taste_profile),
            selectinload(Plan.messages).selectinload(Message.sender),
        )
        .where(Plan.id == plan.id)
    )
    plan = result.scalar_one()
    return await _load_plan_out(plan, db, current_user)


@router.websocket("/{plan_id}/stream")
async def plan_stream(plan_id: str, websocket: WebSocket, token: str):
    """WebSocket for real-time plan chat."""
    try:
        user_id = decode_token(token)
    except Exception:
        await websocket.close(code=4001)
        return

    await websocket.accept()
    _connections.setdefault(plan_id, []).append(websocket)

    try:
        while True:
            data = await websocket.receive_text()
            # Echo to all connections in this plan room
            if plan_id in _connections:
                for ws in _connections[plan_id]:
                    if ws != websocket:
                        try:
                            await ws.send_text(data)
                        except Exception:
                            pass
    except WebSocketDisconnect:
        if plan_id in _connections:
            try:
                _connections[plan_id].remove(websocket)
            except ValueError:
                pass
