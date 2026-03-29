#!/usr/bin/env bash
# post-setup.sh — additional setup that runs after dotfiles are applied
#
# Responsibility:
#   - Install Claude Code CLI (via https://claude.ai/install.sh)
#   - Install Codex CLI (via npm install -g @openai/codex)
#   - Register Serena MCP server into Claude Code and Codex (idempotent)
#   - Register Sequential Thinking MCP into Claude Code and Codex (idempotent)
#   - Download curated Codex skills from openai/skills (plan, figma)
#   - Set up brew-autoupdate (tap domt4/autoupdate + start 24h schedule)
#
# Safe to re-run: already-configured items are skipped.
# Called automatically by: make install-work / install-personal / install-all
#
# Usage: ./scripts/post-setup.sh
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

# ---- Serena MCP (Claude Code / Codex) -------------------------------------
log "Serena MCP registration..."

if ! command -v uvx &>/dev/null; then
  warn "uvx not found — Serena MCP skipped (install the core Brew profile first)"
else

if claude mcp get serena >/dev/null 2>&1; then
  if claude mcp get serena 2>/dev/null | grep -Fq -- '--open-web-dashboard False'; then
    ok "Claude Code: Serena already registered"
  else
    log "Claude Code: updating Serena to disable browser auto-open..."
    claude mcp remove serena -s user
    claude mcp add --scope user serena -- \
      uvx \
      --from git+https://github.com/oraios/serena \
      serena start-mcp-server --context=claude-code --project-from-cwd \
      --open-web-dashboard False
  fi
else
  log "Registering Serena for Claude Code (user scope)..."
  claude mcp add --scope user serena -- \
    uvx \
    --from git+https://github.com/oraios/serena \
    serena start-mcp-server --context=claude-code --project-from-cwd \
    --open-web-dashboard False
fi
ok "Claude Code: Serena registered"

if command -v codex &>/dev/null; then
  if codex mcp get serena --json >/dev/null 2>&1; then
    if codex mcp get serena --json 2>/dev/null | grep -Fq -- '"--open-web-dashboard"'; then
      ok "Codex: Serena already registered"
    else
      log "Codex: updating Serena to disable browser auto-open..."
      codex mcp remove serena
      codex mcp add serena -- \
        uvx \
        --from git+https://github.com/oraios/serena \
        serena start-mcp-server --context=codex --project-from-cwd \
        --open-web-dashboard False
    fi
  else
    log "Registering Serena for Codex..."
    codex mcp add serena -- \
      uvx \
      --from git+https://github.com/oraios/serena \
      serena start-mcp-server --context=codex --project-from-cwd \
      --open-web-dashboard False
  fi
  ok "Codex: Serena registered"
else
  warn "codex not found — Serena for Codex skipped"
fi

fi  # end uvx check

# ---- Sequential Thinking MCP (Claude Code / Codex) ------------------------
log "Sequential Thinking MCP..."

if command -v claude &>/dev/null; then
  if claude mcp get sequential-thinking >/dev/null 2>&1; then
    ok "Claude Code: sequential-thinking already registered"
  else
    log "Registering sequential-thinking for Claude Code..."
    claude mcp add --scope user sequential-thinking -- \
      npx -y @modelcontextprotocol/server-sequential-thinking
    ok "Claude Code: sequential-thinking registered"
  fi
fi

if command -v codex &>/dev/null; then
  if codex mcp get sequential-thinking --json >/dev/null 2>&1; then
    ok "Codex: sequential-thinking already registered"
  else
    log "Registering sequential-thinking for Codex..."
    codex mcp add sequential-thinking -- \
      npx -y @modelcontextprotocol/server-sequential-thinking
    ok "Codex: sequential-thinking registered"
  fi
fi

# ---- Codex skills from openai/skills ---------------------------------------
log "Codex skills (openai/skills)..."

_skills_dir="${HOME}/.codex/skills"
_skills_tmp="$(mktemp -d)"

if git clone --depth=1 --filter=blob:none --sparse \
    https://github.com/openai/skills.git "${_skills_tmp}" 2>/dev/null; then
  git -C "${_skills_tmp}" sparse-checkout set plan figma
  for _skill in plan figma; do
    if [[ -d "${_skills_dir}/${_skill}" ]]; then
      ok "Codex skill '${_skill}': already present"
    else
      cp -r "${_skills_tmp}/${_skill}" "${_skills_dir}/"
      ok "Codex skill '${_skill}': installed"
    fi
  done
else
  warn "openai/skills のクローンに失敗しました — スキルのインストールをスキップします"
fi
rm -rf "${_skills_tmp}"

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
