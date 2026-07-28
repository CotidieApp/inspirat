import smtplib
import ssl
from email.message import EmailMessage

import httpx
import structlog

from app.config import settings

logger = structlog.get_logger()


def _send_via_resend_api(to: str, subject: str, body: str) -> bool:
    try:
        response = httpx.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {settings.resend_api_key}"},
            json={
                "from": f"{settings.smtp_from_name} <{settings.smtp_from_email}>",
                "to": [to],
                "subject": subject,
                "text": body,
            },
            timeout=10,
        )
        response.raise_for_status()
        return True
    except httpx.HTTPError:
        logger.exception("resend_api_send_failed", to=to, subject=subject)
        return False


def _send_via_smtp(to: str, subject: str, body: str) -> bool:
    message = EmailMessage()
    message["From"] = f"{settings.smtp_from_name} <{settings.smtp_from_email}>"
    message["To"] = to
    message["Subject"] = subject
    message.set_content(body)
    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as server:
            if settings.smtp_use_tls:
                server.starttls(context=ssl.create_default_context())
            if settings.smtp_username and settings.smtp_password:
                server.login(settings.smtp_username, settings.smtp_password)
            server.send_message(message)
        return True
    except (OSError, smtplib.SMTPException):
        logger.exception("smtp_send_failed", to=to, subject=subject)
        return False


def send_email(to: str, subject: str, body: str) -> bool:
    if settings.resend_api_key:
        return _send_via_resend_api(to, subject, body)
    if settings.smtp_host:
        return _send_via_smtp(to, subject, body)
    logger.warning("email_not_configured", to=to, subject=subject)
    return False
