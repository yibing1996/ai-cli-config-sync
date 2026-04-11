---
name: ai-cli-config-sync
description: 将 AI CLI 工具（Claude Code CLI、GitHub Copilot CLI、Codex CLI）的配置同步到 Git 仓库（GitHub/Gitee）。支持跨机器一键同步 CLAUDE.md、AGENTS.md、Skills、MCP 配置等，自动过滤敏感字段。Use this skill when user mentions syncing CLI configs, setup config sync, push/pull configs, or auto sync.
---

# CLI 配置云同步

## 功能说明

将多个 AI CLI 工具的配置文件同步到 Git 仓库，实现跨机器配置共享。支持 GitHub、Gitee 等任意 Git 托管服务。

## 触发关键词

| 关键词 | 操作 |
|---|---|
| 初始化配置同步 / setup config sync | Setup 初始化 |
| 推送配置 / push configs / 同步到云端 | 推送到远程 |
| 拉取配置 / pull configs / 从云端同步 | 从远程拉取 |
| 同步配置 / sync my configs / sync CLI configs | 安全同步（先推送，失败即停） |
| 开启自动同步 / enable auto sync | 配置 shell hook |
| 同步状态 / sync status | 查看差异 |

---

## 同步范围

### GitHub Copilot CLI（`~/.copilot/`）

**同步：**
- `copilot-instructions.md` — Copilot 指令文件
- `config.json` — 仅同步 `banner`、`model`；保留本机 `copilot_tokens`、登录态、`trusted_folders`、`firstLaunchAt`
- `mcp-config.json` — 同步 MCP 配置；远端自动过滤各 server 的 `env`，Pull 时保留本机同名 server 的 `env`

**不同步：**
- `logs/`、`session-state/`、`command-history-state.json`
- `copilot.bat` 等本机启动器

### Claude Code CLI（`~/.claude/`）

**同步：**
- `CLAUDE.md` — AI 主指令文件
- `settings.json` — 自动过滤 `env` 字段（含 API Token），其余保留
- `skills/` — 全部自定义 Skill（镜像同步，含删除）
- `plugins/blocklist.json` — 屏蔽插件列表
- `plugins/known_marketplaces.json` — 已添加的 Marketplace 源

**不同步：**
- `plugins/marketplaces/` — marketplace 缓存（可重新下载）
- `history.jsonl`、`sessions/`、`cache/`、`debug/`、`downloads/`、`telemetry/`

### Codex CLI（`~/.codex/`）

**同步：**
- `AGENTS.md` — Agent 指令文件
- `config.toml` — 自动过滤 `[projects.*]` 段（本机路径）和 `env` 字段（可能含 Token），其余保留
- `skills/` — 全部自定义 Skill（镜像同步，含删除）
- `rules/` — 规则文件
- `memories/` — AI 记忆文件

**不同步：**
- `auth.json` — 登录 Token（各机器独立登录）
- `vendor_imports/` — 系统自带 Skill 库（可重新安装）
- `*.sqlite*`、`logs_*`、`state_*`、`cache/`、`sessions/`、`archived_sessions/`、`tmp/`、`.tmp/`

---

## 运行时分流规则

- **Windows 原生终端（PowerShell / cmd）**：统一调用 `~/.cli-sync/*.ps1`
- **Git Bash / MSYS / WSL / Linux / macOS**：统一调用 `~/.cli-sync/*.sh`
- **不要在 Windows 原生终端里直接运行裸 `bash`**。`C:\Windows\System32\bash.exe` 很可能只是 WSL launcher，会把流程送进 `/home/...`，导致 `HOME`、Git 凭证和同步目录全部错位
- 如果入口脚本缺失：
  - Windows 原生终端：重新运行 `~/.cli-sync/install.ps1`
  - Git Bash / WSL / Linux / macOS：重新运行 `~/.cli-sync/install.sh`

---

## 工作流

### 0. 环境检查

执行 Setup / Push / Pull / Sync / Status / 自动同步前，先检查：

- `~/.cli-sync/config.yml` 是否存在；若不存在，先执行初始化
- 对应运行时的入口脚本是否存在：
  - Windows 原生终端：`~/.cli-sync/install.ps1`、`push.ps1`、`pull.ps1`
  - Git Bash / WSL / Linux / macOS：`~/.cli-sync/install.sh`、`push.sh`、`pull.sh`

---

### 1. Setup（初始化）

**触发**：「初始化配置同步」或首次使用

**步骤**：

1. 询问用户 Git 远程仓库地址（HTTPS 或 SSH 均可）
2. 运行安装好的 Setup 脚本；脚本会自动完成：
   - 创建 `~/.cli-sync/` 和 `~/.cli-sync-repo/`
   - 验证远端可访问性
   - Clone / 初始化同步仓库
   - 自动探测远端默认分支或首个可用分支
   - 写入 `~/.cli-sync/config.yml`
   - 创建 `.gitignore`
   - **智能判断**：远端有内容 → 先 Pull 恢复配置；远端为空 → 首次 Push

**Windows 原生终端（PowerShell / cmd）**：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\.cli-sync\setup.ps1" -RemoteUrl "<用户提供的仓库地址>"
```

**Git Bash / WSL / Linux / macOS**：

```bash
bash "$HOME/.cli-sync/setup.sh" "<用户提供的仓库地址>"
```

---

### 2. Push（推送配置）

**触发**：「推送配置」「push configs」「同步到云端」

**Windows 原生终端（PowerShell / cmd）**：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\.cli-sync\push.ps1"
```

**Git Bash / WSL / Linux / macOS**：

```bash
bash "$HOME/.cli-sync/push.sh"
```

---

### 3. Pull（拉取配置）

**触发**：「拉取配置」「pull configs」「从云端同步」

**Windows 原生终端（PowerShell / cmd）**：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\.cli-sync\pull.ps1"
```

**Git Bash / WSL / Linux / macOS**：

```bash
bash "$HOME/.cli-sync/pull.sh"
```

---

### 4. Sync（安全同步）

**触发**：「同步配置」「sync my configs」「sync CLI configs」

**策略：先推送本地改动；如果推送失败则停止，不自动执行拉取，避免本地尚未推送的 Skill / Rule / Memory 被远端镜像删除。**

**Windows 原生终端（PowerShell / cmd）**：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\.cli-sync\sync.ps1"
```

**Git Bash / WSL / Linux / macOS**：

```bash
bash "$HOME/.cli-sync/sync.sh"
```

---

### 5. 自动同步设置

**触发**：「开启自动同步」「enable auto sync」

**注意：幂等写入，不会重复添加；自动拉取使用保守的 `fetch + ff-only` 策略，失败信息会写入日志。**

**Windows 原生终端（PowerShell / cmd）**：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\.cli-sync\enable-auto-sync.ps1"
```

PowerShell 版会：

- 把自动同步 hook 写入 `$PROFILE`
- 启动 PowerShell 时根据 `auto_pull: true` 后台执行 `pull.ps1`
- 通过 `Register-EngineEvent PowerShell.Exiting` 在退出时按 `auto_push: true` 触发 `push.ps1`

**Git Bash / WSL / Linux / macOS**：

```bash
bash "$HOME/.cli-sync/enable-auto-sync.sh"
```

---

### 6. 查看同步状态

**触发**：「同步状态」「sync status」

**Windows 原生终端（PowerShell / cmd）**：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\.cli-sync\status.ps1"
```

**Git Bash / WSL / Linux / macOS**：

```bash
bash "$HOME/.cli-sync/status.sh"
```

---

## 错误处理

| 错误 | 解决方法 |
|---|---|
| `push.sh / pull.sh / *.ps1 不存在` | Windows 原生终端重新运行 `~/.cli-sync/install.ps1`；Git Bash / WSL / Linux / macOS 重新运行 `~/.cli-sync/install.sh` |
| `~/.cli-sync-repo` 不是有效 Git 仓库 | 备份后删除该目录，重新执行初始化 |
| `git push` 认证失败 | 检查 SSH Key 或 Personal Access Token |
| 自动 pull 失败 | 查看 `~/.cli-sync/auto-sync.log`，确认是否存在分叉、未提交变更或认证失败 |
| 推送失败 | 检查远端地址、认证、网络和仓库权限；若远端已领先，先执行拉取并处理差异 |
| merge 冲突 | `cd ~/.cli-sync-repo && git pull --rebase` 后手动解决 |
| Windows 原生终端里出现 `/bin/bash: ... ~/.cli-sync/*.sh: No such file or directory` | 说明误走了 WSL 的 `bash.exe`；请改用 `~/.cli-sync/*.ps1`，不要在 PowerShell / cmd 里直接调用裸 `bash` |
| `jq` / `python3` 未安装 | `sudo apt install jq python3`（推荐）；否则部分 JSON 合并会降级，Copilot 敏感字段不会自动安全过滤 |

---

## 安全注意事项

1. **强烈建议使用私有仓库**，配置文件含个人工作习惯和 MCP 配置
2. `~/.copilot/config.json` 仅同步明确安全的共享字段；`copilot_tokens`、登录态、`trusted_folders`、`firstLaunchAt` 保留在本机
3. `~/.copilot/mcp-config.json` 会自动过滤各 MCP server 的 `env`；新机器 Pull 后请检查命令路径是否适配本机
4. `settings.json` 的 `env` 字段（含 API Token）**自动过滤**，还原后需手动重设
5. `config.toml` 的 `[projects.*]` 段（本机路径）和 `env` 字段（可能含 Token）**自动过滤**
6. `auth.json` **永远不同步**，每台机器需独立登录
7. 新机器 Pull 后请检查 `config.toml` 中 MCP server 的命令路径（如 `/home/user/.nvm/...`）是否适配本机
