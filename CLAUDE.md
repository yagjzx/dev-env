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
  ├─ bladeai-dev 容器: Python 3.12, Node 22, gh, uv, gitleaks, gcloud, Claude Code, pre-commit, tmux
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

## 新机器部署
前提: gh auth login + 13 repos 已克隆到 ~/workspace/ + ~/.ssh/config 已配置
```bash
bash ~/workspace/dev-env/sync/setup-thin-host.sh
# 部署后一次性操作:
echo "HOST_UID=$(id -u)\nHOST_GID=$(id -g)" > ~/workspace/dev-env/.devcontainer/.env  # uid≠1000 时
docker exec bladeai-dev chown -R vscode:vscode /workspace/.venv /commandhistory
docker exec -u vscode bladeai-dev bash /workspace/dev-env/.devcontainer/post-create.sh
```

## 13 个仓库
bladeai, dev-env, clawforce (heydoraai org), crypto-backtest, quant-backtest, quant-lab, ntws, longxia-market, ig-recruit-radar, xai-radar, claude-memory, ai-expert-monitor, whisper-vocab
