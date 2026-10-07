"""Database connection URL and host resolution utility.

Handles transparent resolution of host machine loopback addresses (localhost, 127.0.0.1, ::1)
to Docker host addresses (host.docker.internal) when running within containerized environments.
"""

from __future__ import annotations

import urllib.parse
from typing import Optional

DOCKER_HOST_INTERNAL = "host.docker.internal"
LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1", "[::1]"})


def resolve_docker_host(host: Optional[str]) -> Optional[str]:
    """Resolve loopback hostnames to host.docker.internal.

    Leaves remote hostnames, explicit host.docker.internal, and non-loopback IP addresses unchanged.

    Examples:
        resolve_docker_host("localhost") -> "host.docker.internal"
        resolve_docker_host("127.0.0.1") -> "host.docker.internal"
        resolve_docker_host("host.docker.internal") -> "host.docker.internal"
        resolve_docker_host("database.example.com") -> "database.example.com"
        resolve_docker_host("192.168.1.50") -> "192.168.1.50"
    """
    if not host:
        return host

    h = host.strip()
    normalized = h.lower()
    # Normalize IPv6 brackets if present (e.g. [::1] or [::1]:27017)
    if normalized.startswith("["):
        close_idx = normalized.find("]")
        if close_idx != -1:
            inner = normalized[1:close_idx]
            suffix = h[close_idx + 1:]
            if inner in LOOPBACK_HOSTS or inner == "::1":
                return f"{DOCKER_HOST_INTERNAL}{suffix}"

    if normalized in LOOPBACK_HOSTS:
        return DOCKER_HOST_INTERNAL

    # Handle host:port if user provided port inside host field (e.g. localhost:27017)
    if ":" in h and not h.startswith("["):
        parts = h.split(":", 1)
        if parts[0].lower() in LOOPBACK_HOSTS:
            return f"{DOCKER_HOST_INTERNAL}:{parts[1]}"

    return h


def resolve_connection_url(url: str) -> str:
    """Parse a database connection URL and modify only the hostname component if loopback.

    Properly preserves:
    - Scheme (mysql, postgresql, mongodb, etc.)
    - Credentials (username, password including special characters or URL encoding)
    - Port number
    - Database path
    - Query parameters (?charset=utf8mb4, ?sslmode=disable, etc.)
    - Fragments

    Examples:
        resolve_connection_url("mysql://root:secret@localhost:3306/db")
            -> "mysql://root:secret@host.docker.internal:3306/db"
        resolve_connection_url("postgresql://user:pass@127.0.0.1:5432/mydb?sslmode=disable")
            -> "postgresql://user:pass@host.docker.internal:5432/mydb?sslmode=disable"
        resolve_connection_url("mysql://user:pass@host.docker.internal:3306/db")
            -> "mysql://user:pass@host.docker.internal:3306/db"
        resolve_connection_url("mysql://user:pass@192.168.1.10:3306/db")
            -> "mysql://user:pass@192.168.1.10:3306/db"
    """
    if not url:
        return url

    # Handle bare host or host:port without URL scheme
    if "://" not in url:
        if ":" in url:
            host_part, port_part = url.split(":", 1)
            return f"{resolve_docker_host(host_part)}:{port_part}"
        return resolve_docker_host(url) or ""

    parsed = urllib.parse.urlsplit(url)
    netloc = parsed.netloc

    userinfo = ""
    hostport = netloc

    # Split credentials from host[:port]
    if "@" in netloc:
        userinfo, hostport = netloc.rsplit("@", 1)
        userinfo += "@"

    # Parse host and port
    if hostport.startswith("["):
        # IPv6 address: [address]:port or [address]
        idx = hostport.find("]")
        if idx != -1:
            ipv6_host = hostport[1:idx]
            port_suffix = hostport[idx + 1 :]
            resolved = resolve_docker_host(ipv6_host)
            if resolved != ipv6_host:
                new_hostport = f"{resolved}{port_suffix}"
            else:
                new_hostport = f"[{ipv6_host}]{port_suffix}"
        else:
            new_hostport = hostport
    elif ":" in hostport:
        host, port = hostport.split(":", 1)
        new_hostport = f"{resolve_docker_host(host)}:{port}"
    else:
        new_hostport = resolve_docker_host(hostport) or ""

    new_netloc = f"{userinfo}{new_hostport}"
    return urllib.parse.urlunsplit(
        (parsed.scheme, new_netloc, parsed.path, parsed.query, parsed.fragment)
    )
