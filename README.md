# cli-config-sync

将 AI CLI 工具的配置一键同步到 GitHub/Gitee，跨机器共享配置从未如此简单。

支持：**GitHub Copilot CLI** · **Claude Code CLI** · **Codex CLI**

[English](./README_EN.md) | 中文

---

## 痛点

你在公司电脑配置好了 AI CLI 工具：

- 写好了 `CLAUDE.md` / `AGENTS.md` 里的详细指令
- 安装了十几个自定义 Skill
- 配置好了 MCP 服务器（Context7、DeepWiki、Sequential Thinking...）
- 在 `config.toml` 里调好了各种模型参数

然后... 你换了一台电脑，一切从零开始。😩

## 解决方案

**cli-config-sync** 将你的 CLI 配置同步到一个私有 Git 仓库（GitHub 或 Gitee），在任意新机器上一句话就能还原所有配置。

```
你说：初始化配置同步
AI 说：请提供你的 Git 仓库地址...
输入地址后，智能判断远端状态：
  → 远端已有配置：自动拉取恢复 ✅
  → 远端为空：首次推送当前配置 ✅
```

---

## 安装

### 方法一：一行命令安装（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yibing1996/cli-config-sync/main/install.sh)
```

### 方法二：clone 后安装

```bash
git clone https://github.com/yibing1996/cli-config-sync.git
cd cli-config-sync
bash install.sh
```

安装脚本会安装核心脚本，并在 `~/.claude` / `~/.codex` 下写入 Skill；目录不存在时会自动创建。

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
| `同步配置` | 双向同步（先保守拉取，再推送） |
| `推送配置` | 将本地改动推到云端 |
| `拉取配置` | 从云端同步到本地 |
| `同步状态` | 查看哪些文件有本地修改 |
| `开启自动同步` | 设置 shell 启动时自动同步 |

### 换了新机器？

```bash
# 1. 安装 CLI 工具（略）
# 2. 安装 cli-config-sync
bash <(curl -fsSL https://raw.githubusercontent.com/yibing1996/cli-config-sync/main/install.sh)
# 3. 在 CLI 里说：
#    「初始化配置同步」→ 输入你的仓库地址 → 配置自动还原
```

---

## 同步范围

### GitHub Copilot CLI / Claude Code CLI

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
- `settings.json` 的 `env` 字段（含 API Token）**自动过滤**，不会同步
- `config.toml` 的 `[projects.*]` 段（本机路径）和 `env` 字段（可能含 Token）**自动过滤**
- `auth.json`（登录 Token）**永远不同步**，每台机器需独立登录
- 新机器 Pull 后请检查 `config.toml` 中 MCP server 的命令路径是否适配本机
- 其余敏感字段如有需要，可在同步仓库的 `.gitignore` 中手动添加

---

## 系统要求

- `bash`（必须）
- `git`（必须）
- `jq` 或 `python3`（推荐，用于过滤 settings.json / config.toml 敏感字段，以及 Pull 时智能合并）
- `rsync`（可选，用于高效目录同步；无则自动降级为 cp）
- Git 全局身份配置（`git config --global user.name` 和 `user.email`）

自动同步说明：
- 启动时自动拉取使用保守的 `fetch + ff-only` 策略，检测到分叉或未提交变更时会停止，不会静默制造 merge 状态
- 自动同步日志默认写入 `~/.cli-sync/auto-sync.log`

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
