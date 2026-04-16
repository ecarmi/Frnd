from datetime import datetime
from typing import Optional
from sqlalchemy import (
    String, Float, Integer, Boolean, DateTime, ForeignKey,
    JSON, Text, func
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum
import uuid
import secrets

from .database import Base
from .sqlalchemy_types import EnumString


def new_uuid() -> str:
    return str(uuid.uuid4())


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class EventCategoryEnum(str, enum.Enum):
    music      = "music"
    nightlife  = "nightlife"
    food_drink = "food_drink"
    arts       = "arts"
    sports     = "sports"
    speaker    = "speaker"
    networking = "networking"
    other      = "other"


class EventTypeEnum(str, enum.Enum):
    """Structured taxonomy sitting above category."""
    study         = "study"
    social        = "social"
    sports        = "sports"
    food          = "food"
    career        = "career"
    entertainment = "entertainment"
    creative      = "creative"
    wellness      = "wellness"
    other         = "other"


class GroupRoleEnum(str, enum.Enum):
    owner  = "owner"
    admin  = "admin"
    member = "member"


class ActivityTypeEnum(str, enum.Enum):
    study       = "study"
    sports      = "sports"
    food        = "food"
    social      = "social"
    creative    = "creative"
    wellness    = "wellness"
    other       = "other"


class ActivityStatusEnum(str, enum.Enum):
    open      = "open"
    full      = "full"
    cancelled = "cancelled"
    completed = "completed"


class CarpoolStatusEnum(str, enum.Enum):
    open      = "open"
    full      = "full"
    cancelled = "cancelled"


class RSVPStatusEnum(str, enum.Enum):
    going      = "going"
    interested = "interested"
    not_going  = "not_going"


class FriendshipTierEnum(str, enum.Enum):
    inner_circle = "inner_circle"
    friend       = "friend"
    connection   = "connection"


class PlanStatusEnum(str, enum.Enum):
    proposal = "proposal"
    voting   = "voting"
    locked   = "locked"
    live     = "live"
    archived = "archived"


class PlanMemberStatusEnum(str, enum.Enum):
    invited  = "invited"
    going    = "going"
    maybe    = "maybe"
    declined = "declined"


class MessageTypeEnum(str, enum.Enum):
    text   = "text"
    image  = "image"
    system = "system"


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class User(Base):
    __tablename__ = "users"

    id: Mapped[str]              = mapped_column(String, primary_key=True, default=new_uuid)
    email: Mapped[Optional[str]] = mapped_column(String(254), unique=True, nullable=True)
    phone: Mapped[Optional[str]] = mapped_column(String(20), unique=True, nullable=True)
    university: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    name: Mapped[str]            = mapped_column(String(120), nullable=False, default="")
    avatar_url: Mapped[Optional[str]] = mapped_column(String(500))
    latitude: Mapped[Optional[float]]  = mapped_column(Float)
    longitude: Mapped[Optional[float]] = mapped_column(Float)
    # 128-dim taste vector stored as JSON array
    taste_vector: Mapped[Optional[list]] = mapped_column(JSON)
    spotify_token: Mapped[Optional[str]] = mapped_column(String(500))
    onboarding_complete: Mapped[bool]    = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime]         = mapped_column(DateTime(timezone=True), server_default=func.now())

    rsvps:       Mapped[list["RSVP"]]       = relationship(back_populates="user")
    taste_profile: Mapped[Optional["TasteProfile"]] = relationship(back_populates="user", uselist=False)


class TasteProfile(Base):
    __tablename__ = "taste_profiles"

    id: Mapped[str]      = mapped_column(String, primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), unique=True)
    genre_weights: Mapped[dict]       = mapped_column(JSON, default=dict)
    category_affinities: Mapped[dict] = mapped_column(JSON, default=dict)
    price_sensitivity: Mapped[float]  = mapped_column(Float, default=0.5)
    time_preferences: Mapped[dict]    = mapped_column(JSON, default=dict)
    human_readable_summary: Mapped[Optional[str]] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped["User"] = relationship(back_populates="taste_profile")


class Venue(Base):
    __tablename__ = "venues"

    id: Mapped[str]      = mapped_column(String, primary_key=True, default=new_uuid)
    name: Mapped[str]    = mapped_column(String(200), nullable=False)
    latitude: Mapped[float]  = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    address: Mapped[str]     = mapped_column(String(500), nullable=False, default="")
    google_place_id: Mapped[Optional[str]] = mapped_column(String(200))
    vibe_tags: Mapped[list]    = mapped_column(JSON, default=list)
    images: Mapped[list]       = mapped_column(JSON, default=list)
    claimed_by: Mapped[Optional[str]] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    events: Mapped[list["Event"]] = relationship(back_populates="venue")


class Event(Base):
    __tablename__ = "events"

    id: Mapped[str]         = mapped_column(String, primary_key=True, default=new_uuid)
    title: Mapped[str]      = mapped_column(String(300), nullable=False)
    description: Mapped[str] = mapped_column(Text, default="")
    venue_id: Mapped[str]   = mapped_column(ForeignKey("venues.id"), nullable=False)
    start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_time: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    price_min: Mapped[Optional[float]]   = mapped_column(Float)
    price_max: Mapped[Optional[float]]   = mapped_column(Float)
    capacity: Mapped[Optional[int]]      = mapped_column(Integer)
    category: Mapped[EventCategoryEnum]  = mapped_column(EnumString(EventCategoryEnum), default=EventCategoryEnum.other)
    event_type: Mapped[Optional[EventTypeEnum]] = mapped_column(EnumString(EventTypeEnum), nullable=True)
    group_id: Mapped[Optional[str]] = mapped_column(ForeignKey("groups.id"), nullable=True)
    tags: Mapped[list]      = mapped_column(JSON, default=list)
    image_url: Mapped[Optional[str]] = mapped_column(String(500))
    source: Mapped[str]     = mapped_column(String(50), default="organic")
    creator_id: Mapped[Optional[str]] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    # 128-dim attribute vector
    attribute_vector: Mapped[Optional[list]] = mapped_column(JSON)
    trending_score: Mapped[float] = mapped_column(Float, default=0.0)
    created_at: Mapped[datetime]  = mapped_column(DateTime(timezone=True), server_default=func.now())

    venue: Mapped["Venue"]   = relationship(back_populates="events")
    rsvps: Mapped[list["RSVP"]] = relationship(back_populates="event")


class RSVP(Base):
    __tablename__ = "rsvps"

    id: Mapped[str]         = mapped_column(String, primary_key=True, default=new_uuid)
    user_id: Mapped[str]    = mapped_column(ForeignKey("users.id"), nullable=False)
    event_id: Mapped[str]   = mapped_column(ForeignKey("events.id"), nullable=False)
    status: Mapped[RSVPStatusEnum] = mapped_column(EnumString(RSVPStatusEnum))
    created_at: Mapped[datetime]   = mapped_column(DateTime(timezone=True), server_default=func.now())

    user:  Mapped["User"]  = relationship(back_populates="rsvps")
    event: Mapped["Event"] = relationship(back_populates="rsvps")


class Friendship(Base):
    __tablename__ = "friendships"

    id: Mapped[str]       = mapped_column(String, primary_key=True, default=new_uuid)
    user_a_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    user_b_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    tier: Mapped[FriendshipTierEnum] = mapped_column(EnumString(FriendshipTierEnum), default=FriendshipTierEnum.friend)
    affinity_score: Mapped[float] = mapped_column(Float, default=0.0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Plan(Base):
    __tablename__ = "plans"

    id: Mapped[str]           = mapped_column(String, primary_key=True, default=new_uuid)
    creator_id: Mapped[str]   = mapped_column(ForeignKey("users.id"), nullable=False)
    title: Mapped[str]        = mapped_column(String(200), nullable=False)
    event_ids: Mapped[list]   = mapped_column(JSON, default=list)
    selected_event_id: Mapped[Optional[str]] = mapped_column(ForeignKey("events.id"))
    status: Mapped[PlanStatusEnum] = mapped_column(EnumString(PlanStatusEnum), default=PlanStatusEnum.proposal)
    meeting_time: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    meeting_location: Mapped[Optional[str]]  = mapped_column(String(500))
    invite_code: Mapped[Optional[str]] = mapped_column(String(20), unique=True, nullable=True, default=lambda: secrets.token_urlsafe(8))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    members:  Mapped[list["PlanMember"]] = relationship(back_populates="plan", cascade="all, delete-orphan")
    messages: Mapped[list["Message"]]    = relationship(back_populates="plan", cascade="all, delete-orphan",
                                                         order_by="Message.created_at")


class PlanMember(Base):
    __tablename__ = "plan_members"

    id: Mapped[str]       = mapped_column(String, primary_key=True, default=new_uuid)
    plan_id: Mapped[str]  = mapped_column(ForeignKey("plans.id"), nullable=False)
    user_id: Mapped[str]  = mapped_column(ForeignKey("users.id"), nullable=False)
    status: Mapped[PlanMemberStatusEnum] = mapped_column(EnumString(PlanMemberStatusEnum), default=PlanMemberStatusEnum.invited)

    plan: Mapped["Plan"] = relationship(back_populates="members")
    user: Mapped["User"] = relationship()


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[str]       = mapped_column(String, primary_key=True, default=new_uuid)
    plan_id: Mapped[str]  = mapped_column(ForeignKey("plans.id"), nullable=False)
    user_id: Mapped[str]  = mapped_column(ForeignKey("users.id"), nullable=False)
    body: Mapped[str]     = mapped_column(Text, nullable=False)
    type: Mapped[MessageTypeEnum] = mapped_column(EnumString(MessageTypeEnum), default=MessageTypeEnum.text)
    created_at: Mapped[datetime]  = mapped_column(DateTime(timezone=True), server_default=func.now())

    plan:   Mapped["Plan"] = relationship(back_populates="messages")
    sender: Mapped["User"] = relationship()


class SavedEvent(Base):
    __tablename__ = "saved_events"

    id: Mapped[str]        = mapped_column(String, primary_key=True, default=new_uuid)
    user_id: Mapped[str]   = mapped_column(ForeignKey("users.id"), nullable=False)
    event_id: Mapped[str]  = mapped_column(ForeignKey("events.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SwipeFeedback(Base):
    __tablename__ = "swipe_feedback"

    id: Mapped[str]       = mapped_column(String, primary_key=True, default=new_uuid)
    user_id: Mapped[str]  = mapped_column(ForeignKey("users.id"), nullable=False)
    event_id: Mapped[str] = mapped_column(ForeignKey("events.id"), nullable=False)
    direction: Mapped[str] = mapped_column(String(10))  # "left" | "right"
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class OTPCode(Base):
    __tablename__ = "otp_codes"

    id: Mapped[str]       = mapped_column(String, primary_key=True, default=new_uuid)
    email: Mapped[str]    = mapped_column(String(254), nullable=False)
    code: Mapped[str]     = mapped_column(String(6), nullable=False)
    used: Mapped[bool]    = mapped_column(Boolean, default=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------

class Group(Base):
    __tablename__ = "groups"

    id: Mapped[str]          = mapped_column(String, primary_key=True, default=new_uuid)
    name: Mapped[str]        = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, default="")
    creator_id: Mapped[str]  = mapped_column(ForeignKey("users.id"), nullable=False)
    is_private: Mapped[bool] = mapped_column(Boolean, default=True)
    image_url: Mapped[Optional[str]] = mapped_column(String(500))
    invite_code: Mapped[Optional[str]] = mapped_column(String(20), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    members: Mapped[list["GroupMembership"]] = relationship(back_populates="group",
                                                             cascade="all, delete-orphan")


class GroupMembership(Base):
    __tablename__ = "group_memberships"

    id: Mapped[str]       = mapped_column(String, primary_key=True, default=new_uuid)
    group_id: Mapped[str] = mapped_column(ForeignKey("groups.id"), nullable=False)
    user_id: Mapped[str]  = mapped_column(ForeignKey("users.id"), nullable=False)
    role: Mapped[GroupRoleEnum] = mapped_column(EnumString(GroupRoleEnum), default=GroupRoleEnum.member)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    group: Mapped["Group"] = relationship(back_populates="members")
    user: Mapped["User"]   = relationship()


# ---------------------------------------------------------------------------
# Activity Posts (LFG)
# ---------------------------------------------------------------------------

class ActivityPost(Base):
    __tablename__ = "activity_posts"

    id: Mapped[str]           = mapped_column(String, primary_key=True, default=new_uuid)
    creator_id: Mapped[str]   = mapped_column(ForeignKey("users.id"), nullable=False)
    title: Mapped[str]        = mapped_column(String(300), nullable=False)
    description: Mapped[str]  = mapped_column(Text, default="")
    activity_type: Mapped[ActivityTypeEnum] = mapped_column(EnumString(ActivityTypeEnum), default=ActivityTypeEnum.social)
    location: Mapped[Optional[str]]         = mapped_column(String(500))
    latitude: Mapped[Optional[float]]       = mapped_column(Float)
    longitude: Mapped[Optional[float]]      = mapped_column(Float)
    scheduled_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    max_participants: Mapped[Optional[int]] = mapped_column(Integer)
    group_id: Mapped[Optional[str]]         = mapped_column(ForeignKey("groups.id"), nullable=True)
    is_members_only: Mapped[bool]           = mapped_column(Boolean, default=False)
    is_announcement: Mapped[bool]           = mapped_column(Boolean, default=False)
    status: Mapped[ActivityStatusEnum]      = mapped_column(EnumString(ActivityStatusEnum), default=ActivityStatusEnum.open)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    creator: Mapped["User"] = relationship()
    group: Mapped[Optional["Group"]] = relationship()
    participants: Mapped[list["ActivityParticipant"]] = relationship(back_populates="activity",
                                                                      cascade="all, delete-orphan")


class ActivityParticipant(Base):
    __tablename__ = "activity_participants"

    id: Mapped[str]          = mapped_column(String, primary_key=True, default=new_uuid)
    activity_id: Mapped[str] = mapped_column(ForeignKey("activity_posts.id"), nullable=False)
    user_id: Mapped[str]     = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    activity: Mapped["ActivityPost"] = relationship(back_populates="participants")
    user: Mapped["User"] = relationship()


# ---------------------------------------------------------------------------
# Carpooling
# ---------------------------------------------------------------------------

class Carpool(Base):
    __tablename__ = "carpools"

    id: Mapped[str]              = mapped_column(String, primary_key=True, default=new_uuid)
    plan_id: Mapped[str]         = mapped_column(ForeignKey("plans.id"), nullable=False)
    driver_id: Mapped[str]       = mapped_column(ForeignKey("users.id"), nullable=False)
    departure_location: Mapped[str]  = mapped_column(String(500), default="")
    departure_latitude: Mapped[Optional[float]]  = mapped_column(Float)
    departure_longitude: Mapped[Optional[float]] = mapped_column(Float)
    departure_time: Mapped[Optional[datetime]]   = mapped_column(DateTime(timezone=True))
    total_seats: Mapped[int]     = mapped_column(Integer, default=3)
    notes: Mapped[Optional[str]] = mapped_column(Text)
    status: Mapped[CarpoolStatusEnum] = mapped_column(EnumString(CarpoolStatusEnum), default=CarpoolStatusEnum.open)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    driver: Mapped["User"] = relationship()
    passengers: Mapped[list["CarpoolPassenger"]] = relationship(back_populates="carpool",
                                                                 cascade="all, delete-orphan")


class CarpoolPassenger(Base):
    __tablename__ = "carpool_passengers"

    id: Mapped[str]          = mapped_column(String, primary_key=True, default=new_uuid)
    carpool_id: Mapped[str]  = mapped_column(ForeignKey("carpools.id"), nullable=False)
    user_id: Mapped[str]     = mapped_column(ForeignKey("users.id"), nullable=False)
    status: Mapped[str]      = mapped_column(String(20), default="confirmed")  # confirmed | pending
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    carpool: Mapped["Carpool"] = relationship(back_populates="passengers")
    user: Mapped["User"] = relationship()
