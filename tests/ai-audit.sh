#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-audit-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.codex" "${tmpdir}/home/.claude" "${tmpdir}/home/.gemini" "${tmpdir}/home/.serena"
mkdir -p "${tmpdir}/scripts/lib"
export HOME="${tmpdir}/home"
export XDG_CONFIG_HOME="${HOME}/.config"
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

cp "${REPO_ROOT}/scripts/ai-audit.sh" "${tmpdir}/scripts/ai-audit.sh"
cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${tmpdir}/scripts/lib/ai-config.sh"
chmod +x "${tmpdir}/scripts/ai-audit.sh" "${tmpdir}/scripts/lib/ai-config.sh"

# ---- Scenario 1: clean case ----
cat > "${HOME}/.codex/config.toml" <<EOF
model = "gpt-5.4"
model_reasoning_effort = "medium"
sandbox_mode = "workspace-write"
approval_policy = "on-request"

[features]
multi_agent = true
codex_hooks = true

[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"

[mcp_servers.exa]
url = "https://mcp.exa.ai/mcp"

[mcp_servers.brave-search]
command = "${HOME}/.local/bin/mcp-with-keychain-secret"
args = ["BRAVE_API_KEY", "dotfiles.ai.mcp", "brave-api-key", "npx", "-y", "@modelcontextprotocol/server-brave-search"]

[mcp_servers.chrome-devtools]
command = "npx"
args = ["-y", "chrome-devtools-mcp@latest"]

[mcp_servers.serena]
command = "${HOME}/.local/bin/serena-mcp"
args = ["codex"]
EOF
cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "latest"
}
EOF
cat > "${HOME}/.claude.json" <<EOF
{
  "mcpServers": {
    "exa": {
      "type": "http",
      "url": "https://mcp.exa.ai/mcp"
    },
    "chrome-devtools": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest"]
    },
    "brave-search": {
      "type": "stdio",
      "command": "${HOME}/.local/bin/mcp-with-keychain-secret",
      "args": ["BRAVE_API_KEY", "dotfiles.ai.mcp", "brave-api-key", "npx", "-y", "@modelcontextprotocol/server-brave-search"]
    },
    "serena": {
      "type": "stdio",
      "command": "${HOME}/.local/bin/serena-mcp",
      "args": ["claude-code"],
      "env": {"UV_NATIVE_TLS": "true"}
    }
  }
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
"${SECURITY_BIN}" add-generic-password -U -s dotfiles.ai.mcp -a brave-api-key -w BSAtest_audit_key
run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should succeed in the clean case"
assert_contains "${RUN_OUTPUT}" "Codex config: present" "ai-audit should report local codex config"
assert_contains "${RUN_OUTPUT}" "Claude settings: present" "ai-audit should report local claude settings"
assert_contains "${RUN_OUTPUT}" "Codex config: no legacy bridge settings detected" "ai-audit should scan codex config"
assert_contains "${RUN_OUTPUT}" "Claude Code: auto-update channel is latest" "ai-audit should validate Claude channel"
assert_contains "${RUN_OUTPUT}" "Claude Code chrome-devtools MCP: registered" "ai-audit should validate Claude chrome-devtools MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code brave-search MCP: registered" "ai-audit should validate Claude Brave Search MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code exa MCP: registered" "ai-audit should validate Claude Exa MCP"
assert_contains "${RUN_OUTPUT}" "Codex: sandbox mode is workspace-write" "ai-audit should validate Codex sandbox"
assert_contains "${RUN_OUTPUT}" "Codex OpenAI Docs MCP: registered" "ai-audit should validate Docs MCP"
assert_contains "${RUN_OUTPUT}" "Codex exa MCP: registered" "ai-audit should validate Exa MCP"
assert_contains "${RUN_OUTPUT}" "Codex brave-search MCP: registered" "ai-audit should validate Brave Search MCP"
assert_contains "${RUN_OUTPUT}" "Codex chrome-devtools MCP: registered" "ai-audit should validate chrome-devtools MCP"
assert_contains "${RUN_OUTPUT}" "Serena config: web_dashboard enabled" "ai-audit should validate Serena config"
assert_contains "${RUN_OUTPUT}" "Claude Code Serena MCP: registered" "ai-audit should report Claude MCP registration"
assert_contains "${RUN_OUTPUT}" "Codex Serena MCP: registered via wrapper" "ai-audit should report Codex MCP registration"
assert_contains "${RUN_OUTPUT}" "AI config audit looks good." "ai-audit should report a clean result"

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
> "${FAKE_SECURITY_DB}"

run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should stay informational with warnings"
assert_contains "${RUN_OUTPUT}" "Gemini settings: missing" "ai-audit should warn on missing gemini settings"
assert_contains "${RUN_OUTPUT}" "Codex config: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy codex settings"
assert_contains "${RUN_OUTPUT}" "Claude settings: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy claude settings"
assert_contains "${RUN_OUTPUT}" "Claude Code: auto-update channel should be latest" "ai-audit should detect Claude channel drift"
assert_contains "${RUN_OUTPUT}" "Claude Code chrome-devtools MCP: missing or drifted" "ai-audit should detect missing Claude chrome-devtools MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code brave-search MCP: missing or drifted" "ai-audit should detect missing Claude Brave Search MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code exa MCP: missing or drifted" "ai-audit should detect missing Claude Exa MCP"
assert_contains "${RUN_OUTPUT}" "Serena config: language_backend should be LSP" "ai-audit should detect Serena config drift"
assert_contains "${RUN_OUTPUT}" "Claude Code Serena MCP: registered" "ai-audit should detect Claude MCP registration"
assert_contains "${RUN_OUTPUT}" "Codex Serena MCP: registered via wrapper" "ai-audit should detect Codex wrapper registration"
assert_contains "${RUN_OUTPUT}" "Codex OpenAI Docs MCP: missing" "ai-audit should detect missing Docs MCP"
assert_contains "${RUN_OUTPUT}" "Codex exa MCP: missing" "ai-audit should detect missing Exa MCP"
assert_contains "${RUN_OUTPUT}" "Codex brave-search MCP: missing" "ai-audit should detect missing Brave Search MCP"
assert_contains "${RUN_OUTPUT}" "Codex chrome-devtools MCP: missing" "ai-audit should detect missing chrome-devtools MCP"
assert_contains "${RUN_OUTPUT}" "Codex config backups: found backup files to review or delete" "ai-audit should report backup files"
assert_contains "${RUN_OUTPUT}" "AI config audit needs attention:" "ai-audit should summarize warnings"

# ---- Scenario 3: legacy MCP entries (playwright, filesystem, drawio) still present ----
cat > "${HOME}/.codex/config.toml" <<EOF
model = "gpt-5.4"
model_reasoning_effort = "medium"
sandbox_mode = "workspace-write"
approval_policy = "on-request"

[features]
multi_agent = true
codex_hooks = true

[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"

[mcp_servers.exa]
url = "https://mcp.exa.ai/mcp"

[mcp_servers.brave-search]
command = "${HOME}/.local/bin/mcp-with-keychain-secret"
args = ["BRAVE_API_KEY", "dotfiles.ai.mcp", "brave-api-key", "npx", "-y", "@modelcontextprotocol/server-brave-search"]

[mcp_servers.chrome-devtools]
command = "npx"
args = ["-y", "chrome-devtools-mcp@latest"]

[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest"]

[mcp_servers.filesystem]
command = "bash"
args = ["-lc", "npx -y @modelcontextprotocol/server-filesystem \"\$HOME\""]

[mcp_servers.drawio]
command = "npx"
args = ["-y", "@drawio/mcp@latest"]

[mcp_servers.serena]
command = "${HOME}/.local/bin/serena-mcp"
args = ["codex"]
EOF
cat > "${HOME}/.claude.json" <<EOF
{
  "mcpServers": {
    "exa": {"type":"http","url":"https://mcp.exa.ai/mcp"},
    "chrome-devtools": {"type":"stdio","command":"npx","args":["-y","chrome-devtools-mcp@latest"]},
    "brave-search": {"type":"stdio","command":"${HOME}/.local/bin/mcp-with-keychain-secret","args":["BRAVE_API_KEY","dotfiles.ai.mcp","brave-api-key","npx","-y","@modelcontextprotocol/server-brave-search"]},
    "playwright": {"type":"stdio","command":"npx","args":["-y","@playwright/mcp@latest"]},
    "filesystem": {"type":"stdio","command":"bash","args":["-lc","npx -y @modelcontextprotocol/server-filesystem \"\$HOME\""]},
    "drawio": {"type":"stdio","command":"npx","args":["-y","@drawio/mcp@latest"]},
    "serena": {"type":"stdio","command":"${HOME}/.local/bin/serena-mcp","args":["claude-code"],"env":{"UV_NATIVE_TLS":"true"}}
  }
}
EOF
rm -f "${HOME}/.codex/config.toml.pre-unmanage-test"
cat > "${HOME}/.claude/settings.json" <<'EOF'
{"autoUpdatesChannel":"latest"}
EOF
cat > "${HOME}/.serena/serena_config.yml" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
EOF

run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should stay informational when legacy MCPs are present"
assert_contains "${RUN_OUTPUT}" "Claude Code playwright MCP: legacy entry present" "ai-audit should flag legacy Claude Code playwright MCP"
assert_contains "${RUN_OUTPUT}" "Codex playwright MCP: legacy entry present" "ai-audit should flag legacy Codex playwright MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code filesystem MCP: legacy entry present" "ai-audit should flag legacy Claude Code filesystem MCP"
assert_contains "${RUN_OUTPUT}" "Codex filesystem MCP: legacy entry present" "ai-audit should flag legacy Codex filesystem MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code drawio MCP: legacy entry present" "ai-audit should flag legacy Claude Code drawio MCP"
assert_contains "${RUN_OUTPUT}" "Codex drawio MCP: legacy entry present" "ai-audit should flag legacy Codex drawio MCP"

pass_test "tests/ai-audit.sh"
