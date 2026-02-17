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
            .|..|.ssh|.gitconfig-host) continue ;;
        esac
        chown -R "$HOST_UID:$HOST_GID" "$d" 2>/dev/null || true
    done
    chown "$HOST_UID:$HOST_GID" /workspace 2>/dev/null || true
fi

# If args provided, exec them as vscode; otherwise sleep forever
if [ $# -gt 0 ]; then
    exec gosu vscode "$@"
else
    exec gosu vscode sleep infinity
fi
