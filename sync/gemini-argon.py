#!/usr/bin/env python3
"""Gemini 4 Argon 命令行（Vertex AI / Gemini Enterprise Agent Platform, global endpoint）

在 bladeai-dev 容器里运行：
  docker exec -it bladeai-dev gosu vscode /workspace/.venv/bin/python /workspace/dev-env/sync/gemini-argon.py            # 多轮对话
  docker exec bladeai-dev gosu vscode /workspace/.venv/bin/python /workspace/dev-env/sync/gemini-argon.py "你好"        # 单次提问
  cat big.txt | docker exec -i bladeai-dev gosu vscode /workspace/.venv/bin/python /workspace/dev-env/sync/gemini-argon.py -   # 从 stdin 读（长上下文）

认证顺序：`gcloud auth print-access-token`（当前 gcloud 登录账号，1 小时有效）→ 回退到 ADC。
  gcloud 优先：在 GCE VM 上 ADC 会先拿到 VM 默认服务账号，通常没有 cloud-platform scope。
--json：每次提问输出一行 JSON（含耗时与 token 用量），便于批量采集。
依赖：google-genai >= 2.30.1（由 sync/setup-gemini-argon.sh 安装）。
"""
import argparse
import json
import os
import subprocess
import sys
import time

from google import genai
from google.genai import types

MODEL = "gemini-4-argon"


def build_client(project: str, location: str) -> genai.Client:
    try:
        from google.oauth2.credentials import Credentials

        token = subprocess.run(
            ["gcloud", "auth", "print-access-token"], check=True, capture_output=True, text=True
        ).stdout.strip()
        return genai.Client(vertexai=True, project=project, location=location, credentials=Credentials(token))
    except (OSError, subprocess.CalledProcessError):
        return genai.Client(vertexai=True, project=project, location=location)


def stream(chat, prompt: str, as_json: bool = False) -> None:
    usage, parts, started = None, [], time.monotonic()
    for chunk in chat.send_message_stream(prompt):
        if chunk.text:
            parts.append(chunk.text)
            if not as_json:
                print(chunk.text, end="", flush=True)
        usage = chunk.usage_metadata or usage
    elapsed = round(time.monotonic() - started, 2)
    if as_json:
        print(json.dumps({
            "prompt": prompt[:300],
            "prompt_chars": len(prompt),
            "text": "".join(parts),
            "seconds": elapsed,
            "input_tokens": usage.prompt_token_count if usage else None,
            "thinking_tokens": (usage.thoughts_token_count or 0) if usage else None,
            "output_tokens": usage.candidates_token_count if usage else None,
        }, ensure_ascii=False))
        return
    print()
    if usage:
        print(
            f"\033[2m[{elapsed}s | in {usage.prompt_token_count} / thinking {usage.thoughts_token_count or 0}"
            f" / out {usage.candidates_token_count}]\033[0m",
            file=sys.stderr,
        )


def main() -> None:
    p = argparse.ArgumentParser(description="Gemini 4 Argon CLI")
    p.add_argument("prompt", nargs="*", help="单次提问；'-' 表示从 stdin 读；省略则进入多轮对话")
    p.add_argument("--project", default=os.environ.get("GOOGLE_CLOUD_PROJECT", "obiwanfly"))
    p.add_argument("--location", default=os.environ.get("GOOGLE_CLOUD_LOCATION", "global"), help="global | us | eu")
    p.add_argument("--thinking", default="MEDIUM", choices=["LOW", "MEDIUM", "HIGH"])
    p.add_argument("--model", default=MODEL)
    p.add_argument("--json", action="store_true", help="单次提问时输出一行 JSON（耗时 + token 用量）")
    args = p.parse_args()

    client = build_client(args.project, args.location)
    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_level=getattr(types.ThinkingLevel, args.thinking))
    )
    chat = client.chats.create(model=args.model, config=config)

    if args.prompt:
        prompt = sys.stdin.read() if args.prompt == ["-"] else " ".join(args.prompt)
        stream(chat, prompt, args.json)
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
