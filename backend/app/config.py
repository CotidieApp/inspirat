from functools import lru_cache

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_SECRET_KEY = "development-only-change-me-please-32-chars"
KNOWN_PLACEHOLDER_SECRETS = {
    DEV_SECRET_KEY,
    "development-only-change-this-secret-key",
    "change-this-to-a-random-64-character-value",
}


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="INSPIRAT_", env_file="../.env", extra="ignore")

    app_name: str = "inspíraT"
    technical_name: str = "inspirat"
    api_prefix: str = "/api/v1"
    # Alias explicito: todos los compose/.env de este repo usan INSPIRAT_ENV,
    # no INSPIRAT_ENVIRONMENT (que es lo que el prefijo generaria solo).
    environment: str = Field(default="development", validation_alias="INSPIRAT_ENV")
    secret_key: str = DEV_SECRET_KEY
    database_url: str = "sqlite:///./inspirat.db"
    redis_url: str = "redis://localhost:6379/0"
    public_url: str = "http://localhost:8000"
    cors_origins: str = "http://localhost:3000"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    max_document_chars: int = 2_000_000

    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_use_tls: bool = True
    smtp_from_email: str = "no-reply@inspirat.app"
    smtp_from_name: str = "inspíraT"
    password_reset_code_minutes: int = 15

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"

    @model_validator(mode="after")
    def _guard_production(self) -> "Settings":
        if self.is_production:
            if self.secret_key in KNOWN_PLACEHOLDER_SECRETS or len(self.secret_key) < 32:
                raise ValueError(
                    "INSPIRAT_SECRET_KEY debe ser un valor propio de al menos 32 "
                    "caracteres en produccion (INSPIRAT_ENV=production)."
                )
            if self.database_url.startswith("sqlite"):
                raise ValueError(
                    "INSPIRAT_DATABASE_URL no puede ser sqlite en produccion "
                    "(INSPIRAT_ENV=production); usa Postgres."
                )
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
