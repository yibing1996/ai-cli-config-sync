#!/usr/bin/env bash
# push.sh — 将本地 CLI 配置推送到 Git 仓库
# 由 cli-config-sync 安装到 ~/.cli-sync/push.sh
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

# ── 检查同步仓库是否有效 ─────────────────────────────────────────────────────
if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "❌ 同步仓库无效：$REPO"
  echo "   请重新执行初始化，或删除 ~/.cli-sync-repo 后重新初始化"
  exit 1
fi

# ── 检查 Git 身份配置（在同步仓库上下文中检查）──────────────────────────────
GIT_NAME=$(git -C "$REPO" config user.name 2>/dev/null || true)
GIT_EMAIL=$(git -C "$REPO" config user.email 2>/dev/null || true)
if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
  echo "❌ Git 身份未配置（在同步仓库上下文中未找到），请先运行："
  echo "   git config --global user.name \"你的名字\""
  echo "   git config --global user.email \"你的邮箱\""
  exit 1
fi

echo "📦 收集配置文件..."

# ── 目录镜像同步（含 --delete 保证删除也同步）────────────────────────────────
_sync_dir() {
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
if [ -d "$CLAUDE_DIR" ]; then
  mkdir -p "$REPO/claude/plugins" "$REPO/claude/skills"

  # CLAUDE.md
  [ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$REPO/claude/"

  # settings.json（过滤 env 字段，含 API Token）
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if command -v jq &> /dev/null; then
      jq 'del(.env)' "$CLAUDE_DIR/settings.json" > "$REPO/claude/settings.json"
    elif command -v python3 &> /dev/null; then
      python3 << 'PYEOF'
import json, os
src = os.path.expanduser('~/.claude/settings.json')
dst = os.path.expanduser('~/.cli-sync-repo/claude/settings.json')
with open(src) as f:
    d = json.load(f)
d.pop('env', None)
with open(dst, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
    else
      echo "⚠️  未找到 jq 或 python3，settings.json 将完整复制（请确保使用私有仓库）"
      cp "$CLAUDE_DIR/settings.json" "$REPO/claude/"
    fi
  fi

  # plugins 配置文件
  [ -f "$CLAUDE_DIR/plugins/blocklist.json" ] && cp "$CLAUDE_DIR/plugins/blocklist.json" "$REPO/claude/plugins/"
  [ -f "$CLAUDE_DIR/plugins/known_marketplaces.json" ] && cp "$CLAUDE_DIR/plugins/known_marketplaces.json" "$REPO/claude/plugins/"

  # skills（全量镜像同步）
  _sync_dir "$CLAUDE_DIR/skills" "$REPO/claude/skills"
fi

# ── Codex CLI ─────────────────────────────────────────────────────────────────
if [ -d "$CODEX_DIR" ]; then
  mkdir -p "$REPO/codex/skills" "$REPO/codex/rules" "$REPO/codex/memories"

  # AGENTS.md
  [ -f "$CODEX_DIR/AGENTS.md" ] && cp "$CODEX_DIR/AGENTS.md" "$REPO/codex/"

  # config.toml（过滤 [projects.*] 段和 env 字段）
  if [ -f "$CODEX_DIR/config.toml" ]; then
    if command -v python3 &> /dev/null; then
      python3 << 'PYEOF'
import re, os

src = os.path.expanduser('~/.codex/config.toml')
dst = os.path.expanduser('~/.cli-sync-repo/codex/config.toml')

with open(src) as f:
    lines = f.readlines()

result = []
skip_section = False
for line in lines:
    # 跳过 [projects.*] 段（含本机绝对路径和信任配置）
    if re.match(r'^\s*\[projects\.', line):
        skip_section = True
        continue
    # 遇到新的非 projects 段，恢复正常
    if re.match(r'^\s*\[(?!projects\.)', line):
        skip_section = False
    if skip_section:
        continue
    # 过滤 env = { ... } 行（可能含 API Token，允许前导空白/缩进）
    if re.match(r'^\s*env\s*=\s*\{', line):
        indent = re.match(r'^(\s*)', line).group(1)
        result.append(f'{indent}# env = {{ ... }}  # 已过滤，请在本机手动配置\n')
        continue
    result.append(line)

# 清理末尾多余空行
content = ''.join(result).rstrip('\n') + '\n'
with open(dst, 'w') as f:
    f.write(content)
PYEOF
    else
      echo "⚠️  未找到 python3，config.toml 将完整复制（[projects] 和 env 未过滤，请确保使用私有仓库）"
      cp "$CODEX_DIR/config.toml" "$REPO/codex/"
    fi
  fi

  # 目录同步
  _sync_dir "$CODEX_DIR/skills"   "$REPO/codex/skills"
  _sync_dir "$CODEX_DIR/rules"    "$REPO/codex/rules"
  _sync_dir "$CODEX_DIR/memories" "$REPO/codex/memories"
fi

# ── Git 提交推送 ──────────────────────────────────────────────────────────────
cd "$REPO"
git add -A

if git diff --cached --quiet; then
  echo "✅ 配置无变化，无需推送"
else
  COMMIT_MSG="sync: $(date '+%Y-%m-%d %H:%M:%S') from $(hostname)"
  git commit -m "$COMMIT_MSG"
  git push "$REMOTE" "$BRANCH" 2>&1 || \
    git push --set-upstream origin "$BRANCH"
  echo "🚀 配置已推送到 $REMOTE ($BRANCH)"
fi
