#!/bin/bash
# BladeAI Development Environment Setup v2.0
# One-shot script to configure a new dev machine
#
# Supports: macOS (arm64/x86_64), Ubuntu 22.04/24.04
# Run: bash <(curl -sL https://raw.githubusercontent.com/yagjzx/dev-env/main/sync/setup-dev-machine.sh)
#   or: bash ~/workspace/dev-env/sync/setup-dev-machine.sh
#
# What it does:
#   1. Install core tools (pyenv, Python 3.12.12, uv, gitleaks, gh, node)
#   2. Deploy shell profile (pyenv init in .zprofile/.profile)
#   3. Clone all 13 repos
#   4. Install shared pre-commit hooks
#   5. Install git-sync daemon (launchd on macOS, cron on Linux)
#   6. Create workspace .venv

set -euo pipefail

# === Config ===
PYTHON_VERSION="3.12.12"
GITLEAKS_VERSION="8.30.0"
WORKSPACE="$HOME/workspace"
GITHUB_ORG="yagjzx"
SYNC_DIR="$WORKSPACE/.sync"
HOOKS_DIR="$WORKSPACE/.githooks"

REPOS=(
    bladeai dev-env clawforce crypto-backtest quant-backtest quant-lab ntws
    longxia-market ig-recruit-radar xai-radar claude-memory
    ai-expert-monitor whisper-vocab
)
# clawforce is under heydoraai org
CLAWFORCE_ORG="heydoraai"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${GREEN}===${NC} $1 ${GREEN}===${NC}"; }

OS="$(uname -s)"
ARCH="$(uname -m)"

# ============================================================
# Step 0: Pre-checks
# ============================================================
step "Pre-checks"

if [[ "$OS" == "Darwin" ]]; then
    info "macOS detected ($ARCH)"
    # Ensure Homebrew
    if ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ "$ARCH" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    info "Homebrew: $(brew --version | head -1)"
elif [[ "$OS" == "Linux" ]]; then
    info "Linux detected ($ARCH)"
    sudo apt-get update -qq
else
    error "Unsupported OS: $OS"; exit 1
fi

# ============================================================
# Step 1: Install core tools
# ============================================================
step "Installing core tools"

# --- pyenv ---
if ! command -v pyenv >/dev/null 2>&1; then
    if [[ "$OS" == "Darwin" ]]; then
        brew install pyenv
    else
        curl -sS https://pyenv.run | bash
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
    fi
fi
eval "$(pyenv init -)" 2>/dev/null || true
info "pyenv: $(pyenv --version)"

# --- Python ---
if ! pyenv versions --bare | grep -q "^${PYTHON_VERSION}$"; then
    warn "Installing Python $PYTHON_VERSION (this takes a few minutes)..."
    if [[ "$OS" == "Linux" ]]; then
        sudo apt-get install -y build-essential libssl-dev zlib1g-dev \
            libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev \
            xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
            > /dev/null 2>&1
    fi
    pyenv install "$PYTHON_VERSION"
fi
pyenv global "$PYTHON_VERSION"
info "Python: $(python3 --version)"

# --- gh CLI ---
if ! command -v gh >/dev/null 2>&1; then
    if [[ "$OS" == "Darwin" ]]; then
        brew install gh
    else
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update -qq && sudo apt-get install -y gh > /dev/null 2>&1
    fi
fi
info "gh: $(gh --version | head -1)"

# --- uv ---
if ! command -v uv >/dev/null 2>&1; then
    if [[ "$OS" == "Darwin" ]]; then
        brew install uv
    else
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
fi
info "uv: $(uv --version 2>/dev/null || echo 'installed')"

# --- gitleaks ---
if ! command -v gitleaks >/dev/null 2>&1; then
    if [[ "$OS" == "Darwin" ]]; then
        brew install gitleaks
    else
        if [[ "$ARCH" == "x86_64" ]]; then
            GL_ARCH="x64"
        else
            GL_ARCH="arm64"
        fi
        curl -sL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \
            | tar xz -C "$HOME/.local/bin" gitleaks
        chmod +x "$HOME/.local/bin/gitleaks"
    fi
fi
info "gitleaks: $(gitleaks version 2>/dev/null || echo 'installed')"

# --- Node.js ---
if ! command -v node >/dev/null 2>&1; then
    if [[ "$OS" == "Darwin" ]]; then
        brew install node
    else
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - > /dev/null 2>&1
        sudo apt-get install -y nodejs > /dev/null 2>&1
    fi
fi
info "Node: $(node --version)"

# ============================================================
# Step 2: Shell profile
# ============================================================
step "Configuring shell profile"

if [[ "$OS" == "Darwin" ]]; then
    PROFILE_FILE="$HOME/.zprofile"
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    TEMPLATE="$SCRIPT_DIR/zprofile-template-macos"

    if [[ -f "$TEMPLATE" ]]; then
        # Backup and deploy template (preserve any user additions)
        if [[ -f "$PROFILE_FILE" ]]; then
            cp "$PROFILE_FILE" "${PROFILE_FILE}.bak"
        fi
        # Check if pyenv init already exists
        if ! grep -q 'pyenv init' "$PROFILE_FILE" 2>/dev/null; then
            cat >> "$PROFILE_FILE" << 'PYENV_BLOCK'

# pyenv init (added by BladeAI setup)
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"
PYENV_BLOCK
            info "Added pyenv init to $PROFILE_FILE"
        else
            info "pyenv init already in $PROFILE_FILE"
        fi
    fi
else
    PROFILE_FILE="$HOME/.profile"
    if ! grep -q 'pyenv init' "$PROFILE_FILE" 2>/dev/null; then
        cat >> "$PROFILE_FILE" << 'PYENV_BLOCK'

# pyenv init (added by BladeAI setup)
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"
PYENV_BLOCK
        info "Added pyenv init to $PROFILE_FILE"
    else
        info "pyenv init already in $PROFILE_FILE"
    fi
fi

# ============================================================
# Step 3: Clone repos
# ============================================================
step "Cloning repositories"
mkdir -p "$WORKSPACE"

if ! gh auth status >/dev/null 2>&1; then
    warn "gh not authenticated. Falling back to SSH URLs."
    USE_SSH=true
else
    USE_SSH=false
fi

for repo in "${REPOS[@]}"; do
    dir="$WORKSPACE/$repo"
    if [[ "$repo" == "clawforce" ]]; then
        org="$CLAWFORCE_ORG"
    else
        org="$GITHUB_ORG"
    fi

    if [[ -d "$dir/.git" ]]; then
        info "$repo: already exists"
    else
        if $USE_SSH; then
            git clone "git@github.com:${org}/${repo}.git" "$dir" 2>/dev/null && info "$repo: cloned (SSH)" || warn "$repo: clone failed"
        else
            gh repo clone "${org}/${repo}" "$dir" 2>/dev/null && info "$repo: cloned" || warn "$repo: clone failed"
        fi
    fi
done

# ============================================================
# Step 4: Pre-commit hooks
# ============================================================
step "Installing pre-commit hooks"
mkdir -p "$HOOKS_DIR"

HOOK_SRC="$WORKSPACE/dev-env/sync/pre-commit-hook"
if [[ -f "$HOOK_SRC" ]]; then
    cp "$HOOK_SRC" "$HOOKS_DIR/pre-commit"
    chmod +x "$HOOKS_DIR/pre-commit"
    info "Hook copied from dev-env/sync/pre-commit-hook"
fi

for repo in "${REPOS[@]}"; do
    dir="$WORKSPACE/$repo"
    [[ -d "$dir/.git" ]] && git -C "$dir" config core.hooksPath "$HOOKS_DIR"
done
info "hooksPath set for all ${#REPOS[@]} repos"

# ============================================================
# Step 5: Git-sync daemon
# ============================================================
step "Installing git-sync daemon"
mkdir -p "$SYNC_DIR"

# Copy git-sync.sh from dev-env repo
SYNC_SRC="$WORKSPACE/dev-env/sync/git-sync.sh"
if [[ -f "$SYNC_SRC" ]]; then
    cp "$SYNC_SRC" "$SYNC_DIR/git-sync.sh"
    chmod +x "$SYNC_DIR/git-sync.sh"
    # Fix WORKSPACE path in the script
    sed -i.bak "s|WORKSPACE=.*|WORKSPACE=\"$WORKSPACE\"|" "$SYNC_DIR/git-sync.sh"
    rm -f "$SYNC_DIR/git-sync.sh.bak"
    info "git-sync.sh deployed"
fi

if [[ "$OS" == "Darwin" ]]; then
    # launchd plist
    PLIST_LABEL="com.bladeai.git-sync"
    PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST_FILE" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SYNC_DIR}/git-sync.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${SYNC_DIR}/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${SYNC_DIR}/launchd-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
PLIST
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE"
    info "launchd agent installed (every 5 minutes)"
else
    CRON_LINE="*/5 * * * * $SYNC_DIR/git-sync.sh"
    (crontab -l 2>/dev/null | grep -v "git-sync.sh"; echo "$CRON_LINE") | crontab -
    info "cron job installed (every 5 minutes)"
fi

# ============================================================
# Step 6: Workspace .venv
# ============================================================
step "Creating workspace .venv"

if [[ ! -d "$WORKSPACE/.venv" ]]; then
    python3 -m venv "$WORKSPACE/.venv"
    info "Created .venv with Python $(python3 --version)"
    # Install common packages if requirements exist
    for repo in "${REPOS[@]}"; do
        req="$WORKSPACE/$repo/requirements.txt"
        if [[ -f "$req" ]]; then
            "$WORKSPACE/.venv/bin/pip" install -r "$req" -q 2>/dev/null || warn "Some packages from $repo failed"
        fi
    done
    info "Packages installed: $("$WORKSPACE/.venv/bin/pip" list 2>/dev/null | wc -l | tr -d ' ')"
else
    info ".venv already exists ($(${WORKSPACE}/.venv/bin/python --version))"
fi

# ============================================================
# Done
# ============================================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  BladeAI dev environment ready!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  Machine:      $(hostname -s) ($OS $ARCH)"
echo "  Python:       $(python3 --version)"
echo "  Workspace:    $WORKSPACE"
echo "  Repos:        ${#REPOS[@]} repositories"
echo "  Pre-commit:   Secret scanning enabled"
echo "  Auto-sync:    Every 5 minutes"
echo "  venv:         $WORKSPACE/.venv"
echo ""
echo "  One-liner to run this on a new machine:"
echo "    bash ~/workspace/dev-env/sync/setup-dev-machine.sh"
echo ""
