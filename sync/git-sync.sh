#!/bin/bash
# BladeAI workspace auto-sync daemon
# Runs every 5 minutes via docker-compose sidecar or host cron
# For each repo: fetch remote, auto-pull if clean, alert if conflicts
#
# Logic:
#   1. git fetch origin
#   2. If local is behind AND working tree is clean → auto pull
#   3. If local is behind AND working tree is dirty → Telegram alert
#   4. If local is ahead → do nothing (user will push when ready)
#   5. If diverged → Telegram alert with instructions

set -euo pipefail

# Auto-detect container vs host environment
if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    WORKSPACE="/workspace"
else
    WORKSPACE="${WORKSPACE:-$HOME/workspace}"
fi

LOCKFILE="$WORKSPACE/.sync/git-sync.lock"
LOG="$WORKSPACE/.sync/sync.log"

# Prevent concurrent runs (container=root, host=user — handle cross-user lock)
mkdir -p "$(dirname "$LOCKFILE")"
if [ -f "$LOCKFILE" ] && [ ! -w "$LOCKFILE" ]; then
    rm -f "$LOCKFILE" 2>/dev/null || true
fi
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "[git-sync] Another instance running, skipping"
    exit 0
fi

# Load Telegram credentials
ENV_FILE="$WORKSPACE/bladeai/.env"
if [ -f "$ENV_FILE" ]; then
    TG_BOT_TOKEN=$(grep '^TG_BOT_TOKEN=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
    TG_CHAT_ID=$(grep '^TG_CHAT_ID=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
else
    TG_BOT_TOKEN=""
    TG_CHAT_ID=""
fi
HOSTNAME=$(hostname -s)

REPOS=(bladeai dev-env clawforce crypto-backtest quant-backtest quant-lab ntws
    longxia-market ig-recruit-radar xai-radar claude-memory
    ai-expert-monitor whisper-vocab)

log() {
    mkdir -p "$(dirname "$LOG")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

notify() {
    [ -z "$TG_BOT_TOKEN" ] && return
    local msg="🔄 *Git Sync ($HOSTNAME)*\n$1"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d text="$msg" \
        -d parse_mode="Markdown" \
        > /dev/null 2>&1 || true
}

# Log rotation (keep under 500 lines)
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null)" -gt 500 ]; then
    tail -200 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

# Counters for cycle summary (printed to stdout for docker logs)
_ok=0 _pulled=0 _errors=0 _dirty=0 _ahead=0 _diverged=0 _skipped=0

for repo in "${REPOS[@]}"; do
    dir="$WORKSPACE/$repo"

    # Skip if not a git repo
    if [ ! -d "$dir/.git" ]; then
        _skipped=$((_skipped+1))
        continue
    fi

    # Fetch remote
    if ! git -C "$dir" fetch origin 2>/dev/null; then
        log "$repo: fetch failed (network?)"
        _errors=$((_errors+1))
        continue
    fi

    # Get branch name
    branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || { _skipped=$((_skipped+1)); continue; }

    # Compare local vs remote
    local_ref=$(git -C "$dir" rev-parse "$branch" 2>/dev/null) || { _skipped=$((_skipped+1)); continue; }
    remote_ref=$(git -C "$dir" rev-parse "origin/$branch" 2>/dev/null) || { _skipped=$((_skipped+1)); continue; }
    base_ref=$(git -C "$dir" merge-base "$branch" "origin/$branch" 2>/dev/null) || { _skipped=$((_skipped+1)); continue; }

    if [ "$local_ref" = "$remote_ref" ]; then
        # Up to date - nothing to do
        _ok=$((_ok+1))
        continue
    fi

    # Check if working tree is clean
    is_clean=true
    if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
        is_clean=false
    fi

    if [ "$local_ref" = "$base_ref" ]; then
        # Local is behind remote
        if $is_clean; then
            # Safe to auto-pull
            if git -C "$dir" pull --ff-only origin "$branch" 2>/dev/null; then
                commits=$(git -C "$dir" log --oneline "${local_ref}..${remote_ref}" | wc -l)
                log "$repo: auto-pulled $commits new commit(s)"
                notify "✅ \`$repo\`: auto-pulled $commits commit(s)"
                _pulled=$((_pulled+1))
            else
                log "$repo: pull failed (non-fast-forward?)"
                notify "⚠️ \`$repo\`: pull failed, needs manual merge"
                _errors=$((_errors+1))
            fi
        else
            # Dirty working tree - can't auto-pull
            log "$repo: behind remote but has uncommitted changes"
            notify "⚠️ \`$repo\`: remote has new commits but local has uncommitted changes.\nRun: \`cd $dir && git stash && git pull && git stash pop\`"
            _dirty=$((_dirty+1))
        fi
    elif [ "$remote_ref" = "$base_ref" ]; then
        # Local is ahead - user hasn't pushed yet
        commits=$(git -C "$dir" log --oneline "${remote_ref}..${local_ref}" | wc -l)
        log "$repo: $commits unpushed commit(s)"
        # Don't alert for this - user will push when ready
        _ahead=$((_ahead+1))
    else
        # Diverged - needs manual resolution
        log "$repo: DIVERGED from remote - needs manual merge"
        notify "🔴 \`$repo\`: local and remote have diverged!\nRun: \`cd $dir && git pull --rebase\`"
        _diverged=$((_diverged+1))
    fi
done

# Print cycle summary to stdout (visible in docker logs)
_ts=$(date '+%Y-%m-%d %H:%M:%S')
_summary="[git-sync] $_ts — ${#REPOS[@]} repos: ${_ok} ok"
[ $_pulled -gt 0 ]  && _summary+=", $_pulled pulled"
[ $_errors -gt 0 ]  && _summary+=", $_errors errors"
[ $_dirty -gt 0 ]   && _summary+=", $_dirty dirty"
[ $_ahead -gt 0 ]   && _summary+=", $_ahead ahead"
[ $_diverged -gt 0 ] && _summary+=", $_diverged diverged"
[ $_skipped -gt 0 ] && _summary+=", $_skipped skipped"
echo "$_summary"
