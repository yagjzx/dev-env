#!/bin/bash
# BladeAI DevContainer post-create setup
# Runs once after container is created (idempotent)

set -euo pipefail

WORKSPACE="/workspace"
VENV="$WORKSPACE/.venv"
PRE_COMMIT_CONFIG="$WORKSPACE/dev-env/.pre-commit-config.yaml"
export UV_LINK_MODE="copy"

REQ_PROJECTS=(
    "xai-radar/requirements.txt"
    "ig-recruit-radar/requirements.txt"
    "crypto-backtest/requirements.txt"
    "quant-backtest/requirements.txt"
    "quant-lab/requirements.txt"
    "longxia-market/scripts/requirements.txt"
)

PY_EDITABLE_PROJECTS=(
    "clawforce|/workspace/clawforce[dev]|"
    "clawforce-admin|/workspace/clawforce-admin[dev]|"
    "clawforce-lobster-fleet|/workspace/clawforce-lobster-fleet[test]|dev"
    "seedforge|/workspace/seedforge[test]|"
)

PY_DEP_ONLY_PROJECTS=(
    "gtm-engine|dev"
)

NODE_CI_PROJECTS=(
    "clawforce/web"
    "clawforce-admin/web"
    "clawforce-lobster-fleet/clawforce-plugin"
    "clawforce-lobster-fleet/dashboard-lobster"
    "clawforce/sdk-js"
    "seedforge/dashboard-admin"
)

NODE_INSTALL_PROJECTS=(
    "clawforce/desktop"
)

FAILURES=()
SKIPPED=()

record_failure() {
    local label="$1"
    FAILURES+=("$label")
    echo "  x $label"
}

record_skip() {
    local label="$1"
    SKIPPED+=("$label")
    echo "  - $label"
}

repair_workspace_venv() {
    local expected_home current_home
    if command -v pyenv >/dev/null 2>&1; then
        expected_home="$(pyenv prefix)/bin"
    else
        expected_home="$(python3 -c "import os, sys; print(os.path.dirname(sys.executable))")"
    fi
    current_home="$(grep "^home" "$VENV/pyvenv.cfg" 2>/dev/null | cut -d= -f2 | tr -d " " || true)"

    if [ ! -e "$VENV/bin/python" ] || [ "$current_home" != "$expected_home" ]; then
        echo "Creating workspace .venv (home=$expected_home)..."
        mkdir -p "$VENV"
        find "$VENV" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
        python3 -m venv --system-site-packages "$VENV"
    elif ! grep -q "include-system-site-packages = true" "$VENV/pyvenv.cfg" 2>/dev/null; then
        echo "Upgrading .venv to include system-site-packages..."
        python3 -m venv --system-site-packages --upgrade "$VENV"
    fi
}

install_requirements_file() {
    local rel_path="$1"
    local abs_path="$WORKSPACE/$rel_path"

    if [ ! -f "$abs_path" ]; then
        record_skip "$rel_path (requirements missing)"
        return
    fi

    echo "  -> $rel_path"
    if uv pip install --python "$VENV/bin/python" -r "$abs_path" --strict; then
        echo "  ok $rel_path"
    else
        record_failure "python requirements: $rel_path"
    fi
}

install_editable_project() {
    local project="$1"
    local editable_spec="$2"
    local groups_csv="$3"
    local project_dir="$WORKSPACE/$project"
    local -a cmd=(uv pip install --python "$VENV/bin/python" --project "$project_dir" --editable "$editable_spec" --strict)

    if [ ! -f "$project_dir/pyproject.toml" ]; then
        record_skip "$project (pyproject missing)"
        return
    fi

    if [ -n "$groups_csv" ]; then
        local group
        for group in ${groups_csv//,/ }; do
            cmd+=(--group "$group")
        done
    fi

    echo "  -> $project"
    if "${cmd[@]}"; then
        echo "  ok $project"
    else
        record_failure "python editable: $project"
    fi
}

check_editable_project_collisions() {
    local duplicates

    duplicates="$(python3 - "$WORKSPACE" "${PY_EDITABLE_PROJECTS[@]}" <<'PYCOLLIDE'
import pathlib
import sys
import tomllib

workspace = pathlib.Path(sys.argv[1])
entries = sys.argv[2:]
names = {}

for entry in entries:
    project = entry.split("|", 1)[0]
    pyproject_path = workspace / project / "pyproject.toml"
    if not pyproject_path.is_file():
        continue

    data = tomllib.loads(pyproject_path.read_text())
    project_name = (data.get("project") or {}).get("name")
    if project_name:
        names.setdefault(project_name, []).append(project)

for project_name, projects in sorted(names.items()):
    if len(projects) > 1:
        print(f"{project_name}: {', '.join(projects)}")
PYCOLLIDE
)"

    if [ -z "$duplicates" ]; then
        return
    fi

    while IFS= read -r duplicate; do
        [ -n "$duplicate" ] || continue
        record_failure "python package collision: $duplicate"
    done <<< "$duplicates"
}

install_pyproject_dependencies() {
    local project="$1"
    local extras_csv="$2"
    local project_dir="$WORKSPACE/$project"
    local tmp_requirements

    if [ ! -f "$project_dir/pyproject.toml" ]; then
        record_skip "$project (pyproject missing)"
        return
    fi

    tmp_requirements="$(mktemp)"
    python3 - "$project_dir" "$extras_csv" > "$tmp_requirements" <<PYREQ
import pathlib
import sys
import tomllib

project_dir = pathlib.Path(sys.argv[1])
extras = [item for item in sys.argv[2].split(",") if item]
data = tomllib.loads(project_dir.joinpath("pyproject.toml").read_text())
project = data.get("project", {})
requirements = list(project.get("dependencies", []))
for extra in extras:
    requirements.extend((project.get("optional-dependencies") or {}).get(extra, []))
for requirement in requirements:
    print(requirement)
PYREQ

    echo "  -> $project (dependencies only)"
    if uv pip install --python "$VENV/bin/python" -r "$tmp_requirements" --strict; then
        echo "  ok $project"
    else
        record_failure "python dependencies: $project"
    fi

    rm -f "$tmp_requirements"
}

install_node_project() {
    local project="$1"
    local mode="$2"
    local project_dir="$WORKSPACE/$project"
    local -a cmd=(npm)

    if [ ! -f "$project_dir/package.json" ]; then
        record_skip "$project (package.json missing)"
        return
    fi

    if [ -d "$project_dir/node_modules" ] && (cd "$project_dir" && npm ls --depth=0 >/dev/null 2>&1); then
        echo "  ok $project (already satisfied)"
        return
    fi

    case "$mode" in
        ci)
            cmd+=(ci --no-fund --no-audit)
            ;;
        install)
            cmd+=(install --no-fund --no-audit --package-lock=false)
            ;;
        *)
            record_failure "node install mode: $project"
            return
            ;;
    esac

    echo "  -> $project ($mode)"
    if (cd "$project_dir" && "${cmd[@]}"); then
        echo "  ok $project"
        return
    fi

    if [ "$mode" = "ci" ]; then
        echo "     retrying $project with --legacy-peer-deps"
        if (cd "$project_dir" && npm ci --no-fund --no-audit --legacy-peer-deps); then
            echo "  ok $project"
            return
        fi
    fi

    record_failure "node dependencies: $project"
}

install_pre_commit_hooks() {
    local -a repo_refs=()

    if [ ! -f "$PRE_COMMIT_CONFIG" ] || ! command -v pre-commit >/dev/null 2>&1; then
        echo "Pre-commit: skipped"
        return
    fi

    mapfile -t repo_refs < <(find "$WORKSPACE" -mindepth 1 -maxdepth 2 \( -type d -o -type f \) -name .git | sort)
    for git_ref in "${repo_refs[@]}"; do
        local repo_dir
        repo_dir="$(dirname "$git_ref")"
        if [ ! -f "$repo_dir/.pre-commit-config.yaml" ]; then
            cp "$PRE_COMMIT_CONFIG" "$repo_dir/.pre-commit-config.yaml"
        fi
        (cd "$repo_dir" && git config --unset-all core.hooksPath 2>/dev/null; pre-commit install --allow-missing-config) >/dev/null 2>&1 || true
    done

    echo "Pre-commit hooks installed for ${#repo_refs[@]} repos"
}

echo "=== BladeAI DevContainer post-create ==="

repair_workspace_venv

echo "Installing Python requirements files..."
for rel_path in "${REQ_PROJECTS[@]}"; do
    install_requirements_file "$rel_path"
done

echo "Installing editable Python projects..."
for entry in "${PY_EDITABLE_PROJECTS[@]}"; do
    IFS="|" read -r project editable_spec groups_csv <<< "$entry"
    install_editable_project "$project" "$editable_spec" "$groups_csv"
done
check_editable_project_collisions

echo "Installing Python dependency-only projects..."
for entry in "${PY_DEP_ONLY_PROJECTS[@]}"; do
    IFS="|" read -r project extras_csv <<< "$entry"
    install_pyproject_dependencies "$project" "$extras_csv"
done

if "$VENV/bin/python" -m pip check >/dev/null 2>&1; then
    echo "Python dependency check passed"
else
    record_failure "python dependency check"
    "$VENV/bin/python" -m pip check || true
fi

echo "Installing Node projects with lockfiles..."
for project in "${NODE_CI_PROJECTS[@]}"; do
    install_node_project "$project" ci
done

echo "Installing Node projects without lockfiles..."
for project in "${NODE_INSTALL_PROJECTS[@]}"; do
    install_node_project "$project" install
done

install_pre_commit_hooks

if [ -f "$HOME/.ssh/config" ]; then
    echo "SSH config: using host-mounted config (read-only)"
else
    echo "SSH config: not found (mount ~/.ssh/config from host)"
fi

HOST_GITCONFIG="$HOME/.gitconfig-host"
if [ -f "$HOST_GITCONFIG" ]; then
    user_name=$(git config -f "$HOST_GITCONFIG" user.name 2>/dev/null || true)
    user_email=$(git config -f "$HOST_GITCONFIG" user.email 2>/dev/null || true)
    [ -n "$user_name" ] && git config --global user.name "$user_name"
    [ -n "$user_email" ] && git config --global user.email "$user_email"
fi
if command -v gh >/dev/null 2>&1; then
    gh auth setup-git 2>/dev/null || true
fi

if [ -w /commandhistory ] || mkdir -p /commandhistory 2>/dev/null; then
    touch /commandhistory/.bash_history 2>/dev/null || true
fi

mapfile -t repo_refs < <(find "$WORKSPACE" -mindepth 1 -maxdepth 2 \( -type d -o -type f \) -name .git | sort)

echo ""
echo "=== DevContainer ready ==="
echo "  Python:     $(python3 --version)"
echo "  Node:       $(node --version)"
echo "  Go:         $(go version 2>/dev/null | cut -d" " -f3 || echo "N/A")"
echo "  gh:         $(gh --version 2>/dev/null | head -1 || echo "N/A")"
echo "  gcloud:     $(gcloud --version 2>/dev/null | head -1 || echo "N/A")"
echo "  uv:         $(uv --version 2>/dev/null || echo "N/A")"
echo "  gitleaks:   $(gitleaks version 2>/dev/null || echo "N/A")"
echo "  claude:     $(claude --version 2>/dev/null || echo "N/A")"
echo "  pre-commit: $(pre-commit --version 2>/dev/null || echo "N/A")"
echo "  pm2:        $(pm2 --version 2>/dev/null || echo "N/A")"
echo "  Playwright: $(python3 -m playwright --version 2>/dev/null || echo "N/A")"
echo "  Workspace:  $WORKSPACE"
echo "  Repos:      ${#repo_refs[@]}"
echo "  Skipped:    ${#SKIPPED[@]}"
echo "  Failures:   ${#FAILURES[@]}"

if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo ""
    echo "Skipped items:"
    printf "  - %s\n" "${SKIPPED[@]}"
fi

if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo ""
    echo "Failed items:"
    printf "  - %s\n" "${FAILURES[@]}"
    exit 1
fi
