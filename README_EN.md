# cli-config-sync

Sync your AI CLI tool configurations to GitHub/Gitee — one command to share configs across machines.

Supports: **GitHub Copilot CLI** · **Claude Code CLI** · **Codex CLI**

English | [中文](./README.md)

---

## The Problem

You've carefully configured your AI CLI tools:

- Crafted detailed instructions in `CLAUDE.md` / `AGENTS.md`
- Installed dozens of custom Skills
- Configured MCP servers (Context7, DeepWiki, Sequential Thinking...)
- Fine-tuned model parameters in `config.toml`

Then you switch machines... and it's all gone. 😩

## The Solution

**cli-config-sync** syncs your CLI configs to a private Git repo (GitHub or Gitee). On any new machine, restore everything with one sentence.

```
You: setup config sync
AI:  Please provide your Git repository URL...
     → Detects remote status automatically:
       Has configs: pulls and restores ✅
       Empty repo: pushes current configs ✅
```

---

## Installation

### Option 1: One-line install (recommended)

```bash
# Replace YOUR_USERNAME with your actual GitHub user or org name
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/cli-config-sync/main/install.sh)
```

### Option 2: Clone and install

```bash
# Replace YOUR_USERNAME with your actual GitHub user or org name
git clone https://github.com/YOUR_USERNAME/cli-config-sync.git
cd cli-config-sync
bash install.sh
```

The installer sets up the core scripts and writes the Skill into `~/.claude` / `~/.codex`; missing directories are created automatically.

---

## Usage

After installation, use natural language in any supported CLI:

### First-time setup (do this once per machine)

```
You: setup config sync
AI:  Please provide your Git repository URL (GitHub/Gitee supported):
You: https://github.com/your-name/my-cli-configs
AI:  ✅ Setup complete, auto-detecting remote status and syncing...
```

### Daily use

| You say | Action |
|---|---|
| `sync my configs` | Two-way sync (safe pull first, then push) |
| `push configs` | Push local changes to remote |
| `pull configs` | Pull remote configs to local |
| `sync status` | Show which files have local changes |
| `enable auto sync` | Set up shell hook for automatic sync |

### New machine setup

```bash
# 1. Install CLI tools (as usual)
# 2. Install cli-config-sync
bash <(curl -fsSL https://raw.githubusercontent.com/.../install.sh)
# 3. In your CLI, say:
#    "setup config sync" → enter your repo URL → configs restored
```

---

## What Gets Synced

### GitHub Copilot CLI / Claude Code CLI

| File | Synced | Notes |
|---|---|---|
| `~/.claude/CLAUDE.md` | ✅ | Main AI instructions |
| `~/.claude/settings.json` | ✅ filtered | `env` field (API tokens) removed automatically |
| `~/.claude/skills/` | ✅ | All custom Skills (mirror sync, including deletions) |
| `~/.claude/plugins/blocklist.json` | ✅ | Blocked plugins list |
| `~/.claude/plugins/known_marketplaces.json` | ✅ | Added marketplace sources |
| `~/.claude/plugins/marketplaces/` | ❌ | Cache, re-downloadable |
| `~/.claude/sessions/`, `cache/`, etc. | ❌ | Local runtime data |

### Codex CLI

| File | Synced | Notes |
|---|---|---|
| `~/.codex/AGENTS.md` | ✅ | Agent instructions |
| `~/.codex/config.toml` | ✅ filtered | `[projects.*]` (local paths) and `env` (tokens) auto-filtered |
| `~/.codex/skills/` | ✅ | All custom Skills (mirror sync, including deletions) |
| `~/.codex/rules/` | ✅ | Rules files |
| `~/.codex/memories/` | ✅ | AI memories |
| `~/.codex/auth.json` | ❌ | Login tokens (per-machine) |
| `~/.codex/vendor_imports/` | ❌ | Built-in Skill library |
| `~/.codex/*.sqlite*`, etc. | ❌ | Local runtime data |

---

## Configuration

After initialization, config is stored at `~/.cli-sync/config.yml`:

```yaml
remote: https://github.com/your-name/my-cli-configs.git
branch: main
auto_pull: false   # set true: auto-pull on shell startup
auto_push: false   # set true: auto-push on shell exit
```

The local Git working directory is at `~/.cli-sync-repo/`.

---

## Security

- **Private repository strongly recommended** (configs contain personal preferences and tool configurations)
- The `env` field in `settings.json` (API tokens) is **automatically filtered out**
- `config.toml`: `[projects.*]` sections (local paths) and `env` fields (potential tokens) are **automatically filtered out**
- `auth.json` (login tokens) is **never synced** — you must log in on each machine
- After pulling on a new machine, check MCP server command paths in `config.toml` for compatibility
- Add additional sensitive paths to `.gitignore` in your sync repo as needed

---

## Requirements

- `bash` (required)
- `git` (required)
- `jq` or `python3` (recommended, for filtering sensitive fields in settings.json / config.toml, and smart merging on pull)
- `rsync` (optional, for efficient directory sync; falls back to `cp`)
- Git global identity (`git config --global user.name` and `user.email`)

Auto-sync notes:
- Startup auto-pull uses a conservative `fetch + ff-only` strategy; if the repo has diverged or has local pending changes, it stops instead of creating a merge state silently
- Auto-sync logs are written to `~/.cli-sync/auto-sync.log`

---

## Contributing

PRs welcome! Especially:

- Support for more CLI tools (aider, cursor, etc.)
- Improved sensitive data filtering
- Better error handling
- Documentation improvements

---

## License

MIT
