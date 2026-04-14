"""Initial schema

Revision ID: 0001
Revises:
Create Date: 2026-04-13

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _create_enum(name: str, values: list) -> None:
    vals = ", ".join(f"'{v}'" for v in values)
    op.execute(f"""
        DO $$ BEGIN
            CREATE TYPE {name} AS ENUM ({vals});
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$;
    """)


def upgrade() -> None:
    # --- Enums (DO block catches duplicate_object on any Postgres version) ---
    _create_enum("eventcategoryenum", ["music", "nightlife", "food_drink", "arts", "sports", "other"])
    _create_enum("eventtypeenum", ["study", "social", "sports", "food", "career", "entertainment", "creative", "wellness", "other"])
    _create_enum("rsvpstatusenum", ["going", "interested", "not_going"])
    _create_enum("friendshiptierenum", ["inner_circle", "friend", "connection"])
    _create_enum("planstatusenum", ["proposal", "voting", "locked", "live", "archived"])
    _create_enum("planmemberstatusenum", ["invited", "going", "maybe", "declined"])
    _create_enum("messagetypeenum", ["text", "image", "system"])
    _create_enum("grouproleenum", ["owner", "admin", "member"])
    _create_enum("activitytypeenum", ["study", "sports", "food", "social", "creative", "wellness", "other"])
    _create_enum("activitystatusenum", ["open", "full", "cancelled", "completed"])
    _create_enum("carpoolstatusenum", ["open", "full", "cancelled"])

    # --- Tables ---
    op.create_table(
        "users",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("email", sa.String(254), unique=True, nullable=True),
        sa.Column("phone", sa.String(20), unique=True, nullable=True),
        sa.Column("university", sa.String(200), nullable=True),
        sa.Column("name", sa.String(120), nullable=False, server_default=""),
        sa.Column("avatar_url", sa.String(500), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("taste_vector", sa.JSON(), nullable=True),
        sa.Column("spotify_token", sa.String(500), nullable=True),
        sa.Column("onboarding_complete", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "taste_profiles",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), unique=True),
        sa.Column("genre_weights", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("category_affinities", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("price_sensitivity", sa.Float(), nullable=False, server_default="0.5"),
        sa.Column("time_preferences", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("human_readable_summary", sa.Text(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "groups",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("creator_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("is_private", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("invite_code", sa.String(20), unique=True, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "group_memberships",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("group_id", sa.String(), sa.ForeignKey("groups.id"), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("role", sa.Text(), nullable=False, server_default="member"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "venues",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("address", sa.String(500), nullable=False, server_default=""),
        sa.Column("google_place_id", sa.String(200), nullable=True),
        sa.Column("vibe_tags", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("images", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("claimed_by", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "events",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("venue_id", sa.String(), sa.ForeignKey("venues.id"), nullable=False),
        sa.Column("start_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_time", sa.DateTime(timezone=True), nullable=True),
        sa.Column("price_min", sa.Float(), nullable=True),
        sa.Column("price_max", sa.Float(), nullable=True),
        sa.Column("capacity", sa.Integer(), nullable=True),
        sa.Column("category", sa.Text(), nullable=False, server_default="other"),
        sa.Column("event_type", sa.Text(), nullable=True),
        sa.Column("group_id", sa.String(), sa.ForeignKey("groups.id"), nullable=True),
        sa.Column("tags", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("source", sa.String(50), nullable=False, server_default="organic"),
        sa.Column("attribute_vector", sa.JSON(), nullable=True),
        sa.Column("trending_score", sa.Float(), nullable=False, server_default="0.0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "rsvps",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("event_id", sa.String(), sa.ForeignKey("events.id"), nullable=False),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "friendships",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_a_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("user_b_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("tier", sa.Text(), nullable=False, server_default="friend"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "plans",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("creator_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("event_ids", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("selected_event_id", sa.String(), sa.ForeignKey("events.id"), nullable=True),
        sa.Column("status", sa.Text(), nullable=False, server_default="proposal"),
        sa.Column("meeting_time", sa.DateTime(timezone=True), nullable=True),
        sa.Column("meeting_location", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "plan_members",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("plan_id", sa.String(), sa.ForeignKey("plans.id"), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("status", sa.Text(), nullable=False, server_default="invited"),
    )

    op.create_table(
        "messages",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("plan_id", sa.String(), sa.ForeignKey("plans.id"), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("type", sa.Text(), nullable=False, server_default="text"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "saved_events",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("event_id", sa.String(), sa.ForeignKey("events.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "swipe_feedback",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("event_id", sa.String(), sa.ForeignKey("events.id"), nullable=False),
        sa.Column("direction", sa.String(10), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "otp_codes",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("email", sa.String(254), nullable=False),
        sa.Column("code", sa.String(6), nullable=False),
        sa.Column("used", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "activity_posts",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("creator_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("description", sa.Text(), nullable=False, server_default=""),
        sa.Column("activity_type", sa.Text(), nullable=False, server_default="social"),
        sa.Column("location", sa.String(500), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("scheduled_time", sa.DateTime(timezone=True), nullable=True),
        sa.Column("max_participants", sa.Integer(), nullable=True),
        sa.Column("group_id", sa.String(), sa.ForeignKey("groups.id"), nullable=True),
        sa.Column("status", sa.Text(), nullable=False, server_default="open"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "activity_participants",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("activity_id", sa.String(), sa.ForeignKey("activity_posts.id"), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "carpools",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("plan_id", sa.String(), sa.ForeignKey("plans.id"), nullable=False),
        sa.Column("driver_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("departure_location", sa.String(500), nullable=False, server_default=""),
        sa.Column("departure_latitude", sa.Float(), nullable=True),
        sa.Column("departure_longitude", sa.Float(), nullable=True),
        sa.Column("departure_time", sa.DateTime(timezone=True), nullable=True),
        sa.Column("total_seats", sa.Integer(), nullable=False, server_default="3"),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("status", sa.Text(), nullable=False, server_default="open"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "carpool_passengers",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("carpool_id", sa.String(), sa.ForeignKey("carpools.id"), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="confirmed"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    # --- Indexes ---
    op.create_index("ix_events_start_time", "events", ["start_time"])
    op.create_index("ix_events_venue_id", "events", ["venue_id"])
    op.create_index("ix_rsvps_user_id", "rsvps", ["user_id"])
    op.create_index("ix_rsvps_event_id", "rsvps", ["event_id"])
    op.create_index("ix_plan_members_plan_id", "plan_members", ["plan_id"])
    op.create_index("ix_plan_members_user_id", "plan_members", ["user_id"])
    op.create_index("ix_messages_plan_id", "messages", ["plan_id"])
    op.create_index("ix_saved_events_user_id", "saved_events", ["user_id"])
    op.create_index("ix_otp_codes_email", "otp_codes", ["email"])
    op.create_index("ix_group_memberships_user_id", "group_memberships", ["user_id"])


def downgrade() -> None:
    op.drop_table("carpool_passengers")
    op.drop_table("carpools")
    op.drop_table("activity_participants")
    op.drop_table("activity_posts")
    op.drop_table("otp_codes")
    op.drop_table("swipe_feedback")
    op.drop_table("saved_events")
    op.drop_table("messages")
    op.drop_table("plan_members")
    op.drop_table("plans")
    op.drop_table("friendships")
    op.drop_table("rsvps")
    op.drop_table("events")
    op.drop_table("venues")
    op.drop_table("group_memberships")
    op.drop_table("groups")
    op.drop_table("taste_profiles")
    op.drop_table("users")

    for name in [
        "carpoolstatusenum", "activitystatusenum", "activitytypeenum",
        "grouproleenum", "messagetypeenum", "planmemberstatusenum",
        "planstatusenum", "friendshiptierenum", "rsvpstatusenum",
        "eventtypeenum", "eventcategoryenum",
    ]:
        op.execute(f"DROP TYPE IF EXISTS {name}")
