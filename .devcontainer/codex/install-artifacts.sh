#!/usr/bin/env bash
# Run as root inside bladeai-dev. Only the Linux copy is changed.
set -euo pipefail
artifact_config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifact_root=/opt/codex-artifacts
artifact_seed="${1:-/home/vscode/.codex/portable-packages/artifact-tool-2.8.59.tgz}"
if [[ ! -f "$artifact_seed" ]]; then
    printf 'Missing local official Artifact Tool seed: %s\n' "$artifact_seed" >&2
    exit 1
fi
install -d -m 755 "$artifact_root" "$artifact_root/node"
cp "$artifact_config_dir/artifacts-node/package.json" "$artifact_config_dir/artifacts-node/package-lock.json" "$artifact_root/node/"
npm ci --prefix "$artifact_root/node" --no-audit --no-fund
install -d -m 755 "$artifact_root/node/node_modules/@oai/artifact-tool"
tar -xzf "$artifact_seed" --strip-components=1 -C "$artifact_root/node/node_modules/@oai/artifact-tool"
/opt/pyenv/shims/python3 -m venv "$artifact_root/venv"
uv pip sync --python "$artifact_root/venv/bin/python" "$artifact_config_dir/artifacts-python.txt"
install -m 644 "$artifact_config_dir/artifact-register.mjs" "$artifact_root/artifact-register.mjs"
install -m 755 "$artifact_config_dir/codex-artifact-node" /usr/local/bin/codex-artifact-node
chmod -R a+rX "$artifact_root"
printf '%s\n' 'Codex artifact runtime installed under /opt/codex-artifacts'
