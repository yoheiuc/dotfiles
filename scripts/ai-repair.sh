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
SERENA_CLAUDE_ENTRY='{"type":"stdio","command":"'"${SERENA_WRAPPER}"'","args":["claude-code"],"env":{}}'
case "$(ai_config_mcp_registration_state "${CLAUDE_JSON}" serena "${SERENA_WRAPPER}")" in
  ok)
    ok "Claude Code: serena already registered with wrapper"
    ;;
  wrong-command)
    ai_config_json_upsert_mcp "${CLAUDE_JSON}" serena "${SERENA_CLAUDE_ENTRY}"
    ok "Claude Code: serena registration repaired"
    restart_needed=1
    ;;
  missing)
    ai_config_json_upsert_mcp "${CLAUDE_JSON}" serena "${SERENA_CLAUDE_ENTRY}"
    ok "Claude Code: serena registration created"
    restart_needed=1
    ;;
esac

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
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" model_reasoning_effort '"high"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" personality '"pragmatic"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" sandbox_mode '"workspace-write"'
ai_config_toml_upsert_top_level "${CODEX_CONFIG}" approval_policy '"on-request"'
ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[profiles.fast]" $'model = "codex-mini-latest"\nmodel_reasoning_effort = "low"\npersonality = "pragmatic"'
ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[profiles.review]" $'model = "gpt-5.4"\nmodel_reasoning_effort = "high"\npersonality = "pragmatic"'
ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[profiles.deep]" $'model = "gpt-5.4"\nmodel_reasoning_effort = "high"\npersonality = "pragmatic"'
ai_config_toml_upsert_section_block "${CODEX_CONFIG}" "[features]" $'multi_agent = true\ncodex_hooks = true'
ok "Codex: baseline model/profiles/sandbox settings normalized"

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

printf '\nVerify with: make ai-audit\n'
if [[ "${restart_needed}" == "1" ]]; then
  printf 'Then restart Claude Code / Codex and close any old terminals still using stale MCP settings.\n'
fi
