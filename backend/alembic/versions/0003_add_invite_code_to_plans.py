"""add invite_code to plans

Revision ID: 0003
Revises: 0002
Create Date: 2026-04-14
"""
from alembic import op
import sqlalchemy as sa
import secrets

revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('plans', sa.Column('invite_code', sa.String(20), nullable=True))
    op.create_unique_constraint('uq_plans_invite_code', 'plans', ['invite_code'])

    # Backfill existing plans with unique invite codes
    connection = op.get_bind()
    result = connection.execute(sa.text("SELECT id FROM plans WHERE invite_code IS NULL"))
    for row in result:
        connection.execute(
            sa.text("UPDATE plans SET invite_code = :code WHERE id = :id"),
            {"code": secrets.token_urlsafe(8), "id": row[0]}
        )


def downgrade() -> None:
    op.drop_constraint('uq_plans_invite_code', 'plans', type_='unique')
    op.drop_column('plans', 'invite_code')
