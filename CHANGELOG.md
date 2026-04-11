# 更新日志

这个文件记录项目的重要变更。

版本号在可行范围内遵循语义化版本约定。

## [0.1.0] - 2026-04-11

### 新增

- 补充首个公开版本的中英文说明文档
- 增加推荐验证清单与本地回归说明
- 新增 `scripts/dev-smoke-test.sh`，用于本地快速自测
- 新增 GitHub Actions CI，在 `push` 和 `pull_request` 时自动运行 smoke test

### 调整

- 完善公开 GitHub 仓库的安装说明与初始化引导
- 将项目正式命名统一为 `ai-cli-config-sync`，同步更新仓库链接、安装命令与公开文案
- 加强同步脚本的安全性，包括更保守的拉取策略、同步仓库有效性检查与敏感字段处理
- 修复 `setup.sh` 在复用已有 `~/.cli-sync-repo` 时的方向判断；即使本地同步仓库已存在，只要远端已有内容也会优先执行 Pull 恢复配置
- 为 `push.sh`、`pull.sh`、`status.sh` 增加可执行 Python 探测与 `node` 回退，避免 Windows 上命中 Microsoft Store `python3` 占位符后同步流程中断
- 修复 `status.sh` 在 Windows CRLF 行尾下的误报问题，避免共享配置实际一致时仍显示本地有差异
- 修复 `pull.sh` 中 Python heredoc 的路径展开风险，避免特殊路径导致合并逻辑报错
- 将“同步配置”默认策略调整为先推送、失败即停，避免本地未推送文件在拉取阶段被镜像删除
- 简化 `push.sh` 的推送失败处理，提供更明确的认证、权限与远端领先排查提示
- 修正“GitHub Copilot CLI 与 `~/.claude` 共用配置”的错误假设，新增真正的 `~/.copilot` 同步支持
- 为 Copilot 增加 `config.json` / `mcp-config.json` 的敏感字段过滤与本机私有字段保留逻辑
- 更新 README、Skill 文档与 smoke test，使 Copilot、Claude Code、Codex 三者的真实同步范围一致
