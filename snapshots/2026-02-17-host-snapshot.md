# dev-vm-tokyo 宿主机完整快照

> 采集时间: 2026-02-17 04:03 UTC
> 用途: 容器化改造前后对比基线

## 系统信息
- **Hostname**: dev-vm-tokyo.asia-northeast1-b.c.obiwanfly.internal
- **OS**: Ubuntu 24.04.3 LTS, Kernel 6.14.0-1021-gcp
- **CPU**: 8 cores (n2-standard-8)
- **RAM**: 31Gi total, 2.8Gi used, 28Gi available
- **Disk**: 96G total, 41G used (42%), 56G available
- **Uptime**: 1 day, 23 hours
- **Public IP**: 34.146.153.23
- **Tailscale IP**: 100.67.53.22

## 监听端口
| Port | Service | Bind | Process |
|------|---------|------|---------|
| 22 | SSH | 0.0.0.0 | systemd |
| 3000 | Gitea HTTP | 127.0.0.1 | Docker |
| 2222 | Gitea SSH | 127.0.0.1 | Docker |
| 8080 | xai-radar dashboard | 0.0.0.0 | python3 (pid 61741) |
| 8090 | ig-recruit-radar dashboard | 0.0.0.0 | python3 (pid 112554) |
| 20241 | cloudflared metrics | 127.0.0.1 | cloudflared (pid 136066) |
| 40300 | Tailscale | 100.67.53.22 | tailscaled |

## Docker 容器
| Name | Image | Status | RAM |
|------|-------|--------|-----|
| bladeai-dev | devcontainer-dev (6.94GB) | Up | 284 MiB |
| bladeai-git-sync | alpine/git:latest | Up 2h | 4.6 MiB |
| gitea | gitea/gitea:latest | Up 47h | 148 MiB |

## Crontab
```
# backup sync — primary is bladeai-git-sync container
*/5 * * * * /home/simba/workspace/.sync/git-sync.sh
*/5 * * * * /home/simba/workspace/bladeai/ip-check.sh >/dev/null 2>&1
0 1 * * * /home/simba/workspace/bladeai/scripts/monitor.sh >> /home/simba/workspace/bladeai/monitor-data/cron.log 2>&1
```

## 工具版本
| Tool | Host | Container | Match? |
|------|------|-----------|--------|
| Python | 3.12.3 (pyenv 3.12.12) | 3.12.12 (pyenv) | ✅ |
| Node | v25.6.1 (nvm) | v25.6.1 (NodeSource) | ✅ |
| Go | 1.25.7 | 1.25.7 | ✅ |
| Rust | 1.93.0 | 1.93.0 (system-wide) | ✅ |
| Docker | 29.2.1 | N/A (宿主机专属) | N/A |
| Docker Compose | 5.0.2 | N/A | N/A |
| gcloud | 556.0.0 | 556.0.0 | ✅ |
| gh CLI | 2.86.0 | 2.86.0 | ✅ |
| gitleaks | 8.30.0 | 8.30.0 | ✅ |
| uv | 0.10.3 | 0.10.3 | ✅ |
| tmux | 3.4 | 3.4 | ✅ |
| vim | 9.1 | 9.1 | ✅ |
| git | 2.53.0 | 2.51.1 | ✅ |
| Claude Code | 2.1.44 | 2.1.44 | ✅ |
| pre-commit | 未装(宿主机用gitleaks hook) | 4.5.1 | ✅ |
| pm2 | (Node v24 only) | 6.0.14 | ✅ |
| Tailscale | 1.94.1 | N/A (宿主机专属) | N/A |
| conda | 26.1.0 | 未安装 | ❌ Phase 2 |

## Python 包对比
| 环境 | 包数量 | 说明 |
|------|--------|------|
| 宿主机 ~/venv | 151 | 核心开发包 |
| 容器 (镜像+venv) | 248 | 包含所有宿主机包 + 7个repo项目依赖 |
| 宿主机有容器没有 | **0** | 完全覆盖 |
| Conda quant 环境 | 159 | 未迁移 (ML/Jupyter专用) |

### 宿主机 ~/venv 完整包列表 (151个)
```
Crawl4AI==0.8.0, Jinja2==3.1.6, MarkupSafe==3.0.3, PySocks==1.7.1, PyYAML==6.0.3,
Pygments==2.19.2, aiodns==4.0.0, aiofiles==25.1.0, aiohappyeyeballs==2.6.1,
aiohttp==3.13.3, aiosignal==1.4.0, aiosqlite==0.22.1, alphashape==1.3.1,
annotated-doc==0.0.4, annotated-types==0.7.0, anyio==4.12.1, apify_client==2.4.1,
apify_shared==2.2.0, async-generator==1.10, attrs==25.4.0, beautifulsoup4==4.14.3,
brotli==1.2.0, ccxt==4.5.37, certifi==2026.1.4, cffi==2.0.0, chardet==5.2.0,
charset-normalizer==3.4.4, click-log==0.4.0, click==8.3.1, coincurve==21.0.0,
colorama==0.4.6, cryptography==46.0.5, cssselect==1.4.0, distro==1.9.0,
fake-http-header==0.3.5, fake-useragent==2.2.0, fastuuid==0.14.0, filelock==3.20.3,
firecrawl-py==4.14.0, frozenlist==1.8.0, fsspec==2026.2.0,
google-ai-generativelanguage==0.6.15, google-api-core==2.29.0,
google-api-python-client==2.190.0, google-auth-httplib2==0.3.0, google-auth==2.48.0,
google-genai==1.63.0, google-generativeai==0.8.6, googleapis-common-protos==1.72.0,
greenlet==3.3.1, grpcio-status==1.71.2, grpcio==1.78.0, h11==0.16.0, h2==4.3.0,
hf-xet==1.2.0, hpack==4.1.0, httpcore==1.0.9, httplib2==0.31.2, httpx==0.28.1,
huggingface_hub==1.4.1, humanize==4.15.0, hyperframe==6.1.0, idna==3.11,
impit==0.11.0, importlib_metadata==8.7.1, jiter==0.13.0, joblib==1.5.3,
jsonschema-specifications==2025.9.1, jsonschema==4.26.0, lark==1.3.1,
litellm==1.81.10, loguru==0.7.3, lxml==5.4.0, markdown-it-py==4.0.0, mdurl==0.1.2,
more-itertools==10.8.0, multidict==6.7.1, mypy_extensions==1.1.0,
nest-asyncio==1.6.0, networkx==3.6.1, nltk==3.9.2, numpy==2.4.2, openai==2.20.0,
outcome==1.3.0.post0, packaging==26.0, pandas==3.0.0, patchright==1.58.0,
pillow==12.1.1, pip==24.0, playwright==1.58.0, praw==7.8.1, prawcore==2.4.0,
propcache==0.4.1, proto-plus==1.27.1, protobuf==5.29.6, psutil==7.2.2,
pyOpenSSL==25.3.0, pyasn1==0.6.2, pyasn1_modules==0.4.2, pycares==5.0.1,
pycparser==3.0, pydantic==2.12.5, pydantic_core==2.41.5, pyee==13.0.0,
pyotp==2.9.0, pyparsing==3.3.2, python-dateutil==2.9.0.post0, python-dotenv==1.2.1,
rank-bm25==0.2.2, referencing==0.37.0, regex==2026.1.15, requests==2.32.5,
rich==14.3.2, rpds-py==0.30.0, rsa==4.9.1, rtree==1.4.1, scipy==1.17.0,
selenium==4.40.0, setuptools==82.0.0, shapely==2.1.2, shellingham==1.5.4,
six==1.17.0, sniffio==1.3.1, snowballstemmer==2.2.0, sortedcontainers==2.4.0,
soupsieve==2.8.3, tenacity==9.1.4, tf-playwright-stealth==1.2.0, tiktoken==0.12.0,
tokenizers==0.22.2, tqdm==4.67.3, trimesh==4.11.2, trio-typing==0.10.0,
trio-websocket==0.12.2, trio==0.32.0, twscrape==0.17.0, typer-slim==0.23.0,
typer==0.23.0, types-certifi==2021.10.8.3, types-urllib3==1.26.25.14,
typing-inspection==0.4.2, typing_extensions==4.15.0, update-checker==0.18.0,
uritemplate==4.2.0, urllib3==2.6.3, websocket-client==1.9.0, websockets==15.0.1,
wsproto==1.3.2, xxhash==3.6.0, yarl==1.22.0, zipp==3.23.0
```

## Playwright 浏览器
| 组件 | 宿主机 | 容器 |
|------|--------|------|
| chromium-1208 | ✅ | ✅ |
| chromium_headless_shell-1208 | ✅ | ✅ |
| ffmpeg-1011 | ✅ | ✅ |

## SSH 别名
hk-panel, jp-dmit, sg-proxy, us-dmit, us-gateway, mac-mini

## Git Global Config
```
credential.https://github.com.helper=!/usr/bin/gh auth git-credential
credential.https://gist.github.com.helper=!/usr/bin/gh auth git-credential
user.name=Simba
user.email=yagjzx@gmail.com
core.hookspath=/home/simba/workspace/.githooks
```

## 13 Repos 状态
| Repo | Branch | Dirty | Ahead | Behind | Last Commit |
|------|--------|-------|-------|--------|-------------|
| bladeai | main | 4 | 0 | 0 | security standards v1.1 + DR validation |
| dev-env | main | 0 | 0 | 0 | Upgrade container to full dev parity |
| clawforce | main | 1 | 0 | 0 | update payment |
| crypto-backtest | main | 1 | 0 | 0 | add CLAUDE.md |
| quant-backtest | main | 1 | 0 | 0 | add CLAUDE.md |
| quant-lab | main | 1 | 0 | 0 | add CLAUDE.md |
| ntws | main | 1 | 0 | 0 | add CLAUDE.md |
| longxia-market | main | 1 | 0 | 0 | add CLAUDE.md |
| ig-recruit-radar | main | 2 | 0 | 3 | crawl 3124 new recruiters |
| xai-radar | master | 2 | 0 | 0 | Add PROJECT_OVERVIEW.md |
| claude-memory | main | 0 | 0 | 0 | DevContainer full parity upgrade |
| ai-expert-monitor | master | 1 | 0 | 0 | review feedback |
| whisper-vocab | master | 1 | 0 | 0 | Code review fixes |

## 磁盘用量
| Path | Size |
|------|------|
| ~/workspace/ | 6.3G |
| ~/miniforge3/ | 2.7G |
| ~/.cache/ | 1.5G |
| ~/venv/ | 975M |
| ~/.nvm/ | 746M |
| ~/.pyenv/ | 326M |
| ~/.cargo/ | 20M |

## 功能性测试结果 (容器)
| Test | Result |
|------|--------|
| Python 32 核心包 import | ✅ ALL OK |
| Playwright Chromium 启动 + 加载网页 | ✅ OK |
| Go 编译运行 | ✅ OK |
| gh CLI 认证 (yagjzx) | ✅ OK |
| gcloud 项目 (obiwanfly) | ✅ OK |
| uv 包管理 | ✅ OK |
| pre-commit 全量扫描 | ✅ 5/5 passed |
| git 操作 | ✅ OK |
| pm2 start/list/delete | ✅ OK |
| SSH aliases 可见 (6个) | ✅ OK |
| 项目特定包 (fastapi/duckdb/backtrader/streamlit/matplotlib/yfinance/uvicorn) | ✅ 7/7 OK |

## 已知差异 (设计决定,非缺陷)
1. **Conda quant**: 宿主机有 159 包 (ML/Jupyter), 容器无 — Phase 2
2. **Docker CLI**: 宿主机有, 容器无 — 不需要容器内套容器
3. **Tailscale**: 宿主机有, 容器无 — 网络基础设施, 非开发工具
