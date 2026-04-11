#!/usr/bin/env bash
# install.sh — ai-cli-config-sync 一键安装脚本
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh)
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
INSTALL_SH_SRC="$SCRIPT_DIR/install.sh"
INSTALL_PS1_SRC="$SCRIPT_DIR/install.ps1"
CLAUDE_SKILL_SRC="$SCRIPT_DIR/skills/ai-cli-config-sync/SKILL.md"
CODEX_SKILL_SRC="$SCRIPT_DIR/skills/ai-cli-config-sync-codex/SKILL.md"
PUSH_SH_SRC="$SCRIPT_DIR/scripts/push.sh"
PULL_SH_SRC="$SCRIPT_DIR/scripts/pull.sh"
SETUP_SH_SRC="$SCRIPT_DIR/scripts/setup.sh"
SYNC_SH_SRC="$SCRIPT_DIR/scripts/sync.sh"
STATUS_SH_SRC="$SCRIPT_DIR/scripts/status.sh"
ENABLE_AUTO_SYNC_SH_SRC="$SCRIPT_DIR/scripts/enable-auto-sync.sh"
RUNTIME_PS1_SRC="$SCRIPT_DIR/scripts/runtime.ps1"
PUSH_PS1_SRC="$SCRIPT_DIR/scripts/push.ps1"
PULL_PS1_SRC="$SCRIPT_DIR/scripts/pull.ps1"
SETUP_PS1_SRC="$SCRIPT_DIR/scripts/setup.ps1"
SYNC_PS1_SRC="$SCRIPT_DIR/scripts/sync.ps1"
STATUS_PS1_SRC="$SCRIPT_DIR/scripts/status.ps1"
ENABLE_AUTO_SYNC_PS1_SRC="$SCRIPT_DIR/scripts/enable-auto-sync.ps1"

SKILL_NAME="ai-cli-config-sync"
LEGACY_SKILL_NAME="cli-config-sync"

# 如果通过 curl 运行，从 GitHub 下载文件
if [ ! -f "$CLAUDE_SKILL_SRC" ]; then
  info "检测到远程安装模式，从 GitHub 下载文件..."
  TMPDIR_CLI=$(mktemp -d)
  REPO_URL="https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main"

  mkdir -p "$TMPDIR_CLI/skills/ai-cli-config-sync" "$TMPDIR_CLI/skills/ai-cli-config-sync-codex" "$TMPDIR_CLI/scripts"

  _download() {
    local path="$1" dest="$2"
    if command -v curl &> /dev/null; then
      curl -fsSL "$REPO_URL/$path" -o "$dest" 2>/dev/null || true
    elif command -v wget &> /dev/null; then
      wget -q "$REPO_URL/$path" -O "$dest" 2>/dev/null || true
    fi
  }

  _download "install.sh" "$TMPDIR_CLI/install.sh"
  _download "install.ps1" "$TMPDIR_CLI/install.ps1"
  _download "skills/ai-cli-config-sync/SKILL.md" "$TMPDIR_CLI/skills/ai-cli-config-sync/SKILL.md"
  _download "skills/ai-cli-config-sync-codex/SKILL.md" "$TMPDIR_CLI/skills/ai-cli-config-sync-codex/SKILL.md"
  _download "scripts/push.sh" "$TMPDIR_CLI/scripts/push.sh"
  _download "scripts/pull.sh" "$TMPDIR_CLI/scripts/pull.sh"
  _download "scripts/setup.sh" "$TMPDIR_CLI/scripts/setup.sh"
  _download "scripts/sync.sh" "$TMPDIR_CLI/scripts/sync.sh"
  _download "scripts/status.sh" "$TMPDIR_CLI/scripts/status.sh"
  _download "scripts/enable-auto-sync.sh" "$TMPDIR_CLI/scripts/enable-auto-sync.sh"
  _download "scripts/runtime.ps1" "$TMPDIR_CLI/scripts/runtime.ps1"
  _download "scripts/push.ps1" "$TMPDIR_CLI/scripts/push.ps1"
  _download "scripts/pull.ps1" "$TMPDIR_CLI/scripts/pull.ps1"
  _download "scripts/setup.ps1" "$TMPDIR_CLI/scripts/setup.ps1"
  _download "scripts/sync.ps1" "$TMPDIR_CLI/scripts/sync.ps1"
  _download "scripts/status.ps1" "$TMPDIR_CLI/scripts/status.ps1"
  _download "scripts/enable-auto-sync.ps1" "$TMPDIR_CLI/scripts/enable-auto-sync.ps1"

  [ -f "$TMPDIR_CLI/skills/ai-cli-config-sync/SKILL.md" ] || err "下载失败，请检查网络或访问 GitHub"
  [ -f "$TMPDIR_CLI/install.sh" ] || err "下载 install.sh 失败，请检查网络或手动 clone 项目后运行"
  [ -f "$TMPDIR_CLI/install.ps1" ] || err "下载 install.ps1 失败，请检查网络或手动 clone 项目后运行"

  INSTALL_SH_SRC="$TMPDIR_CLI/install.sh"
  INSTALL_PS1_SRC="$TMPDIR_CLI/install.ps1"
  CLAUDE_SKILL_SRC="$TMPDIR_CLI/skills/ai-cli-config-sync/SKILL.md"
  CODEX_SKILL_SRC="$TMPDIR_CLI/skills/ai-cli-config-sync-codex/SKILL.md"
  PUSH_SH_SRC="$TMPDIR_CLI/scripts/push.sh"
  PULL_SH_SRC="$TMPDIR_CLI/scripts/pull.sh"
  SETUP_SH_SRC="$TMPDIR_CLI/scripts/setup.sh"
  SYNC_SH_SRC="$TMPDIR_CLI/scripts/sync.sh"
  STATUS_SH_SRC="$TMPDIR_CLI/scripts/status.sh"
  ENABLE_AUTO_SYNC_SH_SRC="$TMPDIR_CLI/scripts/enable-auto-sync.sh"
  RUNTIME_PS1_SRC="$TMPDIR_CLI/scripts/runtime.ps1"
  PUSH_PS1_SRC="$TMPDIR_CLI/scripts/push.ps1"
  PULL_PS1_SRC="$TMPDIR_CLI/scripts/pull.ps1"
  SETUP_PS1_SRC="$TMPDIR_CLI/scripts/setup.ps1"
  SYNC_PS1_SRC="$TMPDIR_CLI/scripts/sync.ps1"
  STATUS_PS1_SRC="$TMPDIR_CLI/scripts/status.ps1"
  ENABLE_AUTO_SYNC_PS1_SRC="$TMPDIR_CLI/scripts/enable-auto-sync.ps1"
fi

echo ""
echo "🚀 ai-cli-config-sync 安装程序"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 安装核心脚本到 ~/.cli-sync/ ──────────────────────────────────────────────
SCRIPTS_DIR="$HOME/.cli-sync"
mkdir -p "$SCRIPTS_DIR"

install_exec_script() {
  local src="$1" dst="$2" name="$3"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    ok "已安装 $name → $dst"
  else
    err "未找到 $name，安装中止（远程下载可能失败，请检查网络或手动 clone 项目后运行 install.sh）"
  fi
}

install_copy_script() {
  local src="$1" dst="$2" name="$3"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    ok "已安装 $name → $dst"
  else
    err "未找到 $name，安装中止（远程下载可能失败，请检查网络或手动 clone 项目后运行 install.sh）"
  fi
}

install_exec_script "$INSTALL_SH_SRC" "$SCRIPTS_DIR/install.sh" "install.sh"
install_copy_script "$INSTALL_PS1_SRC" "$SCRIPTS_DIR/install.ps1" "install.ps1"
install_exec_script "$PUSH_SH_SRC" "$SCRIPTS_DIR/push.sh" "push.sh"
install_exec_script "$PULL_SH_SRC" "$SCRIPTS_DIR/pull.sh" "pull.sh"
install_exec_script "$SETUP_SH_SRC" "$SCRIPTS_DIR/setup.sh" "setup.sh"
install_exec_script "$SYNC_SH_SRC" "$SCRIPTS_DIR/sync.sh" "sync.sh"
install_exec_script "$STATUS_SH_SRC" "$SCRIPTS_DIR/status.sh" "status.sh"
install_exec_script "$ENABLE_AUTO_SYNC_SH_SRC" "$SCRIPTS_DIR/enable-auto-sync.sh" "enable-auto-sync.sh"
install_copy_script "$RUNTIME_PS1_SRC" "$SCRIPTS_DIR/runtime.ps1" "runtime.ps1"
install_copy_script "$PUSH_PS1_SRC" "$SCRIPTS_DIR/push.ps1" "push.ps1"
install_copy_script "$PULL_PS1_SRC" "$SCRIPTS_DIR/pull.ps1" "pull.ps1"
install_copy_script "$SETUP_PS1_SRC" "$SCRIPTS_DIR/setup.ps1" "setup.ps1"
install_copy_script "$SYNC_PS1_SRC" "$SCRIPTS_DIR/sync.ps1" "sync.ps1"
install_copy_script "$STATUS_PS1_SRC" "$SCRIPTS_DIR/status.ps1" "status.ps1"
install_copy_script "$ENABLE_AUTO_SYNC_PS1_SRC" "$SCRIPTS_DIR/enable-auto-sync.ps1" "enable-auto-sync.ps1"

# ── 检测并安装 Skill 到各 CLI ────────────────────────────────────────────────
INSTALLED=0

# Claude Code CLI
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
if [ -d "$HOME/.claude" ]; then
  info "检测到 Claude Code CLI（~/.claude/）"
else
  info "未检测到 ~/.claude/ 目录，将自动创建（Claude Code 首次运行后即可使用 Skill）"
fi
if [ -d "$CLAUDE_SKILLS_DIR/$LEGACY_SKILL_NAME" ] && [ "$LEGACY_SKILL_NAME" != "$SKILL_NAME" ]; then
  rm -rf "$CLAUDE_SKILLS_DIR/$LEGACY_SKILL_NAME"
  info "已移除旧版 Skill 目录 → $CLAUDE_SKILLS_DIR/$LEGACY_SKILL_NAME"
fi
mkdir -p "$CLAUDE_SKILLS_DIR/$SKILL_NAME"
cp "$CLAUDE_SKILL_SRC" "$CLAUDE_SKILLS_DIR/$SKILL_NAME/SKILL.md"
ok "已安装 Skill → $CLAUDE_SKILLS_DIR/$SKILL_NAME/SKILL.md"
INSTALLED=$((INSTALLED + 1))

# GitHub Copilot CLI
if [ -d "$HOME/.copilot" ]; then
  info "检测到 GitHub Copilot CLI（~/.copilot/），其受支持配置将由 ~/.cli-sync/push.sh 和 pull.sh 同步"
else
  info "未检测到 ~/.copilot/ 目录；后续安装 GitHub Copilot CLI 后，push/pull 会自动识别并同步其受支持配置"
fi

# Codex CLI
CODEX_SKILLS_DIR="$HOME/.codex/skills"
if [ -d "$HOME/.codex" ]; then
  info "检测到 Codex CLI（~/.codex/）"
else
  info "未检测到 ~/.codex/ 目录，将自动创建（CLI 首次运行后即可使用 Skill）"
fi
if [ -d "$CODEX_SKILLS_DIR/$LEGACY_SKILL_NAME" ] && [ "$LEGACY_SKILL_NAME" != "$SKILL_NAME" ]; then
  rm -rf "$CODEX_SKILLS_DIR/$LEGACY_SKILL_NAME"
  info "已移除旧版 Skill 目录 → $CODEX_SKILLS_DIR/$LEGACY_SKILL_NAME"
fi
if [ -f "$CODEX_SKILL_SRC" ]; then
  mkdir -p "$CODEX_SKILLS_DIR/$SKILL_NAME"
  cp "$CODEX_SKILL_SRC" "$CODEX_SKILLS_DIR/$SKILL_NAME/SKILL.md"
  ok "已安装 Skill → $CODEX_SKILLS_DIR/$SKILL_NAME/SKILL.md"
else
  mkdir -p "$CODEX_SKILLS_DIR/$SKILL_NAME"
  cp "$CLAUDE_SKILL_SRC" "$CODEX_SKILLS_DIR/$SKILL_NAME/SKILL.md"
  ok "已安装 Skill → $CODEX_SKILLS_DIR/$SKILL_NAME/SKILL.md（使用通用版本）"
fi
INSTALLED=$((INSTALLED + 1))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ok "安装完成！共安装 $INSTALLED 份 Skill 配置"
echo ""
echo "📦 核心脚本："
echo "   Bash / Git Bash / WSL：$SCRIPTS_DIR/install.sh, setup.sh, push.sh, pull.sh, sync.sh, status.sh, enable-auto-sync.sh"
echo "   Windows PowerShell / cmd：$SCRIPTS_DIR/install.ps1, push.ps1, pull.ps1, setup.ps1, sync.ps1, status.ps1, enable-auto-sync.ps1"
echo ""
echo "📖 使用方法："
echo "   在任意 AI CLI 对话中说：「初始化配置同步」"
echo "   或：「setup config sync」"
echo ""
echo "🔗 更多信息：https://github.com/yibing1996/ai-cli-config-sync"
echo ""

# 清理临时目录
if [ -n "${TMPDIR_CLI:-}" ]; then
  rm -rf "$TMPDIR_CLI"
fi
