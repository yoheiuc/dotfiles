#!/usr/bin/env bash
# dashboard.sh — generate a local Markdown dashboard from status and AI audit
#
# Usage:
#   ./scripts/dashboard.sh
#   ./scripts/dashboard.sh /tmp/custom-dashboard.md
#   OUTPUT=docs/last-dashboard.md ./scripts/dashboard.sh --open
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OUTPUT_PATH="${OUTPUT:-}"
OPEN_AFTER_GENERATE="${OPEN_DASHBOARD:-0}"
POSITIONAL_OUTPUT=""

for arg in "$@"; do
  case "${arg}" in
    --open)
      OPEN_AFTER_GENERATE=1
      ;;
    *)
      if [[ -z "${POSITIONAL_OUTPUT}" ]]; then
        POSITIONAL_OUTPUT="${arg}"
      else
        printf 'ERROR: unexpected argument: %s\n' "${arg}" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "${OUTPUT_PATH}" ]]; then
  OUTPUT_PATH="${POSITIONAL_OUTPUT:-${TMPDIR:-/tmp}/dotfiles-dashboard.md}"
fi
OUTPUT_PATH="$(printf '%s\n' "${OUTPUT_PATH}" | sed 's#//*#/#g')"
OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"

mkdir -p "${OUTPUT_DIR}"

status_raw="$(mktemp "${TMPDIR:-/tmp}/dotfiles-status-raw.XXXXXX")"
audit_raw="$(mktemp "${TMPDIR:-/tmp}/dotfiles-ai-audit-raw.XXXXXX")"
status_txt="$(mktemp "${TMPDIR:-/tmp}/dotfiles-status-clean.XXXXXX")"
audit_txt="$(mktemp "${TMPDIR:-/tmp}/dotfiles-ai-audit-clean.XXXXXX")"
prev_status_txt="$(mktemp "${TMPDIR:-/tmp}/dotfiles-prev-status-clean.XXXXXX")"
prev_audit_txt="$(mktemp "${TMPDIR:-/tmp}/dotfiles-prev-ai-audit-clean.XXXXXX")"
summary_tmp="$(mktemp "${TMPDIR:-/tmp}/dotfiles-dashboard-summary.XXXXXX")"
diff_tmp="$(mktemp "${TMPDIR:-/tmp}/dotfiles-dashboard-diff.XXXXXX")"
trap 'rm -f "${status_raw}" "${audit_raw}" "${status_txt}" "${audit_txt}" "${prev_status_txt}" "${prev_audit_txt}" "${summary_tmp}" "${diff_tmp}"' EXIT

strip_ansi_file() {
  sed -E $'s/\x1B\\[[0-9;]*[A-Za-z]//g' "$1" > "$2"
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

extract_previous_raw_block() {
  local input_file="$1"
  local heading="$2"
  local output_file="$3"

  awk -v heading="${heading}" '
    $0 == heading { in_heading=1; next }
    in_heading && /^```text$/ { in_block=1; next }
    in_block && /^```$/ { exit }
    in_block { print }
  ' "${input_file}" > "${output_file}"
}

render_diff_summary() {
  local label="$1"
  local previous_file="$2"
  local current_file="$3"

  if [[ ! -s "${previous_file}" ]]; then
    printf -- '- %s: no previous snapshot\n' "${label}"
    return 0
  fi

  if cmp -s "${previous_file}" "${current_file}"; then
    printf -- '- %s: unchanged\n' "${label}"
    return 0
  fi

  printf -- '- %s: changed\n' "${label}"
  set +e
  diff -u "${previous_file}" "${current_file}" > "${diff_tmp}"
  set -e
  printf '\n```diff\n'
  sed -n '1,80p' "${diff_tmp}"
  printf '\n```\n\n'
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
had_previous_dashboard=0

if [[ -f "${OUTPUT_PATH}" ]]; then
  had_previous_dashboard=1
  extract_previous_raw_block "${OUTPUT_PATH}" "## Raw Status Output" "${prev_status_txt}"
  extract_previous_raw_block "${OUTPUT_PATH}" "## Raw AI Audit Output" "${prev_audit_txt}"
fi

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

  printf '## Since Last Dashboard\n\n'
  if [[ "${had_previous_dashboard}" -eq 1 ]]; then
    printf -- '- Previous dashboard: found at `%s`\n' "${OUTPUT_PATH}"
  else
    printf -- '- Previous dashboard: none\n'
  fi
  render_diff_summary "Status output" "${prev_status_txt}" "${status_txt}"
  render_diff_summary "AI audit output" "${prev_audit_txt}" "${audit_txt}"

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

if [[ "${OPEN_AFTER_GENERATE}" == "1" ]]; then
  if command -v open >/dev/null 2>&1; then
    open "${OUTPUT_PATH}"
    printf 'Opened dashboard: %s\n' "${OUTPUT_PATH}"
  else
    printf 'WARNING: open command not found, dashboard not opened.\n' >&2
  fi
fi
