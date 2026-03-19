#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$ROOT_DIR/.devcontainer/Dockerfile"
REQ_IN="$ROOT_DIR/.devcontainer/requirements-base.in"
REQ_LOCK="$ROOT_DIR/.devcontainer/requirements-base.txt"

NODE_CHANNEL="current"
CLAUDE_CHANNEL="latest"

usage() {
  cat <<'EOF'
Usage: bash sync/refresh-devcontainer-stack.sh [--node-channel current|lts] [--claude-channel latest|stable]

Refreshes:
  1. pinned toolchain versions in .devcontainer/Dockerfile
  2. compiled Python lockfile .devcontainer/requirements-base.txt

Defaults:
  --node-channel current
  --claude-channel latest
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-channel)
      NODE_CHANNEL="${2:?missing value for --node-channel}"
      shift 2
      ;;
    --claude-channel)
      CLAUDE_CHANNEL="${2:?missing value for --claude-channel}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$NODE_CHANNEL" in
  current|lts) ;;
  *)
    echo "Invalid --node-channel: $NODE_CHANNEL" >&2
    exit 1
    ;;
esac

case "$CLAUDE_CHANNEL" in
  latest|stable) ;;
  *)
    echo "Invalid --claude-channel: $CLAUDE_CHANNEL" >&2
    exit 1
    ;;
esac

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd jq
require_cmd sed
require_cmd sort
require_cmd awk
require_cmd grep
require_cmd uv

host_python_platform() {
  case "$(uname -m)" in
    arm64|aarch64)
      echo "aarch64-unknown-linux-gnu"
      ;;
    x86_64)
      echo "x86_64-unknown-linux-gnu"
      ;;
    *)
      echo "Unsupported host architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

current_arg() {
  sed -n -E "s/^ARG $1=(.*)$/\\1/p" "$DOCKERFILE" | head -n 1
}

update_arg() {
  local name="$1"
  local value="$2"
  local tmp_file
  tmp_file="$(mktemp)"
  sed -E "s#^(ARG ${name}=).*#\\1${value}#" "$DOCKERFILE" > "$tmp_file"
  mv "$tmp_file" "$DOCKERFILE"
}

fetch_node_version() {
  if [[ "$NODE_CHANNEL" == "lts" ]]; then
    curl -fsSL https://nodejs.org/dist/index.json | jq -r 'map(select(.lts != false))[0].version' | sed 's/^v//'
  else
    curl -fsSL https://nodejs.org/dist/index.json | jq -r '.[0].version' | sed 's/^v//'
  fi
}

fetch_python_version() {
  local current python_series listing
  current="$(current_arg PYTHON_VERSION)"
  python_series="$(printf '%s' "$current" | cut -d. -f1-2)"
  listing="$(curl -fsSL https://www.python.org/ftp/python/)"

  printf '%s' "$listing" \
    | grep -oE "href=\"${python_series//./\\.}\\.[0-9]+/\"" \
    | sed -E 's/^href="([^"]+)\/"$/\1/' \
    | sort -V \
    | tail -n 1
}

fetch_rust_version() {
  local manifest
  manifest="$(curl -fsSL https://static.rust-lang.org/dist/channel-rust-stable.toml)"

  awk '
      /^\[pkg\.rust\]$/ { in_rust=1; next }
      in_rust && /^version = / {
        line = $0
        sub(/^version = "/, "", line)
        sub(/ .*/, "", line)
        sub(/"$/, "", line)
        print line
        exit
      }
    ' <<<"$manifest"
}

fetch_go_version() {
  curl -fsSL https://go.dev/dl/?mode=json | jq -r 'map(select(.stable))[0].version | sub("^go"; "")'
}

fetch_gcloud_version() {
  curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json | jq -r '.version + "-0"'
}

fetch_gh_version() {
  curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name | sub("^v"; "")'
}

fetch_gitleaks_version() {
  curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r '.tag_name | sub("^v"; "")'
}

fetch_uv_version() {
  curl -fsSL https://api.github.com/repos/astral-sh/uv/releases/latest | jq -r '.tag_name | sub("^v"; "")'
}

fetch_codex_version() {
  curl -fsSL https://registry.npmjs.org/%40openai%2Fcodex/latest | jq -r '.version'
}

fetch_gemini_version() {
  curl -fsSL https://registry.npmjs.org/%40google%2Fgemini-cli/latest | jq -r '.version'
}

fetch_claude_version() {
  curl -fsSL "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${CLAUDE_CHANNEL}"
}

echo "Refreshing pinned toolchain versions..."
PYTHON_VERSION="$(fetch_python_version)"
NODE_VERSION="$(fetch_node_version)"
RUST_VERSION="$(fetch_rust_version)"
GO_VERSION="$(fetch_go_version)"
GCLOUD_VERSION="$(fetch_gcloud_version)"
GH_VERSION="$(fetch_gh_version)"
GITLEAKS_VERSION="$(fetch_gitleaks_version)"
UV_VERSION="$(fetch_uv_version)"
CODEX_VERSION="$(fetch_codex_version)"
GEMINI_VERSION="$(fetch_gemini_version)"
CLAUDE_CODE_VERSION="$(fetch_claude_version)"

update_arg PYTHON_VERSION "$PYTHON_VERSION"
update_arg NODE_VERSION "$NODE_VERSION"
update_arg RUST_VERSION "$RUST_VERSION"
update_arg GO_VERSION "$GO_VERSION"
update_arg GCLOUD_VERSION "$GCLOUD_VERSION"
update_arg GH_VERSION "$GH_VERSION"
update_arg GITLEAKS_VERSION "$GITLEAKS_VERSION"
update_arg UV_VERSION "$UV_VERSION"
update_arg CODEX_VERSION "$CODEX_VERSION"
update_arg GEMINI_VERSION "$GEMINI_VERSION"
update_arg CLAUDE_CODE_VERSION "$CLAUDE_CODE_VERSION"

echo "Compiling pinned Python lockfile..."
PYTHON_PLATFORM="$(host_python_platform)"
uv pip compile \
  "$REQ_IN" \
  --upgrade \
  --python-version "${PYTHON_VERSION%.*}" \
  --python-platform "${PYTHON_PLATFORM}" \
  --output-file "$REQ_LOCK" \
  --custom-compile-command "bash sync/refresh-devcontainer-stack.sh --node-channel ${NODE_CHANNEL} --claude-channel ${CLAUDE_CHANNEL}"

echo ""
echo "Refreshed devcontainer stack:"
echo "  Python:   $PYTHON_VERSION"
echo "  Node:     $NODE_VERSION ($NODE_CHANNEL)"
echo "  Rust:     $RUST_VERSION"
echo "  Go:       $GO_VERSION"
echo "  gcloud:   $GCLOUD_VERSION"
echo "  gh:       $GH_VERSION"
echo "  uv:       $UV_VERSION"
echo "  gitleaks: $GITLEAKS_VERSION"
echo "  Claude:   $CLAUDE_CODE_VERSION ($CLAUDE_CHANNEL)"
echo "  Codex:    $CODEX_VERSION"
echo "  Gemini:   $GEMINI_VERSION"
echo ""
echo "Next:"
echo "  docker compose --env-file $ROOT_DIR/.devcontainer/.env -f $ROOT_DIR/.devcontainer/docker-compose.yml build dev"
echo "  docker compose --env-file $ROOT_DIR/.devcontainer/.env -f $ROOT_DIR/.devcontainer/docker-compose.yml up -d --force-recreate"
