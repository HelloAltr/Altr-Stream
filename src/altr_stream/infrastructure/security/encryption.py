"""Credential encryption at rest using Fernet symmetric cryptography."""

from __future__ import annotations

import os
from pathlib import Path
from cryptography.fernet import Fernet, InvalidToken

from altr_stream.config import settings

ENCRYPTION_PREFIX = "enc:v1:"


class SecurityConfigurationError(Exception):
    """Raised when encryption key configuration is missing or invalid."""


class CredentialEncryptionError(Exception):
    """Raised when credential encryption fails."""


class CredentialDecryptionError(Exception):
    """Raised when credential decryption fails due to wrong key or corrupted ciphertext."""


class CredentialEncryptionService:
    """Service providing transparent Fernet encryption at rest for physical database credentials."""

    def __init__(
        self,
        key: str | bytes | None = None,
        key_file_path: Path | None = None,
        auto_generate: bool = True,
    ) -> None:
        self._key = self._resolve_key(
            explicit_key=key,
            key_file_path=key_file_path,
            auto_generate=auto_generate,
        )
        try:
            self._fernet = Fernet(self._key)
        except Exception as exc:
            raise SecurityConfigurationError(f"Invalid encryption key provided: {exc}") from exc

    def _resolve_key(
        self,
        explicit_key: str | bytes | None,
        key_file_path: Path | None,
        auto_generate: bool,
    ) -> bytes:
        """Resolve encryption key from explicit parameter, environment, file, or secure generation."""
        # 1. Explicit key
        if explicit_key:
            if isinstance(explicit_key, str):
                return explicit_key.strip().encode("utf-8")
            return explicit_key

        # 2. Environment variable via settings
        if settings.encryption_key and settings.encryption_key.strip():
            return settings.encryption_key.strip().encode("utf-8")

        # 3. Persistent key file in data directory
        resolved_file = key_file_path or (settings.data_dir / ".encryption_key")
        if resolved_file.is_file():
            try:
                content = resolved_file.read_text(encoding="utf-8").strip()
                if content:
                    return content.encode("utf-8")
            except Exception as exc:
                raise SecurityConfigurationError(
                    f"Failed to read encryption key file at {resolved_file}: {exc}"
                ) from exc

        # 4. Auto-generate and persist if allowed
        if auto_generate:
            try:
                resolved_file.parent.mkdir(parents=True, exist_ok=True)
                new_key = Fernet.generate_key()
                # Write with restrictive permissions (0600)
                fd = os.open(
                    str(resolved_file),
                    os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
                    0o600,
                )
                with os.fdopen(fd, "wb") as f:
                    f.write(new_key)
                return new_key
            except Exception as exc:
                raise SecurityConfigurationError(
                    f"Failed to persist auto-generated encryption key to {resolved_file}: {exc}"
                ) from exc

        raise SecurityConfigurationError(
            "No encryption key provided in ALTR_STREAM_ENCRYPTION_KEY or keyfile."
        )

    def is_encrypted(self, value: str | None) -> bool:
        """Determine if a credential string is encrypted with Fernet."""
        if not value or not isinstance(value, str):
            return False
        if value.startswith(ENCRYPTION_PREFIX):
            return True
        # Check raw Fernet token (starts with gAAAAA and valid base64 length)
        if value.startswith("gAAAAA") and len(value) >= 100:
            return True
        return False

    def encrypt(self, plaintext: str | None) -> str | None:
        """Encrypt plaintext password; idempotent if already encrypted."""
        if plaintext is None:
            return None
        if plaintext == "":
            return ""
        if self.is_encrypted(plaintext):
            return plaintext

        try:
            token = self._fernet.encrypt(plaintext.encode("utf-8")).decode("utf-8")
            return f"{ENCRYPTION_PREFIX}{token}"
        except Exception as exc:
            raise CredentialEncryptionError(f"Failed to encrypt credential: {exc}") from exc

    def decrypt(self, ciphertext: str | None) -> str | None:
        """Decrypt ciphertext; transparently returns unencrypted legacy strings during migration."""
        if ciphertext is None:
            return None
        if ciphertext == "":
            return ""

        # If string is not encrypted, it is unmigrated plaintext
        if not self.is_encrypted(ciphertext):
            return ciphertext

        token = ciphertext
        if token.startswith(ENCRYPTION_PREFIX):
            token = token[len(ENCRYPTION_PREFIX) :]

        try:
            decrypted = self._fernet.decrypt(token.encode("utf-8")).decode("utf-8")
            return decrypted
        except InvalidToken as exc:
            raise CredentialDecryptionError(
                "Failed to decrypt credential: wrong encryption key or corrupted ciphertext."
            ) from exc
        except Exception as exc:
            raise CredentialDecryptionError(f"Unexpected decryption failure: {exc}") from exc


# Default global instance using configuration / data directory keyfile
_encryption_service: CredentialEncryptionService | None = None


def get_encryption_service() -> CredentialEncryptionService:
    """Retrieve or initialize the global CredentialEncryptionService singleton."""
    global _encryption_service
    if _encryption_service is None:
        _encryption_service = CredentialEncryptionService()
    return _encryption_service
