#!/usr/bin/env bash
# push.sh — 将本地 CLI 配置推送到 Git 仓库
# 由 ai-cli-config-sync 安装到 ~/.cli-sync/push.sh
set -e

CONFIG_FILE="$HOME/.cli-sync/config.yml"
REPO="$HOME/.cli-sync-repo"
COPILOT_DIR="$HOME/.copilot"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 未找到 ~/.cli-sync/config.yml，请先初始化（说「初始化配置同步」）"
  exit 1
fi

REMOTE=$(grep '^remote:' "$CONFIG_FILE" | sed 's/remote: *//')
BRANCH=$(grep '^branch:' "$CONFIG_FILE" | sed 's/branch: *//' | tr -d '[:space:]')
BRANCH=${BRANCH:-main}

PYTHON_CMD=()
PYTHON_CMD_CHECKED=0

_detect_python() {
  if [ "$PYTHON_CMD_CHECKED" -eq 1 ]; then
    [ "${#PYTHON_CMD[@]}" -gt 0 ]
    return
  fi

  PYTHON_CMD_CHECKED=1

  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" - <<'PYEOF' >/dev/null 2>&1
import json
PYEOF
    then
      PYTHON_CMD=("$candidate")
      return 0
    fi
  done

  if command -v py >/dev/null 2>&1 && py -3 - <<'PYEOF' >/dev/null 2>&1
import json
PYEOF
  then
    PYTHON_CMD=("py" "-3")
    return 0
  fi

  PYTHON_CMD=()
  return 1
}

_run_python() {
  _detect_python || return 1
  "${PYTHON_CMD[@]}" "$@"
}

_has_node() {
  command -v node >/dev/null 2>&1
}

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

# ── GitHub Copilot CLI ────────────────────────────────────────────────────────
_filter_copilot_config_json() {
  local src="$1" dst="$2"

  if _detect_python; then
    SRC="$src" DST="$dst" _run_python << 'PYEOF'
import json
import os

src = os.environ['SRC']
dst = os.environ['DST']

with open(src) as f:
    data = json.load(f)

# 仅同步明确安全、适合跨机器共享的字段。
result = {}
for key in ('banner', 'model'):
    if key in data:
        result[key] = data[key]

with open(dst, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
    f.write('\n')
PYEOF
  elif _has_node; then
    SRC="$src" DST="$dst" node << 'JSEOF'
const fs = require('fs');

const src = process.env.SRC;
const dst = process.env.DST;
const data = JSON.parse(fs.readFileSync(src, 'utf8'));

const result = {};
for (const key of ['banner', 'model']) {
  if (Object.prototype.hasOwnProperty.call(data, key)) {
    result[key] = data[key];
  }
}

fs.writeFileSync(dst, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
JSEOF
  else
    echo "⚠️  未找到可用的 Python 或 node，已跳过 Copilot config.json 同步（避免上传本机登录态和 Token）"
  fi
}

_filter_copilot_mcp_json() {
  local src="$1" dst="$2"

  if _detect_python; then
    SRC="$src" DST="$dst" _run_python << 'PYEOF'
import json
import os

src = os.environ['SRC']
dst = os.environ['DST']

with open(src) as f:
    data = json.load(f)

result = json.loads(json.dumps(data))
servers = result.get('mcpServers')
if isinstance(servers, dict):
    for name, server in servers.items():
        if isinstance(server, dict):
            # env 常包含 Token、代理和本机特定环境变量，不入库。
            server.pop('env', None)

with open(dst, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
    f.write('\n')
PYEOF
  elif _has_node; then
    SRC="$src" DST="$dst" node << 'JSEOF'
const fs = require('fs');

const src = process.env.SRC;
const dst = process.env.DST;
const data = JSON.parse(fs.readFileSync(src, 'utf8'));
const result = JSON.parse(JSON.stringify(data));
const servers = result.mcpServers;

if (servers && typeof servers === 'object' && !Array.isArray(servers)) {
  for (const server of Object.values(servers)) {
    if (server && typeof server === 'object' && !Array.isArray(server)) {
      delete server.env;
    }
  }
}

fs.writeFileSync(dst, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
JSEOF
  else
    echo "⚠️  未找到可用的 Python 或 node，已跳过 Copilot mcp-config.json 同步（避免上传本机 env）"
  fi
}

if [ -d "$COPILOT_DIR" ]; then
  mkdir -p "$REPO/copilot"

  [ -f "$COPILOT_DIR/copilot-instructions.md" ] && cp "$COPILOT_DIR/copilot-instructions.md" "$REPO/copilot/"

  if [ -f "$COPILOT_DIR/config.json" ]; then
    _filter_copilot_config_json "$COPILOT_DIR/config.json" "$REPO/copilot/config.json"
  fi

  if [ -f "$COPILOT_DIR/mcp-config.json" ]; then
    _filter_copilot_mcp_json "$COPILOT_DIR/mcp-config.json" "$REPO/copilot/mcp-config.json"
  fi
fi

# ── Claude Code CLI ───────────────────────────────────────────────────────────
if [ -d "$CLAUDE_DIR" ]; then
  mkdir -p "$REPO/claude/plugins" "$REPO/claude/skills"

  # CLAUDE.md
  [ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$REPO/claude/"

  # settings.json（过滤 env 字段，含 API Token）
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if command -v jq &> /dev/null; then
      jq 'del(.env)' "$CLAUDE_DIR/settings.json" > "$REPO/claude/settings.json"
    elif _detect_python; then
      _run_python << 'PYEOF'
import json, os
src = os.path.expanduser('~/.claude/settings.json')
dst = os.path.expanduser('~/.cli-sync-repo/claude/settings.json')
with open(src) as f:
    d = json.load(f)
d.pop('env', None)
with open(dst, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
    elif _has_node; then
      node << 'JSEOF'
const fs = require('fs');

const src = `${process.env.HOME}/.claude/settings.json`;
const dst = `${process.env.HOME}/.cli-sync-repo/claude/settings.json`;
const data = JSON.parse(fs.readFileSync(src, 'utf8'));

delete data.env;

fs.writeFileSync(dst, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
JSEOF
    else
      echo "⚠️  未找到 jq、可用的 Python 或 node，settings.json 将完整复制（请确保使用私有仓库）"
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
    if _detect_python; then
      _run_python << 'PYEOF'
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
    elif _has_node; then
      node << 'JSEOF'
const fs = require('fs');

const src = `${process.env.HOME}/.codex/config.toml`;
const dst = `${process.env.HOME}/.cli-sync-repo/codex/config.toml`;
const rawLines = fs.readFileSync(src, 'utf8').replace(/\r\n/g, '\n').split('\n');
if (rawLines.length > 0 && rawLines[rawLines.length - 1] === '') {
  rawLines.pop();
}

const result = [];
let skipSection = false;

for (const rawLine of rawLines) {
  const line = `${rawLine}\n`;
  if (/^\s*\[projects\./.test(line)) {
    skipSection = true;
    continue;
  }
  if (/^\s*\[(?!projects\.)/.test(line)) {
    skipSection = false;
  }
  if (skipSection) {
    continue;
  }
  if (/^\s*env\s*=\s*\{/.test(line)) {
    const indent = (line.match(/^(\s*)/) || [''])[1];
    result.push(`${indent}# env = { ... }  # 已过滤，请在本机手动配置\n`);
    continue;
  }
  result.push(line);
}

const content = `${result.join('').replace(/\n*$/, '')}\n`;
fs.writeFileSync(dst, content, 'utf8');
JSEOF
    else
      echo "⚠️  未找到可用的 Python 或 node，config.toml 将完整复制（[projects] 和 env 未过滤，请确保使用私有仓库）"
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

  if ! git push "$REMOTE" "$BRANCH"; then
    echo "❌ 推送失败：未能将本地配置推送到远端"
    echo "   请检查："
    echo "   1) 远端地址是否正确：$REMOTE"
    echo "   2) Git 认证、网络连接和仓库权限是否正常"
    echo "   3) 远端是否已有新提交，若已领先请先执行拉取并处理差异"
    exit 1
  fi

  echo "🚀 配置已推送到 $REMOTE ($BRANCH)"
fi
