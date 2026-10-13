#!/usr/bin/env bash
# 一次性准备 Gemini 4 Argon（宿主机运行）：
#   1. 在 GCP 项目启用 aiplatform API（宿主机 gcloud，Thin Host 设计）
#   2. 在 bladeai-dev 容器 venv 里装 google-genai >= 2.30.1
#   3. 冒烟测试：global endpoint 调一次 gemini-4-argon
set -euo pipefail

PROJECT="${GOOGLE_CLOUD_PROJECT:-obiwanfly}"
CONTAINER="${DEV_ENV_CONTAINER:-bladeai-dev}"

echo "==> [host] enable aiplatform.googleapis.com on $PROJECT"
gcloud services enable aiplatform.googleapis.com --project "$PROJECT"

echo "==> [$CONTAINER] install google-genai>=2.30.1"
docker exec "$CONTAINER" gosu vscode bash -lc \
    'uv pip install --python /workspace/.venv/bin/python "google-genai>=2.30.1"'

echo "==> [$CONTAINER] smoke test"
docker exec "$CONTAINER" gosu vscode bash -lc \
    "/workspace/.venv/bin/python /workspace/dev-env/sync/gemini-argon.py --project '$PROJECT' --thinking LOW '用一句话介绍你自己，并说出你的模型名称。'"
