---
name: cli-config-sync
description: 将 AI CLI 工具（Claude Code CLI、GitHub Copilot CLI、Codex CLI）的配置同步到 Git 仓库（GitHub/Gitee）。支持跨机器一键同步 CLAUDE.md、AGENTS.md、Skills、MCP 配置等，自动过滤 API Token 等敏感字段。Use this skill when user mentions syncing CLI configs, setup config sync, push/pull configs, or auto sync.
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
- `settings.json` — 自动过滤 `env` 字段（含 API Token），其余内容保留
- `skills/` — 全部自定义 Skill 目录
- `plugins/blocklist.json` — 屏蔽插件列表
- `plugins/known_marketplaces.json` — 已添加的 Marketplace 源

**不同步：**
- `plugins/marketplaces/` — marketplace 缓存（可从 GitHub 重新下载）
- `history.jsonl`、`sessions/`、`cache/`、`debug/`、`downloads/`、`telemetry/`

### Codex CLI（`~/.codex/`）

**同步：**
- `AGENTS.md` — Agent 指令文件
- `config.toml` — MCP 配置、模型参数、项目信任列表
- `skills/` — 全部自定义 Skill 目录
- `rules/` — 规则文件
- `memories/` — AI 记忆文件

**不同步：**
- `auth.json` — 登录 Token（各机器独立登录）
- `vendor_imports/` — 系统自带 Skill 库（可重新安装）
- `*.sqlite*`、`logs_*`、`state_*`、`cache/`、`sessions/`、`archived_sessions/`、`tmp/`、`.tmp/`

---

## 工作流

### 0. 每次触发前先检查

```bash
CONFIG_FILE="$HOME/.cli-sync/config.yml"
REPO_DIR="$HOME/.cli-sync-repo"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "⚠️  未找到同步配置，请先执行初始化（说「初始化配置同步」）"
  exit 1
fi

REMOTE=$(grep '^remote:' "$CONFIG_FILE" | sed 's/remote: *//')
BRANCH=$(grep '^branch:' "$CONFIG_FILE" | sed 's/branch: *//' | tr -d '[:space:]')
BRANCH=${BRANCH:-main}
```

---

### 1. Setup（初始化）

**触发**：「初始化配置同步」或首次使用

**步骤**：

1. 询问用户 Git 远程仓库地址（HTTPS 或 SSH 均可）
2. 创建配置目录和配置文件
3. 初始化或 clone 本地 Git 仓库
4. 创建 `.gitignore`
5. 生成 `push.sh` 和 `pull.sh` 辅助脚本
6. 执行首次推送

```bash
REMOTE_URL="<用户提供的仓库地址>"
REPO_DIR="$HOME/.cli-sync-repo"
SCRIPTS_DIR="$HOME/.cli-sync"

# 创建目录
mkdir -p "$SCRIPTS_DIR" "$REPO_DIR"

# 写入配置文件
cat > "$SCRIPTS_DIR/config.yml" << CONFIGEOF
remote: $REMOTE_URL
branch: main
auto_pull: false
auto_push: false
CONFIGEOF

# 初始化 Git 仓库
cd "$REPO_DIR"
if [ "$(ls -A "$REPO_DIR")" ]; then
  echo "仓库目录不为空，跳过初始化"
else
  if git ls-remote "$REMOTE_URL" HEAD > /dev/null 2>&1; then
    git clone "$REMOTE_URL" . && echo "✅ 已 clone 远程仓库"
  else
    git init
    git remote add origin "$REMOTE_URL"
    git checkout -b main 2>/dev/null || git branch -m main
    echo "✅ 已初始化本地仓库"
  fi
fi

# 创建 .gitignore
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

echo "✅ Setup 完成，接下来执行首次推送..."
```

然后立即执行 Push 工作流（见下方）。

---

### 2. Push（推送配置）

**触发**：「推送配置」「push configs」「同步到云端」

```bash
#!/usr/bin/env bash
set -e

REPO="$HOME/.cli-sync-repo"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

echo "📦 收集配置文件..."

# ── GitHub Copilot CLI / Claude Code CLI ──────────────────────────────────────
mkdir -p "$REPO/claude/plugins" "$REPO/claude/skills"

# CLAUDE.md
[ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$REPO/claude/"

# settings.json（过滤 env 字段）
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  if command -v jq &> /dev/null; then
    jq 'del(.env)' "$CLAUDE_DIR/settings.json" > "$REPO/claude/settings.json"
  elif command -v python3 &> /dev/null; then
    python3 - << 'PYEOF'
import json, os
src = os.path.expanduser('~/.claude/settings.json')
dst = os.path.expanduser('~/.cli-sync-repo/claude/settings.json')
with open(src) as f:
    d = json.load(f)
d.pop('env', None)
with open(dst, 'w') as f:
    json.dump(d, f, indent=2)
PYEOF
  else
    echo "⚠️  未找到 jq 或 python3，settings.json 将完整复制（含 env 字段，请确保使用私有仓库）"
    cp "$CLAUDE_DIR/settings.json" "$REPO/claude/"
  fi
fi

# plugins 配置文件
[ -f "$CLAUDE_DIR/plugins/blocklist.json" ] && cp "$CLAUDE_DIR/plugins/blocklist.json" "$REPO/claude/plugins/"
[ -f "$CLAUDE_DIR/plugins/known_marketplaces.json" ] && cp "$CLAUDE_DIR/plugins/known_marketplaces.json" "$REPO/claude/plugins/"

# skills（全量同步）
if [ -d "$CLAUDE_DIR/skills" ]; then
  if command -v rsync &> /dev/null; then
    rsync -a --delete "$CLAUDE_DIR/skills/" "$REPO/claude/skills/"
  else
    rm -rf "$REPO/claude/skills" && cp -r "$CLAUDE_DIR/skills" "$REPO/claude/skills"
  fi
fi

# ── Codex CLI ──────────────────────────────────────────────────────────────────
if [ -d "$CODEX_DIR" ]; then
  mkdir -p "$REPO/codex/skills" "$REPO/codex/rules" "$REPO/codex/memories"

  [ -f "$CODEX_DIR/AGENTS.md" ] && cp "$CODEX_DIR/AGENTS.md" "$REPO/codex/"
  [ -f "$CODEX_DIR/config.toml" ] && cp "$CODEX_DIR/config.toml" "$REPO/codex/"

  _sync_dir() {
    local src="$1" dst="$2"
    [ -d "$src" ] || return 0
    if command -v rsync &> /dev/null; then
      rsync -a --delete "$src/" "$dst/"
    else
      rm -rf "$dst" && cp -r "$src" "$dst"
    fi
  }

  _sync_dir "$CODEX_DIR/skills"   "$REPO/codex/skills"
  _sync_dir "$CODEX_DIR/rules"    "$REPO/codex/rules"
  _sync_dir "$CODEX_DIR/memories" "$REPO/codex/memories"
fi

# ── Git 提交推送 ───────────────────────────────────────────────────────────────
cd "$REPO"
git add -A

if git diff --cached --quiet; then
  echo "✅ 配置无变化，无需推送"
else
  COMMIT_MSG="sync: $(date '+%Y-%m-%d %H:%M:%S') from $(hostname)"
  git commit -m "$COMMIT_MSG"
  REMOTE=$(grep '^remote:' "$HOME/.cli-sync/config.yml" | sed 's/remote: *//')
  BRANCH=$(grep '^branch:' "$HOME/.cli-sync/config.yml" | sed 's/branch: *//' | tr -d '[:space:]')
  git push "$REMOTE" "${BRANCH:-main}" 2>&1 || \
    git push --set-upstream origin "${BRANCH:-main}"
  echo "🚀 配置已推送到 $REMOTE"
fi
```

---

### 3. Pull（拉取配置）

**触发**：「拉取配置」「pull configs」「从云端同步」或新机器初次安装后

```bash
#!/usr/bin/env bash
set -e

REPO="$HOME/.cli-sync-repo"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

REMOTE=$(grep '^remote:' "$HOME/.cli-sync/config.yml" | sed 's/remote: *//')
BRANCH=$(grep '^branch:' "$HOME/.cli-sync/config.yml" | sed 's/branch: *//' | tr -d '[:space:]')

echo "🔄 从远程拉取配置..."
cd "$REPO"
git pull "$REMOTE" "${BRANCH:-main}"

echo "📋 还原配置文件..."

# ── GitHub Copilot CLI / Claude Code CLI ──────────────────────────────────────
mkdir -p "$CLAUDE_DIR/plugins" "$CLAUDE_DIR/skills"

[ -f "$REPO/claude/CLAUDE.md" ] && cp "$REPO/claude/CLAUDE.md" "$CLAUDE_DIR/"
[ -f "$REPO/claude/settings.json" ] && cp "$REPO/claude/settings.json" "$CLAUDE_DIR/"
[ -f "$REPO/claude/plugins/blocklist.json" ] && cp "$REPO/claude/plugins/blocklist.json" "$CLAUDE_DIR/plugins/"
[ -f "$REPO/claude/plugins/known_marketplaces.json" ] && cp "$REPO/claude/plugins/known_marketplaces.json" "$CLAUDE_DIR/plugins/"

if [ -d "$REPO/claude/skills" ]; then
  if command -v rsync &> /dev/null; then
    rsync -a "$REPO/claude/skills/" "$CLAUDE_DIR/skills/"
  else
    cp -r "$REPO/claude/skills/." "$CLAUDE_DIR/skills/"
  fi
fi

# ── Codex CLI ──────────────────────────────────────────────────────────────────
if [ -d "$REPO/codex" ] && [ -d "$CODEX_DIR" ]; then
  [ -f "$REPO/codex/AGENTS.md" ] && cp "$REPO/codex/AGENTS.md" "$CODEX_DIR/"
  [ -f "$REPO/codex/config.toml" ] && cp "$REPO/codex/config.toml" "$CODEX_DIR/"

  _restore_dir() {
    local src="$1" dst="$2"
    [ -d "$src" ] || return 0
    mkdir -p "$dst"
    if command -v rsync &> /dev/null; then
      rsync -a "$src/" "$dst/"
    else
      cp -r "$src/." "$dst/"
    fi
  }

  _restore_dir "$REPO/codex/skills"   "$CODEX_DIR/skills"
  _restore_dir "$REPO/codex/rules"    "$CODEX_DIR/rules"
  _restore_dir "$REPO/codex/memories" "$CODEX_DIR/memories"
fi

echo "✅ 配置还原完成"
echo "📝 注意：settings.json 的 env 字段（API Token）未同步，如需设置请手动配置"
```

---

### 4. 自动同步设置

**触发**：「开启自动同步」「enable auto sync」

检测当前 shell 类型，向 `~/.bashrc` 或 `~/.zshrc` 追加以下内容：

```bash
# 检测 shell 类型
SHELL_RC=""
if [ -n "$ZSH_VERSION" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
  SHELL_RC="$HOME/.bashrc"
fi

# 写入 auto-sync hook
cat >> "$SHELL_RC" << 'HOOKEOF'

# CLI 配置自动同步 (by cli-config-sync)
if [ -f "$HOME/.cli-sync/config.yml" ] && [ -f "$HOME/.cli-sync/pull.sh" ]; then
  # 启动时静默后台拉取
  AUTO_PULL=$(grep 'auto_pull:' "$HOME/.cli-sync/config.yml" | grep -i 'true' || true)
  if [ -n "$AUTO_PULL" ]; then
    (bash "$HOME/.cli-sync/pull.sh" > /dev/null 2>&1 &)
  fi
fi

# 退出时自动推送
_cli_sync_push_on_exit() {
  if [ -f "$HOME/.cli-sync/config.yml" ]; then
    AUTO_PUSH=$(grep 'auto_push:' "$HOME/.cli-sync/config.yml" | grep -i 'true' || true)
    if [ -n "$AUTO_PUSH" ] && [ -f "$HOME/.cli-sync/push.sh" ]; then
      bash "$HOME/.cli-sync/push.sh" > /dev/null 2>&1
    fi
  fi
}
trap _cli_sync_push_on_exit EXIT
HOOKEOF

echo "✅ 自动同步 hook 已写入 $SHELL_RC"
echo "💡 请编辑 ~/.cli-sync/config.yml 将 auto_pull 和/或 auto_push 设为 true 来启用"
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

## 生成辅助脚本（Setup 时执行）

Setup 完成后，将上方 Push 和 Pull 工作流的代码保存为独立脚本：

```bash
SCRIPTS_DIR="$HOME/.cli-sync"

# 将 Push 工作流代码保存为 push.sh
cat > "$SCRIPTS_DIR/push.sh" << 'PUSHEOF'
# （此处粘贴完整的 Push 工作流代码）
PUSHEOF
chmod +x "$SCRIPTS_DIR/push.sh"

# 将 Pull 工作流代码保存为 pull.sh
cat > "$SCRIPTS_DIR/pull.sh" << 'PULLEOF'
# （此处粘贴完整的 Pull 工作流代码）
PULLEOF
chmod +x "$SCRIPTS_DIR/pull.sh"

echo "✅ 辅助脚本已生成：$SCRIPTS_DIR/push.sh 和 $SCRIPTS_DIR/pull.sh"
```

**实际执行时，请直接将 Push/Pull 工作流中的完整代码写入对应文件，而不是用占位符。**

---

## 错误处理

| 错误 | 解决方法 |
|---|---|
| `git push` 失败（403/认证失败） | 检查 SSH Key 或 Personal Access Token；HTTPS 建议使用 Token 作为密码 |
| `git push` 首次失败（无 upstream） | 改用 `git push --set-upstream origin main` |
| merge 冲突 | `cd ~/.cli-sync-repo && git pull --rebase`，手动解决冲突后 `git push` |
| `jq` 未安装 | `sudo apt install jq`（Linux）或 `brew install jq`（macOS） |
| `rsync` 未安装 | `sudo apt install rsync`（Linux）或 `brew install rsync`（macOS）；已提供 cp 兜底 |

---

## 安全注意事项

1. **强烈建议使用私有仓库**，配置文件含个人工作习惯和 MCP 配置
2. `settings.json` 的 `env` 字段已自动过滤，还原后需手动重设 API Token
3. `auth.json` 永远不会同步，每台机器需独立登录
4. `config.toml` 的 `[projects.*]` 信任路径含本机绝对路径，新机器 pull 后请检查并按需修改
