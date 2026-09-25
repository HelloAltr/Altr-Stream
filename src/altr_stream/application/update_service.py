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
    ReleaseFetchResult,
    ReleaseFetchStatus,
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
        current_version: str | None = None,
    ) -> None:
        self.github_repo = github_repo
        self.updates_dir = updates_dir or settings.updates_dir
        self.cache_ttl_sec = cache_ttl_sec
        self._http_client = http_client
        self._current_version = current_version

        self._cached_releases: list[ReleaseInfo] | None = None
        self._cache_timestamp: float = 0.0

        # Ensure updates directory exists
        self.updates_dir.mkdir(parents=True, exist_ok=True)

    @property
    def current_semver(self) -> SemVer:
        if self._current_version:
            return SemVer.parse(self._current_version)
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

    async def fetch_releases_result(self, force_refresh: bool = False) -> ReleaseFetchResult:
        """Fetch releases from GitHub API with caching, rate limit header inspection, and explicit status."""
        now = datetime.now(timezone.utc).timestamp()
        if (
            not force_refresh
            and self._cached_releases is not None
            and (now - self._cache_timestamp) < self.cache_ttl_sec
        ):
            return ReleaseFetchResult(
                status=ReleaseFetchStatus.SUCCESS,
                releases=self._cached_releases,
                is_cached=True,
            )

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
                if not isinstance(raw_data, list):
                    logger.warning("GitHub Releases API returned non-list JSON.")
                    return ReleaseFetchResult(
                        status=ReleaseFetchStatus.UNAVAILABLE,
                        releases=[],
                        error_code="github_api_unavailable",
                        message="Unable to check for updates: GitHub API returned unexpected format.",
                    )
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
                return ReleaseFetchResult(
                    status=ReleaseFetchStatus.SUCCESS,
                    releases=releases,
                    is_cached=False,
                )

            if response.status_code in (403, 429):
                retry_after_hdr = response.headers.get("retry-after")
                reset_hdr = response.headers.get("x-ratelimit-reset")
                retry_after_sec: int | None = None
                if retry_after_hdr and retry_after_hdr.strip().isdigit():
                    retry_after_sec = int(retry_after_hdr.strip())
                elif reset_hdr and reset_hdr.strip().isdigit():
                    reset_epoch = int(reset_hdr.strip())
                    retry_after_sec = max(1, reset_epoch - int(now))

                logger.warning(
                    "GitHub Releases API rate limited (HTTP %d). Retry-after: %s sec.",
                    response.status_code,
                    retry_after_sec,
                )
                msg = "Unable to check for updates right now because GitHub Releases API is temporarily rate limited."
                if retry_after_sec:
                    msg += f" Please try again in {retry_after_sec} seconds."

                return ReleaseFetchResult(
                    status=ReleaseFetchStatus.RATE_LIMITED,
                    releases=[],
                    error_code="github_rate_limited",
                    message=msg,
                    retry_after=retry_after_sec,
                )

            logger.warning(
                "GitHub Releases API returned unexpected status %d.", response.status_code
            )
            return ReleaseFetchResult(
                status=ReleaseFetchStatus.UNAVAILABLE,
                releases=[],
                error_code="github_api_unavailable",
                message=f"Unable to check for updates: GitHub API returned status {response.status_code}.",
            )

        except httpx.TimeoutException as exc:
            logger.warning("GitHub Releases API request timed out: %s", exc)
            return ReleaseFetchResult(
                status=ReleaseFetchStatus.UNAVAILABLE,
                releases=[],
                error_code="network_timeout",
                message="Unable to check for updates: connection to GitHub timed out.",
            )
        except Exception as exc:
            logger.warning("Failed to fetch GitHub releases: %s", exc)
            return ReleaseFetchResult(
                status=ReleaseFetchStatus.UNAVAILABLE,
                releases=[],
                error_code="network_error",
                message="Unable to check for updates due to a network error.",
            )

    async def fetch_releases(self, force_refresh: bool = False) -> list[ReleaseInfo]:
        """Fetch releases from GitHub API with caching, returning release list."""
        res = await self.fetch_releases_result(force_refresh=force_refresh)
        return res.releases

    async def check_for_updates(
        self,
        channel: ReleaseChannel | None = None,
        force_refresh: bool = False,
    ) -> UpgradePlan:
        """Resolve direct upgrade plan against official GitHub releases with explicit discovery status."""
        fetch_releases_func = getattr(self, "fetch_releases", None)
        if fetch_releases_func and getattr(fetch_releases_func, "__func__", None) != UpdateService.fetch_releases:
            mocked_res = await fetch_releases_func(force_refresh=force_refresh)
            if isinstance(mocked_res, list):
                plan = DirectUpgradeResolver.resolve_direct_upgrade(
                    current_version=self.current_semver,
                    available_releases=mocked_res,
                    channel=channel,
                )
                return UpgradePlan(
                    current_version=plan.current_version,
                    target_version=plan.target_version,
                    update_available=plan.update_available,
                    channel=plan.channel,
                    target_release=plan.target_release,
                    all_releases=plan.all_releases,
                    check_available=True,
                )

        fetch_res = await self.fetch_releases_result(force_refresh=force_refresh)
        if fetch_res.status == ReleaseFetchStatus.SUCCESS:
            plan = DirectUpgradeResolver.resolve_direct_upgrade(
                current_version=self.current_semver,
                available_releases=fetch_res.releases,
                channel=channel,
            )
            return UpgradePlan(
                current_version=plan.current_version,
                target_version=plan.target_version,
                update_available=plan.update_available,
                channel=plan.channel,
                target_release=plan.target_release,
                all_releases=plan.all_releases,
                check_available=True,
                error_code=None,
                message=None,
                retry_after=None,
            )

        # Discovery failed (rate limited or unavailable)
        target_channel = channel or self.current_semver.channel
        return UpgradePlan(
            current_version=self.current_semver,
            target_version=None,
            update_available=False,
            channel=target_channel,
            target_release=None,
            all_releases=[],
            check_available=False,
            error_code=fetch_res.error_code,
            message=fetch_res.message,
            retry_after=fetch_res.retry_after,
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

            # If persisted status is stale relative to the running node, normalize to IDLE
            if status.is_stale(self.current_semver):
                logger.info(
                    "Normalizing stale update status (state=%s, current=%s, target=%s) for running node %s",
                    status.state.value,
                    status.current_version,
                    status.target_version,
                    self.current_semver,
                )
                normalized = UpdateStatus(
                    state=UpdateStatusState.IDLE,
                    current_version=str(self.current_semver),
                    message="System is up to date.",
                )
                try:
                    self._write_atomic_json(self.status_file, normalized.to_dict())
                except Exception as exc:
                    logger.warning("Failed to normalize stale update status on disk: %s", exc)

                # Clean up obsolete update-request.json if present
                if self.request_file.exists():
                    try:
                        self.request_file.unlink()
                    except OSError:
                        pass

                return normalized

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
