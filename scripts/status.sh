#!/usr/bin/env bash
# status.sh — 查看同步仓库状态与本地共享配置差异
set -euo pipefail

REPO="$HOME/.cli-sync-repo"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

_sanitized_diff() {
  local kind="$1" local_file="$2" repo_file="$3" out_file="$4"
  [ -f "$local_file" ] && [ -f "$repo_file" ] || return 1

  if ! command -v python3 >/dev/null 2>&1; then
    echo "  ℹ️  未找到 python3，跳过 $kind 的过滤后对比"
    return 1
  fi

  KIND="$kind" LOCAL_FILE="$local_file" OUT_FILE="$out_file" python3 << 'PYEOF'
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

  ! diff -q "$out_file" "$repo_file" > /dev/null 2>&1
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
    if ! diff -q "$HOME/.copilot/$f" "$REPO/copilot/$f" > /dev/null 2>&1; then
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
    if ! diff -q "$HOME/.claude/$f" "$REPO/claude/$f" > /dev/null 2>&1; then
      echo "  📝 claude/$f 有本地未推送的修改"
      CHANGED=1
    fi
  fi
done

for f in AGENTS.md; do
  if [ -f "$HOME/.codex/$f" ] && [ -f "$REPO/codex/$f" ]; then
    if ! diff -q "$HOME/.codex/$f" "$REPO/codex/$f" > /dev/null 2>&1; then
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
