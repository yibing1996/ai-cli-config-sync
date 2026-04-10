#!/usr/bin/env bash
# uninstall.sh — cli-config-sync 卸载脚本

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

echo ""
echo "🗑️  cli-config-sync 卸载程序"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

REMOVED=0

# 卸载 GitHub Copilot CLI / Claude Code CLI 版本
CLAUDE_SKILL="$HOME/.claude/skills/cli-config-sync"
if [ -d "$CLAUDE_SKILL" ]; then
  rm -rf "$CLAUDE_SKILL"
  ok "已卸载：$CLAUDE_SKILL"
  REMOVED=$((REMOVED + 1))
else
  warn "未找到：$CLAUDE_SKILL（已卸载或未安装）"
fi

# 卸载 Codex CLI 版本
CODEX_SKILL="$HOME/.codex/skills/cli-config-sync"
if [ -d "$CODEX_SKILL" ]; then
  rm -rf "$CODEX_SKILL"
  ok "已卸载：$CODEX_SKILL"
  REMOVED=$((REMOVED + 1))
else
  warn "未找到：$CODEX_SKILL（已卸载或未安装）"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "卸载完成，共移除 $REMOVED 个 Skill"
echo ""
echo "📝 注意：以下文件/目录未自动删除（含您的同步数据），请按需手动删除："
echo "   ~/.cli-sync/         — 同步配置和辅助脚本"
echo "   ~/.cli-sync-repo/    — 本地 Git 仓库"
echo ""
