#!/bin/bash
# BladeAI DevContainer post-create setup
# Runs once after container is created (idempotent)

set -euo pipefail

WORKSPACE="/workspace"
VENV="$WORKSPACE/.venv"
PRE_COMMIT_CONFIG="$WORKSPACE/dev-env/.pre-commit-config.yaml"

REPOS=(bladeai dev-env clawforce crypto-backtest quant-backtest quant-lab ntws
    longxia-market ig-recruit-radar xai-radar claude-memory
    ai-expert-monitor whisper-vocab)

echo "=== BladeAI DevContainer post-create ==="

# 1. Create workspace venv (idempotent — only if not already present)
if [ ! -f "$VENV/bin/python" ]; then
    echo "Creating workspace .venv..."
    python3 -m venv "$VENV"
fi

# 2. Install pre-commit hooks for all repos
if [ -f "$PRE_COMMIT_CONFIG" ] && command -v pre-commit >/dev/null 2>&1; then
    for repo in "${REPOS[@]}"; do
        dir="$WORKSPACE/$repo"
        [ -d "$dir/.git" ] || continue
        # Copy shared config if repo doesn't have its own
        if [ ! -f "$dir/.pre-commit-config.yaml" ]; then
            cp "$PRE_COMMIT_CONFIG" "$dir/.pre-commit-config.yaml"
        fi
        (cd "$dir" && pre-commit install --allow-missing-config) 2>/dev/null || true
    done
    echo "Pre-commit hooks installed for all repos"
fi

# 3. SSH config: use host-mounted config, don't overwrite
if [ -f "$HOME/.ssh/config" ]; then
    echo "SSH config: using host-mounted config (read-only)"
else
    echo "SSH config: not found (mount ~/.ssh/config from host)"
fi

# 4. Git credential helper via gh
if command -v gh >/dev/null 2>&1; then
    gh auth setup-git 2>/dev/null || true
fi

# 5. Shell history directory
mkdir -p /commandhistory
touch /commandhistory/.bash_history

# 6. Environment summary
echo ""
echo "=== DevContainer ready ==="
echo "  Python:    $(python3 --version)"
echo "  Node:      $(node --version)"
echo "  gh:        $(gh --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  gcloud:    $(gcloud --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  uv:        $(uv --version 2>/dev/null || echo 'N/A')"
echo "  gitleaks:  $(gitleaks version 2>/dev/null || echo 'N/A')"
echo "  claude:    $(claude --version 2>/dev/null || echo 'N/A')"
echo "  pre-commit: $(pre-commit --version 2>/dev/null || echo 'N/A')"
echo "  Workspace: $WORKSPACE"
echo "  Repos:     ${#REPOS[@]}"
echo ""
