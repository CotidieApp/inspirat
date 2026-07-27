import unicodedata
from datetime import UTC, datetime, timedelta
from io import BytesIO

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import ValidationError
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.community import router as community_router
from app.config import settings
from app.database import get_db
from app.deps import current_user, document_access, owned_project
from app.email import send_email
from app.models import (
    Comment,
    Document,
    DocumentVersion,
    Notification,
    PasswordResetCode,
    Project,
    SessionToken,
    Share,
    SharePermission,
    User,
    now,
)
from app.rate_limit import enforce
from app.schemas import (
    CommentIn,
    CommentOut,
    DocumentIn,
    DocumentOut,
    DocumentUpdate,
    InboxItem,
    LoginIn,
    PasswordForgotIn,
    PasswordResetIn,
    ProjectIn,
    ProjectOut,
    RefreshIn,
    RegisterIn,
    ShareIn,
    ShareOut,
    SyncRequest,
    SyncResponse,
    TokenPair,
    UserOut,
    VersionIn,
    VersionOut,
)
from app.security import (
    create_access_token,
    hash_password,
    hash_token,
    new_refresh_token,
    new_reset_code,
    verify_password,
)

router = APIRouter()
router.include_router(community_router)


def token_pair(user: User, db: Session, device_name: str) -> TokenPair:
    refresh, refresh_hash = new_refresh_token()
    db.add(
        SessionToken(
            user_id=user.id,
            token_hash=refresh_hash,
            device_name=device_name[:120],
            expires_at=datetime.now(UTC) + timedelta(days=settings.refresh_token_days),
        )
    )
    db.commit()
    return TokenPair(
        access_token=create_access_token(user.id),
        refresh_token=refresh,
        expires_in=settings.access_token_minutes * 60,
        user=UserOut.model_validate(user),
    )


@router.post("/auth/register", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
def register(data: RegisterIn, db: Session = Depends(get_db)) -> TokenPair:
    user = User(
        email=data.email.lower(),
        username=data.username.lower(),
        display_name=data.display_name.strip(),
        password_hash=hash_password(data.password),
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "El correo o usuario ya existe") from exc
    return token_pair(user, db, "Registro")


@router.post("/auth/login", response_model=TokenPair)
def login(data: LoginIn, db: Session = Depends(get_db)) -> TokenPair:
    identity = data.identity.lower().strip()
    enforce("login", identity, limit=10, window_seconds=900)
    user = db.scalar(select(User).where(or_(User.email == identity, User.username == identity)))
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Credenciales incorrectas")
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Cuenta desactivada")
    return token_pair(user, db, data.device_name)


@router.post("/auth/refresh", response_model=TokenPair)
def refresh(data: RefreshIn, db: Session = Depends(get_db)) -> TokenPair:
    session = db.scalar(
        select(SessionToken).where(
            SessionToken.token_hash == hash_token(data.refresh_token),
            SessionToken.revoked_at.is_(None),
        )
    )
    expiry = (
        session.expires_at.replace(tzinfo=UTC)
        if session and not session.expires_at.tzinfo
        else (session.expires_at if session else None)
    )
    if not session or not expiry or expiry <= datetime.now(UTC):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token de renovación inválido")
    session.revoked_at = now()
    user = db.get(User, session.user_id)
    if not user or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Cuenta no disponible")
    return token_pair(user, db, data.device_name)


@router.post("/auth/logout-all", status_code=status.HTTP_204_NO_CONTENT)
def logout_all(user: User = Depends(current_user), db: Session = Depends(get_db)) -> Response:
    sessions = db.scalars(
        select(SessionToken).where(
            SessionToken.user_id == user.id, SessionToken.revoked_at.is_(None)
        )
    )
    for session in sessions:
        session.revoked_at = now()
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/auth/password/forgot", status_code=status.HTTP_202_ACCEPTED)
def forgot_password(data: PasswordForgotIn, db: Session = Depends(get_db)) -> dict:
    identity = data.identity.lower().strip()
    enforce("password-forgot", identity, limit=3, window_seconds=900)
    generic_response = {"message": "Si la cuenta existe, se envió un código a su correo."}
    user = db.scalar(select(User).where(or_(User.email == identity, User.username == identity)))
    if not user or not user.is_active:
        return generic_response
    for previous in db.scalars(
        select(PasswordResetCode).where(
            PasswordResetCode.user_id == user.id, PasswordResetCode.used_at.is_(None)
        )
    ):
        previous.used_at = now()
    code, code_hash = new_reset_code()
    db.add(
        PasswordResetCode(
            user_id=user.id,
            code_hash=code_hash,
            expires_at=datetime.now(UTC)
            + timedelta(minutes=settings.password_reset_code_minutes),
        )
    )
    db.commit()
    send_email(
        user.email,
        "Código para restablecer tu contraseña de inspíraT",
        (
            f"Hola {user.display_name},\n\n"
            f"Tu código para restablecer la contraseña es: {code}\n"
            f"Vence en {settings.password_reset_code_minutes} minutos.\n\n"
            "Si no lo solicitaste, puedes ignorar este mensaje."
        ),
    )
    return generic_response


@router.post("/auth/password/reset", response_model=TokenPair)
def reset_password(data: PasswordResetIn, db: Session = Depends(get_db)) -> TokenPair:
    identity = data.identity.lower().strip()
    enforce("password-reset", identity, limit=8, window_seconds=900)
    invalid = HTTPException(status.HTTP_400_BAD_REQUEST, "Código inválido o vencido")
    user = db.scalar(select(User).where(or_(User.email == identity, User.username == identity)))
    if not user:
        raise invalid
    reset_code = db.scalar(
        select(PasswordResetCode)
        .where(
            PasswordResetCode.user_id == user.id,
            PasswordResetCode.code_hash == hash_token(data.code),
            PasswordResetCode.used_at.is_(None),
        )
        .order_by(PasswordResetCode.created_at.desc())
    )
    expiry = (
        reset_code.expires_at
        if reset_code and reset_code.expires_at.tzinfo
        else (reset_code.expires_at.replace(tzinfo=UTC) if reset_code else None)
    )
    if not reset_code or not expiry or expiry <= datetime.now(UTC):
        raise invalid
    reset_code.used_at = now()
    user.password_hash = hash_password(data.new_password)
    for session in db.scalars(
        select(SessionToken).where(
            SessionToken.user_id == user.id, SessionToken.revoked_at.is_(None)
        )
    ):
        session.revoked_at = now()
    db.commit()
    return token_pair(user, db, data.device_name)


@router.get("/users/me", response_model=UserOut)
def me(user: User = Depends(current_user)) -> User:
    return user


@router.get("/projects", response_model=list[ProjectOut])
def list_projects(
    user: User = Depends(current_user), db: Session = Depends(get_db)
) -> list[Project]:
    return list(
        db.scalars(
            select(Project)
            .where(Project.owner_id == user.id, Project.deleted_at.is_(None))
            .order_by(Project.updated_at.desc())
        )
    )


def existing_project_by_client_id(client_id: str, user: User, db: Session) -> Project | None:
    return db.scalar(
        select(Project).where(Project.owner_id == user.id, Project.client_id == client_id)
    )


@router.post("/projects", response_model=ProjectOut, status_code=status.HTTP_201_CREATED)
def create_project(
    data: ProjectIn, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> Project:
    existing = existing_project_by_client_id(data.client_id, user, db)
    if existing:
        return existing
    project = Project(owner_id=user.id, **data.model_dump())
    db.add(project)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = existing_project_by_client_id(data.client_id, user, db)
        if existing:
            return existing
        raise
    db.refresh(project)
    return project


@router.patch("/projects/{project_id}", response_model=ProjectOut)
def update_project(
    project_id: str,
    data: ProjectIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Project:
    project = owned_project(project_id, user, db)
    for key, value in data.model_dump(exclude={"client_id"}).items():
        setattr(project, key, value)
    project.revision += 1
    db.commit()
    db.refresh(project)
    return project


@router.delete("/projects/{project_id}", status_code=status.HTTP_204_NO_CONTENT)
def trash_project(
    project_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> Response:
    project = owned_project(project_id, user, db)
    project.deleted_at = now()
    project.revision += 1
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/projects/{project_id}/documents", response_model=list[DocumentOut])
def list_documents(
    project_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> list[Document]:
    owned_project(project_id, user, db)
    return list(
        db.scalars(
            select(Document)
            .where(Document.project_id == project_id, Document.deleted_at.is_(None))
            .order_by(Document.position, Document.created_at)
        )
    )


def existing_document_by_client_id(
    project_id: str, client_id: str, db: Session
) -> Document | None:
    return db.scalar(
        select(Document).where(
            Document.project_id == project_id, Document.client_id == client_id
        )
    )


@router.post(
    "/projects/{project_id}/documents",
    response_model=DocumentOut,
    status_code=status.HTTP_201_CREATED,
)
def create_document(
    project_id: str,
    data: DocumentIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Document:
    project = owned_project(project_id, user, db)
    existing = existing_document_by_client_id(project.id, data.client_id, db)
    if existing:
        return existing
    if len(data.content) > settings.max_document_chars:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Documento demasiado grande")
    document = Document(
        project_id=project.id,
        word_count=len(data.content.split()),
        **data.model_dump(),
    )
    db.add(document)
    project.revision += 1
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = existing_document_by_client_id(project.id, data.client_id, db)
        if existing:
            return existing
        raise
    db.refresh(document)
    return document


@router.get("/documents/{document_id}", response_model=DocumentOut)
def get_document(
    document_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> Document:
    document, _ = document_access(document_id, user, db)
    return document


@router.put(
    "/documents/{document_id}",
    response_model=DocumentOut,
    responses={409: {"description": "Conflicto: se conservan ambas versiones"}},
)
def update_document(
    document_id: str,
    data: DocumentUpdate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Document:
    document, owner = document_access(document_id, user, db, SharePermission.edit)
    if len(data.content) > settings.max_document_chars:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Documento demasiado grande")
    if data.base_revision != document.revision:
        backup = DocumentVersion(
            document_id=document.id,
            author_id=user.id,
            name=f"Conflicto conservado r{data.base_revision}",
            content=data.content,
            revision=data.base_revision,
            is_manual=True,
        )
        db.add(backup)
        db.commit()
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "message": (
                    "El servidor tiene cambios más recientes; tu texto quedó guardado como versión"
                ),
                "server": DocumentOut.model_validate(document).model_dump(mode="json"),
                "submitted_content": data.content,
                "backup_version_id": backup.id,
            },
        )
    if data.create_version or document.content != data.content:
        db.add(
            DocumentVersion(
                document_id=document.id,
                author_id=user.id,
                name=data.version_name or "Guardado automático",
                content=document.content,
                revision=document.revision,
                is_manual=data.create_version,
            )
        )
    document.content = data.content
    document.word_count = len(data.content.split())
    if data.title is not None:
        document.title = data.title
    document.revision += 1
    if owner:
        document.project.revision += 1
    db.commit()
    db.refresh(document)
    return document


@router.post("/documents/{document_id}/versions", response_model=VersionOut)
def create_version(
    document_id: str,
    data: VersionIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> DocumentVersion:
    document, _ = document_access(document_id, user, db, SharePermission.edit)
    version = DocumentVersion(
        document_id=document.id,
        author_id=user.id,
        name=data.name,
        content=document.content,
        revision=document.revision,
        is_manual=True,
    )
    db.add(version)
    db.commit()
    db.refresh(version)
    return version


@router.get("/documents/{document_id}/versions", response_model=list[VersionOut])
def list_versions(
    document_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> list[DocumentVersion]:
    document_access(document_id, user, db)
    return list(
        db.scalars(
            select(DocumentVersion)
            .where(DocumentVersion.document_id == document_id)
            .order_by(DocumentVersion.created_at.desc())
        )
    )


@router.post("/versions/{version_id}/restore", response_model=DocumentOut)
def restore_version(
    version_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> Document:
    version = db.get(DocumentVersion, version_id)
    if not version:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Versión no encontrada")
    document, _ = document_access(version.document_id, user, db, SharePermission.edit)
    db.add(
        DocumentVersion(
            document_id=document.id,
            author_id=user.id,
            name=f"Copia antes de restaurar {version.name}",
            content=document.content,
            revision=document.revision,
            is_manual=True,
        )
    )
    document.content = version.content
    document.word_count = len(version.content.split())
    document.revision += 1
    db.commit()
    db.refresh(document)
    return document


def existing_share(document_id: str, recipient_id: str, db: Session) -> Share | None:
    return db.scalar(
        select(Share).where(Share.document_id == document_id, Share.recipient_id == recipient_id)
    )


def apply_share(share: Share, data: ShareIn) -> None:
    share.permission = data.permission
    share.message = data.message
    share.expires_at = data.expires_at
    share.revoked_at = None


@router.post("/documents/{document_id}/shares", response_model=ShareOut)
def share_document(
    document_id: str,
    data: ShareIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Share:
    document, owner = document_access(document_id, user, db)
    if not owner:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Solo el propietario puede compartir")
    recipient_key = data.recipient.lower().strip()
    recipient = db.scalar(
        select(User).where(
            User.is_active.is_(True),
            or_(User.email == recipient_key, User.username == recipient_key),
        )
    )
    if not recipient:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Destinatario no encontrado")
    if recipient.id == user.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "No puedes enviártelo a ti mismo")
    share = existing_share(document.id, recipient.id, db)
    if share:
        apply_share(share, data)
    else:
        share = Share(
            document_id=document.id,
            sender_id=user.id,
            recipient_id=recipient.id,
            permission=data.permission,
            message=data.message,
            expires_at=data.expires_at,
        )
        db.add(share)
    db.add(
        Notification(
            user_id=recipient.id,
            kind="share",
            title=f"{user.display_name} compartió «{document.title}»",
            body=data.message,
            resource_id=document.id,
        )
    )
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        share = existing_share(document.id, recipient.id, db)
        if share is None:
            raise
        apply_share(share, data)
        db.add(
            Notification(
                user_id=recipient.id,
                kind="share",
                title=f"{user.display_name} compartió «{document.title}»",
                body=data.message,
                resource_id=document.id,
            )
        )
        db.commit()
    db.refresh(share)
    return share


@router.delete("/shares/{share_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_share(
    share_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> Response:
    share = db.get(Share, share_id)
    if not share or share.sender_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Envío no encontrado")
    share.revoked_at = now()
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/shares/inbox", response_model=list[InboxItem])
def inbox(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> list[InboxItem]:
    shares = list(
        db.scalars(
            select(Share)
            .where(
                Share.recipient_id == user.id,
                Share.revoked_at.is_(None),
                or_(Share.expires_at.is_(None), Share.expires_at > now()),
            )
            .order_by(Share.created_at.desc())
            .offset(offset)
            .limit(limit)
        )
    )
    if not shares:
        return []
    document_ids = {share.document_id for share in shares}
    sender_ids = {share.sender_id for share in shares}
    documents_by_id = {
        document.id: document
        for document in db.scalars(select(Document).where(Document.id.in_(document_ids)))
    }
    senders_by_id = {
        sender.id: sender for sender in db.scalars(select(User).where(User.id.in_(sender_ids)))
    }
    result = []
    for share in shares:
        document = documents_by_id.get(share.document_id)
        sender = senders_by_id.get(share.sender_id)
        if document is None or sender is None:
            continue
        result.append(
            InboxItem(
                **ShareOut.model_validate(share).model_dump(),
                document=DocumentOut.model_validate(document),
                sender_name=sender.display_name,
            )
        )
    return result


@router.post("/documents/{document_id}/comments", response_model=CommentOut)
def add_comment(
    document_id: str,
    data: CommentIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Comment:
    document, owner = document_access(document_id, user, db, SharePermission.comment)
    comment = Comment(document_id=document.id, author_id=user.id, **data.model_dump())
    db.add(comment)
    if not owner:
        db.add(
            Notification(
                user_id=document.project.owner_id,
                kind="comment",
                title=f"Nuevo comentario en «{document.title}»",
                body=data.body[:300],
                resource_id=document.id,
            )
        )
    db.commit()
    db.refresh(comment)
    return comment


@router.get("/documents/{document_id}/comments", response_model=list[CommentOut])
def list_comments(
    document_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> list[Comment]:
    document_access(document_id, user, db)
    return list(
        db.scalars(
            select(Comment)
            .where(Comment.document_id == document_id)
            .order_by(Comment.created_at.asc())
        )
    )


@router.get("/search")
def search(
    q: str = Query(min_length=2, max_length=100),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    pattern = f"%{q}%"
    projects = list(
        db.scalars(
            select(Project).where(
                Project.owner_id == user.id,
                Project.deleted_at.is_(None),
                or_(Project.title.ilike(pattern), Project.synopsis.ilike(pattern)),
            )
        )
    )
    documents = list(
        db.scalars(
            select(Document)
            .join(Project)
            .where(
                Project.owner_id == user.id,
                Document.deleted_at.is_(None),
                or_(Document.title.ilike(pattern), Document.content.ilike(pattern)),
            )
        )
    )
    return {
        "projects": [ProjectOut.model_validate(item) for item in projects],
        "documents": [DocumentOut.model_validate(item) for item in documents],
    }


@router.post("/sync", response_model=SyncResponse)
def sync(
    data: SyncRequest,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> SyncResponse:
    accepted: list[dict] = []
    conflicts: list[dict] = []
    for change in data.changes:
        try:
            with db.begin_nested():
                if change.entity == "project" and change.operation == "upsert":
                    existing = db.scalar(
                        select(Project).where(
                            Project.owner_id == user.id, Project.client_id == change.client_id
                        )
                    )
                    if (
                        existing
                        and change.base_revision
                        and existing.revision != change.base_revision
                    ):
                        conflicts.append(
                            {
                                "entity": "project",
                                "client_id": change.client_id,
                                "server_revision": existing.revision,
                                "server": ProjectOut.model_validate(existing).model_dump(
                                    mode="json"
                                ),
                                "submitted": change.payload,
                            }
                        )
                        continue
                    if not existing:
                        validated = ProjectIn.model_validate(
                            {"client_id": change.client_id, **change.payload}
                        )
                        existing = Project(owner_id=user.id, **validated.model_dump())
                        db.add(existing)
                    else:
                        for key, value in change.payload.items():
                            if key in ProjectIn.model_fields and key != "client_id":
                                setattr(existing, key, value)
                        existing.revision += 1
                    db.flush()
                    accepted.append(
                        {
                            "entity": "project",
                            "client_id": change.client_id,
                            "server_id": existing.id,
                        }
                    )
                elif change.entity == "document" and change.operation == "upsert":
                    project_client_id = change.payload.get("project_client_id")
                    project = db.scalar(
                        select(Project).where(
                            Project.owner_id == user.id, Project.client_id == project_client_id
                        )
                    )
                    if not project:
                        conflicts.append(
                            {
                                "entity": "document",
                                "client_id": change.client_id,
                                "reason": "parent_missing",
                                "submitted": change.payload,
                            }
                        )
                        continue
                    content = change.payload.get("content")
                    if isinstance(content, str) and len(content) > settings.max_document_chars:
                        conflicts.append(
                            {
                                "entity": "document",
                                "client_id": change.client_id,
                                "reason": "content_too_large",
                                "submitted": {"content": None, **change.payload},
                            }
                        )
                        continue
                    existing = db.scalar(
                        select(Document).where(
                            Document.project_id == project.id,
                            Document.client_id == change.client_id,
                        )
                    )
                    if (
                        existing
                        and change.base_revision
                        and existing.revision != change.base_revision
                    ):
                        db.add(
                            DocumentVersion(
                                document_id=existing.id,
                                author_id=user.id,
                                name=f"Conflicto móvil r{change.base_revision}",
                                content=str(change.payload.get("content", "")),
                                revision=change.base_revision,
                                is_manual=True,
                            )
                        )
                        conflicts.append(
                            {
                                "entity": "document",
                                "client_id": change.client_id,
                                "server_revision": existing.revision,
                                "server": DocumentOut.model_validate(existing).model_dump(
                                    mode="json"
                                ),
                                "submitted": change.payload,
                            }
                        )
                        continue
                    payload = dict(change.payload)
                    payload.pop("project_client_id", None)
                    validated = DocumentIn.model_validate(
                        {"client_id": change.client_id, **payload}
                    )
                    if not existing:
                        existing = Document(
                            project_id=project.id,
                            word_count=len(validated.content.split()),
                            **validated.model_dump(),
                        )
                        db.add(existing)
                    else:
                        db.add(
                            DocumentVersion(
                                document_id=existing.id,
                                author_id=user.id,
                                name="Antes de sincronizar",
                                content=existing.content,
                                revision=existing.revision,
                            )
                        )
                        for key, value in validated.model_dump(exclude={"client_id"}).items():
                            setattr(existing, key, value)
                        existing.word_count = len(existing.content.split())
                        existing.revision += 1
                    db.flush()
                    accepted.append(
                        {
                            "entity": "document",
                            "client_id": change.client_id,
                            "server_id": existing.id,
                        }
                    )
        except (ValidationError, IntegrityError) as exc:
            conflicts.append(
                {
                    "entity": change.entity,
                    "client_id": change.client_id,
                    "reason": "invalid_payload"
                    if isinstance(exc, ValidationError)
                    else "integrity_error",
                    "submitted": change.payload,
                }
            )
    db.commit()
    project_query = select(Project).where(Project.owner_id == user.id, Project.deleted_at.is_(None))
    if data.since:
        project_query = project_query.where(Project.updated_at >= data.since)
    projects = list(db.scalars(project_query))
    project_ids = [
        item.id for item in db.scalars(select(Project).where(Project.owner_id == user.id))
    ]
    document_query = select(Document).where(
        Document.project_id.in_(project_ids), Document.deleted_at.is_(None)
    )
    if data.since:
        document_query = document_query.where(Document.updated_at >= data.since)
    documents = list(db.scalars(document_query))
    return SyncResponse(
        accepted=accepted,
        conflicts=conflicts,
        projects=[ProjectOut.model_validate(item) for item in projects],
        documents=[DocumentOut.model_validate(item) for item in documents],
        server_time=now(),
    )


@router.get("/documents/{document_id}/export")
def export_document(
    document_id: str,
    format: str = Query(default="txt", pattern="^(txt|md|pdf)$"),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Response:
    document, _ = document_access(document_id, user, db)
    ascii_title = (
        unicodedata.normalize("NFKD", document.title).encode("ascii", "ignore").decode("ascii")
    )
    filename = "".join(c for c in ascii_title if c.isalnum() or c in " -_").strip() or "escrito"
    if format in {"txt", "md"}:
        content = document.content
        if format == "md":
            content = f"# {document.title}\n\n{content}"
        return Response(
            content=content.encode("utf-8"),
            media_type="text/plain; charset=utf-8" if format == "txt" else "text/markdown",
            headers={"Content-Disposition": f'attachment; filename="{filename}.{format}"'},
        )
    buffer = BytesIO()
    story = [Paragraph(document.title, getSampleStyleSheet()["Title"]), Spacer(1, 18)]
    for paragraph in document.content.splitlines():
        story.append(Paragraph(paragraph or " ", getSampleStyleSheet()["BodyText"]))
        story.append(Spacer(1, 8))
    SimpleDocTemplate(buffer, pagesize=A4, title=document.title, author=user.display_name).build(
        story
    )
    return Response(
        content=buffer.getvalue(),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}.pdf"'},
    )
