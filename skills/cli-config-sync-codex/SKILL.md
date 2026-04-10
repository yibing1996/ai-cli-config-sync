---
name: cli-config-sync
description: 将 AI CLI 工具（Codex CLI、Claude Code CLI、GitHub Copilot CLI）的配置同步到 Git 仓库（GitHub/Gitee）。支持跨机器一键同步 AGENTS.md、CLAUDE.md、Skills、MCP 配置等，自动过滤敏感字段。Use this skill when user mentions syncing CLI configs, setup config sync, push/pull configs, or auto sync.
---

# CLI 配置云同步（Codex CLI 版）

## 功能说明

将多个 AI CLI 工具的配置文件同步到 Git 仓库，实现跨机器配置共享。支持 GitHub、Gitee 等任意 Git 托管服务。

> 本 Skill 与 GitHub Copilot CLI / Claude Code CLI 版本功能完全一致，仅在工具调用方式上适配 Codex CLI。

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
4. **自动探测远端默认分支或首个可用分支**（不写死 main）
5. 写入配置文件
6. 创建 `.gitignore`
7. **智能判断**：远端有内容 → 先 Pull 恢复配置；远端为空 → 首次 Push

```bash
REMOTE_URL="<用户提供的仓库地址>"
REPO_DIR="$HOME/.cli-sync-repo"
SCRIPTS_DIR="$HOME/.cli-sync"

# 创建目录
mkdir -p "$SCRIPTS_DIR" "$REPO_DIR"

# Clone、复用或初始化同步仓库
cd "$REPO_DIR"
HAS_REMOTE_CONTENT=false
BRANCH="main"

if [ "$(ls -A "$REPO_DIR" 2>/dev/null)" ]; then
  if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "检测到已有同步仓库，复用现有仓库"
    BRANCH=$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "main")
  else
    echo "❌ $REPO_DIR 已存在且非空，但不是有效 Git 仓库"
    echo "   请备份后删除该目录，再重新初始化"
    exit 1
  fi
else
  # 第一步：验证远端是否可访问
  if ! git ls-remote "$REMOTE_URL" &>/dev/null; then
    echo "❌ 无法访问远端仓库：$REMOTE_URL"
    echo "   请检查：1) 仓库地址是否正确  2) 网络连接  3) 认证配置（SSH key 或 Token）"
    exit 1
  fi

  # 第二步：判断远端是否有分支内容（用 --heads 检查所有分支，比只检查 HEAD 更可靠）
  if git ls-remote --heads "$REMOTE_URL" 2>/dev/null | grep -q .; then
    # 远端有分支 → clone
    git clone "$REMOTE_URL" .
    HAS_REMOTE_CONTENT=true

    # 优先使用远端默认分支；若远端 HEAD 未正确指向，再退回到首个可用分支
    DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || true)
    if [ -z "$DEFAULT_BRANCH" ] || [ "$DEFAULT_BRANCH" = "(unknown)" ]; then
      DEFAULT_BRANCH=$(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin | head -n 1)
    fi

    if [ -n "$DEFAULT_BRANCH" ]; then
      BRANCH="$DEFAULT_BRANCH"
      CURRENT_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
      if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
        git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
      fi
    else
      BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "main")
    fi

    echo "✅ 已 clone 远程仓库（分支：$BRANCH）"
  else
    # 远端可访问但无分支（空仓库） → 本地初始化
    git init
    git remote add origin "$REMOTE_URL"
    git checkout -b "$BRANCH" 2>/dev/null || git branch -m "$BRANCH"
    echo "✅ 已初始化本地仓库（分支：$BRANCH）"
  fi
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
copilot/logs/
copilot/session-state/
copilot/command-history-state.json
copilot/copilot.bat
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

### 4. Sync（安全同步）

**触发**：「同步配置」「sync my configs」「sync CLI configs」

**策略：先推送本地改动；如果推送失败则停止，不自动执行拉取，避免本地尚未推送的 Skill / Rule / Memory 被远端镜像删除。**

```bash
if bash "$HOME/.cli-sync/push.sh"; then
  echo "✅ 已优先完成本地配置推送"
  echo "ℹ️  如需恢复其他机器刚推送的配置，请先确认本机没有未推送的新文件，再手动执行「拉取配置」"
else
  echo "⚠️  已停止同步流程，未自动执行拉取"
  echo "   建议先执行「同步状态」检查差异，再决定是否手动拉取"
  exit 1
fi
```

---

### 5. 自动同步设置

**触发**：「开启自动同步」「enable auto sync」

**注意：幂等写入，不会重复添加；自动拉取使用保守的 `fetch + ff-only` 策略，失败信息会写入日志。**

```bash
# 检测 shell 类型
if [ -n "$ZSH_VERSION" ]; then
  SHELL_RC="$HOME/.zshrc"
else
  SHELL_RC="$HOME/.bashrc"
fi

LOG_FILE="$HOME/.cli-sync/auto-sync.log"

# 幂等检查：已存在则跳过
if grep -q 'cli-config-sync-hook-start' "$SHELL_RC" 2>/dev/null; then
  echo "ℹ️  自动同步 hook 已存在于 $SHELL_RC，无需重复添加"
else
  cat >> "$SHELL_RC" << 'HOOKEOF'

# >>> cli-config-sync-hook-start >>>
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
# <<< cli-config-sync-hook-end <<<
HOOKEOF
  echo "✅ 自动同步 hook 已写入 $SHELL_RC"
  echo "💡 编辑 ~/.cli-sync/config.yml 将 auto_pull 和/或 auto_push 设为 true 来启用"
fi
```

---

### 6. 查看同步状态

**触发**：「同步状态」「sync status」

```bash
REPO="$HOME/.cli-sync-repo"
TMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

_sanitized_diff() {
  local kind="$1" local_file="$2" repo_file="$3" out_file="$4"
  [ -f "$local_file" ] && [ -f "$repo_file" ] || return 1

  if ! command -v python3 >/dev/null 2>&1; then
    echo "  ℹ️  未找到 python3，跳过 $kind 的过滤后对比"
    return 1
  fi

  KIND="$kind" LOCAL_FILE="$local_file" OUT_FILE="$out_file" python3 << 'PYEOF'
import json
import os
import re

kind = os.environ['KIND']
local_file = os.environ['LOCAL_FILE']
out_file = os.environ['OUT_FILE']

if kind == 'copilot-config':
    with open(local_file) as f:
        data = json.load(f)
    result = {}
    for key in ('banner', 'model'):
        if key in data:
            result[key] = data[key]
    with open(out_file, 'w') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write('\n')
elif kind == 'copilot-mcp':
    with open(local_file) as f:
        data = json.load(f)
    result = json.loads(json.dumps(data))
    servers = result.get('mcpServers')
    if isinstance(servers, dict):
        for name, server in servers.items():
            if isinstance(server, dict):
                server.pop('env', None)
    with open(out_file, 'w') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write('\n')
elif kind == 'codex-config':
    with open(local_file) as f:
        lines = f.readlines()
    result = []
    skip_section = False
    for line in lines:
        if re.match(r'^\s*\[projects\.', line):
            skip_section = True
            continue
        if re.match(r'^\s*\[(?!projects\.)', line):
            skip_section = False
        if skip_section:
            continue
        if re.match(r'^\s*env\s*=\s*\{', line):
            indent = re.match(r'^(\s*)', line).group(1)
            result.append(f'{indent}# env = {{ ... }}  # 已过滤，请在本机手动配置\n')
            continue
        result.append(line)
    with open(out_file, 'w') as f:
        f.write(''.join(result).rstrip('\n') + '\n')
else:
    raise SystemExit(f'unknown kind: {kind}')
PYEOF

  ! diff -q "$out_file" "$repo_file" > /dev/null 2>&1
}

echo "=== Git 状态 ==="
cd "$REPO" && git status --short
echo ""
echo "=== 最近提交 ==="
git log --oneline -5

echo ""
echo "=== 本地文件对比 ==="
CHANGED=0
for f in copilot-instructions.md; do
  if [ -f "$HOME/.copilot/$f" ] && [ -f "$REPO/copilot/$f" ]; then
    if ! diff -q "$HOME/.copilot/$f" "$REPO/copilot/$f" > /dev/null 2>&1; then
      echo "  📝 copilot/$f 有本地未推送的修改"
      CHANGED=1
    fi
  fi
done
if _sanitized_diff "copilot-config" "$HOME/.copilot/config.json" "$REPO/copilot/config.json" "$TMP_DIR/copilot-config.json"; then
  echo "  📝 copilot/config.json 有本地未推送的共享字段修改"
  CHANGED=1
fi
if _sanitized_diff "copilot-mcp" "$HOME/.copilot/mcp-config.json" "$REPO/copilot/mcp-config.json" "$TMP_DIR/copilot-mcp.json"; then
  echo "  📝 copilot/mcp-config.json 有本地未推送的共享配置修改"
  CHANGED=1
fi
for f in AGENTS.md; do
  if [ -f "$HOME/.codex/$f" ] && [ -f "$REPO/codex/$f" ]; then
    if ! diff -q "$HOME/.codex/$f" "$REPO/codex/$f" > /dev/null 2>&1; then
      echo "  📝 codex/$f 有本地未推送的修改"
      CHANGED=1
    fi
  fi
done
if _sanitized_diff "codex-config" "$HOME/.codex/config.toml" "$REPO/codex/config.toml" "$TMP_DIR/codex-config.toml"; then
  echo "  📝 codex/config.toml 有本地未推送的共享配置修改"
  CHANGED=1
fi
for f in CLAUDE.md; do
  if [ -f "$HOME/.claude/$f" ] && [ -f "$REPO/claude/$f" ]; then
    if ! diff -q "$HOME/.claude/$f" "$REPO/claude/$f" > /dev/null 2>&1; then
      echo "  📝 claude/$f 有本地未推送的修改"
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
| `~/.cli-sync-repo` 不是有效 Git 仓库 | 备份后删除该目录，重新执行初始化 |
| `git push` 认证失败 | 检查 SSH Key 或 Personal Access Token |
| 自动 pull 失败 | 查看 `~/.cli-sync/auto-sync.log`，确认是否存在分叉、未提交变更或认证失败 |
| 推送失败 | 检查远端地址、认证、网络和仓库权限；若远端已领先，先执行拉取并处理差异 |
| merge 冲突 | `cd ~/.cli-sync-repo && git pull --rebase` 后手动解决 |
| `jq` / `python3` 未安装 | `sudo apt install jq python3`（推荐）；否则部分 JSON 合并会降级，Copilot 敏感字段不会自动安全过滤 |

---

## 安全注意事项

1. **强烈建议使用私有仓库**，配置文件含个人工作习惯和 MCP 配置
2. `~/.copilot/config.json` 仅同步明确安全的共享字段；`copilot_tokens`、登录态、`trusted_folders`、`firstLaunchAt` 保留在本机
3. `~/.copilot/mcp-config.json` 会自动过滤各 MCP server 的 `env`；新机器 Pull 后请检查命令路径是否适配本机
4. `settings.json` 的 `env` 字段（含 API Token）**自动过滤**，还原后需手动重设
5. `config.toml` 的 `[projects.*]` 段（本机路径）和 `env` 字段（可能含 Token）**自动过滤**
6. `auth.json` **永远不同步**，每台机器需独立登录
7. 新机器 Pull 后请检查 `config.toml` 中 MCP server 的命令路径是否适配本机
