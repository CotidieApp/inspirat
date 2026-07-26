"""Comunidad y mensajería.

Revision ID: 0002
Revises: 0001
"""

import sqlalchemy as sa

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "community_messages",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("channel", sa.String(length=10), nullable=False),
        sa.Column("sender_id", sa.String(length=36), nullable=False),
        sa.Column("recipient_id", sa.String(length=36), nullable=True),
        sa.Column("document_id", sa.String(length=36), nullable=True),
        sa.Column("body", sa.Text(), nullable=False, server_default=""),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint(
            "(channel = 'general' AND recipient_id IS NULL) "
            "OR (channel = 'direct' AND recipient_id IS NOT NULL)",
            name="ck_community_message_channel_recipient",
        ),
        sa.CheckConstraint(
            "length(trim(body)) > 0 OR document_id IS NOT NULL",
            name="ck_community_message_has_content",
        ),
        sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["recipient_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_messages_channel",
        "community_messages",
        ["channel"],
        unique=False,
    )
    op.create_index(
        "ix_community_messages_document_id",
        "community_messages",
        ["document_id"],
        unique=False,
    )
    op.create_index(
        "ix_community_messages_recipient_id",
        "community_messages",
        ["recipient_id"],
        unique=False,
    )
    op.create_index(
        "ix_community_messages_sender_id",
        "community_messages",
        ["sender_id"],
        unique=False,
    )
    op.create_index(
        "ix_community_messages_general_created",
        "community_messages",
        ["channel", "created_at"],
        unique=False,
    )
    op.create_index(
        "ix_community_messages_direct_pair_created",
        "community_messages",
        ["channel", "sender_id", "recipient_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_community_messages_direct_pair_created",
        table_name="community_messages",
    )
    op.drop_index(
        "ix_community_messages_general_created",
        table_name="community_messages",
    )
    op.drop_index("ix_community_messages_sender_id", table_name="community_messages")
    op.drop_index("ix_community_messages_recipient_id", table_name="community_messages")
    op.drop_index("ix_community_messages_document_id", table_name="community_messages")
    op.drop_index("ix_community_messages_channel", table_name="community_messages")
    op.drop_table("community_messages")
