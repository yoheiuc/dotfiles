#!/usr/bin/env bash
# ai-repair.sh — normalize local AI runtime settings that commonly drift
#
# Usage:
#   ./scripts/ai-repair.sh
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"

log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }

SERENA_WRAPPER="${HOME}/.local/bin/serena-mcp"
KEYCHAIN_ENV_WRAPPER="${HOME}/.local/bin/mcp-with-keychain-secret"
SERENA_CONFIG_DIR="${HOME}/.serena"
SERENA_CONFIG_PATH="${SERENA_CONFIG_DIR}/serena_config.yml"
SERENA_CONFIG_BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"

CLAUDE_JSON="${HOME}/.claude.json"
CLAUDE_SETTINGS_JSON="${HOME}/.claude/settings.json"
CODEX_CONFIG="${HOME}/.codex/config.toml"
OPENAI_DOCS_MCP_URL="https://developers.openai.com/mcp"

restart_needed=0

write_serena_config() {
  mkdir -p "${SERENA_CONFIG_DIR}"
  cat > "${SERENA_CONFIG_PATH}" <<'EOF'
language_backend: LSP
web_dashboard: true
web_dashboard_open_on_launch: false
project_serena_folder_location: "$projectDir/.serena"
projects: []
EOF
}

# ---- Serena local config -----------------------------------------------------
log "Serena local config..."
if [[ ! -f "${SERENA_CONFIG_PATH}" ]]; then
  write_serena_config
  ok "Created Serena config at ${SERENA_CONFIG_PATH}"
else
  serena_config_ok=1
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^language_backend:[[:space:]]*LSP([[:space:]]|$)'; then
    serena_config_ok=0
  fi
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^web_dashboard:[[:space:]]*true([[:space:]]|$)'; then
    serena_config_ok=0
  fi
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^web_dashboard_open_on_launch:[[:space:]]*false([[:space:]]|$)'; then
    serena_config_ok=0
  fi
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^project_serena_folder_location:[[:space:]]*"\$projectDir/\.serena"([[:space:]]|$)'; then
    serena_config_ok=0
  fi
  if ! ai_config_file_contains_regex "${SERENA_CONFIG_PATH}" '^projects:'; then
    serena_config_ok=0
  fi

  if [[ "${serena_config_ok}" == "1" ]]; then
    ok "Serena config already matches expected defaults"
  else
    cp "${SERENA_CONFIG_PATH}" "${SERENA_CONFIG_PATH}.pre-ai-repair-${SERENA_CONFIG_BACKUP_SUFFIX}"
    write_serena_config
    ok "Reset Serena config to expected defaults"
    ok "Backup saved to ${SERENA_CONFIG_PATH}.pre-ai-repair-${SERENA_CONFIG_BACKUP_SUFFIX}"
  fi
  unset serena_config_ok
fi

# ---- Serena wrapper ----------------------------------------------------------
log "Serena wrapper..."
if [[ -x "${SERENA_WRAPPER}" ]]; then
  ok "Wrapper present: ${SERENA_WRAPPER}"
else
  warn "Wrapper missing: ${SERENA_WRAPPER}"
  warn "  Run: chezmoi apply"
fi

# ---- Claude Code MCP registration (JSON direct) -----------------------------
log "Claude Code MCP registration..."
SERENA_CLAUDE_ENTRY='{"type":"stdio","command":"'"${SERENA_WRAPPER}"'","args":["claude-code"],"env":{"UV_NATIVE_TLS":"true"}}'
EXA_CLAUDE_ENTRY='{"type":"http","url":"https://mcp.exa.ai/mcp"}'
# Slack's clientId / callbackPort below are public values published in Slack's
# official docs (https://docs.slack.dev/ai/slack-mcp-server/connect-to-claude/),
# not secrets. OAuth tokens themselves are managed by Claude Code, not dotfiles.
SLACK_CLAUDE_ENTRY='{"type":"http","url":"https://mcp.slack.com/mcp","oauth":{"clientId":"1601185624273.8899143856786","callbackPort":3118}}'
CHROME_DEVTOOLS_CLAUDE_ENTRY='{"type":"stdio","command":"npx","args":["-y","chrome-devtools-mcp@latest"]}'
# owlocr-mcp runs via uvx directly against the GitHub repo — no local clone,
# no wrapper script. Serena uses a similar uvx approach but wraps it in
# ~/.local/bin/serena-mcp for config flags; owlocr needs no such wrapping.
# Requires macOS (Vision framework) + uv installed + the upstream repo to
# expose an `owlocr-mcp` entry under `[project.scripts]` in its pyproject.
# If MCP connect fails, verify with: uvx --from git+... owlocr-mcp --help
OWLOCR_CLAUDE_ENTRY='{"type":"stdio","command":"bash","args":["-lc","uvx --quiet --from git+https://github.com/jangisaac-dev/owlocr-mcp owlocr-mcp"]}'
BRAVE_SEARCH_CLAUDE_ENTRY='{"type":"stdio","command":"'"${KEYCHAIN_ENV_WRAPPER}"'","args":["BRAVE_API_KEY","dotfiles.ai.mcp","brave-api-key","npx","-y","@modelcontextprotocol/server-brave-search"]}'
serena_cmd_state="$(ai_config_mcp_registration_state "${CLAUDE_JSON}" serena "${SERENA_WRAPPER}")"
serena_uv_tls="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('serena',{}).get('env',{}).get('UV_NATIVE_TLS','')" 2>/dev/null || true)"
claude_chrome_devtools_cmd="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('chrome-devtools',{}).get('command','')" 2>/dev/null || true)"
claude_chrome_devtools_args="$(ai_config_json_read "${CLAUDE_JSON}" "'|'.join(d.get('mcpServers',{}).get('chrome-devtools',{}).get('args',[]))" 2>/dev/null || true)"
claude_owlocr_cmd="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('owlocr',{}).get('command','')" 2>/dev/null || true)"
claude_owlocr_args="$(ai_config_json_read "${CLAUDE_JSON}" "'|'.join(d.get('mcpServers',{}).get('owlocr',{}).get('args',[]))" 2>/dev/null || true)"
claude_exa_url="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('exa',{}).get('url','')" 2>/dev/null || true)"
claude_slack_url="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('slack',{}).get('url','')" 2>/dev/null || true)"
claude_brave_search_cmd="$(ai_config_json_read "${CLAUDE_JSON}" "d.get('mcpServers',{}).get('brave-search',{}).get('command','')" 2>/dev/null || true)"

if [[ "${serena_cmd_state}" == "ok" && "${serena_uv_tls}" == "true" ]]; then
  ok "Claude Code: serena already registered with wrapper and UV_NATIVE_TLS"
else
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" serena "${SERENA_CLAUDE_ENTRY}"
  if [[ "${serena_cmd_state}" != "ok" ]]; then
    ok "Claude Code: serena registration repaired/created"
  else
    ok "Claude Code: serena UV_NATIVE_TLS env added"
  fi
  restart_needed=1
fi
unset serena_cmd_state serena_uv_tls

if [[ "${claude_chrome_devtools_cmd}" != "npx" || "${claude_chrome_devtools_args}" != '-y|chrome-devtools-mcp@latest' ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" chrome-devtools "${CHROME_DEVTOOLS_CLAUDE_ENTRY}"
  ok "Claude Code: chrome-devtools MCP registered"
  restart_needed=1
else
  ok "Claude Code: chrome-devtools MCP already registered"
fi

_owlocr_expected_args='-lc|uvx --quiet --from git+https://github.com/jangisaac-dev/owlocr-mcp owlocr-mcp'
if [[ "${claude_owlocr_cmd}" != "bash" || "${claude_owlocr_args}" != "${_owlocr_expected_args}" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" owlocr "${OWLOCR_CLAUDE_ENTRY}"
  ok "Claude Code: owlocr MCP registered"
  restart_needed=1
else
  ok "Claude Code: owlocr MCP already registered"
fi
unset _owlocr_expected_args

if [[ "${claude_exa_url}" != "https://mcp.exa.ai/mcp" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" exa "${EXA_CLAUDE_ENTRY}"
  ok "Claude Code: exa MCP registered"
  restart_needed=1
else
  ok "Claude Code: exa MCP already registered"
fi

if [[ "${claude_slack_url}" != "https://mcp.slack.com/mcp" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" slack "${SLACK_CLAUDE_ENTRY}"
  ok "Claude Code: slack MCP registered"
  restart_needed=1
else
  ok "Claude Code: slack MCP already registered"
fi

if [[ "${claude_brave_search_cmd}" != "${KEYCHAIN_ENV_WRAPPER}" ]]; then
  ai_config_json_upsert_mcp "${CLAUDE_JSON}" brave-search "${BRAVE_SEARCH_CLAUDE_ENTRY}"
  ok "Claude Code: brave-search MCP registered"
  restart_needed=1
else
  ok "Claude Code: brave-search MCP already registered"
fi

unset claude_chrome_devtools_cmd claude_chrome_devtools_args claude_owlocr_cmd claude_owlocr_args claude_exa_url claude_slack_url claude_brave_search_cmd

# Strip legacy MCP registrations that have been retired.
#   playwright  → @playwright/cli + skill (see post-setup.sh)
#   filesystem  → native Claude Code Read/Write/Edit/Grep/Glob tools
#   drawio      → Mermaid (inline in .md) or mermaid-cli (mmdc) for PNG/SVG output
#   notion      → ntn CLI + makenotion/skills (see post-setup.sh)
#   github      → gh CLI (gh pr, gh issue, gh api …)
for _legacy in playwright filesystem drawio notion github; do
  if [[ "$(ai_config_json_remove_mcp "${CLAUDE_JSON}" "${_legacy}" 2>/dev/null || true)" == "removed" ]]; then
    ok "Claude Code: legacy ${_legacy} MCP removed"
    restart_needed=1
  fi
done
unset _legacy

# ---- Claude Code local settings baseline -----------------------------------
log "Claude Code local settings..."
mkdir -p "$(dirname "${CLAUDE_SETTINGS_JSON}")"
if [[ "$(ai_config_json_read "${CLAUDE_SETTINGS_JSON}" "d.get('autoUpdatesChannel','')" 2>/dev/null || true)" == "latest" ]]; then
  ok "Claude Code: auto-update channel already set to latest"
else
  ai_config_json_upsert_key "${CLAUDE_SETTINGS_JSON}" autoUpdatesChannel '"latest"'
  ok "Claude Code: auto-update channel set to latest"
fi

# ---- Codex baseline ---------------------------------------------------------
log "Codex baseline..."
mkdir -p "$(dirname "${CODEX_CONFIG}")"
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" model '"gpt-5.4"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" model_reasoning_effort '"medium"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" personality '"pragmatic"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" sandbox_mode '"workspace-write"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" approval_policy '"on-request"'
ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[features]" $'multi_agent = true\ncodex_hooks = true'
ok "Codex: baseline model/sandbox settings normalized"

# ---- Codex MCP registration (TOML direct) -----------------------------------
log "Codex MCP registration..."
case "$(ai_config_codex_mcp_state "${CODEX_CONFIG}" "${SERENA_WRAPPER}")" in
  ok)
    ok "Codex: serena already registered with wrapper"
    ;;
  wrong-command)
    ai_config_codex_upsert_mcp "${CODEX_CONFIG}" serena "${SERENA_WRAPPER}" codex
    ok "Codex: serena registration repaired"
    restart_needed=1
    ;;
  missing)
    ai_config_codex_upsert_mcp "${CODEX_CONFIG}" serena "${SERENA_WRAPPER}" codex
    ok "Codex: serena registration created"
    restart_needed=1
    ;;
esac

case "$(ai_config_codex_mcp_url_state "${CODEX_CONFIG}" openaiDeveloperDocs "${OPENAI_DOCS_MCP_URL}")" in
  ok)
    ok "Codex: OpenAI Docs MCP already registered"
    ;;
  wrong-url|missing)
    ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.openaiDeveloperDocs]" "url = \"${OPENAI_DOCS_MCP_URL}\""
    ok "Codex: OpenAI Docs MCP registered"
    restart_needed=1
    ;;
esac

codex_chrome_devtools_cmd="$(ai_config_toml_read "${CODEX_CONFIG}" "d.get('mcp_servers',{}).get('chrome-devtools',{}).get('command','')" 2>/dev/null || true)"
codex_chrome_devtools_args="$(ai_config_toml_read "${CODEX_CONFIG}" "'|'.join(d.get('mcp_servers',{}).get('chrome-devtools',{}).get('args',[]))" 2>/dev/null || true)"
codex_owlocr_cmd="$(ai_config_toml_read "${CODEX_CONFIG}" "d.get('mcp_servers',{}).get('owlocr',{}).get('command','')" 2>/dev/null || true)"
codex_owlocr_args="$(ai_config_toml_read "${CODEX_CONFIG}" "'|'.join(d.get('mcp_servers',{}).get('owlocr',{}).get('args',[]))" 2>/dev/null || true)"
codex_exa_url="$(ai_config_toml_read "${CODEX_CONFIG}" "d.get('mcp_servers',{}).get('exa',{}).get('url','')" 2>/dev/null || true)"
codex_slack_url="$(ai_config_toml_read "${CODEX_CONFIG}" "d.get('mcp_servers',{}).get('slack',{}).get('url','')" 2>/dev/null || true)"
codex_brave_search_cmd="$(ai_config_toml_read "${CODEX_CONFIG}" "d.get('mcp_servers',{}).get('brave-search',{}).get('command','')" 2>/dev/null || true)"

if [[ "${codex_chrome_devtools_cmd}" != "npx" || "${codex_chrome_devtools_args}" != '-y|chrome-devtools-mcp@latest' ]]; then
  ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.chrome-devtools]" $'command = "npx"\nargs = ["-y", "chrome-devtools-mcp@latest"]'
  ok "Codex: chrome-devtools MCP registered"
  restart_needed=1
else
  ok "Codex: chrome-devtools MCP already registered"
fi

_codex_owlocr_expected_args='-lc|uvx --quiet --from git+https://github.com/jangisaac-dev/owlocr-mcp owlocr-mcp'
if [[ "${codex_owlocr_cmd}" != "bash" || "${codex_owlocr_args}" != "${_codex_owlocr_expected_args}" ]]; then
  ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.owlocr]" $'command = "bash"\nargs = ["-lc", "uvx --quiet --from git+https://github.com/jangisaac-dev/owlocr-mcp owlocr-mcp"]'
  ok "Codex: owlocr MCP registered"
  restart_needed=1
else
  ok "Codex: owlocr MCP already registered"
fi
unset _codex_owlocr_expected_args

if [[ "${codex_exa_url}" != "https://mcp.exa.ai/mcp" ]]; then
  ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.exa]" 'url = "https://mcp.exa.ai/mcp"'
  ok "Codex: exa MCP registered"
  restart_needed=1
else
  ok "Codex: exa MCP already registered"
fi

if [[ "${codex_slack_url}" != "https://mcp.slack.com/mcp" ]]; then
  ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.slack]" 'url = "https://mcp.slack.com/mcp"'
  ok "Codex: slack MCP registered"
  restart_needed=1
else
  ok "Codex: slack MCP already registered"
fi

if [[ "${codex_brave_search_cmd}" != "${KEYCHAIN_ENV_WRAPPER}" ]]; then
  ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[mcp_servers.brave-search]" $'command = "'"${KEYCHAIN_ENV_WRAPPER}"$'"\nargs = ["BRAVE_API_KEY", "dotfiles.ai.mcp", "brave-api-key", "npx", "-y", "@modelcontextprotocol/server-brave-search"]'
  ok "Codex: brave-search MCP registered"
  restart_needed=1
else
  ok "Codex: brave-search MCP already registered"
fi

unset codex_chrome_devtools_cmd codex_chrome_devtools_args codex_owlocr_cmd codex_owlocr_args codex_exa_url codex_slack_url codex_brave_search_cmd

# Strip legacy Codex MCP registrations retired in favor of CLIs / native tools.
for _legacy in playwright filesystem drawio notion github; do
  if [[ "$(ai_config_toml_remove_mcp_section "${CODEX_CONFIG}" "${_legacy}" 2>/dev/null || true)" == "removed" ]]; then
    ok "Codex: legacy ${_legacy} MCP removed"
    restart_needed=1
  fi
done
unset _legacy

printf '\nVerify with: make ai-audit\n'
if [[ "${restart_needed}" == "1" ]]; then
  printf 'Then restart Claude Code / Codex and close any old terminals still using stale MCP settings.\n'
fi
