from conftest import register


def auth(pair):
    return {"Authorization": f"Bearer {pair['access_token']}"}


def project_payload(client_id: str, title: str = "Proyecto sincronizado") -> dict:
    return {
        "client_id": client_id,
        "title": title,
        "work_type": "novel",
        "synopsis": "",
        "status": "draft",
        "color": "#1E5B57",
    }


def document_payload(
    project_client_id: str, client_id: str, content: str = "Texto inicial."
) -> dict:
    return {
        "project_client_id": project_client_id,
        "client_id": client_id,
        "title": "Capítulo sincronizado",
        "kind": "chapter",
        "position": 0,
        "content": content,
    }


def test_sync_creates_project_and_document(client):
    pair = register(client, "sincro")
    project_client_id = "33333333-3333-4333-8333-333333333333"
    document_client_id = "44444444-4444-4444-8444-444444444444"
    response = client.post(
        "/api/v1/sync",
        headers=auth(pair),
        json={
            "changes": [
                {
                    "entity": "project",
                    "operation": "upsert",
                    "client_id": project_client_id,
                    "payload": project_payload(project_client_id),
                },
                {
                    "entity": "document",
                    "operation": "upsert",
                    "client_id": document_client_id,
                    "payload": document_payload(project_client_id, document_client_id),
                },
            ]
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["accepted"]) == 2
    assert body["conflicts"] == []
    assert len(body["projects"]) == 1
    assert len(body["documents"]) == 1


def test_sync_rejects_oversized_document_without_losing_other_changes(client):
    pair = register(client, "sincro2")
    project_client_id = "55555555-5555-4555-8555-555555555555"
    huge_document_id = "66666666-6666-4666-8666-666666666666"
    ok_document_id = "77777777-7777-4777-8777-777777777777"
    response = client.post(
        "/api/v1/sync",
        headers=auth(pair),
        json={
            "changes": [
                {
                    "entity": "project",
                    "operation": "upsert",
                    "client_id": project_client_id,
                    "payload": project_payload(project_client_id),
                },
                {
                    "entity": "document",
                    "operation": "upsert",
                    "client_id": huge_document_id,
                    "payload": document_payload(
                        project_client_id, huge_document_id, content="a" * 2_000_001
                    ),
                },
                {
                    "entity": "document",
                    "operation": "upsert",
                    "client_id": ok_document_id,
                    "payload": document_payload(project_client_id, ok_document_id),
                },
            ]
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    accepted_client_ids = {item["client_id"] for item in body["accepted"]}
    assert accepted_client_ids == {project_client_id, ok_document_id}
    assert len(body["conflicts"]) == 1
    assert body["conflicts"][0]["client_id"] == huge_document_id
    assert body["conflicts"][0]["reason"] == "content_too_large"
    assert len(body["documents"]) == 1


def test_sync_invalid_payload_does_not_abort_whole_batch(client):
    pair = register(client, "sincro3")
    project_a = "88888888-8888-4888-8888-888888888888"
    project_bad = "99999999-9999-4999-8999-999999999999"
    project_b = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    response = client.post(
        "/api/v1/sync",
        headers=auth(pair),
        json={
            "changes": [
                {
                    "entity": "project",
                    "operation": "upsert",
                    "client_id": project_a,
                    "payload": project_payload(project_a, "Primero"),
                },
                {
                    "entity": "project",
                    "operation": "upsert",
                    "client_id": project_bad,
                    "payload": {**project_payload(project_bad), "title": ""},
                },
                {
                    "entity": "project",
                    "operation": "upsert",
                    "client_id": project_b,
                    "payload": project_payload(project_b, "Tercero"),
                },
            ]
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    accepted_client_ids = {item["client_id"] for item in body["accepted"]}
    assert accepted_client_ids == {project_a, project_b}
    assert len(body["conflicts"]) == 1
    assert body["conflicts"][0]["client_id"] == project_bad
    assert body["conflicts"][0]["reason"] == "invalid_payload"
    assert len(body["projects"]) == 2


def test_sync_document_upsert_rejects_orphan_with_missing_parent(client):
    pair = register(client, "sincro4")
    response = client.post(
        "/api/v1/sync",
        headers=auth(pair),
        json={
            "changes": [
                {
                    "entity": "document",
                    "operation": "upsert",
                    "client_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                    "payload": document_payload(
                        "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                        "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                    ),
                }
            ]
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["accepted"] == []
    assert body["conflicts"][0]["reason"] == "parent_missing"


def test_create_project_recovers_from_concurrent_duplicate(client, monkeypatch):
    pair = register(client, "carrera1")
    payload = project_payload("dddddddd-dddd-4ddd-8ddd-dddddddddddd", "Primer intento")
    first = client.post("/api/v1/projects", headers=auth(pair), json=payload)
    assert first.status_code == 201, first.text

    import app.api.routes as routes_module

    real_check = routes_module.existing_project_by_client_id
    calls = {"n": 0}

    def flaky_check(client_id, user, db):
        calls["n"] += 1
        if calls["n"] == 1:
            return None
        return real_check(client_id, user, db)

    monkeypatch.setattr(routes_module, "existing_project_by_client_id", flaky_check)

    retry_payload = {**payload, "title": "Segundo intento (mismo client_id)"}
    retry = client.post("/api/v1/projects", headers=auth(pair), json=retry_payload)
    assert retry.status_code == 201, retry.text
    assert retry.json()["id"] == first.json()["id"]
    assert retry.json()["title"] == "Primer intento"


def test_create_document_recovers_from_concurrent_duplicate(client, monkeypatch):
    pair = register(client, "carrera2")
    project = client.post(
        "/api/v1/projects",
        headers=auth(pair),
        json=project_payload("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"),
    )
    assert project.status_code == 201, project.text
    project_id = project.json()["id"]
    doc_payload = {
        "client_id": "ffffffff-ffff-4fff-8fff-ffffffffffff",
        "title": "Primer intento",
        "kind": "chapter",
        "content": "Texto.",
    }
    first = client.post(
        f"/api/v1/projects/{project_id}/documents", headers=auth(pair), json=doc_payload
    )
    assert first.status_code == 201, first.text

    import app.api.routes as routes_module

    real_check = routes_module.existing_document_by_client_id
    calls = {"n": 0}

    def flaky_check(project_id_arg, client_id, db):
        calls["n"] += 1
        if calls["n"] == 1:
            return None
        return real_check(project_id_arg, client_id, db)

    monkeypatch.setattr(routes_module, "existing_document_by_client_id", flaky_check)

    retry_payload = {**doc_payload, "title": "Segundo intento (mismo client_id)"}
    retry = client.post(
        f"/api/v1/projects/{project_id}/documents", headers=auth(pair), json=retry_payload
    )
    assert retry.status_code == 201, retry.text
    assert retry.json()["id"] == first.json()["id"]
    assert retry.json()["title"] == "Primer intento"


def test_share_document_recovers_from_concurrent_duplicate(client, author, reader, monkeypatch):
    project = client.post(
        "/api/v1/projects",
        headers=auth(author),
        json=project_payload("11111111-1111-4111-8aaa-111111111111"),
    )
    assert project.status_code == 201, project.text
    document = client.post(
        f"/api/v1/projects/{project.json()['id']}/documents",
        headers=auth(author),
        json={
            "client_id": "22222222-2222-4222-8aaa-222222222222",
            "title": "Compartido",
            "kind": "chapter",
            "content": "Texto.",
        },
    )
    assert document.status_code == 201, document.text
    document_id = document.json()["id"]

    first = client.post(
        f"/api/v1/documents/{document_id}/shares",
        headers=auth(author),
        json={"recipient": reader["user"]["username"], "permission": "comment"},
    )
    assert first.status_code == 200, first.text

    import app.api.routes as routes_module

    real_check = routes_module.existing_share
    calls = {"n": 0}

    def flaky_check(document_id_arg, recipient_id, db):
        calls["n"] += 1
        if calls["n"] == 1:
            return None
        return real_check(document_id_arg, recipient_id, db)

    monkeypatch.setattr(routes_module, "existing_share", flaky_check)

    retry = client.post(
        f"/api/v1/documents/{document_id}/shares",
        headers=auth(author),
        json={"recipient": reader["user"]["username"], "permission": "edit"},
    )
    assert retry.status_code == 200, retry.text
    assert retry.json()["id"] == first.json()["id"]
    assert retry.json()["permission"] == "edit"
