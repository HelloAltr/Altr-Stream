"""Source domain models."""

from datetime import datetime, timezone
from enum import Enum
import uuid
from pydantic import BaseModel, Field, SecretStr


class SourceType(str, Enum):
    """Supported source connector types."""

    POSTGRESQL = "POSTGRESQL"
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
    """Connection parameters for physical data sources."""

    host: str
    port: int
    database_name: str
    username: str
    password: str
    options: dict[str, str] = Field(default_factory=dict)

    def masked_dict(self) -> dict[str, str | int]:
        """Return parameters with password masked."""
        return {
            "host": self.host,
            "port": self.port,
            "database_name": self.database_name,
            "username": self.username,
            "password": "••••••••",
        }


class Source(BaseModel):
    """Domain model representing a registered data source."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    type: SourceType = SourceType.POSTGRESQL
    host: str
    port: int
    database_name: str
    username: str
    password: str
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
            password=self.password,
        )

    def to_safe_dict(self) -> dict:
        """Convert to dictionary without exposing sensitive credentials."""
        data = self.model_dump(exclude={"password"})
        data["password_masked"] = "••••••••" if self.password else ""
        return data
