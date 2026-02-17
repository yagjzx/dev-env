# dev-env — Claude Code 项目指令

## 你是谁、用户是谁
- **你（Claude Code）运行在宿主机上**，通过 `docker exec` 操控容器内的工具
- **用户不会自己进容器**，用户只跟你对话，你负责所有技术操作
- 当你需要 Python/Node/uv/gcloud/pre-commit 等工具时，用 `docker exec -u vscode bladeai-dev <命令>`
- git/ssh 操作可以在宿主机直接执行（宿主机有 gitleaks hook）
- 文件在宿主机 `~/workspace/` = 容器 `/workspace/`（同一份，bind mount）

## 容器操作模板
```bash
# 执行命令（不进入容器，你最常用的方式）
docker exec -u vscode bladeai-dev python3 /workspace/some-repo/script.py
docker exec -u vscode bladeai-dev uv run --directory /workspace/some-repo pytest
docker exec -u vscode bladeai-dev node /workspace/some-repo/index.js
docker exec -u vscode bladeai-dev gcloud compute instances list

# 检查状态
docker ps --filter name=bladeai
docker logs bladeai-git-sync --tail 5
```

## 架构
```
宿主机 (Thin Host): Docker + SSH + ~/workspace/ (13 repos)
  ├─ bladeai-dev 容器: Python 3.12.12, Node 25, Go 1.25.7, Rust 1.93.0, gh, uv, gitleaks, gcloud, Claude Code, pre-commit, tmux, pm2, vim, Playwright+Chromium
  └─ bladeai-git-sync 容器: 每5分钟自动同步 13 repos, Telegram 告警
```

## 项目结构
- `.devcontainer/` — Dockerfile + docker-compose.yml + post-create.sh + entrypoint.sh
- `.devcontainer/.env` — 机器特定 HOST_UID/HOST_GID（不入 git，用 `.env.example` 作模板）
- `.pre-commit-config.yaml` — 共享 pre-commit hooks (gitleaks + check-yaml + detect-private-key)
- `sync/setup-thin-host.sh` — 新机器一键部署脚本
- `sync/git-sync.sh` — 自动同步守护（容器 sidecar + 宿主机 cron 双跑）

## 关键规则
- **宿主机只装 Docker + SSH**，开发工具全在容器内
- **Host gitconfig 挂载到 `.gitconfig-host:ro`**（不是 `.gitconfig`），避免 core.hooksPath 冲突
- **Git hooks 双环境**: 宿主机用 global `core.hooksPath` (简单 gitleaks)，容器用 per-repo `pre-commit install`
- **named volume 首次创建后需 chown**: `docker exec bladeai-dev chown -R vscode:vscode /workspace/.venv /commandhistory`

## Dockerfile 防护规则 (血泪教训!)

### 规则 1: 文件多的工具必须装到系统目录
**错误做法**: `USER vscode` → `RUN curl pyenv.run | bash` → 装到 `~/.pyenv` (5万+文件)
**正确做法**: 装到 `/opt/pyenv` 或 `/usr/local/` (root 拥有, `chmod -R a+rX`)

**原因**: entrypoint 做 UID 重映射 (1000→1001) 后要 `chown -R /home/vscode`。
pyenv (~5万文件) + Rust (~5万文件) 在用户目录时, chown 要 77-120 秒。
更糟的是, read-only bind mounts (.ssh, .gitconfig-host) 会导致 chown 报错中断。

**当前正确位置**:
| 工具 | 位置 | 原因 |
|------|------|------|
| pyenv + Python | `/opt/pyenv` | 文件多, 系统级避免 chown |
| Rust + Cargo | `/usr/local/rustup` + `/usr/local/cargo` | 同上 |
| Go | `/usr/local/go` | 标准做法 |
| Node/npm | `/usr/bin` + `/usr/lib` | NodeSource apt 安装 |
| Playwright 浏览器 | `/home/vscode/.cache/ms-playwright` | 文件少, USER vscode 安装 |

### 规则 2: pip install 跟 pyenv 在同一 USER 下
pyenv 在 `/opt/pyenv` (root) → `pip install` 也要以 root 运行
否则 pip 会 fallback 到 `--user` 装到 `~/.local/`, 不跟 pyenv 一起

### 规则 3: COPY 的文件 vscode 不能删
`COPY requirements.txt /tmp/` 以 root 创建 → `USER vscode` 后 `rm /tmp/requirements.txt` 会失败
解决: 不删, 或在 root 阶段删

### 规则 4: entrypoint chown 必须跳过 read-only mounts
docker-compose 挂载的 `:ro` 文件 (`.ssh/config`, `.gitconfig-host`) 不能 chown
当前 entrypoint 逐目录 chown, 跳过 `.ssh` 和 `.gitconfig-host`

## 首次部署容器 (用户说"把容器跑起来"时执行这个)

**前提条件** (部署前检查，缺哪个报给用户):
- [ ] Docker 已安装且在运行 (`docker info`)
- [ ] `~/workspace/` 目录存在，里面有 13 个 repo (至少有 `dev-env/`)
- [ ] `gh auth status` 已登录 GitHub
- [ ] `~/.ssh/config` 存在 (有 SSH aliases)
- [ ] `~/.gitconfig` 存在 (有 user.name/email)

**部署步骤** (按顺序执行):
```bash
# Step 1: 确保必要文件存在 (Docker bind mount 缺文件会创建空目录导致错误)
touch ~/.ssh/known_hosts 2>/dev/null
mkdir -p ~/.config/gcloud 2>/dev/null

# Step 2: 创建 .env (UID 重映射，macOS 通常是 501, Linux 通常是 1000+)
cd ~/workspace/dev-env/.devcontainer
printf "HOST_UID=%s\nHOST_GID=%s\n" "$(id -u)" "$(id -g)" > .env

# Step 3: Build 镜像 (首次约 10-15 分钟，含下载)
docker compose build dev

# Step 4: 启动两个容器
docker compose up -d

# Step 5: 等 entrypoint UID 重映射完成，然后运行 post-create
sleep 10
docker exec -u vscode bladeai-dev bash /workspace/dev-env/.devcontainer/post-create.sh

# Step 6: 验证
docker exec -u vscode bladeai-dev bash -c '
  echo "Python:  $(python3 --version)"
  echo "Node:    $(node --version)"
  echo "Rust:    $(rustc --version)"
  echo "Go:      $(go version)"
  echo "pm2:     $(pm2 --version 2>/dev/null | tail -1)"
  python3 -c "import pandas, numpy, httpx, pydantic; print(\"Packages: OK\")"
'
```

**验证通过标准**: Python 3.12.12, Node v25.x, Rust 1.93.0, Go 1.25.7, Packages OK

**macOS 注意事项**:
- Docker Desktop 需要在 Settings → Resources 里分配足够内存 (建议 8GB+, 镜像 8.65GB)
- 首次 build 比 Linux 慢 (Docker Desktop 虚拟化开销)
- `SSH_AUTH_SOCK` 如果用 1Password SSH Agent, 路径不同 — 容器内 SSH 功能可能受限, 但 git 用 HTTPS (gh credential helper) 不受影响

## 完整重新部署 (新机器从零开始)
前提: gh auth login + 13 repos 已克隆到 ~/workspace/ + ~/.ssh/config 已配置
```bash
bash ~/workspace/dev-env/sync/setup-thin-host.sh
# 然后按上面"首次部署容器"步骤执行
```

## 13 个仓库
bladeai, dev-env, clawforce (heydoraai org), crypto-backtest, quant-backtest, quant-lab, ntws, longxia-market, ig-recruit-radar, xai-radar, claude-memory, ai-expert-monitor, whisper-vocab
