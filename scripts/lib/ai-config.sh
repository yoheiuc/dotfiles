#!/usr/bin/env bash
# scripts/lib/ai-config.sh — shell helpers for local AI config inspection.
#
# All JSON / TOML mutation is delegated to scripts/lib/ai_config.py, which
# writes via tempfile + os.replace so crashes cannot corrupt ~/.claude.json or
# ~/.codex/config.toml mid-write.

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

# Resolve a Python 3.11+ interpreter that has `tomllib` in its stdlib. macOS
# ships /usr/bin/python3 as 3.9 which lacks tomllib, so fall back to
# homebrew-installed pythons when the default is too old. Cached per shell.
ai_config_python_with_tomllib() {
  if [[ -n "${_AI_CONFIG_PY_TOMLLIB:-}" ]]; then
    printf '%s\n' "${_AI_CONFIG_PY_TOMLLIB}"
    return 0
  fi
  local candidate
  for candidate in python3 python3.14 python3.13 python3.12 python3.11; do
    if command -v "${candidate}" >/dev/null 2>&1 \
       && "${candidate}" -c 'import tomllib' 2>/dev/null; then
      _AI_CONFIG_PY_TOMLLIB="${candidate}"
      printf '%s\n' "${_AI_CONFIG_PY_TOMLLIB}"
      return 0
    fi
  done
  _AI_CONFIG_PY_TOMLLIB="python3"
  printf '%s\n' "${_AI_CONFIG_PY_TOMLLIB}"
  return 1
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

# Read a field from a TOML file. Requires tomllib (Python 3.11+).
# Usage: ai_config_toml_read <file> <python_expr>   (expr receives parsed TOML as `d`)
ai_config_toml_read() {
  local py
  py="$(ai_config_python_with_tomllib)" || true
  "${py}" "${_AI_CONFIG_PY}" toml-read "$1" "$2"
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

ai_config_toml_remove_mcp_section() {
  python3 "${_AI_CONFIG_PY}" toml-remove-mcp-section "$1" "$2"
}

ai_config_toml_upsert_top_level() {
  python3 "${_AI_CONFIG_PY}" toml-upsert-top-level "$1" "$2" "$3"
}

ai_config_toml_upsert_section_block() {
  python3 "${_AI_CONFIG_PY}" toml-upsert-section-block "$1" "$2" "$3"
}

ai_config_codex_upsert_mcp() {
  python3 "${_AI_CONFIG_PY}" codex-upsert-mcp "$1" "$2" "$3" "$4"
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

# Check Codex serena MCP state in config.toml.
ai_config_codex_mcp_state() {
  local file="$1"
  local expected_command="$2"

  local actual_command
  actual_command="$(ai_config_toml_read "${file}" "d.get('mcp_servers',{}).get('serena',{}).get('command','')" 2>/dev/null)" || { printf 'missing\n'; return; }

  if [[ "${actual_command}" == "${expected_command}" ]]; then
    printf 'ok\n'
  else
    printf 'wrong-command\n'
  fi
}

ai_config_codex_mcp_url_state() {
  local file="$1"
  local server_name="$2"
  local expected_url="$3"

  local actual_url
  actual_url="$(ai_config_toml_read "${file}" "d.get('mcp_servers',{}).get('${server_name}',{}).get('url','')" 2>/dev/null)" || { printf 'missing\n'; return; }

  if [[ "${actual_url}" == "${expected_url}" ]]; then
    printf 'ok\n'
  else
    printf 'wrong-url\n'
  fi
}

# ---- Keychain / legacy env credential helpers --------------------------------

ai_config_read_keychain_secret() {
  local account="$1"
  local security_bin="${SECURITY_BIN:-security}"
  local service="${KEYCHAIN_SERVICE:-dotfiles.ai.mcp}"

  if ! command -v "${security_bin}" >/dev/null 2>&1; then
    printf ''
    return 0
  fi
  "${security_bin}" find-generic-password -w -s "${service}" -a "${account}" 2>/dev/null || true
}

ai_config_read_legacy_env_secret() {
  local env_name="$1"
  local env_file="${AI_SHARED_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/ai-secrets.env}"
  local fallback="${AI_SHARED_ENV_FALLBACK_FILE:-${HOME}/.config/dotfiles/ai-secrets.env}"

  if [[ ! -f "${env_file}" && "${fallback}" != "${env_file}" && -f "${fallback}" ]]; then
    env_file="${fallback}"
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

ai_config_resolve_secret() {
  local env_name="$1"
  local account="$2"
  local secret=""

  secret="$(ai_config_read_keychain_secret "${account}")"
  if [[ -z "${secret}" ]]; then
    secret="$(ai_config_read_legacy_env_secret "${env_name}")"
  fi
  printf '%s' "${secret}"
}
