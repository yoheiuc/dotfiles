#!/usr/bin/env bash

brew_autoupdate_label() {
  printf 'com.github.domt4.homebrew-autoupdate\n'
}

brew_autoupdate_plist_path() {
  printf '%s/Library/LaunchAgents/%s.plist\n' "${HOME}" "$(brew_autoupdate_label)"
}

brew_autoupdate_runner_path() {
  printf '%s/Library/Application Support/com.github.domt4.homebrew-autoupdate/brew_autoupdate\n' "${HOME}"
}

brew_autoupdate_is_loaded() {
  local uid
  uid="$(id -u 2>/dev/null || true)"
  [[ -n "${uid}" ]] || return 1
  launchctl print "gui/${uid}/$(brew_autoupdate_label)" >/dev/null 2>&1
}

brew_autoupdate_interval() {
  local plist_path
  plist_path="$(brew_autoupdate_plist_path)"
  [[ -f "${plist_path}" ]] || return 1
  plutil -extract StartInterval raw -o - "${plist_path}" 2>/dev/null
}

brew_autoupdate_runner_contains() {
  local needle="$1"
  local runner_path
  runner_path="$(brew_autoupdate_runner_path)"
  [[ -f "${runner_path}" ]] || return 1
  grep -Fq -- "${needle}" "${runner_path}"
}

brew_autoupdate_has_sudo_support() {
  brew_autoupdate_runner_contains "SUDO_ASKPASS="
}

brew_autoupdate_pinentry_available() {
  [[ "${BREW_AUTOUPDATE_FORCE_PINENTRY_MISSING:-0}" == "1" ]] && return 1
  command -v pinentry-mac >/dev/null 2>&1
}

brew_autoupdate_mode_summary() {
  if brew_autoupdate_has_sudo_support; then
    printf 'with sudo support\n'
  else
    printf 'without sudo support\n'
  fi
}

brew_autoupdate_matches_dotfiles_baseline() {
  local expected_interval="${1:-3600}"

  brew_autoupdate_is_loaded || return 1
  [[ "$(brew_autoupdate_interval 2>/dev/null || true)" == "${expected_interval}" ]] || return 1
  brew_autoupdate_runner_contains "brew update" || return 1
  brew_autoupdate_runner_contains "brew upgrade --formula" || return 1
  brew_autoupdate_runner_contains "brew upgrade --cask -v --greedy" || return 1
  brew_autoupdate_runner_contains "brew cleanup" || return 1

  if brew_autoupdate_pinentry_available; then
    brew_autoupdate_has_sudo_support || return 1
  fi

  return 0
}
