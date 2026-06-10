#!/usr/bin/env bash
# sync.sh — 安全同步：先拉取合并远端，再提交并推送本地配置
set -euo pipefail

if bash "$HOME/.cli-sync/push.sh"; then
  echo "✅ 已完成远端合并与本地配置推送"
  echo "ℹ️  如需把远端配置还原到本机，请确认本机私有文件已备份，再手动执行「拉取配置」"
else
  echo "⚠️  已停止同步流程，未完成配置推送"
  echo "   建议先执行「同步状态」检查差异，再处理 Git 冲突或认证问题"
  exit 1
fi
