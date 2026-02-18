#!/bin/bash
# Claude Code 完整环境自检脚本
# 用法: bash ~/workspace/.sync/claude-env-check.sh
# 检查所有 MCP、插件、LSP、Hook 是否真正可用

PASS="✅" FAIL="❌" WARN="⚠️ "
pass=0; fail=0; warn=0

ok()   { echo "  $PASS $1"; pass=$((pass+1)); }
fail() { echo "  $FAIL $1"; fail=$((fail+1)); }
warn() { echo "  $WARN $1"; warn=$((warn+1)); }
sec()  { echo ""; echo "━━━ $1 ━━━"; }

sec "Claude Code 本体"
if VER=$(claude --version 2>/dev/null); then
  ok "Claude Code $VER"
else
  fail "claude 命令不存在"
fi

sec "settings.json"
CFG=~/.claude/settings.json
if [ -f "$CFG" ]; then
  ok "文件存在: $CFG"
  MODEL=$(jq -r '.model // "未设置"' "$CFG" 2>/dev/null)
  ok "model = $MODEL"
  PLUGINS_COUNT=$(jq '.enabledPlugins | length' "$CFG" 2>/dev/null)
  ok "启用插件数 = $PLUGINS_COUNT"
else
  fail "settings.json 不存在"
fi

sec "MCP: fetch"
UVX=$HOME/.local/bin/uvx
if [ -x "$UVX" ]; then
  ok "uvx 存在: $UVX"
  if timeout 5 $UVX mcp-server-fetch --help &>/dev/null; then
    ok "uvx mcp-server-fetch 可启动"
  else
    warn "uvx mcp-server-fetch 启动异常（检查网络或 uvx 缓存）"
  fi
else
  fail "uvx 不存在: $UVX"
fi

sec "MCP: playwright"
NPXPATH="$HOME/.nvm/versions/node/v25.6.1/bin/npx"
if [ -x "$NPXPATH" ]; then
  ok "npx 存在: $NPXPATH"
  if $NPXPATH --yes @playwright/mcp@0.0.68 --version &>/dev/null; then
    ok "@playwright/mcp@0.0.68 可运行"
  else
    warn "@playwright/mcp 需要下载或运行失败"
  fi
else
  fail "npx 不存在: $NPXPATH"
fi

sec "MCP: github plugin (需要 GITHUB_PERSONAL_ACCESS_TOKEN)"
TOKEN_ENV=$(printenv GITHUB_PERSONAL_ACCESS_TOKEN 2>/dev/null)
TOKEN_CFG=$(jq -r '.env.GITHUB_PERSONAL_ACCESS_TOKEN // ""' ~/.claude/settings.json 2>/dev/null)
TOKEN_LOCAL=$(jq -r '.env.GITHUB_PERSONAL_ACCESS_TOKEN // ""' ~/.claude/settings.local.json 2>/dev/null)
if [ -n "$TOKEN_ENV" ]; then
  ok "GITHUB_PERSONAL_ACCESS_TOKEN 已在环境变量中"
elif [ -n "$TOKEN_CFG" ]; then
  ok "GITHUB_PERSONAL_ACCESS_TOKEN 在 settings.json"
elif [ -n "$TOKEN_LOCAL" ]; then
  ok "GITHUB_PERSONAL_ACCESS_TOKEN 在 settings.local.json (${TOKEN_LOCAL:0:15}...)"
else
  fail "GITHUB_PERSONAL_ACCESS_TOKEN 未设置 → github MCP 插件无法工作"
  echo "         修复: 运行 'gh auth token' 取值后写入 ~/.claude/settings.local.json 的 env 段"
fi

sec "MCP: context7 plugin"
# context7 不接受 --version，用 jsonrpc initialize 测试（有任何 jsonrpc 响应即为正常）
RESPONSE=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' | \
  timeout 5 $NPXPATH @upstash/context7-mcp 2>/dev/null | head -1)
if echo "$RESPONSE" | grep -q "jsonrpc"; then
  ok "@upstash/context7-mcp 可运行（jsonrpc 响应正常）"
else
  warn "@upstash/context7-mcp 无响应（检查 npx 或网络）"
fi

sec "LSP: pyright-langserver"
if PYRIGHT=$(which pyright-langserver 2>/dev/null); then
  ok "pyright-langserver 存在: $PYRIGHT"
  # 用正确的 LSP Content-Length 协议测试
  MSG='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":null,"capabilities":{}}}'
  MSGLEN=${#MSG}
  RESPONSE=$(printf "Content-Length: %d\r\n\r\n%s" "$MSGLEN" "$MSG" | timeout 4 pyright-langserver --stdio 2>/dev/null | head -5)
  if echo "$RESPONSE" | grep -q "jsonrpc"; then
    ok "pyright-langserver LSP 协议响应正常"
  else
    warn "pyright-langserver 无 LSP 响应（可能是启动慢，实际使用时正常）"
  fi
else
  fail "pyright-langserver 未安装 → 修复: pip install pyright"
fi

sec "LSP: typescript-language-server"
if TSLS=$(which typescript-language-server 2>/dev/null); then
  ok "typescript-language-server 存在: $TSLS"
  MSG='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":null,"capabilities":{}}}'
  MSGLEN=${#MSG}
  RESPONSE=$(printf "Content-Length: %d\r\n\r\n%s" "$MSGLEN" "$MSG" | timeout 4 typescript-language-server --stdio 2>/dev/null | head -5)
  if echo "$RESPONSE" | grep -q "jsonrpc"; then
    ok "typescript-language-server LSP 协议响应正常"
  else
    warn "typescript-language-server 无 LSP 响应（可能是启动慢，实际使用时正常）"
  fi
else
  fail "typescript-language-server 未安装 → 修复: npm install -g typescript-language-server typescript"
fi

sec "Hook: security-guidance"
HOOK_PY=~/.claude/plugins/cache/claude-plugins-official/security-guidance/*/hooks/security_reminder_hook.py
HOOK_FILE=$(ls $HOOK_PY 2>/dev/null | head -1)
if [ -f "$HOOK_FILE" ]; then
  ok "hook 脚本存在: $HOOK_FILE"
  if python3=$(which python3 2>/dev/null); then
    ok "python3 可用: $python3"
    if python3 -m py_compile "$HOOK_FILE" 2>/dev/null; then
      ok "hook 脚本语法正常"
    else
      fail "hook 脚本语法错误"
    fi
  else
    fail "python3 不在 PATH（hook 无法运行）"
  fi
else
  fail "security-guidance hook 脚本不存在"
fi

sec "Hook: hookify"
HOOKIFY_DIR=$(ls -d ~/.claude/plugins/cache/claude-plugins-official/hookify/*/hooks 2>/dev/null | head -1)
if [ -d "$HOOKIFY_DIR" ]; then
  ok "hookify hooks 目录存在: $HOOKIFY_DIR"
  PY_OK=0; PY_FAIL=0
  for f in "$HOOKIFY_DIR"/*.py; do
    [ -f "$f" ] || continue
    if python3 -m py_compile "$f" 2>/dev/null; then
      PY_OK=$((PY_OK+1))
    else
      PY_FAIL=$((PY_FAIL+1))
      fail "$(basename $f) 语法错误"
    fi
  done
  [ $PY_OK -gt 0 ] && ok "$PY_OK 个 hook 脚本语法正常"
else
  warn "hookify hooks 目录不存在"
fi

sec "Skill 插件（纯 Markdown，检查缓存文件）"
for plugin in commit-commands pr-review-toolkit feature-dev code-review frontend-design claude-md-management; do
  COUNT=$(find ~/.claude/plugins/cache/claude-plugins-official/$plugin -name "*.md" 2>/dev/null | wc -l)
  if [ "$COUNT" -gt 0 ]; then
    ok "$plugin: $COUNT 个 skill/command 文件"
  else
    fail "$plugin: 无 .md 文件（插件未下载或路径错误）"
  fi
done

sec "已安装但未启用的插件"
INSTALLED=$(jq -r '.plugins | keys[]' ~/.claude/plugins/installed_plugins.json 2>/dev/null)
ENABLED=$(jq -r '.enabledPlugins | keys[]' ~/.claude/settings.json 2>/dev/null)
DISABLED_COUNT=0
for p in $INSTALLED; do
  name="${p%@*}"
  if ! echo "$ENABLED" | grep -q "$name"; then
    warn "$p 已安装但未启用"
    DISABLED_COUNT=$((DISABLED_COUNT+1))
  fi
done
[ $DISABLED_COUNT -eq 0 ] && ok "所有已安装插件均已启用"

sec "python3 (宿主机 hook 运行时)"
if PY3=$(which python3 2>/dev/null); then
  PY3VER=$(python3 --version 2>&1)
  ok "$PY3VER → $PY3"
else
  fail "python3 不在 PATH（所有 hook 插件均无法运行）"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 通过: $pass"
echo "  ❌ 失败: $fail"
echo "  ⚠️  警告: $warn"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $fail -gt 0 ]; then
  echo "  → 有 $fail 项失败，需要修复"
  exit 1
elif [ $warn -gt 0 ]; then
  echo "  → 有 $warn 项警告，建议检查"
  exit 0
else
  echo "  → 全部通过"
  exit 0
fi
