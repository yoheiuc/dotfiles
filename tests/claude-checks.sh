#!/usr/bin/env bash
# tests/claude-checks.sh — unit tests for scripts/lib/claude-checks.sh predicates.
#
# These predicates are the shared read-state surface between ai-audit.sh,
# ai-repair.sh, doctor.sh and status.sh. Indirect coverage exists via the
# script-level integration tests, but predicate-level edge cases (missing
# file / wrong value / partial match) deserve direct assertions so that
# threshold changes (e.g. effortLevel xhigh→high降格 2026-04-27) surface
# here first.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"
source "${REPO_ROOT}/scripts/lib/claude-plugins.sh"
source "${REPO_ROOT}/scripts/lib/claude-checks.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-claude-checks-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

# Predicates resolve ${HOME}/.claude/settings.json etc at call time, so
# pointing HOME at a per-test fixture root is enough — no subshell needed.
HOME="${tmpdir}/home"
mkdir -p "${HOME}/.claude" "${HOME}/.playwright" "${HOME}/.config/zsh"

settings="${HOME}/.claude/settings.json"

# Helper — runs predicate, returns "true"/"false" string instead of relying on
# bash exit codes (more legible in assertions).
predicate_result() {
  if "$@"; then echo "true"; else echo "false"; fi
}

# ── claude_autoupdate_is_latest ──────────────────────────────────────────────
rm -f "${settings}"
assert_eq "false" "$(predicate_result claude_autoupdate_is_latest)" \
  "autoupdate predicate should be false when settings.json missing"
echo '{"autoUpdatesChannel":"stable"}' > "${settings}"
assert_eq "false" "$(predicate_result claude_autoupdate_is_latest)" \
  "autoupdate predicate should be false when channel != latest"
echo '{"autoUpdatesChannel":"latest"}' > "${settings}"
assert_eq "true"  "$(predicate_result claude_autoupdate_is_latest)" \
  "autoupdate predicate should be true when channel == latest"

# ── claude_enable_tool_search_is_set ─────────────────────────────────────────
rm -f "${settings}"
assert_eq "false" "$(predicate_result claude_enable_tool_search_is_set)" \
  "tool_search predicate should be false when settings.json missing"
echo '{"env":{}}' > "${settings}"
assert_eq "false" "$(predicate_result claude_enable_tool_search_is_set)" \
  "tool_search predicate should be false when env.ENABLE_TOOL_SEARCH unset"
echo '{"env":{"ENABLE_TOOL_SEARCH":"auto:5"}}' > "${settings}"
assert_eq "true"  "$(predicate_result claude_enable_tool_search_is_set)" \
  "tool_search predicate should be true when env.ENABLE_TOOL_SEARCH == auto:5"

# ── claude_effort_is_high ────────────────────────────────────────────────────
rm -f "${settings}"
assert_eq "false" "$(predicate_result claude_effort_is_high)" \
  "effort predicate should be false when settings.json missing"
echo '{"effortLevel":"xhigh"}' > "${settings}"
assert_eq "false" "$(predicate_result claude_effort_is_high)" \
  "effort predicate should be false when effortLevel != high"
echo '{"effortLevel":"high"}' > "${settings}"
assert_eq "true"  "$(predicate_result claude_effort_is_high)" \
  "effort predicate should be true when effortLevel == high"

# ── claude_hook_command_present ──────────────────────────────────────────────
rm -f "${settings}"
assert_eq "false" "$(predicate_result claude_hook_command_present '$HOME/.claude/auto-save.sh')" \
  "hook predicate should be false when settings.json missing"
cat > "${settings}" <<'EOF'
{
  "hooks": {
    "Stop": [
      {"matcher": "", "hooks": [
        {"type": "command", "command": "$HOME/.claude/auto-save.sh"}
      ]}
    ]
  }
}
EOF
assert_eq "true"  "$(predicate_result claude_hook_command_present '$HOME/.claude/auto-save.sh')" \
  "hook predicate should match registered hook command"
assert_eq "false" "$(predicate_result claude_hook_command_present '$HOME/.claude/never-registered.sh')" \
  "hook predicate should not match unregistered command"

# ── claude_mcp_present / _stdio_matches / _http_matches ─────────────────────
mcp_file="${tmpdir}/claude.json"
cat > "${mcp_file}" <<'EOF'
{
  "mcpServers": {
    "vision": {"type": "stdio", "command": "npx", "args": ["-y", "@tuannvm/vision-mcp-server"]},
    "exa":    {"type": "http",  "url": "https://mcp.exa.ai/mcp"}
  }
}
EOF
assert_eq "true"  "$(predicate_result claude_mcp_present "${mcp_file}" vision)" \
  "mcp_present should be true when entry exists"
assert_eq "false" "$(predicate_result claude_mcp_present "${mcp_file}" missing)" \
  "mcp_present should be false when entry absent"
assert_eq "false" "$(predicate_result claude_mcp_present "${tmpdir}/no-such-file.json" vision)" \
  "mcp_present should be false when file missing"

assert_eq "true"  "$(predicate_result claude_mcp_stdio_matches "${mcp_file}" vision npx '-y|@tuannvm/vision-mcp-server')" \
  "stdio_matches should accept exact command + pipe-joined args"
assert_eq "false" "$(predicate_result claude_mcp_stdio_matches "${mcp_file}" vision npx 'wrong-args')" \
  "stdio_matches should reject mismatched args"

assert_eq "true"  "$(predicate_result claude_mcp_http_matches "${mcp_file}" exa 'https://mcp.exa.ai/mcp')" \
  "http_matches should accept exact url + type=http"
assert_eq "false" "$(predicate_result claude_mcp_http_matches "${mcp_file}" exa 'https://wrong.example')" \
  "http_matches should reject mismatched url"

# ── claude_lsp_plugins_missing / claude_general_plugins_missing ─────────────
# Empty installed_plugins.json → every dotfiles-owned plugin is missing.
mkdir -p "${HOME}/.claude/plugins"
echo '{"plugins":{}}' > "${HOME}/.claude/plugins/installed_plugins.json"
missing_lsp="$(claude_lsp_plugins_missing | wc -l | tr -d ' ')"
assert_eq "${#CLAUDE_LSP_PLUGINS[@]}" "${missing_lsp}" \
  "lsp_plugins_missing should list every plugin when none installed"
missing_general="$(claude_general_plugins_missing | wc -l | tr -d ' ')"
assert_eq "${#CLAUDE_GENERAL_PLUGINS[@]}" "${missing_general}" \
  "general_plugins_missing should list every plugin when none installed"
# Mark them all installed via the shared stub helper → both predicates empty.
write_installed_plugins_stub
assert_eq "" "$(claude_lsp_plugins_missing)" \
  "lsp_plugins_missing should be empty when all installed"
assert_eq "" "$(claude_general_plugins_missing)" \
  "general_plugins_missing should be empty when all installed"

# ── playwright_is_stealth_patched ────────────────────────────────────────────
pw_cfg="${HOME}/.playwright/cli.config.json"
rm -f "${pw_cfg}"
assert_eq "false" "$(predicate_result playwright_is_stealth_patched)" \
  "playwright stealth predicate should be false when config missing"
cat > "${pw_cfg}" <<'EOF'
{ "browser": { "launchOptions": { "args": [], "ignoreDefaultArgs": [] } } }
EOF
assert_eq "false" "$(predicate_result playwright_is_stealth_patched)" \
  "playwright stealth predicate should be false when sentinels absent"
cat > "${pw_cfg}" <<'EOF'
{
  "browser": {
    "launchOptions": {
      "args": ["--disable-blink-features=AutomationControlled"],
      "ignoreDefaultArgs": ["--enable-automation"]
    }
  }
}
EOF
assert_eq "true" "$(predicate_result playwright_is_stealth_patched)" \
  "playwright stealth predicate should be true with both sentinels present"

# ── playwright_pwopen_is_ephemeral ───────────────────────────────────────────
pw_zsh="${HOME}/.config/zsh/playwright.zsh"
rm -f "${pw_zsh}"
assert_eq "false" "$(predicate_result playwright_pwopen_is_ephemeral)" \
  "pwopen ephemeral predicate should be false when wrapper missing"
echo 'true' > "${pw_zsh}"
assert_eq "false" "$(predicate_result playwright_pwopen_is_ephemeral)" \
  "pwopen ephemeral predicate should be false when sentinels absent"
cat > "${pw_zsh}" <<'EOF'
__pwopen_cleanup() { :; }
pwopen() {
  trap __pwopen_cleanup EXIT INT TERM
  chmod 700 "$dir"
  date -u +%Y%m%dT%H%M%SZ "$$"
}
EOF
assert_eq "true" "$(predicate_result playwright_pwopen_is_ephemeral)" \
  "pwopen ephemeral predicate should be true when all four sentinels present"

pass_test "tests/claude-checks.sh"
