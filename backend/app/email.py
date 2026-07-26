import smtplib
import ssl
from email.message import EmailMessage

import structlog

from app.config import settings

logger = structlog.get_logger()


def send_email(to: str, subject: str, body: str) -> bool:
    if not settings.smtp_host:
        logger.warning("smtp_not_configured", to=to, subject=subject)
        return False
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
