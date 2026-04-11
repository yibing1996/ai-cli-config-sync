#!/usr/bin/env bash
# enable-auto-sync.sh — 为 bash/zsh 添加自动同步 hook
set -euo pipefail

if [ -n "${ZSH_VERSION:-}" ]; then
  SHELL_RC="$HOME/.zshrc"
else
  SHELL_RC="$HOME/.bashrc"
fi

LOG_FILE="$HOME/.cli-sync/auto-sync.log"

if grep -q 'ai-cli-config-sync-hook-start' "$SHELL_RC" 2>/dev/null; then
  echo "ℹ️  自动同步 hook 已存在于 $SHELL_RC，无需重复添加"
  exit 0
fi

cat >> "$SHELL_RC" << 'HOOKEOF'

# >>> ai-cli-config-sync-hook-start >>>
if [ -f "$HOME/.cli-sync/config.yml" ] && [ -f "$HOME/.cli-sync/pull.sh" ]; then
  mkdir -p "$HOME/.cli-sync"
  LOG_FILE="$HOME/.cli-sync/auto-sync.log"
  AUTO_PULL=$(grep 'auto_pull:' "$HOME/.cli-sync/config.yml" | grep -i 'true' || true)
  if [ -n "$AUTO_PULL" ]; then
    (bash "$HOME/.cli-sync/pull.sh" >> "$LOG_FILE" 2>&1 &)
  fi
fi

_cli_sync_push_on_exit() {
  if [ -f "$HOME/.cli-sync/config.yml" ]; then
    mkdir -p "$HOME/.cli-sync"
    LOG_FILE="$HOME/.cli-sync/auto-sync.log"
    AUTO_PUSH=$(grep 'auto_push:' "$HOME/.cli-sync/config.yml" | grep -i 'true' || true)
    if [ -n "$AUTO_PUSH" ] && [ -f "$HOME/.cli-sync/push.sh" ]; then
      bash "$HOME/.cli-sync/push.sh" >> "$LOG_FILE" 2>&1 || true
    fi
  fi
}
trap _cli_sync_push_on_exit EXIT
# <<< ai-cli-config-sync-hook-end <<<
HOOKEOF

echo "✅ 自动同步 hook 已写入 $SHELL_RC"
echo "💡 请编辑 ~/.cli-sync/config.yml 将 auto_pull 和/或 auto_push 设为 true 来启用"
