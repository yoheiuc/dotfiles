#!/usr/bin/env bash
# post-setup.sh — additional setup that runs after dotfiles are applied
#
# Responsibility:
#   - Install/update Claude Code CLI via native installer and keep it on latest
#   - Install Codex CLI (via npm install -g @openai/codex)
#   - Install clasp (via npm install -g @google/clasp)
#   - Register Serena MCP server into Claude Code and Codex (idempotent)
#   - Register Sequential Thinking MCP into Claude Code and Codex (idempotent)
#   - Install Google Workspace CLI (gws) skills under ~/.claude/skills and ~/.codex/skills (idempotent)
#   - Install find-skills (vercel-labs/skills) so Claude / Codex can discover skills from natural-language queries (idempotent)
#   - Rely on chezmoi-managed Codex skills bundled in this repository
#   - Keep brew-autoupdate disabled (manual brew update/upgrade policy)
#
# Safe to re-run: already-configured items are skipped.
# Called automatically by: make install / make sync
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
    warn "npm not found — run `make install` first."
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

# ---- clasp (Google Apps Script CLI) ----------------------------------------
log "clasp..."

if command -v clasp &>/dev/null; then
  ok "clasp already installed: $(clasp --version 2>/dev/null | head -1 || true)"
else
  if ! command -v npm &>/dev/null; then
    warn "npm not found — run `make install` first."
    exit 1
  fi

  log "Installing clasp via npm..."
  npm install -g @google/clasp
  if command -v clasp &>/dev/null; then
    ok "clasp installed: $(clasp --version 2>/dev/null | head -1 || true)"
  else
    warn "clasp CLI still not found after install — open a new terminal and re-run."
    exit 1
  fi
fi

# ---- Playwright CLI --------------------------------------------------------
log "Playwright CLI..."

if command -v playwright-cli &>/dev/null; then
  ok "playwright-cli already installed: $(playwright-cli --version 2>/dev/null | head -1 || true)"
else
  if ! command -v npm &>/dev/null; then
    warn "npm not found — run `make install` first."
    exit 1
  fi

  log "Installing @playwright/cli via npm..."
  npm install -g @playwright/cli@latest
  hash -r
  if command -v playwright-cli &>/dev/null; then
    ok "playwright-cli installed: $(playwright-cli --version 2>/dev/null | head -1 || true)"
  else
    warn "playwright-cli still not found after install — open a new terminal and re-run."
    exit 1
  fi
fi

# Install Chromium browser (idempotent — CLI detects existing binaries).
# Don't silence output: Chromium download can take minutes on slow networks and
# the user should see progress.
if playwright-cli install-browser; then
  ok "playwright-cli: Chromium ready"
else
  warn "playwright-cli install-browser failed — run manually: playwright-cli install-browser"
fi

# Install skill files into ~/.claude/skills/playwright-cli.
# `playwright-cli install --skills` is CWD-relative and writes to
# `./.claude/skills/playwright-cli`, so force the CWD to $HOME — otherwise the
# skill dir lands wherever post-setup happens to be invoked from
# (e.g. the dotfiles checkout).
if (cd "${HOME}" && playwright-cli install --skills); then
  ok "playwright-cli: skills installed for Claude Code and Codex"
else
  warn "playwright-cli install --skills failed — run manually from \$HOME: (cd \"\${HOME}\" && playwright-cli install --skills)"
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
  warn "uvx not found — Serena MCP skipped (run \`make install\` first)"
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
  warn "gws not found — run \`make install\` first (googleworkspace-cli)"
elif ! command -v npx &>/dev/null; then
  warn "npx not found — gws skills skipped (run \`make install\` first)"
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

# ---- find-skills (vercel-labs/skills) -------------------------------------
# find-skills lets Claude Code / Codex search and install further skills from
# natural-language queries (English keywords work best). Installing it via
# `npx skills add` places the skill bundle under ~/.claude/skills/find-skills
# and ~/.codex/skills/find-skills, so both agents can self-discover skills
# without manual /plugin install steps.
log "find-skills skill..."

if ! command -v npx &>/dev/null; then
  warn "npx not found — find-skills skipped (run \`make install\` first)"
else
  # npx skills layout:
  #   -a claude-code → copies to ~/.claude/skills/ AND ~/.agents/skills/
  #   -a codex       → copies only to ~/.agents/skills/ (Codex reads the
  #                    unified location; ~/.codex/skills/ stays reserved
  #                    for chezmoi-managed skills)
  for target in claude-code:"${HOME}/.claude/skills" codex:"${HOME}/.agents/skills"; do
    agent="${target%%:*}"
    dir="${target#*:}"
    mkdir -p "${dir}"
    if [[ -f "${dir}/find-skills/SKILL.md" ]]; then
      ok "find-skills already present under ${dir/#${HOME}/\~}"
    else
      log "Installing find-skills for ${agent} into ${dir/#${HOME}/\~} ..."
      if npx -y skills add https://github.com/vercel-labs/skills -a "${agent}" -g -y --skill find-skills; then
        ok "find-skills installed (${agent})"
      else
        warn "npx skills add failed for ${agent} — re-run or install manually"
      fi
    fi
  done
  unset target agent dir
fi

# ---- Notion CLI (ntn) ------------------------------------------------------
log "Notion CLI (ntn)..."

if command -v ntn &>/dev/null; then
  ok "ntn already installed: $(ntn --version 2>/dev/null | head -1 || true)"
else
  log "Installing Notion CLI via official installer..."
  # Official installer from Notion: https://ntn.dev
  if curl -fsSL https://ntn.dev | bash; then
    hash -r
    if command -v ntn &>/dev/null; then
      ok "ntn installed: $(ntn --version 2>/dev/null | head -1 || true)"
    else
      warn "ntn still not found after install — open a new terminal and re-run, or add ntn's install dir to PATH"
    fi
  else
    warn "ntn install failed — run manually: curl -fsSL https://ntn.dev | bash"
  fi
fi

# ---- Notion CLI skills (makenotion/skills) --------------------------------
log "Notion CLI skills..."

if ! command -v npx &>/dev/null; then
  warn "npx not found — notion-cli skills skipped (run \`make install\` first)"
else
  for target in claude-code:"${HOME}/.claude/skills" codex:"${HOME}/.codex/skills"; do
    agent="${target%%:*}"
    dir="${target#*:}"
    mkdir -p "${dir}"
    if [[ -f "${dir}/notion-cli/SKILL.md" ]]; then
      ok "notion-cli skill already present under ${dir/#${HOME}/\~}"
    else
      log "Installing notion-cli skill for ${agent} into ${dir/#${HOME}/\~} ..."
      if npx -y skills add https://github.com/makenotion/skills -a "${agent}" -g -y --skill notion-cli; then
        ok "notion-cli skill installed (${agent})"
      else
        warn "npx skills add failed for ${agent} — re-run or install manually"
      fi
    fi
  done
  unset target agent dir
fi

# ---- Homebrew share perms (zsh compinit) ----------------------------------
# Homebrew installs /opt/homebrew/share as group-writable (drwxrwxr-x), which
# zsh's compinit flags as "insecure" and prompts on every shell start. Drop
# group-write to silence the prompt. chmod is idempotent.
log "Homebrew share perms (zsh compinit)..."

_brew_share="${HOMEBREW_PREFIX:-/opt/homebrew}/share"
if [[ -d "${_brew_share}" ]]; then
  _before="$(stat -f '%Lp' "${_brew_share}" 2>/dev/null || echo '?')"
  chmod g-w "${_brew_share}"
  _after="$(stat -f '%Lp' "${_brew_share}" 2>/dev/null || echo '?')"
  if [[ "${_before}" != "${_after}" ]]; then
    ok "${_brew_share}: perms ${_before} -> ${_after} (dropped group-write)"
  else
    ok "${_brew_share}: perms ${_after}, already clean"
  fi
  unset _before _after
else
  warn "${_brew_share} not found — skipping compinit perms fix"
fi
unset _brew_share

# ---- brew autoupdate -------------------------------------------------------
log "brew autoupdate..."
launchctl bootout "gui/$(id -u)/$(brew_autoupdate_label)" >/dev/null 2>&1 || true
brew autoupdate delete >/dev/null 2>&1 || true
rm -f "$(brew_autoupdate_plist_path)" "$(brew_autoupdate_runner_path)"
ok "brew autoupdate: disabled by dotfiles policy"

printf '\nVerify with: make doctor\n'
printf '             codex login    (one-time auth)\n'
printf '             ntn login      (one-time Notion OAuth)\n'

if command -v playwright-cli >/dev/null 2>&1; then
  printf '\n\033[1mTo let agents drive your Chrome (Playwright CLI attach):\033[0m\n'
  printf '  policy: pwattach is restricted to an AI-DEDICATED Chrome profile.\n'
  printf '  one-time setup (per machine):\n'
  printf '    1. Chrome profile picker → "Add" → create an "AI" profile\n'
  printf '    2. in that AI profile only (Chrome 144+):\n'
  printf '         open chrome://inspect/#remote-debugging → toggle ON\n'
  printf '         "Allow remote debugging for this browser instance"\n'
  printf '       (leave your main profile'\''s toggle OFF)\n'
  printf '    3. sign in to the AI profile with read-only / non-privileged\n'
  printf '       accounts only — not your everyday logins\n'
  printf '    4. add to ~/.zshenv:  export PLAYWRIGHT_AI_CHROME_READY=1\n'
  printf '    5. restart shell\n'
  printf '  daily use: focus the AI profile'\''s Chrome window, then run\n'
  printf '    pwattach   (exports PLAYWRIGHT_CLI_SESSION=chrome)\n'
  printf '    → launch Claude Code / Codex from that shell\n'
  printf '    pwdetach   (close CDP session; Chrome stays open)\n'
  printf '  rationale + risks: see README.md "pwattach のセキュリティ"\n'
fi
