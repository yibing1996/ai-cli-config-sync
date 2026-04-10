#!/usr/bin/env bash
# pull.sh — 从 Git 仓库拉取配置并还原到本地
# 由 cli-config-sync 安装到 ~/.cli-sync/pull.sh
#
# 核心策略：拉取远端配置覆盖本地，但保留本机私有字段：
#   - settings.json 的 env 字段（API Token）
#   - config.toml 的 [projects.*] 段和 env 字段
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
if ! git pull "$REMOTE" "$BRANCH"; then
  echo "❌ git pull 失败，请检查网络连接、远端地址或认证配置"
  echo "   远端：$REMOTE  分支：$BRANCH"
  exit 1
fi

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

# ── settings.json 智能合并：用远端内容 + 保留本机 env ─────────────────────────
_merge_settings_json() {
  local remote_file="$1" local_file="$2"
  [ -f "$remote_file" ] || return 0

  # 如果本地不存在，直接复制
  if [ ! -f "$local_file" ]; then
    cp "$remote_file" "$local_file"
    return 0
  fi

  # 有 jq 时：远端内容 + 保留本机 env
  if command -v jq &> /dev/null; then
    local LOCAL_ENV
    LOCAL_ENV=$(jq -c '.env // empty' "$local_file" 2>/dev/null || true)
    if [ -n "$LOCAL_ENV" ]; then
      jq --argjson env "$LOCAL_ENV" '. + {env: $env}' "$remote_file" > "$local_file.tmp"
      mv "$local_file.tmp" "$local_file"
    else
      cp "$remote_file" "$local_file"
    fi
  # 有 python3 时
  elif command -v python3 &> /dev/null; then
    python3 << PYEOF
import json, os
remote = "$remote_file"
local = "$local_file"

with open(local) as f:
    local_data = json.load(f)
with open(remote) as f:
    remote_data = json.load(f)

# 保留本机 env
local_env = local_data.get('env')
result = dict(remote_data)
if local_env is not None:
    result['env'] = local_env

with open(local, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
PYEOF
  else
    # 无工具时直接覆盖，但警告
    echo "⚠️  无 jq 或 python3，settings.json 直接覆盖（本机 env 可能丢失）"
    cp "$remote_file" "$local_file"
  fi
}

# ── config.toml 智能合并：用远端内容 + 保留本机 [projects.*] 和 env ────────────
_merge_config_toml() {
  local remote_file="$1" local_file="$2"
  [ -f "$remote_file" ] || return 0

  # 如果本地不存在，直接复制
  if [ ! -f "$local_file" ]; then
    cp "$remote_file" "$local_file"
    return 0
  fi

  if command -v python3 &> /dev/null; then
    python3 << PYEOF
import re, os

remote = "$remote_file"
local = "$local_file"

# 从本地文件提取 [projects.*] 段和 env 行
with open(local) as f:
    local_lines = f.readlines()

local_projects = []  # 保存本机 [projects.*] 段
local_envs = {}      # 保存本机 env 行（按所在段分组）
current_section = ""
in_projects = False

for line in local_lines:
    if re.match(r'^\[projects\.', line):
        in_projects = True
        local_projects.append(line)
        continue
    if re.match(r'^\[', line):
        if in_projects:
            in_projects = False
        current_section = line.strip()
    if in_projects:
        local_projects.append(line)
        continue
    if re.match(r'^env\s*=\s*\{', line):
        local_envs[current_section] = line

# 读取远端文件，还原 env 行到对应段
with open(remote) as f:
    remote_lines = f.readlines()

result = []
current_section = ""
for line in remote_lines:
    if re.match(r'^\[', line):
        current_section = line.strip()
    # 如果远端的 env 被注释掉了，尝试用本机的 env 还原
    if re.match(r'^#\s*env\s*=\s*\{.*已过滤', line):
        if current_section in local_envs:
            result.append(local_envs[current_section])
            continue
    result.append(line)

# 末尾追加本机的 [projects.*] 段
if local_projects:
    result.append('\n')
    result.extend(local_projects)

content = ''.join(result).rstrip('\n') + '\n'
with open(local, 'w') as f:
    f.write(content)
PYEOF
  else
    # 无 python3 时直接覆盖，但警告
    echo "⚠️  无 python3，config.toml 直接覆盖（本机 [projects] 和 env 可能丢失）"
    cp "$remote_file" "$local_file"
  fi
}

# ── GitHub Copilot CLI / Claude Code CLI ──────────────────────────────────────
if [ -d "$REPO/claude" ]; then
  # 自动创建目录（新机器上可能不存在 ~/.claude）
  mkdir -p "$CLAUDE_DIR/plugins" "$CLAUDE_DIR/skills"

  [ -f "$REPO/claude/CLAUDE.md" ] && cp "$REPO/claude/CLAUDE.md" "$CLAUDE_DIR/"

  # settings.json：智能合并，保留本机 env
  _merge_settings_json "$REPO/claude/settings.json" "$CLAUDE_DIR/settings.json"

  [ -f "$REPO/claude/plugins/blocklist.json" ] && cp "$REPO/claude/plugins/blocklist.json" "$CLAUDE_DIR/plugins/"
  [ -f "$REPO/claude/plugins/known_marketplaces.json" ] && cp "$REPO/claude/plugins/known_marketplaces.json" "$CLAUDE_DIR/plugins/"

  _restore_dir "$REPO/claude/skills" "$CLAUDE_DIR/skills"
fi

# ── Codex CLI ─────────────────────────────────────────────────────────────────
if [ -d "$REPO/codex" ]; then
  # 自动创建目录（新机器上可能不存在 ~/.codex）
  mkdir -p "$CODEX_DIR/skills" "$CODEX_DIR/rules" "$CODEX_DIR/memories"

  [ -f "$REPO/codex/AGENTS.md" ] && cp "$REPO/codex/AGENTS.md" "$CODEX_DIR/"

  # config.toml：智能合并，保留本机 [projects.*] 和 env
  _merge_config_toml "$REPO/codex/config.toml" "$CODEX_DIR/config.toml"

  _restore_dir "$REPO/codex/skills"   "$CODEX_DIR/skills"
  _restore_dir "$REPO/codex/rules"    "$CODEX_DIR/rules"
  _restore_dir "$REPO/codex/memories" "$CODEX_DIR/memories"
fi

echo "✅ 配置还原完成"
echo "📝 注意事项："
echo "   - settings.json 的 env 字段已保留本机值（如有）"
echo "   - config.toml 的 [projects] 和 env 已保留本机值（如有）"
echo "   - auth.json 不同步，各机器需独立登录"
