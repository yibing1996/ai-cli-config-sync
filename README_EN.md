# ai-cli-config-sync

Sync your AI CLI tool configurations to GitHub/Gitee — one command to share configs across machines.

Supports: **GitHub Copilot CLI** · **Claude Code CLI** · **Codex CLI**

English | [中文](./README.md)

> Use a **private Git repository** for real personal configs, and validate one full sync cycle across your own machines first.

---

## The Problem

You've carefully configured your AI CLI tools:

- Crafted detailed instructions in `CLAUDE.md` / `AGENTS.md`
- Installed dozens of custom Skills
- Configured MCP servers (Context7, DeepWiki, Sequential Thinking...)
- Fine-tuned model parameters in `config.toml`

Then you switch machines... and it's all gone. 😩

## The Solution

**ai-cli-config-sync** syncs your CLI configs to a private Git repo (GitHub or Gitee). On any new machine, restore everything with one sentence.

```
You: setup config sync
AI:  Please provide your Git repository URL...
     → Detects remote status automatically:
       Has configs: pulls and restores ✅
       Empty repo: pushes current configs ✅
```

---

## Installation

Recommended usage:

- Start with a **GitHub private repository**
- Run initialization and first push on one machine that already has your configs
- Validate pull-and-restore behavior on a second machine
- Only after that share it with teammates or use it in a wider workflow

### Option 1: One-line install (recommended)

**Git Bash / WSL / Linux / macOS:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh)
```

If process substitution is awkward in **Windows Git Bash**, you can also use:

```bash
curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh | bash
```

**Windows PowerShell:**

```powershell
$tmp = Join-Path $env:TEMP "ai-cli-config-sync-install.ps1"
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.ps1" -OutFile $tmp
& $tmp
```

**Windows cmd:**

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "$tmp = Join-Path $env:TEMP 'ai-cli-config-sync-install.ps1'; Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.ps1' -OutFile $tmp; & $tmp"
```

Notes:

- Running `curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh` by itself only prints the script contents; it does not install anything
- Native Windows shells should use `install.ps1`; it resolves **Git for Windows' Git Bash** automatically and avoids accidentally going through `C:\Windows\System32\bash.exe` into WSL
- If you only want to inspect the detected Git path first, run `where git` from `cmd` or `(Get-Command git).Source` from PowerShell
- If you run the installer inside **WSL**, configs are installed into WSL's own `~/.claude` / `~/.codex` / `~/.copilot`, not your Windows user profile

### Option 2: Clone and install

```bash
git clone https://github.com/yibing1996/ai-cli-config-sync.git
cd ai-cli-config-sync
```

**Git Bash / WSL / Linux / macOS:**

```bash
bash install.sh
```

**Windows PowerShell / cmd:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Windows notes:

- If you see `$'\r': command not found`, the installer itself is usually fine; Git most likely checked out `*.sh` files with `CRLF` line endings
- This repo now ships with `.gitattributes` to force `LF` for `*.sh`; pulling the latest version and re-cloning should fix it
- `git clone` can be done from `cmd`, PowerShell, or Git Bash; native Windows shells should then run `install.ps1`
- If you want a quick fix in the current checkout, run:

```bash
sed -i 's/\r$//' install.sh scripts/*.sh
bash install.sh
```

The installer copies `install.*`, `setup.*`, `push.*`, `pull.*`, `sync.*`, `status.*`, and `enable-auto-sync.*` into `~/.cli-sync/`, then writes the Skill into `~/.claude` / `~/.codex`; it does not write a Skill into `~/.copilot`, but `push.sh` / `pull.sh` will automatically detect and sync supported Copilot files. Missing directories are created automatically.

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
| `sync my configs` | Safe sync (push local changes first; stop on failure) |
| `push configs` | Push local changes to remote |
| `pull configs` | Pull remote configs to local |
| `sync status` | Show which files have local changes |
| `enable auto sync` | Set up shell hook for automatic sync |

Note:
To avoid deleting local-only Skills / Rules / Memories during a mirror-style pull, `sync my configs` now pushes local changes first. If the push fails, the flow stops instead of auto-pulling over your unpublished local files.

### New machine setup

```bash
# 1. Install CLI tools (as usual)
# 2. Install ai-cli-config-sync
bash <(curl -fsSL https://raw.githubusercontent.com/yibing1996/ai-cli-config-sync/main/install.sh)
# 3. In your CLI, say:
#    "setup config sync" → enter your repo URL → configs restored
```

---

## What Gets Synced

### GitHub Copilot CLI

| File | Synced | Notes |
|---|---|---|
| `~/.copilot/copilot-instructions.md` | ✅ | Copilot instructions file |
| `~/.copilot/config.json` | ✅ filtered / merged | Only syncs `banner` and `model`; keeps local `copilot_tokens`, login state, `trusted_folders`, and `firstLaunchAt` |
| `~/.copilot/mcp-config.json` | ✅ filtered / merged | Syncs MCP config; strips per-server `env` before upload and restores local `env` on pull when the server name matches |
| `~/.copilot/logs/`, `session-state/` | ❌ | Runtime logs and session state |
| `~/.copilot/command-history-state.json` | ❌ | Local command history state |
| `~/.copilot/copilot.bat` and similar launchers | ❌ | Machine-local launcher files |

### Claude Code CLI

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
- `~/.copilot/config.json` syncs only clearly safe shared fields (currently `banner` and `model`); `copilot_tokens`, login state, `trusted_folders`, and `firstLaunchAt` stay local
- `~/.copilot/mcp-config.json` automatically strips per-server `env` before upload and restores local `env` on pull when possible
- The `env` field in `settings.json` (API tokens) is **automatically filtered out**
- `config.toml`: `[projects.*]` sections (local paths) and `env` fields (potential tokens) are **automatically filtered out**
- `auth.json` (login tokens) is **never synced** — you must log in on each machine
- After pulling on a new machine, check MCP server command paths in both `config.toml` and `~/.copilot/mcp-config.json` for compatibility
- Add additional sensitive paths to `.gitignore` in your sync repo as needed

---

## Known Limitations

- The project is currently validated mainly in **GitHub + WSL / Git Bash / Linux / macOS / Windows PowerShell** environments; test Gitee or other environments before relying on them
- Auto-sync uses a conservative fast-forward-only strategy; if the local sync repo has divergence, uncommitted changes, or unpushed commits, auto-pull stops instead of forcing a merge
- Runtime-local data such as `auth.json`, `vendor_imports/`, databases, sessions, and caches are intentionally not synced
- After restore, manually verify machine-specific paths in both `config.toml` and `~/.copilot/mcp-config.json`, such as MCP command paths, interpreter locations, and working directories
- Native Windows shells are now supported through `install.ps1`, `push.ps1`, `pull.ps1`, and related wrappers; if you still run `*.sh` directly, prefer Git Bash and keep repository `*.sh` files on `LF` line endings

---

## Requirements

- `bash` (required; on Windows, Git for Windows is recommended because it ships Git Bash)
- `git` (required)
- `jq` or `python3` (recommended, for filtering sensitive fields in settings.json / config.toml, and smart merging on pull)
- `rsync` (optional, for efficient directory sync; falls back to `cp`)
- Git global identity (`git config --global user.name` and `user.email`)

Auto-sync notes:
- Startup auto-pull uses a conservative `fetch + ff-only` strategy; if the repo has diverged or has local pending changes, it stops instead of creating a merge state silently
- Auto-sync logs are written to `~/.cli-sync/auto-sync.log`

---

## Local Smoke Test

If you changed the scripts, or want to verify the install and sync flow locally first, run this from the project root:

```bash
bash scripts/dev-smoke-test.sh
```

The script checks:

- Core script syntax
- Whether the installer works under a temporary `HOME`
- Whether `push.sh` filters Claude / Codex / Copilot sensitive fields
- Whether `pull.sh` preserves machine-local private fields, including Copilot login state and MCP env
- Whether `pull.sh` stops safely when the sync repo has diverged

---

## Recommended Verification Checklist

If you plan to use this against a real config repository, verify at least the following:

- Run `bash scripts/dev-smoke-test.sh` locally first
- Run one full end-to-end flow with a **GitHub private repository** first, so you do not accidentally sync sensitive configs into a public repo
- On a machine that already has real configs, run install, initialization, and first push; confirm the remote repo contains the expected files
- Validate restore behavior in a **clean environment**, such as a second machine, a container, or a temporary `HOME` directory
- After restore succeeds on the second machine, modify `AGENTS.md`, `CLAUDE.md`, or one custom Skill, then run another push and pull to confirm two-way sync
- Check that `env` in `settings.json`, plus `env` and `[projects.*]` in `config.toml`, and the login / token / `trusted_folders` fields in `~/.copilot/config.json` stay local and are not uploaded to the remote repo
- Trigger one auto-sync scenario and inspect `~/.cli-sync/auto-sync.log` to confirm there are no auth failures, divergence issues, or fast-forward failures

Recommended minimum test matrix:

- GitHub private repo + HTTPS
- GitHub private repo + SSH
- At least two environments: one “already configured” machine and one “clean” environment

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
