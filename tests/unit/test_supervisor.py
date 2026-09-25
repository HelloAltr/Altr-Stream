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
    def __init__(
        self,
        current_image: str = "ghcr.io/helloaltr/altr-stream:0.13.1-alpha",
        local_images: dict[str, bool] | None = None,
    ):
        self.current_image = current_image
        self.local_images = dict(local_images or {})
        self.pull_calls: list[str] = []
        self.recreate_calls: list[tuple[str, str]] = []
        self.copy_from_calls: list[tuple[str, str, Path]] = []
        self.copy_to_calls: list[tuple[Path, str, str]] = []
        self.remove_in_calls: list[tuple[str, str]] = []
        self.container_files: dict[str, str] = {}
        self.fail_pull = False
        self.fail_recreate = False

    def image_exists_locally(self, image: str) -> bool:
        return self.local_images.get(image, False)

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

    def copy_from_container(self, container_name: str, container_path: str, host_path: Path) -> bool:
        self.copy_from_calls.append((container_name, container_path, host_path))
        if container_path in self.container_files:
            host_path.parent.mkdir(parents=True, exist_ok=True)
            host_path.write_text(self.container_files[container_path], encoding="utf-8")
            return True
        return False

    def copy_to_container(self, service_name: str, host_path: Path, container_path: str) -> bool:
        self.copy_to_calls.append((service_name, host_path, container_path))
        if host_path.exists():
            self.container_files[container_path] = host_path.read_text(encoding="utf-8")
            return True
        return False

    def remove_in_container(self, container_name: str, container_path: str) -> bool:
        self.remove_in_calls.append((container_name, container_path))
        self.container_files.pop(container_path, None)
        return True


class MockHealthChecker(HealthCheckerInterface):
    def __init__(
        self,
        healthy: bool = True,
        live_version: str | None = None,
        health_sequence: list[bool] | None = None,
        live_version_sequence: list[str | None] | None = None,
    ):
        self.healthy = healthy
        self.live_version = live_version
        self.health_sequence = list(health_sequence) if health_sequence is not None else None
        self.live_version_sequence = list(live_version_sequence) if live_version_sequence is not None else None
        self.checked_urls: list[str] = []
        self.expected_versions: list[str | None] = []

    def get_live_version(self, health_url: str) -> str | None:
        if self.live_version_sequence:
            return self.live_version_sequence.pop(0)
        return self.live_version

    def wait_for_health(
        self,
        health_url: str,
        expected_version: str | None = None,
        timeout_sec: int = 60,
        interval_sec: float = 2.0,
    ) -> bool:
        self.checked_urls.append(health_url)
        self.expected_versions.append(expected_version)
        if self.health_sequence:
            return self.health_sequence.pop(0)
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
    # Healthcheck: fails for target 0.13.2, succeeds for rollback to 0.13.1
    health_checker = MockHealthChecker(
        health_sequence=[False, True],
        live_version="0.13.1-alpha",
    )

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


def test_supervisor_syncs_request_from_container_when_not_on_host(updates_dir: Path, compose_file: Path):
    docker_client = MockDockerClient(current_image="ghcr.io/helloaltr/altr-stream:0.13.3-alpha")
    health_checker = MockHealthChecker(healthy=True)

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        service_name="altr-stream",
        docker_client=docker_client,
        health_checker=health_checker,
        health_timeout_sec=5,
    )

    # Simulate request written inside container volume, but not present on host filesystem
    req_data = {
        "request_id": "req-container-sync-123",
        "current_version": "0.13.3-alpha",
        "target_version": "0.13.4-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.4-alpha",
        "created_at": "2026-09-24T00:00:00Z",
        "channel": "alpha",
    }
    docker_client.container_files["/app/data/updates/update-request.json"] = json.dumps(req_data)

    # Verify not on host initially
    req_file = updates_dir / "update-request.json"
    assert not req_file.exists()

    # Run supervisor process
    result = supervisor.process_pending_request()

    assert result is not None
    assert result["state"] == "completed"
    assert result["target_version"] == "0.13.4-alpha"
    assert result["progress_percent"] == 100

    # Verify copy_from_container was invoked to retrieve the request
    assert any(call[1] == "/app/data/updates/update-request.json" for call in docker_client.copy_from_calls)

    # Verify status was written and synced back into container
    assert "/app/data/updates/update-status.json" in docker_client.container_files
    container_status = json.loads(docker_client.container_files["/app/data/updates/update-status.json"])
    assert container_status["state"] == "completed"

    # Verify request was cleaned up from container
    assert "/app/data/updates/update-request.json" not in docker_client.container_files


def test_host_docker_client_get_current_image_parses_json_list(monkeypatch, compose_file: Path):
    from altr_stream.supervisor.supervisor import HostDockerClient
    import subprocess

    client = HostDockerClient()

    # Simulate modern Docker Compose output: JSON array
    mock_json_list = json.dumps([
        {
            "ContainerName": "altr-stream",
            "Repository": "ghcr.io/helloaltr/altr-stream",
            "Tag": "0.13.2-alpha",
        }
    ])

    def mock_run(cmd, *args, **kwargs):
        if "images" in cmd:
            return subprocess.CompletedProcess(cmd, 0, stdout=mock_json_list, stderr="")
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", mock_run)
    image = client.get_current_image(compose_file, "altr-stream")
    assert image == "ghcr.io/helloaltr/altr-stream:0.13.2-alpha"


def test_host_docker_client_get_current_image_parses_json_dict(monkeypatch, compose_file: Path):
    from altr_stream.supervisor.supervisor import HostDockerClient
    import subprocess

    client = HostDockerClient()

    # Simulate legacy Docker Compose output: single dict
    mock_json_dict = json.dumps({
        "Repository": "ghcr.io/helloaltr/altr-stream",
        "Tag": "0.13.3-alpha",
    })

    def mock_run(cmd, *args, **kwargs):
        if "images" in cmd:
            return subprocess.CompletedProcess(cmd, 0, stdout=mock_json_dict, stderr="")
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", mock_run)
    image = client.get_current_image(compose_file, "altr-stream")
    assert image == "ghcr.io/helloaltr/altr-stream:0.13.3-alpha"


def test_host_docker_client_get_current_image_fallback_to_inspect(monkeypatch, compose_file: Path):
    from altr_stream.supervisor.supervisor import HostDockerClient
    import subprocess

    client = HostDockerClient()

    def mock_run(cmd, *args, **kwargs):
        if "images" in cmd:
            # compose images fails
            return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="error")
        if "inspect" in cmd:
            return subprocess.CompletedProcess(cmd, 0, stdout="ghcr.io/helloaltr/altr-stream:0.13.4-alpha\n", stderr="")
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", mock_run)
    image = client.get_current_image(compose_file, "altr-stream")
    assert image == "ghcr.io/helloaltr/altr-stream:0.13.4-alpha"


def test_host_docker_client_environment_and_binary_discovery():
    from altr_stream.supervisor.supervisor import HostDockerClient
    client = HostDockerClient(docker_bin="/custom/bin/docker")
    assert client.docker_bin == "/custom/bin/docker"
    env = client._get_env()
    assert "PATH" in env
    assert "/usr/bin" in env["PATH"]


def test_status_daemon_pgrep_fallback(tmp_path: Path, monkeypatch):
    from altr_stream.supervisor.supervisor import status_daemon
    import subprocess

    def mock_run(cmd, *args, **kwargs):
        if "pgrep" in cmd:
            return subprocess.CompletedProcess(cmd, 0, stdout="99999\n", stderr="")
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", mock_run)
    exit_code = status_daemon(tmp_path)
    assert exit_code == 0


def test_supervisor_simulation_override_not_superseded(updates_dir: Path, compose_file: Path):
    """When the live node simulates an older version (0.13.2-alpha), an update to 0.13.3-alpha must NOT be superseded."""
    docker_client = MockDockerClient(current_image="ghcr.io/helloaltr/altr-stream:0.13.4-alpha")
    # Live node health returns 0.13.2-alpha (simulated)
    health_checker = MockHealthChecker(healthy=True, live_version="0.13.2-alpha")

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
        "request_id": "test-simulation-update",
        "current_version": "0.13.2-alpha",
        "target_version": "0.13.3-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.3-alpha",
        "created_at": "2026-09-24T00:00:00Z",
    }
    req_file.write_text(json.dumps(req_data))

    result = supervisor.process_pending_request()

    assert result is not None
    assert result["state"] == "completed"
    assert result["target_version"] == "0.13.3-alpha"
    assert docker_client.pull_calls == ["ghcr.io/helloaltr/altr-stream:0.13.3-alpha"]
    assert len(docker_client.recreate_calls) == 1
    assert docker_client.recreate_calls[0] == ("altr-stream", "ghcr.io/helloaltr/altr-stream:0.13.3-alpha")


def test_supervisor_downgrade_request_rejected_as_failed(updates_dir: Path, compose_file: Path):
    """If a request attempts to downgrade to an older version, supervisor must mark it FAILED, never silent idle."""
    docker_client = MockDockerClient(current_image="ghcr.io/helloaltr/altr-stream:0.13.4-alpha")
    health_checker = MockHealthChecker(healthy=True, live_version="0.13.4-alpha")

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        service_name="altr-stream",
        docker_client=docker_client,
        health_checker=health_checker,
    )

    req_file = updates_dir / "update-request.json"
    req_data = {
        "request_id": "test-downgrade",
        "current_version": "0.13.4-alpha",
        "target_version": "0.13.3-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.3-alpha",
    }
    req_file.write_text(json.dumps(req_data))

    result = supervisor.process_pending_request()

    assert result is not None
    assert result["state"] == "failed"
    assert "older than running" in result["error"]
    assert result["progress_percent"] == 0


def test_recreate_service_clears_simulation_environment(compose_file: Path, monkeypatch):
    """Verify that recreate_service removes ALTR_STREAM_APP_VERSION and ALTR_STREAM_SIMULATED_VERSION rather than injecting empty strings."""
    from altr_stream.supervisor.supervisor import HostDockerClient
    import subprocess

    client = HostDockerClient()
    captured_envs = []

    def mock_run(cmd, env=None, *args, **kwargs):
        captured_envs.append(env)
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", mock_run)
    # Pre-populate env with simulation variables
    monkeypatch.setenv("ALTR_STREAM_APP_VERSION", "0.13.2-alpha")
    monkeypatch.setenv("ALTR_STREAM_SIMULATED_VERSION", "0.13.2-alpha")

    client.recreate_service(compose_file, "altr-stream", "ghcr.io/helloaltr/altr-stream:0.13.3-alpha")

    assert len(captured_envs) == 1
    env = captured_envs[0]
    assert env["ALTR_STREAM_IMAGE"] == "ghcr.io/helloaltr/altr-stream:0.13.3-alpha"
    # Empty strings MUST NOT be passed to avoid crashing older versions like 0.13.3-alpha
    assert "ALTR_STREAM_APP_VERSION" not in env
    assert "ALTR_STREAM_SIMULATED_VERSION" not in env


def test_supervisor_rollback_success_when_live_version_restored(updates_dir: Path, compose_file: Path):
    """When rollback successfully restores the expected previous version, state is rolled_back."""
    docker_client = MockDockerClient(current_image="ghcr.io/helloaltr/altr-stream:0.13.2-alpha")
    # Healthcheck sequence: 1st (0.13.3) fails, 2nd (rollback to 0.13.2) succeeds
    health_checker = MockHealthChecker(
        health_sequence=[False, True],
        live_version="0.13.2-alpha",
    )

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        service_name="altr-stream",
        docker_client=docker_client,
        health_checker=health_checker,
    )

    req_file = updates_dir / "update-request.json"
    req_data = {
        "request_id": "test-rollback-ok",
        "current_version": "0.13.2-alpha",
        "target_version": "0.13.3-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.3-alpha",
    }
    req_file.write_text(json.dumps(req_data))

    result = supervisor.process_pending_request()

    assert result is not None
    assert result["state"] == "rolled_back"
    assert result["current_version"] == "0.13.2-alpha"
    assert result["rollback_performed"] is True
    assert "Rolled back to previous version 0.13.2-alpha" in result["message"]


def test_supervisor_rollback_mismatch_becomes_failed(updates_dir: Path, compose_file: Path):
    """When rollback fails to restore the expected previous version, final state MUST be failed (never rolled_back)."""
    docker_client = MockDockerClient(current_image="ghcr.io/helloaltr/altr-stream:0.13.2-alpha")
    # Healthcheck sequence: 1st (0.13.3) fails, 2nd (rollback) returns False because live node is 0.13.4
    health_checker = MockHealthChecker(
        health_sequence=[False, False],
        live_version_sequence=["0.13.2-alpha", "0.13.4-alpha"],
    )

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        service_name="altr-stream",
        docker_client=docker_client,
        health_checker=health_checker,
    )

    req_file = updates_dir / "update-request.json"
    req_data = {
        "request_id": "test-rollback-mismatch",
        "current_version": "0.13.2-alpha",
        "target_version": "0.13.3-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.3-alpha",
    }
    req_file.write_text(json.dumps(req_data))

    result = supervisor.process_pending_request()

    assert result is not None
    # Crucial: Must be marked failed, NOT rolled_back!
    assert result["state"] == "failed"
    # Crucial: current_version must reflect actual running version (0.13.4-alpha), NOT 0.13.2-alpha!
    assert result["current_version"] == "0.13.4-alpha"
    assert "Rollback verification failed" in result["error"]
    assert "expected 0.13.2-alpha" in result["error"]


def test_supervisor_pull_fails_when_local_disabled(updates_dir: Path, compose_file: Path):
    """When docker pull fails and allow_local_images is False, update fails immediately."""
    docker_client = MockDockerClient(current_image="ghcr.io/helloaltr/altr-stream:0.13.3-alpha")
    docker_client.fail_pull = True
    health_checker = MockHealthChecker(healthy=True)

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        docker_client=docker_client,
        health_checker=health_checker,
        allow_local_images=False,
    )

    req_file = updates_dir / "update-request.json"
    req_file.write_text(json.dumps({
        "request_id": "test-pull-fail",
        "current_version": "0.13.3-alpha",
        "target_version": "0.13.4-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.4-alpha",
    }))

    result = supervisor.process_pending_request()
    assert result is not None
    assert result["state"] == "failed"
    assert result["message"] == "Failed to pull image."
    assert "Connection timed out" in result["error"]


def test_supervisor_pull_fallback_to_local_when_enabled(updates_dir: Path, compose_file: Path):
    """When remote pull fails but allow_local_images=True and image exists locally, update proceeds to completion."""
    target_img = "ghcr.io/helloaltr/altr-stream:0.13.4-alpha"
    docker_client = MockDockerClient(
        current_image="ghcr.io/helloaltr/altr-stream:0.13.3-alpha",
        local_images={target_img: True},
    )
    docker_client.fail_pull = True
    health_checker = MockHealthChecker(
        healthy=True,
        live_version_sequence=["0.13.3-alpha", "0.13.4-alpha"],
    )

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        docker_client=docker_client,
        health_checker=health_checker,
        allow_local_images=True,
    )

    req_file = updates_dir / "update-request.json"
    req_file.write_text(json.dumps({
        "request_id": "test-local-fallback",
        "current_version": "0.13.3-alpha",
        "target_version": "0.13.4-alpha",
        "target_image": target_img,
    }))

    result = supervisor.process_pending_request()
    assert result is not None
    assert result["state"] == "completed"
    assert result["target_version"] == "0.13.4-alpha"
    assert result["progress_percent"] == 100
    assert "completed successfully" in result["message"]
    # Recreate service should have been called with target_img
    assert len(docker_client.recreate_calls) == 1
    assert docker_client.recreate_calls[0][1] == target_img


def test_supervisor_pull_fails_when_local_enabled_but_image_missing(updates_dir: Path, compose_file: Path):
    """When remote pull fails and allow_local_images=True but image is NOT present locally, update fails."""
    docker_client = MockDockerClient(
        current_image="ghcr.io/helloaltr/altr-stream:0.13.3-alpha",
        local_images={},
    )
    docker_client.fail_pull = True
    health_checker = MockHealthChecker(healthy=True)

    supervisor = AltrSupervisor(
        updates_dir=updates_dir,
        compose_file=compose_file,
        docker_client=docker_client,
        health_checker=health_checker,
        allow_local_images=True,
    )

    req_file = updates_dir / "update-request.json"
    req_file.write_text(json.dumps({
        "request_id": "test-missing-local",
        "current_version": "0.13.3-alpha",
        "target_version": "0.13.4-alpha",
        "target_image": "ghcr.io/helloaltr/altr-stream:0.13.4-alpha",
    }))

    result = supervisor.process_pending_request()
    assert result is not None
    assert result["state"] == "failed"
    assert result["message"] == "Failed to pull image."



