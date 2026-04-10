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
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── 定位源文件 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SKILL_SRC="$SCRIPT_DIR/skills/cli-config-sync/SKILL.md"
CODEX_SKILL_SRC="$SCRIPT_DIR/skills/cli-config-sync-codex/SKILL.md"
PUSH_SH_SRC="$SCRIPT_DIR/scripts/push.sh"
PULL_SH_SRC="$SCRIPT_DIR/scripts/pull.sh"

# 如果通过 curl 运行，从 GitHub 下载文件
if [ ! -f "$CLAUDE_SKILL_SRC" ]; then
  info "检测到远程安装模式，从 GitHub 下载文件..."
  TMPDIR_CLI=$(mktemp -d)
  REPO_URL="https://raw.githubusercontent.com/YOUR_USERNAME/cli-config-sync/main"

  mkdir -p "$TMPDIR_CLI/skills/cli-config-sync" "$TMPDIR_CLI/skills/cli-config-sync-codex" "$TMPDIR_CLI/scripts"

  _download() {
    local path="$1" dest="$2"
    if command -v curl &> /dev/null; then
      curl -fsSL "$REPO_URL/$path" -o "$dest" 2>/dev/null || true
    elif command -v wget &> /dev/null; then
      wget -q "$REPO_URL/$path" -O "$dest" 2>/dev/null || true
    fi
  }

  _download "skills/cli-config-sync/SKILL.md" "$TMPDIR_CLI/skills/cli-config-sync/SKILL.md"
  _download "skills/cli-config-sync-codex/SKILL.md" "$TMPDIR_CLI/skills/cli-config-sync-codex/SKILL.md"
  _download "scripts/push.sh" "$TMPDIR_CLI/scripts/push.sh"
  _download "scripts/pull.sh" "$TMPDIR_CLI/scripts/pull.sh"

  [ -f "$TMPDIR_CLI/skills/cli-config-sync/SKILL.md" ] || err "下载失败，请检查网络或访问 GitHub"

  CLAUDE_SKILL_SRC="$TMPDIR_CLI/skills/cli-config-sync/SKILL.md"
  CODEX_SKILL_SRC="$TMPDIR_CLI/skills/cli-config-sync-codex/SKILL.md"
  PUSH_SH_SRC="$TMPDIR_CLI/scripts/push.sh"
  PULL_SH_SRC="$TMPDIR_CLI/scripts/pull.sh"
fi

echo ""
echo "🚀 cli-config-sync 安装程序"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 安装核心脚本到 ~/.cli-sync/ ──────────────────────────────────────────────
SCRIPTS_DIR="$HOME/.cli-sync"
mkdir -p "$SCRIPTS_DIR"

if [ -f "$PUSH_SH_SRC" ]; then
  cp "$PUSH_SH_SRC" "$SCRIPTS_DIR/push.sh"
  chmod +x "$SCRIPTS_DIR/push.sh"
  ok "已安装 push.sh → $SCRIPTS_DIR/push.sh"
else
  warn "未找到 push.sh 源文件（将在首次 Setup 时由 Skill 生成）"
fi

if [ -f "$PULL_SH_SRC" ]; then
  cp "$PULL_SH_SRC" "$SCRIPTS_DIR/pull.sh"
  chmod +x "$SCRIPTS_DIR/pull.sh"
  ok "已安装 pull.sh → $SCRIPTS_DIR/pull.sh"
else
  warn "未找到 pull.sh 源文件（将在首次 Setup 时由 Skill 生成）"
fi

# ── 检测并安装 Skill 到各 CLI ────────────────────────────────────────────────
INSTALLED=0

# GitHub Copilot CLI / Claude Code CLI（共用 ~/.claude/skills/）
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
if [ -d "$HOME/.claude" ]; then
  info "检测到 GitHub Copilot CLI / Claude Code CLI（~/.claude/）"
  mkdir -p "$CLAUDE_SKILLS_DIR/cli-config-sync"
  cp "$CLAUDE_SKILL_SRC" "$CLAUDE_SKILLS_DIR/cli-config-sync/SKILL.md"
  ok "已安装 Skill → $CLAUDE_SKILLS_DIR/cli-config-sync/SKILL.md"
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
    ok "已安装 Skill → $CODEX_SKILLS_DIR/cli-config-sync/SKILL.md"
  else
    mkdir -p "$CODEX_SKILLS_DIR/cli-config-sync"
    cp "$CLAUDE_SKILL_SRC" "$CODEX_SKILLS_DIR/cli-config-sync/SKILL.md"
    ok "已安装 Skill → $CODEX_SKILLS_DIR/cli-config-sync/SKILL.md（使用通用版本）"
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
echo "📦 核心脚本：$SCRIPTS_DIR/push.sh, $SCRIPTS_DIR/pull.sh"
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
