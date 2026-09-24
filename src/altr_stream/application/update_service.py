"""UpdateService managing GitHub Releases, SemVer checks, and IPC with Host Supervisor."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
from typing import Any
import httpx

from altr_stream.config import settings
from altr_stream.domain.semver import (
    DirectUpgradeResolver,
    ReleaseChannel,
    ReleaseInfo,
    SemVer,
    UpgradePlan,
)
from altr_stream.domain.updates import (
    UpdateRequest,
    UpdateStatus,
    UpdateStatusState,
)

logger = logging.getLogger(__name__)

DEFAULT_GITHUB_REPO = "helloaltr/altr-stream"
DEFAULT_CACHE_TTL_SECONDS = 300.0  # 5 minutes


class UpdateService:
    """Application service for update resolution, release fetching, and IPC coordination."""

    def __init__(
        self,
        github_repo: str = DEFAULT_GITHUB_REPO,
        updates_dir: Path | None = None,
        cache_ttl_sec: float = DEFAULT_CACHE_TTL_SECONDS,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        self.github_repo = github_repo
        self.updates_dir = updates_dir or settings.updates_dir
        self.cache_ttl_sec = cache_ttl_sec
        self._http_client = http_client

        self._cached_releases: list[ReleaseInfo] | None = None
        self._cache_timestamp: float = 0.0

        # Ensure updates directory exists
        self.updates_dir.mkdir(parents=True, exist_ok=True)

    @property
    def current_semver(self) -> SemVer:
        return SemVer.parse(settings.app_version)

    @property
    def request_file(self) -> Path:
        return self.updates_dir / "update-request.json"

    @property
    def status_file(self) -> Path:
        return self.updates_dir / "update-status.json"

    def _write_atomic_json(self, target_path: Path, data: dict[str, Any]) -> None:
        """Write a dictionary to disk atomically using a temporary file and atomic rename."""
        target_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = target_path.parent / f"{target_path.name}.tmp.{os.getpid()}"
        try:
            content = json.dumps(data, indent=2)
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write(content)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, target_path)
        finally:
            if tmp_path.exists():
                try:
                    tmp_path.unlink()
                except OSError:
                    pass

    async def fetch_releases(self, force_refresh: bool = False) -> list[ReleaseInfo]:
        """Fetch releases from GitHub API with caching and error handling."""
        now = datetime.now(timezone.utc).timestamp()
        if (
            not force_refresh
            and self._cached_releases is not None
            and (now - self._cache_timestamp) < self.cache_ttl_sec
        ):
            return self._cached_releases

        url = f"https://api.github.com/repos/{self.github_repo}/releases"
        headers = {
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": f"Altr-Stream-Node/{settings.app_version}",
        }

        try:
            if self._http_client:
                response = await self._http_client.get(url, headers=headers, timeout=5.0)
            else:
                async with httpx.AsyncClient(timeout=5.0) as client:
                    response = await client.get(url, headers=headers)

            if response.status_code == 200:
                raw_data = response.json()
                releases: list[ReleaseInfo] = []
                for item in raw_data:
                    tag = item.get("tag_name", "")
                    parsed_ver = SemVer.try_parse(tag)
                    if parsed_ver is not None:
                        rel = ReleaseInfo(
                            version=parsed_ver,
                            tag_name=tag,
                            name=item.get("name") or tag,
                            published_at=item.get("published_at"),
                            body=item.get("body"),
                            prerelease=item.get("prerelease", False),
                            html_url=item.get("html_url"),
                            tarball_url=item.get("tarball_url"),
                        )
                        releases.append(rel)

                self._cached_releases = releases
                self._cache_timestamp = now
                return releases

            if response.status_code in (403, 429):
                logger.warning("GitHub Releases API rate limited (HTTP %d).", response.status_code)
            else:
                logger.warning(
                    "GitHub Releases API returned unexpected status %d.", response.status_code
                )

        except Exception as exc:
            logger.warning("Failed to fetch GitHub releases: %s", exc)

        # Return cached releases if available on error, otherwise empty list
        return self._cached_releases or []

    async def check_for_updates(
        self,
        channel: ReleaseChannel | None = None,
        force_refresh: bool = False,
    ) -> UpgradePlan:
        """Resolve direct upgrade plan against official GitHub releases."""
        releases = await self.fetch_releases(force_refresh=force_refresh)
        return DirectUpgradeResolver.resolve_direct_upgrade(
            current_version=self.current_semver,
            available_releases=releases,
            channel=channel,
        )

    async def request_update(
        self,
        target_version_str: str,
        channel: ReleaseChannel | None = None,
    ) -> UpdateStatus:
        """Create an update intent request for the host supervisor."""
        target_semver = SemVer.parse(target_version_str)
        if target_semver <= self.current_semver:
            raise ValueError(
                f"Target version {target_semver} must be strictly greater than current version {self.current_semver}."
            )

        current_status = await self.get_status()
        if current_status.state.is_active:
            raise ValueError(
                f"Cannot request update: an update workflow is already active in state '{current_status.state.value}'."
            )

        # Build clean target image name pointing to official GHCR registry
        clean_tag = str(target_semver)
        target_image = f"ghcr.io/helloaltr/altr-stream:{clean_tag}"
        effective_channel = channel or target_semver.channel

        # 1. Create and write update request intent
        req = UpdateRequest.create(
            current_version=str(self.current_semver),
            target_version=str(target_semver),
            target_image=target_image,
            channel=effective_channel.value,
        )
        self._write_atomic_json(self.request_file, req.to_dict())

        # 2. Update status to REQUESTED
        status = UpdateStatus(
            request_id=req.request_id,
            state=UpdateStatusState.REQUESTED,
            current_version=str(self.current_semver),
            target_version=str(target_semver),
            progress_percent=10,
            message="Update request dispatched to host supervisor.",
        )
        self._write_atomic_json(self.status_file, status.to_dict())

        logger.info(
            "Dispatched update request %s: %s -> %s (%s)",
            req.request_id,
            req.current_version,
            req.target_version,
            req.target_image,
        )
        return status

    async def get_status(self) -> UpdateStatus:
        """Read the current update status written by the host supervisor or application."""
        if not self.status_file.is_file():
            return UpdateStatus(
                state=UpdateStatusState.IDLE,
                current_version=str(self.current_semver),
                message="System is up to date.",
            )

        try:
            content = self.status_file.read_text(encoding="utf-8")
            data = json.loads(content)
            status = UpdateStatus.from_dict(data)

            # If supervisor marked completed and current running version matches target, normalize
            if (
                status.state == UpdateStatusState.COMPLETED
                and status.target_version == str(self.current_semver)
            ):
                return UpdateStatus(
                    state=UpdateStatusState.IDLE,
                    current_version=str(self.current_semver),
                    message=f"Successfully running updated version {self.current_semver}.",
                )
            return status
        except Exception as exc:
            logger.warning("Failed to parse update-status.json: %s", exc)
            return UpdateStatus(
                state=UpdateStatusState.IDLE,
                current_version=str(self.current_semver),
                message="Failed to read update status; defaulting to idle.",
                error=str(exc),
            )

    async def clear_terminal_status(self) -> UpdateStatus:
        """Reset terminal status (completed/failed/rolled_back) back to IDLE."""
        current = await self.get_status()
        if not current.state.is_terminal:
            raise ValueError(
                f"Cannot clear active update status in state '{current.state.value}'."
            )

        status = UpdateStatus(
            state=UpdateStatusState.IDLE,
            current_version=str(self.current_semver),
            message="Status cleared.",
        )
        self._write_atomic_json(self.status_file, status.to_dict())
        return status


# Global UpdateService singleton
_update_service: UpdateService | None = None


def get_update_service() -> UpdateService:
    """Retrieve or initialize the global UpdateService singleton."""
    global _update_service
    if _update_service is None:
        _update_service = UpdateService()
    return _update_service
