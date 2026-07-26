import re

from conftest import register


def capture_email(monkeypatch):
    sent: list[dict] = []

    def fake_send_email(to: str, subject: str, body: str) -> bool:
        sent.append({"to": to, "subject": subject, "body": body})
        return True

    monkeypatch.setattr("app.api.routes.send_email", fake_send_email)
    return sent


def extract_code(body: str) -> str:
    match = re.search(r"\b(\d{6})\b", body)
    assert match, body
    return match.group(1)


def test_forgot_and_reset_password_happy_path(client, monkeypatch):
    sent = capture_email(monkeypatch)
    pair = register(client, "autora")

    forgot = client.post(
        "/api/v1/auth/password/forgot", json={"identity": "autora@example.com"}
    )
    assert forgot.status_code == 202
    assert len(sent) == 1
    assert sent[0]["to"] == "autora@example.com"
    code = extract_code(sent[0]["body"])

    reset = client.post(
        "/api/v1/auth/password/reset",
        json={
            "identity": "autora@example.com",
            "code": code,
            "new_password": "Otra-clave-2026-segura",
        },
    )
    assert reset.status_code == 200, reset.text

    old_login = client.post(
        "/api/v1/auth/login",
        json={"identity": "autora@example.com", "password": "Una-clave-segura-2026"},
    )
    assert old_login.status_code == 401

    new_login = client.post(
        "/api/v1/auth/login",
        json={"identity": "autora@example.com", "password": "Otra-clave-2026-segura"},
    )
    assert new_login.status_code == 200

    old_refresh = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": pair["refresh_token"], "device_name": "Antiguo"},
    )
    assert old_refresh.status_code == 401


def test_reset_code_is_single_use(client, monkeypatch):
    sent = capture_email(monkeypatch)
    register(client, "autora")
    client.post("/api/v1/auth/password/forgot", json={"identity": "autora@example.com"})
    code = extract_code(sent[0]["body"])

    first = client.post(
        "/api/v1/auth/password/reset",
        json={"identity": "autora@example.com", "code": code, "new_password": "Clave-2026-uno"},
    )
    assert first.status_code == 200

    second = client.post(
        "/api/v1/auth/password/reset",
        json={"identity": "autora@example.com", "code": code, "new_password": "Clave-2026-dos"},
    )
    assert second.status_code == 400


def test_forgot_password_does_not_reveal_unknown_accounts(client, monkeypatch):
    sent = capture_email(monkeypatch)
    response = client.post(
        "/api/v1/auth/password/forgot", json={"identity": "nadie@example.com"}
    )
    assert response.status_code == 202
    assert sent == []


def test_reset_password_rejects_wrong_code(client, monkeypatch):
    sent = capture_email(monkeypatch)
    register(client, "autora")
    client.post("/api/v1/auth/password/forgot", json={"identity": "autora@example.com"})
    code = extract_code(sent[0]["body"])
    wrong_code = f"{(int(code) + 1) % 1_000_000:06d}"

    response = client.post(
        "/api/v1/auth/password/reset",
        json={
            "identity": "autora@example.com",
            "code": wrong_code,
            "new_password": "Clave-2026-nueva",
        },
    )
    assert response.status_code == 400


def test_login_is_rate_limited_after_repeated_attempts(client):
    register(client, "autora")
    for _ in range(10):
        response = client.post(
            "/api/v1/auth/login",
            json={"identity": "autora@example.com", "password": "clave-incorrecta"},
        )
        assert response.status_code == 401

    limited = client.post(
        "/api/v1/auth/login",
        json={"identity": "autora@example.com", "password": "clave-incorrecta"},
    )
    assert limited.status_code == 429


def test_forgot_password_is_rate_limited(client, monkeypatch):
    capture_email(monkeypatch)
    register(client, "autora")
    for _ in range(3):
        response = client.post(
            "/api/v1/auth/password/forgot", json={"identity": "autora@example.com"}
        )
        assert response.status_code == 202

    limited = client.post(
        "/api/v1/auth/password/forgot", json={"identity": "autora@example.com"}
    )
    assert limited.status_code == 429
