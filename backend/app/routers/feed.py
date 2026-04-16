from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db
from ..models import User
from ..schemas import FeedResponse
from ..auth import get_current_user
from ..config import settings
from ..services.feed import get_feed

router = APIRouter(prefix="/feed", tags=["feed"])


@router.get("", response_model=FeedResponse)
async def feed(
    lat: float = Query(settings.default_feed_lat, description="User latitude"),
    lng: float = Query(settings.default_feed_lng, description="User longitude"),
    radius: float = Query(8.0, description="Search radius in km"),
    cursor: str = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    events, next_cursor = await get_feed(
        user=current_user,
        lat=lat,
        lng=lng,
        radius_km=radius,
        db=db,
        cursor=cursor,
    )
    return FeedResponse(events=events, next_cursor=next_cursor)
