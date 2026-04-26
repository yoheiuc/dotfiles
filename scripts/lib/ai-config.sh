#!/usr/bin/env bash
# scripts/lib/ai-config.sh — shell helpers for local AI config inspection.
#
# All JSON mutation is delegated to scripts/lib/ai_config.py, which writes via
# tempfile + os.replace so crashes cannot corrupt ~/.claude.json mid-write.

AI_CONFIG_LEGACY_PATTERN='approval_policy[[:space:]]*=[[:space:]]*"never"|sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"|BEGIN CCB|END CCB|ai-bridge|cc-bridge|codex-dual|\bccb\b'

_AI_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AI_CONFIG_PY="${_AI_CONFIG_LIB_DIR}/ai_config.py"

ai_config_file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

ai_config_describe_file() {
  local label="$1"
  local path="$2"
  local include_size="${3:-0}"

  if [[ -f "${path}" ]]; then
    if [[ "${include_size}" == "1" ]]; then
      printf '%s: present (%s, %s bytes)\n' "${label}" "${path}" "$(ai_config_file_size_bytes "${path}")"
    else
      printf '%s: present (%s)\n' "${label}" "${path}"
    fi
  else
    printf '%s: missing (%s)\n' "${label}" "${path}"
  fi
}

ai_config_has_legacy_settings() {
  local path="$1"
  local pattern="${2:-${AI_CONFIG_LEGACY_PATTERN}}"

  [[ -f "${path}" ]] || return 1
  grep -Eq "${pattern}" "${path}"
}

ai_config_file_contains_regex() {
  local path="$1"
  local pattern="$2"

  [[ -f "${path}" ]] || return 1
  grep -Eq "${pattern}" "${path}"
}

ai_config_backup_matches() {
  local glob_pattern="$1"
  compgen -G "${glob_pattern}" || true
}

# Read a field from a JSON file.
# Usage: ai_config_json_read <file> <python_expr>   (expr receives parsed JSON as `d`)
ai_config_json_read() {
  python3 "${_AI_CONFIG_PY}" json-read "$1" "$2"
}

ai_config_json_upsert_mcp() {
  python3 "${_AI_CONFIG_PY}" json-upsert-mcp "$1" "$2" "$3"
}

ai_config_json_remove_mcp() {
  python3 "${_AI_CONFIG_PY}" json-remove-mcp "$1" "$2"
}

ai_config_json_upsert_key() {
  python3 "${_AI_CONFIG_PY}" json-upsert-key "$1" "$2" "$3"
}

ai_config_json_upsert_nested_key() {
  python3 "${_AI_CONFIG_PY}" json-upsert-nested-key "$1" "$2" "$3"
}

# Check MCP registration state in a JSON file.
# Usage: ai_config_mcp_registration_state <file> <server_name> <expected_command>
# Prints one of: ok, wrong-command, missing
ai_config_mcp_registration_state() {
  local file="$1"
  local name="$2"
  local expected_command="$3"

  local actual_command
  if actual_command="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('command','')")"; then
    if [[ "${actual_command}" == "${expected_command}" ]]; then
      printf 'ok\n'
    else
      printf 'wrong-command\n'
    fi
  else
    printf 'missing\n'
  fi
}

