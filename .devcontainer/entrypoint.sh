#!/bin/bash
# Remap vscode UID/GID to match host user, then drop privileges
set -e

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
CURRENT_UID=$(id -u vscode 2>/dev/null || echo 1000)
CURRENT_GID=$(id -g vscode 2>/dev/null || echo 1000)

if [ "$HOST_UID" != "$CURRENT_UID" ] || [ "$HOST_GID" != "$CURRENT_GID" ]; then
    groupmod -g "$HOST_GID" vscode 2>/dev/null || true
    usermod -u "$HOST_UID" -g "$HOST_GID" vscode 2>/dev/null || true
    # Only lightweight chown needed — pyenv and Rust are in /opt and /usr/local
    # Skip read-only bind mounts (.ssh, .gitconfig-host)
    chown "$HOST_UID:$HOST_GID" /home/vscode 2>/dev/null || true
    for d in /home/vscode/.*; do
        case "$(basename "$d")" in
            .|..|.ssh|.gitconfig-host|.claude|.codex|.gemini) continue ;;
        esac
        chown -R "$HOST_UID:$HOST_GID" "$d" 2>/dev/null || true
    done
    chown "$HOST_UID:$HOST_GID" /workspace 2>/dev/null || true
fi

# Named volumes are created as root — always fix ownership regardless of UID remap.
# Include uv's cache volume so post-create can install Python deps immediately.
mkdir -p /home/vscode/.cache /home/vscode/.cache/uv

for d in \
    /home/vscode/.cache \
    /home/vscode/.cache/uv \
    /workspace/.venv \
    /commandhistory \
    /workspace/clawforce/web/node_modules \
    /workspace/clawforce/desktop/node_modules \
    /workspace/clawforce/sdk-js/node_modules \
    /workspace/clawforce-admin/web/node_modules \
    /workspace/clawforce-lobster-fleet/clawforce-plugin/node_modules \
    /workspace/clawforce-lobster-fleet/dashboard-lobster/node_modules \
    /workspace/seedforge/dashboard-admin/node_modules
do
    chown -R "$(id -u vscode):$(id -g vscode)" "$d" 2>/dev/null || true
done

# Docker Desktop exposes the host SSH agent at /run/host-services/ssh-auth.sock.
# Copy the host SSH config into a writable file and rewrite IdentityAgent so
# OpenSSH inside Linux resolves the correct socket path.
mkdir -p /home/vscode/.ssh
if [ -f /home/vscode/.ssh/config-host ]; then
    if grep -q '^[[:space:]]*IdentityAgent[[:space:]]' /home/vscode/.ssh/config-host; then
        sed -E "s#^([[:space:]]*IdentityAgent[[:space:]]+).*\$#\\1${SSH_AUTH_SOCK}#" \
            /home/vscode/.ssh/config-host > /home/vscode/.ssh/config
    else
        cp /home/vscode/.ssh/config-host /home/vscode/.ssh/config
        printf '\nHost *\n  IdentityAgent %s\n' "$SSH_AUTH_SOCK" >> /home/vscode/.ssh/config
    fi
    chown "$(id -u vscode):$(id -g vscode)" /home/vscode/.ssh/config 2>/dev/null || true
    chmod 600 /home/vscode/.ssh/config 2>/dev/null || true
fi

# Docker Desktop exposes the mounted socket as root:root inside Linux containers.
# Add vscode to the socket's group so project-local docker compose commands can
# run from inside the devcontainer without falling back to the host shell.
if [ -S /var/run/docker.sock ]; then
    SOCK_GID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)"
    if [ -n "$SOCK_GID" ] && ! id -G vscode | tr ' ' '\n' | grep -qx "$SOCK_GID"; then
        if [ "$SOCK_GID" = "0" ]; then
            usermod -aG 0 vscode 2>/dev/null || true
        else
            if ! getent group "$SOCK_GID" >/dev/null 2>&1; then
                groupadd -g "$SOCK_GID" dockerhost 2>/dev/null || true
            fi
            usermod -aG "$SOCK_GID" vscode 2>/dev/null || usermod -aG dockerhost vscode 2>/dev/null || true
        fi
    fi
fi

# If args provided, exec them as vscode; otherwise sleep forever
if [ $# -gt 0 ]; then
    exec gosu vscode "$@"
else
    exec gosu vscode sleep infinity
fi
