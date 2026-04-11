#!/usr/bin/env bash
# status.sh — 查看同步仓库状态与本地共享配置差异
set -euo pipefail

REPO="$HOME/.cli-sync-repo"
TMP_DIR="$(mktemp -d)"
PYTHON_CMD=()
PYTHON_CMD_CHECKED=0
NODE_CMD=()
NODE_CMD_CHECKED=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

_strip_utf8_bom() {
  local src="$1" dst="$2"
  LC_ALL=C sed $'1s/^\xEF\xBB\xBF//' "$src" > "$dst"
}

_files_differ_ignoring_bom_and_cr() {
  local left="$1" right="$2"
  local normalized_left normalized_right

  normalized_left="$(mktemp "$TMP_DIR/left.XXXXXX")"
  normalized_right="$(mktemp "$TMP_DIR/right.XXXXXX")"
  _strip_utf8_bom "$left" "$normalized_left"
  _strip_utf8_bom "$right" "$normalized_right"

  ! diff --strip-trailing-cr -q "$normalized_left" "$normalized_right" > /dev/null 2>&1
}

_sanitized_diff() {
  local kind="$1" local_file="$2" repo_file="$3" out_file="$4"
  [ -f "$local_file" ] && [ -f "$repo_file" ] || return 1

  if _detect_python; then
    env KIND="$kind" LOCAL_FILE="$local_file" OUT_FILE="$out_file" "${PYTHON_CMD[@]}" << 'PYEOF'
import json
import os
import re

kind = os.environ['KIND']
local_file = os.environ['LOCAL_FILE']
out_file = os.environ['OUT_FILE']

if kind == 'copilot-config':
    with open(local_file) as f:
        data = json.load(f)
    result = {}
    for key in ('banner', 'model'):
        if key in data:
            result[key] = data[key]
    with open(out_file, 'w') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write('\n')
elif kind == 'copilot-mcp':
    with open(local_file) as f:
        data = json.load(f)
    result = json.loads(json.dumps(data))
    servers = result.get('mcpServers')
    if isinstance(servers, dict):
        for _, server in servers.items():
            if isinstance(server, dict):
                server.pop('env', None)
    with open(out_file, 'w') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write('\n')
elif kind == 'codex-config':
    with open(local_file) as f:
        lines = f.readlines()
    result = []
    skip_section = False
    for line in lines:
        if re.match(r'^\s*\[projects\.', line):
            skip_section = True
            continue
        if re.match(r'^\s*\[(?!projects\.)', line):
            skip_section = False
        if skip_section:
            continue
        if re.match(r'^\s*env\s*=\s*\{', line):
            indent = re.match(r'^(\s*)', line).group(1)
            result.append(f'{indent}# env = {{ ... }}  # 已过滤，请在本机手动配置\n')
            continue
        result.append(line)
    with open(out_file, 'w') as f:
        f.write(''.join(result).rstrip('\n') + '\n')
else:
    raise SystemExit(f'unknown kind: {kind}')
PYEOF
  elif _has_node; then
    local node_local_file node_out_file
    node_local_file=$(_node_path_arg "$local_file")
    node_out_file=$(_node_path_arg "$out_file")
    "${NODE_CMD[@]}" - "$kind" "$node_local_file" "$node_out_file" << 'JSEOF'
const fs = require('fs');
const readText = (path) => fs.readFileSync(path, 'utf8').replace(/^\uFEFF/, '');

const [, , kind, localFile, outFile] = process.argv;

if (kind === 'copilot-config') {
  const data = JSON.parse(readText(localFile));
  const result = {};
  for (const key of ['banner', 'model']) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      result[key] = data[key];
    }
  }
  fs.writeFileSync(outFile, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
} else if (kind === 'copilot-mcp') {
  const data = JSON.parse(readText(localFile));
  const result = JSON.parse(JSON.stringify(data));
  const servers = result.mcpServers;
  if (servers && typeof servers === 'object' && !Array.isArray(servers)) {
    for (const server of Object.values(servers)) {
      if (server && typeof server === 'object' && !Array.isArray(server)) {
        delete server.env;
      }
    }
  }
  fs.writeFileSync(outFile, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
} else if (kind === 'codex-config') {
  const rawLines = readText(localFile).replace(/\r\n/g, '\n').split('\n');
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
  fs.writeFileSync(outFile, `${result.join('').replace(/\n*$/, '')}\n`, 'utf8');
} else {
  throw new Error(`unknown kind: ${kind}`);
}
JSEOF
  else
    echo "  ℹ️  未找到可用的 Python 或 node，跳过 $kind 的过滤后对比"
    return 1
  fi

  local normalized_local="$out_file.local"
  local normalized_repo="$out_file.repo"
  _strip_utf8_bom "$out_file" "$normalized_local"
  _strip_utf8_bom "$repo_file" "$normalized_repo"

  ! diff --strip-trailing-cr -q "$normalized_local" "$normalized_repo" > /dev/null 2>&1
}

echo "=== Git 状态 ==="
git -C "$REPO" status --short

echo ""
echo "=== 最近提交 ==="
git -C "$REPO" log --oneline -5

echo ""
echo "=== 本地文件对比 ==="
CHANGED=0

for f in copilot-instructions.md; do
  if [ -f "$HOME/.copilot/$f" ] && [ -f "$REPO/copilot/$f" ]; then
    if _files_differ_ignoring_bom_and_cr "$HOME/.copilot/$f" "$REPO/copilot/$f"; then
      echo "  📝 copilot/$f 有本地未推送的修改"
      CHANGED=1
    fi
  fi
done

if _sanitized_diff "copilot-config" "$HOME/.copilot/config.json" "$REPO/copilot/config.json" "$TMP_DIR/copilot-config.json"; then
  echo "  📝 copilot/config.json 有本地未推送的共享字段修改"
  CHANGED=1
fi

if _sanitized_diff "copilot-mcp" "$HOME/.copilot/mcp-config.json" "$REPO/copilot/mcp-config.json" "$TMP_DIR/copilot-mcp.json"; then
  echo "  📝 copilot/mcp-config.json 有本地未推送的共享配置修改"
  CHANGED=1
fi

for f in CLAUDE.md; do
  if [ -f "$HOME/.claude/$f" ] && [ -f "$REPO/claude/$f" ]; then
    if _files_differ_ignoring_bom_and_cr "$HOME/.claude/$f" "$REPO/claude/$f"; then
      echo "  📝 claude/$f 有本地未推送的修改"
      CHANGED=1
    fi
  fi
done

for f in AGENTS.md; do
  if [ -f "$HOME/.codex/$f" ] && [ -f "$REPO/codex/$f" ]; then
    if _files_differ_ignoring_bom_and_cr "$HOME/.codex/$f" "$REPO/codex/$f"; then
      echo "  📝 codex/$f 有本地未推送的修改"
      CHANGED=1
    fi
  fi
done

if _sanitized_diff "codex-config" "$HOME/.codex/config.toml" "$REPO/codex/config.toml" "$TMP_DIR/codex-config.toml"; then
  echo "  📝 codex/config.toml 有本地未推送的共享配置修改"
  CHANGED=1
fi

if [ "$CHANGED" -eq 0 ]; then
  echo "  ✅ 所有核心配置文件与仓库一致"
else
  echo "  ℹ️  已列出本机尚未推送的共享配置差异"
fi
