#!/usr/bin/env bash
# ai-audit.sh — focused audit for local AI client configs and shared guidance
#
# Usage:
#   ./scripts/ai-audit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ai-config.sh"

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
if command -v claude >/dev/null 2>&1; then
  claude_mcp_list_out="$(ai_config_run_with_timeout 15 claude mcp list 2>&1 || true)"
  case "$(ai_config_claude_serena_registration_state "${claude_mcp_list_out}" "${HOME}/.claude.json")" in
    connected)
      ok "Claude Code Serena MCP: connected"
      ;;
    disconnected)
      attention "Claude Code Serena MCP: found but not connected"
      ;;
    registered-timeout)
      ok "Claude Code Serena MCP: registered (interactive health check timed out)"
      ;;
    timeout)
      attention "Claude Code Serena MCP: check timed out"
      ;;
    *)
      attention "Claude Code Serena MCP: missing — run make ai-repair"
      ;;
  esac
else
  info "Claude Code MCP audit skipped: claude is missing"
fi

if command -v codex >/dev/null 2>&1; then
  codex_mcp_list_out="$(ai_config_run_with_timeout 8 codex mcp list 2>&1 | ai_config_strip_codex_path_warning || true)"
  case "$(ai_config_codex_serena_registration_state "${codex_mcp_list_out}" "${HOME}/.local/bin/serena-mcp")" in
    wrapper)
      ok "Codex Serena MCP: wrapper registration detected"
      ;;
    legacy-uvx)
      attention "Codex Serena MCP: legacy uvx registration detected — run make ai-repair, then restart old terminals"
      ;;
    unexpected)
      attention "Codex Serena MCP: unexpected command detected — run make ai-repair"
      ;;
    timeout)
      attention "Codex Serena MCP: check timed out"
      ;;
    *)
      attention "Codex Serena MCP: missing — run make ai-repair"
      ;;
  esac
else
  info "Codex MCP audit skipped: codex is missing"
fi

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
