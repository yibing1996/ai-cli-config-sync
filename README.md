# ai-cli-config-sync

将 AI CLI 工具的配置一键同步到 GitHub/Gitee，跨机器共享配置从未如此简单。

支持：**GitHub Copilot CLI** · **Claude Code CLI** · **Codex CLI**

[English](./README_EN.md) | 中文

> 建议使用**私有 Git 仓库**保存真实个人配置，并在自己的多台机器上先完成一轮完整同步验证。

---

## 痛点

你在公司电脑配置好了 AI CLI 工具：

- 写好了 `CLAUDE.md` / `AGENTS.md` 里的详细指令
- 安装了十几个自定义 Skill
- 配置好了 MCP 服务器（Context7、DeepWiki、Sequential Thinking...）
- 在 `config.toml` 里调好了各种模型参数

然后... 你换了一台电脑，一切从零开始。😩

## 解决方案

**ai-cli-config-sync** 将你的 CLI 配置同步到一个私有 Git 仓库（GitHub 或 Gitee），在任意新机器上一句话就能还原所有配置。

```
你说：初始化配置同步
AI 说：请提供你的 Git 仓库地址...
输入地址后，智能判断远端状态：
  → 远端已有配置：自动拉取恢复 ✅
  → 远端为空：首次推送当前配置 ✅
```

---

## 安装

推荐使用建议：

- 优先准备一个 **GitHub 私有仓库**
- 先在一台已配置好的机器上执行一次初始化和推送
- 再在另一台机器上验证拉取恢复是否符合预期
- 确认无误后，再分享给团队成员或用于更大范围场景

### 方法一：一行命令安装（推荐）

**Git Bash / WSL / Linux / macOS：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh)
```

如果你在 **Windows Git Bash** 下遇到进程替换兼容问题，也可以这样执行：

```bash
curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh | bash
```

**Windows PowerShell：**

```powershell
$tmp = Join-Path $env:TEMP "ai-cli-config-sync-install.ps1"
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.ps1" -OutFile $tmp
powershell -NoProfile -ExecutionPolicy Bypass -File "$tmp"
```

**Windows cmd：**

```cmd
set "AI_CLI_SYNC_INSTALL_PS1=%TEMP%\ai-cli-config-sync-install.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.ps1' -OutFile '%AI_CLI_SYNC_INSTALL_PS1%'"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%AI_CLI_SYNC_INSTALL_PS1%"
```

说明：

- 单独执行 `curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh` 只会把脚本内容打印到终端，不会自动安装
- Windows 原生终端推荐走 `install.ps1`；它会自动定位 **Git for Windows 自带的 Git Bash**，避免误用 `C:\Windows\System32\bash.exe` 把流程送进 WSL
- 下载版 `install.ps1` 会先通过 PowerShell 补齐完整安装 payload，再交给 Git Bash 执行，因此不依赖 Bash 侧再去额外下载脚本
- 如果当前 PowerShell 会话启用了脚本执行限制，请用 `powershell -NoProfile -ExecutionPolicy Bypass -File $tmp` 启动下载后的安装脚本，而不要直接 `& $tmp`
- 如果你只想确认 Git 的实际路径，可以在 `cmd` 中执行 `where git`，或在 PowerShell 中执行 `(Get-Command git).Source`
- 如果你在 **WSL** 中执行，配置会安装到 WSL 自己的 `~/.claude` / `~/.codex` / `~/.copilot`，不会写入 Windows 本机用户目录

### 方法二：clone 后安装

```bash
git clone https://github.com/yibing1996/ai-cli-config-sync.git
cd ai-cli-config-sync
```

**Git Bash / WSL / Linux / macOS：**

```bash
bash install.sh
```

**Windows PowerShell / cmd：**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Windows 额外说明：

- 如果你执行 `bash install.sh` 时看到 `$'\r': command not found`，通常不是脚本逻辑有问题，而是 Git 在 clone 时把 `*.sh` 签出成了 `CRLF`
- 这个仓库现在已通过 `.gitattributes` 强制 `*.sh` 使用 `LF`；拉取最新版本后重新 clone 一次通常就能恢复正常
- `git clone` 可以在 `cmd`、PowerShell、Git Bash 中执行；Windows 原生终端推荐直接运行 `install.ps1`
- 如果你想在当前目录先临时修复，也可以执行：

```bash
sed -i 's/\r$//' install.sh scripts/*.sh
bash install.sh
```

安装脚本会把 `install.*`、`setup.*`、`push.*`、`pull.*`、`sync.*`、`status.*`、`enable-auto-sync.*` 安装到 `~/.cli-sync/`，并在 `~/.claude` / `~/.codex` 下写入 Skill；`~/.copilot` 不写入 Skill，但后续 `push.sh` / `pull.sh` 会自动识别并同步受支持的 Copilot 配置。目录不存在时会自动创建。

---

## 使用方法

安装后，打开任意支持的 CLI 工具，用自然语言操作：

### 首次配置（新机器上只需这一步）

```
你：初始化配置同步
AI：请提供你的 Git 仓库地址（支持 GitHub/Gitee）：
你：https://github.com/your-name/my-cli-configs
AI：✅ 初始化完成，智能判断远端状态后自动同步
```

### 日常使用

| 你说 | 效果 |
|---|---|
| `同步配置` | 安全同步（先推送本地改动；失败即停） |
| `推送配置` | 将本地改动推到云端 |
| `拉取配置` | 从云端同步到本地 |
| `同步状态` | 查看哪些文件有本地修改 |
| `开启自动同步` | 设置 shell 启动时自动同步 |

说明：
为避免本机尚未推送的 Skill / Rule / Memory 在拉取阶段被镜像删除，`同步配置` 默认优先推送本地改动；如果推送失败，会直接停止并提示你先处理远端领先、认证或权限问题。

### 换了新机器？

```bash
# 1. 安装 CLI 工具（略）
# 2. 安装 ai-cli-config-sync
bash <(curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh)
# 3. 在 CLI 里说：
#    「初始化配置同步」→ 输入你的仓库地址 → 配置自动还原
```

---

## 同步范围

### GitHub Copilot CLI

| 文件 | 是否同步 | 说明 |
|---|---|---|
| `~/.copilot/copilot-instructions.md` | ✅ | Copilot 指令文件 |
| `~/.copilot/config.json` | ✅ 过滤 / 合并 | 仅同步 `banner`、`model`；保留本机 `copilot_tokens`、登录态、`trusted_folders`、`firstLaunchAt` |
| `~/.copilot/mcp-config.json` | ✅ 过滤 / 合并 | 同步 MCP 配置；远端自动去掉各 server 的 `env`，Pull 时保留本机同名 server 的 `env` |
| `~/.copilot/logs/`、`session-state/` | ❌ | 运行时日志与会话状态 |
| `~/.copilot/command-history-state.json` | ❌ | 本机命令历史状态 |
| `~/.copilot/copilot.bat` 等启动器 | ❌ | 本机启动脚本 |

### Claude Code CLI

| 文件 | 是否同步 | 说明 |
|---|---|---|
| `~/.claude/CLAUDE.md` | ✅ | AI 主指令 |
| `~/.claude/settings.json` | ✅ 过滤 | 去掉 `env`（API Token），其余保留 |
| `~/.claude/skills/` | ✅ | 全部自定义 Skill（镜像同步，含删除） |
| `~/.claude/plugins/blocklist.json` | ✅ | 屏蔽插件列表 |
| `~/.claude/plugins/known_marketplaces.json` | ✅ | 添加的 Marketplace 源 |
| `~/.claude/plugins/marketplaces/` | ❌ | 缓存，可重新下载 |
| `~/.claude/sessions/`、`cache/` 等 | ❌ | 本机私有数据 |

### Codex CLI

| 文件 | 是否同步 | 说明 |
|---|---|---|
| `~/.codex/AGENTS.md` | ✅ | Agent 指令 |
| `~/.codex/config.toml` | ✅ 过滤 | 过滤 `[projects.*]`（本机路径）和 `env`（Token），其余保留 |
| `~/.codex/skills/` | ✅ | 全部自定义 Skill（镜像同步，含删除） |
| `~/.codex/rules/` | ✅ | 规则文件 |
| `~/.codex/memories/` | ✅ | AI 记忆 |
| `~/.codex/auth.json` | ❌ | 登录 Token（各机器独立） |
| `~/.codex/vendor_imports/` | ❌ | 系统自带 Skill 库 |
| `~/.codex/*.sqlite*` 等 | ❌ | 本机运行数据 |

---

## 配置文件

首次初始化后，配置保存在 `~/.cli-sync/config.yml`：

```yaml
remote: https://github.com/your-name/my-cli-configs.git
branch: main
auto_pull: false   # 设为 true：shell 启动时自动 pull
auto_push: false   # 设为 true：shell 退出时自动 push
```

同步数据的本地 Git 仓库位于 `~/.cli-sync-repo/`。

---

## 安全说明

- **强烈建议使用私有仓库**（配置含个人指令和工具习惯）
- `~/.copilot/config.json` 只同步明确安全的共享字段（当前为 `banner`、`model`）；`copilot_tokens`、登录态、`trusted_folders`、`firstLaunchAt` 会保留在本机
- `~/.copilot/mcp-config.json` 会自动过滤各 MCP server 的 `env` 字段；Pull 时会尽量恢复本机已有的 `env`
- `settings.json` 的 `env` 字段（含 API Token）**自动过滤**，不会同步
- `config.toml` 的 `[projects.*]` 段（本机路径）和 `env` 字段（可能含 Token）**自动过滤**
- `auth.json`（登录 Token）**永远不同步**，每台机器需独立登录
- 新机器 Pull 后请检查 `config.toml` 与 `~/.copilot/mcp-config.json` 中 MCP server 的命令路径是否适配本机
- 其余敏感字段如有需要，可在同步仓库的 `.gitignore` 中手动添加

---

## 已知限制

- 当前主要在 **GitHub + WSL / Git Bash / Linux / macOS / Windows PowerShell** 环境下验证；Gitee 与其他环境建议先自行回归测试
- 自动同步使用保守的快进策略；如果本地同步仓库存在分叉、未提交变更或未推送提交，自动拉取会停止而不是强行合并
- `auth.json`、`vendor_imports/`、数据库、会话、缓存等本机运行数据不会同步
- 恢复后请手动检查 `config.toml` 与 `~/.copilot/mcp-config.json` 中和本机路径强相关的 MCP 命令、解释器路径、工作目录等配置
- Windows 原生终端现已支持通过 `install.ps1`、`push.ps1`、`pull.ps1` 等包装脚本运行；如需直接运行 `*.sh`，仍建议使用 Git Bash，并确保仓库中的 `*.sh` 文件保持 `LF` 行尾

---

## 系统要求

- `bash`（必须；Windows 建议安装 Git for Windows，自带 Git Bash）
- `git`（必须）
- `jq`、可用的 Python（`python3` / `python` / Windows 的 `py -3`）或 `node`（推荐，用于过滤 settings.json / config.toml 敏感字段，以及 Pull 时智能合并；若 Windows 上的 `python3` 只是应用商店占位符，脚本会自动回退到 `node`）
- `rsync`（可选，用于高效目录同步；无则自动降级为 cp）
- Git 全局身份配置（`git config --global user.name` 和 `user.email`）

自动同步说明：
- 启动时自动拉取使用保守的 `fetch + ff-only` 策略，检测到分叉或未提交变更时会停止，不会静默制造 merge 状态
- 自动同步日志默认写入 `~/.cli-sync/auto-sync.log`

---

## 本地快速自测

如果你修改了脚本，或想先在本地确认安装与同步链路，建议在项目根目录运行：

```bash
bash scripts/dev-smoke-test.sh
```

这个脚本会检查：

- 核心脚本语法是否正确
- 安装脚本是否能在临时 `HOME` 下完成安装
- `push.sh` 是否会过滤 Claude / Codex / Copilot 的敏感字段
- `pull.sh` 是否会保留本机私有字段（含 Copilot 登录态和 MCP env）
- `pull.sh` 在仓库分叉时是否会安全停止

如果你要在 **Windows 原生终端（PowerShell / cmd）** 下验证安装与 `.ps1` 包装脚本链路，建议额外运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev-windows-smoke-test.ps1
```

这个脚本会在临时用户目录下逐项验证：

- PowerShell / cmd 的安装方式
- `setup.ps1`、`push.ps1`、`pull.ps1`、`sync.ps1`、`status.ps1`、`enable-auto-sync.ps1`
- Windows 下的 Python 占位符回退与 CRLF 差异场景

如果你还想额外 spot check 当前 GitHub 公开安装命令，也可以再执行一次：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev-windows-smoke-test.ps1 -UseRemoteDownload
```

---

## 推荐验证清单

如果你准备在真实配置仓库中使用，建议至少完成以下检查：

- 在本地先运行一次 `bash scripts/dev-smoke-test.sh`
- 用 **GitHub 私有仓库** 跑通一次完整流程，避免在公开仓库里误同步敏感配置
- 在“已配置好的机器”上执行安装、初始化和首次推送，确认远端仓库里已产生预期文件
- 在“全新环境”中验证恢复流程，例如新机器、容器，或使用一个临时 `HOME` 目录
- 在第二台机器恢复成功后，修改 `AGENTS.md`、`CLAUDE.md` 或某个 Skill，再执行一次推送和拉取，确认双向同步正常
- 检查 `settings.json` 的 `env`、`config.toml` 的 `env` 与 `[projects.*]`、以及 `~/.copilot/config.json` 的登录态 / Token / `trusted_folders` 是否按预期保留在本机、未被同步到远端
- 手动触发一次自动同步场景，并查看 `~/.cli-sync/auto-sync.log`，确认没有出现认证失败、分叉或快进失败

推荐最少验证矩阵：

- GitHub 私有仓库 + HTTPS
- GitHub 私有仓库 + SSH
- 至少两台环境：一台“已有配置”，一台“空白环境”

---

## 贡献

欢迎提交 PR！特别欢迎：

- 支持更多 CLI 工具（如 aider、cursor 等）
- 改进敏感数据过滤逻辑
- 完善错误处理
- 翻译文档

---

## License

MIT
