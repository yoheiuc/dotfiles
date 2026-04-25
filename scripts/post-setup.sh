#!/usr/bin/env bash
# post-setup.sh — additional setup that runs after dotfiles are applied
#
# Responsibility:
#   - Install/update Claude Code CLI via native installer and keep it on latest
#   - Install clasp (via npm install -g @google/clasp)
#   - Register Sequential Thinking MCP into Claude Code (idempotent)
#   - Install Google Workspace CLI (gws) skills under ~/.claude/skills (idempotent)
#   - Install find-skills (vercel-labs/skills) so Claude can discover skills from natural-language queries (idempotent)
#   - Keep brew-autoupdate disabled (manual brew update/upgrade policy)
#
# Safe to re-run: already-configured items are skipped.
# Called automatically by: make install / make sync
#
# Usage: ./scripts/post-setup.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/ui.sh"
source "${REPO_ROOT}/scripts/lib/ai-config.sh"
source "${REPO_ROOT}/scripts/lib/brew-autoupdate.sh"
source "${REPO_ROOT}/scripts/lib/claude-plugins.sh"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }

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
  # Official Anthropic installer: https://claude.ai/install.sh (vendor-signed, pinned to latest channel).
  # curl | bash is the documented install path; see https://docs.anthropic.com/claude-code
  curl -fsSL https://claude.ai/install.sh | bash
  hash -r
  ok "Claude Code installed: $(claude --version 2>/dev/null | head -1 || true)"
fi
ok "Claude Code auto-update channel: latest"
unset CLAUDE_SETTINGS_JSON claude_path

# ---- Claude Code marketplace + LSP plugins ---------------------------------
# Per-language LSP plugins are distributed via anthropics/claude-plugins-official.
# Register the marketplace once, then install each plugin idempotently. The list
# of plugins lives in scripts/lib/claude-plugins.sh so doctor.sh verifies the
# same set.
log "Claude Code plugins (claude-plugins-official)..."

if command -v claude &>/dev/null; then
  if jq -e --arg name "${CLAUDE_PLUGIN_MARKETPLACE_NAME}" \
      'has($name)' "${HOME}/.claude/plugins/known_marketplaces.json" >/dev/null 2>&1; then
    ok "marketplace ${CLAUDE_PLUGIN_MARKETPLACE_NAME}: already registered"
  else
    log "Adding marketplace ${CLAUDE_PLUGIN_MARKETPLACE_SOURCE}..."
    if claude plugin marketplace add "${CLAUDE_PLUGIN_MARKETPLACE_SOURCE}"; then
      ok "marketplace ${CLAUDE_PLUGIN_MARKETPLACE_NAME}: registered"
    else
      warn "marketplace add failed — run manually: claude plugin marketplace add ${CLAUDE_PLUGIN_MARKETPLACE_SOURCE}"
    fi
  fi

  for _plugin in "${CLAUDE_LSP_PLUGINS[@]}" "${CLAUDE_GENERAL_PLUGINS[@]}"; do
    if claude_plugin_is_installed "${_plugin}"; then
      ok "plugin ${_plugin}: already installed"
    else
      log "Installing plugin ${_plugin}@${CLAUDE_PLUGIN_MARKETPLACE_NAME}..."
      if claude plugin install "${_plugin}@${CLAUDE_PLUGIN_MARKETPLACE_NAME}"; then
        ok "plugin ${_plugin}: installed"
      else
        warn "plugin ${_plugin} install failed — run manually: claude plugin install ${_plugin}@${CLAUDE_PLUGIN_MARKETPLACE_NAME}"
      fi
    fi
  done
  unset _plugin
else
  warn "claude not found — skipping plugin install"
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
  ok "playwright-cli: skills installed for Claude Code"
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

# ---- ai-repair (Claude Code local drift) ----------------------------------
# ai-repair は Claude Code 設定ベースラインの補正と legacy MCP 掃除を担当。
# post-setup の一環として必ず走らせる（冪等）。
bash "${REPO_ROOT}/scripts/ai-repair.sh"

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

# ---- Google Workspace CLI skills (Claude Code) ----------------------------
log "Google Workspace CLI skills..."

if ! command -v gws &>/dev/null; then
  warn "gws not found — run \`make install\` first (googleworkspace-cli)"
elif ! command -v npx &>/dev/null; then
  warn "npx not found — gws skills skipped (run \`make install\` first)"
else
  _dir="${HOME}/.claude/skills"
  mkdir -p "${_dir}"
  if compgen -G "${_dir}/gws-*/SKILL.md" >/dev/null; then
    ok "gws skills already present under ${_dir/#${HOME}/\~}"
  else
    log "Installing gws skills for claude-code into ${_dir/#${HOME}/\~} ..."
    if npx -y skills add https://github.com/googleworkspace/cli -a claude-code -g -y; then
      ok "gws skills installed"
    else
      warn "npx skills add failed — re-run or install manually"
    fi
  fi
  unset _dir
fi

# ---- find-skills (vercel-labs/skills) -------------------------------------
# find-skills lets Claude Code search and install further skills from
# natural-language queries (English keywords work best). `npx skills add
# -a claude-code` places the bundle under ~/.claude/skills/find-skills AND
# ~/.agents/skills/find-skills, so the agent can self-discover skills without
# manual /plugin install steps.
log "find-skills skill..."

if ! command -v npx &>/dev/null; then
  warn "npx not found — find-skills skipped (run \`make install\` first)"
else
  _dir="${HOME}/.claude/skills"
  mkdir -p "${_dir}"
  if [[ -f "${_dir}/find-skills/SKILL.md" ]]; then
    ok "find-skills already present under ${_dir/#${HOME}/\~}"
  else
    log "Installing find-skills for claude-code into ${_dir/#${HOME}/\~} ..."
    if npx -y skills add https://github.com/vercel-labs/skills -a claude-code -g -y --skill find-skills; then
      ok "find-skills installed"
    else
      warn "npx skills add failed — re-run or install manually"
    fi
  fi
  unset _dir
fi

# ---- Notion CLI (ntn) ------------------------------------------------------
log "Notion CLI (ntn)..."

if command -v ntn &>/dev/null; then
  ok "ntn already installed: $(ntn --version 2>/dev/null | head -1 || true)"
else
  log "Installing Notion CLI via official installer..."
  # Official Notion installer: https://ntn.dev (distributed by Notion Labs, documented install path).
  # curl | bash is accepted here because the install target is $HOME/.ntn (non-privileged, user-local).
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
  _dir="${HOME}/.claude/skills"
  mkdir -p "${_dir}"
  if [[ -f "${_dir}/notion-cli/SKILL.md" ]]; then
    ok "notion-cli skill already present under ${_dir/#${HOME}/\~}"
  else
    log "Installing notion-cli skill for claude-code into ${_dir/#${HOME}/\~} ..."
    if npx -y skills add https://github.com/makenotion/skills -a claude-code -g -y --skill notion-cli; then
      ok "notion-cli skill installed"
    else
      warn "npx skills add failed — re-run or install manually"
    fi
  fi
  unset _dir
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
  printf '    → launch Claude Code from that shell\n'
  printf '    pwdetach   (close CDP session; Chrome stays open)\n'
  printf '  rationale + risks: see README.md "pwattach のセキュリティ"\n'
fi
