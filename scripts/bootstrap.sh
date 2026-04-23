#!/usr/bin/env bash
# bootstrap.sh — minimal machine provisioning
#
# Responsibility (nothing more):
#   1. Verify Homebrew is present
#   2. Install chezmoi if missing
#   3. Apply Python 3.13 SSL compat (corporate proxy workaround)
#   4. Install Brew packages (no cleanup)
#   5. Apply dotfiles via chezmoi
#
# Called automatically by: make install
#
# Usage: ./scripts/bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

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

# Verify Swift actually executes — a present-but-broken CLT (partial install,
# macOS upgrade leftovers) will fail opaque downstream (brew postflight, chezmoi
# run_once scripts). doctor.sh has the same check.
if ! swift -e "print(0)" &>/dev/null; then
  die "CLT is installed at $(xcode-select -p) but Swift execution failed. Reset with: sudo rm -rf $(xcode-select -p) && xcode-select --install"
fi

# ---- 1. Homebrew -----------------------------------------------------------
command -v brew &>/dev/null \
  || die "Homebrew not found. Install: https://brew.sh"

# ---- 2. chezmoi (bootstrap dependency — install before brew bundle) --------
if ! command -v chezmoi &>/dev/null; then
  log "Installing chezmoi..."
  brew install chezmoi
fi

# ---- 3. Python 3.13 SSL compat (corporate proxy workaround) ---------------
# gcloud-cli and other Python 3.13+ tools fail behind CASB/proxies
# (Netskope, Zscaler, etc.) due to VERIFY_X509_STRICT rejecting MITM certs.
# Deploy sitecustomize.py before brew bundle so cask postflight works.
_ssl_compat_src="${REPO_ROOT}/home/dot_local/lib/python-ssl-compat/sitecustomize.py"
_ssl_compat_dst="${HOME}/.local/lib/python-ssl-compat"
if [[ -f "${_ssl_compat_src}" ]]; then
  mkdir -p "${_ssl_compat_dst}"
  cp "${_ssl_compat_src}" "${_ssl_compat_dst}/sitecustomize.py"
  export PYTHONPATH="${_ssl_compat_dst}${PYTHONPATH:+:${PYTHONPATH}}"
  log "Python SSL compat: VERIFY_X509_STRICT disabled for corporate proxy"
fi
unset _ssl_compat_src _ssl_compat_dst

# ---- 4. Homebrew packages (install, no cleanup) ----------------------------
log "Installing packages from Brewfile..."
brew bundle --file="${REPO_ROOT}/home/dot_Brewfile"

# ---- 5. Point chezmoi at this repo and apply dotfiles ----------------------
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
printf '  • Run: make doctor             (verify setup)\n'
