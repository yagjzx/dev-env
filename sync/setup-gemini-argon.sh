#!/usr/bin/env bash
# 一次性准备 Gemini 4 Argon（宿主机运行）：
#   1. 在 GCP 项目启用 aiplatform API（宿主机 gcloud，Thin Host 设计）
#   2. 冒烟测试：bladeai-dev 容器里用 uv 隔离环境（google-genai>=2.30.1）调一次 global endpoint
#      不往共享 /workspace/.venv 装包：那里 google-genai 按 requirements-base.txt 锁在 1.x
set -euo pipefail

PROJECT="${GOOGLE_CLOUD_PROJECT:-obiwanfly}"
CONTAINER="${DEV_ENV_CONTAINER:-bladeai-dev}"

echo "==> [host] enable aiplatform.googleapis.com on $PROJECT"
gcloud services enable aiplatform.googleapis.com --project "$PROJECT"

echo "==> [$CONTAINER] smoke test"
docker exec "$CONTAINER" gosu vscode bash -lc \
    "uv run -q --no-project --isolated --with 'google-genai>=2.30.1' python /workspace/dev-env/sync/gemini-argon.py --project '$PROJECT' --thinking LOW '用一句话介绍你自己，并说出你的模型名称。'"
