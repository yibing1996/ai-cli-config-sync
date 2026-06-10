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
NODE_CMD=()
NODE_CMD_CHECKED=0

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
  _export_runtime_context
  "${PYTHON_CMD[@]}" "$@"
}

_export_runtime_context() {
  local name
  for name in SRC DST REMOTE_FILE LOCAL_FILE KIND OUT_FILE; do
    if [ "${!name+x}" = "x" ]; then
      export "$name"
    fi
  done
}

_is_windows_posix_shell() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

_detect_node() {
  if [ "$NODE_CMD_CHECKED" -eq 1 ]; then
    [ "${#NODE_CMD[@]}" -gt 0 ]
    return
  fi

  NODE_CMD_CHECKED=1

  if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1; then
    NODE_CMD=("node")
    return 0
  fi

  if _is_windows_posix_shell && command -v node.exe >/dev/null 2>&1 && node.exe --version >/dev/null 2>&1; then
    NODE_CMD=("node.exe")
    return 0
  fi

  NODE_CMD=()
  return 1
}

_run_node() {
  _detect_node || return 1
  _export_runtime_context
  "${NODE_CMD[@]}" "$@"
}

_has_node() {
  _detect_node
}

_node_path_arg() {
  local path="$1"
  if [ "${#NODE_CMD[@]}" -gt 0 ] && [ "${NODE_CMD[0]}" = "node.exe" ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
  else
    printf '%s\n' "$path"
  fi
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

echo "🔄 拉取并合并远端同步仓库..."
cd "$REPO"

# ── 推送前先合并远端：保持像普通项目一样先 pull 再 commit/push ──────────────
_merge_remote_branch_before_push() {
  local remote="$1" branch="$2"
  local ls_output ls_status

  set +e
  ls_output=$(git ls-remote --exit-code --heads "$remote" "$branch" 2>&1)
  ls_status=$?
  set -e

  if [ "$ls_status" -eq 2 ]; then
    echo "ℹ️  远端分支 $branch 尚不存在，将在本次同步中首次推送"
    return 0
  fi

  if [ "$ls_status" -ne 0 ]; then
    echo "❌ 检查远端分支失败，请检查网络连接、远端地址或认证配置"
    echo "   远端：$remote  分支：$branch"
    echo "$ls_output"
    exit 1
  fi

  if ! git fetch "$remote" "$branch"; then
    echo "❌ git fetch 失败，请检查网络连接、远端地址或认证配置"
    echo "   远端：$remote  分支：$branch"
    exit 1
  fi

  if ! git merge --no-edit FETCH_HEAD; then
    echo "❌ 合并远端同步仓库失败，已停止推送"
    echo "   请先在 ~/.cli-sync-repo 中解决冲突后，再重新执行同步"
    exit 1
  fi
}

_merge_remote_branch_before_push "$REMOTE" "$BRANCH"

echo "📦 收集配置文件..."

# ── 目录增量同步：保留远端已有文件，避免拉取合并后被本机空缺误删 ───────────────
_sync_dir() {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  if command -v rsync &> /dev/null; then
    rsync -a "$src/" "$dst/"
  else
    cp -R "$src/." "$dst/"
  fi
}

# ── GitHub Copilot CLI ────────────────────────────────────────────────────────
_filter_copilot_config_json() {
  local src="$1" dst="$2"

  if _detect_python; then
    env SRC="$src" DST="$dst" "${PYTHON_CMD[@]}" << 'PYEOF'
import json
import os

src = os.environ['SRC']
dst = os.environ['DST']

def load_jsonc(path):
    with open(path, encoding='utf-8-sig') as f:
        text = ''.join(
            line for line in f
            if not line.lstrip().startswith('//')
        )
    return json.loads(text)

data = load_jsonc(src)

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
    local node_src node_dst
    node_src=$(_node_path_arg "$src")
    node_dst=$(_node_path_arg "$dst")
    "${NODE_CMD[@]}" - "$node_src" "$node_dst" << 'JSEOF'
const fs = require('fs');
const readText = (path) => fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, '');
const readJsonc = (path) => JSON.parse(
  readText(path)
    .split(/\r?\n/)
    .filter((line) => !line.trimStart().startsWith('//'))
    .join('\n')
);

const [, , src, dst] = process.argv;
const data = readJsonc(src);

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
    env SRC="$src" DST="$dst" "${PYTHON_CMD[@]}" << 'PYEOF'
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
    local node_src node_dst
    node_src=$(_node_path_arg "$src")
    node_dst=$(_node_path_arg "$dst")
    "${NODE_CMD[@]}" - "$node_src" "$node_dst" << 'JSEOF'
const fs = require('fs');
const readText = (path) => fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, '');

const [, , src, dst] = process.argv;
const data = JSON.parse(readText(src));
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

  # settings.json 含本机偏好和潜在敏感字段，不再同步；同时删除仓库中的旧副本。
  rm -f "$REPO/claude/settings.json"

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

  # config.toml 含 MCP 路径、模型偏好和本机信任配置，不再同步；同时删除仓库中的旧副本。
  rm -f "$REPO/codex/config.toml"

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
