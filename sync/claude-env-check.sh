#!/bin/bash
# Claude Code 完整环境自检脚本
# 用法: bash ~/workspace/dev-env/sync/claude-env-check.sh
# 真正的 MCP 配置在 ~/.claude.json，插件/LSP/Hook 在 ~/.claude/settings.json

pass=0; fail=0; warn=0
ok()   { echo "  ✅ $1"; pass=$((pass+1)); }
fail() { echo "  ❌ $1"; fail=$((fail+1)); }
warn() { echo "  ⚠️  $1"; warn=$((warn+1)); }
sec()  { echo ""; echo "━━━ $1 ━━━"; }

CLAUDE_MAIN=~/.claude.json
CLAUDE_CFG=~/.claude/settings.json
NPXPATH="$HOME/.nvm/versions/node/v25.6.1/bin/npx"

sec "Claude Code 本体"
if VER=$(claude --version 2>/dev/null); then
  ok "$VER"
else
  fail "claude 命令不存在"
fi

sec "MCP 服务器（来源: ~/.claude.json）"
if [ ! -f "$CLAUDE_MAIN" ]; then
  fail "~/.claude.json 不存在"
else
  # 获取配置的 MCP 列表
  MCP_NAMES=$(python3 -c "
import json
with open('$CLAUDE_MAIN') as f:
    d = json.load(f)
servers = d.get('mcpServers', {})
for name in servers:
    print(name)
" 2>/dev/null)

  ok "已配置 $(echo "$MCP_NAMES" | wc -l) 个 MCP"

  # 获取实际运行中的进程关键词
  RUNNING=$(ps aux | grep -E "node.*mcp|npx.*mcp|uvx.*fetch" | grep -v grep | tr '\n' '|')

  for name in $MCP_NAMES; do
    case "$name" in
      github)
        if echo "$RUNNING" | grep -q "mcp-server-github\|modelcontextprotocol/server-github"; then
          # 检查 token
          TOKEN=$(python3 -c "
import json
with open('$CLAUDE_MAIN') as f:
    d = json.load(f)
t = d.get('mcpServers',{}).get('github',{}).get('env',{}).get('GITHUB_PERSONAL_ACCESS_TOKEN','')
print(t[:6] if t else '')
" 2>/dev/null)
          [ -n "$TOKEN" ] && ok "github: 运行中 (token: ${TOKEN}...)" || warn "github: 运行中但 token 为空"
        else
          fail "github: 未运行"
        fi
        ;;
      notion)
        TOKEN=$(python3 -c "
import json
with open('$CLAUDE_MAIN') as f:
    d = json.load(f)
h = d.get('mcpServers',{}).get('notion',{}).get('env',{}).get('OPENAPI_MCP_HEADERS','')
import re
m = re.search(r'Bearer (\S+)', h)
t = m.group(1) if m else ''
print(t[:6] if t and not t.startswith('\${') else 'placeholder')
" 2>/dev/null)
        if [ "$TOKEN" = "placeholder" ] || [ -z "$TOKEN" ]; then
          warn "notion: 配置了但 NOTION_TOKEN 未设置（API 调用会失败）"
        elif echo "$RUNNING" | grep -q "notion"; then
          ok "notion: 运行中 (token: ${TOKEN}...)"
        else
          fail "notion: token 有但进程未运行"
        fi
        ;;
      fetch)
        if echo "$RUNNING" | grep -q "uvx.*fetch\|mcp-server-fetch"; then
          ok "fetch: 运行中"
        else
          warn "fetch: 未运行（重启后生效）"
        fi
        ;;
      docker)
        if echo "$RUNNING" | grep -q "docker-mcp"; then
          ok "docker: 运行中"
        else
          warn "docker: 未运行（Linux 无头服务器无 Docker Desktop，属正常）"
        fi
        ;;
      playwright)
        if echo "$RUNNING" | grep -q "playwright-mcp\|playwright/mcp"; then
          ok "playwright: 运行中"
        else
          fail "playwright: 未运行"
        fi
        ;;
      cloudflare-*)
        label="${name#cloudflare-}"
        if echo "$RUNNING" | grep -q "$label\|cloudflare"; then
          ok "$name: 运行中"
        else
          fail "$name: 未运行"
        fi
        ;;
      *)
        if echo "$RUNNING" | grep -qi "$name"; then
          ok "$name: 运行中"
        else
          warn "$name: 状态未知（检查进程）"
        fi
        ;;
    esac
  done
fi

sec "插件（来源: ~/.claude/settings.json）"
if [ ! -f "$CLAUDE_CFG" ]; then
  fail "~/.claude/settings.json 不存在"
else
  ENABLED=$(python3 -c "
import json
with open('$CLAUDE_CFG') as f:
    d = json.load(f)
plugins = d.get('enabledPlugins', {})
for k,v in plugins.items():
    if v: print(k.split('@')[0])
" 2>/dev/null)
  COUNT=$(echo "$ENABLED" | grep -c .)
  ok "已启用 $COUNT 个插件: $(echo $ENABLED | tr '\n' ' ')"
fi

sec "LSP 服务器"
if PYRIGHT=$(which pyright-langserver 2>/dev/null); then
  ok "pyright-langserver: $PYRIGHT"
else
  fail "pyright-langserver 未安装 → pip install pyright"
fi
if TSLS=$(which typescript-language-server 2>/dev/null); then
  ok "typescript-language-server: $TSLS"
else
  fail "typescript-language-server 未安装 → npm install -g typescript-language-server typescript"
fi

sec "Hook 脚本（python3 运行时）"
PYTHON3=$(which python3 2>/dev/null)
if [ -n "$PYTHON3" ]; then
  ok "python3: $PYTHON3 ($(python3 --version 2>&1))"
else
  fail "python3 不在 PATH（所有 hook 插件均无法运行）"
fi

HOOK_PY=$(ls ~/.claude/plugins/cache/claude-plugins-official/security-guidance/*/hooks/security_reminder_hook.py 2>/dev/null | head -1)
if [ -f "$HOOK_PY" ]; then
  python3 -m py_compile "$HOOK_PY" 2>/dev/null && ok "security-guidance hook 语法正常" || fail "security-guidance hook 语法错误"
else
  fail "security-guidance hook 脚本不存在"
fi

HOOKIFY_DIR=$(ls -d ~/.claude/plugins/cache/claude-plugins-official/hookify/*/hooks 2>/dev/null | head -1)
if [ -d "$HOOKIFY_DIR" ]; then
  ERR=0
  for f in "$HOOKIFY_DIR"/*.py; do
    [ -f "$f" ] || continue
    python3 -m py_compile "$f" 2>/dev/null || ERR=$((ERR+1))
  done
  [ $ERR -eq 0 ] && ok "hookify hooks 全部语法正常" || fail "hookify 有 $ERR 个脚本语法错误"
else
  warn "hookify hooks 目录不存在"
fi

sec "Skill 插件缓存"
SKILL_OK=0; SKILL_FAIL=0
for plugin in commit-commands pr-review-toolkit feature-dev code-review frontend-design claude-md-management; do
  COUNT=$(find ~/.claude/plugins/cache/claude-plugins-official/$plugin -name "*.md" 2>/dev/null | wc -l)
  if [ "$COUNT" -gt 0 ]; then
    SKILL_OK=$((SKILL_OK+1))
  else
    SKILL_FAIL=$((SKILL_FAIL+1))
    fail "$plugin: 无缓存文件"
  fi
done
[ $SKILL_OK -gt 0 ] && ok "$SKILL_OK 个 skill 插件缓存正常"

sec "已安装但未启用的插件"
INSTALLED=$(python3 -c "
import json
with open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')) as f:
    d = json.load(f)
for k in d.get('plugins', {}):
    print(k.split('@')[0])
" 2>/dev/null)
ENABLED_NAMES=$(python3 -c "
import json
with open(os.path.expanduser('~/.claude/settings.json')) as f:
    d = json.load(f)
for k in d.get('enabledPlugins', {}):
    print(k.split('@')[0])
" 2>/dev/null)
DISABLED=0
for p in $INSTALLED; do
  echo "$ENABLED_NAMES" | grep -qx "$p" || { warn "$p 已安装但未启用"; DISABLED=$((DISABLED+1)); }
done
[ $DISABLED -eq 0 ] && ok "所有已安装插件均已启用"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  ✅ 通过: %d   ❌ 失败: %d   ⚠️  警告: %d\n" "$pass" "$fail" "$warn"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ $fail -gt 0 ] && exit 1 || exit 0
