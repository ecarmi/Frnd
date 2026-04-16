"""support saved group activities

Revision ID: 0007
Revises: 0006
Create Date: 2026-04-16
"""
from alembic import op
import sqlalchemy as sa

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("saved_events", sa.Column("activity_id", sa.String(), nullable=True))
    op.create_foreign_key(
        "fk_saved_events_activity_id_activity_posts",
        "saved_events",
        "activity_posts",
        ["activity_id"],
        ["id"],
    )
    op.alter_column(
        "saved_events",
        "event_id",
        existing_type=sa.String(),
        nullable=True,
    )


def downgrade() -> None:
    op.alter_column(
        "saved_events",
        "event_id",
        existing_type=sa.String(),
        nullable=False,
    )
    op.drop_constraint("fk_saved_events_activity_id_activity_posts", "saved_events", type_="foreignkey")
    op.drop_column("saved_events", "activity_id")
