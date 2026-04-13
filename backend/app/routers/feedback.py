from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import User, SwipeFeedback
from ..schemas import SwipeBody
from ..auth import get_current_user

router = APIRouter(prefix="/feedback", tags=["feedback"])


@router.post("/swipe")
async def record_swipe(
    body: SwipeBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    feedback = SwipeFeedback(
        user_id=current_user.id,
        event_id=body.event_id,
        direction=body.direction,
    )
    db.add(feedback)
    await db.commit()
    return {}
