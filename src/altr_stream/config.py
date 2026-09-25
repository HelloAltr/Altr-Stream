"""Application settings and configuration."""

from typing import Any
from pathlib import Path
from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from altr_stream.__version__ import __version__


class Settings(BaseSettings):
    """Altr Stream configuration settings."""

    app_name: str = "Altr Stream"
    app_version: str = __version__
    simulated_version: str | None = None
    debug: bool = False
    host: str = "0.0.0.0"
    port: int = 8000

    # Local SQLite metadata store path
    data_dir: Path = Path("data")
    database_url: str = "sqlite+aiosqlite:///data/altr_stream.db"

    # Static assets directory for Flutter Web SPA
    static_dir: Path | None = Path("/app/static")

    # Security & Encryption
    encryption_key: str | None = None

    # Update IPC directory
    updates_dir: Path = Path("data/updates")

    # Connection timeouts
    default_connection_timeout_sec: float = 5.0

    model_config = SettingsConfigDict(
        env_prefix="ALTR_STREAM_",
        env_file=".env",
        extra="ignore",
    )

    @field_validator("app_version", mode="before")
    @classmethod
    def _validate_app_version(cls, v: Any) -> str:
        """Ensure empty or blank version strings safely default to canonical version."""
        if v is None or not str(v).strip():
            return __version__
        return str(v).strip()

    def model_post_init(self, __context: Any) -> None:
        """Apply test simulation override if specified."""
        super().model_post_init(__context)
        if self.simulated_version and self.simulated_version.strip():
            self.app_version = self.simulated_version.strip()


settings = Settings()
