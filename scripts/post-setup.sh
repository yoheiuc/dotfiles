#!/usr/bin/env bash
# post-setup.sh — additional setup that runs after dotfiles are applied
#
# Responsibility:
#   - Install/update Claude Code CLI via native installer and keep it on latest
#   - Install Codex CLI (via npm install -g @openai/codex)
#   - Register Serena MCP server into Claude Code and Codex (idempotent)
#   - Register Sequential Thinking MCP into Claude Code and Codex (idempotent)
#   - Install Google Workspace CLI (gws) skills under ~/.claude/skills and ~/.codex/skills (idempotent)
#   - Rely on chezmoi-managed Codex skills bundled in this repository
#   - Keep brew-autoupdate disabled (manual brew update/upgrade policy)
#
# Safe to re-run: already-configured items are skipped.
# Called automatically by: make install-home
#
# Usage: ./scripts/post-setup.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"
source "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh"

log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }

# ---- Claude Code CLI -------------------------------------------------------
log "Claude Code CLI..."

CLAUDE_SETTINGS_JSON="${HOME}/.claude/settings.json"
mkdir -p "$(dirname "${CLAUDE_SETTINGS_JSON}")"
ai_config_json_upsert_key "${CLAUDE_SETTINGS_JSON}" autoUpdatesChannel '"latest"'

if command -v claude &>/dev/null; then
  claude_path="$(command -v claude)"
  if [[ "${claude_path}" == "/opt/homebrew/bin/claude" ]]; then
    log "Migrating Claude Code from Homebrew to native latest..."
    claude install latest
    hash -r
  fi
  ok "Claude Code available: $(claude --version 2>/dev/null | head -1 || true)"
else
  log "Installing Claude Code native latest..."
  curl -fsSL https://claude.ai/install.sh | bash
  hash -r
  ok "Claude Code installed: $(claude --version 2>/dev/null | head -1 || true)"
fi
ok "Claude Code auto-update channel: latest"
unset CLAUDE_SETTINGS_JSON claude_path

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

# ---- Google Workspace CLI skills (Claude Code / Codex) --------------------
log "Google Workspace CLI skills..."

if ! command -v gws &>/dev/null; then
  warn "gws not found — install the core Brew profile first (googleworkspace-cli)"
elif ! command -v npx &>/dev/null; then
  warn "npx not found — gws skills skipped (install node via core Brew profile)"
else
  for target in claude-code:"${HOME}/.claude/skills" codex:"${HOME}/.codex/skills"; do
    agent="${target%%:*}"
    dir="${target#*:}"
    mkdir -p "${dir}"
    if compgen -G "${dir}/gws-*/SKILL.md" >/dev/null; then
      ok "gws skills already present under ${dir/#${HOME}/\~}"
    else
      log "Installing gws skills for ${agent} into ${dir/#${HOME}/\~} ..."
      if npx -y skills add https://github.com/googleworkspace/cli -a "${agent}" -g -y; then
        ok "gws skills installed (${agent})"
      else
        warn "npx skills add failed for ${agent} — re-run or install manually"
      fi
    fi
  done
  unset target agent dir
fi

# ---- brew autoupdate -------------------------------------------------------
log "brew autoupdate..."
launchctl bootout "gui/$(id -u)/$(brew_autoupdate_label)" >/dev/null 2>&1 || true
brew autoupdate delete >/dev/null 2>&1 || true
rm -f "$(brew_autoupdate_plist_path)" "$(brew_autoupdate_runner_path)"
ok "brew autoupdate: disabled by dotfiles policy"

printf '\nVerify with: make doctor\n'
printf '             codex login    (one-time auth)\n'
