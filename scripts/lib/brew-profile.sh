#!/usr/bin/env bash

brew_profile_extract_entries() {
  local kind="$1"
  local file="$2"

  [[ -f "${file}" ]] || return 0

  case "${kind}" in
    formula)
      sed -nE 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' "${file}" | sort -u
      ;;
    cask)
      sed -nE 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' "${file}" | sort -u
      ;;
    *)
      return 1
      ;;
  esac
}

brew_profile_forbidden_entries() {
  local active_profile="$1"
  local repo_root="$2"
  local kind="$3"
  local home_entries

  [[ "${active_profile}" == "core" ]] || return 1

  home_entries="$(brew_profile_extract_entries "${kind}" "${repo_root}/home/dot_Brewfile.home")"
  [[ -n "${home_entries}" ]] || return 1
  printf '%s\n' "${home_entries}" | sed '/^$/d' | sort -u
}

brew_profile_installed_entries() {
  local kind="$1"

  case "${kind}" in
    formula)
      brew list --formula | sort -u
      ;;
    cask)
      brew list --cask | sort -u
      ;;
    *)
      return 1
      ;;
  esac
}

brew_profile_drift_entries() {
  local active_profile="$1"
  local repo_root="$2"
  local kind="$3"
  local forbidden installed unexpected

  forbidden="$(brew_profile_forbidden_entries "${active_profile}" "${repo_root}" "${kind}" || true)"
  [[ -n "${forbidden}" ]] || return 1

  installed="$(brew_profile_installed_entries "${kind}" || true)"
  unexpected="$(comm -12 <(printf '%s\n' "${forbidden}" | sort -u) <(printf '%s\n' "${installed}" | sort -u))"

  [[ -n "${unexpected}" ]] || return 1
  printf '%s\n' "${unexpected}"
}
