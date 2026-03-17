#!/usr/bin/env bash
# bootstrap.sh — provision a new machine from this dotfiles repo
# Usage: bash scripts/bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---- 0. Pre-flight --------------------------------------------------------
command -v brew  &>/dev/null || die "Homebrew not found. Install from https://brew.sh"
command -v chezmoi &>/dev/null || { log "Installing chezmoi via brew..."; brew install chezmoi; }

# ---- 1. Homebrew packages -------------------------------------------------
log "Installing Homebrew packages (brew bundle)..."
brew bundle --file="${REPO_ROOT}/Brewfile"

# ---- 2. Apply dotfiles ----------------------------------------------------
log "Applying dotfiles via chezmoi..."
chezmoi apply --source="${REPO_ROOT}/home"

# ---- 3. Serena MCP integration (Claude Code) ------------------------------
if command -v claude &>/dev/null; then
  log "Registering Serena MCP server (user scope, project-from-cwd)..."
  claude mcp add --scope user serena -- \
    uvx --from git+https://github.com/oraios/serena \
    serena start-mcp-server --context=claude-code --project-from-cwd
  log "Serena registered. Verify with: claude mcp list"
else
  printf '\033[1;33mWARN: claude CLI not found — skipping Serena MCP registration.\033[0m\n'
  printf '      Re-run this script after installing Claude (cask "claude").\n'
fi

log "Bootstrap complete!"
printf '\n  Next steps:\n'
printf '  1. Open a new terminal session to load your zsh config.\n'
printf '  2. Run scripts/doctor.sh to verify the setup.\n'
printf '  3. In Claude Code: /plugin install superpowers\n'
