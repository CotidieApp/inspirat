from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator

from app.models import ProjectStatus, SharePermission


class ApiModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class RegisterIn(ApiModel):
    email: EmailStr
    username: str = Field(min_length=3, max_length=40, pattern=r"^[a-zA-Z0-9_.-]+$")
    display_name: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=10, max_length=128)
    accepted_terms: bool

    @field_validator("accepted_terms")
    @classmethod
    def terms_required(cls, value: bool) -> bool:
        if not value:
            raise ValueError("Debes aceptar las condiciones y la política de privacidad")
        return value


class LoginIn(ApiModel):
    identity: str
    password: str
    device_name: str = "Android"


class RefreshIn(ApiModel):
    refresh_token: str
    device_name: str = "Android"


class PasswordForgotIn(ApiModel):
    identity: str = Field(min_length=3, max_length=320)


class PasswordResetIn(ApiModel):
    identity: str = Field(min_length=3, max_length=320)
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")
    new_password: str = Field(min_length=10, max_length=128)
    device_name: str = "Android"


class UserOut(ApiModel):
    id: str
    email: EmailStr
    username: str
    display_name: str


class UserPublic(ApiModel):
    id: str
    username: str
    display_name: str


class TokenPair(ApiModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserOut


class ProjectIn(ApiModel):
    client_id: str = Field(min_length=8, max_length=36)
    title: str = Field(min_length=1, max_length=240)
    subtitle: str | None = Field(default=None, max_length=240)
    work_type: str = Field(default="free", max_length=40)
    synopsis: str = Field(default="", max_length=20_000)
    status: ProjectStatus = ProjectStatus.draft
    color: str = Field(default="#1E5B57", pattern=r"^#[0-9A-Fa-f]{6,8}$")
    word_goal: int | None = Field(default=None, ge=0)


class ProjectOut(ProjectIn):
    id: str
    owner_id: str
    revision: int
    created_at: datetime
    updated_at: datetime


class DocumentIn(ApiModel):
    client_id: str = Field(min_length=8, max_length=36)
    title: str = Field(min_length=1, max_length=240)
    kind: str = Field(default="chapter", max_length=30)
    position: int = Field(default=0, ge=0)
    content: str = ""


class DocumentUpdate(ApiModel):
    title: str | None = Field(default=None, min_length=1, max_length=240)
    content: str
    base_revision: int = Field(ge=1)
    create_version: bool = False
    version_name: str | None = Field(default=None, max_length=120)


class DocumentOut(DocumentIn):
    id: str
    project_id: str
    word_count: int
    revision: int
    created_at: datetime
    updated_at: datetime


class ChatMessageIn(ApiModel):
    client_id: str | None = Field(default=None, min_length=8, max_length=36)
    body: str = Field(default="", max_length=4000)
    document_id: str | None = None

    @model_validator(mode="after")
    def require_body_or_document(self) -> "ChatMessageIn":
        self.body = self.body.strip()
        if not self.body and self.document_id is None:
            raise ValueError("El mensaje debe incluir texto o un documento")
        return self


class ChatMessageOut(ApiModel):
    id: str
    client_id: str | None
    sender: UserPublic
    recipient: UserPublic | None
    body: str
    document: DocumentOut | None
    created_at: datetime
    read_at: datetime | None


class CommunityPublishIn(ApiModel):
    client_id: str = Field(min_length=8, max_length=36)
    body: str = Field(default="", max_length=4000)
    document_id: str | None = None
    publish_general: bool = False
    recipient_ids: list[str] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def validate_publication(self) -> "CommunityPublishIn":
        self.body = self.body.strip()
        if not self.body and self.document_id is None:
            raise ValueError("La publicación debe incluir texto o un documento")
        if not self.publish_general and not self.recipient_ids:
            raise ValueError("Selecciona el chat general o al menos un destinatario")
        if len(set(self.recipient_ids)) != len(self.recipient_ids):
            raise ValueError("Los destinatarios no pueden repetirse")
        if any(
            len(recipient_id) < 8 or len(recipient_id) > 36
            for recipient_id in self.recipient_ids
        ):
            raise ValueError("Uno o más identificadores de destinatario no son válidos")
        self.recipient_ids = sorted(self.recipient_ids)
        return self


class CommunityPublishOut(ApiModel):
    client_id: str
    created: bool
    messages: list[ChatMessageOut]


class ConversationOut(ApiModel):
    user: UserPublic
    last_message: ChatMessageOut
    unread_count: int


class ReadReceiptOut(ApiModel):
    updated: int
    read_at: datetime


class ConflictOut(ApiModel):
    message: str
    server: DocumentOut
    submitted_content: str


class VersionIn(ApiModel):
    name: str = Field(default="Hito manual", min_length=1, max_length=120)


class VersionOut(ApiModel):
    id: str
    document_id: str
    author_id: str
    name: str
    content: str
    revision: int
    is_manual: bool
    created_at: datetime


class ShareIn(ApiModel):
    recipient: str
    permission: SharePermission = SharePermission.comment
    message: str = Field(default="", max_length=500)
    expires_at: datetime | None = None


class ShareOut(ApiModel):
    id: str
    document_id: str
    sender_id: str
    recipient_id: str
    permission: SharePermission
    message: str
    opened_at: datetime | None
    revoked_at: datetime | None
    expires_at: datetime | None
    created_at: datetime


class InboxItem(ShareOut):
    document: DocumentOut
    sender_name: str


class CommentIn(ApiModel):
    body: str = Field(min_length=1, max_length=4000)
    parent_id: str | None = None
    anchor_start: int | None = Field(default=None, ge=0)
    anchor_end: int | None = Field(default=None, ge=0)
    quoted_text: str | None = Field(default=None, max_length=1000)


class CommentOut(CommentIn):
    id: str
    document_id: str
    author_id: str
    resolved_at: datetime | None
    created_at: datetime


class SyncChange(ApiModel):
    entity: str
    operation: str
    client_id: str
    payload: dict
    base_revision: int | None = None


class SyncRequest(ApiModel):
    changes: list[SyncChange] = Field(default_factory=list, max_length=200)
    since: datetime | None = None


class SyncResponse(ApiModel):
    accepted: list[dict]
    conflicts: list[dict]
    projects: list[ProjectOut]
    documents: list[DocumentOut]
    server_time: datetime
