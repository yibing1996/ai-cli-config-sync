---
name: cli-config-sync
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
| 同步配置 / sync my configs / sync CLI configs | 先 pull 再 push |
| 开启自动同步 / enable auto sync | 配置 shell hook |
| 同步状态 / sync status | 查看差异 |

---

## 同步范围

### GitHub Copilot CLI / Claude Code CLI（`~/.claude/`）

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

## 工作流

### 0. 环境检查

执行 Push / Pull / Sync / Status 前，先检查：

```bash
# 检查配置文件
if [ ! -f "$HOME/.cli-sync/config.yml" ]; then
  echo "⚠️  未找到同步配置，请先执行初始化（说「初始化配置同步」）"
  exit 1
fi

# 检查脚本文件
if [ ! -f "$HOME/.cli-sync/push.sh" ] || [ ! -f "$HOME/.cli-sync/pull.sh" ]; then
  echo "⚠️  push.sh 或 pull.sh 缺失，请重新运行 install.sh"
  exit 1
fi
```

---

### 1. Setup（初始化）

**触发**：「初始化配置同步」或首次使用

**步骤**：

1. 询问用户 Git 远程仓库地址（HTTPS 或 SSH 均可）
2. 创建配置目录
3. Clone 或初始化本地 Git 仓库
4. **自动探测远端默认分支**（不写死 main）
5. 写入配置文件
6. 创建 `.gitignore`
7. **智能判断**：远端有内容 → 先 Pull 恢复配置；远端为空 → 首次 Push

```bash
REMOTE_URL="<用户提供的仓库地址>"
REPO_DIR="$HOME/.cli-sync-repo"
SCRIPTS_DIR="$HOME/.cli-sync"

# 创建目录
mkdir -p "$SCRIPTS_DIR" "$REPO_DIR"

# Clone 或初始化
cd "$REPO_DIR"
HAS_REMOTE_CONTENT=false
BRANCH="main"

if [ "$(ls -A "$REPO_DIR" 2>/dev/null)" ]; then
  echo "仓库目录不为空，跳过初始化"
  BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
elif git ls-remote "$REMOTE_URL" HEAD 2>/dev/null | grep -q .; then
  # 远端有内容（ls-remote 返回了 ref 信息）→ clone
  git clone "$REMOTE_URL" .
  BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
  HAS_REMOTE_CONTENT=true
  echo "✅ 已 clone 远程仓库（分支：$BRANCH）"
else
  # 远端为空或不可访问 → 初始化
  git init
  git remote add origin "$REMOTE_URL"
  # 尝试探测远端默认分支
  DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || true)
  if [ -n "$DEFAULT_BRANCH" ] && [ "$DEFAULT_BRANCH" != "(unknown)" ]; then
    BRANCH="$DEFAULT_BRANCH"
  fi
  git checkout -b "$BRANCH" 2>/dev/null || git branch -m "$BRANCH"
  echo "✅ 已初始化本地仓库（分支：$BRANCH）"
fi

# 写入配置文件（使用探测到的分支名）
cat > "$SCRIPTS_DIR/config.yml" << CONFIGEOF
remote: $REMOTE_URL
branch: $BRANCH
auto_pull: false
auto_push: false
CONFIGEOF

# 创建 .gitignore（仅在不存在时创建，保留用户自定义规则）
if [ ! -f "$REPO_DIR/.gitignore" ]; then
  cat > "$REPO_DIR/.gitignore" << 'GITIGNEOF'
# 认证文件（绝不同步）
auth.json

# SQLite 数据库
*.sqlite
*.sqlite-shm
*.sqlite-wal

# 运行时数据
cache/
sessions/
archived_sessions/
tmp/
.tmp/
logs_*
state_*
history.jsonl
downloads/
debug/
telemetry/
shell-snapshots/
shell_snapshots/
file-history/

# Marketplace 缓存（可从 GitHub 重新下载）
claude/plugins/marketplaces/
codex/vendor_imports/
GITIGNEOF
else
  echo "ℹ️  .gitignore 已存在，保留现有内容"
fi

echo "✅ Setup 完成"
```

**然后根据情况执行**：

- 如果 `$HAS_REMOTE_CONTENT` 为 `true`（远端已有配置）：
  运行 `bash "$HOME/.cli-sync/pull.sh"` 恢复配置到本地，提示「✅ 配置已从云端恢复」
- 否则（远端为空）：
  运行 `bash "$HOME/.cli-sync/push.sh"` 执行首次推送，提示「✅ 配置已首次推送到云端」

---

### 2. Push（推送配置）

**触发**：「推送配置」「push configs」「同步到云端」

直接调用已安装的推送脚本：

```bash
bash "$HOME/.cli-sync/push.sh"
```

---

### 3. Pull（拉取配置）

**触发**：「拉取配置」「pull configs」「从云端同步」

直接调用已安装的拉取脚本：

```bash
bash "$HOME/.cli-sync/pull.sh"
```

---

### 4. 自动同步设置

**触发**：「开启自动同步」「enable auto sync」

**注意：幂等写入，不会重复添加。**

```bash
# 检测 shell 类型
if [ -n "$ZSH_VERSION" ]; then
  SHELL_RC="$HOME/.zshrc"
else
  SHELL_RC="$HOME/.bashrc"
fi

# 幂等检查：已存在则跳过
if grep -q 'cli-config-sync-hook-start' "$SHELL_RC" 2>/dev/null; then
  echo "ℹ️  自动同步 hook 已存在于 $SHELL_RC，无需重复添加"
else
  cat >> "$SHELL_RC" << 'HOOKEOF'

# >>> cli-config-sync-hook-start >>>
if [ -f "$HOME/.cli-sync/config.yml" ] && [ -f "$HOME/.cli-sync/pull.sh" ]; then
  AUTO_PULL=$(grep 'auto_pull:' "$HOME/.cli-sync/config.yml" | grep -i 'true' || true)
  if [ -n "$AUTO_PULL" ]; then
    (bash "$HOME/.cli-sync/pull.sh" > /dev/null 2>&1 &)
  fi
fi

_cli_sync_push_on_exit() {
  if [ -f "$HOME/.cli-sync/config.yml" ]; then
    AUTO_PUSH=$(grep 'auto_push:' "$HOME/.cli-sync/config.yml" | grep -i 'true' || true)
    if [ -n "$AUTO_PUSH" ] && [ -f "$HOME/.cli-sync/push.sh" ]; then
      bash "$HOME/.cli-sync/push.sh" > /dev/null 2>&1
    fi
  fi
}
trap _cli_sync_push_on_exit EXIT
# <<< cli-config-sync-hook-end <<<
HOOKEOF
  echo "✅ 自动同步 hook 已写入 $SHELL_RC"
  echo "💡 请编辑 ~/.cli-sync/config.yml 将 auto_pull 和/或 auto_push 设为 true 来启用"
fi
```

---

### 5. 查看同步状态

**触发**：「同步状态」「sync status」

```bash
REPO="$HOME/.cli-sync-repo"

echo "=== Git 状态 ==="
cd "$REPO" && git status --short

echo ""
echo "=== 最近提交 ==="
git log --oneline -5

echo ""
echo "=== 本地文件对比 ==="
CHANGED=0
for f in CLAUDE.md; do
  if [ -f "$HOME/.claude/$f" ] && [ -f "$REPO/claude/$f" ]; then
    if ! diff -q "$HOME/.claude/$f" "$REPO/claude/$f" > /dev/null 2>&1; then
      echo "  📝 claude/$f 有本地未推送的修改"
      CHANGED=1
    fi
  fi
done
for f in AGENTS.md config.toml; do
  if [ -f "$HOME/.codex/$f" ] && [ -f "$REPO/codex/$f" ]; then
    if ! diff -q "$HOME/.codex/$f" "$REPO/codex/$f" > /dev/null 2>&1; then
      echo "  📝 codex/$f 有本地未推送的修改"
      CHANGED=1
    fi
  fi
done
[ $CHANGED -eq 0 ] && echo "  ✅ 所有核心配置文件与仓库一致"
```

---

## 错误处理

| 错误 | 解决方法 |
|---|---|
| `push.sh 或 pull.sh 不存在` | 重新运行 install.sh 安装脚本 |
| `git push` 认证失败 | 检查 SSH Key 或 Personal Access Token |
| 首次 push 失败（无 upstream） | 已自动尝试 `--set-upstream` |
| merge 冲突 | `cd ~/.cli-sync-repo && git pull --rebase` 后手动解决 |
| `jq` / `python3` 未安装 | `sudo apt install jq`（推荐）；否则 settings.json/config.toml 整体复制 |

---

## 安全注意事项

1. **强烈建议使用私有仓库**，配置文件含个人工作习惯和 MCP 配置
2. `settings.json` 的 `env` 字段（含 API Token）**自动过滤**，还原后需手动重设
3. `config.toml` 的 `[projects.*]` 段（本机路径）和 `env` 字段（可能含 Token）**自动过滤**
4. `auth.json` **永远不同步**，每台机器需独立登录
5. 新机器 Pull 后请检查 `config.toml` 中 MCP server 的命令路径（如 `/home/user/.nvm/...`）是否适配本机
