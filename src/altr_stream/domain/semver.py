"""Semantic Versioning (SemVer 2.0.0) specification and Direct Upgrade Resolver."""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum
from functools import total_ordering
from typing import Sequence

# SemVer 2.0.0 compliant regex with optional leading 'v'
# Spec: https://semver.org/spec/v2.0.0.html
_SEMVER_REGEX = re.compile(
    r"^v?(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
)


class ReleaseChannel(str, Enum):
    """Release distribution channels."""

    ALPHA = "alpha"
    BETA = "beta"
    STABLE = "stable"

    @classmethod
    def from_string(cls, value: str) -> ReleaseChannel:
        val = value.strip().lower()
        if val in ("alpha", "a"):
            return cls.ALPHA
        if val in ("beta", "b", "rc"):
            return cls.BETA
        if val in ("stable", "release", "ga"):
            return cls.STABLE
        raise ValueError(f"Unknown release channel: {value}")


@total_ordering
class SemVer:
    """Robust SemVer 2.0.0 data structure and deterministic comparator."""

    __slots__ = ("major", "minor", "patch", "prerelease", "build", "raw")

    def __init__(
        self,
        major: int,
        minor: int,
        patch: int,
        prerelease: str | None = None,
        build: str | None = None,
        raw: str | None = None,
    ) -> None:
        self.major = int(major)
        self.minor = int(minor)
        self.patch = int(patch)
        self.prerelease = prerelease or None
        self.build = build or None
        self.raw = raw or self._format_str()

    def _format_str(self) -> str:
        res = f"{self.major}.{self.minor}.{self.patch}"
        if self.prerelease:
            res += f"-{self.prerelease}"
        if self.build:
            res += f"+{self.build}"
        return res

    @property
    def is_prerelease(self) -> bool:
        return self.prerelease is not None

    @property
    def channel(self) -> ReleaseChannel:
        """Derive the release channel of this version."""
        if not self.prerelease:
            return ReleaseChannel.STABLE
        pre = self.prerelease.lower()
        if "alpha" in pre:
            return ReleaseChannel.ALPHA
        if "beta" in pre or "rc" in pre:
            return ReleaseChannel.BETA
        return ReleaseChannel.ALPHA

    @classmethod
    def parse(cls, version_str: str) -> SemVer:
        """Parse a SemVer 2.0.0 version string. Raises ValueError if malformed."""
        if not version_str or not isinstance(version_str, str):
            raise ValueError(f"Invalid version string: {version_str!r}")

        clean = version_str.strip()
        match = _SEMVER_REGEX.match(clean)
        if not match:
            raise ValueError(f"Version string does not conform to SemVer 2.0.0: {version_str!r}")

        groups = match.groupdict()
        return cls(
            major=int(groups["major"]),
            minor=int(groups["minor"]),
            patch=int(groups["patch"]),
            prerelease=groups["prerelease"],
            build=groups["buildmetadata"],
            raw=clean,
        )

    @classmethod
    def try_parse(cls, version_str: str) -> SemVer | None:
        """Safely attempt to parse version; returns None if malformed."""
        try:
            return cls.parse(version_str)
        except ValueError:
            return None

    def __str__(self) -> str:
        return self._format_str()

    def __repr__(self) -> str:
        return f"SemVer({self._format_str()!r})"

    def __hash__(self) -> int:
        # Build metadata is ignored in hash per SemVer 2.0.0
        return hash((self.major, self.minor, self.patch, self.prerelease))

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, SemVer):
            return NotImplemented
        return (
            self.major == other.major
            and self.minor == other.minor
            and self.patch == other.patch
            and self.prerelease == other.prerelease
        )

    def __lt__(self, other: object) -> bool:
        if not isinstance(other, SemVer):
            return NotImplemented

        # 1. Compare major, minor, patch numerically
        if (self.major, self.minor, self.patch) != (other.major, other.minor, other.patch):
            return (self.major, self.minor, self.patch) < (other.major, other.minor, other.patch)

        # 2. When major.minor.patch are equal:
        # A normal version has greater precedence than a pre-release version.
        if self.prerelease is None and other.prerelease is not None:
            return False
        if self.prerelease is not None and other.prerelease is None:
            return True
        if self.prerelease is None and other.prerelease is None:
            return False

        # 3. Both have pre-release. Compare dot-separated identifiers.
        assert self.prerelease is not None and other.prerelease is not None
        self_parts = self.prerelease.split(".")
        other_parts = other.prerelease.split(".")

        for sp, op in zip(self_parts, other_parts):
            if sp == op:
                continue
            sp_is_num = sp.isdigit()
            op_is_num = op.isdigit()

            if sp_is_num and op_is_num:
                return int(sp) < int(op)
            if sp_is_num and not op_is_num:
                # Numeric identifiers always have lower precedence than non-numeric
                return True
            if not sp_is_num and op_is_num:
                return False
            # Both non-numeric: ASCII lexical comparison
            return sp < op

        # Larger set of pre-release fields has higher precedence
        return len(self_parts) < len(other_parts)


@dataclass(frozen=True)
class ReleaseInfo:
    """GitHub Release metadata representation."""

    version: SemVer
    tag_name: str
    name: str
    published_at: str | None
    body: str | None
    prerelease: bool
    html_url: str | None
    tarball_url: str | None = None
    channel: ReleaseChannel | None = None

    def __post_init__(self) -> None:
        if self.channel is None:
            object.__setattr__(self, "channel", self.version.channel)


@dataclass(frozen=True)
class UpgradePlan:
    """Result of an upgrade resolution query."""

    current_version: SemVer
    target_version: SemVer | None
    update_available: bool
    channel: ReleaseChannel
    target_release: ReleaseInfo | None
    all_releases: list[ReleaseInfo]
    check_available: bool = True
    error_code: str | None = None
    message: str | None = None
    retry_after: int | None = None


class DirectUpgradeResolver:
    """Resolves direct upgrade targets based on SemVer 2.0.0 and channel policy."""

    @staticmethod
    def is_channel_allowed(release_channel: ReleaseChannel, user_channel: ReleaseChannel) -> bool:
        """Channel hierarchy:

        - ALPHA accepts: ALPHA, BETA, STABLE
        - BETA accepts: BETA, STABLE
        - STABLE accepts: STABLE
        """
        if user_channel == ReleaseChannel.ALPHA:
            return True
        if user_channel == ReleaseChannel.BETA:
            return release_channel in (ReleaseChannel.BETA, ReleaseChannel.STABLE)
        if user_channel == ReleaseChannel.STABLE:
            return release_channel == ReleaseChannel.STABLE
        return False

    @classmethod
    def resolve_direct_upgrade(
        cls,
        current_version: SemVer,
        available_releases: Sequence[ReleaseInfo],
        channel: ReleaseChannel | None = None,
    ) -> UpgradePlan:
        """Select the highest compatible release directly without requiring intermediate hops."""
        target_channel = channel or current_version.channel

        # Filter releases by channel compatibility
        compatible: list[ReleaseInfo] = [
            rel for rel in available_releases
            if cls.is_channel_allowed(rel.version.channel, target_channel)
        ]

        # Sort by SemVer ascending
        compatible.sort(key=lambda r: r.version)

        # Eliminate duplicates if multiple releases have the exact same SemVer
        unique_releases: list[ReleaseInfo] = []
        seen_versions: set[SemVer] = set()
        for rel in compatible:
            if rel.version not in seen_versions:
                seen_versions.add(rel.version)
                unique_releases.append(rel)

        # Filter strictly strictly newer than current version (direct upgrade)
        newer_releases = [rel for rel in unique_releases if rel.version > current_version]

        if not newer_releases:
            return UpgradePlan(
                current_version=current_version,
                target_version=None,
                update_available=False,
                channel=target_channel,
                target_release=None,
                all_releases=unique_releases,
            )

        # Direct upgrade selects the highest newer version available
        highest = newer_releases[-1]
        return UpgradePlan(
            current_version=current_version,
            target_version=highest.version,
            update_available=True,
            channel=target_channel,
            target_release=highest,
            all_releases=unique_releases,
        )
