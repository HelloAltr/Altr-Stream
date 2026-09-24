"""Unit tests for CredentialEncryptionService, database migration, and credential redaction."""

from pathlib import Path
import pytest
from cryptography.fernet import Fernet
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker

from altr_stream.domain.source import Source, SourceType, SourceStatus
from altr_stream.infrastructure.database.models import Base, SourceModel
from altr_stream.infrastructure.database.migrations import run_migrations
from altr_stream.infrastructure.database.repository import SqliteSourceRepository
from altr_stream.infrastructure.security.encryption import (
    CredentialDecryptionError,
    CredentialEncryptionService,
    ENCRYPTION_PREFIX,
    SecurityConfigurationError,
)
from altr_stream.presentation.api.dtos import SourceResponseDTO


class TestCredentialEncryptionService:
    def test_encrypt_and_decrypt(self):
        key = Fernet.generate_key().decode()
        service = CredentialEncryptionService(key=key)

        secret = "SuperSecretPassword123!@#"
        ciphertext = service.encrypt(secret)
        assert ciphertext is not None
        assert ciphertext.startswith(ENCRYPTION_PREFIX)
        assert secret not in ciphertext

        decrypted = service.decrypt(ciphertext)
        assert decrypted == secret

    def test_idempotent_encryption_does_not_double_encrypt(self):
        key = Fernet.generate_key().decode()
        service = CredentialEncryptionService(key=key)

        secret = "MyDatabasePassword"
        encrypted_once = service.encrypt(secret)
        encrypted_twice = service.encrypt(encrypted_once)

        assert encrypted_once == encrypted_twice
        assert service.decrypt(encrypted_twice) == secret

    def test_handles_none_and_empty(self):
        key = Fernet.generate_key().decode()
        service = CredentialEncryptionService(key=key)

        assert service.encrypt(None) is None
        assert service.encrypt("") == ""
        assert service.decrypt(None) is None
        assert service.decrypt("") == ""

    def test_wrong_key_raises_decryption_error(self):
        key1 = Fernet.generate_key().decode()
        key2 = Fernet.generate_key().decode()

        service1 = CredentialEncryptionService(key=key1)
        service2 = CredentialEncryptionService(key=key2)

        ciphertext = service1.encrypt("sensitive_pass")

        with pytest.raises(CredentialDecryptionError) as exc_info:
            service2.decrypt(ciphertext)
        assert "wrong encryption key or corrupted ciphertext" in str(exc_info.value)

    def test_malformed_ciphertext_raises_decryption_error(self):
        key = Fernet.generate_key().decode()
        service = CredentialEncryptionService(key=key)

        with pytest.raises(CredentialDecryptionError):
            service.decrypt(f"{ENCRYPTION_PREFIX}not_a_valid_fernet_token")

    def test_missing_or_invalid_key_raises_configuration_error(self, tmp_path: Path):
        with pytest.raises(SecurityConfigurationError):
            CredentialEncryptionService(key="invalid_short_key", auto_generate=False)

        empty_file = tmp_path / "empty.key"
        empty_file.write_text("")
        with pytest.raises(SecurityConfigurationError):
            CredentialEncryptionService(key_file_path=empty_file, auto_generate=False)

    def test_auto_generate_and_persist_key(self, tmp_path: Path):
        key_file = tmp_path / "subdir" / ".encryption_key"
        assert not key_file.exists()

        service = CredentialEncryptionService(key_file_path=key_file, auto_generate=True)
        assert key_file.is_file()

        # Re-instantiating with the same file loads the same key
        service2 = CredentialEncryptionService(key_file_path=key_file, auto_generate=False)
        test_val = "PersistedKeyTest"
        cipher = service.encrypt(test_val)
        assert service2.decrypt(cipher) == test_val


class TestRepositoryAndMigrationEncryption:
    @pytest.fixture
    async def engine(self):
        eng = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
        async with eng.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        yield eng
        await eng.dispose()

    @pytest.fixture
    def encryption_service(self):
        key = Fernet.generate_key().decode()
        return CredentialEncryptionService(key=key)

    @pytest.mark.asyncio
    async def test_repository_stores_encrypted_and_retrieves_decrypted(self, engine, encryption_service):
        session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
        async with session_factory() as session:
            repo = SqliteSourceRepository(session, encryption=encryption_service)

            source = Source(
                name="Encrypted PG",
                type=SourceType.POSTGRESQL,
                host="localhost",
                port=5432,
                database_name="app_db",
                username="postgres",
                password="PlaintextPasswordToEncrypt",
            )
            created = await repo.create(source)
            await session.commit()

            # Domain entity returned from repo has decrypted password
            assert created.password == "PlaintextPasswordToEncrypt"

            # Direct inspection of raw database row shows ciphertext at rest
            raw_row = (await session.execute(text("SELECT password FROM sources WHERE id = :id"), {"id": created.id})).scalar_one()
            assert raw_row.startswith(ENCRYPTION_PREFIX)
            assert "PlaintextPasswordToEncrypt" not in raw_row

            # Fetch through repo decrypts back to original plaintext
            fetched = await repo.get_by_id(created.id)
            assert fetched is not None
            assert fetched.password == "PlaintextPasswordToEncrypt"

    @pytest.mark.asyncio
    async def test_idempotent_database_migration(self, engine, encryption_service):
        # Insert raw legacy unencrypted rows into SQLite table
        session_factory = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
        async with session_factory() as session:
            await session.execute(
                text(
                    """
                    INSERT INTO sources (id, name, type, host, port, database_name, username, password, status, created_at, updated_at)
                    VALUES
                    ('src-1', 'Legacy Plaintext 1', 'POSTGRESQL', 'localhost', 5432, 'db1', 'u1', 'legacy_secret_1', 'ACTIVE', datetime('now'), datetime('now')),
                    ('src-2', 'Legacy Plaintext 2', 'MYSQL', 'localhost', 3306, 'db2', 'u2', 'legacy_secret_2', 'ACTIVE', datetime('now'), datetime('now'));
                    """
                )
            )
            await session.commit()

        # Run migration with encryption service
        async with engine.begin() as conn:
            await conn.run_sync(run_migrations)

        # Inspect SQLite rows: must now be encrypted
        async with session_factory() as session:
            rows = (await session.execute(text("SELECT id, password FROM sources ORDER BY id"))).fetchall()
            assert len(rows) == 2
            assert rows[0][1].startswith(ENCRYPTION_PREFIX)
            assert rows[1][1].startswith(ENCRYPTION_PREFIX)
            first_pass_enc = rows[0][1]

        # Re-running migration (idempotent across restarts) must not alter or double-encrypt
        async with engine.begin() as conn:
            await conn.run_sync(run_migrations)

        async with session_factory() as session:
            row1 = (await session.execute(text("SELECT password FROM sources WHERE id = 'src-1'"))).scalar_one()
            assert row1 == first_pass_enc

    def test_api_dto_never_exposes_plaintext_or_ciphertext(self):
        source = Source(
            name="Secure Source",
            type=SourceType.POSTGRESQL,
            host="db.example.com",
            port=5432,
            username="admin",
            password="MySecretPassword123",
        )
        dto = SourceResponseDTO.from_domain(source)
        dto_dict = dto.model_dump()

        # Never exposes 'password' field
        assert "password" not in dto_dict
        # Exposes standard redacted mask
        assert dto_dict["password_masked"] == "••••••••"
        assert "MySecretPassword123" not in str(dto_dict)
