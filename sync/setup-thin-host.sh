#!/bin/bash
# BladeAI Thin Host Bootstrap v1.0
# Installs ONLY Docker + creates dev wrapper. All dev tools live in containers.
#
# Run: bash ~/workspace/dev-env/sync/setup-thin-host.sh
#   or: bash <(curl -sL https://raw.githubusercontent.com/yagjzx/dev-env/main/sync/setup-thin-host.sh)

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

OS="$(uname -s)"
WORKSPACE="${HOME}/workspace"
COMPOSE_FILE="$WORKSPACE/dev-env/.devcontainer/docker-compose.yml"

# === Step 1: Docker ===
if command -v docker >/dev/null 2>&1; then
    info "Docker: $(docker --version)"
elif [[ "$OS" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
        warn "Installing Docker Desktop via Homebrew..."
        brew install --cask docker
        open /Applications/Docker.app
        echo "Waiting for Docker to start..."
        while ! docker info >/dev/null 2>&1; do sleep 2; done
        info "Docker Desktop installed and running"
    else
        error "Homebrew not found. Install Docker Desktop manually: https://docker.com/products/docker-desktop"
    fi
elif [[ "$OS" == "Linux" ]]; then
    warn "Installing Docker Engine..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    sudo systemctl enable --now docker
    info "Docker Engine installed (log out and back in for group changes)"
else
    error "Unsupported OS: $OS"
fi

# === Step 2: Docker Compose ===
if docker compose version >/dev/null 2>&1; then
    info "Docker Compose: $(docker compose version --short)"
else
    error "Docker Compose not found. It should be included with Docker Desktop / Engine."
fi

# === Step 3: Clone dev-env (if needed) ===
if [[ ! -d "$WORKSPACE/dev-env/.git" ]]; then
    mkdir -p "$WORKSPACE"
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh repo clone yagjzx/dev-env "$WORKSPACE/dev-env"
    else
        git clone https://github.com/yagjzx/dev-env.git "$WORKSPACE/dev-env"
    fi
    info "dev-env repo cloned"
else
    info "dev-env repo: already exists"
fi

# === Step 4: Start containers ===
if [[ -f "$COMPOSE_FILE" ]]; then
    info "Starting containers..."
    docker compose -f "$COMPOSE_FILE" up -d --build
    info "Containers started"
else
    error "Compose file not found: $COMPOSE_FILE"
fi

# === Step 5: Create 'dev' wrapper ===
mkdir -p "$HOME/bin"
cat > "$HOME/bin/dev" << 'WRAPPER'
#!/bin/bash
# Enter bladeai-dev container as vscode user
# Usage: dev [command]
#   dev          — interactive bash shell
#   dev command  — run command and exit

CONTAINER="bladeai-dev"
USER="vscode"

if ! docker inspect "$CONTAINER" &>/dev/null; then
    echo "Container $CONTAINER not running. Start with:"
    echo "  cd ~/workspace/dev-env/.devcontainer && docker compose up -d"
    exit 1
fi

if [ $# -eq 0 ]; then
    exec docker exec -it -u "$USER" "$CONTAINER" bash
else
    exec docker exec -u "$USER" "$CONTAINER" "$@"
fi
WRAPPER
chmod +x "$HOME/bin/dev"

# Add ~/bin to PATH if not already there
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    SHELL_RC="$HOME/.bashrc"
    [[ "$SHELL" == *zsh ]] && SHELL_RC="$HOME/.zshrc"
    echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
    warn "Added ~/bin to PATH in $SHELL_RC (restart shell to use)"
fi
info "Wrapper created: run 'dev' to enter container"

# === Done ===
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Thin Host ready!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  Host tools: Docker only"
echo "  Dev tools:  All inside container"
echo ""
echo "  Enter dev container:  dev"
echo "  Or:  docker exec -it bladeai-dev bash"
echo ""
