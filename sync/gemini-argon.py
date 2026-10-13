#!/usr/bin/env python3
"""Gemini 4 Argon 命令行（Vertex AI / Gemini Enterprise Agent Platform, global endpoint）

在 bladeai-dev 容器里运行：
  docker exec -it bladeai-dev gosu vscode /workspace/.venv/bin/python /workspace/dev-env/sync/gemini-argon.py            # 多轮对话
  docker exec bladeai-dev gosu vscode /workspace/.venv/bin/python /workspace/dev-env/sync/gemini-argon.py "你好"        # 单次提问

认证顺序：ADC (gcloud auth application-default login) → 回退到 `gcloud auth print-access-token`（1 小时有效）。
依赖：google-genai >= 2.30.1（由 sync/setup-gemini-argon.sh 安装）。
"""
import argparse
import os
import subprocess
import sys

from google import genai
from google.genai import types

MODEL = "gemini-4-argon"


def build_client(project: str, location: str) -> genai.Client:
    try:
        import google.auth

        google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
        return genai.Client(vertexai=True, project=project, location=location)
    except Exception:
        pass
    from google.oauth2.credentials import Credentials

    token = subprocess.run(
        ["gcloud", "auth", "print-access-token"], check=True, capture_output=True, text=True
    ).stdout.strip()
    return genai.Client(vertexai=True, project=project, location=location, credentials=Credentials(token))


def stream(chat, prompt: str) -> None:
    usage = None
    for chunk in chat.send_message_stream(prompt):
        if chunk.text:
            print(chunk.text, end="", flush=True)
        usage = chunk.usage_metadata or usage
    print()
    if usage:
        print(
            f"\033[2m[in {usage.prompt_token_count} / thinking {usage.thoughts_token_count or 0}"
            f" / out {usage.candidates_token_count}]\033[0m",
            file=sys.stderr,
        )


def main() -> None:
    p = argparse.ArgumentParser(description="Gemini 4 Argon CLI")
    p.add_argument("prompt", nargs="*", help="单次提问；省略则进入多轮对话")
    p.add_argument("--project", default=os.environ.get("GOOGLE_CLOUD_PROJECT", "obiwanfly"))
    p.add_argument("--location", default=os.environ.get("GOOGLE_CLOUD_LOCATION", "global"), help="global | us | eu")
    p.add_argument("--thinking", default="MEDIUM", choices=["LOW", "MEDIUM", "HIGH"])
    p.add_argument("--model", default=MODEL)
    args = p.parse_args()

    client = build_client(args.project, args.location)
    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_level=getattr(types.ThinkingLevel, args.thinking))
    )
    chat = client.chats.create(model=args.model, config=config)

    if args.prompt:
        stream(chat, " ".join(args.prompt))
        return

    print(f"{args.model} @ {args.project}/{args.location}  thinking={args.thinking}  (Ctrl-D 退出)")
    while True:
        try:
            prompt = input("\n> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if prompt:
            stream(chat, prompt)


if __name__ == "__main__":
    main()
