#!/usr/bin/env bash
# pull.sh — 从 Git 仓库拉取配置并还原到本地
# 由 cli-config-sync 安装到 ~/.cli-sync/pull.sh
set -e

CONFIG_FILE="$HOME/.cli-sync/config.yml"
REPO="$HOME/.cli-sync-repo"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 未找到 ~/.cli-sync/config.yml，请先初始化（说「初始化配置同步」）"
  exit 1
fi

REMOTE=$(grep '^remote:' "$CONFIG_FILE" | sed 's/remote: *//')
BRANCH=$(grep '^branch:' "$CONFIG_FILE" | sed 's/branch: *//' | tr -d '[:space:]')
BRANCH=${BRANCH:-main}

echo "🔄 从远程拉取配置..."
cd "$REPO"
git pull "$REMOTE" "$BRANCH" || true

echo "📋 还原配置文件..."

# ── 目录镜像还原（含 --delete 保证删除也同步）────────────────────────────────
_restore_dir() {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  if command -v rsync &> /dev/null; then
    rsync -a --delete "$src/" "$dst/"
  else
    rm -rf "$dst" && cp -r "$src" "$dst"
  fi
}

# ── GitHub Copilot CLI / Claude Code CLI ──────────────────────────────────────
if [ -d "$REPO/claude" ]; then
  # 自动创建目录（新机器上可能不存在 ~/.claude）
  mkdir -p "$CLAUDE_DIR/plugins" "$CLAUDE_DIR/skills"

  [ -f "$REPO/claude/CLAUDE.md" ] && cp "$REPO/claude/CLAUDE.md" "$CLAUDE_DIR/"
  [ -f "$REPO/claude/settings.json" ] && cp "$REPO/claude/settings.json" "$CLAUDE_DIR/"
  [ -f "$REPO/claude/plugins/blocklist.json" ] && cp "$REPO/claude/plugins/blocklist.json" "$CLAUDE_DIR/plugins/"
  [ -f "$REPO/claude/plugins/known_marketplaces.json" ] && cp "$REPO/claude/plugins/known_marketplaces.json" "$CLAUDE_DIR/plugins/"

  _restore_dir "$REPO/claude/skills" "$CLAUDE_DIR/skills"
fi

# ── Codex CLI ─────────────────────────────────────────────────────────────────
if [ -d "$REPO/codex" ]; then
  # 自动创建目录（新机器上可能不存在 ~/.codex）
  mkdir -p "$CODEX_DIR/skills" "$CODEX_DIR/rules" "$CODEX_DIR/memories"

  [ -f "$REPO/codex/AGENTS.md" ] && cp "$REPO/codex/AGENTS.md" "$CODEX_DIR/"
  [ -f "$REPO/codex/config.toml" ] && cp "$REPO/codex/config.toml" "$CODEX_DIR/"

  _restore_dir "$REPO/codex/skills"   "$CODEX_DIR/skills"
  _restore_dir "$REPO/codex/rules"    "$CODEX_DIR/rules"
  _restore_dir "$REPO/codex/memories" "$CODEX_DIR/memories"
fi

echo "✅ 配置还原完成"
echo "📝 注意事项："
echo "   - settings.json 的 env 字段（API Token）未同步，如需设置请手动配置"
echo "   - config.toml 的 [projects] 信任路径和 env 字段未同步，新机器请手动添加"
echo "   - auth.json 不同步，各机器需独立登录"
