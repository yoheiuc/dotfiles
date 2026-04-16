#!/usr/bin/env bash
# brew-add.sh — record a locally-installed Homebrew package in a tracked Brewfile
#
# Usage:
#   ./scripts/brew-add.sh core brew jq
#   ./scripts/brew-add.sh home cask google-chrome
#   ./scripts/brew-add.sh core tap domt4/autoupdate
set -euo pipefail

REPO_ROOT="${DOTFILES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CORE_BREWFILE="${REPO_ROOT}/home/dot_Brewfile.core"
HOME_BREWFILE="${REPO_ROOT}/home/dot_Brewfile.home"

PROFILE="${1:-}"
KIND="${2:-}"
NAME="${3:-}"

die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
ok() { printf '\033[1;32m✓\033[0m  %s\n' "$*"; }

case "${PROFILE}" in
  core) TARGET_BREWFILE="${CORE_BREWFILE}" ; OTHER_BREWFILE="${HOME_BREWFILE}" ;;
  home) TARGET_BREWFILE="${HOME_BREWFILE}" ; OTHER_BREWFILE="${CORE_BREWFILE}" ;;
  *) die "Unsupported profile '${PROFILE:-}' (expected: core or home)" ;;
esac

case "${KIND}" in
  brew|cask|tap) ;;
  *) die "Unsupported kind '${KIND:-}' (expected: brew, cask, or tap)" ;;
esac

[[ -n "${NAME}" ]] || die "Package name is required"

ensure_locally_installed() {
  case "${KIND}" in
    brew)
      brew list --formula "${NAME}" >/dev/null 2>&1 \
        || die "'${NAME}' is not installed locally as a formula"
      ;;
    cask)
      brew list --cask "${NAME}" >/dev/null 2>&1 \
        || die "'${NAME}' is not installed locally as a cask"
      ;;
    tap)
      brew tap | grep -Fxq "${NAME}" \
        || die "'${NAME}' is not installed locally as a tap"
      ;;
  esac
}

entry_pattern() {
  printf '^[[:space:]]*%s[[:space:]]+"%s"([[:space:]]*,.*)?$' "${KIND}" "${NAME}"
}

insert_before_line() {
  local file="$1"
  local line_number="$2"
  local entry="$3"
  local tmp_file

  tmp_file="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brew-add.XXXXXX")"
  awk -v line="${line_number}" -v entry="${entry}" '
    NR == line { print entry }
    { print }
    END {
      if (line == 0 || line > NR) {
        if (NR > 0) {
          print entry
        } else {
          printf "%s\n", entry
        }
      }
    }
  ' "${file}" > "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

insert_entry() {
  local entry
  local line_number=""
  entry="${KIND} \"${NAME}\""

  case "${KIND}" in
    tap)
      line_number="$(grep -nE '^[[:space:]]*tap[[:space:]]+"' "${TARGET_BREWFILE}" | tail -1 | cut -d: -f1 || true)"
      if [[ -n "${line_number}" ]]; then
        insert_before_line "${TARGET_BREWFILE}" "$((line_number + 1))" "${entry}"
      else
        line_number="$(grep -nE '^[[:space:]]*(brew|cask)[[:space:]]+"' "${TARGET_BREWFILE}" | head -1 | cut -d: -f1 || true)"
        if [[ -n "${line_number}" ]]; then
          insert_before_line "${TARGET_BREWFILE}" "${line_number}" "${entry}"
        else
          insert_before_line "${TARGET_BREWFILE}" 0 "${entry}"
        fi
      fi
      ;;
    brew)
      line_number="$(grep -nE '^[[:space:]]*cask[[:space:]]+"' "${TARGET_BREWFILE}" | head -1 | cut -d: -f1 || true)"
      if [[ -n "${line_number}" ]]; then
        insert_before_line "${TARGET_BREWFILE}" "${line_number}" "${entry}"
      else
        insert_before_line "${TARGET_BREWFILE}" 0 "${entry}"
      fi
      ;;
    cask)
      insert_before_line "${TARGET_BREWFILE}" 0 "${entry}"
      ;;
  esac
}

ensure_locally_installed

if grep -Eq "$(entry_pattern)" "${TARGET_BREWFILE}"; then
  die "'${NAME}' is already declared in $(basename "${TARGET_BREWFILE}")"
fi

if grep -Eq "$(entry_pattern)" "${OTHER_BREWFILE}"; then
  die "'${NAME}' is already declared in $(basename "${OTHER_BREWFILE}")"
fi

insert_entry
ok "Added ${KIND} '${NAME}' to $(basename "${TARGET_BREWFILE}")"
