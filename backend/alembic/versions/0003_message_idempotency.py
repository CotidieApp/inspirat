"""Idempotencia de mensajes móviles.

Revision ID: 0003
Revises: 0002
"""

import sqlalchemy as sa

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("community_messages") as batch_op:
        batch_op.add_column(sa.Column("client_id", sa.String(length=36), nullable=True))
        batch_op.create_unique_constraint(
            "uq_community_message_sender_client",
            ["sender_id", "client_id"],
        )


def downgrade() -> None:
    with op.batch_alter_table("community_messages") as batch_op:
        batch_op.drop_constraint(
            "uq_community_message_sender_client",
            type_="unique",
        )
        batch_op.drop_column("client_id")
