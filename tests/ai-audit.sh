#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/tests/lib/testlib.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-audit-test.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/home/.claude"
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
cp "${REPO_ROOT}/scripts/lib/ui.sh" "${tmpdir}/scripts/lib/ui.sh"
cp "${REPO_ROOT}/scripts/lib/ai-config.sh" "${tmpdir}/scripts/lib/ai-config.sh"
cp "${REPO_ROOT}/scripts/lib/ai_config.py" "${tmpdir}/scripts/lib/ai_config.py"
cp "${REPO_ROOT}/scripts/lib/claude-plugins.sh" "${tmpdir}/scripts/lib/claude-plugins.sh"
cp "${REPO_ROOT}/scripts/lib/claude-checks.sh" "${tmpdir}/scripts/lib/claude-checks.sh"
chmod +x "${tmpdir}/scripts/ai-audit.sh" "${tmpdir}/scripts/lib/ai-config.sh"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/claude-plugins.sh"

# ---- Scenario 1: clean case ----
write_installed_plugins_stub
cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "latest",
  "effortLevel": "xhigh",
  "env": {"ENABLE_TOOL_SEARCH": "auto:5"},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Grep", "hooks": [{"type": "command", "command": "$HOME/.claude/lsp-hint.sh"}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [
        {"type": "command", "command": "$HOME/.claude/auto-save.sh"},
        {"type": "command", "command": "$HOME/.claude/chezmoi-auto-apply.sh"}
      ]}
    ]
  }
}
EOF
cat > "${HOME}/.claude.json" <<EOF
{
  "mcpServers": {
    "exa": {
      "type": "http",
      "url": "https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa,web_search_advanced_exa"
    },
    "jamf-docs": {
      "type": "http",
      "url": "https://developer.jamf.com/mcp"
    },
    "slack": {
      "type": "http",
      "url": "https://mcp.slack.com/mcp",
      "oauth": {"clientId": "1601185624273.8899143856786", "callbackPort": 3118}
    },
    "vision": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@tuannvm/vision-mcp-server"]
    },
    "sequential-thinking": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    }
  }
}
EOF
: > "${HOME}/.claude/CLAUDE.md"
run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should succeed in the clean case"
assert_contains "${RUN_OUTPUT}" "Claude settings: present" "ai-audit should report local claude settings"
assert_contains "${RUN_OUTPUT}" "Claude Code: auto-update channel is latest" "ai-audit should validate Claude channel"
assert_contains "${RUN_OUTPUT}" "Claude Code: ENABLE_TOOL_SEARCH env is set" "ai-audit should validate ENABLE_TOOL_SEARCH env"
assert_contains "${RUN_OUTPUT}" "Claude Code: effortLevel is xhigh" "ai-audit should validate effortLevel xhigh baseline"
assert_contains "${RUN_OUTPUT}" "Claude Code: hook registered (\$HOME/.claude/lsp-hint.sh)" "ai-audit should validate lsp-hint hook"
assert_contains "${RUN_OUTPUT}" "Claude Code: hook registered (\$HOME/.claude/auto-save.sh)" "ai-audit should validate auto-save hook"
assert_contains "${RUN_OUTPUT}" "Claude Code: hook registered (\$HOME/.claude/chezmoi-auto-apply.sh)" "ai-audit should validate chezmoi-auto-apply hook"
assert_contains "${RUN_OUTPUT}" "Claude Code vision MCP: registered" "ai-audit should validate Claude vision MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code sequential-thinking MCP: registered" "ai-audit should validate Claude sequential-thinking MCP"
assert_not_contains "${RUN_OUTPUT}" "Claude Code brave-search MCP: registered" "ai-audit should not expect retired Claude Brave Search MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code exa MCP: registered" "ai-audit should validate Claude Exa MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code jamf-docs MCP: registered" "ai-audit should validate Claude Jamf docs MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code slack MCP: registered" "ai-audit should validate Claude Slack MCP"
assert_not_contains "${RUN_OUTPUT}" "Claude Code serena MCP: legacy entry present" "ai-audit should not flag serena when absent"
assert_not_contains "${RUN_OUTPUT}" "Retired Serena state still on disk" "ai-audit should not flag Serena state when absent"
assert_contains "${RUN_OUTPUT}" "No retired agent state at ${HOME}/.codex" "ai-audit should report absence of retired Codex state"
assert_contains "${RUN_OUTPUT}" "No retired agent state at ${HOME}/.gemini" "ai-audit should report absence of retired Gemini state"
assert_contains "${RUN_OUTPUT}" "LSP plugins: all ${#CLAUDE_LSP_PLUGINS[@]} installed" "ai-audit should validate LSP plugins are installed"
assert_contains "${RUN_OUTPUT}" "general plugins: all ${#CLAUDE_GENERAL_PLUGINS[@]} installed" "ai-audit should validate general plugins are installed"
assert_contains "${RUN_OUTPUT}" "AI config audit looks good." "ai-audit should report a clean result"

# ---- Scenario 1b: --quiet on a clean tree ----
run_capture bash "${tmpdir}/scripts/ai-audit.sh" --quiet
assert_eq "0" "${RUN_STATUS}" "ai-audit --quiet should exit 0 when clean"
assert_eq "" "${RUN_OUTPUT}" "ai-audit --quiet should print nothing when clean"

# ---- Scenario 2: drift + registrations ----
cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "stable"
}
cc-bridge
EOF
cat > "${HOME}/.claude.json" <<'EOF'
{
  "mcpServers": {}
}
EOF
: > "${HOME}/.claude/settings.json.pre-unmanage-test"
: > "${FAKE_SECURITY_DB}"

# Retired agent state left on disk — audit should flag for removal.
mkdir -p "${HOME}/.codex"
mkdir -p "${HOME}/.gemini"

run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should stay informational with warnings"
assert_contains "${RUN_OUTPUT}" "Claude settings: legacy bridge or unsafe approval settings detected" "ai-audit should detect legacy claude settings"
assert_contains "${RUN_OUTPUT}" "Claude Code: auto-update channel should be latest" "ai-audit should detect Claude channel drift"
assert_contains "${RUN_OUTPUT}" "Claude Code: ENABLE_TOOL_SEARCH env should be auto:5" "ai-audit should detect missing ENABLE_TOOL_SEARCH env"
assert_contains "${RUN_OUTPUT}" "Claude Code: effortLevel should be xhigh" "ai-audit should detect missing effortLevel xhigh"
assert_contains "${RUN_OUTPUT}" "Claude Code: hook missing (\$HOME/.claude/lsp-hint.sh)" "ai-audit should detect missing lsp-hint hook"
assert_contains "${RUN_OUTPUT}" "Claude Code: hook missing (\$HOME/.claude/auto-save.sh)" "ai-audit should detect missing auto-save hook"
assert_contains "${RUN_OUTPUT}" "Claude Code: hook missing (\$HOME/.claude/chezmoi-auto-apply.sh)" "ai-audit should detect missing chezmoi-auto-apply hook"
assert_contains "${RUN_OUTPUT}" "Claude Code vision MCP: missing or drifted" "ai-audit should detect missing Claude vision MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code sequential-thinking MCP: missing or drifted" "ai-audit should detect missing Claude sequential-thinking MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code exa MCP: missing or drifted" "ai-audit should detect missing Claude Exa MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code jamf-docs MCP: missing or drifted" "ai-audit should detect missing Claude Jamf docs MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code slack MCP: missing or drifted" "ai-audit should detect missing Claude Slack MCP"
assert_contains "${RUN_OUTPUT}" "Retired agent state still on disk: ${HOME}/.codex" "ai-audit should flag retired Codex state"
assert_contains "${RUN_OUTPUT}" "Retired agent state still on disk: ${HOME}/.gemini" "ai-audit should flag retired Gemini state"
assert_contains "${RUN_OUTPUT}" "Claude settings backups: found backup files to review or delete" "ai-audit should report backup files"
assert_contains "${RUN_OUTPUT}" "AI config audit needs attention:" "ai-audit should summarize warnings"

# ---- Scenario 2b: --quiet on a dirty tree exits non-zero ----
run_capture bash "${tmpdir}/scripts/ai-audit.sh" --quiet
assert_eq "1" "${RUN_STATUS}" "ai-audit --quiet should exit 1 when attention items exist"
assert_contains "${RUN_OUTPUT}" "Retired agent state still on disk" "ai-audit --quiet should still print attention lines"
assert_not_contains "${RUN_OUTPUT}" "AI config audit" "ai-audit --quiet should suppress the summary banner"

# ---- Scenario 2c: missing plugins surface as attention ----
rm -f "${HOME}/.claude/plugins/installed_plugins.json"
run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_contains "${RUN_OUTPUT}" "LSP plugins missing" "ai-audit should flag missing LSP plugins"
assert_contains "${RUN_OUTPUT}" "general plugins missing" "ai-audit should flag missing general plugins"
write_installed_plugins_stub  # restore for following scenarios

# Clean up retired-state dirs for next scenario
rm -rf "${HOME}/.codex" "${HOME}/.gemini"

# ---- Scenario 3: legacy MCP entries (playwright, filesystem, drawio) still present ----
cat > "${HOME}/.claude.json" <<EOF
{
  "mcpServers": {
    "exa": {"type":"http","url":"https://mcp.exa.ai/mcp?tools=web_search_exa,web_fetch_exa,web_search_advanced_exa"},
    "chrome-devtools": {"type":"stdio","command":"npx","args":["-y","chrome-devtools-mcp@latest"]},
    "brave-search": {"type":"stdio","command":"${HOME}/.local/bin/mcp-with-keychain-secret","args":["BRAVE_API_KEY","dotfiles.ai.mcp","brave-api-key","npx","-y","@modelcontextprotocol/server-brave-search"]},
    "playwright": {"type":"stdio","command":"npx","args":["-y","@playwright/mcp@latest"]},
    "filesystem": {"type":"stdio","command":"bash","args":["-lc","npx -y @modelcontextprotocol/server-filesystem \"\$HOME\""]},
    "drawio": {"type":"stdio","command":"npx","args":["-y","@drawio/mcp@latest"]},
    "notion": {"type":"http","url":"https://mcp.notion.com/mcp"},
    "github": {"type":"stdio","command":"npx","args":["-y","@modelcontextprotocol/server-github"]},
    "owlocr": {"type":"stdio","command":"bash","args":["-lc","uvx --quiet --from git+https://github.com/jangisaac-dev/owlocr-mcp owlocr-mcp"]},
    "serena": {"type":"stdio","command":"${HOME}/.local/bin/serena-mcp","args":["claude-code"],"env":{"UV_NATIVE_TLS":"true"}}
  }
}
EOF
# Simulate leftover Serena wrapper + config so the audit flags them as retired state.
mkdir -p "${HOME}/.local/bin" "${HOME}/.serena"
: > "${HOME}/.local/bin/serena-mcp"
chmod +x "${HOME}/.local/bin/serena-mcp"
: > "${HOME}/.serena/serena_config.yml"
rm -f "${HOME}/.claude/settings.json.pre-unmanage-test"
cat > "${HOME}/.claude/settings.json" <<'EOF'
{
  "autoUpdatesChannel": "latest",
  "effortLevel": "xhigh",
  "env": {"ENABLE_TOOL_SEARCH": "auto:5"},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Grep", "hooks": [{"type": "command", "command": "$HOME/.claude/lsp-hint.sh"}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [
        {"type": "command", "command": "$HOME/.claude/auto-save.sh"},
        {"type": "command", "command": "$HOME/.claude/chezmoi-auto-apply.sh"}
      ]}
    ]
  }
}
EOF
run_capture bash "${tmpdir}/scripts/ai-audit.sh"
assert_eq "0" "${RUN_STATUS}" "ai-audit should stay informational when legacy MCPs are present"
assert_contains "${RUN_OUTPUT}" "Claude Code playwright MCP: legacy entry present" "ai-audit should flag legacy Claude Code playwright MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code filesystem MCP: legacy entry present" "ai-audit should flag legacy Claude Code filesystem MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code drawio MCP: legacy entry present" "ai-audit should flag legacy Claude Code drawio MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code notion MCP: legacy entry present" "ai-audit should flag legacy Claude Code notion MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code github MCP: legacy entry present" "ai-audit should flag legacy Claude Code github MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code owlocr MCP: legacy entry present" "ai-audit should flag legacy Claude Code owlocr MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code chrome-devtools MCP: legacy entry present" "ai-audit should flag legacy Claude Code chrome-devtools MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code brave-search MCP: legacy entry present" "ai-audit should flag legacy Claude Code brave-search MCP"
assert_contains "${RUN_OUTPUT}" "Claude Code serena MCP: legacy entry present" "ai-audit should flag legacy Claude Code serena MCP"
assert_contains "${RUN_OUTPUT}" "Retired Serena state still on disk" "ai-audit should flag leftover Serena state"
assert_contains "${RUN_OUTPUT}" "Retired Serena wrapper still present" "ai-audit should flag leftover Serena wrapper"

pass_test "tests/ai-audit.sh"
