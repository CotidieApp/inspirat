"""Publicaciones comunitarias transaccionales.

Revision ID: 0005
Revises: 0004
"""

import sqlalchemy as sa

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "community_publications",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("sender_id", sa.String(length=36), nullable=False),
        sa.Column("client_id", sa.String(length=36), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "sender_id",
            "client_id",
            name="uq_community_publication_sender_client",
        ),
    )
    op.create_index(
        "ix_community_publications_sender_id",
        "community_publications",
        ["sender_id"],
        unique=False,
    )
    with op.batch_alter_table("community_messages") as batch_op:
        batch_op.add_column(
            sa.Column("publication_id", sa.String(length=36), nullable=True)
        )
        batch_op.create_foreign_key(
            "fk_community_messages_publication_id",
            "community_publications",
            ["publication_id"],
            ["id"],
            ondelete="SET NULL",
        )
    op.create_index(
        "ix_community_messages_publication_id",
        "community_messages",
        ["publication_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_community_messages_publication_id",
        table_name="community_messages",
    )
    with op.batch_alter_table("community_messages") as batch_op:
        batch_op.drop_constraint(
            "fk_community_messages_publication_id",
            type_="foreignkey",
        )
        batch_op.drop_column("publication_id")
    op.drop_index(
        "ix_community_publications_sender_id",
        table_name="community_publications",
    )
    op.drop_table("community_publications")
