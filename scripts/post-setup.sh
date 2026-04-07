#!/usr/bin/env bash
# post-setup.sh — additional setup that runs after dotfiles are applied
#
# Responsibility:
#   - Install Claude Code CLI (via https://claude.ai/install.sh)
#   - Install Codex CLI (via npm install -g @openai/codex)
#   - Register Serena MCP server into Claude Code and Codex (idempotent)
#   - Register Sequential Thinking MCP into Claude Code and Codex (idempotent)
#   - Rely on chezmoi-managed Codex skills bundled in this repository
#   - Set up brew-autoupdate (tap domt4/autoupdate + start 24h schedule)
#
# Safe to re-run: already-configured items are skipped.
# Called automatically by: make install-home
#
# Usage: ./scripts/post-setup.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"

log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }

# ---- Claude Code CLI -------------------------------------------------------
log "Claude Code CLI..."

if command -v claude &>/dev/null; then
  ok "Claude Code already installed: $(claude --version 2>/dev/null | head -1 || true)"
else
  warn "claude CLI not found — install via Brewfile (cask \"claude-code\")"
fi

# ---- Codex CLI -------------------------------------------------------------
log "Codex CLI..."

if command -v codex &>/dev/null; then
  ok "Codex already installed: $(codex --version 2>/dev/null | tail -1 || true)"
else
  if ! command -v npm &>/dev/null; then
    warn "npm not found — install the core Brew profile first."
    exit 1
  fi

  log "Installing Codex via npm..."
  npm install -g @openai/codex
  if command -v codex &>/dev/null; then
    ok "Codex installed: $(codex --version 2>/dev/null | tail -1 || true)"
  else
    warn "codex CLI still not found after install — open a new terminal and re-run."
    exit 1
  fi
fi

# ---- Aider CLI -------------------------------------------------------------
log "Aider CLI..."

if command -v aider &>/dev/null; then
  ok "Aider already installed: $(aider --version 2>/dev/null | head -1 || true)"
else
  warn "aider not found — install via Brewfile (brew \"aider\")"
fi

# ---- Serena MCP (Claude Code / Codex) -------------------------------------
if ! command -v uvx &>/dev/null; then
  log "Serena MCP registration..."
  warn "uvx not found — Serena MCP skipped (install the core Brew profile first)"
else
  bash "${REPO_ROOT}/scripts/ai-repair.sh"
fi

# ---- Sequential Thinking MCP (Claude Code) --------------------------------
log "Sequential Thinking MCP..."

CLAUDE_JSON="${HOME}/.claude.json"
SEQ_THINK_ENTRY='{"type":"stdio","command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"],"env":{}}'

case "$(ai_config_mcp_registration_state "${CLAUDE_JSON}" sequential-thinking npx)" in
  ok)
    ok "Claude Code: sequential-thinking already registered"
    ;;
  *)
    ai_config_json_upsert_mcp "${CLAUDE_JSON}" sequential-thinking "${SEQ_THINK_ENTRY}"
    ok "Claude Code: sequential-thinking registered"
    ;;
esac

# ---- Codex skills ----------------------------------------------------------
log "Codex skills..."
ok "Codex skills are managed by chezmoi under ~/.codex/skills"

# ---- brew autoupdate -------------------------------------------------------
log "brew autoupdate..."

if ! brew tap | grep -q "domt4/autoupdate"; then
  log "Tapping domt4/autoupdate..."
  brew tap domt4/autoupdate
fi

if brew autoupdate status 2>/dev/null | grep -q "Autoupdate is installed and running"; then
  ok "brew autoupdate: already running"
else
  log "Starting brew autoupdate (every 24h)..."
  brew autoupdate start 86400 --upgrade --cleanup
  ok "brew autoupdate: started (every 24h, with upgrade + cleanup)"
fi

printf '\nVerify with: make doctor\n'
printf '             codex login    (one-time auth)\n'
