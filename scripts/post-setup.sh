#!/usr/bin/env bash
# post-setup.sh — additional setup that runs after dotfiles are applied
#
# Responsibility:
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

# ---- Serena MCP (Claude Code) ---------------------------------------------
log "Serena MCP registration..."

if ! command -v claude &>/dev/null; then
  warn "claude CLI not found — skipping Serena registration."
  warn "Install Claude (cask \"claude\") then re-run this script."
  exit 0
fi

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
