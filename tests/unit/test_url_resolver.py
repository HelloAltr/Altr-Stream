"""Unit tests for Docker host transparent resolution and database URL parsing."""

import pytest
from httpx import AsyncClient
from altr_stream.domain.source import ConnectionConfig, SourceType
from altr_stream.infrastructure.connectors.factory import ConnectorFactory
from altr_stream.infrastructure.connectors.mongodb.connector import MongoDBConnector
from altr_stream.infrastructure.connectors.mysql.connector import MySQLConnector
from altr_stream.infrastructure.connectors.postgres.connector import PostgreSQLConnector
from altr_stream.infrastructure.database.url_resolver import (
    DOCKER_HOST_INTERNAL,
    resolve_connection_url,
    resolve_docker_host,
)


# ---------------------------------------------------------------------------
# 1. Hostname Resolution Tests
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "input_host, expected_host",
    [
        ("localhost", DOCKER_HOST_INTERNAL),
        ("127.0.0.1", DOCKER_HOST_INTERNAL),
        ("::1", DOCKER_HOST_INTERNAL),
        ("[::1]", DOCKER_HOST_INTERNAL),
        ("LOCALHOST", DOCKER_HOST_INTERNAL),
        ("host.docker.internal", DOCKER_HOST_INTERNAL),
        ("192.168.1.100", "192.168.1.100"),
        ("10.0.0.5", "10.0.0.5"),
        ("172.18.0.2", "172.18.0.2"),
        ("database.example.com", "database.example.com"),
        ("remote-db.example.com", "remote-db.example.com"),
        ("mysql-container", "mysql-container"),
        ("postgres-test", "postgres-test"),
        (None, None),
        ("", ""),
    ],
)
def test_resolve_docker_host(input_host, expected_host):
    """Verify resolve_docker_host maps loopback addresses to host.docker.internal while keeping others intact."""
    assert resolve_docker_host(input_host) == expected_host


# ---------------------------------------------------------------------------
# 2. Connection URL Resolution Tests
# ---------------------------------------------------------------------------


def test_resolve_connection_url_mysql_localhost():
    """Verify standard MySQL URL targeting localhost resolves to host.docker.internal."""
    url = "mysql://root:secret_pass@localhost:3306/my_database"
    expected = "mysql://root:secret_pass@host.docker.internal:3306/my_database"
    assert resolve_connection_url(url) == expected


def test_resolve_connection_url_mysql_127_0_0_1():
    """Verify MySQL URL targeting 127.0.0.1 resolves to host.docker.internal."""
    url = "mysql://root:secret_pass@127.0.0.1:3306/my_database"
    expected = "mysql://root:secret_pass@host.docker.internal:3306/my_database"
    assert resolve_connection_url(url) == expected


def test_resolve_connection_url_postgres_with_credentials_and_queries():
    """Verify PostgreSQL URL preserves complex credentials and query parameters."""
    url = "postgresql://my_user:p%40ss%23word@localhost:5432/analytics_prod?sslmode=disable&application_name=altr"
    expected = "postgresql://my_user:p%40ss%23word@host.docker.internal:5432/analytics_prod?sslmode=disable&application_name=altr"
    assert resolve_connection_url(url) == expected


def test_resolve_connection_url_mongodb_with_auth_source():
    """Verify MongoDB connection URL with authSource query parameter."""
    url = "mongodb://admin:super_secret@127.0.0.1:27017/shop?authSource=admin&replicaSet=rs0"
    expected = "mongodb://admin:super_secret@host.docker.internal:27017/shop?authSource=admin&replicaSet=rs0"
    assert resolve_connection_url(url) == expected


def test_resolve_connection_url_explicit_host_docker_internal():
    """Verify explicit host.docker.internal is preserved without alteration."""
    url = "mysql://root:password@host.docker.internal:3306/mydb"
    assert resolve_connection_url(url) == url


def test_resolve_connection_url_remote_hostname():
    """Verify remote hostnames like database.example.com remain unchanged."""
    url = "postgresql://user:pass@database.example.com:5432/production"
    assert resolve_connection_url(url) == url


def test_resolve_connection_url_remote_ipv4_address():
    """Verify remote private/public IPv4 addresses remain unchanged."""
    url1 = "mysql://app:secret@192.168.1.50:3306/crm"
    assert resolve_connection_url(url1) == url1

    url2 = "postgres://app:secret@10.0.1.20:5432/inventory"
    assert resolve_connection_url(url2) == url2


def test_resolve_connection_url_bare_host_and_port():
    """Verify bare host:port strings without URL scheme."""
    assert resolve_connection_url("localhost:3306") == "host.docker.internal:3306"
    assert resolve_connection_url("127.0.0.1:5432") == "host.docker.internal:5432"
    assert resolve_connection_url("host.docker.internal:3306") == "host.docker.internal:3306"
    assert resolve_connection_url("192.168.1.200:3306") == "192.168.1.200:3306"
    assert resolve_connection_url("remote-db.example.com:27017") == "remote-db.example.com:27017"


def test_resolve_connection_url_ipv6_loopback():
    """Verify IPv6 loopback [::1] is translated to host.docker.internal."""
    url = "mysql://user:pass@[::1]:3306/testdb"
    expected = "mysql://user:pass@host.docker.internal:3306/testdb"
    assert resolve_connection_url(url) == expected


def test_resolve_connection_url_ipv6_remote():
    """Verify remote IPv6 addresses are preserved intact."""
    url = "mysql://user:pass@[2001:db8::1]:3306/testdb"
    assert resolve_connection_url(url) == url


# ---------------------------------------------------------------------------
# 3. ConnectionConfig Integration Tests
# ---------------------------------------------------------------------------


def test_connection_config_resolved_host_property():
    """Verify ConnectionConfig.resolved_host property dynamically resolves loopback hosts."""
    cfg_local = ConnectionConfig(host="localhost", port=3306)
    assert cfg_local.host == "localhost"
    assert cfg_local.resolved_host == "host.docker.internal"

    cfg_ip = ConnectionConfig(host="127.0.0.1", port=5432)
    assert cfg_ip.host == "127.0.0.1"
    assert cfg_ip.resolved_host == "host.docker.internal"

    cfg_remote = ConnectionConfig(host="db.example.com", port=3306)
    assert cfg_remote.host == "db.example.com"
    assert cfg_remote.resolved_host == "db.example.com"


def test_connection_config_from_connection_url():
    """Verify ConnectionConfig.from_connection_url parses URL, preserving original host while enabling runtime resolution."""
    url = "mysql://shop_user:my_pass@localhost:3306/shop_db?charset=utf8mb4"
    cfg = ConnectionConfig.from_connection_url(url)

    # User-facing host must remain "localhost"
    assert cfg.host == "localhost"
    assert cfg.resolved_host == "host.docker.internal"
    assert cfg.port == 3306
    assert cfg.username == "shop_user"
    assert cfg.password == "my_pass"
    assert cfg.database_name == "shop_db"
    assert cfg.options.get("charset") == "utf8mb4"


# ---------------------------------------------------------------------------
# 4. Connector Integration Tests (Specific Requirements 1-7)
# ---------------------------------------------------------------------------


def test_mongodb_connection_localhost():
    """Requirement 1: localhost MongoDB connection passes host.docker.internal to client while preserving host."""
    cfg = ConnectionConfig(host="localhost", port=27017, database_name="shop")
    connector = ConnectorFactory.get_connector(SourceType.MONGODB, cfg)
    assert isinstance(connector, MongoDBConnector)
    # UI/config must keep localhost
    assert connector.config.host == "localhost"
    assert connector.config.resolved_host == "host.docker.internal"

    # Runtime client URI must resolve to host.docker.internal
    resolved_uri = connector._build_connection_uri(resolved=True)
    assert "mongodb://host.docker.internal:27017/shop" in resolved_uri
    assert "localhost" not in resolved_uri

    # Raw URI (for display) keeps localhost
    display_uri = connector._build_connection_uri(resolved=False)
    assert "mongodb://localhost:27017/shop" in display_uri


def test_mongodb_connection_127_0_0_1():
    """Requirement 2: 127.0.0.1 MongoDB connection resolves to host.docker.internal."""
    cfg = ConnectionConfig(host="127.0.0.1", port=27017, database_name="analytics")
    connector = ConnectorFactory.get_connector(SourceType.MONGODB, cfg)
    assert connector.config.host == "127.0.0.1"
    assert connector.config.resolved_host == "host.docker.internal"
    resolved_uri = connector._build_connection_uri(resolved=True)
    assert "mongodb://host.docker.internal:27017/analytics" in resolved_uri


def test_mysql_connection_localhost():
    """Requirement 3: localhost MySQL connection uses resolved_host for driver while preserving config."""
    cfg = ConnectionConfig(host="localhost", port=3306, database_name="ecommerce")
    connector = ConnectorFactory.get_connector(SourceType.MYSQL, cfg)
    assert isinstance(connector, MySQLConnector)
    assert connector.config.host == "localhost"
    assert connector.config.resolved_host == "host.docker.internal"


def test_postgresql_connection_localhost():
    """Requirement 4: localhost PostgreSQL connection uses resolved_host for driver while preserving config."""
    cfg = ConnectionConfig(host="localhost", port=5432, database_name="warehouse")
    connector = ConnectorFactory.get_connector(SourceType.POSTGRESQL, cfg)
    assert isinstance(connector, PostgreSQLConnector)
    assert connector.config.host == "localhost"
    assert connector.config.resolved_host == "host.docker.internal"


def test_host_docker_internal_remains_unchanged():
    """Requirement 5: explicit host.docker.internal remains unchanged for all drivers."""
    for stype in (SourceType.MONGODB, SourceType.MYSQL, SourceType.POSTGRESQL):
        cfg = ConnectionConfig(host="host.docker.internal", port=5000, database_name="db")
        connector = ConnectorFactory.get_connector(stype, cfg)
        assert connector.config.host == "host.docker.internal"
        assert connector.config.resolved_host == "host.docker.internal"


def test_remote_hostname_and_ip_remain_unchanged():
    """Requirement 6: remote hostnames and LAN/public IPs remain unchanged."""
    test_hosts = ["db.internal.corp", "192.168.1.150", "10.200.0.5", "db.example.com"]
    for remote_h in test_hosts:
        cfg = ConnectionConfig(host=remote_h, port=3306, database_name="db")
        assert cfg.host == remote_h
        assert cfg.resolved_host == remote_h


def test_localhost_with_credentials_database_path_options():
    """Requirement 7: localhost with URL credentials, database name, and query parameters."""
    url = "mongodb://my_admin:p%40ss%3Aword@localhost:27017/my_app_db?authSource=admin&replicaSet=rs0"
    resolved = resolve_connection_url(url)
    assert resolved == "mongodb://my_admin:p%40ss%3Aword@host.docker.internal:27017/my_app_db?authSource=admin&replicaSet=rs0"

    cfg = ConnectionConfig.from_connection_url(url)
    assert cfg.host == "localhost"
    assert cfg.resolved_host == "host.docker.internal"
    assert cfg.username == "my_admin"
    assert cfg.password == "p@ss:word"
    assert cfg.database_name == "my_app_db"
    assert cfg.options.get("authSource") == "admin"


# ---------------------------------------------------------------------------
# 5. Requirement 8: Actual Test Connection API / Integration Path
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_sources_test_connection_api_preserves_localhost_and_resolves(client: AsyncClient):
    """Requirement 8: POST /api/v1/sources/test resolves localhost to host.docker.internal for driver."""
    from unittest.mock import patch
    from altr_stream.domain.connector import ConnectionTestResult

    mock_result = ConnectionTestResult(
        success=True,
        message="Connected successfully to MongoDB v7.0.43 (5.2 ms)",
        latency_ms=5.2,
        server_version="7.0.43",
    )

    captured_config = []

    async def mock_test_connection(self):
        captured_config.append(self.config)
        return mock_result

    with patch(
        "altr_stream.infrastructure.connectors.mongodb.connector.MongoDBConnector.test_connection",
        new=mock_test_connection,
    ):
        payload = {
            "type": "MONGODB",
            "host": "localhost",
            "port": 27017,
            "database_name": "test_db",
        }
        res = await client.post("/api/v1/sources/test", json=payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert "7.0.43" in data["server_version"]

        # Verify the connector received the config with resolved_host
        assert len(captured_config) == 1
        connector_cfg = captured_config[0]
        # User input preserved
        assert connector_cfg.host == "localhost"
        # Resolved host provided to driver
        assert connector_cfg.resolved_host == "host.docker.internal"
