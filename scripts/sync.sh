#!/usr/bin/env bash
# sync.sh — 安全同步：先推送，失败即停
set -euo pipefail

if bash "$HOME/.cli-sync/push.sh"; then
  echo "✅ 已优先完成本地配置推送"
  echo "ℹ️  如需恢复其他机器刚推送的配置，请先确认本机没有未推送的新文件，再手动执行「拉取配置」"
else
  echo "⚠️  已停止同步流程，未自动执行拉取"
  echo "   建议先执行「同步状态」检查差异，再决定是否手动拉取"
  exit 1
fi
