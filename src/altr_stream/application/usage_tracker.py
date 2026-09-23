"""Global real-time actual read and write tracking for the Altr Stream node."""

import asyncio
from datetime import datetime, timedelta, timezone
import logging
import threading
import time

logger = logging.getLogger(__name__)


def _current_minute_key(dt: datetime | None = None) -> str:
    """Format datetime as 1-minute bucket key: YYYY-MM-DD HH:MM:00 (UTC)."""
    if dt is None:
        dt = datetime.now(timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M:00")


class UsageTracker:
    """Thread-safe global usage tracker with 1-minute step sparse logging and window querying."""

    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super().__new__(cls)
                cls._instance._init_tracker()
            return cls._instance

    def _init_tracker(self) -> None:
        self.total_reads: int = 0
        self.total_writes: int = 0
        self.start_time: float = time.time()
        # In-memory sparse minute buckets: { "YYYY-MM-DD HH:MM:00": {"reads": int, "writes": int} }
        self.minute_buckets: dict[str, dict[str, int]] = {}
        # Per-source sparse telemetry tracking
        self.source_totals: dict[str, dict[str, int]] = {}
        self.source_minute_buckets: dict[str, dict[str, dict[str, int]]] = {}
        self._save_scheduled: bool = False

    def _schedule_save(self) -> None:
        """Schedule a background async DB save if an event loop is running."""
        try:
            loop = asyncio.get_running_loop()
            if loop.is_running():
                with self._lock:
                    if self._save_scheduled:
                        return
                    self._save_scheduled = True
                loop.create_task(self._async_save_wrapper())
        except RuntimeError:
            pass

    async def _async_save_wrapper(self) -> None:
        """Wrapper for debounced async DB saving."""
        try:
            await asyncio.sleep(0.5)
            await self.save_to_db()
        finally:
            with self._lock:
                self._save_scheduled = False

    def record_read(self, count: int = 1, source_id: str | None = None) -> None:
        """Record one or more read operations into minute bucket (sparse logging)."""
        if count <= 0:
            return
        minute_key = _current_minute_key()
        with self._lock:
            self.total_reads += count
            bucket = self.minute_buckets.setdefault(minute_key, {"reads": 0, "writes": 0})
            bucket["reads"] += count

            if source_id:
                s_tot = self.source_totals.setdefault(source_id, {"total_reads": 0, "total_writes": 0})
                s_tot["total_reads"] += count
                s_buckets = self.source_minute_buckets.setdefault(source_id, {})
                s_bucket = s_buckets.setdefault(minute_key, {"reads": 0, "writes": 0})
                s_bucket["reads"] += count

        self._schedule_save()

    def record_write(self, count: int = 1, source_id: str | None = None) -> None:
        """Record one or more write operations into minute bucket (sparse logging)."""
        if count <= 0:
            return
        minute_key = _current_minute_key()
        with self._lock:
            self.total_writes += count
            bucket = self.minute_buckets.setdefault(minute_key, {"reads": 0, "writes": 0})
            bucket["writes"] += count

            if source_id:
                s_tot = self.source_totals.setdefault(source_id, {"total_reads": 0, "total_writes": 0})
                s_tot["total_writes"] += count
                s_buckets = self.source_minute_buckets.setdefault(source_id, {})
                s_bucket = s_buckets.setdefault(minute_key, {"reads": 0, "writes": 0})
                s_bucket["writes"] += count

        self._schedule_save()

    async def load_from_db(self, session=None) -> None:
        """Load persisted cumulative totals and active log buckets from database."""
        try:
            from sqlalchemy import select
            from altr_stream.infrastructure.database.models import NodeUsageLogModelDB, NodeUsageModelDB
            from altr_stream.infrastructure.database.session import get_session_factory

            async def _do_load(s):
                # 1. Load cumulative totals (global + per-source)
                result = await s.execute(select(NodeUsageModelDB))
                records = result.scalars().all()
                with self._lock:
                    for rec in records:
                        if rec.id == "global_usage":
                            self.total_reads = rec.total_reads
                            self.total_writes = rec.total_writes
                        else:
                            self.source_totals[rec.id] = {
                                "total_reads": rec.total_reads,
                                "total_writes": rec.total_writes,
                            }

                # 2. Load sparse 1-minute logs from past 7 days
                cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%d %H:%M:00")
                log_result = await s.execute(
                    select(NodeUsageLogModelDB).where(NodeUsageLogModelDB.minute_timestamp >= cutoff)
                )
                logs = log_result.scalars().all()
                with self._lock:
                    for log in logs:
                        if log.source_id == "_global":
                            self.minute_buckets[log.minute_timestamp] = {
                                "reads": log.reads,
                                "writes": log.writes,
                            }
                        else:
                            s_buckets = self.source_minute_buckets.setdefault(log.source_id, {})
                            s_buckets[log.minute_timestamp] = {
                                "reads": log.reads,
                                "writes": log.writes,
                            }
                logger.info("Loaded usage telemetry: total_reads=%d, total_writes=%d, tracked_sources=%d", self.total_reads, self.total_writes, len(self.source_totals))

            if session is not None:
                await _do_load(session)
            else:
                factory = get_session_factory()
                async with factory() as s:
                    await _do_load(s)
        except Exception as err:
            logger.warning("Failed to load node usage from database: %s", err)

    async def save_to_db(self, session=None) -> None:
        """Persist current cumulative totals and active minute buckets to database (sparse logging)."""
        try:
            from sqlalchemy import select
            from altr_stream.infrastructure.database.models import NodeUsageLogModelDB, NodeUsageModelDB
            from altr_stream.infrastructure.database.session import get_session_factory

            with self._lock:
                global_reads = self.total_reads
                global_writes = self.total_writes
                source_tots_copy = {k: dict(v) for k, v in self.source_totals.items()}
                global_buckets_copy = {k: dict(v) for k, v in self.minute_buckets.items() if v["reads"] > 0 or v["writes"] > 0}
                source_buckets_copy = {
                    sid: {k: dict(v) for k, v in b.items() if v["reads"] > 0 or v["writes"] > 0}
                    for sid, b in self.source_minute_buckets.items()
                }

            async def _do_save(s):
                # 1. Save global & per-source cumulative totals
                all_tots = {"global_usage": {"total_reads": global_reads, "total_writes": global_writes}}
                for sid, st in source_tots_copy.items():
                    all_tots[sid] = st

                for record_id, counts in all_tots.items():
                    result = await s.execute(
                        select(NodeUsageModelDB).where(NodeUsageModelDB.id == record_id)
                    )
                    rec = result.scalar_one_or_none()
                    if rec:
                        rec.total_reads = counts["total_reads"]
                        rec.total_writes = counts["total_writes"]
                    else:
                        s.add(NodeUsageModelDB(
                            id=record_id,
                            total_reads=counts["total_reads"],
                            total_writes=counts["total_writes"],
                        ))

                # 2. Save sparse 1-minute log buckets
                all_log_buckets: list[tuple[str, str, dict[str, int]]] = [
                    ("_global", m_key, counts) for m_key, counts in global_buckets_copy.items()
                ]
                for sid, b_dict in source_buckets_copy.items():
                    for m_key, counts in b_dict.items():
                        all_log_buckets.append((sid, m_key, counts))

                for sid, m_key, counts in all_log_buckets:
                    log_res = await s.execute(
                        select(NodeUsageLogModelDB).where(
                            (NodeUsageLogModelDB.source_id == sid) & (NodeUsageLogModelDB.minute_timestamp == m_key)
                        )
                    )
                    log_rec = log_res.scalar_one_or_none()
                    if log_rec:
                        log_rec.reads = counts["reads"]
                        log_rec.writes = counts["writes"]
                    else:
                        s.add(NodeUsageLogModelDB(
                            source_id=sid,
                            minute_timestamp=m_key,
                            reads=counts["reads"],
                            writes=counts["writes"],
                        ))

                await s.commit()

            if session is not None:
                await _do_save(session)
            else:
                factory = get_session_factory()
                async with factory() as s:
                    await _do_save(s)
        except Exception as err:
            logger.warning("Failed to save node usage to database: %s", err)

    async def clear_data(self, session=None) -> None:
        """Clear all monitored telemetry metrics from memory and SQLite database."""
        try:
            from sqlalchemy import delete
            from altr_stream.infrastructure.database.models import NodeUsageLogModelDB, NodeUsageModelDB
            from altr_stream.infrastructure.database.session import get_session_factory

            async def _do_clear(s):
                await s.execute(delete(NodeUsageModelDB))
                await s.execute(delete(NodeUsageLogModelDB))
                await s.commit()

            if session is not None:
                await _do_clear(session)
            else:
                factory = get_session_factory()
                async with factory() as s:
                    await _do_clear(s)
        except Exception as err:
            logger.warning("Failed to clear node usage database tables: %s", err)
        finally:
            with self._lock:
                self.total_reads = 0
                self.total_writes = 0
                self.start_time = time.time()
                self.minute_buckets.clear()
                self.source_totals.clear()
                self.source_minute_buckets.clear()
                self._save_scheduled = False
            logger.info("Cleared all node usage monitoring data.")

    async def get_metrics(self, window: str = "30m", source_id: str | None = None, session=None) -> dict:
        """Get summarized usage metrics, time-series data, X-axis timestamps, and Y-axis scale."""
        now_utc = datetime.now(timezone.utc)
        normalized_window = window.lower().strip() if window else "30m"

        # Determine time window parameters
        if normalized_window == "1h":
            duration = timedelta(hours=1)
            num_steps = 60
            step_delta = timedelta(minutes=1)
            time_fmt = "%H:%M"
        elif normalized_window == "1d":
            duration = timedelta(days=1)
            num_steps = 24
            step_delta = timedelta(hours=1)
            time_fmt = "%H:00"
        elif normalized_window == "1w":
            duration = timedelta(days=7)
            num_steps = 7
            step_delta = timedelta(days=1)
            time_fmt = "%b %d"
        else:  # default "30m"
            normalized_window = "30m"
            duration = timedelta(minutes=30)
            num_steps = 30
            step_delta = timedelta(minutes=1)
            time_fmt = "%H:%M"

        # Generate step timestamps ending at current minute
        end_step = now_utc.replace(second=0, microsecond=0)
        start_step = end_step - (step_delta * (num_steps - 1))

        timestamps: list[str] = []
        raw_reads: list[int] = []
        raw_writes: list[int] = []

        with self._lock:
            if source_id:
                s_tot = self.source_totals.get(source_id, {})
                tot_r = s_tot.get("total_reads", 0)
                tot_w = s_tot.get("total_writes", 0)
                active_buckets = self.source_minute_buckets.get(source_id, {})
            else:
                tot_r = self.total_reads
                tot_w = self.total_writes
                active_buckets = self.minute_buckets

            total_ops = tot_r + tot_w
            if total_ops > 0:
                read_pct = round((tot_r / total_ops) * 100.0, 1)
                write_pct = round((tot_w / total_ops) * 100.0, 1)
            else:
                read_pct = 0.0
                write_pct = 0.0

            elapsed_mins = max((time.time() - self.start_time) / 60.0, 0.1)
            ops_per_min = round(total_ops / elapsed_mins, 1)

            # Build step series (sparse lookup: missing entries default to 0)
            for i in range(num_steps):
                step_dt = start_step + (step_delta * i)
                timestamps.append(step_dt.strftime(time_fmt))

                if normalized_window in ("30m", "1h"):
                    key = step_dt.strftime("%Y-%m-%d %H:%M:00")
                    bucket = active_buckets.get(key, {"reads": 0, "writes": 0})
                    r_val = bucket["reads"]
                    w_val = bucket["writes"]
                elif normalized_window == "1d":
                    # Aggregate 60 minutes for this hour
                    r_val = 0
                    w_val = 0
                    for m in range(60):
                        m_dt = step_dt + timedelta(minutes=m)
                        key = m_dt.strftime("%Y-%m-%d %H:%M:00")
                        bucket = active_buckets.get(key)
                        if bucket:
                            r_val += bucket["reads"]
                            w_val += bucket["writes"]
                else:  # "1w"
                    # Aggregate 1440 minutes for this day
                    r_val = 0
                    w_val = 0
                    for m in range(1440):
                        m_dt = step_dt + timedelta(minutes=m)
                        key = m_dt.strftime("%Y-%m-%d %H:%M:00")
                        bucket = active_buckets.get(key)
                        if bucket:
                            r_val += bucket["reads"]
                            w_val += bucket["writes"]

                raw_reads.append(r_val)
                raw_writes.append(w_val)

        # Calculate Y-axis max scale
        max_ops = max(max(raw_reads, default=0), max(raw_writes, default=0))
        y_max = max(max_ops, 10)  # Minimum scale of 10 for clean visual Y-axis ticks

        # Normalize 0.0 to 1.0 for UI painter (both 0-values resting at exact 0.0 origin baseline)
        read_history = [
            round(r / float(y_max), 3) if r > 0 else 0.0
            for r in raw_reads
        ]
        write_history = [
            round(w / float(y_max), 3) if w > 0 else 0.0
            for w in raw_writes
        ]

        return {
            "total_reads": tot_r,
            "total_writes": tot_w,
            "ops_per_minute": ops_per_min,
            "read_percentage": read_pct,
            "write_percentage": write_pct,
            "time_window": normalized_window,
            "timestamps": timestamps,
            "raw_reads": raw_reads,
            "raw_writes": raw_writes,
            "read_history": read_history,
            "write_history": write_history,
            "y_max": y_max,
        }

    def reset(self) -> None:
        """Reset metrics (useful for testing)."""
        with self._lock:
            self.total_reads = 0
            self.total_writes = 0
            self.start_time = time.time()
            self.minute_buckets.clear()
            self.source_totals.clear()
            self.source_minute_buckets.clear()
            self._save_scheduled = False


# Singleton instance accessor
usage_tracker = UsageTracker()


