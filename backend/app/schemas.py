from datetime import datetime
from typing import Optional
from pydantic import BaseModel

from .models import (
    EventCategoryEnum, EventTypeEnum, RSVPStatusEnum, FriendshipTierEnum,
    PlanStatusEnum, PlanMemberStatusEnum, MessageTypeEnum,
    GroupRoleEnum, ActivityTypeEnum, ActivityStatusEnum, CarpoolStatusEnum,
)


# ---------------------------------------------------------------------------
# Base helpers
# ---------------------------------------------------------------------------

class OrmBase(BaseModel):
    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# User
# ---------------------------------------------------------------------------

class TasteProfileOut(OrmBase):
    id: str
    user_id: str
    genre_weights: dict
    category_affinities: dict
    price_sensitivity: float
    time_preferences: dict
    human_readable_summary: Optional[str] = None
    updated_at: datetime


class UserOut(OrmBase):
    id: str
    email: Optional[str] = None
    phone: Optional[str] = None
    university: Optional[str] = None
    name: str
    avatar_url: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    onboarding_complete: bool
    created_at: datetime
    taste_profile: Optional[TasteProfileOut] = None


class UserUpdate(BaseModel):
    name: Optional[str] = None
    vibe_tag_ids: Optional[list[str]] = None


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

class OTPRequest(BaseModel):
    phone: Optional[str] = None  # kept for backward compat
    email: Optional[str] = None


class OTPVerify(BaseModel):
    phone: Optional[str] = None  # kept for backward compat
    email: Optional[str] = None
    code: str


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class OnboardingBody(BaseModel):
    name: Optional[str] = None
    vibe_tag_names: list[str]


# ---------------------------------------------------------------------------
# Venue
# ---------------------------------------------------------------------------

class VenueOut(OrmBase):
    id: str
    name: str
    latitude: float
    longitude: float
    address: str
    google_place_id: Optional[str] = None
    vibe_tags: list[str] = []
    images: list[str] = []
    claimed_by: Optional[str] = None
    created_at: datetime


# ---------------------------------------------------------------------------
# Event
# ---------------------------------------------------------------------------

class EventOut(OrmBase):
    id: str
    title: str
    description: str
    venue: VenueOut
    start_time: datetime
    end_time: Optional[datetime] = None
    price_min: Optional[float] = None
    price_max: Optional[float] = None
    capacity: Optional[int] = None
    category: EventCategoryEnum
    event_type: Optional[EventTypeEnum] = None
    group_id: Optional[str] = None
    tags: list[str] = []
    image_url: Optional[str] = None
    source: str
    creator_id: Optional[str] = None
    trending_score: float = 0.0
    # Feed extras
    friends_going: list[UserOut] = []
    friends_interested: list[UserOut] = []
    total_interested: int = 0
    user_rsvp_status: Optional[RSVPStatusEnum] = None
    ai_reason_chip: Optional[str] = None
    is_saved: bool = False


class VenueCreate(BaseModel):
    name: str
    address: str
    latitude: float
    longitude: float


class EventCreate(BaseModel):
    title: str
    description: str = ""
    venue_id: Optional[str] = None    # use existing venue
    venue: Optional[VenueCreate] = None  # or create inline
    start_time: datetime
    end_time: Optional[datetime] = None
    price_min: Optional[float] = None
    price_max: Optional[float] = None
    capacity: Optional[int] = None
    category: EventCategoryEnum = EventCategoryEnum.other
    tags: list[str] = []
    image_url: Optional[str] = None
    group_id: Optional[str] = None


class FeedResponse(BaseModel):
    events: list[EventOut]
    next_cursor: Optional[str] = None


# ---------------------------------------------------------------------------
# RSVP
# ---------------------------------------------------------------------------

class RSVPOut(OrmBase):
    id: str
    user_id: str
    event_id: str
    status: RSVPStatusEnum
    created_at: datetime


class RSVPBody(BaseModel):
    status: RSVPStatusEnum


# ---------------------------------------------------------------------------
# Friendship
# ---------------------------------------------------------------------------

class FriendshipOut(OrmBase):
    id: str
    user_a_id: str
    user_b_id: str
    tier: FriendshipTierEnum
    created_at: datetime
    other_user: Optional[UserOut] = None


# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------

class MessageOut(OrmBase):
    id: str
    plan_id: str
    user_id: str
    body: str
    type: MessageTypeEnum
    created_at: datetime
    sender: Optional[UserOut] = None


class PlanMemberOut(OrmBase):
    id: str
    plan_id: str
    user_id: str
    status: PlanMemberStatusEnum
    user: Optional[UserOut] = None


class PlanOut(OrmBase):
    id: str
    creator_id: str
    title: str
    event_options: list[EventOut] = []
    status: PlanStatusEnum
    meeting_time: Optional[datetime] = None
    meeting_location: Optional[str] = None
    members: list[PlanMemberOut] = []
    messages: list[MessageOut] = []
    created_at: datetime
    selected_event_id: Optional[str] = None
    invite_code: Optional[str] = None


class CreatePlanBody(BaseModel):
    title: str
    event_ids: list[str] = []
    invitee_ids: list[str] = []


class VoteBody(BaseModel):
    event_id: str


class MsgBody(BaseModel):
    body: str


class PlanStatusBody(BaseModel):
    status: PlanStatusEnum


class InviteBody(BaseModel):
    user_ids: list[str]


# ---------------------------------------------------------------------------
# Feedback
# ---------------------------------------------------------------------------

class SwipeBody(BaseModel):
    event_id: str
    direction: str  # "left" | "right"


# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------

class GroupMemberOut(OrmBase):
    id: str
    group_id: str
    user_id: str
    role: GroupRoleEnum
    created_at: datetime
    user: Optional[UserOut] = None


class GroupOut(OrmBase):
    id: str
    name: str
    description: str
    creator_id: str
    is_private: bool
    image_url: Optional[str] = None
    invite_code: Optional[str] = None
    created_at: datetime
    members: list[GroupMemberOut] = []
    member_count: int = 0


class GroupCreate(BaseModel):
    name: str
    description: str = ""
    is_private: bool = True


class GroupJoin(BaseModel):
    invite_code: str


# ---------------------------------------------------------------------------
# Activity Posts
# ---------------------------------------------------------------------------

class ActivityParticipantOut(OrmBase):
    id: str
    activity_id: str
    user_id: str
    created_at: datetime
    user: Optional[UserOut] = None


class ActivityPostOut(OrmBase):
    id: str
    creator_id: str
    title: str
    description: str
    activity_type: ActivityTypeEnum
    location: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    scheduled_time: Optional[datetime] = None
    max_participants: Optional[int] = None
    group_id: Optional[str] = None
    status: ActivityStatusEnum
    created_at: datetime
    creator: Optional[UserOut] = None
    participants: list[ActivityParticipantOut] = []
    participant_count: int = 0
    is_joined: bool = False


class ActivityPostCreate(BaseModel):
    title: str
    description: str = ""
    activity_type: ActivityTypeEnum = ActivityTypeEnum.social
    location: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    scheduled_time: Optional[datetime] = None
    max_participants: Optional[int] = None
    group_id: Optional[str] = None


# ---------------------------------------------------------------------------
# Carpooling
# ---------------------------------------------------------------------------

class CarpoolPassengerOut(OrmBase):
    id: str
    carpool_id: str
    user_id: str
    status: str
    created_at: datetime
    user: Optional[UserOut] = None


class CarpoolOut(OrmBase):
    id: str
    plan_id: str
    driver_id: str
    departure_location: str
    departure_latitude: Optional[float] = None
    departure_longitude: Optional[float] = None
    departure_time: Optional[datetime] = None
    total_seats: int
    notes: Optional[str] = None
    status: CarpoolStatusEnum
    created_at: datetime
    driver: Optional[UserOut] = None
    passengers: list[CarpoolPassengerOut] = []
    seats_available: int = 0


class CarpoolCreate(BaseModel):
    plan_id: str
    departure_location: str
    departure_latitude: Optional[float] = None
    departure_longitude: Optional[float] = None
    departure_time: Optional[datetime] = None
    total_seats: int = 3
    notes: Optional[str] = None
