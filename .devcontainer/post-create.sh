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

# 1. Create/repair workspace venv with system-site-packages
# The venv must point to the current pyenv Python (/opt/pyenv/...).
# After a Dockerfile rebuild that moves pyenv, the named volume venv
# may still reference the old path — detect and recreate if needed.
EXPECTED_HOME="$(python3 -c 'import sys, os; print(os.path.dirname(sys.executable))')"
CURRENT_HOME="$(grep '^home' "$VENV/pyvenv.cfg" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true)"

if [ ! -e "$VENV/bin/python" ] || [ "$CURRENT_HOME" != "$EXPECTED_HOME" ]; then
    echo "Creating workspace .venv (home=$EXPECTED_HOME)..."
    rm -rf "$VENV"/* "$VENV"/.* 2>/dev/null || true
    python3 -m venv --system-site-packages "$VENV"
elif ! grep -q "include-system-site-packages = true" "$VENV/pyvenv.cfg" 2>/dev/null; then
    echo "Upgrading .venv to include system-site-packages..."
    python3 -m venv --system-site-packages --upgrade "$VENV"
fi

# 2. Install project-specific requirements into workspace .venv
PROJ_REQS_DIR="$WORKSPACE"
PROJ_REPOS_WITH_REQS=(
    "xai-radar/requirements.txt"
    "ig-recruit-radar/requirements.txt"
    "crypto-backtest/requirements.txt"
    "quant-backtest/requirements.txt"
    "quant-lab/requirements.txt"
    "clawforce/requirements.txt"
    "longxia-market/scripts/requirements.txt"
)
if [ -e "$VENV/bin/pip" ]; then
    echo "Installing project requirements into workspace .venv..."
    for req in "${PROJ_REPOS_WITH_REQS[@]}"; do
        req_path="$PROJ_REQS_DIR/$req"
        if [ -f "$req_path" ]; then
            "$VENV/bin/pip" install --no-cache-dir -r "$req_path" 2>/dev/null \
                && echo "  ✓ $req" \
                || echo "  ✗ $req (some packages failed)"
        else
            echo "  - $req (repo not cloned, skipping)"
        fi
    done
fi

# 3. Install pre-commit hooks for all repos
if [ -f "$PRE_COMMIT_CONFIG" ] && command -v pre-commit >/dev/null 2>&1; then
    for repo in "${REPOS[@]}"; do
        dir="$WORKSPACE/$repo"
        [ -d "$dir/.git" ] || continue
        # Copy shared config if repo doesn't have its own
        if [ ! -f "$dir/.pre-commit-config.yaml" ]; then
            cp "$PRE_COMMIT_CONFIG" "$dir/.pre-commit-config.yaml"
        fi
        # Unset host core.hooksPath (bind-mounted .git/config may carry host paths)
        (cd "$dir" && git config --unset-all core.hooksPath 2>/dev/null; pre-commit install --allow-missing-config) 2>/dev/null || true
    done
    echo "Pre-commit hooks installed for all repos"
fi

# 4. SSH config: use host-mounted config, don't overwrite
if [ -f "$HOME/.ssh/config" ]; then
    echo "SSH config: using host-mounted config (read-only)"
else
    echo "SSH config: not found (mount ~/.ssh/config from host)"
fi

# 5. Git config: import user identity from host, set up credential helper
# Host gitconfig is mounted at ~/.gitconfig-host (read-only) to avoid
# inheriting core.hooksPath which conflicts with pre-commit install
HOST_GITCONFIG="$HOME/.gitconfig-host"
if [ -f "$HOST_GITCONFIG" ]; then
    user_name=$(git config -f "$HOST_GITCONFIG" user.name 2>/dev/null || true)
    user_email=$(git config -f "$HOST_GITCONFIG" user.email 2>/dev/null || true)
    [ -n "$user_name" ] && git config --global user.name "$user_name"
    [ -n "$user_email" ] && git config --global user.email "$user_email"
fi
if command -v gh >/dev/null 2>&1; then
    gh auth setup-git 2>/dev/null || true
fi

# 6. Shell history directory (may need root — skip if permission denied)
if [ -w /commandhistory ] || mkdir -p /commandhistory 2>/dev/null; then
    touch /commandhistory/.bash_history 2>/dev/null || true
fi

# 7. Environment summary
echo ""
echo "=== DevContainer ready ==="
echo "  Python:     $(python3 --version)"
echo "  Node:       $(node --version)"
echo "  Go:         $(go version 2>/dev/null | cut -d' ' -f3 || echo 'N/A')"
echo "  gh:         $(gh --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  gcloud:     $(gcloud --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  uv:         $(uv --version 2>/dev/null || echo 'N/A')"
echo "  gitleaks:   $(gitleaks version 2>/dev/null || echo 'N/A')"
echo "  claude:     $(claude --version 2>/dev/null || echo 'N/A')"
echo "  pre-commit: $(pre-commit --version 2>/dev/null || echo 'N/A')"
echo "  pm2:        $(pm2 --version 2>/dev/null || echo 'N/A')"
echo "  Playwright: $(python3 -m playwright --version 2>/dev/null || echo 'N/A')"
echo "  Workspace:  $WORKSPACE"
echo "  Repos:      ${#REPOS[@]}"
echo ""
