# Stage 1: Build Flutter Web application
FROM plugfox/flutter:3.47.2-web AS frontend-build

WORKDIR /app/frontend

ARG ALTR_APP_VERSION=0.13.5-alpha

# Copy pubspec first for layer caching
COPY frontend/altr_stream_admin/pubspec.yaml frontend/altr_stream_admin/pubspec.lock* ./
RUN flutter pub get

# Copy frontend source code and compile web release bundle with canonical version injected
COPY frontend/altr_stream_admin/ .
RUN flutter build web --release --no-tree-shake-icons --dart-define=ALTR_APP_VERSION=${ALTR_APP_VERSION}

# Apply cache busting to bootstrap, main entrypoint, and font manifests
RUN BUILD_ID=$(date +%s)-$(md5sum build/web/main.dart.js | cut -c 1-8) && \
    echo "Applying Cache Busting Build ID: ${BUILD_ID}" && \
    sed -i "s/flutter_bootstrap\.js/flutter_bootstrap\.js?v=${BUILD_ID}/g" build/web/index.html && \
    sed -i "s/\"main\.dart\.js\"/\"main\.dart\.js?v=${BUILD_ID}\"/g" build/web/flutter_bootstrap.js && \
    if [ -f build/web/assets/FontManifest.json ]; then \
        sed -i "s/MaterialIcons-Regular\.otf/MaterialIcons-Regular\.otf?v=${BUILD_ID}/g" build/web/assets/FontManifest.json; \
    fi

# Stage 2: Unified Altr Stream Node Runtime
FROM python:3.12-slim AS runtime

WORKDIR /app

# Install minimal system runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Create unprivileged user and group: altr (UID/GID 10001)
RUN groupadd -g 10001 altr && \
    useradd -u 10001 -g altr -s /bin/bash -m altr

# Copy dependency configuration and source
COPY pyproject.toml README.md ./
COPY src/ src/

# Install application and dependencies system-wide
RUN uv pip install --system -e .

# Copy compiled Flutter Web SPA assets to /app/static
COPY --from=frontend-build /app/frontend/build/web /app/static

# Create persistent storage directory for SQLite metadata and state
RUN mkdir -p /app/data && chown -R altr:altr /app/data /app/static

# Environment configuration
ENV PYTHONUNBUFFERED=1 \
    ALTR_STREAM_HOST=0.0.0.0 \
    ALTR_STREAM_PORT=8000 \
    ALTR_STREAM_DATABASE_URL=sqlite+aiosqlite:////app/data/altr_stream.db \
    ALTR_STREAM_STATIC_DIR=/app/static

# Switch to unprivileged user
USER altr

# Healthcheck testing the real Altr Stream health API
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/api/v1/health || exit 1

EXPOSE 8000

CMD ["uvicorn", "altr_stream.main:app", "--host", "0.0.0.0", "--port", "8000"]
