"""Application settings and configuration."""

from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Altr Stream configuration settings."""

    app_name: str = "Altr Stream"
    app_version: str = "0.1.0"
    debug: bool = False
    host: str = "0.0.0.0"
    port: int = 8000

    # Local SQLite metadata store path
    data_dir: Path = Path("data")
    database_url: str = "sqlite+aiosqlite:///data/altr_stream.db"

    # Connection timeouts
    default_connection_timeout_sec: float = 5.0

    model_config = SettingsConfigDict(
        env_prefix="ALTR_STREAM_",
        env_file=".env",
        extra="ignore",
    )


settings = Settings()
