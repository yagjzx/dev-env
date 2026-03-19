#!/usr/bin/env bash
# BladeAI Thin Host Bootstrap v2.0
# 新 Mac (M5 Max) 一键部署脚本 — 宿主机只装基础设施，开发工具全在容器里
#
# 使用方式:
#   bash <(curl -sL https://raw.githubusercontent.com/yagjzx/dev-env/main/sync/setup-thin-host.sh)
#   或本地执行:
#   bash ~/workspace/dev-env/sync/setup-thin-host.sh

set -euo pipefail

# ─── 颜色 & 工具函数 ────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}━━ $1 ━━${NC}"; }
pause()   { echo -e "\n${YELLOW}[手动操作]${NC} $1"; echo "完成后按 Enter 继续..."; read -r; }

OS="$(uname -s)"
[[ "$OS" != "Darwin" ]] && error "此脚本仅支持 macOS"

WORKSPACE="${HOME}/workspace"
COMPOSE_FILE="$WORKSPACE/dev-env/.devcontainer/docker-compose.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_MANIFEST_LOCAL="$SCRIPT_DIR/../manifests/repos.tsv"
REPO_MANIFEST_URL="https://raw.githubusercontent.com/yagjzx/dev-env/main/manifests/repos.tsv"

# ─── Repo manifest ──────────────────────────────────────────────────────────
manifest_stream() {
  if [[ -f "$REPO_MANIFEST_LOCAL" ]]; then
    cat "$REPO_MANIFEST_LOCAL"
  else
    curl -fsSL "$REPO_MANIFEST_URL"
  fi
}

repo_rows() {
  local tier="${1:-all}"
  if [[ "$tier" == "all" ]]; then
    manifest_stream | awk -F '\t' 'NF >= 3 && $1 !~ /^#/'
  else
    manifest_stream | awk -F '\t' -v tier="$tier" 'NF >= 3 && $1 !~ /^#/ && $1 == tier'
  fi
}

repo_count() {
  repo_rows "$1" | wc -l | tr -d ' '
}

# ─── Phase 0: 欢迎 & 前置说明 ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   BladeAI Thin Host Bootstrap v2.0                  ║${NC}"
echo -e "${BOLD}║   M5 Max MacBook Pro 一键环境部署                    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "宿主机只装: Homebrew · Docker · gh · gcloud · Tailscale"
echo "开发工具全在容器: Python · Node · Go · Rust · Claude Code · Codex · Gemini"
echo ""
echo -e "${YELLOW}预计耗时: 20-35 分钟（主要是 Docker 镜像 build）${NC}"
echo ""
echo "开始前请确认:"
echo "  1. 已安装 1Password，已登录账号"
echo "  2. 1Password → Settings → Developer → SSH Agent 已开启"
echo "  3. id_ed25519 密钥已添加到 1Password (导入你的私钥)"
echo "  4. 网络正常（需下载约 3-5 GB）"
echo ""
echo "按 Enter 开始，Ctrl+C 退出..."
read -r

# ─── Phase 1: 宿主机工具安装 ────────────────────────────────────────────────
step "Phase 1: 宿主机工具"

# 1.1 Homebrew
if command -v brew &>/dev/null; then
  info "Homebrew: $(brew --version | head -1)"
else
  warn "安装 Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon 路径
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  fi
  info "Homebrew 安装完成"
fi

# 1.2 Xcode Command Line Tools (git)
if ! xcode-select -p &>/dev/null; then
  warn "安装 Xcode Command Line Tools (含 git)..."
  xcode-select --install
  pause "等待 Xcode Command Line Tools 安装完成"
fi
info "git: $(git --version)"

# 1.3 Docker Desktop
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  info "Docker: $(docker --version)"
else
  warn "安装 Docker Desktop..."
  brew install --cask docker
  open /Applications/Docker.app
  echo "等待 Docker Desktop 启动（最多 60 秒）..."
  for i in $(seq 1 30); do
    docker info &>/dev/null 2>&1 && break
    sleep 2
  done
  docker info &>/dev/null 2>&1 || error "Docker 未能启动，请手动打开 Docker Desktop 后重新运行"
  info "Docker Desktop 启动完成"
fi

# 1.4 gh CLI
if command -v gh &>/dev/null; then
  info "gh: $(gh --version | head -1)"
else
  warn "安装 gh CLI..."
  brew install gh
  info "gh 安装完成"
fi

# 1.5 gcloud CLI (GCP 基础设施管理，宿主机保留)
if command -v gcloud &>/dev/null; then
  info "gcloud: $(gcloud --version | head -1)"
else
  warn "安装 gcloud CLI..."
  brew install --cask google-cloud-sdk
  # 添加到 PATH
  GCLOUD_PATH="$(brew --prefix)/share/google-cloud-sdk"
  if [[ -f "$GCLOUD_PATH/path.zsh.inc" ]]; then
    echo "source '$GCLOUD_PATH/path.zsh.inc'" >> ~/.zshrc
    source "$GCLOUD_PATH/path.zsh.inc"
  fi
  info "gcloud 安装完成"
fi

# 1.6 Tailscale (系统级网络层)
if command -v tailscale &>/dev/null || [[ -d "/Applications/Tailscale.app" ]]; then
  info "Tailscale: 已安装"
else
  warn "安装 Tailscale..."
  brew install --cask tailscale
  warn "Tailscale 已安装，请手动打开并登录: open /Applications/Tailscale.app"
fi

# ─── Phase 2: 身份 & 凭证配置 ───────────────────────────────────────────────
step "Phase 2: 身份 & 凭证"

# 2.1 gitconfig
if [[ ! -f ~/.gitconfig ]] || ! git config --global user.email &>/dev/null; then
  echo ""
  echo "配置 git 身份（用于 commit 作者信息）:"
  read -rp "  姓名 [Kailei Zhang]: " GIT_NAME
  GIT_NAME="${GIT_NAME:-Kailei Zhang}"
  read -rp "  邮箱 [yagjzx@gmail.com]: " GIT_EMAIL
  GIT_EMAIL="${GIT_EMAIL:-yagjzx@gmail.com}"

  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global credential."https://github.com".helper ""
  git config --global --add credential."https://github.com".helper "!/opt/homebrew/bin/gh auth git-credential"
  git config --global credential."https://gist.github.com".helper ""
  git config --global --add credential."https://gist.github.com".helper "!/opt/homebrew/bin/gh auth git-credential"
  # Commit signing via 1Password SSH Agent
  git config --global gpg.format ssh
  git config --global gpg.ssh.program "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
  git config --global commit.gpgsign true
  info "gitconfig 配置完成（含 commit signing）"
else
  info "gitconfig: $(git config --global user.email)"
fi

# 2.2 SSH config (使用 1Password Agent，不存文件)
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/known_hosts

if [[ ! -f ~/.ssh/config ]]; then
  cat > ~/.ssh/config << 'SSHCONFIG'
# === BladeAI 服务器 — 1Password SSH Agent ===
# 所有 SSH 连接通过 1Password agent 认证 (Touch ID)
# 无本地密钥文件。id_ed25519 已存入 1Password。

Host hk-gcp-1
  HostName 34.92.184.237
  User simba

Host hk-gcp-2
  HostName 34.96.242.209
  User simba

Host hk-gcp-2-ts
  HostName 100.105.188.107
  User simba

Host jp-dmit
  HostName 154.31.116.12
  User root

Host jp-dmit-ts
  HostName 100.105.190.124
  User root

Host jp-gcp
  HostName 35.194.109.153
  User simba
  # 注意: jp-gcp 用 GCP 自动生成的 google_compute_engine key
  # 若需要连接，运行: gcloud compute ssh --zone asia-northeast1-b <instance>

Host us-dmit
  HostName 64.186.227.36
  User root

Host us-gcp
  HostName 100.88.122.17
  User simba

Host us-att
  HostName 99.165.198.148
  User root

Host kr-gcp
  HostName 34.50.3.26
  User simba

Host tw-gcp
  HostName 35.221.252.105
  User simba

# === 个人开发机 ===
Host dev-vm-tokyo
  HostName 100.67.53.22
  User simba

Host mac-mini
  HostName 100.77.47.23
  User ob

Host imac
  HostName 192.168.50.159
  User kaileizhang

# === GitHub ===
Host github.com
  # gh CLI 通过 HTTPS + Keychain 处理 git 操作
  # 这里仅用于 git@github.com 格式的 SSH clone

# === 默认: 1Password SSH Agent (Touch ID 认证) ===
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  ServerAliveInterval 60
  ServerAliveCountMax 3
SSHCONFIG
  chmod 600 ~/.ssh/config
  info "~/.ssh/config 已生成（使用 1Password Agent）"
else
  info "~/.ssh/config 已存在，跳过"
fi

# 2.3 验证 1Password SSH Agent
OP_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
if SSH_AUTH_SOCK="$OP_SOCK" ssh-add -l &>/dev/null; then
  KEY_COUNT=$(SSH_AUTH_SOCK="$OP_SOCK" ssh-add -l | wc -l | tr -d ' ')
  info "1Password SSH Agent: $KEY_COUNT 个密钥已加载"
  # 自动设置 commit signing key（取 id_ed25519）
  SIGNING_KEY=$(SSH_AUTH_SOCK="$OP_SOCK" ssh-add -L 2>/dev/null | grep ed25519 | head -1)
  if [[ -n "$SIGNING_KEY" ]]; then
    git config --global user.signingkey "$SIGNING_KEY"
    info "commit signing key 已配置"
  fi
else
  warn "1Password SSH Agent 没有找到密钥"
  pause "请打开 1Password → 确认 SSH Agent 已开启 → 将 id_ed25519 私钥添加到 1Password 保险库"
  SSH_AUTH_SOCK="$OP_SOCK" ssh-add -l &>/dev/null || error "1Password 中没有 SSH 密钥，请先添加再继续"
fi

# 2.4 测试 GitHub SSH 认证
if SSH_AUTH_SOCK="$OP_SOCK" ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  info "GitHub SSH 认证: 通过"
else
  warn "GitHub SSH 认证失败，尝试 gh auth login..."
fi

# 2.5 gh CLI 认证
if gh auth status &>/dev/null 2>&1; then
  info "gh: 已登录 $(gh api user -q .login 2>/dev/null || echo 'GitHub')"
else
  warn "需要登录 GitHub CLI..."
  gh auth login --hostname github.com --git-protocol https --web
  info "gh 登录完成"
fi

# ─── Phase 3: Workspace & Repos ─────────────────────────────────────────────
step "Phase 3: 克隆代码仓库"

mkdir -p "$WORKSPACE"

clone_repo() {
  local repo="$1"  # 格式: org/name
  local name="${2:-$(basename "$repo")}"

  local target="$WORKSPACE/$name"
  if [[ -d "$target/.git" ]]; then
    echo "  ↩ $name (已存在，跳过)"
    return
  fi
  echo -n "  ↓ $repo ... "
  gh repo clone "$repo" "$target" -- --quiet 2>&1 && echo "✓" || echo "⚠ 失败（可能是私有仓库权限）"
}

CORE_COUNT="$(repo_count core)"
FULL_COUNT="$(repo_count full)"
LARGE_COUNT="$(repo_count large)"

echo "正在克隆核心仓库 (${CORE_COUNT} 个)..."
while IFS=$'\t' read -r _tier repo local_dir; do
  clone_repo "$repo" "$local_dir"
done < <(repo_rows core)

echo ""
echo "是否克隆扩展仓库（full tier，共 ${FULL_COUNT} 个）？"
read -rp "  [y/N]: " CLONE_FULL
if [[ "${CLONE_FULL,,}" == "y" ]]; then
  while IFS=$'\t' read -r _tier repo local_dir; do
    clone_repo "$repo" "$local_dir"
  done < <(repo_rows full)
  info "扩展仓库克隆完成"
fi

echo ""
echo "是否克隆大型模型仓库（large tier，共 ${LARGE_COUNT} 个，体积大）？"
read -rp "  [y/N]: " CLONE_LARGE
if [[ "${CLONE_LARGE,,}" == "y" ]]; then
  while IFS=$'\t' read -r _tier repo local_dir; do
    clone_repo "$repo" "$local_dir"
  done < <(repo_rows large)
  info "大型模型仓库克隆完成"
fi

info "Workspace 准备完成: $(ls "$WORKSPACE" | grep -v '^_' | wc -l | tr -d ' ') 个目录"

# ─── Phase 4: 容器部署 ───────────────────────────────────────────────────────
step "Phase 4: 容器部署"

# 4.1 生成 .devcontainer/.env
DEVCONTAINER_DIR="$WORKSPACE/dev-env/.devcontainer"
if [[ ! -f "$DEVCONTAINER_DIR/.env" ]]; then
  GH_TOKEN="$(gh auth token 2>/dev/null || echo '')"
  [[ -z "$GH_TOKEN" ]] && error "无法获取 GH_TOKEN，请确认 gh auth login 已完成"

  printf "HOST_UID=%s\nHOST_GID=%s\nGH_TOKEN=%s\n" \
    "$(id -u)" "$(id -g)" "$GH_TOKEN" \
    > "$DEVCONTAINER_DIR/.env"
  info ".devcontainer/.env 生成完成"
else
  # 更新 GH_TOKEN（token 可能过期）
  GH_TOKEN="$(gh auth token 2>/dev/null || echo '')"
  if [[ -n "$GH_TOKEN" ]]; then
    sed -i '' "s|^GH_TOKEN=.*|GH_TOKEN=$GH_TOKEN|" "$DEVCONTAINER_DIR/.env"
    info ".devcontainer/.env GH_TOKEN 已刷新"
  fi
fi

# 4.2 确保 Docker bind mount 需要的文件存在
touch ~/.ssh/known_hosts
mkdir -p ~/.config/gcloud

# 4.3 Build 镜像
warn "Build Docker 镜像（首次约 15-25 分钟，M5 Max 请在 Docker Desktop Settings → Resources 分配 16GB+ 内存）..."
docker compose -f "$COMPOSE_FILE" build dev
info "镜像 build 完成"

# 4.4 启动容器
# Force recreate so runtime config changes like init/entrypoint updates
# actually reach long-lived dev containers.
docker compose -f "$COMPOSE_FILE" up -d --force-recreate
info "容器启动完成"

# 4.5 等 entrypoint UID 重映射完成
echo "等待容器初始化（约 15 秒）..."
sleep 15

# 确认容器已就绪
until docker exec bladeai-dev echo "ready" &>/dev/null; do
  sleep 2
done

# 4.6 运行 post-create
docker exec bladeai-dev gosu vscode bash /workspace/dev-env/.devcontainer/post-create.sh
info "post-create 完成"

# ─── Phase 5: Dev 快捷命令 ───────────────────────────────────────────────────
step "Phase 5: 快捷命令"

mkdir -p "$HOME/bin"
cat > "$HOME/bin/dev-env" << 'WRAPPER'
#!/bin/bash
exec "$HOME/workspace/dev-env/bin/dev-env" "$@"
WRAPPER
chmod +x "$HOME/bin/dev-env"

cat > "$HOME/bin/dev" << 'WRAPPER'
#!/bin/bash
exec "$HOME/workspace/dev-env/bin/dev-env" shell "$@"
WRAPPER
chmod +x "$HOME/bin/dev"

# 添加 ~/bin 到 PATH
if ! grep -q 'PATH.*HOME/bin' ~/.zshrc 2>/dev/null; then
  echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
fi
export PATH="$HOME/bin:$PATH"
info "快捷命令创建完成: 运行 'dev' 进入容器，'dev-env doctor' 做全环境自检"

# ─── Phase 6: 验证 ───────────────────────────────────────────────────────────
step "Phase 6: 验证"

docker exec bladeai-dev gosu vscode bash -lc '
  echo "  Python:  $(python3 --version 2>/dev/null)"
  echo "  Node:    $(node --version 2>/dev/null)"
  echo "  Go:      $(go version 2>/dev/null | cut -d" " -f3)"
  echo "  Rust:    $(rustc --version 2>/dev/null | cut -d" " -f2)"
  echo "  uv:      $(uv --version 2>/dev/null)"
  echo "  gh:      $(gh --version 2>/dev/null | head -1)"
  echo "  Claude:  $(claude --version 2>/dev/null | head -1)"
  echo "  Codex:   $(codex --version 2>/dev/null | head -1)"
  echo "  Gemini:  $(gemini --version 2>/dev/null | head -1)"
  python3 -c "import pandas, numpy, httpx, pydantic; print(\"  Python packages: OK\")" 2>/dev/null || echo "  Python packages: ⚠ 部分缺失"
' 2>/dev/null

# ─── 完成 ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   部署完成！                                         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "宿主机工具:  Homebrew · Docker · gh · gcloud · Tailscale"
echo "开发容器:    bladeai-dev (Python/Node/Go/Rust/Claude/Codex/Gemini)"
echo "Git 同步:    bladeai-git-sync (每5分钟自动 pull)"
echo ""
echo "常用命令:"
echo "  dev                  — 进入开发容器"
echo "  dev-env doctor       — 检查 Docker / repo manifest / 服务健康"
echo "  dev-env up all       — 启动 clawforce + seedforge"
echo "  dev-env scan         — 生成 workspace 代码清单"
echo "  docker compose -f ~/workspace/dev-env/.devcontainer/docker-compose.yml logs -f"
echo ""
echo "⚠️  请手动完成:"
echo "  1. source ~/.zshrc  (让 PATH 生效)"
echo "  2. 打开 Tailscale → 登录 → 连接网络"
echo "  3. gcloud auth login  (如需 GCP 访问)"
echo "  4. Docker Desktop → Settings → Resources → 建议分配 16GB+ 内存"
echo ""
