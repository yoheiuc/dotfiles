#!/usr/bin/env bash
# brew-bundle.sh — manage Homebrew packages from the tracked Brewfile
#
# Modes:
#   sync    install + cleanup (removes packages not in Brewfile)  ← used by make sync
#   install install only, no cleanup                              ← used by bootstrap
#   check   verify all packages are present (non-destructive)     ← used by make doctor
#   preview show what install/cleanup would change                ← used by make preview
#
# Usage:
#   ./scripts/brew-bundle.sh sync
#   ./scripts/brew-bundle.sh install
#   ./scripts/brew-bundle.sh check
#   ./scripts/brew-bundle.sh preview
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="${REPO_ROOT}/home/dot_Brewfile"

MODE="${1:-sync}"

die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }

[[ -f "${BREWFILE}" ]] || die "Missing Brewfile: ${BREWFILE}"

case "${MODE}" in
  sync|install|check|preview) ;;
  *) die "Unsupported mode '${MODE}' (expected: sync, install, check, or preview)" ;;
esac

if [[ "${MODE}" == "sync" ]]; then
  log "Installing packages from Brewfile..."
  brew bundle --file="${BREWFILE}"
  log "Removing packages not declared in Brewfile..."
  brew bundle cleanup --file="${BREWFILE}" --force
elif [[ "${MODE}" == "install" ]]; then
  log "Installing packages from Brewfile (no cleanup)..."
  brew bundle --file="${BREWFILE}"
elif [[ "${MODE}" == "preview" ]]; then
  log "Previewing Brewfile state..."

  printf '  brew bundle check --verbose --no-upgrade:\n'
  set +e
  check_out="$(HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="${BREWFILE}" --verbose --no-upgrade 2>&1)"
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
  cleanup_out="$(HOMEBREW_NO_AUTO_UPDATE=1 brew bundle cleanup --file="${BREWFILE}" 2>&1)"
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
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="${BREWFILE}" --verbose --no-upgrade
fi
