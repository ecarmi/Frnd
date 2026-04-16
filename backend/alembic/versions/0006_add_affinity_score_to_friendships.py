"""add affinity_score to friendships

Revision ID: 0006
Revises: 0005
Create Date: 2026-04-16
"""
from alembic import op
import sqlalchemy as sa

revision = '0006'
down_revision = '0005'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('friendships', sa.Column('affinity_score', sa.Float(), nullable=False, server_default='0.0'))


def downgrade() -> None:
    op.drop_column('friendships', 'affinity_score')
