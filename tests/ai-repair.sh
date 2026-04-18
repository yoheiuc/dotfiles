#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-repair-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.local/bin" "${tmpdir}/home/.codex"
export HOME="${tmpdir}/home"
export XDG_CONFIG_HOME="${HOME}/.config"
export DOTFILES_REPO_ROOT="${REPO_ROOT}"
export FAKE_SECURITY_DB="${tmpdir}/security-db"

cat > "${tmpdir}/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
db="${FAKE_SECURITY_DB:?}"
mkdir -p "$(dirname "${db}")"
touch "${db}"
cmd="${1:?}"
shift
case "${cmd}" in
  add-generic-password)
    service=""
    account=""
    secret=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -U) shift ;;
        -s) service="$2"; shift 2 ;;
        -a) account="$2"; shift 2 ;;
        -w) secret="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    grep -v "^${service}"$'\t'"${account}"$'\t' "${db}" > "${db}.tmp" || true
    printf '%s\t%s\t%s\n' "${service}" "${account}" "${secret}" >> "${db}.tmp"
    mv "${db}.tmp" "${db}"
    ;;
  find-generic-password)
    service=""
    account=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -w) shift ;;
        -s) service="$2"; shift 2 ;;
        -a) account="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    awk -F '\t' -v s="${service}" -v a="${account}" '$1==s && $2==a { print $3; found=1 } END { exit found ? 0 : 1 }' "${db}"
    ;;
  delete-generic-password)
    service=""
    account=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -s) service="$2"; shift 2 ;;
        -a) account="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    grep -v "^${service}"$'\t'"${account}"$'\t' "${db}" > "${db}.tmp" || true
    mv "${db}.tmp" "${db}"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${tmpdir}/security"
export SECURITY_BIN="${tmpdir}/security"

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
assert_contains "${RUN_OUTPUT}" "Codex: baseline model/sandbox settings normalized" "ai-repair should normalize Codex baseline"
assert_contains "${RUN_OUTPUT}" "OpenAI Docs MCP registered" "ai-repair should register Docs MCP"
assert_contains "$(cat "${HOME}/.serena/serena_config.yml")" 'project_serena_folder_location: "$projectDir/.serena"' "ai-repair should write the expected Serena config"
assert_contains "$(cat "${HOME}/.claude/settings.json")" '"autoUpdatesChannel": "latest"' "ai-repair should write Claude auto-update channel"

# Verify Claude Code JSON registration
claude_json_cmd="$(python3 -c "import json; d=json.load(open('${HOME}/.claude.json')); print(d['mcpServers']['serena']['command'])")"
assert_eq "${HOME}/.local/bin/serena-mcp" "${claude_json_cmd}" "ai-repair should write the correct serena command to .claude.json"

# Verify Codex TOML registration
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'sandbox_mode = "workspace-write"' "ai-repair should set Codex sandbox mode"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'approval_policy = "on-request"' "ai-repair should set Codex approval policy"
assert_contains "$(cat "${HOME}/.codex/config.toml")" '[mcp_servers.openaiDeveloperDocs]' "ai-repair should add Docs MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'url = "https://developers.openai.com/mcp"' "ai-repair should set Docs MCP URL"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.serena]" "ai-repair should add Codex MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "args = [\"codex\"]" "ai-repair should set correct Codex args"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.filesystem]" "ai-repair should not register retired filesystem MCP in Codex"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" "@modelcontextprotocol/server-filesystem" "ai-repair should not set retired filesystem MCP args in Codex"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.github]" "ai-repair should not add removed GitHub MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.exa]" "ai-repair should add Exa MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'url = "https://mcp.exa.ai/mcp"' "ai-repair should set Exa MCP URL"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.brave-search]" "ai-repair should add Brave Search MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" 'mcp-with-keychain-secret' "ai-repair should route Brave Search MCP through the keychain wrapper"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "@modelcontextprotocol/server-brave-search" "ai-repair should set Brave Search MCP command args"
assert_not_contains "$(cat "${HOME}/.claude.json")" '"github"' "ai-repair should not register removed GitHub MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"exa"' "ai-repair should register Exa MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"url": "https://mcp.exa.ai/mcp"' "ai-repair should set Exa MCP URL for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-filesystem' "ai-repair should not register retired filesystem MCP for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@drawio/mcp@latest' "ai-repair should not register retired drawio MCP for Claude Code"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@playwright/mcp@latest' "ai-repair should not register retired Playwright MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" '"chrome-devtools"' "ai-repair should register chrome-devtools MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" 'chrome-devtools-mcp@latest' "ai-repair should set Claude chrome-devtools MCP args"
assert_contains "$(cat "${HOME}/.claude.json")" '"brave-search"' "ai-repair should register Brave Search MCP for Claude Code"
assert_contains "$(cat "${HOME}/.claude.json")" 'mcp-with-keychain-secret' "ai-repair should route Claude Brave Search MCP through the keychain wrapper"
assert_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-brave-search' "ai-repair should set Claude Brave Search MCP args"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.drawio]" "ai-repair should not register retired drawio MCP in Codex"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" "@drawio/mcp@latest" "ai-repair should not set retired drawio MCP args in Codex"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.playwright]" "ai-repair should not register retired Playwright MCP in Codex"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" "@playwright/mcp@latest" "ai-repair should not set retired Playwright MCP args in Codex"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "[mcp_servers.chrome-devtools]" "ai-repair should add chrome-devtools MCP section"
assert_contains "$(cat "${HOME}/.codex/config.toml")" "chrome-devtools-mcp@latest" "ai-repair should set chrome-devtools MCP command args"

# Re-run should be idempotent
run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed on re-run"
assert_contains "${RUN_OUTPUT}" "already registered" "ai-repair should detect existing registration"
assert_contains "${RUN_OUTPUT}" "auto-update channel already set to latest" "ai-repair should detect existing Claude baseline"
assert_contains "${RUN_OUTPUT}" "OpenAI Docs MCP already registered" "ai-repair should detect existing Docs MCP"

# Keychain should feed both Claude Code and Codex without plaintext config values
"${SECURITY_BIN}" add-generic-password -U -s dotfiles.ai.mcp -a brave-api-key -w BSAtest_key_12345
run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed when keychain secrets are present"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" 'BSAtest_key_12345' "ai-repair should not write the Brave API key into Codex config"
assert_not_contains "$(cat "${HOME}/.claude.json")" 'BSAtest_key_12345' "ai-repair should not write the Brave API key into Claude Code config"

# Legacy MCP removal — simulate an old dotfiles install and verify convergence.
python3 -c "
import json
p = '${HOME}/.claude.json'
with open(p) as f: d = json.load(f)
d.setdefault('mcpServers', {})['playwright'] = {
  'type': 'stdio', 'command': 'npx', 'args': ['-y', '@playwright/mcp@latest']
}
d['mcpServers']['filesystem'] = {
  'type': 'stdio', 'command': 'bash',
  'args': ['-lc', 'npx -y @modelcontextprotocol/server-filesystem \"\$HOME\"']
}
d['mcpServers']['drawio'] = {
  'type': 'stdio', 'command': 'npx', 'args': ['-y', '@drawio/mcp@latest']
}
with open(p, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
"
cat >> "${HOME}/.codex/config.toml" <<'EOF'

[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest"]

[mcp_servers.playwright.tools.browser_navigate]
approval_mode = "approve"

[mcp_servers.filesystem]
command = "bash"
args = ["-lc", "npx -y @modelcontextprotocol/server-filesystem \"$HOME\""]

[mcp_servers.drawio]
command = "npx"
args = ["-y", "@drawio/mcp@latest"]
EOF

run_capture bash "${REPO_ROOT}/scripts/ai-repair.sh"
assert_eq "0" "${RUN_STATUS}" "ai-repair should succeed when purging legacy MCPs"
assert_contains "${RUN_OUTPUT}" "legacy playwright MCP removed" "ai-repair should announce legacy playwright removal"
assert_contains "${RUN_OUTPUT}" "legacy filesystem MCP removed" "ai-repair should announce legacy filesystem removal"
assert_contains "${RUN_OUTPUT}" "legacy drawio MCP removed" "ai-repair should announce legacy drawio removal"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@playwright/mcp@latest' "ai-repair should strip legacy playwright from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@modelcontextprotocol/server-filesystem' "ai-repair should strip legacy filesystem from .claude.json"
assert_not_contains "$(cat "${HOME}/.claude.json")" '@drawio/mcp@latest' "ai-repair should strip legacy drawio from .claude.json"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" '[mcp_servers.playwright]' "ai-repair should strip legacy playwright section from Codex config"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" '[mcp_servers.playwright.tools.browser_navigate]' "ai-repair should strip legacy playwright tools subsections from Codex config"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" '[mcp_servers.filesystem]' "ai-repair should strip legacy filesystem section from Codex config"
assert_not_contains "$(cat "${HOME}/.codex/config.toml")" '[mcp_servers.drawio]' "ai-repair should strip legacy drawio section from Codex config"

pass_test "tests/ai-repair.sh"
