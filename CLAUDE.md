# dev-env — Claude Code 项目指令

## 项目概览
开发机环境管理仓库。管理 4 台开发机（iMac、MacBook Pro、Mac Mini、Tokyo VM）的工具链、shell 配置、DevContainer 和自动同步。

## 目录约定
- `.devcontainer/` — VS Code DevContainer 配置（Dockerfile + post-create 脚本）
- `sync/` — 环境部署与同步脚本
  - `setup-dev-machine.sh` — 新机器一键部署（macOS + Linux）
  - `git-sync.sh` — 自动 fetch/pull 守护进程（launchd/cron）
  - `pre-commit-hook` — gitleaks 密钥扫描 hook
  - `zprofile-template-macos` — macOS 标准 .zprofile
  - `profile-template-linux` — Linux 标准 .profile 追加块
- `docs/` — 开发机审计框架

## 工具链版本基线
| 工具 | 版本 |
|------|------|
| Python | 3.12.12 (via pyenv) |
| Git | 2.53.0 |
| Node | v25.6.1 |
| gh | 2.86.0 |
| uv | 0.10.3 |
| gitleaks | 8.30.0 |
| gcloud | 556.0.0 |

## 关键规则
- **所有机器必须通过 `setup-dev-machine.sh` 部署**，禁止手动装工具
- **pyenv init 必须在 .zprofile（macOS）或 .profile（Linux）中**，不能只放 .zshrc
- **pre-commit hook 统一通过 `core.hooksPath` 共享**，不要逐 repo 复制
- **git-sync 的 REPOS 列表必须包含所有 13 个 repo**

## 13 个仓库
bladeai, dev-env, clawforce (heydoraai org), crypto-backtest, quant-backtest, quant-lab, ntws, longxia-market, ig-recruit-radar, xai-radar, claude-memory, ai-expert-monitor, whisper-vocab

## 新机器部署
```bash
bash <(curl -sL https://raw.githubusercontent.com/yagjzx/dev-env/main/sync/setup-dev-machine.sh)
```
