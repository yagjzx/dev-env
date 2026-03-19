#!/usr/bin/env bash
set -euo pipefail

ROOT="/workspace/clawforce"
DEV_ENV_ROOT="/workspace/dev-env"
ENV_FILE="$ROOT/.env.devcontainer.local"
ENV_LINK="$ROOT/.env"
COMPOSE_BASE="$ROOT/docker-compose.yml"
COMPOSE_OVERRIDE="$DEV_ENV_ROOT/templates/clawforce.compose.override.yml"
RENDER="$DEV_ENV_ROOT/sync/render-clawforce-env.py"
CREATED_ENV_LINK=false
BACKEND_ONLY=false

for arg in "$@"; do
    [ "$arg" = "--backend-only" ] && BACKEND_ONLY=true
done

log() { echo "[clawforce-dev-env] $*"; }

compose() {
    docker compose -f "$COMPOSE_BASE" -f "$COMPOSE_OVERRIDE" "$@"
}

ensure_env_files() {
    if [ ! -f "$ENV_FILE" ]; then
        python3 "$RENDER" \
            --template "$DEV_ENV_ROOT/templates/clawforce.env.devcontainer.local" \
            --output "$ENV_FILE" \
            >/dev/null
        log "Created $ENV_FILE from template"
    fi

    if [ ! -e "$ENV_LINK" ]; then
        ln -s ".env.devcontainer.local" "$ENV_LINK"
        CREATED_ENV_LINK=true
    fi
}

cleanup() {
    log "Shutting down..."
    kill "${BACKEND_PID:-}" 2>/dev/null || true
    kill "${ARQ_PID:-}" 2>/dev/null || true
    kill "${FRONTEND_PID:-}" 2>/dev/null || true
    compose stop postgres redis >/dev/null 2>&1 || true
    if [ "$CREATED_ENV_LINK" = true ]; then
        rm -f "$ENV_LINK"
    fi
    log "Done."
}

trap cleanup EXIT INT TERM

ensure_env_files
cd "$ROOT"

log "Starting postgres and redis..."
compose up -d postgres redis

log "Waiting for postgres..."
until compose exec -T postgres pg_isready -U clawforce -q 2>/dev/null; do
    sleep 1
done
log "Postgres ready."

log "Running alembic migrations..."
APP_ENV_FILE=.env.devcontainer.local uv run alembic upgrade head

log "Starting backend (uvicorn reload on :8000)..."
APP_ENV_FILE=.env.devcontainer.local uv run uvicorn clawforce.main:app --reload --host 0.0.0.0 --port 8000 &
BACKEND_PID=$!
log "Backend PID: $BACKEND_PID"

APP_ENV_FILE=.env.devcontainer.local uv run python -m arq clawforce.jobs.worker.WorkerSettings &
ARQ_PID=$!
log "Arq worker PID: $ARQ_PID"

if [ "$BACKEND_ONLY" = false ] && [ -d "$ROOT/web" ]; then
    log "Starting frontend (vite on :5173)..."
    cd "$ROOT/web"
    if [ ! -d node_modules ]; then
        log "Installing frontend dependencies first..."
        npm install
    fi
    npm run dev -- --host 0.0.0.0 &
    FRONTEND_PID=$!
    log "Frontend PID: $FRONTEND_PID"
    cd "$ROOT"
fi

echo ""
log "=== Development environment started ==="
log "  API:      http://localhost:8000"
log "  Docs:     http://localhost:8000/docs"
[ "$BACKEND_ONLY" = false ] && log "  Frontend: http://localhost:5173"
log ""
log "Press Ctrl+C to stop all processes."
echo ""

wait
