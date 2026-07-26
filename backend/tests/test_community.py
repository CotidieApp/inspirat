from conftest import TestingSession, register
from sqlalchemy import func, select
from test_mvp import auth, create_story

from app.models import (
    CommunityMessage,
    CommunityPublication,
    Notification,
    Share,
    User,
)


def test_public_user_directory_excludes_email_self_and_inactive(client, author, reader):
    third = register(client, "tercera")
    with TestingSession() as db:
        inactive = db.get(User, third["user"]["id"])
        inactive.is_active = False
        db.commit()
    response = client.get("/api/v1/community/users", headers=auth(author))

    assert response.status_code == 200
    users = response.json()
    assert {item["username"] for item in users} == {"lectora"}
    assert all("email" not in item for item in users)
    assert all(item["id"] != author["user"]["id"] for item in users)

    assert third["user"]["id"] not in {item["id"] for item in users}
    assert client.get("/api/v1/community/users").status_code == 401


def test_general_chat_is_visible_to_authenticated_users_only(client, author, reader):
    _, document = create_story(client, author)
    published = client.post(
        "/api/v1/community/general/messages",
        headers=auth(author),
        json={"body": "Comparto mi comienzo.", "document_id": document["id"]},
    )

    assert published.status_code == 201, published.text
    assert published.json()["document"]["content"] == "La lluvia recordó primero."
    feed = client.get("/api/v1/community/general/messages", headers=auth(reader))
    assert feed.status_code == 200
    assert feed.json()[0]["id"] == published.json()["id"]
    assert client.get("/api/v1/community/general/messages").status_code == 401

    document_access = client.get(
        f"/api/v1/documents/{document['id']}",
        headers=auth(reader),
    )
    assert document_access.status_code == 200
    comment = client.post(
        f"/api/v1/documents/{document['id']}/comments",
        headers=auth(reader),
        json={"body": "Gracias por compartir."},
    )
    assert comment.status_code == 200


def test_cannot_attach_another_users_document(client, author, reader):
    _, document = create_story(client, author)

    general = client.post(
        "/api/v1/community/general/messages",
        headers=auth(reader),
        json={"body": "Intento indebido.", "document_id": document["id"]},
    )
    direct = client.post(
        f"/api/v1/community/direct/{author['user']['id']}/messages",
        headers=auth(reader),
        json={"body": "Intento indebido.", "document_id": document["id"]},
    )

    assert general.status_code == 403
    assert direct.status_code == 403


def test_direct_chat_is_private_and_attachment_creates_comment_access(
    client, author, reader
):
    intruder = register(client, "intrusa")
    _, document = create_story(client, author)
    sent = client.post(
        f"/api/v1/community/direct/{reader['user']['id']}/messages",
        headers=auth(author),
        json={"body": "¿Qué te parece?", "document_id": document["id"]},
    )

    assert sent.status_code == 201, sent.text
    message_id = sent.json()["id"]
    assert (
        client.get(
            f"/api/v1/community/messages/{message_id}",
            headers=auth(reader),
        ).status_code
        == 200
    )
    assert (
        client.get(
            f"/api/v1/community/messages/{message_id}",
            headers=auth(intruder),
        ).status_code
        == 403
    )
    intruder_chat = client.get(
        f"/api/v1/community/direct/{author['user']['id']}/messages",
        headers=auth(intruder),
    )
    assert intruder_chat.status_code == 200
    assert intruder_chat.json() == []

    assert (
        client.get(
            f"/api/v1/documents/{document['id']}",
            headers=auth(reader),
        ).status_code
        == 200
    )
    assert (
        client.post(
            f"/api/v1/documents/{document['id']}/comments",
            headers=auth(reader),
            json={"body": "Me gusta."},
        ).status_code
        == 200
    )
    assert (
        client.put(
            f"/api/v1/documents/{document['id']}",
            headers=auth(reader),
            json={"content": "No debo editar.", "base_revision": 1},
        ).status_code
        == 403
    )


def test_conversation_unread_count_and_read_receipt(client, author, reader):
    sent = client.post(
        f"/api/v1/community/direct/{reader['user']['id']}/messages",
        headers=auth(author),
        json={"body": "Hola."},
    )
    assert sent.status_code == 201

    conversations = client.get(
        "/api/v1/community/conversations",
        headers=auth(reader),
    )
    assert conversations.status_code == 200
    assert conversations.json()[0]["user"]["id"] == author["user"]["id"]
    assert conversations.json()[0]["unread_count"] == 1

    read = client.post(
        f"/api/v1/community/direct/{author['user']['id']}/read",
        headers=auth(reader),
    )
    assert read.status_code == 200
    assert read.json()["updated"] == 1

    conversations = client.get(
        "/api/v1/community/conversations",
        headers=auth(reader),
    )
    assert conversations.json()[0]["unread_count"] == 0
    message = client.get(
        f"/api/v1/community/messages/{sent.json()['id']}",
        headers=auth(reader),
    )
    assert message.json()["read_at"] is not None


def test_message_requires_text_or_document_and_pagination_is_bounded(
    client, author, reader
):
    empty = client.post(
        "/api/v1/community/general/messages",
        headers=auth(author),
        json={"body": "   "},
    )
    assert empty.status_code == 422

    for number in range(3):
        response = client.post(
            "/api/v1/community/general/messages",
            headers=auth(author),
            json={"body": f"Mensaje {number}"},
        )
        assert response.status_code == 201
    first_page = client.get(
        "/api/v1/community/general/messages?limit=2&offset=0",
        headers=auth(reader),
    )
    second_page = client.get(
        "/api/v1/community/general/messages?limit=2&offset=2",
        headers=auth(reader),
    )
    assert len(first_page.json()) == 2
    assert len(second_page.json()) == 1
    assert {item["id"] for item in first_page.json()}.isdisjoint(
        {item["id"] for item in second_page.json()}
    )


def test_message_retry_with_client_id_is_idempotent(client, author, reader):
    payload = {
        "client_id": "77777777-7777-4777-8777-777777777777",
        "body": "Mensaje que se reintenta tras un timeout.",
    }
    first = client.post(
        f"/api/v1/community/direct/{reader['user']['id']}/messages",
        headers=auth(author),
        json=payload,
    )
    retry = client.post(
        f"/api/v1/community/direct/{reader['user']['id']}/messages",
        headers=auth(author),
        json=payload,
    )

    assert first.status_code == 201
    assert retry.status_code == 201
    assert retry.json()["id"] == first.json()["id"]
    assert retry.json()["client_id"] == payload["client_id"]
    messages = client.get(
        f"/api/v1/community/direct/{author['user']['id']}/messages",
        headers=auth(reader),
    )
    assert [item["id"] for item in messages.json()] == [first.json()["id"]]
    conversations = client.get(
        "/api/v1/community/conversations",
        headers=auth(reader),
    )
    assert conversations.json()[0]["unread_count"] == 1

    conflict = client.post(
        "/api/v1/community/general/messages",
        headers=auth(author),
        json={**payload, "body": "Contenido distinto."},
    )
    assert conflict.status_code == 409


def test_transactional_publish_creates_all_destinations_once(
    client, author, reader
):
    third = register(client, "tercera")
    _, document = create_story(client, author)
    payload = {
        "client_id": "88888888-8888-4888-8888-888888888888",
        "body": "Una publicación para toda la comunidad.",
        "document_id": document["id"],
        "publish_general": True,
        "recipient_ids": [third["user"]["id"], reader["user"]["id"]],
    }

    created = client.post(
        "/api/v1/community/publish",
        headers=auth(author),
        json=payload,
    )
    retry = client.post(
        "/api/v1/community/publish",
        headers=auth(author),
        json={**payload, "recipient_ids": list(reversed(payload["recipient_ids"]))},
    )

    assert created.status_code == 200, created.text
    assert created.json()["created"] is True
    assert created.json()["client_id"] == payload["client_id"]
    assert len(created.json()["messages"]) == 3
    assert sum(item["recipient"] is None for item in created.json()["messages"]) == 1
    assert {
        item["recipient"]["id"]
        for item in created.json()["messages"]
        if item["recipient"] is not None
    } == {reader["user"]["id"], third["user"]["id"]}

    assert retry.status_code == 200, retry.text
    assert retry.json()["created"] is False
    assert {item["id"] for item in retry.json()["messages"]} == {
        item["id"] for item in created.json()["messages"]
    }

    with TestingSession() as db:
        assert db.scalar(select(func.count()).select_from(CommunityPublication)) == 1
        assert db.scalar(select(func.count()).select_from(CommunityMessage)) == 3
        assert db.scalar(select(func.count()).select_from(Share)) == 2
        assert db.scalar(select(func.count()).select_from(Notification)) == 2

    assert (
        client.get(
            f"/api/v1/documents/{document['id']}",
            headers=auth(third),
        ).status_code
        == 200
    )
    conflict = client.post(
        "/api/v1/community/publish",
        headers=auth(author),
        json={**payload, "body": "No es la misma operación."},
    )
    assert conflict.status_code == 409


def test_transactional_publish_validates_every_target_before_writing(
    client, author, reader
):
    _, document = create_story(client, author)
    response = client.post(
        "/api/v1/community/publish",
        headers=auth(author),
        json={
            "client_id": "99999999-9999-4999-8999-999999999999",
            "body": "Esto no debe guardarse parcialmente.",
            "document_id": document["id"],
            "publish_general": True,
            "recipient_ids": [
                reader["user"]["id"],
                "00000000-0000-4000-8000-000000000000",
            ],
        },
    )

    assert response.status_code == 404
    with TestingSession() as db:
        assert db.scalar(select(func.count()).select_from(CommunityPublication)) == 0
        assert db.scalar(select(func.count()).select_from(CommunityMessage)) == 0
        assert db.scalar(select(func.count()).select_from(Share)) == 0
        assert db.scalar(select(func.count()).select_from(Notification)) == 0
    assert (
        client.get(
            "/api/v1/community/general/messages",
            headers=auth(reader),
        ).json()
        == []
    )
    assert (
        client.get(
            f"/api/v1/community/direct/{author['user']['id']}/messages",
            headers=auth(reader),
        ).json()
        == []
    )


def test_transactional_publish_rejects_foreign_document_and_invalid_targets(
    client, author, reader
):
    _, document = create_story(client, author)
    foreign_document = client.post(
        "/api/v1/community/publish",
        headers=auth(reader),
        json={
            "client_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "document_id": document["id"],
            "publish_general": True,
        },
    )
    self_delivery = client.post(
        "/api/v1/community/publish",
        headers=auth(author),
        json={
            "client_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            "body": "No debe enviarse a mí.",
            "recipient_ids": [author["user"]["id"]],
        },
    )
    no_destination = client.post(
        "/api/v1/community/publish",
        headers=auth(author),
        json={
            "client_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            "body": "Sin destino.",
        },
    )

    assert foreign_document.status_code == 403
    assert self_delivery.status_code == 400
    assert no_destination.status_code == 422
    with TestingSession() as db:
        assert db.scalar(select(func.count()).select_from(CommunityPublication)) == 0
        assert db.scalar(select(func.count()).select_from(CommunityMessage)) == 0
