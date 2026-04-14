#!/usr/bin/env bash
# ai-audit.sh — focused audit for local AI client configs and shared guidance
#
# Usage:
#   ./scripts/ai-audit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ai-config.sh"

SECURITY_BIN="${SECURITY_BIN:-security}"
KEYCHAIN_SERVICE="dotfiles.ai.mcp"
GITHUB_KEYCHAIN_ACCOUNT="github-personal-access-token"
AI_SHARED_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/ai-secrets.env"
AI_SHARED_ENV_FALLBACK_FILE="${HOME}/.config/dotfiles/ai-secrets.env"

ATTENTION_COUNT=0

section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
ok() { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
info() { printf '  - %s\n' "$*"; }
attention() {
  warn "$*"
  ATTENTION_COUNT=$((ATTENTION_COUNT + 1))
}

describe_file() {
  local label="$1"
  local path="$2"

  if [[ -f "${path}" ]]; then
    info "$(ai_config_describe_file "${label}" "${path}" 1)"
  else
    attention "${label}: missing (${path})"
  fi
}

scan_file_for_legacy_patterns() {
  local label="$1"
  local path="$2"

  if [[ ! -f "${path}" ]]; then
    return 0
  fi

  if ai_config_has_legacy_settings "${path}"; then
    attention "${label}: legacy bridge or unsafe approval settings detected"
  else
    ok "${label}: no legacy bridge settings detected"
  fi
}

report_optional_backups() {
  local label="$1"
  local glob_pattern="$2"
  local matches

  matches="$(ai_config_backup_matches "${glob_pattern}")"
  if [[ -z "${matches}" ]]; then
    ok "${label}: none found"
    return 0
  fi

  attention "${label}: found backup files to review or delete"
  printf '%s\n' "${matches}" | sed 's/^/    /'
}

read_legacy_env_secret() {
  local env_name="$1"
  local env_file="${AI_SHARED_ENV_FILE}"
  if [[ ! -f "${env_file}" && "${AI_SHARED_ENV_FALLBACK_FILE}" != "${env_file}" && -f "${AI_SHARED_ENV_FALLBACK_FILE}" ]]; then
    env_file="${AI_SHARED_ENV_FALLBACK_FILE}"
  fi

  if [[ ! -f "${env_file}" ]]; then
    printf ''
    return 0
  fi

  env -i bash -lc "
    set -a
    source '${env_file}'
    set +a
    printf '%s' \"\${${env_name}:-}\"
  " 2>/dev/null
}

read_keychain_secret() {
  local account="$1"
  if ! command -v "${SECURITY_BIN}" >/dev/null 2>&1; then
    printf ''
    return 0
  fi
  "${SECURITY_BIN}" find-generic-password -w -s "${KEYCHAIN_SERVICE}" -a "${account}" 2>/dev/null || true
}

resolve_ai_secret() {
  local env_name="$1"
  local account="$2"
  local secret=""

  secret="$(read_keychain_secret "${account}")"
  if [[ -z "${secret}" ]]; then
    secret="$(read_legacy_env_secret "${env_name}")"
  fi
  printf '%s' "${secret}"
}

echo
printf '\033[1m=== AI config audit ===\033[0m\n'

section "Local Config Files"
describe_file "Codex config" "${HOME}/.codex/config.toml"
describe_file "Claude settings" "${HOME}/.claude/settings.json"
describe_file "Gemini settings" "${HOME}/.gemini/settings.json"
describe_file "Serena config" "${HOME}/.serena/serena_config.yml"

section "Shared Guidance"
describe_file "Codex hooks" "${HOME}/.codex/hooks.json"
describe_file "Claude guidance" "${HOME}/.claude/CLAUDE.md"
describe_file "AGENTS" "${HOME}/AGENTS.md"

section "Legacy Pattern Scan"
scan_file_for_legacy_patterns "Codex config" "${HOME}/.codex/config.toml"
scan_file_for_legacy_patterns "Claude settings" "${HOME}/.claude/settings.json"
scan_file_for_legacy_patterns "Gemini settings" "${HOME}/.gemini/settings.json"
scan_file_for_legacy_patterns "Codex hooks" "${HOME}/.codex/hooks.json"
scan_file_for_legacy_patterns "Claude guidance" "${HOME}/.claude/CLAUDE.md"
scan_file_for_legacy_patterns "AGENTS" "${HOME}/AGENTS.md"

section "Claude Code Baseline"
if [[ -f "${HOME}/.claude/settings.json" ]]; then
  if [[ "$(ai_config_json_read "${HOME}/.claude/settings.json" "d.get('autoUpdatesChannel','')" 2>/dev/null || true)" == "latest" ]]; then
    ok "Claude Code: auto-update channel is latest"
  else
    attention "Claude Code: auto-update channel should be latest"
  fi
else
  attention "Claude Code settings: missing (${HOME}/.claude/settings.json)"
fi

_claude_json="${HOME}/.claude.json"
if [[ -f "${_claude_json}" ]]; then
  _claude_filesystem_cmd="$(ai_config_json_read "${_claude_json}" "d.get('mcpServers',{}).get('filesystem',{}).get('command','')" 2>/dev/null || true)"
  _claude_filesystem_args="$(ai_config_json_read "${_claude_json}" "'|'.join(d.get('mcpServers',{}).get('filesystem',{}).get('args',[]))" 2>/dev/null || true)"
  if [[ "${_claude_filesystem_cmd}" == "bash" && "${_claude_filesystem_args}" == '-lc|npx -y @modelcontextprotocol/server-filesystem "$HOME"' ]]; then
    ok "Claude Code filesystem MCP: registered"
  else
    attention "Claude Code filesystem MCP: missing or drifted — run make ai-repair"
  fi

  _claude_drawio_cmd="$(ai_config_json_read "${_claude_json}" "d.get('mcpServers',{}).get('drawio',{}).get('command','')" 2>/dev/null || true)"
  _claude_drawio_args="$(ai_config_json_read "${_claude_json}" "'|'.join(d.get('mcpServers',{}).get('drawio',{}).get('args',[]))" 2>/dev/null || true)"
  if [[ "${_claude_drawio_cmd}" == "npx" && "${_claude_drawio_args}" == '-y|@drawio/mcp@latest' ]]; then
    ok "Claude Code drawio MCP: registered"
  else
    attention "Claude Code drawio MCP: missing or drifted — run make ai-repair"
  fi

  _claude_playwright_cmd="$(ai_config_json_read "${_claude_json}" "d.get('mcpServers',{}).get('playwright',{}).get('command','')" 2>/dev/null || true)"
  _claude_playwright_args="$(ai_config_json_read "${_claude_json}" "'|'.join(d.get('mcpServers',{}).get('playwright',{}).get('args',[]))" 2>/dev/null || true)"
  if [[ "${_claude_playwright_cmd}" == "npx" && "${_claude_playwright_args}" == '-y|@playwright/mcp@latest' ]]; then
    ok "Claude Code playwright MCP: registered"
  else
    attention "Claude Code playwright MCP: missing or drifted — run make ai-repair"
  fi

  _claude_chrome_devtools_cmd="$(ai_config_json_read "${_claude_json}" "d.get('mcpServers',{}).get('chrome-devtools',{}).get('command','')" 2>/dev/null || true)"
  _claude_chrome_devtools_args="$(ai_config_json_read "${_claude_json}" "'|'.join(d.get('mcpServers',{}).get('chrome-devtools',{}).get('args',[]))" 2>/dev/null || true)"
  if [[ "${_claude_chrome_devtools_cmd}" == "npx" && "${_claude_chrome_devtools_args}" == '-y|chrome-devtools-mcp@latest' ]]; then
    ok "Claude Code chrome-devtools MCP: registered"
  else
    attention "Claude Code chrome-devtools MCP: missing or drifted — run make ai-repair"
  fi

  _claude_exa_url="$(ai_config_json_read "${_claude_json}" "d.get('mcpServers',{}).get('exa',{}).get('url','')" 2>/dev/null || true)"
  _claude_exa_type="$(ai_config_json_read "${_claude_json}" "d.get('mcpServers',{}).get('exa',{}).get('type','')" 2>/dev/null || true)"
  if [[ "${_claude_exa_url}" == "https://mcp.exa.ai/mcp" && "${_claude_exa_type}" == "http" ]]; then
    ok "Claude Code exa MCP: registered"
  else
    attention "Claude Code exa MCP: missing or drifted — run make ai-repair"
  fi
  unset _claude_filesystem_cmd _claude_filesystem_args _claude_drawio_cmd _claude_drawio_args _claude_playwright_cmd _claude_playwright_args _claude_chrome_devtools_cmd _claude_chrome_devtools_args _claude_exa_url _claude_exa_type
else
  attention "Claude Code MCP config: missing (${_claude_json})"
fi

section "Codex Baseline"
_codex_config="${HOME}/.codex/config.toml"
if [[ -f "${_codex_config}" ]]; then
  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('model','')" 2>/dev/null || true)" == "gpt-5.4" ]]; then
    ok "Codex: model is gpt-5.4"
  else
    attention "Codex: model should be gpt-5.4"
  fi

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('model_reasoning_effort','')" 2>/dev/null || true)" == "medium" ]]; then
    ok "Codex: default reasoning effort is medium"
  else
    attention "Codex: default reasoning effort should be medium"
  fi

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('sandbox_mode','')" 2>/dev/null || true)" == "workspace-write" ]]; then
    ok "Codex: sandbox mode is workspace-write"
  else
    attention "Codex: sandbox mode should be workspace-write"
  fi

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('approval_policy','')" 2>/dev/null || true)" == "on-request" ]]; then
    ok "Codex: approval policy is on-request"
  else
    attention "Codex: approval policy should be on-request"
  fi

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('features',{}).get('codex_hooks',False)" 2>/dev/null || true)" == "True" ]]; then
    ok "Codex: hooks enabled"
  else
    attention "Codex: hooks should be enabled"
  fi

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('features',{}).get('multi_agent',False)" 2>/dev/null || true)" == "True" ]]; then
    ok "Codex: multi-agent enabled"
  else
    attention "Codex: multi-agent should be enabled"
  fi

  case "$(ai_config_codex_mcp_url_state "${_codex_config}" openaiDeveloperDocs "https://developers.openai.com/mcp")" in
    ok)
      ok "Codex OpenAI Docs MCP: registered"
      ;;
    wrong-url)
      attention "Codex OpenAI Docs MCP: wrong URL — run make ai-repair"
      ;;
    missing)
      attention "Codex OpenAI Docs MCP: missing — run make ai-repair"
      ;;
  esac

  for _server in filesystem drawio playwright chrome-devtools; do
    case "$(ai_config_toml_read "${_codex_config}" "d.get('mcp_servers',{}).get('${_server}',{}).get('command','')" 2>/dev/null || true)" in
      "")
        attention "Codex ${_server} MCP: missing — run make ai-repair"
        ;;
      *)
        ok "Codex ${_server} MCP: registered"
        ;;
    esac
  done

  if [[ "$(ai_config_toml_read "${_codex_config}" "d.get('mcp_servers',{}).get('exa',{}).get('url','')" 2>/dev/null || true)" == "https://mcp.exa.ai/mcp" ]]; then
    ok "Codex exa MCP: registered"
  else
    attention "Codex exa MCP: missing — run make ai-repair"
  fi

else
  attention "Codex config: missing (${_codex_config})"
fi

section "Serena Config"
if [[ -f "${HOME}/.serena/serena_config.yml" ]]; then
  if ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^language_backend:[[:space:]]*LSP([[:space:]]|$)'; then
    ok "Serena config: language_backend is LSP"
  else
    attention "Serena config: language_backend should be LSP"
  fi

  if ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^web_dashboard:[[:space:]]*true([[:space:]]|$)'; then
    ok "Serena config: web_dashboard enabled"
  else
    attention "Serena config: web_dashboard should be true"
  fi

  if ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^web_dashboard_open_on_launch:[[:space:]]*false([[:space:]]|$)'; then
    ok "Serena config: dashboard auto-open disabled"
  else
    attention "Serena config: web_dashboard_open_on_launch should be false"
  fi

  if ai_config_file_contains_regex "${HOME}/.serena/serena_config.yml" '^project_serena_folder_location:[[:space:]]*"\$projectDir/\.serena"([[:space:]]|$)'; then
    ok "Serena config: project metadata stored in-project"
  else
    attention 'Serena config: project_serena_folder_location should be "$projectDir/.serena"'
  fi
else
  attention "Serena config: missing (${HOME}/.serena/serena_config.yml)"
fi

section "MCP Registration"
_serena_wrapper="${HOME}/.local/bin/serena-mcp"

_claude_json="${HOME}/.claude.json"
case "$(ai_config_mcp_registration_state "${_claude_json}" serena "${_serena_wrapper}")" in
  ok)
    ok "Claude Code Serena MCP: registered"
    ;;
  wrong-command)
    attention "Claude Code Serena MCP: wrong command — run make ai-repair"
    ;;
  missing)
    attention "Claude Code Serena MCP: missing — run make ai-repair"
    ;;
esac

case "$(ai_config_codex_mcp_state "${_codex_config}" "${_serena_wrapper}")" in
  ok)
    ok "Codex Serena MCP: registered via wrapper"
    ;;
  wrong-command)
    attention "Codex Serena MCP: wrong command — run make ai-repair"
    ;;
  missing)
    attention "Codex Serena MCP: missing — run make ai-repair"
    ;;
esac
unset _serena_wrapper _claude_json _codex_config

section "Backup Files"
report_optional_backups "Codex config backups" "${HOME}/.codex/config.toml.pre-unmanage-*"
report_optional_backups "Claude settings backups" "${HOME}/.claude/settings.json.pre-unmanage-*"
report_optional_backups "Gemini settings backups" "${HOME}/.gemini/settings.json.pre-unmanage-*"

echo
if [[ "${ATTENTION_COUNT}" -eq 0 ]]; then
  printf '\033[1;32mAI config audit looks good.\033[0m\n'
else
  printf '\033[1;33mAI config audit needs attention: %s item(s).\033[0m\n' "${ATTENTION_COUNT}"
fi
