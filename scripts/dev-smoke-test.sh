#!/usr/bin/env bash
# dev-smoke-test.sh — 本地快速自测脚本

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf '[smoke] %s\n' "$*"
}

fail() {
  printf '[smoke] ❌ %s\n' "$*" >&2
  exit 1
}

has_node() {
  command -v node >/dev/null 2>&1 || (is_windows_git_bash && command -v node.exe >/dev/null 2>&1)
}

is_windows_git_bash() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

make_tmpdir() {
  if is_windows_git_bash; then
    local tmp_root="$ROOT_DIR/.git/.tmp-smoke"
    mkdir -p "$tmp_root"
    mktemp -d "$tmp_root/case.XXXXXX"
  else
    mktemp -d
  fi
}

assert_file() {
  [ -f "$1" ] || fail "缺少文件：$1"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq "$needle" "$file" || fail "文件 $file 未包含预期内容：$needle"
}

assert_not_contains() {
  local file="$1" needle="$2"
  if grep -Fq "$needle" "$file"; then
    fail "文件 $file 不应包含：$needle"
  fi
}

write_broken_python_shims() {
  local bindir="$1"
  mkdir -p "$bindir"

  for name in python3 python py; do
    cat > "$bindir/$name" <<'EOF'
#!/usr/bin/env bash
exit 49
EOF
    chmod +x "$bindir/$name"
  done
}

run_syntax_check() {
  log "检查核心脚本语法"
  cd "$ROOT_DIR"
  bash -n install.sh uninstall.sh \
    scripts/push.sh scripts/pull.sh scripts/setup.sh scripts/sync.sh \
    scripts/status.sh scripts/enable-auto-sync.sh scripts/dev-smoke-test.sh
}

run_docs_consistency_check() {
  log "检查文档中的安全同步语义"
  assert_contains "$ROOT_DIR/README.md" '安全同步（先推送本地改动；失败即停）'
  assert_contains "$ROOT_DIR/README.md" 'install.ps1'
  assert_contains "$ROOT_DIR/README.md" 'Windows PowerShell'
  assert_not_contains "$ROOT_DIR/README.md" '先保守拉取，再推送'
  assert_contains "$ROOT_DIR/README.md" '### GitHub Copilot CLI'
  assert_contains "$ROOT_DIR/README.md" '### Claude Code CLI'
  assert_not_contains "$ROOT_DIR/README.md" '### GitHub Copilot CLI / Claude Code CLI'
  assert_contains "$ROOT_DIR/README.md" '根据 `$SHELL` 选择 `~/.bashrc` 或 `~/.zshrc`'
  assert_contains "$ROOT_DIR/README_EN.md" 'Safe sync (push local changes first; stop on failure)'
  assert_contains "$ROOT_DIR/README_EN.md" 'install.ps1'
  assert_contains "$ROOT_DIR/README_EN.md" 'Windows PowerShell'
  assert_not_contains "$ROOT_DIR/README_EN.md" 'safe pull first, then push'
  assert_contains "$ROOT_DIR/README_EN.md" '### GitHub Copilot CLI'
  assert_contains "$ROOT_DIR/README_EN.md" '### Claude Code CLI'
  assert_not_contains "$ROOT_DIR/README_EN.md" '### GitHub Copilot CLI / Claude Code CLI'
  assert_contains "$ROOT_DIR/README_EN.md" 'selects `~/.bashrc` or `~/.zshrc` from `$SHELL`'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync/SKILL.md" '安全同步（先推送，失败即停）'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync/SKILL.md" 'Windows 原生终端（PowerShell / cmd）'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync/SKILL.md" 'setup.ps1'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync/SKILL.md" 'enable-auto-sync.ps1'
  assert_not_contains "$ROOT_DIR/skills/ai-cli-config-sync/SKILL.md" '先 pull 再 push'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync/SKILL.md" '### GitHub Copilot CLI（`~/.copilot/`）'
  assert_not_contains "$ROOT_DIR/skills/ai-cli-config-sync/SKILL.md" '### GitHub Copilot CLI / Claude Code CLI（`~/.claude/`）'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync/SKILL.md" '根据 `$SHELL` 把 hook 写入 `~/.bashrc` 或 `~/.zshrc`'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync-codex/SKILL.md" '安全同步（先推送，失败即停）'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync-codex/SKILL.md" 'Windows 原生终端（PowerShell / cmd）'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync-codex/SKILL.md" 'setup.ps1'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync-codex/SKILL.md" 'enable-auto-sync.ps1'
  assert_not_contains "$ROOT_DIR/skills/ai-cli-config-sync-codex/SKILL.md" '先 pull 再 push'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync-codex/SKILL.md" '### GitHub Copilot CLI（`~/.copilot/`）'
  assert_not_contains "$ROOT_DIR/skills/ai-cli-config-sync-codex/SKILL.md" '### GitHub Copilot CLI / Claude Code CLI（`~/.claude/`）'
  assert_contains "$ROOT_DIR/skills/ai-cli-config-sync-codex/SKILL.md" '根据 `$SHELL` 把 hook 写入 `~/.bashrc` 或 `~/.zshrc`'
}

run_install_smoke() {
  local tmpdir home
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"

  log "验证 install.sh 在临时 HOME 下可用"
  HOME="$home" bash "$ROOT_DIR/install.sh" >/dev/null 2>&1

  assert_file "$home/.cli-sync/install.sh"
  assert_file "$home/.cli-sync/install.ps1"
  assert_file "$home/.cli-sync/push.sh"
  assert_file "$home/.cli-sync/pull.sh"
  assert_file "$home/.cli-sync/setup.sh"
  assert_file "$home/.cli-sync/setup.ps1"
  assert_file "$home/.cli-sync/sync.sh"
  assert_file "$home/.cli-sync/sync.ps1"
  assert_file "$home/.cli-sync/status.sh"
  assert_file "$home/.cli-sync/status.ps1"
  assert_file "$home/.cli-sync/enable-auto-sync.sh"
  assert_file "$home/.cli-sync/enable-auto-sync.ps1"
  assert_file "$home/.cli-sync/runtime.ps1"
  assert_file "$home/.claude/skills/ai-cli-config-sync/SKILL.md"
  assert_file "$home/.codex/skills/ai-cli-config-sync/SKILL.md"

  rm -rf "$tmpdir"
}

run_enable_auto_sync_target_shell_smoke() {
  local tmpdir zsh_home bash_home
  tmpdir="$(make_tmpdir)"
  zsh_home="$tmpdir/home-zsh"
  bash_home="$tmpdir/home-bash"

  log "验证 enable-auto-sync.sh 会根据登录 shell 写入正确的 rc 文件"

  mkdir -p "$zsh_home" "$bash_home"
  : > "$zsh_home/.bashrc"
  : > "$zsh_home/.zshrc"
  : > "$bash_home/.bashrc"
  : > "$bash_home/.zshrc"

  HOME="$zsh_home" SHELL=/bin/zsh bash "$ROOT_DIR/scripts/enable-auto-sync.sh" >/dev/null 2>&1
  assert_contains "$zsh_home/.zshrc" 'ai-cli-config-sync-hook-start'
  assert_not_contains "$zsh_home/.bashrc" 'ai-cli-config-sync-hook-start'

  HOME="$bash_home" SHELL=/bin/bash bash "$ROOT_DIR/scripts/enable-auto-sync.sh" >/dev/null 2>&1
  assert_contains "$bash_home/.bashrc" 'ai-cli-config-sync-hook-start'
  assert_not_contains "$bash_home/.zshrc" 'ai-cli-config-sync-hook-start'

  rm -rf "$tmpdir"
}

run_auto_pull_hook_smoke() {
  local tmpdir home remote log_file
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"
  log_file="$home/.cli-sync/auto-sync.log"

  log "验证 auto_pull=true 时 shell 启动会自动拉取"
  HOME="$home" bash "$ROOT_DIR/install.sh" >/dev/null 2>&1
  printf '\n' > "$home/.bashrc"

  git init --bare "$remote" >/dev/null 2>&1
  git init "$tmpdir/src" >/dev/null 2>&1
  git -C "$tmpdir/src" config user.name smoke-test
  git -C "$tmpdir/src" config user.email smoke@example.com
  mkdir -p "$tmpdir/src/codex"
  cat > "$tmpdir/src/codex/AGENTS.md" <<'EOF'
# remote
auto pull works
EOF
  git -C "$tmpdir/src" add codex/AGENTS.md >/dev/null 2>&1
  git -C "$tmpdir/src" commit -m "seed" >/dev/null 2>&1
  git -C "$tmpdir/src" branch -M main
  git -C "$tmpdir/src" remote add origin "$remote"
  git -C "$tmpdir/src" push origin main >/dev/null 2>&1
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  git clone "$remote" "$home/.cli-sync-repo" >/dev/null 2>&1
  git -C "$home/.cli-sync-repo" config user.name smoke-test
  git -C "$home/.cli-sync-repo" config user.email smoke@example.com
  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
auto_pull: true
auto_push: false
EOF

  HOME="$home" SHELL=/bin/bash bash "$home/.cli-sync/enable-auto-sync.sh" >/dev/null 2>&1
  rm -f "$home/.codex/AGENTS.md"

  HOME="$home" bash --rcfile "$home/.bashrc" -i -c 'for i in $(seq 1 80); do if [ -f "$HOME/.codex/AGENTS.md" ] && grep -Fq "auto pull works" "$HOME/.codex/AGENTS.md"; then exit 0; fi; sleep 0.25; done; exit 1' >/dev/null 2>&1

  assert_file "$home/.codex/AGENTS.md"
  assert_contains "$home/.codex/AGENTS.md" 'auto pull works'
  assert_file "$log_file"
  assert_contains "$log_file" '从远程拉取配置'

  rm -rf "$tmpdir"
}

run_auto_push_hook_smoke() {
  local tmpdir home remote log_file clone_check
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"
  log_file="$home/.cli-sync/auto-sync.log"
  clone_check="$tmpdir/clone-check"

  log "验证 auto_push=true 时 shell 退出会自动推送"
  HOME="$home" bash "$ROOT_DIR/install.sh" >/dev/null 2>&1
  printf '\n' > "$home/.bashrc"

  git init --bare "$remote" >/dev/null 2>&1
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$home/.cli-sync-repo" "$home/.cli-sync" "$home/.codex"
  git init "$home/.cli-sync-repo" >/dev/null 2>&1
  git -C "$home/.cli-sync-repo" config user.name smoke-test
  git -C "$home/.cli-sync-repo" config user.email smoke@example.com
  git -C "$home/.cli-sync-repo" remote add origin "$remote"
  git -C "$home/.cli-sync-repo" checkout -b main >/dev/null 2>&1

  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
auto_pull: false
auto_push: true
EOF

  cat > "$home/.codex/AGENTS.md" <<'EOF'
# local
auto push works
EOF

  HOME="$home" SHELL=/bin/bash bash "$home/.cli-sync/enable-auto-sync.sh" >/dev/null 2>&1
  HOME="$home" bash --rcfile "$home/.bashrc" -i -c 'true' >/dev/null 2>&1

  git clone "$remote" "$clone_check" >/dev/null 2>&1
  assert_file "$clone_check/codex/AGENTS.md"
  assert_contains "$clone_check/codex/AGENTS.md" 'auto push works'
  assert_file "$log_file"
  assert_contains "$log_file" '配置已推送'

  rm -rf "$tmpdir"
}

run_push_filter_smoke() {
  local tmpdir home remote filtered
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"

  log "验证 push.sh 会过滤缩进版敏感字段"
  mkdir -p "$home/.cli-sync-repo" "$home/.cli-sync" "$home/.codex"
  git init --bare "$remote" >/dev/null 2>&1
  git init "$home/.cli-sync-repo" >/dev/null 2>&1
  git -C "$home/.cli-sync-repo" config user.name smoke-test
  git -C "$home/.cli-sync-repo" config user.email smoke@example.com
  git -C "$home/.cli-sync-repo" remote add origin "$remote"
  git -C "$home/.cli-sync-repo" checkout -b main >/dev/null 2>&1

  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
EOF

  cat > "$home/.codex/config.toml" <<'EOF'
 [projects."/tmp/proj"]
 trusted = true

 [model]
   env = { OPENAI_API_KEY = "secret" }
   name = "gpt-5"
EOF

  HOME="$home" bash "$ROOT_DIR/scripts/push.sh" >/dev/null 2>&1

  filtered="$home/.cli-sync-repo/codex/config.toml"
  assert_file "$filtered"
  assert_not_contains "$filtered" 'OPENAI_API_KEY'
  assert_not_contains "$filtered" '[projects."/tmp/proj"]'
  assert_contains "$filtered" 'name = "gpt-5"'

  rm -rf "$tmpdir"
}

run_copilot_push_filter_smoke() {
  local tmpdir home remote filtered_config filtered_mcp
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"

  log "验证 push.sh 会过滤 Copilot 私有字段和 MCP env"
  mkdir -p "$home/.cli-sync-repo" "$home/.cli-sync" "$home/.copilot"
  git init --bare "$remote" >/dev/null 2>&1
  git init "$home/.cli-sync-repo" >/dev/null 2>&1
  git -C "$home/.cli-sync-repo" config user.name smoke-test
  git -C "$home/.cli-sync-repo" config user.email smoke@example.com
  git -C "$home/.cli-sync-repo" remote add origin "$remote"
  git -C "$home/.cli-sync-repo" checkout -b main >/dev/null 2>&1

  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
EOF

  cat > "$home/.copilot/config.json" <<'EOF'
{
  "firstLaunchAt": "2026-04-10T12:00:00Z",
  "banner": {
    "hidden": true
  },
  "copilot_tokens": {
    "github.com": {
      "token": "secret"
    }
  },
  "last_logged_in_user": "zyb",
  "logged_in_users": [
    "zyb"
  ],
  "trusted_folders": [
    "/tmp/project"
  ],
  "model": "gpt-5"
}
EOF

  cat > "$home/.copilot/mcp-config.json" <<'EOF'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "uvx",
      "args": ["duckduckgo-mcp-server"],
      "env": {
        "UV_HTTP_TIMEOUT": "120"
      }
    }
  }
}
EOF

  cat > "$home/.copilot/copilot-instructions.md" <<'EOF'
# Copilot
shared instructions
EOF

  HOME="$home" bash "$ROOT_DIR/scripts/push.sh" >/dev/null 2>&1

  filtered_config="$home/.cli-sync-repo/copilot/config.json"
  filtered_mcp="$home/.cli-sync-repo/copilot/mcp-config.json"
  assert_file "$filtered_config"
  assert_file "$filtered_mcp"
  assert_file "$home/.cli-sync-repo/copilot/copilot-instructions.md"
  assert_contains "$filtered_config" '"banner"'
  assert_contains "$filtered_config" '"model": "gpt-5"'
  assert_not_contains "$filtered_config" 'copilot_tokens'
  assert_not_contains "$filtered_config" 'last_logged_in_user'
  assert_not_contains "$filtered_config" 'trusted_folders'
  assert_contains "$filtered_mcp" '"duckduckgo-search"'
  assert_not_contains "$filtered_mcp" '"env"'

  rm -rf "$tmpdir"
}

run_copilot_push_node_fallback_smoke() {
  local tmpdir home remote fakebin filtered_config filtered_mcp
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"
  fakebin="$tmpdir/fakebin"

  if ! has_node; then
    log "跳过 push.sh 的 Node fallback smoke test（当前运行时未找到可用 node）"
    return 0
  fi
  write_broken_python_shims "$fakebin"

  log "验证 push.sh 在 Python 不可用时会回退到 node"
  mkdir -p "$home/.cli-sync-repo" "$home/.cli-sync" "$home/.copilot"
  git init --bare "$remote" >/dev/null 2>&1
  git init "$home/.cli-sync-repo" >/dev/null 2>&1
  git -C "$home/.cli-sync-repo" config user.name smoke-test
  git -C "$home/.cli-sync-repo" config user.email smoke@example.com
  git -C "$home/.cli-sync-repo" remote add origin "$remote"
  git -C "$home/.cli-sync-repo" checkout -b main >/dev/null 2>&1

  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
EOF

  cat > "$home/.copilot/config.json" <<'EOF'
{
  "banner": {
    "hidden": true
  },
  "model": "gpt-5",
  "copilot_tokens": {
    "github.com": {
      "token": "secret"
    }
  }
}
EOF

  cat > "$home/.copilot/mcp-config.json" <<'EOF'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "uvx",
      "args": ["duckduckgo-mcp-server"],
      "env": {
        "UV_HTTP_TIMEOUT": "120"
      }
    }
  }
}
EOF

  PATH="$fakebin:$PATH" HOME="$home" bash "$ROOT_DIR/scripts/push.sh" >/dev/null 2>&1

  filtered_config="$home/.cli-sync-repo/copilot/config.json"
  filtered_mcp="$home/.cli-sync-repo/copilot/mcp-config.json"
  assert_file "$filtered_config"
  assert_file "$filtered_mcp"
  assert_contains "$filtered_config" '"model": "gpt-5"'
  assert_not_contains "$filtered_config" 'copilot_tokens'
  assert_not_contains "$filtered_mcp" '"env"'

  rm -rf "$tmpdir"
}

run_pull_merge_smoke() {
  local tmpdir home remote merged settings
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"

  log "验证 pull.sh 会保留本机私有字段"
  git init --bare "$remote" >/dev/null 2>&1
  git init "$tmpdir/src" >/dev/null 2>&1
  git -C "$tmpdir/src" config user.name smoke-test
  git -C "$tmpdir/src" config user.email smoke@example.com
  mkdir -p "$tmpdir/src/codex" "$tmpdir/src/claude"

  cat > "$tmpdir/src/codex/config.toml" <<'EOF'
 [model]
 name = "gpt-5"
   # env = { ... }  # 已过滤，请在本机手动配置
EOF

  cat > "$tmpdir/src/claude/settings.json" <<'EOF'
{
  "theme": "light"
}
EOF

  git -C "$tmpdir/src" add codex/config.toml claude/settings.json >/dev/null 2>&1
  git -C "$tmpdir/src" commit -m "init" >/dev/null 2>&1
  git -C "$tmpdir/src" branch -M main
  git -C "$tmpdir/src" remote add origin "$remote"
  git -C "$tmpdir/src" push origin main >/dev/null 2>&1
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$home/.cli-sync" "$home/.codex" "$home/.claude"
  git clone "$remote" "$home/.cli-sync-repo" >/dev/null 2>&1

  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
EOF

  cat > "$home/.codex/config.toml" <<'EOF'
 [model]
   env = { OPENAI_API_KEY = "secret" }

 [projects."/tmp/proj"]
 trusted = true
EOF

  cat > "$home/.claude/settings.json" <<'EOF'
{
  "env": {
    "ANTHROPIC_API_KEY": "secret"
  }
}
EOF

  HOME="$home" bash "$ROOT_DIR/scripts/pull.sh" >/dev/null 2>&1

  merged="$home/.codex/config.toml"
  settings="$home/.claude/settings.json"

  assert_contains "$merged" 'OPENAI_API_KEY'
  assert_contains "$merged" '[projects."/tmp/proj"]'
  assert_contains "$settings" 'ANTHROPIC_API_KEY'
  assert_contains "$settings" '"theme": "light"'

  rm -rf "$tmpdir"
}

run_copilot_pull_merge_smoke() {
  local tmpdir home remote merged_config merged_mcp
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"

  log "验证 pull.sh 会保留 Copilot 本机私有字段和 MCP env"
  git init --bare "$remote" >/dev/null 2>&1
  git init "$tmpdir/src" >/dev/null 2>&1
  git -C "$tmpdir/src" config user.name smoke-test
  git -C "$tmpdir/src" config user.email smoke@example.com
  mkdir -p "$tmpdir/src/copilot"

  cat > "$tmpdir/src/copilot/config.json" <<'EOF'
{
  "banner": {
    "hidden": false
  },
  "model": "gpt-5"
}
EOF

  cat > "$tmpdir/src/copilot/mcp-config.json" <<'EOF'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "uvx",
      "args": ["duckduckgo-mcp-server"]
    }
  }
}
EOF

  cat > "$tmpdir/src/copilot/copilot-instructions.md" <<'EOF'
# Shared Copilot Instructions
EOF

  git -C "$tmpdir/src" add copilot >/dev/null 2>&1
  git -C "$tmpdir/src" commit -m "init" >/dev/null 2>&1
  git -C "$tmpdir/src" branch -M main
  git -C "$tmpdir/src" remote add origin "$remote"
  git -C "$tmpdir/src" push origin main >/dev/null 2>&1
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$home/.cli-sync" "$home/.copilot"
  git clone "$remote" "$home/.cli-sync-repo" >/dev/null 2>&1

  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
EOF

  cat > "$home/.copilot/config.json" <<'EOF'
{
  "firstLaunchAt": "2026-01-01T00:00:00Z",
  "copilot_tokens": {
    "github.com": {
      "token": "secret"
    }
  },
  "last_logged_in_user": "zyb",
  "logged_in_users": [
    "zyb"
  ],
  "trusted_folders": [
    "/tmp/project"
  ]
}
EOF

  cat > "$home/.copilot/mcp-config.json" <<'EOF'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "old-command",
      "args": ["old"],
      "env": {
        "UV_HTTP_TIMEOUT": "120"
      }
    },
    "local-only": {
      "command": "keep-local",
      "env": {
        "LOCAL_ONLY": "1"
      }
    }
  }
}
EOF

  HOME="$home" bash "$ROOT_DIR/scripts/pull.sh" >/dev/null 2>&1

  merged_config="$home/.copilot/config.json"
  merged_mcp="$home/.copilot/mcp-config.json"
  assert_contains "$merged_config" '"model": "gpt-5"'
  assert_contains "$merged_config" 'copilot_tokens'
  assert_contains "$merged_config" 'last_logged_in_user'
  assert_contains "$merged_config" 'trusted_folders'
  assert_not_contains "$merged_config" 'old-command'
  assert_contains "$merged_mcp" '"command": "uvx"'
  assert_contains "$merged_mcp" '"UV_HTTP_TIMEOUT": "120"'
  assert_contains "$merged_mcp" 'local-only'
  assert_contains "$merged_mcp" 'LOCAL_ONLY'
  assert_contains "$home/.copilot/copilot-instructions.md" 'Shared Copilot Instructions'

  rm -rf "$tmpdir"
}

run_copilot_pull_node_fallback_smoke() {
  local tmpdir home remote fakebin merged_config merged_mcp
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"
  fakebin="$tmpdir/fakebin"

  if ! has_node; then
    log "跳过 pull.sh 的 Node fallback smoke test（当前运行时未找到可用 node）"
    return 0
  fi
  write_broken_python_shims "$fakebin"

  log "验证 pull.sh 在 Python 不可用时会回退到 node"
  git init --bare "$remote" >/dev/null 2>&1
  git init "$tmpdir/src" >/dev/null 2>&1
  git -C "$tmpdir/src" config user.name smoke-test
  git -C "$tmpdir/src" config user.email smoke@example.com
  mkdir -p "$tmpdir/src/copilot"

  cat > "$tmpdir/src/copilot/config.json" <<'EOF'
{
  "banner": {
    "hidden": false
  },
  "model": "gpt-5"
}
EOF

  cat > "$tmpdir/src/copilot/mcp-config.json" <<'EOF'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "uvx",
      "args": ["duckduckgo-mcp-server"]
    }
  }
}
EOF

  git -C "$tmpdir/src" add copilot >/dev/null 2>&1
  git -C "$tmpdir/src" commit -m "init" >/dev/null 2>&1
  git -C "$tmpdir/src" branch -M main
  git -C "$tmpdir/src" remote add origin "$remote"
  git -C "$tmpdir/src" push origin main >/dev/null 2>&1
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$home/.cli-sync" "$home/.copilot"
  git clone "$remote" "$home/.cli-sync-repo" >/dev/null 2>&1

  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
EOF

  cat > "$home/.copilot/config.json" <<'EOF'
{
  "firstLaunchAt": "2026-01-01T00:00:00Z",
  "copilot_tokens": {
    "github.com": {
      "token": "secret"
    }
  },
  "trusted_folders": [
    "/tmp/project"
  ]
}
EOF

  cat > "$home/.copilot/mcp-config.json" <<'EOF'
{
  "mcpServers": {
    "duckduckgo-search": {
      "command": "old-command",
      "env": {
        "UV_HTTP_TIMEOUT": "120"
      }
    },
    "local-only": {
      "command": "keep-local",
      "env": {
        "LOCAL_ONLY": "1"
      }
    }
  }
}
EOF

  PATH="$fakebin:$PATH" HOME="$home" bash "$ROOT_DIR/scripts/pull.sh" >/dev/null 2>&1

  merged_config="$home/.copilot/config.json"
  merged_mcp="$home/.copilot/mcp-config.json"
  assert_contains "$merged_config" '"model": "gpt-5"'
  assert_contains "$merged_config" 'copilot_tokens'
  assert_contains "$merged_config" 'trusted_folders'
  assert_contains "$merged_mcp" '"command": "uvx"'
  assert_contains "$merged_mcp" '"UV_HTTP_TIMEOUT": "120"'
  assert_contains "$merged_mcp" 'local-only'
  assert_contains "$merged_mcp" 'LOCAL_ONLY'

  rm -rf "$tmpdir"
}

run_pull_special_path_smoke() {
  local tmpdir home remote merged
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home spaced dir"
  remote="$tmpdir/remote.git"

  log "验证 pull.sh 在特殊路径下的 Python 合并逻辑"
  git init --bare "$remote" >/dev/null 2>&1
  git init "$tmpdir/src" >/dev/null 2>&1
  git -C "$tmpdir/src" config user.name smoke-test
  git -C "$tmpdir/src" config user.email smoke@example.com
  mkdir -p "$tmpdir/src/codex"

  cat > "$tmpdir/src/codex/config.toml" <<'EOF'
 [model]
 name = "gpt-5"
   # env = { ... }  # 已过滤，请在本机手动配置
EOF

  git -C "$tmpdir/src" add codex/config.toml >/dev/null 2>&1
  git -C "$tmpdir/src" commit -m "init" >/dev/null 2>&1
  git -C "$tmpdir/src" branch -M main
  git -C "$tmpdir/src" remote add origin "$remote"
  git -C "$tmpdir/src" push origin main >/dev/null 2>&1
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$home/.cli-sync" "$home/.codex"
  git clone "$remote" "$home/.cli-sync-repo" >/dev/null 2>&1

  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
EOF

  cat > "$home/.codex/config.toml" <<'EOF'
 [model]
   env = { OPENAI_API_KEY = "secret" }

 [projects."/tmp/proj"]
 trusted = true
EOF

  HOME="$home" bash "$ROOT_DIR/scripts/pull.sh" >/dev/null 2>&1

  merged="$home/.codex/config.toml"
  assert_contains "$merged" 'OPENAI_API_KEY'
  assert_contains "$merged" '[projects."/tmp/proj"]'
  assert_contains "$merged" 'name = "gpt-5"'

  rm -rf "$tmpdir"
}

run_pull_diverge_smoke() {
  local tmpdir home remote stdout_file stderr_file
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"
  stdout_file="$tmpdir/pull.stdout"
  stderr_file="$tmpdir/pull.stderr"

  log "验证 pull.sh 在仓库分叉时会安全停止"
  git init --bare "$remote" >/dev/null 2>&1

  git init "$tmpdir/src1" >/dev/null 2>&1
  git -C "$tmpdir/src1" config user.name smoke-test
  git -C "$tmpdir/src1" config user.email smoke@example.com
  echo one > "$tmpdir/src1/file.txt"
  git -C "$tmpdir/src1" add file.txt >/dev/null 2>&1
  git -C "$tmpdir/src1" commit -m "one" >/dev/null 2>&1
  git -C "$tmpdir/src1" branch -M main
  git -C "$tmpdir/src1" remote add origin "$remote"
  git -C "$tmpdir/src1" push origin main >/dev/null 2>&1
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  git clone "$remote" "$home/.cli-sync-repo" >/dev/null 2>&1
  git -C "$home/.cli-sync-repo" config user.name smoke-test
  git -C "$home/.cli-sync-repo" config user.email smoke@example.com
  echo local >> "$home/.cli-sync-repo/file.txt"
  git -C "$home/.cli-sync-repo" commit -am "local" >/dev/null 2>&1

  git clone "$remote" "$tmpdir/src2" >/dev/null 2>&1
  git -C "$tmpdir/src2" config user.name smoke-test
  git -C "$tmpdir/src2" config user.email smoke@example.com
  echo remote >> "$tmpdir/src2/file.txt"
  git -C "$tmpdir/src2" commit -am "remote" >/dev/null 2>&1
  git -C "$tmpdir/src2" push origin main >/dev/null 2>&1

  mkdir -p "$home/.cli-sync" "$home/.codex"
  cat > "$home/.cli-sync/config.yml" <<EOF
remote: $remote
branch: main
EOF

  if HOME="$home" bash "$ROOT_DIR/scripts/pull.sh" >"$stdout_file" 2>"$stderr_file"; then
    fail "仓库分叉时 pull.sh 不应成功"
  fi

  assert_contains "$stdout_file" '已停止自动合并'

  rm -rf "$tmpdir"
}

run_setup_existing_repo_prefers_pull_smoke() {
  local tmpdir home remote result_file
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  remote="$tmpdir/remote.git"
  result_file="$home/result.txt"

  log "验证 setup.sh 在复用已有同步仓库时仍会优先拉取远端配置"
  git init --bare "$remote" >/dev/null 2>&1
  git init "$tmpdir/src" >/dev/null 2>&1
  git -C "$tmpdir/src" config user.name smoke-test
  git -C "$tmpdir/src" config user.email smoke@example.com
  echo remote > "$tmpdir/src/file.txt"
  git -C "$tmpdir/src" add file.txt >/dev/null 2>&1
  git -C "$tmpdir/src" commit -m "init" >/dev/null 2>&1
  git -C "$tmpdir/src" branch -M main
  git -C "$tmpdir/src" remote add origin "$remote"
  git -C "$tmpdir/src" push origin main >/dev/null 2>&1
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

  mkdir -p "$home/.cli-sync"
  cat > "$home/.cli-sync/pull.sh" <<'EOF'
#!/usr/bin/env bash
echo PULL > "$HOME/result.txt"
EOF
  cat > "$home/.cli-sync/push.sh" <<'EOF'
#!/usr/bin/env bash
echo PUSH > "$HOME/result.txt"
EOF
  chmod +x "$home/.cli-sync/pull.sh" "$home/.cli-sync/push.sh"

  git clone "$remote" "$home/.cli-sync-repo" >/dev/null 2>&1

  HOME="$home" bash "$ROOT_DIR/scripts/setup.sh" "$remote" >/dev/null 2>&1

  assert_file "$result_file"
  assert_contains "$result_file" 'PULL'
  assert_not_contains "$result_file" 'PUSH'

  rm -rf "$tmpdir"
}

run_status_crlf_node_fallback_smoke() {
  local tmpdir home fakebin output_file
  tmpdir="$(make_tmpdir)"
  home="$tmpdir/home"
  fakebin="$tmpdir/fakebin"
  output_file="$tmpdir/status.out"

  if ! has_node; then
    log "跳过 status.sh 的 Node fallback smoke test（当前运行时未找到可用 node）"
    return 0
  fi
  write_broken_python_shims "$fakebin"

  log "验证 status.sh 在 CRLF 差异和 Python 不可用时不会误报"
  mkdir -p "$home/.cli-sync-repo/copilot" "$home/.copilot"
  git init "$home/.cli-sync-repo" >/dev/null 2>&1
  git -C "$home/.cli-sync-repo" config user.name smoke-test
  git -C "$home/.cli-sync-repo" config user.email smoke@example.com

  printf '# Shared Instructions\n' > "$home/.cli-sync-repo/copilot/copilot-instructions.md"
  printf '{\n  "model": "gpt-5"\n}\n' > "$home/.cli-sync-repo/copilot/config.json"
  git -C "$home/.cli-sync-repo" add copilot >/dev/null 2>&1
  git -C "$home/.cli-sync-repo" commit -m "init" >/dev/null 2>&1

  printf '# Shared Instructions\r\n' > "$home/.copilot/copilot-instructions.md"
  printf '{\r\n  "model": "gpt-5"\r\n}\r\n' > "$home/.copilot/config.json"

  PATH="$fakebin:$PATH" HOME="$home" bash "$ROOT_DIR/scripts/status.sh" >"$output_file" 2>&1

  assert_contains "$output_file" '✅ 所有核心配置文件与仓库一致'
  assert_not_contains "$output_file" '有本地未推送'

  rm -rf "$tmpdir"
}

main() {
  run_syntax_check
  run_docs_consistency_check
  run_install_smoke
  run_enable_auto_sync_target_shell_smoke
  run_auto_pull_hook_smoke
  run_auto_push_hook_smoke
  run_push_filter_smoke
  run_copilot_push_filter_smoke
  run_copilot_push_node_fallback_smoke
  run_pull_merge_smoke
  run_copilot_pull_merge_smoke
  run_copilot_pull_node_fallback_smoke
  run_pull_special_path_smoke
  run_pull_diverge_smoke
  run_setup_existing_repo_prefers_pull_smoke
  run_status_crlf_node_fallback_smoke
  log "✅ 所有 smoke test 通过"
}

main "$@"
