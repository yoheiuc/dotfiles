#!/usr/bin/env bash
# profile.sh — persist and read the active dotfiles profile for this machine
#
# Usage:
#   ./scripts/profile.sh get
#   ./scripts/profile.sh set home
#   ./scripts/profile.sh exists
#   ./scripts/profile.sh path
set -euo pipefail

PROFILE_FILE="${HOME}/.config/dotfiles/profile"
DEFAULT_PROFILE="core"

die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

canonicalize_profile() {
  case "${1:-}" in
    core|home)
      printf '%s\n' "${1}"
      ;;
    work)
      printf 'core\n'
      ;;
    personal)
      printf 'home\n'
      ;;
    all)
      die "Legacy profile 'all' is no longer supported; choose 'core' or 'home'"
      ;;
    *)
      die "Unsupported profile '${1:-}' (expected: core or home)"
      ;;
  esac
}

validate_profile() {
  canonicalize_profile "${1:-}" >/dev/null
}

get_profile() {
  if [[ -r "${PROFILE_FILE}" ]]; then
    local profile canonical_profile
    profile="$(tr -d '[:space:]' < "${PROFILE_FILE}")"
    if [[ -n "${profile}" ]]; then
      canonical_profile="$(canonicalize_profile "${profile}")"
      if [[ "${canonical_profile}" != "${profile}" ]]; then
        mkdir -p "$(dirname "${PROFILE_FILE}")"
        printf '%s\n' "${canonical_profile}" > "${PROFILE_FILE}"
      fi
      printf '%s\n' "${canonical_profile}"
      return 0
    fi
  fi

  printf '%s\n' "${DEFAULT_PROFILE}"
}

set_profile() {
  local profile canonical_profile
  profile="${1:-}"
  canonical_profile="$(canonicalize_profile "${profile}")"

  mkdir -p "$(dirname "${PROFILE_FILE}")"
  printf '%s\n' "${canonical_profile}" > "${PROFILE_FILE}"
  printf '%s\n' "${canonical_profile}"
}

command_name="${1:-get}"

case "${command_name}" in
  get)
    get_profile
    ;;
  set)
    set_profile "${2:-}"
    ;;
  exists)
    if [[ -r "${PROFILE_FILE}" ]] && [[ -n "$(tr -d '[:space:]' < "${PROFILE_FILE}")" ]]; then
      exit 0
    fi
    exit 1
    ;;
  path)
    printf '%s\n' "${PROFILE_FILE}"
    ;;
  *)
    die "Unsupported command '${command_name}' (expected: get, set, exists, or path)"
    ;;
esac
