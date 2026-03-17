#!/usr/bin/env bash
# bootstrap.sh — minimal machine provisioning
#
# Responsibility (nothing more):
#   1. Verify Homebrew is present
#   2. Install chezmoi if missing
#   3. Install Homebrew packages (Brewfile)
#   4. Apply dotfiles via chezmoi
#
# Post-dotfiles setup (Serena MCP, etc.) → scripts/post-setup.sh
#
# Usage: bash scripts/bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="${REPO_ROOT}/home/dot_Brewfile"

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

# ---- 3. Homebrew packages --------------------------------------------------
log "Installing packages (brew bundle)..."
brew bundle --file="${BREWFILE}"

# ---- 4. Apply dotfiles -----------------------------------------------------
log "Applying dotfiles (chezmoi apply)..."
chezmoi apply --source="${REPO_ROOT}/home"

log "Bootstrap complete."
printf '\nNext:\n'
printf '  • Open a new terminal to load zsh config\n'
printf '  • Run:  bash scripts/post-setup.sh   (Serena MCP, etc.)\n'
printf '  • Run:  bash scripts/doctor.sh        (verify setup)\n'
