import os

os.environ["INSPIRAT_DATABASE_URL"] = "sqlite://"
os.environ["INSPIRAT_SECRET_KEY"] = "test-secret-key-that-is-long-enough-and-never-production"

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.rate_limit import limiter

engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
TestingSession = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


@pytest.fixture(autouse=True)
def clean_database():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    limiter.reset()
    yield


@pytest.fixture
def client():
    def override_db():
        db = TestingSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def register(client, username: str):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": f"{username}@example.com",
            "username": username,
            "display_name": username.title(),
            "password": "Una-clave-segura-2026",
            "accepted_terms": True,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.fixture
def author(client):
    return register(client, "autora")


@pytest.fixture
def reader(client):
    return register(client, "lectora")
