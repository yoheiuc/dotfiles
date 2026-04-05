#!/usr/bin/env bash
# dashboard.sh — generate a local Markdown dashboard from status and AI audit
#
# Usage:
#   ./scripts/dashboard.sh
#   ./scripts/dashboard.sh /tmp/custom-dashboard.md
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OUTPUT_PATH="${1:-${TMPDIR:-/tmp}/dotfiles-dashboard.md}"
OUTPUT_PATH="$(printf '%s\n' "${OUTPUT_PATH}" | sed 's#//*#/#g')"
OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"

mkdir -p "${OUTPUT_DIR}"

status_raw="$(mktemp "${TMPDIR:-/tmp}/dotfiles-status-raw.XXXXXX")"
audit_raw="$(mktemp "${TMPDIR:-/tmp}/dotfiles-ai-audit-raw.XXXXXX")"
status_txt="$(mktemp "${TMPDIR:-/tmp}/dotfiles-status-clean.XXXXXX")"
audit_txt="$(mktemp "${TMPDIR:-/tmp}/dotfiles-ai-audit-clean.XXXXXX")"
summary_tmp="$(mktemp "${TMPDIR:-/tmp}/dotfiles-dashboard-summary.XXXXXX")"
trap 'rm -f "${status_raw}" "${audit_raw}" "${status_txt}" "${audit_txt}" "${summary_tmp}"' EXIT

strip_ansi_file() {
  sed -E $'s/\x1B\\[[0-9;]*[A-Za-z]//g' "$1" > "$2"
}

markdown_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

collect_highlights() {
  local input_file="$1"
  awk '
    /^Active profile:/ { print "- " $0; next }
    /^[[:space:]]*[✓⚠✗]-?[[:space:]]/ {
      line=$0
      sub(/^[[:space:]]*[✓⚠✗][[:space:]]+/, "", line)
      print "- " line
      next
    }
    /^[[:space:]]*-[[:space:]]/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]+/, "", line)
      print "- " line
    }
  ' "${input_file}"
}

run_and_capture() {
  local output_file="$1"
  shift

  set +e
  "$@" >"${output_file}" 2>&1
  local cmd_status=$?
  set -e
  return "${cmd_status}"
}

status_exit=0
audit_exit=0

if run_and_capture "${status_raw}" bash "${REPO_ROOT}/scripts/status.sh"; then
  status_exit=0
else
  status_exit=$?
fi
if run_and_capture "${audit_raw}" bash "${REPO_ROOT}/scripts/ai-audit.sh"; then
  audit_exit=0
else
  audit_exit=$?
fi

strip_ansi_file "${status_raw}" "${status_txt}"
strip_ansi_file "${audit_raw}" "${audit_txt}"

status_attention="$(grep -c "⚠" "${status_txt}" || true)"
audit_attention="$(grep -c "⚠" "${audit_txt}" || true)"
status_profile="$(grep -m1 '^Active profile:' "${status_txt}" | sed 's/^Active profile: //')"
generated_at="$(date '+%Y-%m-%d %H:%M:%S %Z')"

{
  printf '# Dotfiles Dashboard\n\n'
  printf 'Generated: `%s`\n\n' "${generated_at}"

  printf '## Overview\n\n'
  if [[ -n "${status_profile}" ]]; then
    printf -- '- Active profile: `%s`\n' "${status_profile}"
  fi
  if [[ "${status_attention}" == "0" ]]; then
    printf -- '- Status summary: clean\n'
  else
    printf -- '- Status summary: %s warning(s)\n' "${status_attention}"
  fi
  if [[ "${audit_attention}" == "0" ]]; then
    printf -- '- AI audit summary: clean\n'
  else
    printf -- '- AI audit summary: %s warning(s)\n' "${audit_attention}"
  fi
  printf -- '- Source repo: `%s`\n' "${REPO_ROOT}"
  printf -- '- Output file: `%s`\n' "${OUTPUT_PATH}"
  printf '\n'

  printf '## Status Highlights\n\n'
  if ! collect_highlights "${status_txt}" > "${summary_tmp}" || [[ ! -s "${summary_tmp}" ]]; then
    printf -- '- No status highlights collected.\n'
  else
    cat "${summary_tmp}"
  fi
  printf '\n'

  printf '## AI Highlights\n\n'
  if ! collect_highlights "${audit_txt}" > "${summary_tmp}" || [[ ! -s "${summary_tmp}" ]]; then
    printf -- '- No AI audit highlights collected.\n'
  else
    cat "${summary_tmp}"
  fi
  printf '\n'

  printf '## Raw Status Output\n\n'
  printf '```text\n'
  cat "${status_txt}"
  printf '\n```\n\n'

  printf '## Raw AI Audit Output\n\n'
  printf '```text\n'
  cat "${audit_txt}"
  printf '\n```\n'
} > "${OUTPUT_PATH}"

printf 'Generated Markdown dashboard: %s\n' "${OUTPUT_PATH}"
printf '  status warnings: %s\n' "${status_attention}"
printf '  ai audit warnings: %s\n' "${audit_attention}"
printf '  status exit: %s\n' "${status_exit}"
printf '  ai audit exit: %s\n' "${audit_exit}"
