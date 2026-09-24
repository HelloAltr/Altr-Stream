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
import subprocess
import time
from typing import Any
import urllib.request
import urllib.error

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

    def get_current_image(self, compose_file: Path, service_name: str) -> str:
        raise NotImplementedError

    def recreate_service(self, compose_file: Path, service_name: str, image: str) -> None:
        raise NotImplementedError


class HostDockerClient(DockerClientInterface):
    """Executes Docker CLI commands on the host."""

    def pull_image(self, image: str) -> None:
        logger.info("Pulling container image: %s", image)
        cmd = ["docker", "pull", image]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"docker pull failed ({res.returncode}): {res.stderr.strip()}")

    def get_current_image(self, compose_file: Path, service_name: str) -> str:
        cmd = [
            "docker",
            "compose",
            "-f",
            str(compose_file),
            "images",
            "--format",
            "json",
            service_name,
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            try:
                lines = [l for l in res.stdout.strip().splitlines() if l.strip()]
                if lines:
                    data = json.loads(lines[0])
                    repo = data.get("Repository")
                    tag = data.get("Tag")
                    if repo and tag:
                        return f"{repo}:{tag}"
            except Exception as exc:
                logger.warning("Failed to parse docker compose images output: %s", exc)

        # Fallback to inspect running container
        inspect_cmd = [
            "docker",
            "inspect",
            "--format",
            "{{.Config.Image}}",
            service_name,
        ]
        res_inspect = subprocess.run(inspect_cmd, capture_output=True, text=True)
        if res_inspect.returncode == 0 and res_inspect.stdout.strip():
            return res_inspect.stdout.strip()

        return ""

    def recreate_service(self, compose_file: Path, service_name: str, image: str) -> None:
        logger.info("Recreating service '%s' with image: %s", service_name, image)
        env = os.environ.copy()
        env["ALTR_STREAM_IMAGE"] = image

        cmd = [
            "docker",
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


class HostHealthChecker(HealthCheckerInterface):
    """Verifies node health by polling /api/v1/health."""

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
    ) -> None:
        self.updates_dir = updates_dir.resolve()
        self.compose_file = compose_file.resolve()
        self.service_name = service_name
        self.health_url = health_url
        self.docker_client = docker_client or HostDockerClient()
        self.health_checker = health_checker or HostHealthChecker()
        self.health_timeout_sec = health_timeout_sec

        self.updates_dir.mkdir(parents=True, exist_ok=True)

    @property
    def request_file(self) -> Path:
        return self.updates_dir / "update-request.json"

    @property
    def status_file(self) -> Path:
        return self.updates_dir / "update-status.json"

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
            try:
                self.request_file.unlink()
            except OSError:
                pass
            return None

        request_id = req.get("request_id")
        current_version = req.get("current_version", "unknown")
        target_version = req.get("target_version", "unknown")
        target_image = req["target_image"]

        logger.info(
            "Starting update workflow %s: %s -> %s (%s)",
            request_id,
            current_version,
            target_version,
            target_image,
        )

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
            try:
                self.request_file.unlink()
            except OSError:
                pass
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
            try:
                self.request_file.unlink()
            except OSError:
                pass
            return final_status

        # 5. Failure & Rollback Branch: ROLLING_BACK -> ROLLED_BACK
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

        try:
            self.docker_client.recreate_service(
                self.compose_file, self.service_name, previous_image
            )
            rollback_health = self.health_checker.wait_for_health(
                health_url=self.health_url,
                expected_version=current_version,
                timeout_sec=self.health_timeout_sec,
            )
            if not rollback_health:
                logger.error("Rollback container failed health check!")
        except Exception as exc:
            logger.error("Error during rollback recreation: %s", exc)

        final_status = {
            "request_id": request_id,
            "state": "rolled_back",
            "current_version": current_version,
            "target_version": target_version,
            "progress_percent": 100,
            "message": f"Rolled back to previous version {current_version} due to failure.",
            "error": "New version failed health verification; rollback executed.",
            "rollback_performed": True,
        }
        self._write_status_atomic(final_status)
        try:
            self.request_file.unlink()
        except OSError:
            pass
        return final_status

    def run_loop(self, poll_interval: float = 2.0, once: bool = False) -> None:
        """Supervisor monitoring loop."""
        logger.info(
            "Supervisor watching for update requests in '%s' (once=%s)...",
            self.updates_dir,
            once,
        )
        while True:
            self.process_pending_request()
            if once:
                break
            time.sleep(poll_interval)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] [Supervisor] %(message)s",
    )
    parser = argparse.ArgumentParser(description="Altr Stream Host Supervisor")
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
        "--once",
        action="store_true",
        help="Process a single pending request and exit",
    )

    args = parser.parse_args()
    supervisor = AltrSupervisor(
        updates_dir=args.updates_dir,
        compose_file=args.compose_file,
        service_name=args.service_name,
        health_url=args.health_url,
        health_timeout_sec=args.health_timeout,
    )
    supervisor.run_loop(poll_interval=args.poll_interval, once=args.once)


if __name__ == "__main__":
    main()
