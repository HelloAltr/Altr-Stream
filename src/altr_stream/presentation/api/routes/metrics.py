from fastapi import APIRouter, Query, status

from altr_stream.application.usage_tracker import usage_tracker
from altr_stream.presentation.api.dtos import NodeUsageResponseDTO

router = APIRouter(prefix="/metrics", tags=["Metrics"])


@router.get("/usage", response_model=NodeUsageResponseDTO, status_code=status.HTTP_200_OK)
async def get_node_usage(
    time_window: str = Query(default="30m", pattern="^(30m|1h|1d|1w)$", description="Monitoring time window"),
    source_id: str | None = Query(default=None, description="Optional Data Source ID to filter metrics"),
) -> NodeUsageResponseDTO:
    """Return real-time global or per-source read and write tracking metrics for the Altr Stream node."""
    metrics = await usage_tracker.get_metrics(window=time_window, source_id=source_id)
    return NodeUsageResponseDTO(
        total_reads=metrics["total_reads"],
        total_writes=metrics["total_writes"],
        ops_per_minute=metrics["ops_per_minute"],
        read_percentage=metrics["read_percentage"],
        write_percentage=metrics["write_percentage"],
        time_window=metrics["time_window"],
        timestamps=metrics["timestamps"],
        raw_reads=metrics["raw_reads"],
        raw_writes=metrics["raw_writes"],
        read_history=metrics["read_history"],
        write_history=metrics["write_history"],
        y_max=metrics["y_max"],
    )


@router.delete("/usage", status_code=status.HTTP_200_OK)
async def clear_node_usage() -> dict:
    """Clear all monitored read and write telemetry logs and cumulative metrics from memory and database."""
    await usage_tracker.clear_data()
    return {"message": "All monitored usage data successfully cleared."}

