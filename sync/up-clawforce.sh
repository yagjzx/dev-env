#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/workspace"
ROOT="$WORKSPACE/clawforce"
ENV_FILE="$ROOT/.env.devcontainer.local"
TEMPLATE="$WORKSPACE/dev-env/templates/clawforce.env.devcontainer.local"
RUNNER="$WORKSPACE/dev-env/sync/run-clawforce-stack.sh"
RENDER="$WORKSPACE/dev-env/sync/render-clawforce-env.py"

if [ ! -f "$ENV_FILE" ]; then
    python3 "$RENDER" --template "$TEMPLATE" --output "$ENV_FILE" >/dev/null
    echo "Created $ENV_FILE from template"
fi

if pm2 describe clawforce-dev >/dev/null 2>&1; then
    pm2 delete clawforce-dev >/dev/null 2>&1 || true
fi
pm2 start "$RUNNER" --name clawforce-dev --interpreter bash

for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
        curl -fsS http://127.0.0.1:8000/health
        exit 0
    fi
    sleep 1
done

echo "clawforce health check timed out" >&2
exit 1
