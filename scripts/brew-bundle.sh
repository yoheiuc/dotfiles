#!/usr/bin/env bash
# brew-bundle.sh — manage Homebrew packages for the effective profile
#
# Modes:
#   sync    install + cleanup (removes packages not in profile)  ← used by make install-*
#   install install only, no cleanup                             ← used by make update-*
#   check   verify all packages are present (non-destructive)    ← used by make doctor
#   preview show what install/cleanup would change               ← used by make preview*
#
# Profiles: core | work | personal | all
#
# Usage:
#   ./scripts/brew-bundle.sh sync    core
#   ./scripts/brew-bundle.sh sync    all
#   ./scripts/brew-bundle.sh install personal
#   ./scripts/brew-bundle.sh check   work
#   ./scripts/brew-bundle.sh preview all
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_BREWFILE="${REPO_ROOT}/home/dot_Brewfile.core"
WORK_BREWFILE="${REPO_ROOT}/home/dot_Brewfile.work"
PERSONAL_BREWFILE="${REPO_ROOT}/home/dot_Brewfile.personal"

MODE="${1:-sync}"
PROFILE="${2:-core}"

die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }

[[ -f "${CORE_BREWFILE}" ]] || die "Missing core Brewfile: ${CORE_BREWFILE}"

case "${MODE}" in
  sync|install|check|preview) ;;
  *) die "Unsupported mode '${MODE}' (expected: sync, install, check, or preview)" ;;
esac

case "${PROFILE}" in
  core|work|personal|all) ;;
  *) die "Unsupported profile '${PROFILE}' (expected: core, work, personal, or all)" ;;
esac

effective_brewfile="$(mktemp "${TMPDIR:-/tmp}/dotfiles-brewfile.XXXXXX")"
trap 'rm -f "${effective_brewfile}"' EXIT

cat "${CORE_BREWFILE}" > "${effective_brewfile}"
if [[ "${PROFILE}" == "work" || "${PROFILE}" == "all" ]]; then
  [[ -f "${WORK_BREWFILE}" ]] || die "Missing work Brewfile: ${WORK_BREWFILE}"
  printf '\n' >> "${effective_brewfile}"
  cat "${WORK_BREWFILE}" >> "${effective_brewfile}"
fi
if [[ "${PROFILE}" == "personal" || "${PROFILE}" == "all" ]]; then
  [[ -f "${PERSONAL_BREWFILE}" ]] || die "Missing personal Brewfile: ${PERSONAL_BREWFILE}"
  printf '\n' >> "${effective_brewfile}"
  cat "${PERSONAL_BREWFILE}" >> "${effective_brewfile}"
fi

if [[ "${MODE}" == "sync" ]]; then
  log "Installing packages for '${PROFILE}' profile..."
  brew bundle --file="${effective_brewfile}"
  log "Removing packages not declared in '${PROFILE}' profile..."
  brew bundle cleanup --file="${effective_brewfile}" --force
elif [[ "${MODE}" == "install" ]]; then
  log "Installing packages for '${PROFILE}' profile (no cleanup)..."
  brew bundle --file="${effective_brewfile}"
elif [[ "${MODE}" == "preview" ]]; then
  log "Previewing packages for '${PROFILE}' profile..."

  printf '  brew bundle check --verbose --no-upgrade:\n'
  set +e
  check_out="$(brew bundle check --file="${effective_brewfile}" --verbose --no-upgrade 2>&1)"
  check_status=$?
  set -e

  if [[ -n "${check_out}" ]]; then
    printf '%s\n' "${check_out}" | sed 's/^/    /'
  fi

  if [[ ${check_status} -eq 0 ]]; then
    printf '    All declared dependencies are already installed.\n'
  elif [[ ${check_status} -eq 1 ]]; then
    printf '    Missing dependencies are listed above.\n'
  else
    exit "${check_status}"
  fi

  printf '\n  brew bundle cleanup (preview only):\n'
  set +e
  cleanup_out="$(brew bundle cleanup --file="${effective_brewfile}" 2>&1)"
  cleanup_status=$?
  set -e

  if [[ ${cleanup_status} -eq 0 ]]; then
    printf '    No packages would be removed.\n'
  elif [[ ${cleanup_status} -eq 1 ]]; then
    printf '%s\n' "${cleanup_out}" | sed 's/^/    /'
  else
    printf '%s\n' "${cleanup_out}" | sed 's/^/    /' >&2
    exit "${cleanup_status}"
  fi
else
  brew bundle check --file="${effective_brewfile}"
fi
