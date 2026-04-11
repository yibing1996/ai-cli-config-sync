#!/usr/bin/env bash
# setup.sh — 初始化 ~/.cli-sync/config.yml 与 ~/.cli-sync-repo
set -euo pipefail

REMOTE_URL="${1:-${AI_CLI_SYNC_REMOTE_URL:-}}"
if [ -z "$REMOTE_URL" ]; then
  echo "❌ 用法：bash ~/.cli-sync/setup.sh <git-remote-url>"
  exit 1
fi

CONFIG_FILE="$HOME/.cli-sync/config.yml"
REPO_DIR="$HOME/.cli-sync-repo"
SCRIPTS_DIR="$HOME/.cli-sync"
HAS_REMOTE_CONTENT=false
BRANCH="main"
AUTO_PULL="false"
AUTO_PUSH="false"

if [ -f "$CONFIG_FILE" ]; then
  AUTO_PULL=$(grep '^auto_pull:' "$CONFIG_FILE" | sed 's/auto_pull: *//' | tr -d '[:space:]' || true)
  AUTO_PUSH=$(grep '^auto_push:' "$CONFIG_FILE" | sed 's/auto_push: *//' | tr -d '[:space:]' || true)
  AUTO_PULL=${AUTO_PULL:-false}
  AUTO_PUSH=${AUTO_PUSH:-false}
fi

mkdir -p "$SCRIPTS_DIR" "$REPO_DIR"

if [ "$(ls -A "$REPO_DIR" 2>/dev/null)" ]; then
  if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "检测到已有同步仓库，复用现有仓库"
    if ! git ls-remote "$REMOTE_URL" &>/dev/null; then
      echo "❌ 无法访问远端仓库：$REMOTE_URL"
      echo "   请检查：1) 仓库地址是否正确  2) 网络连接  3) 认证配置（SSH key 或 Token）"
      exit 1
    fi
    if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
      git -C "$REPO_DIR" remote set-url origin "$REMOTE_URL"
    else
      git -C "$REPO_DIR" remote add origin "$REMOTE_URL"
    fi
    BRANCH=$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "main")
    if git ls-remote --heads "$REMOTE_URL" 2>/dev/null | grep -q .; then
      HAS_REMOTE_CONTENT=true
    fi
  else
    echo "❌ $REPO_DIR 已存在且非空，但不是有效 Git 仓库"
    echo "   请备份后删除该目录，再重新初始化"
    exit 1
  fi
else
  if ! git ls-remote "$REMOTE_URL" &>/dev/null; then
    echo "❌ 无法访问远端仓库：$REMOTE_URL"
    echo "   请检查：1) 仓库地址是否正确  2) 网络连接  3) 认证配置（SSH key 或 Token）"
    exit 1
  fi

  if git ls-remote --heads "$REMOTE_URL" 2>/dev/null | grep -q .; then
    git -C "$REPO_DIR" clone "$REMOTE_URL" .
    HAS_REMOTE_CONTENT=true

    DEFAULT_BRANCH=$(git -C "$REPO_DIR" remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || true)
    if [ -z "$DEFAULT_BRANCH" ] || [ "$DEFAULT_BRANCH" = "(unknown)" ]; then
      DEFAULT_BRANCH=$(git -C "$REPO_DIR" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin | head -n 1)
    fi

    if [ -n "$DEFAULT_BRANCH" ]; then
      BRANCH="$DEFAULT_BRANCH"
      CURRENT_BRANCH=$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
      if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
        git -C "$REPO_DIR" checkout "$BRANCH" 2>/dev/null || git -C "$REPO_DIR" checkout -b "$BRANCH" "origin/$BRANCH"
      fi
    else
      BRANCH=$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "main")
    fi

    echo "✅ 已 clone 远程仓库（分支：$BRANCH）"
  else
    git -C "$REPO_DIR" init
    git -C "$REPO_DIR" remote add origin "$REMOTE_URL"
    git -C "$REPO_DIR" checkout -b "$BRANCH" 2>/dev/null || git -C "$REPO_DIR" branch -m "$BRANCH"
    echo "✅ 已初始化本地仓库（分支：$BRANCH）"
  fi
fi

cat > "$CONFIG_FILE" <<EOF
remote: $REMOTE_URL
branch: $BRANCH
auto_pull: $AUTO_PULL
auto_push: $AUTO_PUSH
EOF

if [ ! -f "$REPO_DIR/.gitignore" ]; then
  cat > "$REPO_DIR/.gitignore" << 'EOF'
# 认证文件（绝不同步）
auth.json

# SQLite 数据库
*.sqlite
*.sqlite-shm
*.sqlite-wal

# 运行时数据
cache/
sessions/
archived_sessions/
tmp/
.tmp/
logs_*
state_*
history.jsonl
downloads/
debug/
telemetry/
shell-snapshots/
shell_snapshots/
file-history/

# Marketplace 缓存（可从 GitHub 重新下载）
claude/plugins/marketplaces/
copilot/logs/
copilot/session-state/
copilot/command-history-state.json
copilot/copilot.bat
codex/vendor_imports/
EOF
else
  echo "ℹ️  .gitignore 已存在，保留现有内容"
fi

echo "✅ Setup 完成"

if [ "$HAS_REMOTE_CONTENT" = "true" ]; then
  echo "ℹ️  检测到远端已有配置，初始化将同步远端到本地"
  bash "$HOME/.cli-sync/pull.sh"
else
  echo "ℹ️  远端为空，初始化将推送本地配置"
  bash "$HOME/.cli-sync/push.sh"
fi
