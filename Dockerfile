# Module 17 — Production Docker image for the collision-risk backend.
# Build context: backend/ (the git repo root).
#   docker build -t collision-risk-backend .
#   docker run -p 8000:8000 collision-risk-backend

FROM python:3.14-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Runtime system library required by the XGBoost native runtime.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install project dependencies first (layer caching).
COPY requirements.txt ./
RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Application code and runtime configuration.
COPY app/ ./app/
COPY configs/ ./configs/

# Model artifacts (optional): add trained models under models/ before building,
# or mount them into /app/models at runtime. The service loads models lazily at
# startup and degrades gracefully (HTTP 503 on risk endpoints) when absent.
COPY models/ ./models/

# Writable runtime directories: SQLite database and log files.
RUN mkdir -p data logs \
    && useradd --create-home --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app

# Run as a non-root user (defense in depth; no secrets in the image).
USER appuser

EXPOSE 8000

# Health check against the /health endpoint.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request, sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status == 200 else 1)"

# Production startup command: no reload, host/port/workers from environment
# (matching .env.example APP_HOST / APP_PORT / MAX_WORKERS).
CMD ["sh", "-c", "uvicorn app.main:app --host \"${APP_HOST:-0.0.0.0}\" --port \"${APP_PORT:-8000}\" --workers \"${MAX_WORKERS:-1}\""]