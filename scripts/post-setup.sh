#!/usr/bin/env bash
# post-setup.sh — additional setup that runs after dotfiles are applied
#
# Responsibility:
#   - Install Claude Code CLI (via https://claude.ai/install.sh)
#   - Register Serena MCP server into Claude Code (idempotent)
#   - Any future "first-time only" configuration that is not a dotfile
#
# Safe to re-run: already-configured items are skipped.
#
# Usage: bash scripts/post-setup.sh
set -euo pipefail

log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }

# ---- Claude Code CLI -------------------------------------------------------
log "Claude Code CLI..."

if command -v claude &>/dev/null; then
  ok "Claude Code already installed: $(claude --version 2>/dev/null || true)"
else
  log "Installing Claude Code via install script..."
  curl -fsSL https://claude.ai/install.sh | bash
  # Reload PATH so subsequent steps can find the claude binary
  export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
  if command -v claude &>/dev/null; then
    ok "Claude Code installed: $(claude --version 2>/dev/null || true)"
  else
    warn "claude CLI still not found after install — open a new terminal and re-run."
    exit 1
  fi
fi

# ---- Serena MCP (Claude Code) ---------------------------------------------
log "Serena MCP registration..."

if ! command -v uvx &>/dev/null; then
  warn "uvx not found — install uv via Brewfile first."
  exit 0
fi

# Idempotency: skip if already registered
if claude mcp list 2>/dev/null | grep -q '^serena'; then
  ok "Serena already registered — nothing to do."
else
  log "Registering Serena (user scope)..."
  claude mcp add --scope user serena -- \
    uvx --from git+https://github.com/oraios/serena \
    serena start-mcp-server --context=claude-code --project-from-cwd
  ok "Serena registered."
fi

printf '\nVerify with: claude mcp list\n'
