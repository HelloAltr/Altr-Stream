"""Unit tests for AltrSupervisor, IPC transitions, and automated rollback engine."""

import json
from pathlib import Path
import pytest

from altr_stream.supervisor import (
    AltrSupervisor,
    DockerClientInterface,
    HealthCheckerInterface,
)


class MockDockerClient(DockerClientInterface):
    def __init__(self, current_image: str = "ghcr.io/helloaltr/altr-stream:0.13.1-alpha"):
        self.current_image = current_image
        self.pull_calls: list[str] = []
        self.recreate_calls: list[tuple[str, str]] = []
        self.fail_pull = False
        self.fail_recreate = False

    def pull_image(self, image: str) -> None:
        if self.fail_pull:
            raise RuntimeError("Connection timed out contacting GHCR.")
        self.pull_calls.append(image)

    def get_current_image(self, compose_file: Path, service_name: str) -> str:
        return self.current_image

    def recreate_service(self, compose_file: Path, service_name: str, image: str) -> None:
        if self.fail_recreate:
            raise RuntimeError("Docker daemon unavailable.")
        self.recreate_calls.append((service_name, image))


class MockHealthChecker(HealthCheckerInterface):
    def __init__(self, healthy: bool = True):
        self.healthy = healthy
        self.checked_urls: list[str] = []
        self.expected_versions: list[str | None] = []

    def wait_for_health(
        self,
        health_url: str,
        expected_version: str | None = None,
        timeout_sec: int = 60,
        interval_sec: float = 2.0,
    ) -> bool:
        self.checked_urls.append(health_url)
        self.expected_versions.append(expected_version)
        return self.healthy


@pytest.fixture
def updates_dir(tmp_path: Path) -> Path:
    d = tmp_path / "updates"
    d.mkdir(parents=True, exist_ok=True)
    return d


@pytest.fixture
def compose_file(tmp_path: Path) -> Path:
    f = tmp_path / "docker-compose.yml"
    f.write_text("services: { altr-stream: { image: test } }")
    return f


def test_supervisor_successful_update_lifecycle(updates_dir: Path, compose_file: Path):
    docker_client = MockDockerClient(current_image="ghcr.io/helloaltr/altr-stream:0.13.1-alpha")
    health_checker = MockHealthChecker(healthy=True)

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        service_name="altr-stream",
        docker_client=docker_client,
        health_checker=health_checker,
        health_timeout_sec=5,
    )

    # 1. Simulate an update request from the application
    req_file = updates_dir / "update-request.json"
    req_data = {
        "request_id": "test-req-123",
        "current_version": "0.13.1-alpha",
        "target_version": "0.13.2-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.2-alpha",
        "created_at": "2026-09-24T00:00:00Z",
        "channel": "alpha",
    }
    req_file.write_text(json.dumps(req_data))

    # 2. Run supervisor process
    result = supervisor.process_pending_request()

    assert result is not None
    assert result["state"] == "completed"
    assert result["target_version"] == "0.13.2-alpha"
    assert result["progress_percent"] == 100
    assert result["rollback_performed"] is False

    # Verify Docker and Health calls
    assert docker_client.pull_calls == ["ghcr.io/helloaltr/altr-stream:0.13.2-alpha"]
    assert docker_client.recreate_calls == [
        ("altr-stream", "ghcr.io/helloaltr/altr-stream:0.13.2-alpha")
    ]
    assert health_checker.expected_versions == ["0.13.2-alpha"]

    # Verify update-request was cleaned up
    assert not req_file.exists()

    # Verify update-status.json contains completed state
    status_content = json.loads((updates_dir / "update-status.json").read_text())
    assert status_content["state"] == "completed"


def test_supervisor_pull_failure_marks_failed(updates_dir: Path, compose_file: Path):
    docker_client = MockDockerClient()
    docker_client.fail_pull = True
    health_checker = MockHealthChecker(healthy=True)

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        docker_client=docker_client,
        health_checker=health_checker,
    )

    req_file = updates_dir / "update-request.json"
    req_data = {
        "request_id": "test-req-pull-fail",
        "current_version": "0.13.1-alpha",
        "target_version": "0.13.2-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.2-alpha",
        "created_at": "2026-09-24T00:00:00Z",
    }
    req_file.write_text(json.dumps(req_data))

    result = supervisor.process_pending_request()

    assert result["state"] == "failed"
    assert "Failed to pull image" in result["message"]
    assert not req_file.exists()


def test_supervisor_activation_failure_executes_automated_rollback(updates_dir: Path, compose_file: Path):
    docker_client = MockDockerClient(current_image="ghcr.io/helloaltr/altr-stream:0.13.1-alpha")
    # Healthcheck fails for new version!
    health_checker = MockHealthChecker(healthy=False)

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        service_name="altr-stream",
        docker_client=docker_client,
        health_checker=health_checker,
        health_timeout_sec=5,
    )

    req_file = updates_dir / "update-request.json"
    req_data = {
        "request_id": "test-req-rollback",
        "current_version": "0.13.1-alpha",
        "target_version": "0.13.2-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.2-alpha",
        "created_at": "2026-09-24T00:00:00Z",
    }
    req_file.write_text(json.dumps(req_data))

    result = supervisor.process_pending_request()

    assert result is not None
    assert result["state"] == "rolled_back"
    assert result["rollback_performed"] is True
    assert "Rolled back" in result["message"]

    # Verify sequence of container recreation: first target image, then rollback to previous
    assert docker_client.recreate_calls == [
        ("altr-stream", "ghcr.io/helloaltr/altr-stream:0.13.2-alpha"),
        ("altr-stream", "ghcr.io/helloaltr/altr-stream:0.13.1-alpha"),
    ]

    # Verify update-request was cleaned up
    assert not req_file.exists()


def test_supervisor_rejects_unauthorized_image_origin(updates_dir: Path, compose_file: Path):
    docker_client = MockDockerClient()
    health_checker = MockHealthChecker()

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        docker_client=docker_client,
        health_checker=health_checker,
    )

    req_file = updates_dir / "update-request.json"
    req_data = {
        "request_id": "evil-request",
        "current_version": "0.13.1-alpha",
        "target_version": "0.13.2-alpha",
        "target_image": "evil-hacker-registry.com/malicious:latest",
        "created_at": "2026-09-24T00:00:00Z",
    }
    req_file.write_text(json.dumps(req_data))

    supervisor.process_pending_request()

    # Request is discarded and status marked failed
    assert not req_file.exists()
    status_content = json.loads((updates_dir / "update-status.json").read_text())
    assert status_content["state"] == "failed"
    assert "Unauthorized target image" in status_content["error"]
