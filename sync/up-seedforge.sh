#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/workspace"
ROOT="$WORKSPACE/seedforge"
ENV_FILE="$ROOT/.env.devcontainer.local"
TEMPLATE="$WORKSPACE/dev-env/templates/seedforge.env.devcontainer.local"

if [ ! -f "$ENV_FILE" ]; then
    cp "$TEMPLATE" "$ENV_FILE"
    echo "Created $ENV_FILE from template"
fi

cd "$ROOT"
docker compose up -d seedforge-db seedforge-redis
set -a
source .env.devcontainer.local
set +a
uv run alembic upgrade head

if pm2 describe seedforge-api >/dev/null 2>&1; then
    pm2 restart seedforge-api --update-env
else
    pm2 start "bash -lc 'set -a && source .env.devcontainer.local && set +a && uv run uvicorn seedforge.main:app --host 0.0.0.0 --port 8100'" --name seedforge-api
fi

cd "$ROOT/dashboard-admin"
if pm2 describe seedforge-web >/dev/null 2>&1; then
    pm2 restart seedforge-web --update-env
else
    pm2 start "npm run dev -- --host 0.0.0.0 --port 5174" --name seedforge-web
fi

for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:8100/health >/dev/null 2>&1; then
        curl -fsS http://127.0.0.1:8100/health
        exit 0
    fi
    sleep 1
done

echo "seedforge health check timed out" >&2
exit 1
