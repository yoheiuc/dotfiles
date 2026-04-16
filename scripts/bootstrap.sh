#!/usr/bin/env bash
# bootstrap.sh — minimal machine provisioning
#
# Responsibility (nothing more):
#   1. Verify Homebrew is present
#   2. Install chezmoi if missing
#   3. Pre-install uv + Python 3.12 (gcloud corporate proxy workaround)
#   4. Install core Brew packages (no cleanup — won't remove home packages)
#   5. Persist the active machine profile
#   6. Apply dotfiles via chezmoi
#
# Called automatically by: make install / install-home
#
# Usage: ./scripts/bootstrap.sh [core|home]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-core}"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

case "${PROFILE}" in
  core|home) ;;
  work) PROFILE="core" ;;
  *) die "Unsupported profile '${PROFILE}' (expected: core or home)" ;;
esac

# ---- 0. Xcode Command Line Tools -------------------------------------------
if ! xcode-select -p &>/dev/null; then
  log "Xcode Command Line Tools not found. Starting installation..."
  xcode-select --install
  printf 'Waiting for CLT installation to finish... (Press any key when done)\n'
  read -n 1 -s -r
  if ! xcode-select -p &>/dev/null; then
    die "CLT installation not detected. Please install and try again."
  fi
fi

# ---- 1. Homebrew -----------------------------------------------------------
command -v brew &>/dev/null \
  || die "Homebrew not found. Install: https://brew.sh"

# ---- 2. chezmoi (bootstrap dependency — install before brew bundle) --------
if ! command -v chezmoi &>/dev/null; then
  log "Installing chezmoi..."
  brew install chezmoi
fi

# ---- 3. Python 3.12 for gcloud (corporate proxy workaround) ---------------
# gcloud-cli cask bundles Python 3.13+ which enables VERIFY_X509_STRICT.
# Corporate CASB/proxies (Netskope, Zscaler, etc.) use MITM certificates
# that lack RFC 5280 compliance, causing SSL errors during cask postflight.
# Pre-install Python 3.12 via uv so CLOUDSDK_PYTHON is set before brew bundle.
if ! command -v uv &>/dev/null; then
  log "Installing uv (needed for Python 3.12 management)..."
  brew install uv
fi
if ! uv python find 3.12 &>/dev/null 2>&1; then
  log "Installing Python 3.12 via uv (gcloud proxy workaround)..."
  uv python install 3.12
fi
export CLOUDSDK_PYTHON="$(uv python find 3.12 2>/dev/null)"
if [[ -n "${CLOUDSDK_PYTHON}" ]]; then
  log "CLOUDSDK_PYTHON=${CLOUDSDK_PYTHON}"
fi

# ---- 4. Homebrew packages (install core profile, no cleanup) ---------------
# Cleanup is intentionally skipped here so that home packages
# installed by broader profiles are not removed when bootstrap re-runs.
# Cleanup happens only when explicitly running brew-bundle.sh sync <profile>.
log "Installing packages for 'core' profile..."
brew bundle --file="${REPO_ROOT}/home/dot_Brewfile.core"

# ---- 5. Persist active profile ---------------------------------------------
if [[ "${PROFILE}" == "core" ]]; then
  if bash "${REPO_ROOT}/scripts/profile.sh" exists; then
    ACTIVE_PROFILE="$(bash "${REPO_ROOT}/scripts/profile.sh" get)"
    log "Keeping existing dotfiles profile '${ACTIVE_PROFILE}'..."
  else
    log "Setting active dotfiles profile to 'core'..."
    ACTIVE_PROFILE="$(bash "${REPO_ROOT}/scripts/profile.sh" set core)"
  fi
else
  log "Setting active dotfiles profile to '${PROFILE}'..."
  ACTIVE_PROFILE="$(bash "${REPO_ROOT}/scripts/profile.sh" set "${PROFILE}")"
fi

# ---- 6. Point chezmoi at this repo and apply dotfiles ----------------------
# Keep a single source of truth for day-to-day edits:
#   ~/.local/share/chezmoi -> ~/dotfiles
# .chezmoiroot tells chezmoi the actual source is home/ inside that repo.
CHEZMOI_LINK="${HOME}/.local/share/chezmoi"
mkdir -p "$(dirname "${CHEZMOI_LINK}")"

if [ -L "${CHEZMOI_LINK}" ]; then
  current_target="$(readlink "${CHEZMOI_LINK}")"
  if [ "${current_target}" != "${REPO_ROOT}" ]; then
    log "Repointing existing chezmoi symlink..."
    rm "${CHEZMOI_LINK}"
    ln -s "${REPO_ROOT}" "${CHEZMOI_LINK}"
  fi
elif [ -e "${CHEZMOI_LINK}" ]; then
  backup_path="${CHEZMOI_LINK}.backup.$(date +%Y%m%d-%H%M%S)"
  log "Backing up existing chezmoi source to ${backup_path}..."
  mv "${CHEZMOI_LINK}" "${backup_path}"
  ln -s "${REPO_ROOT}" "${CHEZMOI_LINK}"
else
  log "Linking chezmoi source to this repo..."
  ln -s "${REPO_ROOT}" "${CHEZMOI_LINK}"
fi

log "Applying dotfiles..."
chezmoi apply

log "Bootstrap complete."
printf '\nNext:\n'
printf '  • Active profile: %s\n' "${ACTIVE_PROFILE}"
printf '  • Open a new terminal to load zsh config\n'
printf '  • Optional: make install-home       (add home apps)\n'
printf '  • Run:      make doctor             (verify setup)\n'
