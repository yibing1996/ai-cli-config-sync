#!/usr/bin/env bash
# uninstall.sh — ai-cli-config-sync 卸载脚本

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

echo ""
echo "🗑️  ai-cli-config-sync 卸载程序"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

REMOVED=0
SKILL_NAME="ai-cli-config-sync"
LEGACY_SKILL_NAME="cli-config-sync"

# 卸载 GitHub Copilot CLI / Claude Code CLI 版本
for CLAUDE_SKILL in "$HOME/.claude/skills/$SKILL_NAME" "$HOME/.claude/skills/$LEGACY_SKILL_NAME"; do
  if [ -d "$CLAUDE_SKILL" ]; then
    rm -rf "$CLAUDE_SKILL"
    ok "已卸载：$CLAUDE_SKILL"
    REMOVED=$((REMOVED + 1))
  else
    warn "未找到：$CLAUDE_SKILL（已卸载或未安装）"
  fi
done

# 卸载 Codex CLI 版本
for CODEX_SKILL in "$HOME/.codex/skills/$SKILL_NAME" "$HOME/.codex/skills/$LEGACY_SKILL_NAME"; do
  if [ -d "$CODEX_SKILL" ]; then
    rm -rf "$CODEX_SKILL"
    ok "已卸载：$CODEX_SKILL"
    REMOVED=$((REMOVED + 1))
  else
    warn "未找到：$CODEX_SKILL（已卸载或未安装）"
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "卸载完成，共移除 $REMOVED 个 Skill"
echo ""
echo "📝 注意：以下文件/目录未自动删除（含您的同步数据），请按需手动删除："
echo "   ~/.cli-sync/         — 同步配置以及 Bash / PowerShell 辅助脚本"
echo "   ~/.cli-sync-repo/    — 本地 Git 仓库"
echo ""
