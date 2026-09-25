"""Host-level supervisor for Altr Stream container updates and rollback execution.

Runs exclusively on the host (never inside the application container).
Watches file-based IPC update requests, orchestrates privileged Docker commands,
verifies application health, and executes automated rollback if activation fails.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
from typing import Any
import urllib.request
import urllib.error

# Ensure project 'src' directory is in sys.path even when supervisor.py is run directly
_SRC_DIR = Path(__file__).resolve().parent.parent.parent
if str(_SRC_DIR) not in sys.path:
    sys.path.insert(0, str(_SRC_DIR))

from altr_stream.domain.semver import SemVer

# Setup logging
logger = logging.getLogger("altr_supervisor")

ALLOWED_IMAGE_PREFIXES = (
    "ghcr.io/helloaltr/altr-stream:",
    "altr-stream:",
)


class DockerClientInterface:
    """Interface for host Docker engine interactions."""

    def pull_image(self, image: str) -> None:
        raise NotImplementedError

    def image_exists_locally(self, image: str) -> bool:
        """Check if image exists in host Docker local cache."""
        return False

    def get_current_image(self, compose_file: Path, service_name: str) -> str:
        raise NotImplementedError

    def recreate_service(self, compose_file: Path, service_name: str, image: str) -> None:
        raise NotImplementedError

    def copy_from_container(self, service_name: str, container_path: str, host_path: Path) -> bool:
        """Copy file or directory from container to host. Returns True on success, False if absent/failed."""
        return False

    def copy_to_container(self, service_name: str, host_path: Path, container_path: str) -> bool:
        """Copy file or directory from host to container. Returns True on success, False on failure."""
        return False

    def remove_in_container(self, service_name: str, container_path: str) -> bool:
        """Remove file or directory inside container. Returns True on success, False on failure."""
        return False


class HostDockerClient(DockerClientInterface):
    """Executes Docker CLI commands on the host."""

    def __init__(self, docker_bin: str | None = None) -> None:
        self.docker_bin = docker_bin or self._find_docker()

    @staticmethod
    def _find_docker() -> str:
        which_docker = shutil.which("docker")
        if which_docker:
            return which_docker
        candidates = [
            Path.home() / ".docker" / "bin" / "docker",
            Path("/opt/homebrew/bin/docker"),
            Path("/usr/local/bin/docker"),
            Path("/usr/bin/docker"),
        ]
        for c in candidates:
            if c.is_file() and os.access(c, os.X_OK):
                return str(c)
        return "docker"

    def _get_env(self) -> dict[str, str]:
        env = os.environ.copy()
        extra_paths = [
            str(Path.home() / ".docker" / "bin"),
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        current_path = env.get("PATH", "")
        for ep in extra_paths:
            if ep not in current_path:
                current_path = f"{ep}:{current_path}"
        env["PATH"] = current_path
        return env

    def image_exists_locally(self, image: str) -> bool:
        cmd = [self.docker_bin, "image", "inspect", image]
        res = subprocess.run(cmd, env=self._get_env(), capture_output=True, text=True)
        return res.returncode == 0

    def pull_image(self, image: str) -> None:
        logger.info("Pulling container image: %s", image)
        cmd = [self.docker_bin, "pull", image]
        res = subprocess.run(cmd, env=self._get_env(), capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"docker pull failed ({res.returncode}): {res.stderr.strip()}")

    def get_current_image(self, compose_file: Path, service_name: str) -> str:
        cmd = [
            self.docker_bin,
            "compose",
            "-f",
            str(compose_file),
            "images",
            "--format",
            "json",
            service_name,
        ]
        res = subprocess.run(cmd, env=self._get_env(), capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            try:
                parsed = json.loads(res.stdout.strip())
                item: dict[str, Any] = {}
                if isinstance(parsed, list) and parsed:
                    item = parsed[0] if isinstance(parsed[0], dict) else {}
                elif isinstance(parsed, dict):
                    item = parsed

                repo = item.get("Repository") or item.get("repository")
                tag = item.get("Tag") or item.get("tag")
                if repo and tag:
                    return f"{repo}:{tag}"
            except Exception as exc:
                logger.warning("Failed to parse docker compose images output: %s", exc)

        # Fallback to inspect running container
        inspect_cmd = [
            self.docker_bin,
            "inspect",
            "--format",
            "{{.Config.Image}}",
            service_name,
        ]
        res_inspect = subprocess.run(inspect_cmd, env=self._get_env(), capture_output=True, text=True)
        if res_inspect.returncode == 0 and res_inspect.stdout.strip():
            return res_inspect.stdout.strip()

        return ""

    def recreate_service(self, compose_file: Path, service_name: str, image: str) -> None:
        logger.info("Recreating service '%s' with image: %s", service_name, image)
        env = self._get_env()
        env["ALTR_STREAM_IMAGE"] = image
        env.pop("ALTR_STREAM_APP_VERSION", None)
        env.pop("ALTR_STREAM_SIMULATED_VERSION", None)

        cmd = [
            self.docker_bin,
            "compose",
            "-f",
            str(compose_file),
            "up",
            "-d",
            "--no-deps",
            service_name,
        ]
        res = subprocess.run(cmd, env=env, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"docker compose up failed ({res.returncode}): {res.stderr.strip()}")

    def copy_from_container(self, service_name: str, container_path: str, host_path: Path) -> bool:
        host_path.parent.mkdir(parents=True, exist_ok=True)
        cmd = [self.docker_bin, "cp", f"{service_name}:{container_path}", str(host_path)]
        res = subprocess.run(cmd, env=self._get_env(), capture_output=True, text=True)
        return res.returncode == 0

    def copy_to_container(self, service_name: str, host_path: Path, container_path: str) -> bool:
        cmd = [self.docker_bin, "cp", str(host_path), f"{service_name}:{container_path}"]
        res = subprocess.run(cmd, env=self._get_env(), capture_output=True, text=True)
        return res.returncode == 0

    def remove_in_container(self, service_name: str, container_path: str) -> bool:
        cmd = [self.docker_bin, "exec", service_name, "rm", "-f", container_path]
        res = subprocess.run(cmd, env=self._get_env(), capture_output=True, text=True)
        return res.returncode == 0


class HealthCheckerInterface:
    """Interface for verifying application health."""

    def wait_for_health(
        self,
        health_url: str,
        expected_version: str | None = None,
        timeout_sec: int = 60,
        interval_sec: float = 2.0,
    ) -> bool:
        raise NotImplementedError

    def get_live_version(self, health_url: str) -> str | None:
        raise NotImplementedError


class HostHealthChecker(HealthCheckerInterface):
    """Verifies node health by polling /api/v1/health."""

    def get_live_version(self, health_url: str) -> str | None:
        try:
            req = urllib.request.Request(
                health_url,
                headers={"Accept": "application/json", "User-Agent": "Altr-Supervisor"},
            )
            with urllib.request.urlopen(req, timeout=2.0) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    v = data.get("version")
                    if v:
                        return str(v).strip()
        except Exception as exc:
            logger.debug("Live health check for node version failed: %s", exc)
        return None

    def wait_for_health(
        self,
        health_url: str,
        expected_version: str | None = None,
        timeout_sec: int = 60,
        interval_sec: float = 2.0,
    ) -> bool:
        logger.info("Polling health check at %s (timeout: %ds)...", health_url, timeout_sec)
        start_time = time.time()

        while (time.time() - start_time) < timeout_sec:
            try:
                req = urllib.request.Request(
                    health_url,
                    headers={"Accept": "application/json", "User-Agent": "Altr-Supervisor"},
                )
                with urllib.request.urlopen(req, timeout=3.0) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode("utf-8"))
                        status_val = data.get("status")
                        ver_val = data.get("version")

                        if status_val == "healthy":
                            if expected_version:
                                clean_exp = expected_version.lstrip("v")
                                clean_ver = str(ver_val).lstrip("v")
                                if clean_ver == clean_exp:
                                    logger.info(
                                        "Application is healthy and running expected version %s.",
                                        ver_val,
                                    )
                                    return True
                                logger.info(
                                    "Application healthy but version %s does not yet match expected %s. Waiting...",
                                    ver_val,
                                    clean_exp,
                                )
                            else:
                                logger.info("Application is healthy.")
                                return True
            except Exception as exc:
                logger.debug("Health check poll attempt failed: %s", exc)

            time.sleep(interval_sec)

        logger.error("Health check timed out after %d seconds.", timeout_sec)
        return False


class AltrSupervisor:
    """Supervisor orchestrating atomic updates and safe rollbacks."""

    def __init__(
        self,
        updates_dir: Path,
        compose_file: Path,
        service_name: str = "altr-stream",
        health_url: str = "http://localhost:8000/api/v1/health",
        docker_client: DockerClientInterface | None = None,
        health_checker: HealthCheckerInterface | None = None,
        health_timeout_sec: int = 60,
        allow_local_images: bool | None = None,
    ) -> None:
        self.updates_dir = updates_dir.resolve()
        self.compose_file = compose_file.resolve()
        self.service_name = service_name
        self.health_url = health_url
        self.docker_client = docker_client or HostDockerClient()
        self.health_checker = health_checker or HostHealthChecker()
        self.health_timeout_sec = health_timeout_sec
        if allow_local_images is not None:
            self._allow_local_images = allow_local_images
        else:
            self._allow_local_images = os.environ.get("ALTR_SUPERVISOR_ALLOW_LOCAL_IMAGES", "").lower() in ("1", "true", "yes")

        self.updates_dir.mkdir(parents=True, exist_ok=True)

    @property
    def allow_local_images(self) -> bool:
        """Check if local image fallback is permitted for development/testing."""
        if self._allow_local_images:
            return True
        if os.environ.get("ALTR_SUPERVISOR_ALLOW_LOCAL_IMAGES", "").lower() in ("1", "true", "yes"):
            return True
        if (self.updates_dir / ".allow_local_images").is_file():
            return True
        return False

    @property
    def request_file(self) -> Path:
        return self.updates_dir / "update-request.json"

    @property
    def status_file(self) -> Path:
        return self.updates_dir / "update-status.json"

    def get_live_node_version(self) -> str | None:
        """Query live health endpoint for actual running node version."""
        return self.health_checker.get_live_version(self.health_url)

    def _write_status_atomic(self, status_data: dict[str, Any]) -> None:
        """Write status JSON atomically using PID-tagged temporary file."""
        status_data["updated_at"] = datetime.now(timezone.utc).isoformat()
        tmp_path = self.updates_dir / f"update-status.json.tmp.{os.getpid()}"
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(status_data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, self.status_file)
        finally:
            if tmp_path.exists():
                try:
                    tmp_path.unlink()
                except OSError:
                    pass

        try:
            self.docker_client.copy_to_container(
                self.service_name,
                self.status_file,
                "/app/data/updates/update-status.json",
            )
        except Exception as exc:
            logger.debug("Failed syncing status to container: %s", exc)

    def _cleanup_request_file(self) -> None:
        """Remove update-request.json from both host and container."""
        if self.request_file.exists():
            try:
                self.request_file.unlink()
            except OSError:
                pass
        try:
            self.docker_client.remove_in_container(
                self.service_name,
                "/app/data/updates/update-request.json",
            )
        except Exception as exc:
            logger.debug("Failed removing request file in container: %s", exc)

    def _validate_request(self, req: dict[str, Any]) -> None:
        """Validate request payload against strict security invariants."""
        target_image = req.get("target_image", "")
        if not target_image or not any(target_image.startswith(p) for p in ALLOWED_IMAGE_PREFIXES):
            raise ValueError(
                f"Unauthorized target image '{target_image}'. Must originate from an allowed registry."
            )

        target_version = req.get("target_version", "")
        if not target_version or any(c in target_version for c in ";;|&`$<>"):
            raise ValueError(f"Malformed or unsafe target version: '{target_version}'.")

    def process_pending_request(self) -> dict[str, Any] | None:
        """Inspect and execute pending update request if present."""
        # Synchronize from container if request_file does not yet exist on host
        if not self.request_file.is_file():
            try:
                copied = self.docker_client.copy_from_container(
                    self.service_name,
                    "/app/data/updates/update-request.json",
                    self.request_file,
                )
                if copied and self.request_file.is_file():
                    logger.info("Synchronized update request from container '%s' to host.", self.service_name)
                    self.docker_client.copy_from_container(
                        self.service_name,
                        "/app/data/updates/update-status.json",
                        self.status_file,
                    )
            except Exception as exc:
                logger.debug("Container sync check failed: %s", exc)

        if not self.request_file.is_file():
            return None

        try:
            req_content = self.request_file.read_text(encoding="utf-8")
            req = json.loads(req_content)
            self._validate_request(req)
        except Exception as exc:
            logger.error("Failed to parse or validate update request: %s", exc)
            self._write_status_atomic(
                {
                    "state": "failed",
                    "current_version": "unknown",
                    "error": f"Invalid update request: {exc}",
                    "message": "Update request validation failed.",
                    "progress_percent": 0,
                }
            )
            self._cleanup_request_file()
            return None

        request_id = req.get("request_id")
        current_version = req.get("current_version", "unknown")
        target_version = req.get("target_version", "unknown")
        target_image = req["target_image"]

        # Check running container image/version to reconcile already-satisfied or superseded requests.
        # Priority 1: Live node health endpoint (reflects actual running application version)
        # Priority 2: current_version recorded in update request
        # Priority 3: Docker image tag
        live_version = self.get_live_node_version()
        running_version_str = live_version or current_version or ""
        if not running_version_str or running_version_str == "unknown":
            current_image = self.docker_client.get_current_image(self.compose_file, self.service_name)
            if current_image and ":" in current_image:
                running_version_str = current_image.split(":")[-1]

        running_semver = SemVer.try_parse(running_version_str)
        target_semver = SemVer.try_parse(target_version)

        if running_semver and target_semver:
            if running_semver == target_semver:
                logger.info(
                    "Reconciling pending request %s: service '%s' is already running target version %s. Marking completed.",
                    request_id,
                    self.service_name,
                    running_semver,
                )
                status = {
                    "request_id": request_id,
                    "state": "completed",
                    "current_version": str(running_semver),
                    "target_version": target_version,
                    "progress_percent": 100,
                    "message": f"Service is already running v{target_version}.",
                    "error": None,
                    "rollback_performed": False,
                }
                self._write_status_atomic(status)
                self._cleanup_request_file()
                return status

            if running_semver > target_semver:
                logger.warning(
                    "Rejecting update request %s: service '%s' (v%s) is already on a newer version than requested target v%s.",
                    request_id,
                    self.service_name,
                    running_semver,
                    target_semver,
                )
                status = {
                    "request_id": request_id,
                    "state": "failed",
                    "current_version": str(running_semver),
                    "target_version": target_version,
                    "progress_percent": 0,
                    "message": f"Cannot update to older version v{target_version} (service is on v{running_semver}).",
                    "error": f"Target version v{target_version} is older than running v{running_semver}.",
                    "rollback_performed": False,
                }
                self._write_status_atomic(status)
                self._cleanup_request_file()
                return status

        logger.info(
            "Starting update workflow %s: %s -> %s (%s)",
            request_id,
            current_version,
            target_version,
            target_image,
        )

        # Capture expected version before update begins for rollback verification
        expected_previous_version = running_version_str or current_version

        # 1. State: STAGING (Pull image)
        self._write_status_atomic(
            {
                "request_id": request_id,
                "state": "staging",
                "current_version": current_version,
                "target_version": target_version,
                "progress_percent": 25,
                "message": f"Pulling target image {target_image}...",
                "error": None,
                "rollback_performed": False,
            }
        )

        try:
            self.docker_client.pull_image(target_image)
        except Exception as exc:
            if self.allow_local_images and self.docker_client.image_exists_locally(target_image):
                logger.warning(
                    "Remote pull failed for %s (%s), but image exists locally and allow_local_images is enabled. Proceeding with local image.",
                    target_image,
                    exc,
                )
            else:
                logger.error("Failed to pull image: %s", exc)
                status = {
                    "request_id": request_id,
                    "state": "failed",
                    "current_version": current_version,
                    "target_version": target_version,
                    "progress_percent": 0,
                    "message": "Failed to pull image.",
                    "error": str(exc),
                    "rollback_performed": False,
                }
                self._write_status_atomic(status)
                self._cleanup_request_file()
                return status

        # 2. State: APPLYING (Capture previous image & recreate service)
        previous_image = self.docker_client.get_current_image(self.compose_file, self.service_name)
        if not previous_image:
            previous_image = f"ghcr.io/helloaltr/altr-stream:{current_version}"

        logger.info("Preserved previous image for rollback: %s", previous_image)

        self._write_status_atomic(
            {
                "request_id": request_id,
                "state": "applying",
                "current_version": current_version,
                "target_version": target_version,
                "progress_percent": 50,
                "message": "Recreating application container with updated image...",
                "error": None,
                "rollback_performed": False,
            }
        )

        apply_failed = False
        try:
            self.docker_client.recreate_service(self.compose_file, self.service_name, target_image)
            self.docker_client.copy_to_container(
                self.service_name,
                self.status_file,
                "/app/data/updates/update-status.json",
            )
        except Exception as exc:
            logger.error("Failed to recreate service: %s", exc)
            apply_failed = True

        # 3. State: HEALTH_CHECK
        health_ok = False
        if not apply_failed:
            self._write_status_atomic(
                {
                    "request_id": request_id,
                    "state": "health_check",
                    "current_version": current_version,
                    "target_version": target_version,
                    "progress_percent": 75,
                    "message": "Verifying new version healthcheck...",
                    "error": None,
                    "rollback_performed": False,
                }
            )
            health_ok = self.health_checker.wait_for_health(
                health_url=self.health_url,
                expected_version=target_version,
                timeout_sec=self.health_timeout_sec,
            )

        # 4. Success Branch: COMPLETED
        if health_ok and not apply_failed:
            logger.info("Update %s successfully completed!", request_id)
            final_status = {
                "request_id": request_id,
                "state": "completed",
                "current_version": target_version,
                "target_version": target_version,
                "progress_percent": 100,
                "message": f"Update to {target_version} completed successfully.",
                "error": None,
                "rollback_performed": False,
            }
            self._write_status_atomic(final_status)
            self._cleanup_request_file()
            return final_status

        # 5. Failure & Rollback Branch: ROLLING_BACK -> ROLLED_BACK / FAILED
        logger.warning(
            "Activation failed for %s. Initiating automatic rollback to %s...",
            target_version,
            previous_image,
        )
        self._write_status_atomic(
            {
                "request_id": request_id,
                "state": "rolling_back",
                "current_version": current_version,
                "target_version": target_version,
                "progress_percent": 85,
                "message": f"Activation failed. Rolling back to {previous_image}...",
                "error": "Health check verification failed.",
                "rollback_performed": True,
            }
        )

        rollback_recreate_ok = False
        try:
            self.docker_client.recreate_service(
                self.compose_file, self.service_name, previous_image
            )
            rollback_recreate_ok = True
            self.docker_client.copy_to_container(
                self.service_name,
                self.status_file,
                "/app/data/updates/update-status.json",
            )
        except Exception as exc:
            logger.error("Error during rollback recreation: %s", exc)

        # Verify rollback health against expected previous version
        rollback_health_ok = False
        live_rollback_version: str | None = None
        if rollback_recreate_ok:
            rollback_health_ok = self.health_checker.wait_for_health(
                health_url=self.health_url,
                expected_version=expected_previous_version,
                timeout_sec=self.health_timeout_sec,
            )
            live_rollback_version = self.health_checker.get_live_version(self.health_url)

        # Decide terminal status based on whether rollback actually restored the expected previous version
        clean_exp = expected_previous_version.lstrip("v")
        clean_live = str(live_rollback_version or "").lstrip("v")
        is_truly_restored = rollback_health_ok and (clean_live == clean_exp)

        if is_truly_restored:
            final_version = live_rollback_version or expected_previous_version
            final_status = {
                "request_id": request_id,
                "state": "rolled_back",
                "current_version": final_version,
                "target_version": target_version,
                "progress_percent": 100,
                "message": f"Rolled back to previous version {final_version} due to failure.",
                "error": f"New version {target_version} failed health verification; successfully rolled back to {final_version}.",
                "rollback_performed": True,
            }
        else:
            final_version = live_rollback_version or current_version
            err_msg = (
                f"Update to {target_version} failed healthcheck. Rollback verification failed: "
                f"expected {expected_previous_version}, but node is running {live_rollback_version or 'unknown'}."
            )
            logger.error(err_msg)
            final_status = {
                "request_id": request_id,
                "state": "failed",
                "current_version": final_version,
                "target_version": target_version,
                "progress_percent": 100,
                "message": f"Update to {target_version} failed and rollback verification failed.",
                "error": err_msg,
                "rollback_performed": rollback_recreate_ok,
            }

        self._write_status_atomic(final_status)
        self._cleanup_request_file()
        return final_status

    def run_loop(self, poll_interval: float = 2.0, once: bool = False) -> None:
        """Supervisor monitoring loop."""
        logger.info(
            "Supervisor watching for update requests in '%s' (once=%s)...",
            self.updates_dir,
            once,
        )
        pid_file = self.updates_dir / "supervisor.pid"
        if not once:
            try:
                pid_file.write_text(str(os.getpid()), encoding="utf-8")
            except OSError:
                pass

        def _handle_term(signum: int, frame: Any) -> None:
            if not once and pid_file.is_file():
                try:
                    if int(pid_file.read_text(encoding="utf-8").strip()) == os.getpid():
                        pid_file.unlink(missing_ok=True)
                except (ValueError, OSError):
                    pass
            sys.exit(0)

        try:
            signal.signal(signal.SIGTERM, _handle_term)
            signal.signal(signal.SIGINT, _handle_term)
        except (ValueError, AttributeError):
            pass

        try:
            while True:
                self.process_pending_request()
                if once:
                    break
                time.sleep(poll_interval)
        finally:
            if not once and pid_file.is_file():
                try:
                    if int(pid_file.read_text(encoding="utf-8").strip()) == os.getpid():
                        pid_file.unlink(missing_ok=True)
                except (ValueError, OSError):
                    pass


def is_pid_alive(pid: int) -> bool:
    """Check whether a process with the given PID is actively running."""
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def start_daemon(
    updates_dir: Path,
    compose_file: Path,
    service_name: str = "altr-stream",
    health_url: str = "http://localhost:8000/api/v1/health",
    health_timeout_sec: int = 60,
    poll_interval: float = 2.0,
    allow_local_images: bool | None = None,
) -> int:
    """Start supervisor as a detached background daemon on the host."""
    updates_dir = updates_dir.resolve()
    updates_dir.mkdir(parents=True, exist_ok=True)
    pid_file = updates_dir / "supervisor.pid"
    log_file = updates_dir / "supervisor.log"

    if pid_file.is_file():
        try:
            old_pid = int(pid_file.read_text(encoding="utf-8").strip())
            if is_pid_alive(old_pid):
                print(f"AltrSupervisor is already running (PID {old_pid}).")
                return 0
        except (ValueError, OSError):
            pass
        pid_file.unlink(missing_ok=True)

    script_path = Path(__file__).resolve()
    cmd = [
        sys.executable,
        str(script_path),
        "run",
        "--updates-dir",
        str(updates_dir),
        "--compose-file",
        str(compose_file.resolve()),
        "--service-name",
        service_name,
        "--health-url",
        health_url,
        "--health-timeout",
        str(health_timeout_sec),
        "--poll-interval",
        str(poll_interval),
    ]

    effective_allow_local = (
        allow_local_images
        if allow_local_images is not None
        else os.environ.get("ALTR_SUPERVISOR_ALLOW_LOCAL_IMAGES", "").lower() in ("1", "true", "yes")
    )
    if effective_allow_local:
        cmd.append("--allow-local-images")

    log_fp = open(log_file, "a", encoding="utf-8")
    proc = subprocess.Popen(
        cmd,
        stdout=log_fp,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    pid_file.write_text(str(proc.pid), encoding="utf-8")
    print(f"AltrSupervisor daemon started (PID {proc.pid}). Logs: {log_file}")
    return 0


def stop_daemon(updates_dir: Path) -> int:
    """Stop the running background supervisor daemon."""
    updates_dir = updates_dir.resolve()
    pid_file = updates_dir / "supervisor.pid"
    if not pid_file.is_file():
        print("AltrSupervisor is not running (no PID file found).")
        return 0

    try:
        pid = int(pid_file.read_text(encoding="utf-8").strip())
    except (ValueError, OSError):
        print("Invalid PID file; removing.")
        pid_file.unlink(missing_ok=True)
        return 0

    if not is_pid_alive(pid):
        print(f"AltrSupervisor process (PID {pid}) is not running; cleaning up PID file.")
        pid_file.unlink(missing_ok=True)
        return 0

    print(f"Stopping AltrSupervisor daemon (PID {pid})...")
    try:
        os.kill(pid, signal.SIGTERM)
        for _ in range(25):
            time.sleep(0.2)
            if not is_pid_alive(pid):
                break
        else:
            print("Process did not exit cleanly; sending SIGKILL...")
            os.kill(pid, signal.SIGKILL)
    except OSError as exc:
        print(f"Error terminating process: {exc}")

    pid_file.unlink(missing_ok=True)
    print("AltrSupervisor daemon stopped.")
    return 0


def status_daemon(updates_dir: Path) -> int:
    """Check the status of the background supervisor daemon."""
    updates_dir = updates_dir.resolve()
    pid_file = updates_dir / "supervisor.pid"
    if pid_file.is_file():
        try:
            pid = int(pid_file.read_text(encoding="utf-8").strip())
            if is_pid_alive(pid):
                print(f"AltrSupervisor is running (PID {pid}).")
                return 0
            else:
                pid_file.unlink(missing_ok=True)
                print(f"AltrSupervisor is stopped (cleaned up stale PID {pid}).")
        except (ValueError, OSError):
            pass

    # Fallback: check process list for altr_supervisor
    try:
        res = subprocess.run(["pgrep", "-f", "altr_supervisor.py"], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            pids = [int(p) for p in res.stdout.strip().splitlines() if p.isdigit() and int(p) != os.getpid()]
            if pids:
                print(f"AltrSupervisor is running (PID {pids[0]}).")
                return 0
    except Exception:
        pass

    print("AltrSupervisor is stopped.")
    return 3


def main() -> None:
    parser = argparse.ArgumentParser(description="Altr Stream Host Supervisor")
    parser.add_argument(
        "action",
        nargs="?",
        default="run",
        choices=["run", "start", "stop", "status", "restart"],
        help="Supervisor daemon action (default: run)",
    )
    parser.add_argument(
        "--updates-dir",
        type=Path,
        default=Path("data/updates"),
        help="Path to IPC updates directory",
    )
    parser.add_argument(
        "--compose-file",
        type=Path,
        default=Path("docker-compose.yml"),
        help="Path to production docker-compose.yml",
    )
    parser.add_argument(
        "--service-name",
        type=str,
        default="altr-stream",
        help="Name of the service in Compose",
    )
    parser.add_argument(
        "--health-url",
        type=str,
        default="http://localhost:8000/api/v1/health",
        help="URL of application health endpoint",
    )
    parser.add_argument(
        "--health-timeout",
        type=int,
        default=60,
        help="Timeout in seconds for healthcheck",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=2.0,
        help="Seconds between polling for update requests",
    )
    parser.add_argument(
        "--allow-local-images",
        action="store_true",
        default=os.environ.get("ALTR_SUPERVISOR_ALLOW_LOCAL_IMAGES", "").lower() in ("1", "true", "yes"),
        help="Permit fallback to locally cached Docker images if remote registry pull fails (development/testing only)",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Process a single pending request and exit (only for run action)",
    )

    args = parser.parse_args()

    if args.action == "start":
        sys.exit(
            start_daemon(
                updates_dir=args.updates_dir,
                compose_file=args.compose_file,
                service_name=args.service_name,
                health_url=args.health_url,
                health_timeout_sec=args.health_timeout,
                poll_interval=args.poll_interval,
                allow_local_images=args.allow_local_images,
            )
        )
    elif args.action == "stop":
        sys.exit(stop_daemon(updates_dir=args.updates_dir))
    elif args.action == "status":
        sys.exit(status_daemon(updates_dir=args.updates_dir))
    elif args.action == "restart":
        stop_daemon(updates_dir=args.updates_dir)
        sys.exit(
            start_daemon(
                updates_dir=args.updates_dir,
                compose_file=args.compose_file,
                service_name=args.service_name,
                health_url=args.health_url,
                health_timeout_sec=args.health_timeout,
                poll_interval=args.poll_interval,
                allow_local_images=args.allow_local_images,
            )
        )

    # Default action: run in foreground
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] [Supervisor] %(message)s",
    )
    supervisor = AltrSupervisor(
        updates_dir=args.updates_dir,
        compose_file=args.compose_file,
        service_name=args.service_name,
        health_url=args.health_url,
        health_timeout_sec=args.health_timeout,
        allow_local_images=args.allow_local_images,
    )
    supervisor.run_loop(poll_interval=args.poll_interval, once=args.once)


if __name__ == "__main__":
    main()
