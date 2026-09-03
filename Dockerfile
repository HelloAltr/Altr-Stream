FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Copy dependency configuration
COPY pyproject.toml .
COPY README.md .
COPY src/ src/

# Install application and dependencies
RUN uv pip install --system -e .

# Create directory for SQLite storage
RUN mkdir -p /app/data

ENV PYTHONUNBUFFERED=1
ENV ALTR_STREAM_HOST=0.0.0.0
ENV ALTR_STREAM_PORT=8000
ENV ALTR_STREAM_DATABASE_URL=sqlite+aiosqlite:///app/data/altr_stream.db

EXPOSE 8000

CMD ["uvicorn", "altr_stream.main:app", "--host", "0.0.0.0", "--port", "8000"]
