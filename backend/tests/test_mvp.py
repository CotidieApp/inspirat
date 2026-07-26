from conftest import register


def auth(pair):
    return {"Authorization": f"Bearer {pair['access_token']}"}


def create_story(client, pair):
    project = client.post(
        "/api/v1/projects",
        headers=auth(pair),
        json={
            "client_id": "11111111-1111-4111-8111-111111111111",
            "title": "La ciudad sumergida",
            "work_type": "novel",
            "synopsis": "Una memoria que se niega a desaparecer.",
            "status": "draft",
            "color": "#6856D6",
        },
    )
    assert project.status_code == 201, project.text
    document = client.post(
        f"/api/v1/projects/{project.json()['id']}/documents",
        headers=auth(pair),
        json={
            "client_id": "22222222-2222-4222-8222-222222222222",
            "title": "Capítulo 1",
            "kind": "chapter",
            "content": "La lluvia recordó primero.",
        },
    )
    assert document.status_code == 201, document.text
    return project.json(), document.json()


def test_auth_refresh_rotates_token(client):
    pair = register(client, "rotacion")
    refreshed = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": pair["refresh_token"], "device_name": "Segundo dispositivo"},
    )
    assert refreshed.status_code == 200
    replay = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": pair["refresh_token"], "device_name": "Ataque"},
    )
    assert replay.status_code == 401


def test_private_project_is_not_readable(client, author, reader):
    _, document = create_story(client, author)
    response = client.get(f"/api/v1/documents/{document['id']}", headers=auth(reader))
    assert response.status_code == 403


def test_share_comment_version_restore_and_exports(client, author, reader):
    _, document = create_story(client, author)
    share = client.post(
        f"/api/v1/documents/{document['id']}/shares",
        headers=auth(author),
        json={
            "recipient": "lectora",
            "permission": "comment",
            "message": "¿Qué te parece el comienzo?",
        },
    )
    assert share.status_code == 200, share.text

    inbox = client.get("/api/v1/shares/inbox", headers=auth(reader))
    assert inbox.status_code == 200
    assert inbox.json()[0]["document"]["title"] == "Capítulo 1"

    forbidden_edit = client.put(
        f"/api/v1/documents/{document['id']}",
        headers=auth(reader),
        json={"content": "No debería guardarse", "base_revision": 1},
    )
    assert forbidden_edit.status_code == 403

    comment = client.post(
        f"/api/v1/documents/{document['id']}/comments",
        headers=auth(reader),
        json={"body": "La primera frase tiene fuerza.", "anchor_start": 0, "anchor_end": 9},
    )
    assert comment.status_code == 200

    version = client.post(
        f"/api/v1/documents/{document['id']}/versions",
        headers=auth(author),
        json={"name": "Primer borrador"},
    )
    assert version.status_code == 200

    updated = client.put(
        f"/api/v1/documents/{document['id']}",
        headers=auth(author),
        json={"content": "La lluvia recordó el océano primero.", "base_revision": 1},
    )
    assert updated.status_code == 200
    restored = client.post(f"/api/v1/versions/{version.json()['id']}/restore", headers=auth(author))
    assert restored.status_code == 200
    assert restored.json()["content"] == "La lluvia recordó primero."

    for output_format, content_type in [
        ("txt", "text/plain"),
        ("md", "text/markdown"),
        ("pdf", "application/pdf"),
    ]:
        exported = client.get(
            f"/api/v1/documents/{document['id']}/export?format={output_format}",
            headers=auth(author),
        )
        assert exported.status_code == 200
        assert content_type in exported.headers["content-type"]
        assert len(exported.content) > 10


def test_conflict_preserves_submitted_text_as_version(client, author):
    _, document = create_story(client, author)
    first = client.put(
        f"/api/v1/documents/{document['id']}",
        headers=auth(author),
        json={"content": "Cambio desde el teléfono.", "base_revision": 1},
    )
    assert first.status_code == 200
    conflict = client.put(
        f"/api/v1/documents/{document['id']}",
        headers=auth(author),
        json={"content": "Cambio sin conexión desde la tableta.", "base_revision": 1},
    )
    assert conflict.status_code == 409
    assert conflict.json()["detail"]["backup_version_id"]
    versions = client.get(
        f"/api/v1/documents/{document['id']}/versions", headers=auth(author)
    ).json()
    assert any(item["content"] == "Cambio sin conexión desde la tableta." for item in versions)


def test_revoked_share_stops_access(client, author, reader):
    _, document = create_story(client, author)
    share = client.post(
        f"/api/v1/documents/{document['id']}/shares",
        headers=auth(author),
        json={"recipient": "lectora", "permission": "read"},
    ).json()
    assert (
        client.get(f"/api/v1/documents/{document['id']}", headers=auth(reader)).status_code == 200
    )
    assert client.delete(f"/api/v1/shares/{share['id']}", headers=auth(author)).status_code == 204
    assert (
        client.get(f"/api/v1/documents/{document['id']}", headers=auth(reader)).status_code == 403
    )
