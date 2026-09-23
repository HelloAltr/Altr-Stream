"""Integration test for /api/v1/metrics/usage endpoint."""

import pytest
from fastapi.testclient import TestClient

from altr_stream.application.usage_tracker import usage_tracker
from altr_stream.main import app

client = TestClient(app)


def test_get_node_usage_api():
    usage_tracker.reset()
    usage_tracker.record_read(12)
    usage_tracker.record_write(3)

    response = client.get("/api/v1/metrics/usage")
    assert response.status_code == 200

    data = response.json()
    assert data["total_reads"] == 12
    assert data["total_writes"] == 3
    assert data["read_percentage"] == 80.0
    assert data["write_percentage"] == 20.0
    assert "ops_per_minute" in data
    assert isinstance(data["read_history"], list)
    assert isinstance(data["write_history"], list)
