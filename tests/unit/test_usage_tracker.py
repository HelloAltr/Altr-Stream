"""Unit tests for UsageTracker global metrics tracking."""

import pytest
from altr_stream.application.usage_tracker import UsageTracker, usage_tracker


def test_usage_tracker_singleton():
    t1 = UsageTracker()
    t2 = UsageTracker()
    assert t1 is t2
    assert t1 is usage_tracker


@pytest.mark.asyncio
async def test_record_reads_and_writes():
    usage_tracker.reset()

    usage_tracker.record_read(5)
    usage_tracker.record_write(2)

    metrics = await usage_tracker.get_metrics()
    assert metrics["total_reads"] == 5
    assert metrics["total_writes"] == 2
    assert metrics["read_percentage"] == 71.4
    assert metrics["write_percentage"] == 28.6
    assert len(metrics["read_history"]) == 30
    assert len(metrics["write_history"]) == 30


@pytest.mark.asyncio
async def test_usage_tracker_reset():
    usage_tracker.record_read(10)
    usage_tracker.reset()

    metrics = await usage_tracker.get_metrics()
    assert metrics["total_reads"] == 0
    assert metrics["total_writes"] == 0
    assert metrics["read_percentage"] == 0.0
    assert metrics["write_percentage"] == 0.0


import pytest
from altr_stream.infrastructure.database.session import init_db


@pytest.mark.asyncio
async def test_usage_tracker_db_persistence(test_session):
    usage_tracker.reset()

    usage_tracker.total_reads = 42
    usage_tracker.total_writes = 17

    await usage_tracker.save_to_db(session=test_session)

    usage_tracker.reset()
    assert usage_tracker.total_reads == 0
    assert usage_tracker.total_writes == 0

    await usage_tracker.load_from_db(session=test_session)
    assert usage_tracker.total_reads == 42
    assert usage_tracker.total_writes == 17


@pytest.mark.asyncio
async def test_per_source_tracking():
    usage_tracker.reset()

    usage_tracker.record_read(10, source_id="src_1")
    usage_tracker.record_write(3, source_id="src_1")
    usage_tracker.record_read(5, source_id="src_2")

    global_m = await usage_tracker.get_metrics()
    assert global_m["total_reads"] == 15
    assert global_m["total_writes"] == 3

    src1_m = await usage_tracker.get_metrics(source_id="src_1")
    assert src1_m["total_reads"] == 10
    assert src1_m["total_writes"] == 3

    src2_m = await usage_tracker.get_metrics(source_id="src_2")
    assert src2_m["total_reads"] == 5
    assert src2_m["total_writes"] == 0

    src3_m = await usage_tracker.get_metrics(source_id="src_3")
    assert src3_m["total_reads"] == 0
    assert src3_m["total_writes"] == 0


@pytest.mark.asyncio
async def test_ops_per_minute_resolves_cleanly_to_zero():
    usage_tracker.reset()

    # When idle with no operations recorded, ops/min must be cleanly 0.0
    metrics = await usage_tracker.get_metrics()
    assert metrics["ops_per_minute"] == 0.0

    # When operations occur, it should accurately reflect the active throughput
    usage_tracker.record_read(3)
    usage_tracker.record_write(1)
    active_metrics = await usage_tracker.get_metrics()
    assert active_metrics["ops_per_minute"] == 4.0

    # When operations age past the 60-second sliding window, it resolves back to 0.0
    import time
    past_time = time.time() - 65.0
    with usage_tracker._lock:
        usage_tracker._recent_ops.clear()
        usage_tracker._recent_ops.append((past_time, 4))
        # Clear current minute bucket so fallback does not match
        usage_tracker.minute_buckets.clear()

    idle_metrics = await usage_tracker.get_metrics()
    assert idle_metrics["ops_per_minute"] == 0.0




