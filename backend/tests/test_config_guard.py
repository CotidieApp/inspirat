import pytest
from pydantic import ValidationError

from app.config import Settings


def test_production_rejects_placeholder_secret(monkeypatch):
    monkeypatch.setenv("INSPIRAT_ENV", "production")
    monkeypatch.setenv("INSPIRAT_DATABASE_URL", "postgresql+psycopg://u:p@host:5432/db")
    monkeypatch.delenv("INSPIRAT_SECRET_KEY", raising=False)
    with pytest.raises(ValidationError, match="INSPIRAT_SECRET_KEY"):
        Settings()


def test_production_rejects_sqlite(monkeypatch):
    monkeypatch.setenv("INSPIRAT_ENV", "production")
    monkeypatch.setenv("INSPIRAT_SECRET_KEY", "a-real-secret-key-that-is-at-least-32-chars-long")
    monkeypatch.setenv("INSPIRAT_DATABASE_URL", "sqlite:///./prod.db")
    with pytest.raises(ValidationError, match="INSPIRAT_DATABASE_URL"):
        Settings()


def test_production_accepts_real_configuration(monkeypatch):
    monkeypatch.setenv("INSPIRAT_ENV", "production")
    monkeypatch.setenv("INSPIRAT_SECRET_KEY", "a-real-secret-key-that-is-at-least-32-chars-long")
    monkeypatch.setenv("INSPIRAT_DATABASE_URL", "postgresql+psycopg://u:p@host:5432/db")
    settings = Settings()
    assert settings.is_production is True


def test_development_ignores_placeholder_defaults(monkeypatch):
    monkeypatch.delenv("INSPIRAT_ENV", raising=False)
    monkeypatch.setenv(
        "INSPIRAT_SECRET_KEY", "test-secret-key-that-is-long-enough-and-never-production"
    )
    monkeypatch.setenv("INSPIRAT_DATABASE_URL", "sqlite://")
    settings = Settings()
    assert settings.is_production is False
