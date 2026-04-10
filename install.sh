#!/usr/bin/env bash
# install.sh — cli-config-sync 一键安装脚本
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/cli-config-sync/main/install.sh)
#   或：bash install.sh（在项目目录下运行）

set -e

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── 定位 SKILL.md 文件 ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SKILL_SRC="$SCRIPT_DIR/skills/cli-config-sync/SKILL.md"
CODEX_SKILL_SRC="$SCRIPT_DIR/skills/cli-config-sync-codex/SKILL.md"

# 如果通过 curl 运行，从 GitHub 下载文件
if [ ! -f "$CLAUDE_SKILL_SRC" ]; then
  info "检测到远程安装模式，从 GitHub 下载 Skill 文件..."
  TMPDIR_CLI=$(mktemp -d)
  REPO_URL="https://raw.githubusercontent.com/YOUR_USERNAME/cli-config-sync/main"
  
  mkdir -p "$TMPDIR_CLI/skills/cli-config-sync" "$TMPDIR_CLI/skills/cli-config-sync-codex"
  
  if command -v curl &> /dev/null; then
    curl -fsSL "$REPO_URL/skills/cli-config-sync/SKILL.md" \
      -o "$TMPDIR_CLI/skills/cli-config-sync/SKILL.md" || err "下载失败，请检查网络或访问 GitHub"
    curl -fsSL "$REPO_URL/skills/cli-config-sync-codex/SKILL.md" \
      -o "$TMPDIR_CLI/skills/cli-config-sync-codex/SKILL.md" 2>/dev/null || true
  elif command -v wget &> /dev/null; then
    wget -q "$REPO_URL/skills/cli-config-sync/SKILL.md" \
      -O "$TMPDIR_CLI/skills/cli-config-sync/SKILL.md" || err "下载失败，请检查网络"
    wget -q "$REPO_URL/skills/cli-config-sync-codex/SKILL.md" \
      -O "$TMPDIR_CLI/skills/cli-config-sync-codex/SKILL.md" 2>/dev/null || true
  else
    err "未找到 curl 或 wget，请手动下载：https://github.com/YOUR_USERNAME/cli-config-sync"
  fi
  
  CLAUDE_SKILL_SRC="$TMPDIR_CLI/skills/cli-config-sync/SKILL.md"
  CODEX_SKILL_SRC="$TMPDIR_CLI/skills/cli-config-sync-codex/SKILL.md"
fi

echo ""
echo "🚀 cli-config-sync 安装程序"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 检测并安装到各 CLI ────────────────────────────────────────────────────────
INSTALLED=0

# GitHub Copilot CLI / Claude Code CLI（共用 ~/.claude/skills/）
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
if [ -d "$HOME/.claude" ]; then
  info "检测到 GitHub Copilot CLI / Claude Code CLI（~/.claude/）"
  mkdir -p "$CLAUDE_SKILLS_DIR/cli-config-sync"
  cp "$CLAUDE_SKILL_SRC" "$CLAUDE_SKILLS_DIR/cli-config-sync/SKILL.md"
  ok "已安装到 $CLAUDE_SKILLS_DIR/cli-config-sync/SKILL.md"
  INSTALLED=$((INSTALLED + 1))
else
  warn "未检测到 GitHub Copilot CLI / Claude Code CLI（~/.claude/ 不存在，跳过）"
fi

# Codex CLI
CODEX_SKILLS_DIR="$HOME/.codex/skills"
if [ -d "$HOME/.codex" ]; then
  info "检测到 Codex CLI（~/.codex/）"
  if [ -f "$CODEX_SKILL_SRC" ]; then
    mkdir -p "$CODEX_SKILLS_DIR/cli-config-sync"
    cp "$CODEX_SKILL_SRC" "$CODEX_SKILLS_DIR/cli-config-sync/SKILL.md"
    ok "已安装到 $CODEX_SKILLS_DIR/cli-config-sync/SKILL.md"
  else
    # Codex 使用 Claude 版本（逻辑相同）
    mkdir -p "$CODEX_SKILLS_DIR/cli-config-sync"
    cp "$CLAUDE_SKILL_SRC" "$CODEX_SKILLS_DIR/cli-config-sync/SKILL.md"
    ok "已安装到 $CODEX_SKILLS_DIR/cli-config-sync/SKILL.md"
  fi
  INSTALLED=$((INSTALLED + 1))
else
  warn "未检测到 Codex CLI（~/.codex/ 不存在，跳过）"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $INSTALLED -eq 0 ]; then
  err "未检测到任何支持的 CLI 工具，请先安装 GitHub Copilot CLI / Claude Code CLI / Codex CLI"
fi

ok "安装完成！共安装到 $INSTALLED 个 CLI"
echo ""
echo "📖 使用方法："
echo "   在任意 AI CLI 对话中说：「初始化配置同步」"
echo "   或：「setup config sync」"
echo ""
echo "🔗 更多信息：https://github.com/YOUR_USERNAME/cli-config-sync"
echo ""

# 清理临时目录
if [ -n "${TMPDIR_CLI:-}" ]; then
  rm -rf "$TMPDIR_CLI"
fi
