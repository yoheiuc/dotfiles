#!/usr/bin/env bash

AI_CONFIG_LEGACY_PATTERN='approval_policy[[:space:]]*=[[:space:]]*"never"|sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"|BEGIN CCB|END CCB|ai-bridge|cc-bridge|codex-dual|\bccb\b'

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
