# M5 Max MacBook Pro 迁移方案

> 创建: 2026-03-17
> 状态: 准备就绪，待执行

## 明天到手后的操作步骤

### 第 1 步：安装 1Password 并登录（5 分钟）
1. 下载安装 1Password app
2. 登录 `yagjzx@gmail.com` 账号，等同步完成
3. **Settings → Developer → SSH Agent → 开启**
4. 确认 `id_ed25519` 已出现在 SSH Agent 里

### 第 2 步：运行一键脚本（20-30 分钟）
```bash
bash <(curl -sL https://raw.githubusercontent.com/yagjzx/dev-env/main/sync/setup-thin-host.sh)
```

脚本自动完成：
- Homebrew 安装
- Docker Desktop / gh / gcloud / Tailscale 安装
- `~/.gitconfig` 配置（含 commit signing）
- `~/.ssh/config` 生成（1Password Agent，无本地密钥文件）
- `gh auth login`（弹浏览器登录一次）
- clone 19 个核心 repo + 可选 24 个完整 repo
- `.devcontainer/.env` 生成
- Docker 容器 build + start + post-create

### 第 3 步：脚本完成后（5 分钟）
```bash
source ~/.zshrc       # 让 PATH 生效
tailscale up          # 连接 Tailscale 网络（需登录）
gcloud auth login     # 如需操作 GCP（东京机等）
```

---

## 宿主机工具清单

| 工具 | 用途 |
|------|------|
| Homebrew | 包管理 |
| Docker Desktop | 容器运行时（建议分配 16GB+ 内存） |
| gh CLI | repo clone + 容器 GH_TOKEN 注入 |
| gcloud CLI | GCP 基础设施管理（Tokyo VM 等） |
| Tailscale | 系统级网络（Tokyo / Mac Mini / iMac） |
| 1Password | SSH Agent（Touch ID 认证所有 SSH 连接） |

**不在宿主机装：** Python / Node / npm / Go / Rust / Claude Code（全在容器）

---

## 已完成的准备工作（旧 Mac 上）

- [x] `id_ed25519` 私钥存入 1Password（新 Mac 登录后自动同步）
- [x] GitHub Signing Key 已添加（`SHA256:BLIYHl0...`）
- [x] `setup-thin-host.sh` v2.0 已推送到 `yagjzx/dev-env`
- [x] SSH config 已切换为 1Password Agent（测试通过：GitHub ✅ Tokyo ✅）
- [x] commit signing 已配置并验证（GitHub 显示 Verified）
- [x] git commit 邮箱改为 `yagjzx@gmail.com`

---

## 注意事项

- **jp-gcp 主机**：用的是 GCP 自动生成的 `google_compute_engine` key，新 Mac 上改用 `gcloud compute ssh` 连接
- **旧 Mac 不需要关闭**，可以并行使用，确认新机器一切正常后再切换
- **Docker Desktop**：首次 build 镜像约 15-25 分钟，需要网络良好
