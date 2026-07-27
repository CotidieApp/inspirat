from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings

is_sqlite = settings.database_url.startswith("sqlite")
engine_kwargs: dict = {"pool_pre_ping": True}
if is_sqlite:
    engine_kwargs["connect_args"] = {"check_same_thread": False}
else:
    # Pool chico a propósito: el plan Free del pooler de Supabase (modo
    # session) reserva conexiones reales 1:1 por cliente, con un límite bajo
    # de conexiones concurrentes. connect_timeout evita que una caída
    # momentánea de la base cuelgue requests en vez de fallar rápido.
    engine_kwargs["connect_args"] = {"connect_timeout": 5}
    engine_kwargs["pool_size"] = 3
    engine_kwargs["max_overflow"] = 2
    engine_kwargs["pool_recycle"] = 300

engine = create_engine(settings.database_url, **engine_kwargs)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
