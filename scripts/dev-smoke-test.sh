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
  bash -n install.sh uninstall.sh scripts/push.sh scripts/pull.sh
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
  run_install_smoke
  run_push_filter_smoke
  run_pull_merge_smoke
  run_pull_diverge_smoke
  log "✅ 所有 smoke test 通过"
}

main "$@"
