#!/usr/bin/env bash
# ai-secrets.sh — interactively collect local AI credentials without shell history
#
# Usage:
#   ./scripts/ai-secrets.sh
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SECURITY_BIN="${SECURITY_BIN:-security}"
AI_SHARED_ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
AI_SHARED_ENV_FILE="${AI_SHARED_ENV_DIR}/ai-secrets.env"
KEYCHAIN_SERVICE="dotfiles.ai.mcp"
GITHUB_KEYCHAIN_ACCOUNT="github-personal-access-token"
BRAVE_KEYCHAIN_ACCOUNT="brave-api-key"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
ok() { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
die() { printf '  \033[1;31m✗\033[0m  %s\n' "$*" >&2; exit 1; }

read_legacy_env_secret() {
  local env_name="$1"

  if [[ ! -f "${AI_SHARED_ENV_FILE}" ]]; then
    printf ''
    return 0
  fi

  env -i bash -lc "
    set -a
    source '${AI_SHARED_ENV_FILE}'
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

write_keychain_secret() {
  local account="$1"
  local secret="$2"

  if ! command -v "${SECURITY_BIN}" >/dev/null 2>&1; then
    die "security command not found"
  fi

  if [[ -n "${secret}" ]]; then
    "${SECURITY_BIN}" add-generic-password -U -s "${KEYCHAIN_SERVICE}" -a "${account}" -w "${secret}" >/dev/null
  else
    "${SECURITY_BIN}" delete-generic-password -s "${KEYCHAIN_SERVICE}" -a "${account}" >/dev/null 2>&1 || true
  fi
}

prompt_secret() {
  local label="$1"
  local current_value="$2"
  local response=""

  if [[ -n "${current_value}" ]]; then
    printf '%s [Enterで現状維持 / - で削除]: ' "${label}" >&2
  else
    printf '%s [空欄で未設定のまま]: ' "${label}" >&2
  fi

  if [[ -t 0 ]]; then
    read -r -s response
    printf '\n' >&2
  else
    read -r response
  fi

  if [[ -z "${response}" ]]; then
    printf '%s' "${current_value}"
  elif [[ "${response}" == "-" ]]; then
    printf ''
  else
    if [[ "${response}" == *$'\n'* || "${response}" == *$'\r'* ]]; then
      die "${label} に改行は使えません"
    fi
    printf '%s' "${response}"
  fi
}

remove_legacy_env_file() {
  if [[ -f "${AI_SHARED_ENV_FILE}" ]]; then
    rm -f "${AI_SHARED_ENV_FILE}"
    ok "Removed legacy plaintext file ${AI_SHARED_ENV_FILE}"
  fi
}

main() {
  local github_current=""
  local github_next=""
  local brave_current=""
  local brave_next=""

  github_current="$(read_keychain_secret "${GITHUB_KEYCHAIN_ACCOUNT}")"
  if [[ -z "${github_current}" ]]; then
    github_current="$(read_legacy_env_secret "GITHUB_PERSONAL_ACCESS_TOKEN")"
  fi

  brave_current="$(read_keychain_secret "${BRAVE_KEYCHAIN_ACCOUNT}")"
  if [[ -z "${brave_current}" ]]; then
    brave_current="$(read_legacy_env_secret "BRAVE_API_KEY")"
  fi

  echo
  printf '\033[1m=== AI shared secrets ===\033[0m\n'
  printf 'Claude Code / Codex 共通で使う credential を macOS Keychain に保存します。\n'
  printf '入力は表示されず、shell history にも残りません。\n\n'

  github_next="$(prompt_secret 'GitHub Personal Access Token' "${github_current}")"
  brave_next="$(prompt_secret 'Brave Search API Key' "${brave_current}")"

  log "Writing AI secrets to macOS Keychain..."
  write_keychain_secret "${GITHUB_KEYCHAIN_ACCOUNT}" "${github_next}"
  ok "Saved GitHub credential to Keychain service ${KEYCHAIN_SERVICE}"
  write_keychain_secret "${BRAVE_KEYCHAIN_ACCOUNT}" "${brave_next}"
  ok "Saved Brave API key to Keychain service ${KEYCHAIN_SERVICE}"
  remove_legacy_env_file

  log "Refreshing Claude Code / Codex MCP config..."
  bash "${REPO_ROOT}/scripts/ai-repair.sh"
}

main "$@"
