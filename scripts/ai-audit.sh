#!/usr/bin/env bash
# ai-audit.sh — focused audit for local AI client configs and shared guidance
#
# Usage:
#   ./scripts/ai-audit.sh
set -euo pipefail

ATTENTION_COUNT=0

section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
ok() { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
info() { printf '  - %s\n' "$*"; }
attention() {
  warn "$*"
  ATTENTION_COUNT=$((ATTENTION_COUNT + 1))
}

file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

describe_file() {
  local label="$1"
  local path="$2"

  if [[ -f "${path}" ]]; then
    info "${label}: present (${path}, $(file_size_bytes "${path}") bytes)"
  else
    attention "${label}: missing (${path})"
  fi
}

scan_file_for_legacy_patterns() {
  local label="$1"
  local path="$2"
  local pattern="$3"

  if [[ ! -f "${path}" ]]; then
    return 0
  fi

  if grep -Eq "${pattern}" "${path}"; then
    attention "${label}: legacy bridge or unsafe approval settings detected"
  else
    ok "${label}: no legacy bridge settings detected"
  fi
}

report_optional_backups() {
  local label="$1"
  local glob_pattern="$2"
  local matches=()

  # shellcheck disable=SC2206
  matches=(${glob_pattern})
  if (( ${#matches[@]} == 0 )) || [[ "${matches[0]}" == "${glob_pattern}" ]]; then
    ok "${label}: none found"
    return 0
  fi

  attention "${label}: found backup files to review or delete"
  printf '%s\n' "${matches[@]}" | sed 's/^/    /'
}

echo
printf '\033[1m=== AI config audit ===\033[0m\n'

section "Local Config Files"
describe_file "Codex config" "${HOME}/.codex/config.toml"
describe_file "Claude settings" "${HOME}/.claude/settings.json"
describe_file "Gemini settings" "${HOME}/.gemini/settings.json"

section "Shared Guidance"
describe_file "Codex hooks" "${HOME}/.codex/hooks.json"
describe_file "Claude guidance" "${HOME}/.claude/CLAUDE.md"
describe_file "AGENTS" "${HOME}/AGENTS.md"

section "Legacy Pattern Scan"
legacy_pattern='approval_policy[[:space:]]*=[[:space:]]*"never"|sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"|BEGIN CCB|END CCB|ai-bridge|cc-bridge|codex-dual|\bccb\b'
scan_file_for_legacy_patterns "Codex config" "${HOME}/.codex/config.toml" "${legacy_pattern}"
scan_file_for_legacy_patterns "Claude settings" "${HOME}/.claude/settings.json" "${legacy_pattern}"
scan_file_for_legacy_patterns "Gemini settings" "${HOME}/.gemini/settings.json" "${legacy_pattern}"
scan_file_for_legacy_patterns "Codex hooks" "${HOME}/.codex/hooks.json" "${legacy_pattern}"
scan_file_for_legacy_patterns "Claude guidance" "${HOME}/.claude/CLAUDE.md" "${legacy_pattern}"
scan_file_for_legacy_patterns "AGENTS" "${HOME}/AGENTS.md" "${legacy_pattern}"

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
