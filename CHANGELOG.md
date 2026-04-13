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
- 修复 README 中 Windows `cmd` 安装示例的变量展开问题，改为可直接执行的分行写法
- 修复 Windows PowerShell 5.1 对 `raw.githubusercontent.com` 的 TLS 兼容性问题：README 的 PowerShell / `cmd` 下载命令现在会显式启用 `Tls12`，并避免在下载失败后误执行旧的临时安装脚本
- 修复下载版 `install.ps1` 在 Windows 原生终端里的链路：现在会先由 PowerShell 补齐完整安装 payload，再调用 Git Bash，避免把关键脚本下载留给 Bash 侧处理
- 新增 `scripts/dev-windows-smoke-test.ps1`，用于在 Windows 下回归安装链路与 `.ps1` 包装脚本
- 调整 `scripts/dev-windows-smoke-test.ps1`：默认验证当前工作树的安装 payload，并支持额外 spot check GitHub raw 安装命令
- 调整 `scripts/dev-windows-smoke-test.ps1`：下载安装链路现在会显式模拟 PowerShell 5.1 的 legacy TLS 基线，确保外层下载和 `install.ps1` 内部下载都能自行补齐 `Tls12`
- 调整 `push.sh`、`pull.sh`、`status.sh` 的 Node 回退：仅在原生 Windows POSIX 运行时启用 `node.exe` 探测，并兼容 UTF-8 BOM 与 Windows 路径传递
- 修复 `enable-auto-sync.ps1` 在 `$PROFILE` 为空时的 PowerShell profile 回退路径，避免 Windows 原生终端下写入 hook 失败
- 修复 Windows PowerShell 包装脚本的 UTF-8 控制，避免自动同步日志中的中文输出出现乱码
- 为 `scripts/dev-windows-smoke-test.ps1` 增加 Windows 自动同步真链路回归，覆盖 `auto_pull=true` 的 PowerShell 启动自动拉取与 `auto_push=true` 的 PowerShell 退出自动推送
- 调整 `enable-auto-sync.sh` / `enable-auto-sync.ps1`：重新执行时会自动替换旧 hook，确保升级后能拿到最新自动同步逻辑
- 修复 Unix / WSL 自动同步 hook 在 zsh 场景下误写入 `~/.bashrc` 的问题；现在会根据登录 shell 选择 `~/.bashrc` 或 `~/.zshrc`
- 为 `scripts/dev-smoke-test.sh` 增加 Unix 自动同步回归，覆盖 auto_pull、auto_push 与 shell hook 目标文件选择
- 补齐 Unix / Windows smoke test 矩阵，覆盖 `sync.sh`、`auto_pull` / `auto_push` 在 `true` / `false` 下的正反向回归
- 修复 `pull.sh` 中 Python heredoc 的路径展开风险，避免特殊路径导致合并逻辑报错
- 将“同步配置”默认策略调整为先推送、失败即停，避免本地未推送文件在拉取阶段被镜像删除
- 简化 `push.sh` 的推送失败处理，提供更明确的认证、权限与远端领先排查提示
- 修正“GitHub Copilot CLI 与 `~/.claude` 共用配置”的错误假设，新增真正的 `~/.copilot` 同步支持
- 为 Copilot 增加 `config.json` / `mcp-config.json` 的敏感字段过滤与本机私有字段保留逻辑
- 更新 README、Skill 文档与 smoke test，使 Copilot、Claude Code、Codex 三者的真实同步范围一致
