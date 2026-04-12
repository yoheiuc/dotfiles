#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-audit-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.codex" "${tmpdir}/home/.claude" "${tmpdir}/home/.gemini" "${tmpdir}/home/.serena"
mkdir -p "${tmpdir}/scripts/lib"
export HOME="${tmpdir}/home"

cp "${REPO_ROOT}/scripts/ai-audit.sh" "${tmpdir}/scripts/ai-audit.sh"
cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${tmpdir}/scripts/lib/ai-config.sh"
chmod +x "${tmpdir}/scripts/ai-audit.sh" "${tmpdir}/scripts/lib/ai-config.sh"

# ---- Scenario 1: clean case ----
cat > "${HOME}/.codex/config.toml" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
approval_policy = "on-request"

[features]
multi_agent = true
codex_hooks = true

[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"

[mcp_servers.filesystem]
command = "bash"
args = ["-lc", "npx -y @modelcontextprotocol/server-filesystem \"$HOME\" \"$HOME/ghq\""]

[mcp_servers.github]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]

[mcp_servers.brave-search]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-brave-search"]

[mcp_servers.drawio]
command = "npx"
args = ["-y", "@drawio/mcp@latest"]

[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest"]
EOF
cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "latest"
}
EOF
: > "${HOME}/.gemini/settings.json"
: > "${HOME}/.codex/hooks.json"
: > "${HOME}/.claude/CLAUDE.md"
: > "${HOME}/AGENTS.md"
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
EOF

run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should succeed in the clean case"
assert_contains "${RUN_OUTPUT}" "Codex config: present" "ai-audit should report local codex config"
assert_contains "${RUN_OUTPUT}" "Claude settings: present" "ai-audit should report local claude settings"
assert_contains "${RUN_OUTPUT}" "Codex config: no legacy bridge settings detected" "ai-audit should scan codex config"
assert_contains "${RUN_OUTPUT}" "Claude Code: auto-update channel is latest" "ai-audit should validate Claude channel"
assert_contains "${RUN_OUTPUT}" "Codex: sandbox mode is workspace-write" "ai-audit should validate Codex sandbox"
assert_contains "${RUN_OUTPUT}" "Codex OpenAI Docs MCP: registered" "ai-audit should validate Docs MCP"
assert_contains "${RUN_OUTPUT}" "Codex filesystem MCP: registered" "ai-audit should validate filesystem MCP"
assert_contains "${RUN_OUTPUT}" "Codex github MCP: registered" "ai-audit should validate GitHub MCP"
assert_contains "${RUN_OUTPUT}" "Codex brave-search MCP: registered" "ai-audit should validate Brave MCP"
assert_contains "${RUN_OUTPUT}" "Codex drawio MCP: registered" "ai-audit should validate drawio MCP"
assert_contains "${RUN_OUTPUT}" "Codex playwright MCP: registered" "ai-audit should validate Playwright MCP"
assert_contains "${RUN_OUTPUT}" "Serena config: web_dashboard enabled" "ai-audit should validate Serena config"
assert_contains "${RUN_OUTPUT}" "Claude Code Serena MCP: missing" "ai-audit should report missing Claude MCP registration"
assert_contains "${RUN_OUTPUT}" "Codex Serena MCP: missing" "ai-audit should report missing Codex MCP registration"
assert_contains "${RUN_OUTPUT}" "AI config audit needs attention:" "ai-audit should summarize MCP registration warnings"

# ---- Scenario 2: drift + registrations ----
cat > "${HOME}/.codex/config.toml" <<EOF
# --- BEGIN CCB ---
approval_policy = "never"
sandbox_mode = "danger-full-access"

[mcp_servers.serena]
command = "${HOME}/.local/bin/serena-mcp"
args = ["codex"]
EOF
cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "stable"
}
cc-bridge
EOF
rm -f "${HOME}/.gemini/settings.json"
: > "${HOME}/.codex/config.toml.pre-unmanage-test"
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: JetBrains
web_dashboard: false
web_dashboard_open_on_launch: true
project_serena_folder_location: "/tmp/serena"
EOF
cat > "${HOME}/.claude.json" <<EOF
{
  "mcpServers": {
    "serena": {
      "type": "stdio",
      "command": "${HOME}/.local/bin/serena-mcp",
      "args": ["claude-code"],
      "env": {}
    }
  }
}
EOF

run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should stay informational with warnings"
assert_contains "${RUN_OUTPUT}" "Gemini settings: missing" "ai-audit should warn on missing gemini settings"
assert_contains "${RUN_OUTPUT}" "Codex config: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy codex settings"
assert_contains "${RUN_OUTPUT}" "Claude settings: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy claude settings"
assert_contains "${RUN_OUTPUT}" "Claude Code: auto-update channel should be latest" "ai-audit should detect Claude channel drift"
assert_contains "${RUN_OUTPUT}" "Serena config: language_backend should be LSP" "ai-audit should detect Serena config drift"
assert_contains "${RUN_OUTPUT}" "Claude Code Serena MCP: registered" "ai-audit should detect Claude MCP registration"
assert_contains "${RUN_OUTPUT}" "Codex Serena MCP: registered via wrapper" "ai-audit should detect Codex wrapper registration"
assert_contains "${RUN_OUTPUT}" "Codex OpenAI Docs MCP: missing" "ai-audit should detect missing Docs MCP"
assert_contains "${RUN_OUTPUT}" "Codex filesystem MCP: missing" "ai-audit should detect missing filesystem MCP"
assert_contains "${RUN_OUTPUT}" "Codex github MCP: missing" "ai-audit should detect missing GitHub MCP"
assert_contains "${RUN_OUTPUT}" "Codex brave-search MCP: missing" "ai-audit should detect missing Brave MCP"
assert_contains "${RUN_OUTPUT}" "Codex drawio MCP: missing" "ai-audit should detect missing drawio MCP"
assert_contains "${RUN_OUTPUT}" "Codex playwright MCP: missing" "ai-audit should detect missing Playwright MCP"
assert_contains "${RUN_OUTPUT}" "Codex config backups: found backup files to review or delete" "ai-audit should report backup files"
assert_contains "${RUN_OUTPUT}" "AI config audit needs attention:" "ai-audit should summarize warnings"

pass_test "tests/ai-audit.sh"
