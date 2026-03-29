#!/usr/bin/env bash
# bootstrap.sh — minimal machine provisioning
#
# Responsibility (nothing more):
#   1. Verify Homebrew is present
#   2. Install chezmoi if missing
#   3. Enforce Homebrew packages to match the core Brew profile strictly
#   4. Apply dotfiles via chezmoi
#
# Post-dotfiles setup (Serena MCP, etc.) → scripts/post-setup.sh
#
# Usage: ./scripts/bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---- 1. Homebrew -----------------------------------------------------------
command -v brew &>/dev/null \
  || die "Homebrew not found. Install: https://brew.sh"

# ---- 2. chezmoi (bootstrap dependency — install before brew bundle) --------
if ! command -v chezmoi &>/dev/null; then
  log "Installing chezmoi..."
  brew install chezmoi
fi

# ---- 3. Homebrew packages (install core profile, no cleanup) ---------------
# Cleanup is intentionally skipped here so that work/personal packages
# installed by broader profiles are not removed when bootstrap re-runs.
# Cleanup happens only when explicitly running brew-bundle.sh sync <profile>.
log "Installing packages for 'core' profile..."
brew bundle --file="${REPO_ROOT}/home/dot_Brewfile.core"

# ---- 4. Point chezmoi at this repo and apply dotfiles ----------------------
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
printf '  • Open a new terminal to load zsh config\n'
printf '  • Optional: make install-work       (add work apps)\n'
printf '  • Optional: make install-personal   (add personal apps)\n'
printf '  • Optional: make install-all        (add all apps)\n'
printf '  • Run:      make doctor             (verify setup)\n'
