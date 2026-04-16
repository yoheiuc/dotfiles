#!/usr/bin/env bash
# uninstall.sh — remove dotfiles managed by chezmoi
#
# What this script does:
#   1. Remove chezmoi-managed dotfiles from $HOME
#   2. Remove the chezmoi source symlink (~/.local/share/chezmoi)
#   3. Uninstall chezmoi itself
#   4. Optionally remove Homebrew packages installed by the core Brewfile
#
# Usage: ./scripts/uninstall.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

echo
printf '\033[1m=== dotfiles uninstall ===\033[0m\n'
printf 'This will remove chezmoi-managed dotfiles from your HOME directory.\n\n'
printf 'Press Enter to continue, or Ctrl+C to cancel: '
read -r

# ---- 1. Remove chezmoi-managed files ----------------------------------------
if command -v chezmoi &>/dev/null; then
  log "Removing chezmoi-managed dotfiles..."
  chezmoi purge --binary 2>/dev/null || chezmoi purge || true
else
  warn "chezmoi not found — skipping dotfile removal"
fi

# ---- 2. Remove chezmoi source symlink ----------------------------------------
CHEZMOI_LINK="${HOME}/.local/share/chezmoi"
if [[ -L "$CHEZMOI_LINK" ]]; then
  log "Removing chezmoi source symlink..."
  rm "$CHEZMOI_LINK"
fi

# ---- 3. Uninstall chezmoi via Homebrew ----------------------------------------
if brew list chezmoi &>/dev/null 2>&1; then
  log "Uninstalling chezmoi..."
  brew uninstall chezmoi
fi

# ---- 4. Optional: remove Homebrew packages ----------------------------------------
echo
printf 'Remove Homebrew packages installed by the core Brewfile? [y/N] '
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
  log "Removing Homebrew packages..."
  brew bundle cleanup --file="${REPO_ROOT}/home/dot_Brewfile.core" --force
else
  log "Skipping Homebrew package removal."
fi

echo
printf '\033[1;32mUninstall complete.\033[0m\n'
printf 'The dotfiles repo itself (%s) was not removed.\n' "$REPO_ROOT"
