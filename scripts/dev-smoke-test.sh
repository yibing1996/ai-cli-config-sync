#!/usr/bin/env bash
# dev-smoke-test.sh — 发布前本地快速自测脚本

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf '[smoke] %s\n' "$*"
}

fail() {
  printf '[smoke] ❌ %s\n' "$*" >&2
  exit 1
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

run_syntax_check() {
  log "检查核心脚本语法"
  cd "$ROOT_DIR"
  bash -n install.sh uninstall.sh scripts/push.sh scripts/pull.sh scripts/dev-smoke-test.sh
}

run_docs_consistency_check() {
  log "检查文档中的安全同步语义"
  assert_contains "$ROOT_DIR/README.md" '安全同步（先推送本地改动；失败即停）'
  assert_not_contains "$ROOT_DIR/README.md" '先保守拉取，再推送'
  assert_contains "$ROOT_DIR/README.md" '### GitHub Copilot CLI'
  assert_contains "$ROOT_DIR/README.md" '### Claude Code CLI'
  assert_not_contains "$ROOT_DIR/README.md" '### GitHub Copilot CLI / Claude Code CLI'
  assert_contains "$ROOT_DIR/README_EN.md" 'Safe sync (push local changes first; stop on failure)'
  assert_not_contains "$ROOT_DIR/README_EN.md" 'safe pull first, then push'
  assert_contains "$ROOT_DIR/README_EN.md" '### GitHub Copilot CLI'
  assert_contains "$ROOT_DIR/README_EN.md" '### Claude Code CLI'
  assert_not_contains "$ROOT_DIR/README_EN.md" '### GitHub Copilot CLI / Claude Code CLI'
  assert_contains "$ROOT_DIR/skills/cli-config-sync/SKILL.md" '安全同步（先推送，失败即停）'
  assert_not_contains "$ROOT_DIR/skills/cli-config-sync/SKILL.md" '先 pull 再 push'
  assert_contains "$ROOT_DIR/skills/cli-config-sync/SKILL.md" '### GitHub Copilot CLI（`~/.copilot/`）'
  assert_not_contains "$ROOT_DIR/skills/cli-config-sync/SKILL.md" '### GitHub Copilot CLI / Claude Code CLI（`~/.claude/`）'
  assert_contains "$ROOT_DIR/skills/cli-config-sync/SKILL.md" '_sanitized_diff()'
  assert_not_contains "$ROOT_DIR/skills/cli-config-sync/SKILL.md" 'for f in copilot-instructions.md config.json mcp-config.json; do'
  assert_contains "$ROOT_DIR/skills/cli-config-sync-codex/SKILL.md" '安全同步（先推送，失败即停）'
  assert_not_contains "$ROOT_DIR/skills/cli-config-sync-codex/SKILL.md" '先 pull 再 push'
  assert_contains "$ROOT_DIR/skills/cli-config-sync-codex/SKILL.md" '### GitHub Copilot CLI（`~/.copilot/`）'
  assert_not_contains "$ROOT_DIR/skills/cli-config-sync-codex/SKILL.md" '### GitHub Copilot CLI / Claude Code CLI（`~/.claude/`）'
  assert_contains "$ROOT_DIR/skills/cli-config-sync-codex/SKILL.md" '_sanitized_diff()'
  assert_not_contains "$ROOT_DIR/skills/cli-config-sync-codex/SKILL.md" 'for f in copilot-instructions.md config.json mcp-config.json; do'
}

run_install_smoke() {
  local tmpdir home
  tmpdir="$(mktemp -d)"
  home="$tmpdir/home"

  log "验证 install.sh 在临时 HOME 下可用"
  HOME="$home" bash "$ROOT_DIR/install.sh" >/dev/null 2>&1

  assert_file "$home/.cli-sync/push.sh"
  assert_file "$home/.cli-sync/pull.sh"
  assert_file "$home/.claude/skills/cli-config-sync/SKILL.md"
  assert_file "$home/.codex/skills/cli-config-sync/SKILL.md"

  rm -rf "$tmpdir"
}

run_push_filter_smoke() {
  local tmpdir home remote filtered
  tmpdir="$(mktemp -d)"
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
  tmpdir="$(mktemp -d)"
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

run_pull_merge_smoke() {
  local tmpdir home remote merged settings
  tmpdir="$(mktemp -d)"
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
  tmpdir="$(mktemp -d)"
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

run_pull_special_path_smoke() {
  local tmpdir home remote merged
  tmpdir="$(mktemp -d)"
  home="$tmpdir/home\"quoted"
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
  tmpdir="$(mktemp -d)"
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

main() {
  run_syntax_check
  run_docs_consistency_check
  run_install_smoke
  run_push_filter_smoke
  run_copilot_push_filter_smoke
  run_pull_merge_smoke
  run_copilot_pull_merge_smoke
  run_pull_special_path_smoke
  run_pull_diverge_smoke
  log "✅ 所有 smoke test 通过"
}

main "$@"
