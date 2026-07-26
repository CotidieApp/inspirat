"""Modelo MVP inicial.

Revision ID: 0001
Revises:
"""

from alembic import op
from app import models  # noqa: F401
from app.database import Base

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Esta revisión histórica debe crear únicamente las tablas del MVP inicial.
    # Limitar la lista evita que modelos añadidos después aparezcan antes de su
    # migración correspondiente al preparar una base de datos desde cero.
    initial_tables = (
        "users",
        "sessions",
        "projects",
        "documents",
        "document_versions",
        "shares",
        "comments",
        "notifications",
    )
    Base.metadata.create_all(
        bind=op.get_bind(),
        tables=[Base.metadata.tables[name] for name in initial_tables],
    )


def downgrade() -> None:
    Base.metadata.drop_all(bind=op.get_bind())
