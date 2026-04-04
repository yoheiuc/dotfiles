#!/usr/bin/env bash
# brew-diff.sh — compare tracked Brew entries with local Homebrew state
#
# Usage:
#   ./scripts/brew-diff.sh
#   ./scripts/brew-diff.sh core
#   ./scripts/brew-diff.sh home
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CORE_BREWFILE="${REPO_ROOT}/home/dot_Brewfile.core"
HOME_BREWFILE="${REPO_ROOT}/home/dot_Brewfile.home"
DEFAULT_PROFILE="$(bash "${REPO_ROOT}/scripts/profile.sh" get)"
PROFILE="${1:-${DEFAULT_PROFILE}}"

die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
ok() { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }

case "${PROFILE}" in
  core|home) ;;
  *) die "Unsupported profile '${PROFILE}' (expected: core or home)" ;;
esac

extract_entries() {
  local kind="$1"
  local file="$2"

  case "${kind}" in
    brew)
      sed -nE 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' "${file}"
      ;;
    cask)
      sed -nE 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' "${file}"
      ;;
    tap)
      sed -nE 's/^[[:space:]]*tap[[:space:]]+"([^"]+)".*/\1/p' "${file}"
      ;;
    *)
      return 1
      ;;
  esac
}

declared_entries() {
  local kind="$1"

  extract_entries "${kind}" "${CORE_BREWFILE}"
  if [[ "${PROFILE}" == "home" ]]; then
    extract_entries "${kind}" "${HOME_BREWFILE}"
  fi
}

installed_entries() {
  local kind="$1"

  case "${kind}" in
    brew)
      brew leaves | sort -u
      ;;
    cask)
      brew list --cask | sort -u
      ;;
    tap)
      brew tap | sort -u
      ;;
    *)
      return 1
      ;;
  esac
}

report_kind_diff() {
  local kind="$1"
  local label="$2"
  local declared installed missing extra

  declared="$(declared_entries "${kind}" | sed '/^$/d' | sort -u)"
  installed="$(installed_entries "${kind}" | sed '/^$/d' | sort -u)"

  missing="$(comm -23 <(printf '%s\n' "${declared}") <(printf '%s\n' "${installed}"))"
  extra="$(comm -13 <(printf '%s\n' "${declared}") <(printf '%s\n' "${installed}"))"

  section "${label}"
  if [[ -n "${missing}" ]]; then
    printf '  Missing locally but declared:\n'
    printf '%s\n' "${missing}" | sed 's/^/    /'
    DIFF_FOUND=1
  else
    ok "No missing declared ${label}"
  fi

  if [[ -n "${extra}" ]]; then
    printf '  Installed locally but not tracked:\n'
    printf '%s\n' "${extra}" | sed 's/^/    /'
    DIFF_FOUND=1
  else
    ok "No untracked local ${label}"
  fi
}

DIFF_FOUND=0

printf '\033[1m=== brew diff (%s) ===\033[0m\n' "${PROFILE}"
printf "Formulae use \`brew leaves\`, so only top-level local installs are reported.\n"

report_kind_diff brew "formulae"
report_kind_diff cask "casks"
report_kind_diff tap "taps"

echo
if [[ "${DIFF_FOUND}" -eq 0 ]]; then
  printf '\033[1;32mNo Brew tracking diff.\033[0m\n'
  exit 0
fi

printf '\033[1;33mBrew tracking diff detected.\033[0m\n'
printf 'Add tracked entries with: make brew-add-core KIND=brew|cask|tap NAME=<name>\n'
printf '                        or make brew-add-home KIND=brew|cask|tap NAME=<name>\n'
exit 1
