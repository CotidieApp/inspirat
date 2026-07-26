"""Corrige correos demo incompatibles con EmailStr.

Revision ID: 0004
Revises: 0003
"""

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "UPDATE users SET email = 'ines@example.com' "
        "WHERE username = 'ines' AND email = 'ines@demo.inspirat.local'"
    )
    op.execute(
        "UPDATE users SET email = 'mateo@example.com' "
        "WHERE username = 'mateo' AND email = 'mateo@demo.inspirat.local'"
    )


def downgrade() -> None:
    op.execute(
        "UPDATE users SET email = 'ines@demo.inspirat.local' "
        "WHERE username = 'ines' AND email = 'ines@example.com'"
    )
    op.execute(
        "UPDATE users SET email = 'mateo@demo.inspirat.local' "
        "WHERE username = 'mateo' AND email = 'mateo@example.com'"
    )
