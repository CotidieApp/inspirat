
import hashlib
import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, case, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.deps import current_user
from app.models import (
    CommunityMessage,
    CommunityPublication,
    Document,
    Notification,
    Share,
    SharePermission,
    User,
    now,
)
from app.schemas import (
    ChatMessageIn,
    ChatMessageOut,
    CommunityPublishIn,
    CommunityPublishOut,
    ConversationOut,
    DocumentOut,
    ReadReceiptOut,
    UserPublic,
)

router = APIRouter(prefix="/community", tags=["community"])
PUBLISH_CLIENT_NAMESPACE = uuid.UUID("635998e9-8359-4492-90f1-d659655a8529")


def public_user(user: User) -> UserPublic:
    return UserPublic.model_validate(user)


def message_out(message: CommunityMessage) -> ChatMessageOut:
    document = message.document
    if document is not None and document.deleted_at is not None:
        document = None
    return ChatMessageOut(
        id=message.id,
        client_id=message.client_id,
        sender=public_user(message.sender),
        recipient=public_user(message.recipient) if message.recipient else None,
        body=message.body,
        document=DocumentOut.model_validate(document) if document else None,
        created_at=message.created_at,
        read_at=message.read_at,
    )


def message_options():
    return (
        joinedload(CommunityMessage.sender),
        joinedload(CommunityMessage.recipient),
        joinedload(CommunityMessage.document),
    )


def publication_request_hash(data: CommunityPublishIn) -> str:
    canonical = json.dumps(
        {
            "body": data.body,
            "document_id": data.document_id,
            "publish_general": data.publish_general,
            "recipient_ids": data.recipient_ids,
        },
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def publication_messages(
    publication_id: str,
    db: Session,
) -> list[CommunityMessage]:
    messages = list(
        db.scalars(
            select(CommunityMessage)
            .where(CommunityMessage.publication_id == publication_id)
            .options(*message_options())
        )
    )
    return sorted(
        messages,
        key=lambda message: (
            0 if message.channel == "general" else 1,
            message.recipient_id or "",
        ),
    )


def publication_out(
    publication: CommunityPublication,
    created: bool,
    db: Session,
) -> CommunityPublishOut:
    return CommunityPublishOut(
        client_id=publication.client_id,
        created=created,
        messages=[
            message_out(message)
            for message in publication_messages(publication.id, db)
        ],
    )


def existing_publication(
    sender: User,
    client_id: str,
    request_hash: str,
    db: Session,
) -> CommunityPublication | None:
    publication = db.scalar(
        select(CommunityPublication).where(
            CommunityPublication.sender_id == sender.id,
            CommunityPublication.client_id == client_id,
        )
    )
    if publication is not None and publication.request_hash != request_hash:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "El identificador local ya fue usado por otra publicación",
        )
    return publication


def publication_message_client_id(base_client_id: str, destination: str) -> str:
    return str(
        uuid.uuid5(
            PUBLISH_CLIENT_NAMESPACE,
            f"{base_client_id}:{destination}",
        )
    )


def owned_attachment(document_id: str | None, user: User, db: Session) -> Document | None:
    if document_id is None:
        return None
    document = db.get(Document, document_id)
    if (
        document is None
        or document.deleted_at is not None
        or document.project.deleted_at is not None
    ):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Documento no encontrado")
    if document.project.owner_id != user.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Solo puedes adjuntar documentos propios",
        )
    return document


def active_peer(peer_id: str, current: User, db: Session) -> User:
    peer = db.scalar(select(User).where(User.id == peer_id, User.is_active.is_(True)))
    if peer is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Usuario no encontrado")
    if peer.id == current.id:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "No puedes abrir un chat directo contigo",
        )
    return peer


def direct_pair(user_id: str, peer_id: str):
    return or_(
        and_(
            CommunityMessage.sender_id == user_id,
            CommunityMessage.recipient_id == peer_id,
        ),
        and_(
            CommunityMessage.sender_id == peer_id,
            CommunityMessage.recipient_id == user_id,
        ),
    )


def existing_client_message(
    data: ChatMessageIn,
    channel: str,
    sender: User,
    recipient_id: str | None,
    db: Session,
) -> CommunityMessage | None:
    if data.client_id is None:
        return None
    existing = db.scalar(
        select(CommunityMessage)
        .where(
            CommunityMessage.sender_id == sender.id,
            CommunityMessage.client_id == data.client_id,
        )
        .options(*message_options())
    )
    if existing is None:
        return None
    if (
        existing.channel != channel
        or existing.recipient_id != recipient_id
        or existing.body != data.body
        or existing.document_id != data.document_id
    ):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "El identificador local ya fue usado por otro mensaje",
        )
    return existing


def flush_message(
    message: CommunityMessage,
    data: ChatMessageIn,
    channel: str,
    sender: User,
    recipient_id: str | None,
    db: Session,
) -> tuple[CommunityMessage, bool]:
    db.add(message)
    try:
        db.flush()
        return message, True
    except IntegrityError:
        db.rollback()
        existing = existing_client_message(data, channel, sender, recipient_id, db)
        if existing is not None:
            return existing, False
        raise


def ensure_comment_share(
    document: Document,
    sender: User,
    recipient: User,
    message: str,
    db: Session,
) -> None:
    share = db.scalar(
        select(Share).where(
            Share.document_id == document.id,
            Share.recipient_id == recipient.id,
        )
    )
    if share is None:
        db.add(
            Share(
                document_id=document.id,
                sender_id=sender.id,
                recipient_id=recipient.id,
                permission=SharePermission.comment,
                message=message[:500],
            )
        )
        return
    if share.permission == SharePermission.read:
        share.permission = SharePermission.comment
    share.sender_id = sender.id
    share.message = message[:500]
    share.revoked_at = None
    share.expires_at = None


@router.post("/publish", response_model=CommunityPublishOut)
def publish_to_community(
    data: CommunityPublishIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> CommunityPublishOut:
    request_hash = publication_request_hash(data)
    previous = existing_publication(user, data.client_id, request_hash, db)
    if previous is not None:
        return publication_out(previous, False, db)

    document = owned_attachment(data.document_id, user, db)
    if user.id in data.recipient_ids:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "No puedes enviarte una publicación a ti mismo",
        )
    recipients = list(
        db.scalars(
            select(User).where(
                User.id.in_(data.recipient_ids),
                User.is_active.is_(True),
            )
        )
    )
    recipients_by_id = {recipient.id: recipient for recipient in recipients}
    if set(recipients_by_id) != set(data.recipient_ids):
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "Uno o más destinatarios no están disponibles",
        )

    destinations = (["general"] if data.publish_general else []) + [
        f"direct:{recipient_id}" for recipient_id in data.recipient_ids
    ]
    child_client_ids = [
        publication_message_client_id(data.client_id, destination)
        for destination in destinations
    ]
    collision = db.scalar(
        select(CommunityMessage.id).where(
            CommunityMessage.sender_id == user.id,
            CommunityMessage.client_id.in_(child_client_ids),
        )
    )
    if collision is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Un identificador derivado ya pertenece a otro mensaje",
        )

    publication = CommunityPublication(
        sender_id=user.id,
        client_id=data.client_id,
        request_hash=request_hash,
    )
    messages: list[CommunityMessage] = []
    try:
        db.add(publication)
        db.flush()
        if data.publish_general:
            messages.append(
                CommunityMessage(
                    client_id=publication_message_client_id(data.client_id, "general"),
                    publication_id=publication.id,
                    channel="general",
                    sender_id=user.id,
                    body=data.body,
                    document_id=document.id if document else None,
                )
            )
        for recipient_id in data.recipient_ids:
            recipient = recipients_by_id[recipient_id]
            if document is not None:
                ensure_comment_share(document, user, recipient, data.body, db)
            messages.append(
                CommunityMessage(
                    client_id=publication_message_client_id(
                        data.client_id,
                        f"direct:{recipient_id}",
                    ),
                    publication_id=publication.id,
                    channel="direct",
                    sender_id=user.id,
                    recipient_id=recipient.id,
                    body=data.body,
                    document_id=document.id if document else None,
                )
            )
        db.add_all(messages)
        db.flush()
        for message in messages:
            if message.recipient_id is None:
                continue
            db.add(
                Notification(
                    user_id=message.recipient_id,
                    kind="direct_message",
                    title=f"Nuevo mensaje de {user.display_name}",
                    body=(
                        data.body[:500]
                        if data.body
                        else f"Compartió «{document.title}»"
                    ),
                    resource_id=message.id,
                )
            )
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        previous = existing_publication(user, data.client_id, request_hash, db)
        if previous is not None:
            return publication_out(previous, False, db)
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "No se pudo reservar la publicación; vuelve a intentarlo",
        ) from exc
    except Exception:
        db.rollback()
        raise
    return publication_out(publication, True, db)


@router.get("/users", response_model=list[UserPublic])
def list_public_users(
    q: str | None = Query(default=None, min_length=1, max_length=100),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> list[User]:
    query = select(User).where(User.is_active.is_(True), User.id != user.id)
    if q:
        escaped = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        pattern = f"%{escaped}%"
        query = query.where(
            or_(
                User.username.ilike(pattern, escape="\\"),
                User.display_name.ilike(pattern, escape="\\"),
            )
        )
    return list(
        db.scalars(
            query.order_by(func.lower(User.display_name), User.username)
            .offset(offset)
            .limit(limit)
        )
    )


@router.get("/general/messages", response_model=list[ChatMessageOut])
def list_general_messages(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> list[ChatMessageOut]:
    del user
    messages = db.scalars(
        select(CommunityMessage)
        .where(CommunityMessage.channel == "general")
        .options(*message_options())
        .order_by(CommunityMessage.created_at.desc(), CommunityMessage.id.desc())
        .offset(offset)
        .limit(limit)
    )
    return [message_out(message) for message in messages]


@router.post(
    "/general/messages",
    response_model=ChatMessageOut,
    status_code=status.HTTP_201_CREATED,
)
def publish_general_message(
    data: ChatMessageIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ChatMessageOut:
    existing = existing_client_message(data, "general", user, None, db)
    if existing is not None:
        return message_out(existing)
    document = owned_attachment(data.document_id, user, db)
    message = CommunityMessage(
        client_id=data.client_id,
        channel="general",
        sender_id=user.id,
        body=data.body,
        document_id=document.id if document else None,
    )
    message, created = flush_message(message, data, "general", user, None, db)
    if not created:
        return message_out(message)
    db.commit()
    db.refresh(message)
    return message_out(message)


@router.get("/conversations", response_model=list[ConversationOut])
def list_conversations(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> list[ConversationOut]:
    peer_id = case(
        (CommunityMessage.sender_id == user.id, CommunityMessage.recipient_id),
        else_=CommunityMessage.sender_id,
    )
    peer_rows = list(
        db.execute(
            select(
                peer_id.label("peer_id"),
                func.max(CommunityMessage.created_at).label("last_created_at"),
            )
            .where(
                CommunityMessage.channel == "direct",
                or_(
                    CommunityMessage.sender_id == user.id,
                    CommunityMessage.recipient_id == user.id,
                ),
            )
            .group_by(peer_id)
            .order_by(func.max(CommunityMessage.created_at).desc())
            .offset(offset)
            .limit(limit)
        )
    )
    if not peer_rows:
        return []
    peer_ids = [row.peer_id for row in peer_rows]

    peers_by_id = {peer.id: peer for peer in db.scalars(select(User).where(User.id.in_(peer_ids)))}

    # Un solo round-trip para el ultimo mensaje de cada peer (rank=1 por
    # ventana), en vez de una query por conversacion — antes esto eran hasta
    # 3*N consultas (N = numero de conversaciones en la pagina).
    rank = func.row_number().over(
        partition_by=peer_id,
        order_by=(CommunityMessage.created_at.desc(), CommunityMessage.id.desc()),
    ).label("rank")
    ranked = (
        select(CommunityMessage.id, peer_id.label("peer_id"), rank)
        .where(
            CommunityMessage.channel == "direct",
            or_(
                and_(
                    CommunityMessage.sender_id == user.id,
                    CommunityMessage.recipient_id.in_(peer_ids),
                ),
                and_(
                    CommunityMessage.recipient_id == user.id,
                    CommunityMessage.sender_id.in_(peer_ids),
                ),
            ),
        )
        .subquery()
    )
    message_id_to_peer = {
        row.id: row.peer_id
        for row in db.execute(
            select(ranked.c.id, ranked.c.peer_id).where(ranked.c.rank == 1)
        )
    }
    messages_by_id = {
        message.id: message
        for message in db.scalars(
            select(CommunityMessage)
            .options(*message_options())
            .where(CommunityMessage.id.in_(message_id_to_peer.keys()))
        )
    }
    last_message_by_peer = {
        peer: messages_by_id[message_id]
        for message_id, peer in message_id_to_peer.items()
        if message_id in messages_by_id
    }

    unread_by_peer = dict(
        db.execute(
            select(CommunityMessage.sender_id, func.count())
            .where(
                CommunityMessage.channel == "direct",
                CommunityMessage.sender_id.in_(peer_ids),
                CommunityMessage.recipient_id == user.id,
                CommunityMessage.read_at.is_(None),
            )
            .group_by(CommunityMessage.sender_id)
        ).all()
    )

    conversations: list[ConversationOut] = []
    for peer_id_value in peer_ids:
        peer = peers_by_id.get(peer_id_value)
        last_message = last_message_by_peer.get(peer_id_value)
        if peer is None or last_message is None:
            continue
        conversations.append(
            ConversationOut(
                user=public_user(peer),
                last_message=message_out(last_message),
                unread_count=unread_by_peer.get(peer_id_value, 0),
            )
        )
    return conversations


@router.get("/direct/{peer_id}/messages", response_model=list[ChatMessageOut])
def list_direct_messages(
    peer_id: str,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> list[ChatMessageOut]:
    peer = active_peer(peer_id, user, db)
    messages = db.scalars(
        select(CommunityMessage)
        .where(
            CommunityMessage.channel == "direct",
            direct_pair(user.id, peer.id),
        )
        .options(*message_options())
        .order_by(CommunityMessage.created_at.desc(), CommunityMessage.id.desc())
        .offset(offset)
        .limit(limit)
    )
    return [message_out(message) for message in messages]


@router.post(
    "/direct/{peer_id}/messages",
    response_model=ChatMessageOut,
    status_code=status.HTTP_201_CREATED,
)
def send_direct_message(
    peer_id: str,
    data: ChatMessageIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ChatMessageOut:
    peer = active_peer(peer_id, user, db)
    existing = existing_client_message(data, "direct", user, peer.id, db)
    if existing is not None:
        return message_out(existing)
    document = owned_attachment(data.document_id, user, db)
    if document:
        ensure_comment_share(document, user, peer, data.body, db)
    message = CommunityMessage(
        client_id=data.client_id,
        channel="direct",
        sender_id=user.id,
        recipient_id=peer.id,
        body=data.body,
        document_id=document.id if document else None,
    )
    message, created = flush_message(message, data, "direct", user, peer.id, db)
    if not created:
        return message_out(message)
    db.add(
        Notification(
            user_id=peer.id,
            kind="direct_message",
            title=f"Nuevo mensaje de {user.display_name}",
            body=data.body[:500] if data.body else f"Compartió «{document.title}»",
            resource_id=message.id,
        )
    )
    db.commit()
    db.refresh(message)
    return message_out(message)


@router.post("/direct/{peer_id}/read", response_model=ReadReceiptOut)
def mark_direct_messages_read(
    peer_id: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ReadReceiptOut:
    peer = active_peer(peer_id, user, db)
    read_at = now()
    result = db.execute(
        update(CommunityMessage)
        .where(
            CommunityMessage.channel == "direct",
            CommunityMessage.sender_id == peer.id,
            CommunityMessage.recipient_id == user.id,
            CommunityMessage.read_at.is_(None),
        )
        .values(read_at=read_at)
    )
    db.commit()
    return ReadReceiptOut(updated=result.rowcount or 0, read_at=read_at)


@router.get("/messages/{message_id}", response_model=ChatMessageOut)
def get_community_message(
    message_id: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> ChatMessageOut:
    message = db.scalar(
        select(CommunityMessage)
        .where(CommunityMessage.id == message_id)
        .options(*message_options())
    )
    if message is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Mensaje no encontrado")
    if message.channel == "direct" and user.id not in {
        message.sender_id,
        message.recipient_id,
    }:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "No puedes leer este chat")
    return message_out(message)
