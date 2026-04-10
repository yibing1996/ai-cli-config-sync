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
     → configs restored automatically ✅
```

---

## Installation

### Option 1: One-line install (recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/cli-config-sync/main/install.sh)
```

### Option 2: Clone and install

```bash
git clone https://github.com/YOUR_USERNAME/cli-config-sync.git
cd cli-config-sync
bash install.sh
```

The script auto-detects which CLI tools are installed and installs the appropriate Skill for each.

---

## Usage

After installation, use natural language in any supported CLI:

### First-time setup (do this once per machine)

```
You: setup config sync
AI:  Please provide your Git repository URL (GitHub/Gitee supported):
You: https://github.com/your-name/my-cli-configs
AI:  ✅ Setup complete, running initial push...
```

### Daily use

| You say | Action |
|---|---|
| `sync my configs` | Two-way sync (pull then push) |
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
| `~/.claude/skills/` | ✅ | All custom Skills |
| `~/.claude/plugins/blocklist.json` | ✅ | Blocked plugins list |
| `~/.claude/plugins/known_marketplaces.json` | ✅ | Added marketplace sources |
| `~/.claude/plugins/marketplaces/` | ❌ | Cache, re-downloadable |
| `~/.claude/sessions/`, `cache/`, etc. | ❌ | Local runtime data |

### Codex CLI

| File | Synced | Notes |
|---|---|---|
| `~/.codex/AGENTS.md` | ✅ | Agent instructions |
| `~/.codex/config.toml` | ✅ | MCP config, model params |
| `~/.codex/skills/` | ✅ | All custom Skills |
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
- `auth.json` (login tokens) is **never synced** — you must log in on each machine
- Add additional sensitive paths to `.gitignore` in your sync repo as needed

---

## Requirements

- `bash` (required)
- `git` (required)
- `jq` or `python3` (recommended, for filtering `settings.json`)
- `rsync` (optional, for efficient directory sync; falls back to `cp`)

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
