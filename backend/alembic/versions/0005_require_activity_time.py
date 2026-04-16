"""require activity scheduled_time

Revision ID: 0005
Revises: 0004
Create Date: 2026-04-16
"""
from alembic import op
import sqlalchemy as sa

revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    connection.execute(sa.text("""
        UPDATE activity_posts
        SET scheduled_time = created_at
        WHERE scheduled_time IS NULL
    """))

    op.alter_column(
        'activity_posts',
        'scheduled_time',
        existing_type=sa.DateTime(timezone=True),
        nullable=False,
    )


def downgrade() -> None:
    op.alter_column(
        'activity_posts',
        'scheduled_time',
        existing_type=sa.DateTime(timezone=True),
        nullable=True,
    )
