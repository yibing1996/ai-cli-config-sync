#!/usr/bin/env bash
# pull.sh — 从 Git 仓库拉取配置并还原到本地
# 由 ai-cli-config-sync 安装到 ~/.cli-sync/pull.sh
#
# 核心策略：拉取远端配置覆盖本地，但保留本机私有字段：
#   - Copilot config.json 的登录态、Token 与本机信任目录
#   - Copilot mcp-config.json 中各 server 的 env 字段
#   - Claude settings.json 与 Codex config.toml 完全保留本机版本，不再同步
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

echo "🔄 从远程拉取配置..."
cd "$REPO"

# ── 保守同步 Git 历史：只允许快进，避免后台自动 pull 进入冲突态 ───────────────
_sync_remote_branch() {
  local remote="$1" branch="$2"

  if ! git fetch "$remote" "$branch"; then
    echo "❌ git fetch 失败，请检查网络连接、远端地址或认证配置"
    echo "   远端：$remote  分支：$branch"
    exit 1
  fi

  if [ -z "$(git rev-parse FETCH_HEAD 2>/dev/null || true)" ]; then
    echo "ℹ️  远端分支 $branch 当前为空，无需同步 Git 提交"
    return 0
  fi

  if ! git merge --ff-only FETCH_HEAD; then
    echo "❌ 检测到同步仓库存在未提交变更、未推送提交或与远端分叉，已停止自动合并"
    echo "   请先在 ~/.cli-sync-repo 中处理后，再重新执行拉取"
    exit 1
  fi
}

_sync_remote_branch "$REMOTE" "$BRANCH"

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

# ── Copilot config.json 智能合并：远端共享字段 + 保留本机登录态 / Token ─────────
_merge_copilot_config_json() {
  local remote_file="$1" local_file="$2"
  [ -f "$remote_file" ] || return 0

  if [ ! -f "$local_file" ]; then
    cp "$remote_file" "$local_file"
    return 0
  fi

  if _detect_python; then
    env REMOTE_FILE="$remote_file" LOCAL_FILE="$local_file" "${PYTHON_CMD[@]}" << 'PYEOF'
import json
import os

remote = os.environ['REMOTE_FILE']
local = os.environ['LOCAL_FILE']

def load_jsonc(path):
    with open(path, encoding='utf-8-sig') as f:
        text = ''.join(
            line for line in f
            if not line.lstrip().startswith('//')
        )
    return json.loads(text)

local_data = load_jsonc(local)
with open(remote) as f:
    remote_data = json.load(f)

result = dict(remote_data)
for key in (
    'firstLaunchAt',
    'copilot_tokens',
    'last_logged_in_user',
    'logged_in_users',
    'trusted_folders',
):
    if key in local_data:
        result[key] = local_data[key]

with open(local, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
    f.write('\n')
PYEOF
  elif _has_node; then
    local node_remote node_local
    node_remote=$(_node_path_arg "$remote_file")
    node_local=$(_node_path_arg "$local_file")
    "${NODE_CMD[@]}" - "$node_remote" "$node_local" << 'JSEOF'
const fs = require('fs');
const readText = (path) => fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, '');
const readJsonc = (path) => JSON.parse(
  readText(path)
    .split(/\r?\n/)
    .filter((line) => !line.trimStart().startsWith('//'))
    .join('\n')
);

const [, , remote, local] = process.argv;
const localData = readJsonc(local);
const remoteData = JSON.parse(readText(remote));
const result = { ...remoteData };

for (const key of [
  'firstLaunchAt',
  'copilot_tokens',
  'last_logged_in_user',
  'logged_in_users',
  'trusted_folders',
]) {
  if (Object.prototype.hasOwnProperty.call(localData, key)) {
    result[key] = localData[key];
  }
}

fs.writeFileSync(local, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
JSEOF
  else
    echo "⚠️  无可用的 Python 或 node，Copilot config.json 直接覆盖（本机登录态 / Token 可能丢失）"
    cp "$remote_file" "$local_file"
  fi
}

# ── Copilot mcp-config.json 智能合并：远端共享配置 + 保留本机 env ───────────────
_merge_copilot_mcp_json() {
  local remote_file="$1" local_file="$2"
  [ -f "$remote_file" ] || return 0

  if [ ! -f "$local_file" ]; then
    cp "$remote_file" "$local_file"
    return 0
  fi

  if _detect_python; then
    env REMOTE_FILE="$remote_file" LOCAL_FILE="$local_file" "${PYTHON_CMD[@]}" << 'PYEOF'
import json
import os

remote = os.environ['REMOTE_FILE']
local = os.environ['LOCAL_FILE']

with open(local) as f:
    local_data = json.load(f)
with open(remote) as f:
    remote_data = json.load(f)

result = json.loads(json.dumps(remote_data))
local_servers = local_data.get('mcpServers')
remote_servers = result.get('mcpServers')

if isinstance(local_servers, dict):
    if not isinstance(remote_servers, dict):
        result['mcpServers'] = json.loads(json.dumps(local_servers))
    else:
        for name, remote_server in remote_servers.items():
            local_server = local_servers.get(name)
            if isinstance(remote_server, dict) and isinstance(local_server, dict) and 'env' in local_server:
                merged_server = dict(remote_server)
                merged_server['env'] = local_server['env']
                remote_servers[name] = merged_server

        # 保留仅存在于本机的 MCP server，避免 pull 时静默丢失
        for name, local_server in local_servers.items():
            if name not in remote_servers:
                remote_servers[name] = json.loads(json.dumps(local_server))

with open(local, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
    f.write('\n')
PYEOF
  elif _has_node; then
    local node_remote node_local
    node_remote=$(_node_path_arg "$remote_file")
    node_local=$(_node_path_arg "$local_file")
    "${NODE_CMD[@]}" - "$node_remote" "$node_local" << 'JSEOF'
const fs = require('fs');
const readText = (path) => fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, '');

const [, , remote, local] = process.argv;
const localData = JSON.parse(readText(local));
const remoteData = JSON.parse(readText(remote));
const result = JSON.parse(JSON.stringify(remoteData));
const localServers = localData.mcpServers;

if (localServers && typeof localServers === 'object' && !Array.isArray(localServers)) {
  if (!result.mcpServers || typeof result.mcpServers !== 'object' || Array.isArray(result.mcpServers)) {
    result.mcpServers = JSON.parse(JSON.stringify(localServers));
  } else {
    for (const [name, remoteServer] of Object.entries(result.mcpServers)) {
      const localServer = localServers[name];
      if (
        remoteServer && typeof remoteServer === 'object' && !Array.isArray(remoteServer) &&
        localServer && typeof localServer === 'object' && !Array.isArray(localServer) &&
        Object.prototype.hasOwnProperty.call(localServer, 'env')
      ) {
        result.mcpServers[name] = { ...remoteServer, env: localServer.env };
      }
    }

    for (const [name, localServer] of Object.entries(localServers)) {
      if (!Object.prototype.hasOwnProperty.call(result.mcpServers, name)) {
        result.mcpServers[name] = JSON.parse(JSON.stringify(localServer));
      }
    }
  }
}

fs.writeFileSync(local, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
JSEOF
  else
    echo "⚠️  无可用的 Python 或 node，Copilot mcp-config.json 直接覆盖（本机 env 可能丢失）"
    cp "$remote_file" "$local_file"
  fi
}

# ── GitHub Copilot CLI ────────────────────────────────────────────────────────
if [ -d "$REPO/copilot" ]; then
  mkdir -p "$COPILOT_DIR"

  [ -f "$REPO/copilot/copilot-instructions.md" ] && cp "$REPO/copilot/copilot-instructions.md" "$COPILOT_DIR/"
  _merge_copilot_config_json "$REPO/copilot/config.json" "$COPILOT_DIR/config.json"
  _merge_copilot_mcp_json "$REPO/copilot/mcp-config.json" "$COPILOT_DIR/mcp-config.json"
fi

# ── Claude Code CLI ───────────────────────────────────────────────────────────
if [ -d "$REPO/claude" ]; then
  # 自动创建目录（新机器上可能不存在 ~/.claude）
  mkdir -p "$CLAUDE_DIR/plugins" "$CLAUDE_DIR/skills"

  [ -f "$REPO/claude/CLAUDE.md" ] && cp "$REPO/claude/CLAUDE.md" "$CLAUDE_DIR/"

  # settings.json 不再同步，始终保留本机版本。

  [ -f "$REPO/claude/plugins/blocklist.json" ] && cp "$REPO/claude/plugins/blocklist.json" "$CLAUDE_DIR/plugins/"
  [ -f "$REPO/claude/plugins/known_marketplaces.json" ] && cp "$REPO/claude/plugins/known_marketplaces.json" "$CLAUDE_DIR/plugins/"

  _restore_dir "$REPO/claude/skills" "$CLAUDE_DIR/skills"
fi

# ── Codex CLI ─────────────────────────────────────────────────────────────────
if [ -d "$REPO/codex" ]; then
  # 自动创建目录（新机器上可能不存在 ~/.codex）
  mkdir -p "$CODEX_DIR/skills" "$CODEX_DIR/rules" "$CODEX_DIR/memories"

  [ -f "$REPO/codex/AGENTS.md" ] && cp "$REPO/codex/AGENTS.md" "$CODEX_DIR/"

  # config.toml 不再同步，始终保留本机版本。

  _restore_dir "$REPO/codex/skills"   "$CODEX_DIR/skills"
  _restore_dir "$REPO/codex/rules"    "$CODEX_DIR/rules"
  _restore_dir "$REPO/codex/memories" "$CODEX_DIR/memories"
fi

echo "✅ 配置还原完成"
echo "📝 注意事项："
echo "   - Copilot config.json 已保留本机登录态、Token 与 trusted_folders（如有）"
echo "   - Copilot mcp-config.json 已保留同名 MCP server 的本机 env（如有）"
echo "   - Claude settings.json 不参与同步，已保留本机版本"
echo "   - Codex config.toml 不参与同步，已保留本机版本"
echo "   - auth.json 不同步，各机器需独立登录"
