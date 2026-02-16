#!/bin/bash
# BladeAI workspace auto-sync daemon
# Runs every 5 minutes via cron/systemd
# For each repo: fetch remote, auto-pull if clean, alert if conflicts
#
# Logic:
#   1. git fetch origin
#   2. If local is behind AND working tree is clean → auto pull
#   3. If local is behind AND working tree is dirty → Telegram alert
#   4. If local is ahead → do nothing (user will push when ready)
#   5. If diverged → Telegram alert with instructions

set -euo pipefail

WORKSPACE="/home/simba/workspace"
LOG="/home/simba/workspace/.sync/sync.log"
# Load credentials from workspace .env or bladeai .env
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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

notify() {
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

for repo in "${REPOS[@]}"; do
    dir="$WORKSPACE/$repo"

    # Skip if not a git repo
    [ -d "$dir/.git" ] || continue

    # Fetch remote
    if ! git -C "$dir" fetch origin 2>/dev/null; then
        log "$repo: fetch failed (network?)"
        continue
    fi

    # Get branch name
    branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || continue

    # Compare local vs remote
    local_ref=$(git -C "$dir" rev-parse "$branch" 2>/dev/null) || continue
    remote_ref=$(git -C "$dir" rev-parse "origin/$branch" 2>/dev/null) || continue
    base_ref=$(git -C "$dir" merge-base "$branch" "origin/$branch" 2>/dev/null) || continue

    if [ "$local_ref" = "$remote_ref" ]; then
        # Up to date - nothing to do
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
            else
                log "$repo: pull failed (non-fast-forward?)"
                notify "⚠️ \`$repo\`: pull failed, needs manual merge"
            fi
        else
            # Dirty working tree - can't auto-pull
            log "$repo: behind remote but has uncommitted changes"
            notify "⚠️ \`$repo\`: remote has new commits but local has uncommitted changes.\nRun: \`cd $dir && git stash && git pull && git stash pop\`"
        fi
    elif [ "$remote_ref" = "$base_ref" ]; then
        # Local is ahead - user hasn't pushed yet
        commits=$(git -C "$dir" log --oneline "${remote_ref}..${local_ref}" | wc -l)
        log "$repo: $commits unpushed commit(s)"
        # Don't alert for this - user will push when ready
    else
        # Diverged - needs manual resolution
        log "$repo: DIVERGED from remote - needs manual merge"
        notify "🔴 \`$repo\`: local and remote have diverged!\nRun: \`cd $dir && git pull --rebase\`"
    fi
done
