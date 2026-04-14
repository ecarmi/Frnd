"""add creator_id to events

Revision ID: 0002
Revises: 0001
Create Date: 2026-04-14
"""
from alembic import op
import sqlalchemy as sa

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('events', sa.Column('creator_id', sa.String(), nullable=True))
    op.create_foreign_key(
        'fk_events_creator_id_users',
        'events', 'users',
        ['creator_id'], ['id'],
        ondelete='SET NULL'
    )


def downgrade() -> None:
    op.drop_constraint('fk_events_creator_id_users', 'events', type_='foreignkey')
    op.drop_column('events', 'creator_id')
