#!/bin/bash
# DevContainer post-create setup
# Runs once after container is created

set -euo pipefail

WORKSPACE="/home/vscode/workspace"
HOOKS_DIR="$WORKSPACE/.githooks"
VENV="$WORKSPACE/.venv"

echo "=== BladeAI DevContainer post-create ==="

# 1. Install Python packages from all repos' requirements.txt
if [ -f "$VENV/bin/pip" ]; then
    for req in "$WORKSPACE"/*/requirements.txt; do
        [ -f "$req" ] || continue
        repo=$(basename "$(dirname "$req")")
        echo "Installing packages from $repo..."
        "$VENV/bin/pip" install -q -r "$req" 2>/dev/null || echo "  Warning: some packages from $repo failed"
    done
    echo "Total packages: $("$VENV/bin/pip" list 2>/dev/null | wc -l)"
fi

# 2. Set up pre-commit hooks for all repos
mkdir -p "$HOOKS_DIR"
if [ -f "$WORKSPACE/dev-env/sync/pre-commit-hook" ]; then
    cp "$WORKSPACE/dev-env/sync/pre-commit-hook" "$HOOKS_DIR/pre-commit"
    chmod +x "$HOOKS_DIR/pre-commit"
fi

for dir in "$WORKSPACE"/*/; do
    [ -d "$dir/.git" ] && git -C "$dir" config core.hooksPath "$HOOKS_DIR"
done

# 3. SSH config for VPS hosts (if not already mounted)
if [ ! -f "$HOME/.ssh/config" ] || ! grep -q 'hk-panel' "$HOME/.ssh/config" 2>/dev/null; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cat >> "$HOME/.ssh/config" << 'SSHCONF'

# === BladeAI VPS ===
Host hk-panel
  HostName 35.220.168.96
  User simba

Host jp-dmit
  HostName 154.12.190.176
  User root

Host sg-proxy
  HostName 45.32.122.209
  User root

Host us-dmit
  HostName 64.186.227.36
  User root

Host us-gateway
  HostName 100.88.122.17
  User simba

Host dev-vm-tokyo
  HostName 100.67.53.22
  User simba

Host mac-mini
  HostName 100.77.47.23
  User ob
SSHCONF
fi

echo "=== DevContainer ready ==="
echo "  Python: $(python3 --version)"
echo "  venv:   $("$VENV/bin/python" --version)"
echo "  git:    $(git --version)"
echo "  gh:     $(gh --version | head -1)"
echo "  node:   $(node --version)"
