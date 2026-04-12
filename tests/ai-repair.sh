#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-repair-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.local/bin" "${tmpdir}/home/.codex"
export HOME="${tmpdir}/home"
export DOTFILES_REPO_ROOT="${REPO_ROOT}"

cat > "${HOME}/.local/bin/serena-mcp" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${HOME}/.local/bin/serena-mcp"

# Seed a minimal Codex config so upsert appends
cat > "${HOME}/.codex/config.toml" <<'EOF'
model = "gpt-5.4"
EOF

run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed when creating missing Serena state"
assert_contains "${RUN_OUTPUT}" "Created Serena config" "ai-repair should create Serena config when missing"
assert_contains "${RUN_OUTPUT}" "serena registration created" "ai-repair should register Serena for Claude Code"
assert_contains "${RUN_OUTPUT}" "Claude Code: auto-update channel set to latest" "ai-repair should normalize Claude Code channel"
assert_contains "${RUN_OUTPUT}" "Codex: baseline model/profiles/sandbox settings normalized" "ai-repair should normalize Codex baseline"
assert_contains "${RUN_OUTPUT}" "OpenAI Docs MCP registered" "ai-repair should register Docs MCP"
assert_contains "${RUN_OUTPUT}" "Codex GitHub MCP: GITHUB_PERSONAL_ACCESS_TOKEN is not set" "ai-repair should warn when GitHub token env is missing"
assert_contains "${RUN_OUTPUT}" "Codex Brave MCP: BRAVE_API_KEY is not set" "ai-repair should warn when Brave API key env is missing"
assert_contains "$(cat "${HOME}/.serena/serena_config.yml")" 'project_serena_folder_location: "$projectDir/.serena"' "ai-repair should write the expected Serena config"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"autoUpdatesChannel": "latest"' "ai-repair should write Claude auto-update channel"

# Verify Claude Code JSON registration
claude_json_cmd="$(python3 -c "import json; d=json.load(open('${HOME}/.claude.json')); print(d['mcpServers']['serena']['command'])")"
assert_eq "${HOME}/.local/bin/serena-mcp" "${claude_json_cmd}" "ai-repair should write the correct serena command to .claude.json"

# Verify Codex TOML registration
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'sandbox_mode = "workspace-write"' "ai-repair should set Codex sandbox mode"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'approval_policy = "on-request"' "ai-repair should set Codex approval policy"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[profiles.fast]" "ai-repair should add fast profile"
assert_contains "$(cat "${HOME}/.codex/config.toml")" '[mcp_servers.openaiDeveloperDocs]' "ai-repair should add Docs MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'url = "https://developers.openai.com/mcp"' "ai-repair should set Docs MCP URL"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.serena]" "ai-repair should add Codex MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "args = [\"codex\"]" "ai-repair should set correct Codex args"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.filesystem]" "ai-repair should add filesystem MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "@modelcontextprotocol/server-filesystem" "ai-repair should set filesystem MCP command args"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.github]" "ai-repair should add GitHub MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "@modelcontextprotocol/server-github" "ai-repair should set GitHub MCP command args"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'GITHUB_PERSONAL_ACCESS_TOKEN = "<YOUR_GITHUB_TOKEN>"' "ai-repair should set GitHub MCP token placeholder"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.brave-search]" "ai-repair should add Brave MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "@modelcontextprotocol/server-brave-search" "ai-repair should set Brave MCP command args"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'BRAVE_API_KEY = "<YOUR_BRAVE_API_KEY>"' "ai-repair should set Brave MCP key placeholder"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.drawio]" "ai-repair should add drawio MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "@drawio/mcp@latest" "ai-repair should set drawio MCP command args"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.playwright]" "ai-repair should add Playwright MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "@playwright/mcp@latest" "ai-repair should set Playwright MCP command args"

# Re-run should be idempotent
run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed on re-run"
assert_contains "${RUN_OUTPUT}" "already registered" "ai-repair should detect existing registration"
assert_contains "${RUN_OUTPUT}" "auto-update channel already set to latest" "ai-repair should detect existing Claude baseline"
assert_contains "${RUN_OUTPUT}" "OpenAI Docs MCP already registered" "ai-repair should detect existing Docs MCP"

pass_test "tests/ai-repair.sh"
