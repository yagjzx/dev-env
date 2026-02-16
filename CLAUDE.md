# dev-env — Claude Code 项目指令

## 项目概览
全容器化开发环境管理仓库。Thin Host + Fat Container 策略：宿主机只有 Docker + SSH，所有开发工具封装在 DevContainer 中。

## 架构
```
HOST (极简): Docker + SSH + ~/workspace/ (13 repos)
CONTAINER dev: Python 3.12.12, Node 22, gh, uv, gitleaks, gcloud, Claude Code, pre-commit
CONTAINER git-sync: Alpine + git, 每 5 分钟自动同步, restart: unless-stopped
```

## 目录约定
- `.devcontainer/` — DevContainer 配置 (Dockerfile + docker-compose + post-create)
- `.pre-commit-config.yaml` — 共享 pre-commit hooks (gitleaks + 基础检查)
- `sync/` — 同步与部署脚本
  - `setup-thin-host.sh` — 新机器 bootstrap（只装 Docker + 创建 dev wrapper）
  - `git-sync.sh` — 自动 fetch/pull 守护进程（容器 sidecar 或宿主 cron）
- `docs/` — 开发机审计框架

## 工具链版本基线 (全部在容器内)
| 工具 | 版本 |
|------|------|
| Python | 3.12.12 (via pyenv) |
| Node | 22 (LTS) |
| gh | 2.86.0 |
| uv | 0.10.3 |
| gitleaks | 8.30.0 |
| gcloud | latest |
| Claude Code | latest |
| pre-commit | latest |

## 关键规则
- **宿主机只装 Docker + SSH**，严禁安装 Python/Node/gh 等开发工具
- **环境一致性由 Docker 镜像保证**，不是 shell 脚本
- **pre-commit hooks 通过 `pre-commit install` 在容器内配置**，不用 core.hooksPath
- **SSH config 由宿主机挂载 (read-only)**，post-create.sh 不写入
- **各项目依赖由项目自管理** (uv run)，不装进共享 venv
- **git-sync 的 REPOS 列表必须包含所有 13 个 repo**

## 13 个仓库
bladeai, dev-env, clawforce (heydoraai org), crypto-backtest, quant-backtest, quant-lab, ntws, longxia-market, ig-recruit-radar, xai-radar, claude-memory, ai-expert-monitor, whisper-vocab

## 新机器部署
```bash
bash ~/workspace/dev-env/sync/setup-thin-host.sh
```

## 进入开发环境
```bash
dev                                    # wrapper 命令
docker exec -it bladeai-dev bash       # 或直接 docker exec
```
