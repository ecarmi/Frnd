"""add group activity visibility and announcements

Revision ID: 0004
Revises: 0003
Create Date: 2026-04-16
"""
from alembic import op
import sqlalchemy as sa

revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'activity_posts',
        sa.Column('is_members_only', sa.Boolean(), nullable=False, server_default=sa.false())
    )
    op.add_column(
        'activity_posts',
        sa.Column('is_announcement', sa.Boolean(), nullable=False, server_default=sa.false())
    )

    connection = op.get_bind()
    connection.execute(sa.text("""
        UPDATE activity_posts
        SET is_members_only = TRUE
        WHERE group_id IS NOT NULL
    """))

    op.alter_column('activity_posts', 'is_members_only', server_default=None)
    op.alter_column('activity_posts', 'is_announcement', server_default=None)


def downgrade() -> None:
    op.drop_column('activity_posts', 'is_announcement')
    op.drop_column('activity_posts', 'is_members_only')
