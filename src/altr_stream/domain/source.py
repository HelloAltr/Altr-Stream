"""Source domain models."""

from datetime import datetime, timezone
from enum import Enum
from typing import Any
import uuid
from pydantic import BaseModel, Field


class SourceType(str, Enum):
    """Supported source connector types."""

    POSTGRESQL = "POSTGRESQL"
    SQLITE = "SQLITE"
    MYSQL = "MYSQL"
    MONGODB = "MONGODB"


class SourceStatus(str, Enum):
    """Source health and connectivity status."""

    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    ERROR = "ERROR"
    UNREACHABLE = "UNREACHABLE"
    UNKNOWN = "UNKNOWN"


class ConnectionConfig(BaseModel):
    """Connection parameters for physical data sources (relational network, file-based, or document)."""

    host: str | None = None
    port: int | None = None
    database_name: str | None = None
    username: str | None = None
    password: str | None = None
    file_path: str | None = None
    options: dict[str, Any] = Field(default_factory=dict)

    @property
    def resolved_host(self) -> str | None:
        """Return host resolved for container network access (e.g. localhost/127.0.0.1 -> host.docker.internal)."""
        from altr_stream.infrastructure.database.url_resolver import resolve_docker_host
        return resolve_docker_host(self.host)

    @classmethod
    def from_connection_url(cls, url: str) -> "ConnectionConfig":
        """Parse database connection URL into ConnectionConfig, preserving user-entered host while enabling runtime resolution."""
        import urllib.parse

        parsed = urllib.parse.urlsplit(url)
        db_name = parsed.path.lstrip("/") if parsed.path else None

        options: dict[str, Any] = {}
        if parsed.query:
            for k, v in urllib.parse.parse_qs(parsed.query).items():
                options[k] = v[0] if len(v) == 1 else v

        user = urllib.parse.unquote(parsed.username) if parsed.username else None
        pw = urllib.parse.unquote(parsed.password) if parsed.password else ""

        return cls(
            host=parsed.hostname,
            port=parsed.port,
            database_name=db_name,
            username=user,
            password=pw,
            options=options,
        )

    def masked_dict(self) -> dict[str, Any]:
        """Return parameters with password masked."""
        res: dict[str, Any] = {}
        if self.host is not None:
            res["host"] = self.host
        if self.port is not None:
            res["port"] = self.port
        if self.database_name is not None:
            res["database_name"] = self.database_name
        if self.username is not None:
            res["username"] = self.username
        if self.password is not None:
            res["password"] = "••••••••" if self.password else ""
        if self.file_path is not None:
            res["file_path"] = self.file_path
        if self.options:
            res["options"] = self.options
        return res


class Source(BaseModel):
    """Domain model representing a registered data source."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    type: SourceType = SourceType.POSTGRESQL
    host: str | None = None
    port: int | None = None
    database_name: str | None = None
    username: str | None = None
    password: str | None = None
    file_path: str | None = None
    status: SourceStatus = SourceStatus.UNKNOWN
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @property
    def connection_config(self) -> ConnectionConfig:
        """Extract connection configuration."""
        return ConnectionConfig(
            host=self.host,
            port=self.port,
            database_name=self.database_name,
            username=self.username,
            password=self.password or "",
            file_path=self.file_path,
        )

    def to_safe_dict(self) -> dict:
        """Convert to dictionary without exposing sensitive credentials."""
        data = self.model_dump(exclude={"password"})
        data["password_masked"] = "••••••••" if self.password else ""
        return data

