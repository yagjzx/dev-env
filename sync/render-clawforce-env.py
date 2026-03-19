#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def parse_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key] = value
    return data


def parse_template(path: Path) -> tuple[list[str], dict[str, str]]:
    ordered_keys: list[str] = []
    data: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        ordered_keys.append(key)
        data[key] = value
    return ordered_keys, data


def generate_keypair() -> tuple[str, str]:
    private_pem = subprocess.run(
        ["openssl", "genpkey", "-algorithm", "Ed25519"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    public_pem = subprocess.run(
        ["openssl", "pkey", "-pubout"],
        check=True,
        capture_output=True,
        text=True,
        input=private_pem + "\n",
    ).stdout.strip()
    return private_pem, public_pem


def main() -> int:
    parser = argparse.ArgumentParser(description="Render a local ClawForce dev env file.")
    parser.add_argument("--template", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    template_path = Path(args.template)
    output_path = Path(args.output)

    ordered_keys, template_map = parse_template(template_path)
    existing_map = parse_env(output_path)
    env_map = dict(template_map)
    env_map.update(existing_map)

    needs_keys = not all(
        env_map.get(key)
        for key in (
            "CLAWFORCE_JWT_PRIVATE_KEY",
            "CLAWFORCE_JWT_PUBLIC_KEYS",
            "CLAWFORCE_JWT_KID",
        )
    )

    if needs_keys:
        private_pem, public_pem = generate_keypair()
        env_map["CLAWFORCE_JWT_PRIVATE_KEY"] = private_pem.replace("\n", "\\n")
        env_map["CLAWFORCE_JWT_PUBLIC_KEYS"] = json.dumps(
            {"dev-1": public_pem.replace("\n", "\\n")}
        )
        env_map["CLAWFORCE_JWT_KID"] = "dev-1"

    for key in ("CLAWFORCE_JWT_PRIVATE_KEY", "CLAWFORCE_JWT_PUBLIC_KEYS", "CLAWFORCE_JWT_KID"):
        if key not in ordered_keys:
            ordered_keys.append(key)

    rendered = [f"{key}={env_map[key]}" for key in ordered_keys]
    for key, value in existing_map.items():
        if key not in ordered_keys:
            rendered.append(f"{key}={value}")

    output_path.write_text("\n".join(rendered) + "\n", encoding="utf-8")
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
