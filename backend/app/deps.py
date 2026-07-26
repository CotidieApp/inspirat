from datetime import UTC, datetime

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import CommunityMessage, Document, Project, Share, SharePermission, User
from app.security import decode_access_token

bearer = HTTPBearer(auto_error=False)


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sesión requerida")
    try:
        user_id = decode_access_token(credentials.credentials)
    except jwt.PyJWTError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sesión caducada o inválida") from exc
    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Cuenta no disponible")
    return user


def owned_project(project_id: str, user: User, db: Session) -> Project:
    project = db.scalar(
        select(Project).where(
            Project.id == project_id, Project.owner_id == user.id, Project.deleted_at.is_(None)
        )
    )
    if not project:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Proyecto no encontrado")
    return project


def document_access(
    document_id: str, user: User, db: Session, require: SharePermission = SharePermission.read
) -> tuple[Document, bool]:
    document = db.get(Document, document_id)
    if not document or document.deleted_at or document.project.deleted_at:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Documento no encontrado")
    if document.project.owner_id == user.id:
        return document, True
    if require in {SharePermission.read, SharePermission.comment}:
        published = db.scalar(
            select(CommunityMessage.id).where(
                CommunityMessage.channel == "general",
                CommunityMessage.document_id == document_id,
            )
        )
        if published:
            return document, False
    allowed = {
        SharePermission.read: list(SharePermission),
        SharePermission.comment: [
            SharePermission.comment,
            SharePermission.suggest,
            SharePermission.edit,
        ],
        SharePermission.edit: [SharePermission.edit],
    }[require]
    share = db.scalar(
        select(Share).where(
            Share.document_id == document_id,
            Share.recipient_id == user.id,
            Share.permission.in_(allowed),
            Share.revoked_at.is_(None),
            or_(Share.expires_at.is_(None), Share.expires_at > datetime.now(UTC)),
        )
    )
    if not share:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "No tienes permiso para esta acción")
    return document, False
