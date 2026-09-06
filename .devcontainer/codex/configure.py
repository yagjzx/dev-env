#!/usr/bin/env python3
"""Initialize Linux-only Codex state; preserve host settings and credentials."""
import argparse
import json
import os
from pathlib import Path
import tomllib


def scalar(value):
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(scalar(item) for item in value) + "]"
    raise TypeError(f"Unsupported TOML value: {type(value).__name__}")


def dump_toml(data, prefix=()):
    lines = []
    if prefix:
        lines.append("[" + ".".join(json.dumps(key) for key in prefix) + "]")
    for key, value in data.items():
        if not isinstance(value, dict):
            lines.append(json.dumps(key) + " = " + scalar(value))
    for key, value in data.items():
        if isinstance(value, dict):
            lines.extend(["", dump_toml(value, prefix + (key,)).rstrip()])
    return "\n".join(lines) + "\n"


def initialize(host, target):
    host, target = Path(host), Path(target)
    if host.resolve() == target.resolve():
        raise ValueError("Container state must not overwrite the host Codex home")
    source = tomllib.loads((host / "config.toml").read_text()) if (host / "config.toml").exists() else {}
    target.mkdir(parents=True, exist_ok=True, mode=0o700)
    target.chmod(0o700)
    destination = target / "config.toml"
    if not destination.exists():
        keys = ("model", "model_reasoning_effort", "model_provider", "model_providers",
                "forced_login_method", "personality", "approvals_reviewer", "approval_policy",
                "memories")
        config = {key: source[key] for key in keys if key in source}
        config.setdefault("approval_policy", "on-request")
        config.setdefault("approvals_reviewer", "auto_review")
        config["sandbox_mode"] = "workspace-write"
        config["features"] = {key: value for key, value in source.get("features", {}).items()
                              if key in ("memories", "multi_agent")}
        config["projects"] = {"/workspace": {"trust_level": "trusted"}}
        config["mcp_servers"] = {
            name: settings for name, settings in source.get("mcp_servers", {}).items()
            if settings.get("url") and settings.get("enabled", True)
        }
        content = "# Linux Codex configuration; host desktop state stays separate.\n" + dump_toml(config)
        tomllib.loads(content)
        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as handle:
            handle.write(content)
    auth = target / "auth.json"
    if (host / "auth.json").is_file() and not auth.exists() and not auth.is_symlink():
        auth.symlink_to(os.path.relpath(host / "auth.json", target))
    for profile in host.glob("*.config.toml"):
        dst = target / profile.name
        if not dst.exists():
            dst.write_bytes(profile.read_bytes())
            dst.chmod(0o600)
    skills = target / "skills"
    skills.mkdir(exist_ok=True)
    sources = [path for path in (host / "skills").glob("*") if path.is_dir()]
    for plugin in ("documents", "spreadsheets", "presentations", "pdf"):
        root = host / "plugins/cache/openai-primary-runtime" / plugin
        versions = sorted(path for path in root.glob("*") if path.is_dir())
        if versions:
            sources.extend(path for path in (versions[-1] / "skills").glob("*") if path.is_dir())
    for path in sources:
        dst = skills / path.name
        if not dst.exists() and not dst.is_symlink():
            dst.symlink_to(os.path.relpath(path, skills), target_is_directory=True)
    guidance = target / "AGENTS.md"
    if not guidance.exists():
        guidance.write_text("""# Container execution
You are already inside bladeai-dev. /workspace is the host workspace bind mount.
Run development tools directly here; do not route commands back to macOS.
Keep host desktop paths, browser MCP launchers and host session databases out of this Linux configuration.
For office artifacts use /opt/codex-artifacts/venv/bin/python and /opt/codex-artifacts/node/node_modules.
Use /usr/local/bin/codex-artifact-node for Node artifact scripts. It supplies the supported dependencies in a temporary build directory.
The authoring/rendering rules of the relevant document, spreadsheet, presentation and PDF skills still apply.
""")
    return {"state_directory": str(target), "config": str(destination),
            "auth_available": auth.is_file(), "skill_links": sum(path.is_symlink() for path in skills.iterdir())}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host-home", default="/home/vscode/.codex")
    parser.add_argument("--container-home", default="/home/vscode/.codex/container-linux")
    args = parser.parse_args()
    print(json.dumps(initialize(args.host_home, args.container_home)))
